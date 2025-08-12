#!/usr/bin/env zsh
set -euo pipefail

# =========================
# JupyterHub OpenShift Deployment Script
# =========================
# This script deploys JupyterHub to a local OpenShift cluster running on Podman.
# It creates all necessary resources including:
# - Namespace/Project
# - ConfigMaps for JupyterHub configuration
# - PersistentVolumeClaims for user data persistence
# - Deployment with JupyterHub container
# - Services for internal communication
# - Routes for external access
# - RBAC resources for proper permissions
#
# Prerequisites:
# - OpenShift cluster running (CRC or similar)
# - oc CLI tool installed and configured
# - podman installed and running
#
# Usage:
#   ./deploy-jupyterhub.zsh [options]
#
# Examples:
#   # Basic deployment
#   ./deploy-jupyterhub.zsh
#
#   # Custom namespace and admin user
#   ./deploy-jupyterhub.zsh -n jupyter-dev -u admin -p mypassword
#
#   # With custom storage size
#   ./deploy-jupyterhub.zsh --storage-size 20Gi
#
# =========================

# =========================
# Helpers & Defaults
# =========================
info() { print -P "%F{cyan}==>%f $*"; }
ok()   { print -P "%F{green}✔%f $*"; }
warn() { print -P "%F{yellow}WARNING:%f $*"; }
err()  { print -P "%F{red}ERROR:%f $*" >&2; }

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "Missing '$1'. Please install it and re-run."
    case "$1" in
      podman)  print "  macOS: brew install podman" ;;
      oc)      print "  macOS: brew install openshift-cli" ;;
      crc)     print "  macOS: brew install crc   # optional; for OpenShift Local" ;;
      envsubst) print "  macOS: brew install gettext # provides envsubst" ;;
      openssl) print "  macOS: brew install openssl # for generating secrets" ;;
    esac
    exit 1
  fi
}

have() { command -v "$1" >/dev/null 2>&1; }

# Generate a random string for secrets
generate_secret() {
  local length=${1:-32}
  if have openssl; then
    openssl rand -hex "$length"
  else
    # Fallback using /dev/urandom
    LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c "$length"
  fi
}

# Defaults (override with env or flags)
: "${NAMESPACE:=jupyterhub}"
: "${MANIFESTS:=./manifests}"
: "${APP_NAME:=jupyterhub}"
: "${JUPYTERHUB_IMAGE:=quay.io/jupyterhub/jupyterhub:4.0}"
: "${NOTEBOOK_IMAGE:=quay.io/jupyter/scipy-notebook:latest}"
: "${ADMIN_USER:=admin}"
: "${ADMIN_PASSWORD:=}"
: "${STORAGE_SIZE:=10Gi}"
: "${MEMORY_LIMIT:=2Gi}"
: "${CPU_LIMIT:=1000m}"
: "${USER_STORAGE_SIZE:=5Gi}"
: "${MAX_USERS:=10}"
: "${IDLE_TIMEOUT:=3600}"
: "${CULL_TIMEOUT:=7200}"

