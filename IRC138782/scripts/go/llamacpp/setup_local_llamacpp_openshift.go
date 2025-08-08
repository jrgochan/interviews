// --------------------------------------------------------------
// setup_local_llamacpp_openshift.go
//
// This program performs an end-to-end setup of a llama.cpp chat
// service on local OpenShift (CRC):
//
// (1) Connect to the cluster (via your kubeconfig).
// (2) Ensure a target Namespace exists.
// (3) Create/Update a ConfigMap containing model settings.
// (4) Create/Update a PersistentVolumeClaim (PVC) to persist
//     /models across pod restarts (so we don't re-download).
// (5) Create/Update a Deployment that has:
//     - An initContainer ("fetch-model") that downloads the GGUF
//       model into /models with curl (robust retries).
//     - The main llama.cpp server container using the official
//       image. We DO NOT override command; we configure it via
//       LLAMA_ARG_* environment variables (the image reads these).
//     - A pod-level FSGroup so the mounted volume is writable by
//       OpenShift's random non-root UID under the restricted SCC.
// (6) Create/Update a ClusterIP Service.
// (7) Create/Update an Ingress (OpenShift router exposes it).
// (8) Wait for readiness and then send a real OpenAI-style
//     /v1/chat/completions request to verify it works.
//
// --------------------------------------------------------------
// HOW TO RUN (example):
//
//   # In an empty folder:
//   go mod init llama-chat
//   go get k8s.io/client-go@v0.29.0
//   go get k8s.io/api@v0.29.0
//   go get k8s.io/apimachinery@v0.29.0
//   go mod tidy
//
//   # Use a SMALL GGUF first time (e.g., TinyLlama Q4_K_M)
//   go run setup_local_llamacpp_openshift.go \
//     --kubeconfig=$HOME/.kube/config \
//     --namespace=testing \
//     --name=llama-chat \
//     --model-name=tinyllama-1.1b \
//     --model-url="https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf?download=true" \
//     --system="You are a helpful LANL HPC assistant." \
//     --ctx=2048 \
//     --threads=4
//
// After success, the API should be at:
//   http://<name>.<namespace>.apps-crc.testing/v1/chat/completions
//
// Example curl:
//   curl -s -X POST "http://llama-chat.testing.apps-crc.testing/v1/chat/completions" \
//     -H "Content-Type: application/json" \
//     -d '{"model":"tinyllama-1.1b","messages":[{"role":"system","content":"You are a helpful LANL HPC assistant."},{"role":"user","content":"Say hello in one short sentence."}]}' | jq .
//
// --------------------------------------------------------------

package main

// Standard library imports. We explain briefly what each is used for.
import (
	"context"   // Propagates timeouts/cancellation through API calls
	"crypto/tls" // Allows skipping TLS verification for local dev (CRC)
	"encoding/json" // JSON encode/decode for request/response bodies
	"flag"          // Command-line flags (e.g., --namespace=testing)
	"fmt"           // Printing/logging
	"io"            // Reading HTTP response bodies
	"net/http"      // Sending the verification POST request
	"os"            // OS utilities (stderr, exit codes, environment)
	"path/filepath" // Build default kubeconfig path
	"strings"       // Small helpers for strings
	"time"          // Durations, timeouts
)

// Kubernetes API types we will create/apply.
import (
	appsv1 "k8s.io/api/apps/v1" // Deployment API
	corev1 "k8s.io/api/core/v1" // Core types: Namespace, Service, ConfigMap, PVC, Pod
	netv1 "k8s.io/api/networking/v1" // Ingress API
)

// Kubernetes helper packages.
import (
	kerrors "k8s.io/apimachinery/pkg/api/errors" // For IsNotFound checks
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1" // Object metadata types
	"k8s.io/apimachinery/pkg/api/resource"        // For PVC sizes like "5Gi"
	"k8s.io/apimachinery/pkg/util/intstr"         // IntOrString (ports in probes/services)
	waitutil "k8s.io/apimachinery/pkg/util/wait"  // Poll/wait utilities
)

// Kubernetes client-go: the typed client and kubeconfig loader.
import (
	"k8s.io/client-go/kubernetes"           // The "clientset" for Kubernetes
	"k8s.io/client-go/tools/clientcmd"      // Loads kubeconfig like kubectl does
)

// ---------- Small helper functions ----------

// int32p returns a pointer to an int32 literal. Go doesn't allow &int32(1) directly.
func int32p(i int32) *int32 { return &i }

