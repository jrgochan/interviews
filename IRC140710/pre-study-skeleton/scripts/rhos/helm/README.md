# Helm Charts for RHOS HPC Modules

This directory contains Helm charts for deploying HPC interview modules in OpenShift/Kubernetes environments. The charts provide a more structured, versioned, and parameterized approach to deploying the HPC modules compared to raw YAML manifests.

## 📋 Overview

### Available Helm Charts

| Chart | Description | Dependencies |
|-------|-------------|--------------|
| `shared-resources` | Shared persistent volumes for all HPC modules | None |
| `hpc-base` | Base HPC environment (GCC, MPI, Python, debugging tools) | `shared-resources` |
| `hpc-aiml` | AI/ML environment (PyTorch, Jupyter, TensorBoard, ReFrame) | `shared-resources` |
| `hpc-midas` | MIDAS data acquisition system (PSI/TRIUMF, ROOT, web interface) | `shared-resources` |
| `hpc-milk` | MILK diffraction analysis (MAUD, Java integration) | `shared-resources` |

### Key Features

- **Parameterized Deployments**: Customizable through values files
- **Dependency Management**: Automatic resolution of chart dependencies
- **Version Control**: Semantic versioning for charts and releases
- **OpenShift Integration**: Native support for Routes and SecurityContextConstraints
- **Rollback Support**: Easy rollback to previous versions
- **Template Validation**: Built-in template validation and dry-run capabilities

## 🚀 Quick Start

### Prerequisites

```bash
# Required tools
brew install helm
# or
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify installation
helm version
oc version    # or kubectl version
```

### Deploy All Modules

```bash
# Deploy all modules with dependencies
./deploy.sh deploy --all --wait

# Deploy with custom namespace
./deploy.sh deploy --all --namespace my-hpc-env
```

### Deploy Specific Modules

```bash
# Deploy just the AI/ML module (includes shared-resources automatically)
./deploy.sh deploy --module hpc-aiml --wait

# Deploy multiple specific modules
./deploy.sh deploy --module hpc-midas,hpc-milk --wait
```

## 📚 Detailed Usage

### Deployment Script Commands

The `deploy.sh` script provides comprehensive management capabilities:

#### Deploy Command

```bash
# Basic deployment
./deploy.sh deploy --module <module>

# Deploy with custom values
./deploy.sh deploy --module hpc-aiml --values custom-aiml-values.yaml

# Dry run (validate without deploying)
./deploy.sh deploy --module hpc-base --dry-run

# Force reinstallation
./deploy.sh deploy --module hpc-midas --force

# Deploy and wait for readiness
./deploy.sh deploy --all --wait --timeout 15
```

#### Management Commands

```bash
# List deployed modules
./deploy.sh list

# Show detailed status
./deploy.sh status --module hpc-aiml

# Uninstall modules
./deploy.sh uninstall --module hpc-milk

# Uninstall all modules
./deploy.sh uninstall --all
```

### Manual Helm Commands

For advanced users who prefer direct Helm usage:

```bash
# Deploy shared resources first
helm upgrade --install shared-resources ./shared-resources \
  --namespace hpc-interview --create-namespace

# Deploy HPC base module
helm upgrade --install hpc-base ./hpc-base \
  --namespace hpc-interview

# Deploy AI/ML module with custom values
helm upgrade --install hpc-aiml ./hpc-aiml \
  --namespace hpc-interview \
  --values my-custom-values.yaml

# Check deployment status
helm status hpc-aiml --namespace hpc-interview

# View generated manifests
helm template hpc-base ./hpc-base

# Rollback to previous version
helm rollback hpc-aiml 1 --namespace hpc-interview
```

## ⚙️ Configuration

### Custom Values Files

Each chart can be customized using values files. Here are examples:

#### Custom HPC-Base Values

```yaml
# custom-hpc-base.yaml
namespace: my-custom-namespace

resources:
  requests:
    memory: "1Gi"
    cpu: "1000m"
  limits:
    memory: "4Gi"
    cpu: "4000m"

env:
  - name: CUSTOM_VAR
    value: "custom_value"

additionalLabels:
  environment: "production"
  team: "hpc"
```

#### Custom AI/ML Values

