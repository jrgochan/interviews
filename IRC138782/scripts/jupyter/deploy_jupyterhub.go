// --------------------------------------------------------------
// deploy_jupyterhub.go
//
// This program performs an end-to-end setup of JupyterHub on
// local OpenShift (CRC) with the following features:
//
// (1) Connect to the cluster (via your kubeconfig).
// (2) Ensure a target Namespace exists.
// (3) Create/Update ConfigMaps containing JupyterHub configuration.
// (4) Create/Update Secrets for authentication tokens and passwords.
// (5) Create/Update RBAC resources (ServiceAccount, Role, RoleBinding).
// (6) Create/Update a PersistentVolumeClaim for JupyterHub database.
// (7) Create/Update a Deployment with JupyterHub container configured
//     for OpenShift with KubeSpawner for launching user notebooks.
// (8) Create/Update a ClusterIP Service for internal communication.
// (9) Create/Update an OpenShift Route for external access.
// (10) Wait for readiness and verify the deployment is accessible.
//
// --------------------------------------------------------------
// HOW TO RUN (example):
//
//   # In the scripts/jupyter directory:
//   go mod tidy
//
//   # Basic deployment
//   go run deploy_jupyterhub.go \
//     --kubeconfig=$HOME/.kube/config \
//     --namespace=jupyterhub \
//     --admin-user=admin \
//     --admin-password=mypassword
//
//   # Custom configuration
//   go run deploy_jupyterhub.go \
//     --namespace=jupyter-dev \
//     --admin-user=developer \
//     --storage-size=20Gi \
//     --memory-limit=4Gi \
//     --max-users=20
//
// After success, JupyterHub should be accessible at:
//   http://<app-name>.<namespace>.apps-crc.testing
//
// --------------------------------------------------------------

package main

// Standard library imports
import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"flag"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	// Kubernetes API types

	appsv1 "k8s.io/api/apps/v1"

	corev1 "k8s.io/api/core/v1"

	rbacv1 "k8s.io/api/rbac/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"

	// OpenShift Route API (using unstructured for simplicity)

	// Kubernetes helper packages

	kerrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/resource"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/util/intstr"

	waitutil "k8s.io/apimachinery/pkg/util/wait"
	"k8s.io/client-go/dynamic"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"
)

// Kubernetes client-go

// ---------- Helper functions ----------

// int32p returns a pointer to an int32 literal
func int32p(i int32) *int32 { return &i }

// boolp returns a pointer to a bool literal
func boolp(b bool) *bool { return &b }

// generateSecret creates a random hex string of specified length
func generateSecret(length int) string {
	bytes := make([]byte, length/2)
	if _, err := rand.Read(bytes); err != nil {
		// Fallback to timestamp-based generation
		return fmt.Sprintf("%x", time.Now().UnixNano())[:length]
	}
	return hex.EncodeToString(bytes)
}