// boolp returns a pointer to a bool literal.
func boolp(b bool) *bool { return &b }

// cfgKey is a convenience to pull an environment variable from a ConfigMap key.
// It builds the { ValueFrom: { ConfigMapKeyRef: ... } } boilerplate for you.
func cfgKey(cmName, key string) *corev1.EnvVarSource {
	return &corev1.EnvVarSource{
		ConfigMapKeyRef: &corev1.ConfigMapKeySelector{
			LocalObjectReference: corev1.LocalObjectReference{Name: cmName},
			Key:                  key,
		},
	}
}

// chatReq/Resp define the JSON schema we POST to the OpenAI-compatible endpoint
// and the minimal structure we expect back. llama.cpp may add fields; we only
// parse what we need for a simple verification message.
type chatReq struct {
	Model    string        `json:"model"`
	Messages []chatMessage `json:"messages"`
	Stream   bool          `json:"stream"`
}
type chatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}
type chatResp struct {
	Choices []struct {
		Message struct {
			Role    string `json:"role"`
			Content string `json:"content"`
		} `json:"message"`
	} `json:"choices"`
}

// ---------- main entrypoint ----------
func main() {
	// -------------------------------
	// Command-line flags (CLI options)
	// -------------------------------
	// In Go, flag.String returns a pointer to a string. After flag.Parse(),
	// *namespace dereferences to the actual value.
	ns := flag.String("namespace", "testing", "Namespace to deploy into (created if missing)")
	name := flag.String("name", "llama-chat", "Base name for all objects (Deployment/Service/Ingress)")
	host := flag.String("host", "", "Ingress host (default: <name>.<ns>.apps-crc.testing)")
	kubeconfig := flag.String("kubeconfig", filepath.Join(os.Getenv("HOME"), ".kube", "config"), "Path to kubeconfig")

	// Model configuration.
	modelURL := flag.String("model-url", "", "Direct URL to a GGUF model file (required)")
	modelName := flag.String("model-name", "local-gguf", "Logical model name used by clients")
	ctxLen := flag.Int("ctx", 2048, "Context window tokens for llama.cpp")
	nThreads := flag.Int("threads", 4, "CPU threads for llama.cpp")

	// System prompt for the verification request (optional).
	systemPrompt := flag.String("system", "You are a helpful local model.", "System prompt for verification chat")

	// Timeouts/TLS for the final verification HTTP request.
	timeout := flag.Duration("timeout", 10*time.Minute, "Overall timeout for the setup")
	insecureTLS := flag.Bool("insecure", true, "Allow insecure TLS (handy for local CRC)")

	// Parse flags from CLI.
	flag.Parse()

	// Derive a default host like: <name>.<namespace>.apps-crc.testing
	if *host == "" {
		*host = fmt.Sprintf("%s.%s.apps-crc.testing", *name, *ns)
	}
	// We require a direct, curl'able GGUF URL (no login prompts/cookies).
	if *modelURL == "" {
		fatal("--model-url is required (a direct link to a .gguf file)")
	}

	// Create a context that automatically cancels after --timeout.
	ctx, cancel := context.WithTimeout(context.Background(), *timeout)
	defer cancel()

	// ---------------------
	// Build Kubernetes client
	// ---------------------
	// Load kubeconfig exactly like kubectl does.
	cfg, err := clientcmd.BuildConfigFromFlags("", *kubeconfig)
	must(err, "load kubeconfig")
	// Build the typed clientset (CoreV1, AppsV1, etc.).
	cs, err := kubernetes.NewForConfig(cfg)
	must(err, "create clientset")

	// -----------------------
	// Ensure Namespace exists
	// -----------------------
	fmt.Printf("Ensuring namespace %q exists...\n", *ns)
	must(ensureNamespace(ctx, cs, *ns), "ensure namespace")

	// -------------------------------
	// Create/Update the ConfigMap
	// -------------------------------
	// A ConfigMap stores non-secret key/value config. We'll use it to:
	// - pass the model URL to the initContainer
	// - pass model parameters (ctx, threads, name, system prompt) to llama.cpp
	cmName := *name + "-config"
	cm := &corev1.ConfigMap{
		ObjectMeta: metav1.ObjectMeta{
			Name:      cmName,
			Namespace: *ns,
		},
		Data: map[string]string{
			"MODEL_URL":     *modelURL,
			"MODEL_NAME":    *modelName,
			"SYSTEM_PROMPT": *systemPrompt,
			"CTX_LEN":       fmt.Sprintf("%d", *ctxLen),
			"N_THREADS":     fmt.Sprintf("%d", *nThreads),
		},
	}
	fmt.Println("Creating/updating ConfigMap...")
	must(upsertConfigMap(ctx, cs, cm), "upsert configmap")

	// -----------------------------------------
	// Create/Update a PVC for persistent /models
	// -----------------------------------------
	// We use a 5Gi PVC so the downloaded model survives pod restarts.
	// On CRC, a default StorageClass usually exists and will bind this PVC.
	pvcName := *name + "-models-pvc"
	pvc := &corev1.PersistentVolumeClaim{
		ObjectMeta: metav1.ObjectMeta{
			Name:      pvcName,
			Namespace: *ns,
		},
		Spec: corev1.PersistentVolumeClaimSpec{
			AccessModes: []corev1.PersistentVolumeAccessMode{
				corev1.ReadWriteOnce, // good for single-node CRC
			},
			Resources: corev1.ResourceRequirements{
				Requests: corev1.ResourceList{
					corev1.ResourceStorage: resource.MustParse("5Gi"),
				},
			},
		},
	}
	fmt.Println("Creating/updating PVC (persistent /models)...")
	must(upsertPVC(ctx, cs, pvc), "upsert pvc")

	// ------------------------------------------------------------------
	// Build the Deployment: initContainer (download) + llama.cpp server
	// ------------------------------------------------------------------
	labels := map[string]string{"app": *name}
	modelVolName := "model-store"
	modelMountPath := "/models"

	// IMPORTANT OpenShift detail:
	// - OpenShift uses a *random non-root UID* under the restricted SCC.
	// - Mounted volumes need to be writable by that UID. Setting an FSGroup
	//   at the Pod level makes the volume group-writable appropriately.
	var fsGroup int64 = 65532 // a typical non-privileged group id

	dep := &appsv1.Deployment{
		ObjectMeta: metav1.ObjectMeta{
			Name:      *name,
			Namespace: *ns,
			Labels:    labels,
		},
		Spec: appsv1.DeploymentSpec{
			Replicas: int32p(1),
			Selector: &metav1.LabelSelector{MatchLabels: labels},
			Template: corev1.PodTemplateSpec{
				ObjectMeta: metav1.ObjectMeta{Labels: labels},
				Spec: corev1.PodSpec{
					// Pod-level security context to handle volume perms under restricted SCC
					SecurityContext: &corev1.PodSecurityContext{
						FSGroup: &fsGroup,
						// FSGroupChangeOnRootMismatch reduces unnecessary recursive chown on every mount
						FSGroupChangePolicy: func() *corev1.PodFSGroupChangePolicy {
							v := corev1.FSGroupChangeOnRootMismatch
							return &v
						}(),
					},

					// -------- initContainer: fetch the model into /models --------
					InitContainers: []corev1.Container{
						{
							Name:  "fetch-model",
							Image: "curlimages/curl:8.10.1", // small image with curl
							Command: []string{"sh", "-lc"},
							Args: []string{
								// The script below:
								// - creates /models
								// - ensures it's writable (0775) for fsGroup/random UID
								// - downloads model.gguf with retries if it's missing
								// - shows a listing on success
								`set -euo pipefail
mkdir -p /models
chmod 0775 /models || true

if [ -s /models/model.gguf ]; then
  echo "Model already present: $(ls -lh /models/model.gguf)"
else
  echo "Downloading model from ${MODEL_URL} ..."
  # curl flags:
  # -L: follow redirects
  # --fail: treat HTTP 4xx/5xx as errors
  # --show-error: print error messages on failure
  # --retry/--retry-delay/--retry-max-time: resilience to transient failures
  # --speed-time/--speed-limit: abort if too slow (e.g., hung connection)
  curl -L --fail --show-error \
       --retry 5 --retry-delay 3 --retry-max-time 180 \
       --speed-time 30 --speed-limit 1024 \
       -o /models/model.gguf "${MODEL_URL}"
  echo "Download complete: $(ls -lh /models/model.gguf)"
fi
ls -l /models
`,
							},
							Env: []corev1.EnvVar{
								{Name: "MODEL_URL", ValueFrom: cfgKey(cmName, "MODEL_URL")},
							},
							VolumeMounts: []corev1.VolumeMount{
								{Name: modelVolName, MountPath: modelMountPath},
							},
							SecurityContext: &corev1.SecurityContext{
								RunAsNonRoot:             boolp(true),
								AllowPrivilegeEscalation: boolp(false),
							},
						},
					},

					// -------- main container: llama.cpp server (OpenAI-compatible) --------
					Containers: []corev1.Container{
						{
							Name:  "llama-server",
							// Official server image. We do NOT override command/entrypoint.
							// We'll configure it entirely via LLAMA_ARG_* environment vars below.
							Image: "ghcr.io/ggerganov/llama.cpp:server",

							// Expose HTTP port 8080 (the image listens here with --api).
							Ports: []corev1.ContainerPort{
								{Name: "http", ContainerPort: 8080},
							},

							// Liveness/Readiness:
							// Not all builds expose a health path; TCP probes are the most tolerant.
							ReadinessProbe: &corev1.Probe{
								ProbeHandler: corev1.ProbeHandler{
									TCPSocket: &corev1.TCPSocketAction{Port: intstr.FromInt(8080)},
								},
								InitialDelaySeconds: 5,
								PeriodSeconds:       5,
							},
							LivenessProbe: &corev1.Probe{
								ProbeHandler: corev1.ProbeHandler{
									TCPSocket: &corev1.TCPSocketAction{Port: intstr.FromInt(8080)},
								},
								InitialDelaySeconds: 15,
								PeriodSeconds:       10,
							},

							SecurityContext: &corev1.SecurityContext{
								RunAsNonRoot:             boolp(true),
								AllowPrivilegeEscalation: boolp(false),
							},

							// Mount the /models PVC so the server can read model.gguf
							VolumeMounts: []corev1.VolumeMount{
								{Name: modelVolName, MountPath: modelMountPath},
							},

							// ENV VARS: the server image reads LLAMA_ARG_* to form its arguments.
							// This avoids hardcoding a binary path and keeps compatibility.
							Env: []corev1.EnvVar{
								// Model path:
								{Name: "LLAMA_ARG_MODEL", Value: "/models/model.gguf"},
								// Context length (tokens):
								{Name: "LLAMA_ARG_CTX_SIZE", ValueFrom: cfgKey(cmName, "CTX_LEN")},
								// Threads:
								{Name: "LLAMA_ARG_THREADS", ValueFrom: cfgKey(cmName, "N_THREADS")},
								// Bind host/port:
								{Name: "LLAMA_ARG_HOST", Value: "0.0.0.0"},
								{Name: "LLAMA_ARG_PORT", Value: "8080"},
								// Enable OpenAI-compatible API:
								{Name: "LLAMA_ARG_API", Value: "1"},

								// Optional metadata your clients can use:
								{Name: "MODEL_NAME", ValueFrom: cfgKey(cmName, "MODEL_NAME")},
								{Name: "SYSTEM_PROMPT", ValueFrom: cfgKey(cmName, "SYSTEM_PROMPT")},
							},
						},
					},

					// Volumes section: attach the PVC as "model-store" -> /models
					Volumes: []corev1.Volume{
						{
							Name: modelVolName,
							VolumeSource: corev1.VolumeSource{
								PersistentVolumeClaim: &corev1.PersistentVolumeClaimVolumeSource{
									ClaimName: pvcName,
								},
							},
						},
					},
				},
			},
		},
	}
	fmt.Println("Creating/updating Deployment (with initContainer and FSGroup)...")
	must(upsertDeployment(ctx, cs, dep), "upsert deployment")

	// -------------------------
	// Service (ClusterIP)
	// -------------------------
	// Internal stable address for other pods (and a target for Ingress).
	svc := &corev1.Service{
		ObjectMeta: metav1.ObjectMeta{
			Name:      *name,
			Namespace: *ns,
			Labels:    labels,
		},
		Spec: corev1.ServiceSpec{
			Selector: labels,
			Ports: []corev1.ServicePort{
				{Name: "http", Port: 80, TargetPort: intstr.FromInt(8080)},
			},
			Type: corev1.ServiceTypeClusterIP,
		},
	}
	fmt.Println("Creating/updating Service...")
	must(upsertService(ctx, cs, svc), "upsert service")

	// -------------------------
	// Ingress (OpenShift router)
	// -------------------------
	// On CRC, OpenShift's router will expose this Ingress externally.
	pathType := netv1.PathTypePrefix
	ing := &netv1.Ingress{
		ObjectMeta: metav1.ObjectMeta{
			Name:      *name,
			Namespace: *ns,
			Labels:    labels,
			Annotations: map[string]string{
				// Generous timeout to accommodate model startup/first token times.
				"haproxy.router.openshift.io/timeout": "180s",
			},
		},
		Spec: netv1.IngressSpec{
			Rules: []netv1.IngressRule{
				{
					Host: *host,
					IngressRuleValue: netv1.IngressRuleValue{
						HTTP: &netv1.HTTPIngressRuleValue{
							Paths: []netv1.HTTPIngressPath{
								{
									Path:     "/",
									PathType: &pathType,
									Backend: netv1.IngressBackend{
										Service: &netv1.IngressServiceBackend{
											Name: *name,
											Port: netv1.ServiceBackendPort{Name: "http"},
										},
									},
								},
							},
						},
					},
				},
			},
			// For TLS you could add IngressTLS; HTTP is fine for local CRC tests.
		},
	}
	fmt.Println("Creating/updating Ingress...")
	must(upsertIngress(ctx, cs, ing), "upsert ingress")

	// -------------------------
	// Wait for readiness
	// -------------------------
	fmt.Println("Waiting for Deployment to have at least 1 ready replica (first run may take time for download)...")
	must(waitForDeploymentReady(ctx, cs, *ns, *name), "deployment not ready in time")

	fmt.Println("Waiting for Service to have endpoints (pod IPs behind the Service)...")
	must(waitForEndpoints(ctx, cs, *ns, *name), "service has no endpoints")

	// -------------------------
	// Verify via OpenAI-style /v1/chat/completions
	// -------------------------
	url := "http://" + *host + "/v1/chat/completions"
	fmt.Printf("Probing: %s\n", url)

	reqBody := chatReq{
		Model:  *modelName,
		Stream: false,
		Messages: []chatMessage{
			{Role: "system", Content: *systemPrompt},
			{Role: "user", Content: "Say hello in one short sentence."},
		},
	}
	bts, _ := json.Marshal(reqBody)

	// http.Client with a reasonable timeout. For local CRC with self-signed certs,
	// you might set InsecureSkipVerify if switching to HTTPS.
	httpClient := &http.Client{Timeout: 120 * time.Second}
	if *insecureTLS {
		httpClient.Transport = &http.Transport{
			TLSClientConfig: &tls.Config{InsecureSkipVerify: true}, // acceptable for local dev only
		}
	}

	req, _ := http.NewRequest("POST", url, strings.NewReader(string(bts)))
	req.Header.Set("Content-Type", "application/json")

	resp, err := httpClient.Do(req)
	must(err, "verification HTTP error")
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)

	if resp.StatusCode/100 != 2 {
		// Print the body for debugging if not 2xx.
		fatal("non-2xx from chat endpoint: %d\n%s", resp.StatusCode, string(body))
	}

	// Parse minimal response to confirm the model answered.
	var parsed chatResp
	if err := json.Unmarshal(body, &parsed); err != nil {
		fmt.Println("Raw response:", string(body))
		fatal("could not parse response JSON: %v", err)
	}
	if len(parsed.Choices) == 0 {
		fmt.Println("Raw response:", string(body))
		fatal("no choices in response")
	}

	fmt.Printf("✅ Chat OK. Assistant replied: %q\n", parsed.Choices[0].Message.Content)
	fmt.Println("Done.")
}