```yaml
# custom-aiml.yaml
resources:
  requests:
    memory: "2Gi"
    cpu: "2000m"
  limits:
    memory: "8Gi"
    cpu: "4000m"

routes:
  jupyter:
    enabled: true
    tls:
      termination: edge
  tensorboard:
    enabled: false

env:
  - name: JUPYTER_TOKEN
    value: "my-secure-token"
```

#### Custom Storage Values

```yaml
# custom-storage.yaml
storage:
  workspace:
    size: 20Gi
    storageClass: "fast-ssd"
  data:
    size: 10Gi
    storageClass: "standard"
```

### Environment-Specific Deployments

```bash
# Development environment
./deploy.sh deploy --all --values environments/dev-values.yaml

# Production environment  
./deploy.sh deploy --all --values environments/prod-values.yaml --wait --timeout 20

# Testing environment with minimal resources
./deploy.sh deploy --module hpc-base --values environments/test-values.yaml
```

## 📁 Chart Structure

Each chart follows the standard Helm structure:

```
hpc-<module>/
├── Chart.yaml              # Chart metadata and dependencies
├── values.yaml             # Default configuration values
├── templates/              # Kubernetes manifest templates
│   ├── _helpers.tpl        # Template helpers and functions
│   ├── deployment.yaml     # Main deployment template
│   ├── service.yaml        # Service template
│   └── route.yaml          # OpenShift route template (if applicable)
└── charts/                 # Dependency charts (if any)
```

### Template Functions

Each chart includes helper functions for consistent naming:

```yaml
# Example usage in templates
metadata:
  name: {{ include "hpc-base.deploymentName" . }}
  labels:
    {{- include "hpc-base.labels" . | nindent 4 }}
```

## 🔧 Development and Customization

### Adding New Charts

1. **Create Chart Structure**

   ```bash
   helm create hpc-newmodule
   cd hpc-newmodule
   ```

2. **Update Chart.yaml**

   ```yaml
   apiVersion: v2
   name: hpc-newmodule
   description: New HPC module description
   version: 0.1.0
   dependencies:
     - name: shared-resources
       version: "0.1.0"
       repository: "file://../shared-resources"
   ```

3. **Configure Values**

   ```yaml
   # values.yaml
   namespace: hpc-interview
   image:
     repository: image-registry.openshift-image-registry.svc:5000/hpc-interview/hpc-newmodule
     tag: "latest"
   ```

4. **Update Deploy Script**

   ```bash
   # Add to AVAILABLE_MODULES array in deploy.sh
   AVAILABLE_MODULES=("shared-resources" "hpc-base" "hpc-aiml" "hpc-midas" "hpc-milk" "hpc-newmodule")
   ```

### Testing Charts

```bash
# Validate chart syntax
helm lint ./hpc-base

# Test template rendering
helm template test-release ./hpc-base --debug

# Dry run deployment
./deploy.sh deploy --module hpc-base --dry-run

# Install in test namespace
helm upgrade --install test-hpc-base ./hpc-base \
  --namespace hpc-test --create-namespace \
  --dry-run
```

## 🚨 Troubleshooting

### Common Issues

#### Chart Not Found

```bash
Error: chart not found: ./hpc-base
```

**Solution**: Ensure you're running from the `scripts/rhos/helm` directory

#### Dependency Issues

```bash
Error: dependency "shared-resources" not found
```

**Solution**: Deploy shared-resources first or use `./deploy.sh` which handles dependencies

#### Template Errors

```bash
Error: template: hpc-base/templates/deployment.yaml:10:15: executing "hpc-base/templates/deployment.yaml"
```

**Solution**: Check template syntax and values file format

#### Permission Issues

```bash
Error: configmaps is forbidden: User "system:serviceaccount:..." cannot create resource "configmaps"
```

**Solution**: Ensure proper RBAC permissions or use OpenShift admin account

### Debugging Commands

```bash
# View generated manifests
helm template hpc-aiml ./hpc-aiml --values debug-values.yaml

# Get detailed release information
helm get all hpc-aiml --namespace hpc-interview

# View Helm release history
helm history hpc-base --namespace hpc-interview

# Check pod logs
oc logs -f deployment/hpc-workspace -n hpc-interview

# Describe resources for issues
oc describe pod -l app=hpc-workspace -n hpc-interview
```

