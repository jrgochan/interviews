# JupyterHub OpenShift Deployment Scripts

This directory contains robust, well-documented scripts for deploying JupyterHub to a local OpenShift cluster running on Podman on macOS.

## Overview

JupyterHub is a multi-user server for Jupyter notebooks that allows multiple users to access their own isolated notebook environments. This deployment is specifically configured for OpenShift with the following features:

- **KubeSpawner Integration**: Uses KubeSpawner to launch individual Jupyter notebook pods for each user
- **Persistent Storage**: Each user gets their own persistent volume for data persistence
- **OpenShift Security**: Configured to work with OpenShift's security context constraints
- **Auto-scaling**: Supports multiple concurrent users with resource limits
- **Idle Culling**: Automatically stops idle notebook servers to save resources

## Prerequisites

Before running these scripts, ensure you have:

1. **OpenShift Local (CRC)** installed and running:

   ```bash
   brew install crc
   crc setup
   crc start
   ```

2. **OpenShift CLI (oc)** installed:

   ```bash
   brew install openshift-cli
   ```

3. **Podman** installed and running:

   ```bash
   brew install podman
   podman machine init
   podman machine start
   ```

4. **Go** (for the Go implementation):

   ```bash
   brew install go
   ```

5. **Additional tools** (optional but recommended):

   ```bash
   brew install gettext  # for envsubst
   brew install openssl  # for generating secrets
   ```

## Scripts

### 1. Shell Script: `deploy-jupyterhub.zsh`

A comprehensive Zsh script that handles the complete deployment process.

#### Usage

```bash
# Make the script executable
chmod +x deploy-jupyterhub.zsh

# Basic deployment with defaults
./deploy-jupyterhub.zsh

# Custom configuration
./deploy-jupyterhub.zsh \
  --namespace jupyter-dev \
  --admin-user developer \
  --admin-password mypassword \
  --storage-size 20Gi \
  --memory-limit 4Gi \
  --max-users 20
```

#### Options

| Option | Default | Description |
|--------|---------|-------------|
| `-n, --namespace` | `jupyterhub` | Target namespace/project |
| `-a, --app-name` | `jupyterhub` | Application name |
| `--jupyterhub-image` | `quay.io/jupyterhub/jupyterhub:4.0` | JupyterHub container image |
| `--notebook-image` | `quay.io/jupyter/scipy-notebook:latest` | Default notebook image |
| `-u, --admin-user` | `admin` | Admin username |
| `-p, --admin-password` | *auto-generated* | Admin password |
| `--storage-size` | `10Gi` | Hub storage size |
| `--user-storage` | `5Gi` | User storage size |
| `--memory-limit` | `2Gi` | Memory limit per container |
| `--cpu-limit` | `1000m` | CPU limit per container |
| `--max-users` | `10` | Maximum concurrent users |
| `--idle-timeout` | `3600` | Idle timeout in seconds |
| `--cull-timeout` | `7200` | Cull timeout in seconds |

### 2. Go Implementation: `deploy_jupyterhub.go`

A Go-based implementation using the Kubernetes client-go library for more programmatic control.

#### Usage

```bash
# Download dependencies
go mod tidy

# Basic deployment
go run deploy_jupyterhub.go \
  --kubeconfig=$HOME/.kube/config \
  --namespace=jupyterhub \
  --admin-user=admin

# Custom configuration
go run deploy_jupyterhub.go \
  --namespace=jupyter-dev \
  --admin-user=developer \
  --storage-size=20Gi \
  --memory-limit=4Gi \
  --max-users=20
```

#### Options

| Option | Default | Description |
|--------|---------|-------------|
| `--namespace` | `jupyterhub` | Target namespace |
| `--name` | `jupyterhub` | Base name for all objects |
| `--kubeconfig` | `$HOME/.kube/config` | Path to kubeconfig |
| `--jupyterhub-image` | `quay.io/jupyterhub/jupyterhub:4.0` | JupyterHub image |
| `--notebook-image` | `quay.io/jupyter/scipy-notebook:latest` | Default notebook image |
| `--admin-user` | `admin` | Admin username |
| `--admin-password` | *auto-generated* | Admin password |
| `--storage-size` | `10Gi` | Hub storage size |
| `--user-storage-size` | `5Gi` | User storage size |
| `--memory-limit` | `2Gi` | Memory limit |
| `--cpu-limit` | `1000m` | CPU limit |
| `--max-users` | `10` | Maximum concurrent users |
| `--timeout` | `10m` | Overall timeout |

## Deployment Architecture

The deployment creates the following Kubernetes/OpenShift resources:

### Core Resources

1. **Namespace/Project**: Isolated environment for JupyterHub
2. **ConfigMap**: JupyterHub configuration including KubeSpawner settings
3. **Secret**: Authentication tokens and admin credentials
4. **ServiceAccount**: Service account for JupyterHub pod
5. **Role/RoleBinding**: RBAC permissions for spawning user pods
6. **PersistentVolumeClaim**: Storage for JupyterHub database
7. **Deployment**: JupyterHub application deployment
8. **Service**: Internal service for pod communication
9. **Route**: External access via OpenShift router