// -----------------------------
// Helper functions (Kubernetes)
// -----------------------------

// ensureNamespace: create the Namespace if it doesn't exist.
func ensureNamespace(ctx context.Context, cs *kubernetes.Clientset, ns string) error {
	_, err := cs.CoreV1().Namespaces().Get(ctx, ns, metav1.GetOptions{})
	if kerrors.IsNotFound(err) {
		_, err = cs.CoreV1().Namespaces().Create(ctx, &corev1.Namespace{
			ObjectMeta: metav1.ObjectMeta{Name: ns},
		}, metav1.CreateOptions{})
		return err
	}
	return err
}

// upsertConfigMap: create if missing, else update Data.
func upsertConfigMap(ctx context.Context, cs *kubernetes.Clientset, cm *corev1.ConfigMap) error {
	client := cs.CoreV1().ConfigMaps(cm.Namespace)
	existing, err := client.Get(ctx, cm.Name, metav1.GetOptions{})
	if kerrors.IsNotFound(err) {
		_, err = client.Create(ctx, cm, metav1.CreateOptions{})
		return err
	}
	if err != nil {
		return err
	}
	existing.Data = cm.Data
	_, err = client.Update(ctx, existing, metav1.UpdateOptions{})
	return err
}

// upsertPVC: create if missing, else update Requests/AccessModes.
func upsertPVC(ctx context.Context, cs *kubernetes.Clientset, pvc *corev1.PersistentVolumeClaim) error {
	client := cs.CoreV1().PersistentVolumeClaims(pvc.Namespace)
	existing, err := client.Get(ctx, pvc.Name, metav1.GetOptions{})
	if kerrors.IsNotFound(err) {
		_, err = client.Create(ctx, pvc, metav1.CreateOptions{})
		return err
	}
	if err != nil {
		return err
	}
	// Note: Some PVC fields are immutable after binding, but adjusting resources
	// (requests) is usually allowed depending on the storage class.
	existing.Spec.Resources = pvc.Spec.Resources
	existing.Spec.AccessModes = pvc.Spec.AccessModes
	_, err = client.Update(ctx, existing, metav1.UpdateOptions{})
	return err
}