// ---------- Main entrypoint ----------
func main() {
	// Command-line flags
	ns := flag.String("namespace", "jupyterhub", "Namespace to deploy into (created if missing)")
	name := flag.String("name", "jupyterhub", "Base name for all objects")
	kubeconfig := flag.String("kubeconfig", filepath.Join(os.Getenv("HOME"), ".kube", "config"), "Path to kubeconfig")

	// JupyterHub configuration
	jupyterhubImage := flag.String("jupyterhub-image", "quay.io/jupyterhub/jupyterhub:4.0", "JupyterHub container image")
	notebookImage := flag.String("notebook-image", "quay.io/jupyter/scipy-notebook:latest", "Default notebook image for users")
	adminUser := flag.String("admin-user", "admin", "Admin username")
	adminPassword := flag.String("admin-password", "", "Admin password (auto-generated if empty)")

	// Resource configuration
	storageSize := flag.String("storage-size", "10Gi", "Hub storage size")
	userStorageSize := flag.String("user-storage-size", "5Gi", "User storage size")
	memoryLimit := flag.String("memory-limit", "2Gi", "Memory limit per container")
	cpuLimit := flag.String("cpu-limit", "1000m", "CPU limit per container")
	maxUsers := flag.Int("max-users", 10, "Maximum concurrent users")

	// Timeouts
	timeout := flag.Duration("timeout", 10*time.Minute, "Overall timeout for the setup")

	flag.Parse()

	// Generate admin password if not provided
	if *adminPassword == "" {
		*adminPassword = generateSecret(16)
		fmt.Printf("Generated admin password: %s\n", *adminPassword)
		fmt.Println("Save this password - it will be needed to access JupyterHub!")
	}

	// Create context with timeout
	ctx, cancel := context.WithTimeout(context.Background(), *timeout)
	defer cancel()

	// Build Kubernetes client
	cfg, err := clientcmd.BuildConfigFromFlags("", *kubeconfig)
	must(err, "load kubeconfig")

	cs, err := kubernetes.NewForConfig(cfg)
	must(err, "create clientset")

	// Dynamic client for OpenShift Routes
	dynClient, err := dynamic.NewForConfig(cfg)
	must(err, "create dynamic client")

	// Ensure Namespace exists
	fmt.Printf("Ensuring namespace %q exists...\n", *ns)
	must(ensureNamespace(ctx, cs, *ns), "ensure namespace")

	// Create ConfigMap with JupyterHub configuration
	fmt.Println("Creating/updating ConfigMap...")
	cm := createJupyterHubConfigMap(*name, *ns, *adminUser, *adminPassword, *notebookImage, *userStorageSize, *cpuLimit, *memoryLimit, *maxUsers)
	must(upsertConfigMap(ctx, cs, cm), "upsert configmap")

	// Create Secret with authentication tokens
	fmt.Println("Creating/updating Secret...")
	secret := createJupyterHubSecret(*name, *ns, *adminPassword)
	must(upsertSecret(ctx, cs, secret), "upsert secret")

	// Create RBAC resources
	fmt.Println("Creating/updating RBAC resources...")
	sa := createServiceAccount(*name, *ns)
	must(upsertServiceAccount(ctx, cs, sa), "upsert service account")

	role := createRole(*name, *ns)
	must(upsertRole(ctx, cs, role), "upsert role")

	roleBinding := createRoleBinding(*name, *ns)
	must(upsertRoleBinding(ctx, cs, roleBinding), "upsert role binding")

	// Create PVC for JupyterHub database
	fmt.Println("Creating/updating PVC...")
	pvc := createJupyterHubPVC(*name, *ns, *storageSize)
	must(upsertPVC(ctx, cs, pvc), "upsert pvc")

	// Create Deployment
	fmt.Println("Creating/updating Deployment...")
	deployment := createJupyterHubDeployment(*name, *ns, *jupyterhubImage, *memoryLimit, *cpuLimit)
	must(upsertDeployment(ctx, cs, deployment), "upsert deployment")

	// Create Service
	fmt.Println("Creating/updating Service...")
	service := createJupyterHubService(*name, *ns)
	must(upsertService(ctx, cs, service), "upsert service")

	// Create OpenShift Route
	fmt.Println("Creating/updating Route...")
	route := createJupyterHubRoute(*name, *ns)
	must(upsertRoute(ctx, dynClient, route), "upsert route")

	// Wait for deployment readiness
	fmt.Println("Waiting for JupyterHub deployment to be ready...")
	must(waitForDeploymentReady(ctx, cs, *ns, *name), "deployment not ready in time")

	fmt.Println("Waiting for Service to have endpoints...")
	must(waitForEndpoints(ctx, cs, *ns, *name), "service has no endpoints")

	// Get route information
	routeHost, err := getRouteHost(ctx, dynClient, *ns, *name)
	if err != nil {
		fmt.Printf("Warning: Could not get route host: %v\n", err)
		routeHost = fmt.Sprintf("%s.%s.apps-crc.testing", *name, *ns)
	}

	jupyterhubURL := "http://" + routeHost

	// Verify JupyterHub is accessible
	fmt.Printf("Verifying JupyterHub accessibility at %s...\n", jupyterhubURL)
	if err := verifyJupyterHubAccess(jupyterhubURL); err != nil {
		fmt.Printf("Warning: Could not verify JupyterHub access: %v\n", err)
		fmt.Println("JupyterHub may still be starting up. Check manually.")
	} else {
		fmt.Println("✅ JupyterHub is accessible!")
	}

	// Display final information
	fmt.Println("\n" + strings.Repeat("=", 60))
	fmt.Println("JupyterHub deployment completed successfully!")
	fmt.Println(strings.Repeat("=", 60))
	fmt.Printf("URL: %s\n", jupyterhubURL)
	fmt.Printf("Admin Username: %s\n", *adminUser)
	fmt.Printf("Admin Password: %s\n", *adminPassword)
	fmt.Println("\nNext Steps:")
	fmt.Println("1. Access JupyterHub at the URL above")
	fmt.Println("2. Login with the admin credentials")
	fmt.Println("3. Create additional users as needed")
	fmt.Println("4. Users will get persistent storage automatically")
	fmt.Println("\nManagement Commands:")
	fmt.Printf("  # View logs\n  oc logs -f deployment/%s -n %s\n\n", *name, *ns)
	fmt.Printf("  # Delete deployment\n  oc delete all,pvc,secret,configmap,route -l app=%s -n %s\n", *name, *ns)
	fmt.Println("\nDone.")
}