### Recovery Procedures

#### Failed Deployment

```bash
# Check what went wrong
helm status failed-release --namespace hpc-interview

# Rollback to previous working version
helm rollback failed-release 1 --namespace hpc-interview

# Force reinstall
./deploy.sh deploy --module failed-module --force
```

#### Clean Environment

```bash
# Remove all releases
./deploy.sh uninstall --all

# Clean up remaining resources
oc delete namespace hpc-interview

# Start fresh
./deploy.sh deploy --all --wait
```

## 🔄 Migration from Raw Manifests

If migrating from the raw YAML manifests in `../manifests/`:

### Migration Steps

1. **Export Current Configuration**

   ```bash
   # Save current configurations
   oc get deployment hpc-workspace -o yaml > backup-hpc-workspace.yaml
   oc get deployment aiml-workspace -o yaml > backup-aiml-workspace.yaml
   ```

2. **Uninstall Raw Manifests**

   ```bash
   oc delete -f ../manifests/ -n hpc-interview
   ```

3. **Deploy Using Helm**

   ```bash
   ./deploy.sh deploy --all --wait
   ```

4. **Verify Migration**

   ```bash
   ./deploy.sh status
   oc get pods -n hpc-interview
   ```

### Configuration Mapping

| Raw Manifest | Helm Chart | Values Path |
|--------------|------------|-------------|
| `hpc-workspace-deployment.yaml` | `hpc-base` | `deployment.name` |
| `aiml-deployment.yaml` | `hpc-aiml` | `deployment.name` |
| `midas-deployment.yaml` | `hpc-midas` | `deployment.name` |
| `milk-deployment.yaml` | `hpc-milk` | `deployment.name` |
| `shared-workspace-pvc.yaml` | `shared-resources` | `storage.workspace` |

## 📈 Monitoring and Observability

### Deployment Metrics

```bash
# View resource usage
oc top pods -n hpc-interview

# Check deployment status
helm list --all-namespaces

# View events
oc get events -n hpc-interview --sort-by='.lastTimestamp'
```

### Log Aggregation

```bash
# Stream logs from all pods
oc logs -f -l component=interview-demo -n hpc-interview

# Get logs from specific module
oc logs -f deployment/hpc-workspace -n hpc-interview
```

## 🔐 Security Considerations

### RBAC and Permissions

- Charts use `runAsNonRoot: true` security context
- OpenShift Routes use TLS termination by default
- Secrets should be managed externally (not in values files)

### Image Security

```yaml
# Use specific image tags (not 'latest') in production
image:
  repository: registry.redhat.io/ubi8/ubi
  tag: "8.7-1049"
  pullPolicy: IfNotPresent
```

### Network Policies

```yaml
# Example network policy (add to templates if needed)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: hpc-network-policy
spec:
  podSelector:
    matchLabels:
      app: hpc-workspace
  policyTypes:
  - Ingress
  - Egress
```

## 📊 Performance Optimization

### Resource Tuning

```yaml
# Production resource recommendations
resources:
  requests:
    memory: "2Gi"
    cpu: "1000m"
  limits:
    memory: "8Gi"
    cpu: "4000m"
```

### Storage Performance

```yaml
# Use high-performance storage classes
storage:
  workspace:
    storageClass: "fast-ssd"
    size: 50Gi
  data:
    storageClass: "standard"
    size: 100Gi
```

## 🤝 Contributing

1. **Test Changes**

   ```bash
   helm lint ./your-chart
   ./deploy.sh deploy --module your-chart --dry-run
   ```

2. **Update Documentation**
   - Update this README for new features
   - Add examples for new configuration options
   - Update the main RHOS README

3. **Version Management**
   - Increment chart versions in `Chart.yaml`
   - Use semantic versioning (MAJOR.MINOR.PATCH)
   - Update appVersion when container images change

## 📞 Support

For issues and questions:

1. **Check Logs**: Use the debugging commands above
2. **Validate Configuration**: Use `helm lint` and dry-run options  
3. **Review Documentation**: Check this README and official Helm docs
4. **Test in Isolation**: Deploy individual modules to isolate issues

---

**Happy Helming! 🎉**

For more information about Helm, visit: <https://helm.sh/docs/>
