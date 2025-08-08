// -----------------------------------------------
// setup_local_chat_openshift.go
//
// End-to-end local OpenShift (CRC) setup:
//
// 1) Connect to cluster via kubeconfig.
// 2) Ensure Namespace exists.
// 3) Create/Update ConfigMap with model params.
// 4) Create/Update Deployment (non-root, UBI Python).
//    - Creates a /tmp venv (writable under restricted SCC)
//    - Installs FastAPI/Uvicorn into that venv
//    - Serves /healthz and POST /chat on :8080
// 5) Create/Update ClusterIP Service.
// 6) Create/Update Ingress (OpenShift router exposes it on CRC).
// 7) Wait for readiness and verify by POSTing to /chat.
//
// Usage example:
//   go run setup_local_chat_openshift.go \
//     --kubeconfig=$HOME/.kube/config \
//     --namespace=testing \
//     --name=local-chat \
//     --model=phi-2 \
//     --system="You are a helpful LANL HPC assistant."
// -----------------------------------------------

package main

import (
	"context"
	"crypto/tls"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	netv1 "k8s.io/api/networking/v1"

	kerrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/util/intstr"
	waitutil "k8s.io/apimachinery/pkg/util/wait"

	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"
)

// int32p: helper to get *int32 from a literal (Go doesn’t allow &int32(1)).
func int32p(i int32) *int32 { return &i }

// boolp: helper to get *bool from a literal.
func boolp(b bool) *bool { return &b }

// chatReq/Resp: minimal request/response payloads for the stub chat server.
type chatReq struct {
	Prompt string `json:"prompt"`
}
type chatResp struct {
	Model   string `json:"model"`
	Output  string `json:"output"`
	System  string `json:"system"`
	Version string `json:"version"`
}