usage() {
  cat <<'EOF'
Usage: ./deploy-jupyterhub.zsh [options]

Options (env var overrides in parentheses):
  -n <namespace>      Target namespace/project (NAMESPACE) [default: jupyterhub]
  -m <path>           Manifests dir (MANIFESTS) [default: ./manifests]
  -a <app-name>       App name (APP_NAME) [default: jupyterhub]
  --jupyterhub-image  JupyterHub container image (JUPYTERHUB_IMAGE)
  --notebook-image    Default notebook image (NOTEBOOK_IMAGE)
  -u <username>       Admin username (ADMIN_USER) [default: admin]
  -p <password>       Admin password (ADMIN_PASSWORD) [auto-generated if empty]
  --storage-size      Hub storage size (STORAGE_SIZE) [default: 10Gi]
  --user-storage      User storage size (USER_STORAGE_SIZE) [default: 5Gi]
  --memory-limit      Memory limit per container (MEMORY_LIMIT) [default: 2Gi]
  --cpu-limit         CPU limit per container (CPU_LIMIT) [default: 1000m]
  --max-users         Maximum concurrent users (MAX_USERS) [default: 10]
  --idle-timeout      Idle timeout in seconds (IDLE_TIMEOUT) [default: 3600]
  --cull-timeout      Cull timeout in seconds (CULL_TIMEOUT) [default: 7200]
  -h                  Show help

Environment Variables:
  All options can be set via environment variables (shown in parentheses above).

Examples:
  # Basic deployment with defaults
  ./deploy-jupyterhub.zsh

  # Custom namespace and admin credentials
  ./deploy-jupyterhub.zsh -n jupyter-dev -u myuser -p mypassword

  # High-resource deployment
  ./deploy-jupyterhub.zsh --memory-limit 4Gi --cpu-limit 2000m --storage-size 50Gi

  # Development setup with custom images
  ./deploy-jupyterhub.zsh --jupyterhub-image jupyterhub/jupyterhub:dev --notebook-image jupyter/datascience-notebook:latest
EOF
}

# =========================
# Parse args
# =========================
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n) NAMESPACE="$2"; shift 2;;
    -m) MANIFESTS="$2"; shift 2;;
    -a) APP_NAME="$2"; shift 2;;
    --jupyterhub-image) JUPYTERHUB_IMAGE="$2"; shift 2;;
    --notebook-image) NOTEBOOK_IMAGE="$2"; shift 2;;
    -u) ADMIN_USER="$2"; shift 2;;
    -p) ADMIN_PASSWORD="$2"; shift 2;;
    --storage-size) STORAGE_SIZE="$2"; shift 2;;
    --user-storage) USER_STORAGE_SIZE="$2"; shift 2;;
    --memory-limit) MEMORY_LIMIT="$2"; shift 2;;
    --cpu-limit) CPU_LIMIT="$2"; shift 2;;
    --max-users) MAX_USERS="$2"; shift 2;;
    --idle-timeout) IDLE_TIMEOUT="$2"; shift 2;;
    --cull-timeout) CULL_TIMEOUT="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) err "Unknown arg: $1"; usage; exit 2;;
  esac
done

# =========================
# Preflight checks
# =========================
info "Starting JupyterHub deployment to OpenShift..."

need podman
need oc
have gettext || need envsubst

# Generate admin password if not provided
if [[ -z "${ADMIN_PASSWORD}" ]]; then
  ADMIN_PASSWORD="$(generate_secret 16)"
  warn "Generated admin password: ${ADMIN_PASSWORD}"
  warn "Save this password - it will be needed to access JupyterHub!"
fi

# Ensure Podman machine is reachable (macOS/Windows)
if podman info >/dev/null 2>&1; then
  ok "Podman daemon reachable."
else
  info "Podman not reachable. Ensuring podman machine is running..."
  if podman machine list 2>/dev/null | grep -q 'Running'; then
    ok "Podman machine is running."
  else
    if podman machine list 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -q .; then
      DEFAULT_MACHINE=$(podman machine list | awk 'NR==2 {print $1}')
      info "Starting podman machine '$DEFAULT_MACHINE'..."
      podman machine start "$DEFAULT_MACHINE"
    else
      info "No podman machine found. Initializing and starting default machine..."
      podman machine init
      podman machine start
    fi
    ok "Podman machine started."
  fi
fi

# CRC (OpenShift Local) check
CRC_AVAILABLE=false
if have crc; then
  CRC_AVAILABLE=true
  if crc status 2>/dev/null | grep -q "OpenShift: .*Running"; then
    ok "OpenShift Local is running."
  else
    info "Starting OpenShift Local (this can take several minutes)..."
    crc start
    ok "OpenShift Local started."
  fi
  if crc oc-env >/dev/null 2>&1; then
    info "Evaluating 'crc oc-env' to wire oc and KUBECONFIG..."
    eval "$(crc oc-env)"
  fi