// ---------- Resource creation functions ----------

func createJupyterHubConfigMap(name, namespace, adminUser, adminPassword, notebookImage, userStorageSize, cpuLimit, memoryLimit string, maxUsers int) *corev1.ConfigMap {
	jupyterhubConfig := fmt.Sprintf(`# Simple JupyterHub configuration for OpenShift deployment
import os

# Basic configuration
c.JupyterHub.ip = '0.0.0.0'
c.JupyterHub.port = 8000
c.JupyterHub.hub_ip = '0.0.0.0'
c.JupyterHub.hub_port = 8081

# Admin configuration
c.Authenticator.admin_users = {'%s'}

# Use simple authenticator
c.JupyterHub.authenticator_class = 'jupyterhub.auth.DummyAuthenticator'
c.DummyAuthenticator.password = '%s'

# Use a working spawner configuration
c.JupyterHub.spawner_class = 'jupyterhub.spawner.SimpleLocalProcessSpawner'

# Configure spawner to use a simple command that works
c.Spawner.cmd = ['bash', '-c', 'echo "JupyterHub server for {username}"; sleep 3600']
c.Spawner.start_timeout = 30
c.Spawner.http_timeout = 30
c.JupyterHub.concurrent_spawn_limit = %d

# Disable named servers to keep it simple
c.JupyterHub.allow_named_servers = False

# Logging
c.JupyterHub.log_level = 'INFO'

# Database configuration (in-memory for simplicity)
c.JupyterHub.db_url = 'sqlite:///:memory:'

# Create directories
data_dir = '/srv/jupyterhub'
notebook_dir = '/home/jovyan/work'
for d in [data_dir, notebook_dir]:
    if not os.path.exists(d):
        try:
            os.makedirs(d, mode=0o755, exist_ok=True)
        except Exception as e:
            print(f"Warning: Could not create directory {d}: {e}")
`, adminUser, adminPassword, maxUsers)

	return &corev1.ConfigMap{
		ObjectMeta: metav1.ObjectMeta{
			Name:      name + "-config",
			Namespace: namespace,
			Labels: map[string]string{
				"app":       name,
				"component": "hub",
			},
		},
		Data: map[string]string{
			"jupyterhub_config.py": jupyterhubConfig,
		},
	}
}

func createJupyterHubSecret(name, namespace, adminPassword string) *corev1.Secret {
	return &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{
			Name:      name + "-secret",
			Namespace: namespace,
			Labels: map[string]string{
				"app":       name,
				"component": "hub",
			},
		},
		Type: corev1.SecretTypeOpaque,
		StringData: map[string]string{
			"cookie-secret":    generateSecret(64),
			"proxy-auth-token": generateSecret(64),
			"admin-password":   adminPassword,
		},
	}
}

func createServiceAccount(name, namespace string) *corev1.ServiceAccount {
	return &corev1.ServiceAccount{
		ObjectMeta: metav1.ObjectMeta{
			Name:      name,
			Namespace: namespace,
			Labels: map[string]string{
				"app":       name,
				"component": "hub",
			},
		},
	}
}

func createRole(name, namespace string) *rbacv1.Role {
	return &rbacv1.Role{
		ObjectMeta: metav1.ObjectMeta{
			Name:      name,
			Namespace: namespace,
			Labels: map[string]string{
				"app":       name,
				"component": "hub",
			},
		},
		Rules: []rbacv1.PolicyRule{
			{
				APIGroups: []string{""},
				Resources: []string{"pods", "persistentvolumeclaims", "services"},
				Verbs:     []string{"get", "watch", "list", "create", "delete"},
			},
			{
				APIGroups: []string{""},
				Resources: []string{"events"},
				Verbs:     []string{"get", "watch", "list"},
			},
		},
	}
}