func main() {
	// ---------- Flags (CLI options) ----------
	ns := flag.String("namespace", "testing", "Target namespace (created if missing)")
	name := flag.String("name", "local-chat", "Base name for all K8s objects")
	host := flag.String("host", "", "Ingress host (default: <name>.<ns>.apps-crc.testing)")
	modelName := flag.String("model", "tiny-chat", "Model name reported by the stub")
	systemPrompt := flag.String("system", "You are a helpful local model.", "System prompt string")
	kubeconfig := flag.String("kubeconfig", filepath.Join(os.Getenv("HOME"), ".kube", "config"), "Path to kubeconfig")
	timeout := flag.Duration("timeout", 5*time.Minute, "Overall timeout")
	insecureTLS := flag.Bool("insecure", true, "Skip TLS verify (CRC uses self-signed certs)")
	flag.Parse()

	if *host == "" {
		*host = fmt.Sprintf("%s.%s.apps-crc.testing", *name, *ns)
	}

	// Context with overall timeout so nothing hangs forever.
	ctx, cancel := context.WithTimeout(context.Background(), *timeout)
	defer cancel()

	// ---------- Build Kubernetes client ----------
	cfg, err := clientcmd.BuildConfigFromFlags("", *kubeconfig)
	must(err, "load kubeconfig")
	cs, err := kubernetes.NewForConfig(cfg)
	must(err, "create clientset")

	// ---------- Ensure Namespace ----------
	fmt.Printf("Ensuring namespace %q exists...\n", *ns)
	if err := ensureNamespace(ctx, cs, *ns); err != nil {
		fatal("ensure namespace: %v", err)
	}

	// ---------- ConfigMap (model params) ----------
	cm := &corev1.ConfigMap{
		ObjectMeta: metav1.ObjectMeta{
			Name:      *name + "-config",
			Namespace: *ns,
		},
		Data: map[string]string{
			"MODEL_NAME":    *modelName,
			"SYSTEM_PROMPT": *systemPrompt,
		},
	}
	fmt.Println("Creating/updating ConfigMap...")
	must(upsertConfigMap(ctx, cs, cm), "upsert configmap")

	// ---------- Deployment (non-root UBI Python + venv in /tmp) ----------
	labels := map[string]string{"app": *name}
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
					Containers: []corev1.Container{
						{
							Name:  "chat",
							Image: "registry.access.redhat.com/ubi9/python-39:latest",
							Command: []string{"bash", "-lc"},
							Args: []string{`
set -euo pipefail
cd /tmp

# Write tiny FastAPI app
cat > app.py <<'PY'
from fastapi import FastAPI
from pydantic import BaseModel
import os

app = FastAPI()

class ChatReq(BaseModel):
    prompt: str

@app.get("/healthz")
def healthz():
    return {"ok": True}

@app.post("/chat")
async def chat(req: ChatReq):
    model = os.environ.get("MODEL_NAME", "unknown-model")
    system = os.environ.get("SYSTEM_PROMPT", "")
    text = f"I ({model}) received: {req.prompt.strip()}"
    return {"model": model, "output": text, "system": system, "version": "stub-1"}
PY

# Make writable virtualenv in /tmp (works with OpenShift's random UID)
python -m venv /tmp/venv
. /tmp/venv/bin/activate

# Speed up/quiet pip; IMPORTANT: no --user here
export PIP_NO_CACHE_DIR=1
export PIP_DISABLE_PIP_VERSION_CHECK=1

pip install fastapi==0.115.0 uvicorn==0.30.6 pydantic==2.8.2

# Run app with uvicorn; exec makes it PID 1 for clean signals
exec python -c 'import uvicorn; uvicorn.run("app:app", host="0.0.0.0", port=8080)'
`},
							Env: []corev1.EnvVar{
								{
									Name: "MODEL_NAME",
									ValueFrom: &corev1.EnvVarSource{
										ConfigMapKeyRef: &corev1.ConfigMapKeySelector{
											LocalObjectReference: corev1.LocalObjectReference{Name: *name + "-config"},
											Key:                  "MODEL_NAME",
										},
									},
								},
								{
									Name: "SYSTEM_PROMPT",
									ValueFrom: &corev1.EnvVarSource{
										ConfigMapKeyRef: &corev1.ConfigMapKeySelector{
											LocalObjectReference: corev1.LocalObjectReference{Name: *name + "-config"},
											Key:                  "SYSTEM_PROMPT",
										},
									},
								},
							},
							Ports: []corev1.ContainerPort{{Name: "http", ContainerPort: 8080}},
							SecurityContext: &corev1.SecurityContext{
								RunAsNonRoot:             boolp(true),
								AllowPrivilegeEscalation: boolp(false),
							},
							ReadinessProbe: &corev1.Probe{
								ProbeHandler: corev1.ProbeHandler{
									HTTPGet: &corev1.HTTPGetAction{
										Path: "/healthz",
										Port: intstr.FromInt(8080),
									},
								},
								InitialDelaySeconds: 3,
								PeriodSeconds:       5,
							},
							LivenessProbe: &corev1.Probe{
								ProbeHandler: corev1.ProbeHandler{
									HTTPGet: &corev1.HTTPGetAction{
										Path: "/healthz",
										Port: intstr.FromInt(8080),
									},
								},
								InitialDelaySeconds: 10,
								PeriodSeconds:       10,
							},
							WorkingDir: "/tmp",
						},
					},
				},
			},
		},
	}
	fmt.Println("Creating/updating Deployment...")
	must(upsertDeployment(ctx, cs, dep), "upsert deployment")

	// ---------- Service (ClusterIP) ----------
	svc := &corev1.Service{
		ObjectMeta: metav1.ObjectMeta{
			Name:      *name,
			Namespace: *ns,
			Labels:    labels,
		},
		Spec: corev1.ServiceSpec{
			Selector: labels,
			Ports: []corev1.ServicePort{
				{
					Name:       "http",
					Port:       80,
					TargetPort: intstr.FromInt(8080),
				},
			},
			Type: corev1.ServiceTypeClusterIP,
		},
	}
	fmt.Println("Creating/updating Service...")
	must(upsertService(ctx, cs, svc), "upsert service")

	// ---------- Ingress (OpenShift router will expose it on CRC) ----------
	pathType := netv1.PathTypePrefix
	ing := &netv1.Ingress{
		ObjectMeta: metav1.ObjectMeta{
			Name:      *name,
			Namespace: *ns,
			Labels:    labels,
			Annotations: map[string]string{
				"haproxy.router.openshift.io/timeout": "120s",
			},
		},
		Spec: netv1.IngressSpec{
			Rules: []netv1.IngressRule{
				{
					Host: *host, // e.g., local-chat.testing.apps-crc.testing
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
			// Add TLS here if you have a secret; HTTP is fine on CRC for local testing.
		},
	}
	fmt.Println("Creating/updating Ingress...")
	must(upsertIngress(ctx, cs, ing), "upsert ingress")

	// ---------- Wait for readiness ----------
	fmt.Println("Waiting for Deployment ready replicas...")
	must(waitForDeploymentReady(ctx, cs, *ns, *name), "deployment not ready")

	fmt.Println("Waiting for Service endpoints...")
	must(waitForEndpoints(ctx, cs, *ns, *name), "service has no ready endpoints")

	// ---------- Verify by POST /chat ----------
	url := "http://" + *host + "/chat"
	fmt.Printf("Probing chat endpoint: %s\n", url)

	reqBody, _ := json.Marshal(chatReq{Prompt: "Hello from OpenShift CRC!"})

	httpClient := &http.Client{Timeout: 30 * time.Second}
	if *insecureTLS {
		httpClient.Transport = &http.Transport{
			TLSClientConfig: &tls.Config{InsecureSkipVerify: true}, // ok for local CRC
		}
	}

	req, _ := http.NewRequest("POST", url, strings.NewReader(string(reqBody)))
	req.Header.Set("Content-Type", "application/json")

	resp, err := httpClient.Do(req)
	must(err, "probe HTTP error")
	defer resp.Body.Close()
	bts, _ := io.ReadAll(resp.Body)

	if resp.StatusCode/100 != 2 {
		fatal("non-2xx from chat endpoint: %s", string(bts))
	}

	var parsed chatResp
	must(json.Unmarshal(bts, &parsed), "bad JSON from chat endpoint; body=%s", string(bts))
	fmt.Printf("✅ Chat OK. Model=%q Output=%q\n", parsed.Model, parsed.Output)
	fmt.Println("Done.")
}

// -----------------------------
// Helpers
// -----------------------------

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
	// Preserve immutable ClusterIP on update
	clusterIP := existing.Spec.ClusterIP
	existing.Spec = s.Spec
	existing.Spec.ClusterIP = clusterIP
	_, err = client.Update(ctx, existing, metav1.UpdateOptions{})
	return err
}

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

func waitForDeploymentReady(ctx context.Context, cs *kubernetes.Clientset, ns, name string) error {
	return waitutil.PollImmediateUntilWithContext(ctx, 2*time.Second, func(ctx context.Context) (bool, error) {
		d, err := cs.AppsV1().Deployments(ns).Get(ctx, name, metav1.GetOptions{})
		if err != nil {
			return false, err
		}
		return d.Status.ReadyReplicas >= 1, nil
	})
}

func waitForEndpoints(ctx context.Context, cs *kubernetes.Clientset, ns, name string) error {
	return waitutil.PollImmediateUntilWithContext(ctx, 2*time.Second, func(ctx context.Context) (bool, error) {
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

func must(err error, msg string, args ...any) {
	if err != nil {
		fatal(msg+": %v", append(args, err)...)
	}
}

func fatal(msg string, args ...any) {
	fmt.Fprintf(os.Stderr, "ERROR: "+msg+"\n", args...)
	os.Exit(1)
}