fi

# Login check
if oc whoami >/dev/null 2>&1; then
  ok "Already logged into: $(oc whoami --show-server)"
else
  info "Please login to your cluster:"
  oc login --insecure-skip-tls-verify
  ok "Logged in as $(oc whoami)."
fi

# Namespace
if oc get ns "${NAMESPACE}" >/dev/null 2>&1; then
  info "Namespace '${NAMESPACE}' exists; switching..."
else
  info "Creating namespace '${NAMESPACE}'..."
  oc new-project "${NAMESPACE}" >/dev/null
fi
oc project "${NAMESPACE}" >/dev/null
ok "Using namespace: ${NAMESPACE}"

# =========================
# Create manifests directory
# =========================
info "Creating manifests directory..."
mkdir -p "${MANIFESTS}"

# =========================
# Generate JupyterHub configuration
# =========================
info "Generating JupyterHub configuration..."

# Create jupyterhub_config.py
cat > "${MANIFESTS}/jupyterhub_config.py" <<EOF
# JupyterHub configuration for OpenShift deployment
import os
from kubespawner import KubeSpawner
from oauthenticator.generic import GenericOAuthenticator

# Basic configuration
c.JupyterHub.ip = '0.0.0.0'
c.JupyterHub.port = 8000
c.JupyterHub.hub_ip = '0.0.0.0'

# Database configuration (using SQLite for simplicity)
c.JupyterHub.db_url = 'sqlite:///jupyterhub.sqlite'

# Admin configuration
c.Authenticator.admin_users = {'${ADMIN_USER}'}

# Use simple authenticator for local development
c.JupyterHub.authenticator_class = 'jupyterhub.auth.DummyAuthenticator'
c.DummyAuthenticator.password = '${ADMIN_PASSWORD}'

# Spawner configuration for Kubernetes/OpenShift
c.JupyterHub.spawner_class = KubeSpawner