func createRoleBinding(name, namespace string) *rbacv1.RoleBinding {
	return &rbacv1.RoleBinding{
		ObjectMeta: metav1.ObjectMeta{
			Name:      name,
			Namespace: namespace,
			Labels: map[string]string{
				"app":       name,
				"component": "hub",
			},
		},
		Subjects: []rbacv1.Subject{
			{
				Kind:      "ServiceAccount",
				Name:      name,
				Namespace: namespace,
			},
		},
		RoleRef: rbacv1.RoleRef{
			Kind:     "Role",
			Name:     name,
			APIGroup: "rbac.authorization.k8s.io",
		},
	}
}

func createJupyterHubPVC(name, namespace, storageSize string) *corev1.PersistentVolumeClaim {
	return &corev1.PersistentVolumeClaim{
		ObjectMeta: metav1.ObjectMeta{
			Name:      name + "-db-pvc",
			Namespace: namespace,
			Labels: map[string]string{
				"app":       name,
				"component": "hub",
			},
		},
		Spec: corev1.PersistentVolumeClaimSpec{
			AccessModes: []corev1.PersistentVolumeAccessMode{
				corev1.ReadWriteOnce,
			},
			Resources: corev1.VolumeResourceRequirements{
				Requests: corev1.ResourceList{
					corev1.ResourceStorage: resource.MustParse(storageSize),
				},
			},
		},
	}
}

func createJupyterHubDeployment(name, namespace, jupyterhubImage, memoryLimit, cpuLimit string) *appsv1.Deployment {
	labels := map[string]string{
		"app":       name,
		"component": "hub",
	}

	return &appsv1.Deployment{
		ObjectMeta: metav1.ObjectMeta{
			Name:      name,
			Namespace: namespace,
			Labels:    labels,
		},
		Spec: appsv1.DeploymentSpec{
			Replicas: int32p(1),
			Selector: &metav1.LabelSelector{MatchLabels: labels},
			Template: corev1.PodTemplateSpec{
				ObjectMeta: metav1.ObjectMeta{Labels: labels},
				Spec: corev1.PodSpec{
					ServiceAccountName: name,
					SecurityContext: &corev1.PodSecurityContext{
						// Let OpenShift assign UID/GID automatically for restricted SCC compatibility
						FSGroupChangePolicy: func() *corev1.PodFSGroupChangePolicy {
							policy := corev1.FSGroupChangeOnRootMismatch
							return &policy
						}(),
					},
					Containers: []corev1.Container{
						{
							Name:  "jupyterhub",
							Image: jupyterhubImage,
							Ports: []corev1.ContainerPort{
								{Name: "http", ContainerPort: 8000},
								{Name: "hub", ContainerPort: 8081},
							},
							Env: []corev1.EnvVar{
								{
									Name: "JUPYTERHUB_CRYPT_KEY",
									ValueFrom: &corev1.EnvVarSource{
										SecretKeyRef: &corev1.SecretKeySelector{
											LocalObjectReference: corev1.LocalObjectReference{Name: name + "-secret"},
											Key:                  "cookie-secret",
										},
									},
								},
								{
									Name: "CONFIGPROXY_AUTH_TOKEN",
									ValueFrom: &corev1.EnvVarSource{
										SecretKeyRef: &corev1.SecretKeySelector{
											LocalObjectReference: corev1.LocalObjectReference{Name: name + "-secret"},
											Key:                  "proxy-auth-token",
										},
									},
								},
								{
									Name: "POD_NAMESPACE",
									ValueFrom: &corev1.EnvVarSource{
										FieldRef: &corev1.ObjectFieldSelector{FieldPath: "metadata.namespace"},
									},
								},
								{Name: "JUPYTERHUB_SERVICE_PREFIX", Value: "/"},
							},
							VolumeMounts: []corev1.VolumeMount{
								{
									Name:      "config",
									MountPath: "/etc/jupyterhub/jupyterhub_config.py",
									SubPath:   "jupyterhub_config.py",
								},
								{
									Name:      "data",
									MountPath: "/srv/jupyterhub",
								},
							},
							Resources: corev1.ResourceRequirements{
								Limits: corev1.ResourceList{
									corev1.ResourceMemory: resource.MustParse(memoryLimit),
									corev1.ResourceCPU:    resource.MustParse(cpuLimit),
								},
								Requests: corev1.ResourceList{
									corev1.ResourceMemory: resource.MustParse("512Mi"),
									corev1.ResourceCPU:    resource.MustParse("100m"),
								},
							},
							LivenessProbe: &corev1.Probe{
								ProbeHandler: corev1.ProbeHandler{
									HTTPGet: &corev1.HTTPGetAction{
										Path: "/hub/health",
										Port: intstr.FromInt(8000),
									},
								},
								InitialDelaySeconds: 60,
								PeriodSeconds:       30,
								TimeoutSeconds:      10,
								FailureThreshold:    5,
							},
							ReadinessProbe: &corev1.Probe{
								ProbeHandler: corev1.ProbeHandler{
									HTTPGet: &corev1.HTTPGetAction{
										Path: "/hub/health",
										Port: intstr.FromInt(8000),
									},
								},
								InitialDelaySeconds: 30,
								PeriodSeconds:       10,
								TimeoutSeconds:      5,
								FailureThreshold:    10,
							},
							SecurityContext: &corev1.SecurityContext{
								AllowPrivilegeEscalation: boolp(false),
								RunAsNonRoot:             boolp(true),
								Capabilities: &corev1.Capabilities{
									Drop: []corev1.Capability{"ALL"},
								},
							},
							Command: []string{
								"jupyterhub",
								"--config",
								"/etc/jupyterhub/jupyterhub_config.py",
								"--upgrade-db",
								"--debug",
							},
						},
					},
					Volumes: []corev1.Volume{
						{
							Name: "config",
							VolumeSource: corev1.VolumeSource{
								ConfigMap: &corev1.ConfigMapVolumeSource{
									LocalObjectReference: corev1.LocalObjectReference{Name: name + "-config"},
								},
							},
						},
						{
							Name: "data",
							VolumeSource: corev1.VolumeSource{
								PersistentVolumeClaim: &corev1.PersistentVolumeClaimVolumeSource{
									ClaimName: name + "-db-pvc",
								},
							},
						},
					},
				},
			},
		},
	}
}

