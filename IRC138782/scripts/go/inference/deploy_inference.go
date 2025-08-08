package main

import (
	"context"
	"flag"
	"fmt"
	"path/filepath"
	"time"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	intstr "k8s.io/apimachinery/pkg/util/intstr"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"
)

func int32Ptr(i int32) *int32 { return &i }

func main() {
	// Parse kubeconfig flag
	home := filepath.Join("~", ".kube", "config")
	kubeconfig := flag.String("kubeconfig", filepath.Clean(home), "absolute path to kubeconfig file")
	namespace := flag.String("namespace", "default", "namespace to deploy into")
	flag.Parse()

	// Build config from kubeconfig
	config, err := clientcmd.BuildConfigFromFlags("", *kubeconfig)
	if err != nil {
		panic(err)
	}

	// Create Kubernetes client
	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		panic(err)
	}

	ctx := context.Background()

	// --------------------
	// 1. Create ConfigMap
	// --------------------
	configMap := &corev1.ConfigMap{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "model-config",
			Namespace: *namespace,
		},
		Data: map[string]string{
			"MODEL_NAME": "resnet50",
			"MODEL_PATH": "/models/resnet50",
			"BATCH_SIZE": "16",
		},
	}

	fmt.Println("Creating ConfigMap...")
	_, err = clientset.CoreV1().ConfigMaps(*namespace).Create(ctx, configMap, metav1.CreateOptions{})
	if err != nil {
		panic(err)
	}
	fmt.Println("✅ ConfigMap created.")

	// --------------------
	// 2. Create Deployment
	// --------------------
	labels := map[string]string{"app": "ai-inference"}

	deployment := &appsv1.Deployment{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "ai-inference-deploy",
			Namespace: *namespace,
		},
		Spec: appsv1.DeploymentSpec{
			Replicas: int32Ptr(1),
			Selector: &metav1.LabelSelector{MatchLabels: labels},
			Template: corev1.PodTemplateSpec{
				ObjectMeta: metav1.ObjectMeta{Labels: labels},
				Spec: corev1.PodSpec{
					Containers: []corev1.Container{
						{
							Name:  "inference-server",
							Image: "python:3.11-slim", // In real life: GPU-enabled AI inference image
							Command: []string{"python", "-m", "http.server", "8080"},
							Env: []corev1.EnvVar{
								{Name: "MODEL_NAME", ValueFrom: &corev1.EnvVarSource{
									ConfigMapKeyRef: &corev1.ConfigMapKeySelector{
										LocalObjectReference: corev1.LocalObjectReference{Name: "model-config"},
										Key:                  "MODEL_NAME",
									},
								}},
								{Name: "MODEL_PATH", ValueFrom: &corev1.EnvVarSource{
									ConfigMapKeyRef: &corev1.ConfigMapKeySelector{
										LocalObjectReference: corev1.LocalObjectReference{Name: "model-config"},
										Key:                  "MODEL_PATH",
									},
								}},
								{Name: "BATCH_SIZE", ValueFrom: &corev1.EnvVarSource{
									ConfigMapKeyRef: &corev1.ConfigMapKeySelector{
										LocalObjectReference: corev1.LocalObjectReference{Name: "model-config"},
										Key:                  "BATCH_SIZE",
									},
								}},
							},
							Ports: []corev1.ContainerPort{
								{Name: "http", ContainerPort: 8080},
							},
						},
					},
				},
			},
		},
	}

	fmt.Println("Creating Deployment...")
	_, err = clientset.AppsV1().Deployments(*namespace).Create(ctx, deployment, metav1.CreateOptions{})
	if err != nil {
		panic(err)
	}
	fmt.Println("✅ Deployment created.")

	// --------------------
	// 3. Create Service
	// --------------------
	service := &corev1.Service{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "ai-inference-service",
			Namespace: *namespace,
		},
		Spec: corev1.ServiceSpec{
			Selector: labels,
			Ports: []corev1.ServicePort{
				{
					Port:       80,
					TargetPort: intstr.FromInt(8080),
					Protocol:   corev1.ProtocolTCP,
				},
			},
			Type: corev1.ServiceTypeNodePort,
		},
	}

	fmt.Println("Creating Service...")
	_, err = clientset.CoreV1().Services(*namespace).Create(ctx, service, metav1.CreateOptions{})
	if err != nil {
		panic(err)
	}
	fmt.Println("✅ Service created.")

	fmt.Println("🎯 AI Inference service deployed successfully.")
	time.Sleep(2 * time.Second)
}