// upsertDeployment: create if missing, else replace the Spec.
func upsertDeployment(ctx context.Context, cs *kubernetes.Clientset, d *appsv1.Deployment) error {
	client := cs.AppsV1().Deployments(d.Namespace)
	existing, err := client.Get(ctx, d.Name, metav1.GetOptions{})
	if kerrors.IsNotFound(err) {
		_, err = client.Create(ctx, d, metav1.CreateOptions{})
		return err
	}
	if err != nil {
		return err
	}
	existing.Spec = d.Spec
	_, err = client.Update(ctx, existing, metav1.UpdateOptions{})
	return err
}

// upsertService: create if missing, else replace Spec preserving ClusterIP.
func upsertService(ctx context.Context, cs *kubernetes.Clientset, s *corev1.Service) error {
	client := cs.CoreV1().Services(s.Namespace)
	existing, err := client.Get(ctx, s.Name, metav1.GetOptions{})
	if kerrors.IsNotFound(err) {
		_, err = client.Create(ctx, s, metav1.CreateOptions{})
		return err
	}
	if err != nil {
		return err
	}
	// ClusterIP is immutable; preserve it on update.
	clusterIP := existing.Spec.ClusterIP
	existing.Spec = s.Spec
	existing.Spec.ClusterIP = clusterIP
	_, err = client.Update(ctx, existing, metav1.UpdateOptions{})
	return err
}