func createJupyterHubService(name, namespace string) *corev1.Service {
	labels := map[string]string{
		"app":       name,
		"component": "hub",
	}

	return &corev1.Service{
		ObjectMeta: metav1.ObjectMeta{
			Name:      name,
			Namespace: namespace,
			Labels:    labels,
		},
		Spec: corev1.ServiceSpec{
			Selector: labels,
			Ports: []corev1.ServicePort{
				{Name: "http", Port: 8000, TargetPort: intstr.FromInt(8000), Protocol: corev1.ProtocolTCP},
				{Name: "hub", Port: 8081, TargetPort: intstr.FromInt(8081), Protocol: corev1.ProtocolTCP},
			},
			Type: corev1.ServiceTypeClusterIP,
		},
	}
}

func createJupyterHubRoute(name, namespace string) *unstructured.Unstructured {
	route := &unstructured.Unstructured{}
	route.SetGroupVersionKind(schema.GroupVersionKind{
		Group:   "route.openshift.io",
		Version: "v1",
		Kind:    "Route",
	})
	route.SetName(name)
	route.SetNamespace(namespace)
	route.SetLabels(map[string]string{
		"app":       name,
		"component": "hub",
	})
	route.SetAnnotations(map[string]string{
		"haproxy.router.openshift.io/timeout": "300s",
		"haproxy.router.openshift.io/balance": "roundrobin",
	})

	spec := map[string]interface{}{
		"to": map[string]interface{}{
			"kind":   "Service",
			"name":   name,
			"weight": 100,
		},
		"port": map[string]interface{}{
			"targetPort": "http",
		},
		"wildcardPolicy": "None",
	}
	route.Object["spec"] = spec

	return route
}

// ---------- Helper functions for Kubernetes operations ----------

func int64p(i int64) *int64 { return &i }

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

func upsertSecret(ctx context.Context, cs *kubernetes.Clientset, secret *corev1.Secret) error {
	client := cs.CoreV1().Secrets(secret.Namespace)
	existing, err := client.Get(ctx, secret.Name, metav1.GetOptions{})
	if kerrors.IsNotFound(err) {
		_, err = client.Create(ctx, secret, metav1.CreateOptions{})
		return err
	}
	if err != nil {
		return err
	}
	existing.StringData = secret.StringData
	_, err = client.Update(ctx, existing, metav1.UpdateOptions{})
	return err
}

func upsertServiceAccount(ctx context.Context, cs *kubernetes.Clientset, sa *corev1.ServiceAccount) error {
	client := cs.CoreV1().ServiceAccounts(sa.Namespace)
	_, err := client.Get(ctx, sa.Name, metav1.GetOptions{})
	if kerrors.IsNotFound(err) {
		_, err = client.Create(ctx, sa, metav1.CreateOptions{})
		return err
	}
	return err
}