### Generated Manifests

The shell script generates Kubernetes manifests in the `./manifests` directory:

```
manifests/
├── configmap.yaml       # JupyterHub configuration
├── secret.yaml          # Authentication secrets
├── rbac.yaml            # ServiceAccount, Role, RoleBinding
├── pvc.yaml             # Persistent storage
├── deployment.yaml      # JupyterHub deployment
├── service.yaml         # Internal service
├── route.yaml           # External route
├── kustomization.yaml   # Kustomize configuration
└── jupyterhub_config.py # JupyterHub Python configuration
```

## Configuration Details

### JupyterHub Configuration

The deployment uses a custom `jupyterhub_config.py` with:

- **DummyAuthenticator**: Simple password-based authentication for local development
- **KubeSpawner**: Spawns user notebooks as separate pods
- **Persistent Storage**: Each user gets a dedicated PVC
- **Resource Limits**: CPU and memory limits per user
- **Idle Culling**: Automatic cleanup of idle notebooks
- **OpenShift Security**: Compatible with restricted security context constraints

### Security Context

Configured for OpenShift's restricted SCC:

- Non-root user execution
- Random UID assignment
- Proper volume permissions via FSGroup
- No privilege escalation

### Networking

- **Hub Port**: 8000 (HTTP interface)
- **Internal Port**: 8081 (Hub-spawner communication)
- **External Access**: Via OpenShift Route (HTTP)

## Post-Deployment

### Accessing JupyterHub

After successful deployment, JupyterHub will be accessible at:

```
http://<app-name>.<namespace>.apps-crc.testing
```

### Default Credentials

- **Username**: `admin` (or custom value)
- **Password**: Auto-generated (displayed during deployment)

### User Management

1. Login as admin
2. Go to Control Panel → Admin
3. Add users manually or configure external authentication

### Monitoring

```bash
# View logs
oc logs -f deployment/jupyterhub -n jupyterhub

# Check pod status
oc get pods -n jupyterhub

# View user notebooks
oc get pods -n jupyterhub -l component=singleuser-server

# Check storage
oc get pvc -n jupyterhub
```

## Troubleshooting

### Common Issues

1. **Pod Startup Issues**

   ```bash
   # Check events
   oc get events -n jupyterhub --sort-by='.lastTimestamp'
   
   # Check pod logs
   oc logs deployment/jupyterhub -n jupyterhub
   ```

2. **Storage Issues**

   ```bash
   # Check PVC status
   oc get pvc -n jupyterhub
   
   # Check storage class
   oc get storageclass
   ```

3. **Network Issues**

   ```bash
   # Check route
   oc get route -n jupyterhub
   
   # Check service endpoints
   oc get endpoints -n jupyterhub
   ```

4. **Permission Issues**

   ```bash
   # Check RBAC
   oc get role,rolebinding -n jupyterhub
   
   # Check service account
   oc get sa -n jupyterhub
   ```

### Cleanup

To remove the entire deployment:

```bash
# Using labels (recommended)
oc delete all,pvc,secret,configmap,route -l app=jupyterhub -n jupyterhub

# Or delete the entire namespace
oc delete project jupyterhub
```

## Customization

### Custom Notebook Images

Modify the `--notebook-image` parameter to use different base images:

```bash
# Data science stack
--notebook-image quay.io/jupyter/datascience-notebook:latest

# Minimal notebook
--notebook-image quay.io/jupyter/minimal-notebook:latest

# Custom image
--notebook-image your-registry.com/custom-notebook:latest
```

### Resource Scaling

Adjust resources based on your needs:

```bash
# High-resource deployment
./deploy-jupyterhub.zsh \
  --memory-limit 8Gi \
  --cpu-limit 4000m \
  --storage-size 100Gi \
  --user-storage 20Gi \
  --max-users 50
```

### Authentication

For production use, consider replacing DummyAuthenticator with:

- LDAP/Active Directory
- OAuth (GitHub, Google, etc.)
- SAML
- Custom authenticators

## Development

### Extending the Scripts

Both scripts are designed to be extensible:

1. **Shell Script**: Modify variables and add new manifest templates
2. **Go Script**: Add new resource creation functions and command-line flags

### Testing

Test the deployment in different scenarios:

```bash
# Test with minimal resources
./deploy-jupyterhub.zsh --memory-limit 512Mi --cpu-limit 250m

# Test with multiple users
./deploy-jupyterhub.zsh --max-users 5

# Test cleanup and redeploy
oc delete all,pvc,secret,configmap,route -l app=jupyterhub -n jupyterhub
./deploy-jupyterhub.zsh
```

## References

- [JupyterHub Documentation](https://jupyterhub.readthedocs.io/)
- [KubeSpawner Documentation](https://jupyterhub-kubespawner.readthedocs.io/)
- [OpenShift Documentation](https://docs.openshift.com/)
- [Kubernetes Client-Go](https://github.com/kubernetes/client-go)

## License

This project follows the same license as the parent repository.