# Kubernetes/OpenShift spawner settings
c.KubeSpawner.namespace = '${NAMESPACE}'
c.KubeSpawner.image = '${NOTEBOOK_IMAGE}'
c.KubeSpawner.cpu_limit = ${CPU_LIMIT//m/} / 1000.0
c.KubeSpawner.mem_limit = '${MEMORY_LIMIT}'
c.KubeSpawner.storage_capacity = '${USER_STORAGE_SIZE}'

# Storage configuration
c.KubeSpawner.pvc_name_template = 'claim-{username}'
c.KubeSpawner.volume_mounts = [
    {
        'name': 'volume-{username}',
        'mountPath': '/home/jovyan/work'
    }
]
c.KubeSpawner.volumes = [
    {
        'name': 'volume-{username}',
        'persistentVolumeClaim': {
            'claimName': 'claim-{username}'
        }
    }
]

# Security context for OpenShift
c.KubeSpawner.uid = None  # Let OpenShift assign UID
c.KubeSpawner.gid = None  # Let OpenShift assign GID
c.KubeSpawner.fs_gid = None

# Service account
c.KubeSpawner.service_account = '${APP_NAME}'

# Networking
c.KubeSpawner.hub_connect_ip = '${APP_NAME}'
c.KubeSpawner.hub_connect_port = 8081

# Timeouts and limits
c.Spawner.start_timeout = 300
c.Spawner.http_timeout = 120
c.JupyterHub.concurrent_spawn_limit = ${MAX_USERS}

# Culling configuration
c.JupyterHub.services = [
    {
        'name': 'cull-idle',
        'admin': True,
        'command': [
            'python3', '-m', 'jupyterhub_idle_culler',
            '--timeout=${IDLE_TIMEOUT}',
            '--cull-every=300',
            '--max-age=${CULL_TIMEOUT}'
        ],
    }
]

# Logging
c.JupyterHub.log_level = 'INFO'
c.Spawner.debug = True

# Allow named servers (optional)
c.JupyterHub.allow_named_servers = True
c.JupyterHub.named_server_limit_per_user = 2
EOF

# =========================
# Generate Kubernetes manifests
# =========================
info "Generating Kubernetes manifests..."

# Generate secrets
COOKIE_SECRET=$(generate_secret 32)
PROXY_AUTH_TOKEN=$(generate_secret 32)

# ConfigMap for JupyterHub configuration
cat > "${MANIFESTS}/configmap.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${APP_NAME}-config
  namespace: ${NAMESPACE}
  labels:
    app: ${APP_NAME}
    component: hub
data:
  jupyterhub_config.py: |
$(sed 's/^/    /' "${MANIFESTS}/jupyterhub_config.py")
EOF

# Secret for JupyterHub
cat > "${MANIFESTS}/secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${APP_NAME}-secret
  namespace: ${NAMESPACE}
  labels:
    app: ${APP_NAME}
    component: hub
type: Opaque
stringData:
  cookie-secret: "${COOKIE_SECRET}"
  proxy-auth-token: "${PROXY_AUTH_TOKEN}"
  admin-password: "${ADMIN_PASSWORD}"
EOF

# ServiceAccount and RBAC
cat > "${MANIFESTS}/rbac.yaml" <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${APP_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: ${APP_NAME}
    component: hub
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ${APP_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: ${APP_NAME}
    component: hub
rules:
- apiGroups: [""]
  resources: ["pods", "persistentvolumeclaims", "services"]
  verbs: ["get", "watch", "list", "create", "delete"]
- apiGroups: [""]
  resources: ["events"]
  verbs: ["get", "watch", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${APP_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: ${APP_NAME}
    component: hub
subjects:
- kind: ServiceAccount
  name: ${APP_NAME}
  namespace: ${NAMESPACE}
roleRef:
  kind: Role
  name: ${APP_NAME}
  apiGroup: rbac.authorization.k8s.io
EOF

# PersistentVolumeClaim for JupyterHub database
cat > "${MANIFESTS}/pvc.yaml" <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${APP_NAME}-db-pvc
  namespace: ${NAMESPACE}
  labels:
    app: ${APP_NAME}
    component: hub
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: ${STORAGE_SIZE}
EOF

# Deployment
cat > "${MANIFESTS}/deployment.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: ${APP_NAME}
    component: hub
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${APP_NAME}
      component: hub
  template:
    metadata:
      labels:
        app: ${APP_NAME}
        component: hub
    spec:
      serviceAccountName: ${APP_NAME}
      securityContext:
        fsGroup: 1000
        runAsUser: 1000
        runAsGroup: 1000
      containers:
      - name: jupyterhub
        image: ${JUPYTERHUB_IMAGE}
        ports:
        - containerPort: 8000
          name: http
        - containerPort: 8081
          name: hub
        env:
        - name: JUPYTERHUB_CRYPT_KEY
          valueFrom:
            secretKeyRef:
              name: ${APP_NAME}-secret
              key: cookie-secret
        - name: CONFIGPROXY_AUTH_TOKEN
          valueFrom:
            secretKeyRef:
              name: ${APP_NAME}-secret
              key: proxy-auth-token
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        - name: JUPYTERHUB_SERVICE_PREFIX
          value: "/"
        volumeMounts:
        - name: config
          mountPath: /srv/jupyterhub/jupyterhub_config.py
          subPath: jupyterhub_config.py
        - name: data
          mountPath: /srv/jupyterhub
        resources:
          limits:
            memory: ${MEMORY_LIMIT}
            cpu: ${CPU_LIMIT}
          requests:
            memory: 512Mi
            cpu: 100m
        livenessProbe:
          httpGet:
            path: /hub/health
            port: 8000
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
        readinessProbe:
          httpGet:
            path: /hub/health
            port: 8000
          initialDelaySeconds: 10
          periodSeconds: 5
          timeoutSeconds: 3
        command:
        - jupyterhub
        - --config
        - /srv/jupyterhub/jupyterhub_config.py
        - --upgrade-db
      volumes:
      - name: config
        configMap:
          name: ${APP_NAME}-config
      - name: data
        persistentVolumeClaim:
          claimName: ${APP_NAME}-db-pvc
EOF

# Service
cat > "${MANIFESTS}/service.yaml" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: ${APP_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: ${APP_NAME}
    component: hub
spec:
  selector:
    app: ${APP_NAME}
    component: hub
  ports:
  - name: http
    port: 8000
    targetPort: 8000
    protocol: TCP
  - name: hub
    port: 8081
    targetPort: 8081
    protocol: TCP
  type: ClusterIP
EOF

# Route for external access
cat > "${MANIFESTS}/route.yaml" <<EOF
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: ${APP_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: ${APP_NAME}
    component: hub
  annotations:
    haproxy.router.openshift.io/timeout: "300s"
    haproxy.router.openshift.io/balance: "roundrobin"
spec:
  to:
    kind: Service
    name: ${APP_NAME}
    weight: 100
  port:
    targetPort: http
  wildcardPolicy: None
EOF

# Kustomization file
cat > "${MANIFESTS}/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: ${NAMESPACE}

resources:
- configmap.yaml
- secret.yaml
- rbac.yaml
- pvc.yaml
- deployment.yaml
- service.yaml
- route.yaml

commonLabels:
  app: ${APP_NAME}
  version: "4.0"
  managed-by: "deploy-jupyterhub-script"
EOF

# =========================
# Apply manifests
# =========================
info "Applying Kubernetes manifests..."
oc apply -f "${MANIFESTS}"

# =========================
# Wait for deployment
# =========================
info "Waiting for JupyterHub deployment to be ready..."
oc rollout status deployment/${APP_NAME} -n ${NAMESPACE} --timeout=600s

# =========================
# Get route information
# =========================
info "Getting route information..."
ROUTE_HOST=$(oc get route ${APP_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

if [[ -n "${ROUTE_HOST}" ]]; then
  JUPYTERHUB_URL="http://${ROUTE_HOST}"
  ok "JupyterHub is accessible at: ${JUPYTERHUB_URL}"
else
  warn "Could not determine route host. Check route manually:"
  oc get route ${APP_NAME} -n ${NAMESPACE}
fi

# =========================
# Display status and next steps
# =========================
info "Deployment Status:"
oc get pods -n ${NAMESPACE} -l app=${APP_NAME}

info "Services:"
oc get svc -n ${NAMESPACE} -l app=${APP_NAME}

info "Routes:"
oc get route -n ${NAMESPACE} -l app=${APP_NAME}

info "Storage:"
oc get pvc -n ${NAMESPACE} -l app=${APP_NAME}

# =========================
# Final instructions
# =========================
ok "JupyterHub deployment completed successfully!"
echo
info "Access Information:"
echo "  URL: ${JUPYTERHUB_URL:-'Check route manually'}"
echo "  Admin Username: ${ADMIN_USER}"
echo "  Admin Password: ${ADMIN_PASSWORD}"
echo
info "Next Steps:"
echo "  1. Access JupyterHub at the URL above"
echo "  2. Login with the admin credentials"
echo "  3. Create additional users as needed"
echo "  4. Users will get persistent storage automatically"
echo
info "Management Commands:"
echo "  # View logs"
echo "  oc logs -f deployment/${APP_NAME} -n ${NAMESPACE}"
echo
echo "  # Scale deployment"
echo "  oc scale deployment/${APP_NAME} --replicas=1 -n ${NAMESPACE}"
echo
echo "  # Delete deployment"
echo "  oc delete all,pvc,secret,configmap,route -l app=${APP_NAME} -n ${NAMESPACE}"
echo
echo "  # Access JupyterHub shell"
echo "  oc exec -it deployment/${APP_NAME} -n ${NAMESPACE} -- /bin/bash"

ok "Done."