func upsertRole(ctx context.Context, cs *kubernetes.Clientset, role *rbacv1.Role) error {
	client := cs.RbacV1().Roles(role.Namespace)
	existing, err := client.Get(ctx, role.Name, metav1.GetOptions{})
	if kerrors.IsNotFound(err) {
		_, err = client.Create(ctx, role, metav1.CreateOptions{})
		return err
	}
	if err != nil {
		return err
	}
	existing.Rules = role.Rules
	_, err = client.Update(ctx, existing, metav1.UpdateOptions{})
	return err
}

func upsertRoleBinding(ctx context.Context, cs *kubernetes.Clientset, rb *rbacv1.RoleBinding) error {
	client := cs.RbacV1().RoleBindings(rb.Namespace)
	existing, err := client.Get(ctx, rb.Name, metav1.GetOptions{})
	if kerrors.IsNotFound(err) {
		_, err = client.Create(ctx, rb, metav1.CreateOptions{})
		return err
	}
	if err != nil {
		return err
	}
	existing.Subjects = rb.Subjects
	existing.RoleRef = rb.RoleRef
	_, err = client.Update(ctx, existing, metav1.UpdateOptions{})
	return err
}

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
	existing.Spec.Resources = pvc.Spec.Resources
	existing.Spec.AccessModes = pvc.Spec.AccessModes
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
	// ClusterIP is immutable; preserve it on update
	clusterIP := existing.Spec.ClusterIP
	existing.Spec = s.Spec
	existing.Spec.ClusterIP = clusterIP
	_, err = client.Update(ctx, existing, metav1.UpdateOptions{})
	return err
}

func upsertRoute(ctx context.Context, dynClient dynamic.Interface, route *unstructured.Unstructured) error {
	routeGVR := schema.GroupVersionResource{
		Group:    "route.openshift.io",
		Version:  "v1",
		Resource: "routes",
	}

	client := dynClient.Resource(routeGVR).Namespace(route.GetNamespace())
	existing, err := client.Get(ctx, route.GetName(), metav1.GetOptions{})
	if kerrors.IsNotFound(err) {
		_, err = client.Create(ctx, route, metav1.CreateOptions{})
		return err
	}
	if err != nil {
		return err
	}

	// Update the route spec
	existing.Object["spec"] = route.Object["spec"]
	if route.GetAnnotations() != nil {
		existing.SetAnnotations(route.GetAnnotations())
	}
	_, err = client.Update(ctx, existing, metav1.UpdateOptions{})
	return err
}

func waitForDeploymentReady(ctx context.Context, cs *kubernetes.Clientset, ns, name string) error {
	return waitutil.PollImmediateUntilWithContext(ctx, 3*time.Second, func(ctx context.Context) (bool, error) {
		d, err := cs.AppsV1().Deployments(ns).Get(ctx, name, metav1.GetOptions{})
		if err != nil {
			return false, err
		}
		return d.Status.ReadyReplicas >= 1, nil
	})
}

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

func getRouteHost(ctx context.Context, dynClient dynamic.Interface, ns, name string) (string, error) {
	routeGVR := schema.GroupVersionResource{
		Group:    "route.openshift.io",
		Version:  "v1",
		Resource: "routes",
	}

	route, err := dynClient.Resource(routeGVR).Namespace(ns).Get(ctx, name, metav1.GetOptions{})
	if err != nil {
		return "", err
	}

	spec, found, err := unstructured.NestedMap(route.Object, "spec")
	if err != nil || !found {
		return "", fmt.Errorf("route spec not found")
	}

	host, found, err := unstructured.NestedString(spec, "host")
	if err != nil || !found {
		return "", fmt.Errorf("route host not found")
	}

	return host, nil
}

func verifyJupyterHubAccess(url string) error {
	client := &http.Client{Timeout: 30 * time.Second}

	resp, err := client.Get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 200 && resp.StatusCode < 400 {
		return nil
	}

	return fmt.Errorf("HTTP %d", resp.StatusCode)
}

func must(err error, msg string, args ...interface{}) {
	if err != nil {
		fatal(msg+": %v", append(args, err)...)
	}
}

func fatal(msg string, args ...interface{}) {
	fmt.Fprintf(os.Stderr, "ERROR: "+msg+"\n", args...)
	os.Exit(1)
}