// upsertIngress: create if missing, else update Spec and merge annotations.
func upsertIngress(ctx context.Context, cs *kubernetes.Clientset, ing *netv1.Ingress) error {
	client := cs.NetworkingV1().Ingresses(ing.Namespace)
	existing, err := client.Get(ctx, ing.Name, metav1.GetOptions{})
	if kerrors.IsNotFound(err) {
		_, err = client.Create(ctx, ing, metav1.CreateOptions{})
		return err
	}
	if err != nil {
		return err
	}
	existing.Spec = ing.Spec
	if existing.Annotations == nil {
		existing.Annotations = map[string]string{}
	}
	for k, v := range ing.Annotations {
		existing.Annotations[k] = v
	}
	_, err = client.Update(ctx, existing, metav1.UpdateOptions{})
	return err
}

// waitForDeploymentReady: poll until ReadyReplicas >= 1 or context times out.
func waitForDeploymentReady(ctx context.Context, cs *kubernetes.Clientset, ns, name string) error {
	return waitutil.PollImmediateUntilWithContext(ctx, 3*time.Second, func(ctx context.Context) (bool, error) {
		d, err := cs.AppsV1().Deployments(ns).Get(ctx, name, metav1.GetOptions{})
		if err != nil {
			return false, err
		}
		return d.Status.ReadyReplicas >= 1, nil
	})
}

// waitForEndpoints: poll until the Service lists at least one ready endpoint.
func waitForEndpoints(ctx context.Context, cs *kubernetes.Clientset, ns, name string) error {
	return waitutil.PollImmediateUntilWithContext(ctx, 3*time.Second, func(ctx context.Context) (bool, error) {
		ep, err := cs.CoreV1().Endpoints(ns).Get(ctx, name, metav1.GetOptions{})
		if err != nil {
			return false, err
		}
		for _, s := range ep.Subsets {
			if len(s.Addresses) > 0 {
				return true, nil
			}
		}
		return false, nil
	})
}

// must: fail fast with a formatted message if err != nil.
func must(err error, msg string, args ...any) {
	if err != nil {
		fatal(msg+": %v", append(args, err)...)
	}
}

// fatal: print error to stderr and exit non-zero.
func fatal(msg string, args ...any) {
	fmt.Fprintf(os.Stderr, "ERROR: "+msg+"\n", args...)
	os.Exit(1)
}

