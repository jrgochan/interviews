#!/bin/bash
# RHOS/OpenShift Setup Script for HPC Interview Examples
# Comprehensive setup for all HPC examples in OpenShift environment

set -e  # Exit on any error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
NAMESPACE="hpc-interview"
TIMEOUT_MINUTES=10
LOG_FILE="${SCRIPT_DIR}/setup.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "${LOG_FILE}"
}

echo -e "${BLUE}🚀 HPC Interview Environment Setup for RHOS/OpenShift${NC}"
echo -e "Project root: ${PROJECT_ROOT}"
echo -e "Script directory: ${SCRIPT_DIR}"
echo -e "Namespace: ${NAMESPACE}"
echo -e "Log file: ${LOG_FILE}"
echo

# Initialize log file
echo "=== HPC Interview Environment Setup - $(date) ===" > "${LOG_FILE}"

# Function to check prerequisites with detailed validation
check_prerequisites() {
    echo -e "${BLUE}📋 Comprehensive Prerequisites Check...${NC}"
    log "Starting prerequisites check"
    
    local has_errors=false
    
    # Check for required commands (docker is optional if podman is available)
    local required_commands=("podman" "oc" "git")
    local optional_commands=("docker")
    
    for cmd in "${required_commands[@]}"; do
        if command -v "$cmd" &> /dev/null; then
            echo -e "${GREEN}✅ $cmd found: $(command -v $cmd)${NC}"
            log "$cmd found at $(command -v $cmd)"
        else
            echo -e "${RED}❌ $cmd not found${NC}"
            log "ERROR: $cmd not found"
            has_errors=true
        fi
    done
    
    for cmd in "${optional_commands[@]}"; do
        if command -v "$cmd" &> /dev/null; then
            echo -e "${GREEN}✅ $cmd found: $(command -v $cmd)${NC}"
            log "$cmd found at $(command -v $cmd)"
        else
            echo -e "${YELLOW}⚠️  $cmd not found (optional - using podman)${NC}"
            log "WARNING: $cmd not found (optional)"
        fi
    done
    
    # Check Podman connectivity
    echo -e "${CYAN}Testing Podman connectivity...${NC}"
    if podman version &> /dev/null; then
        echo -e "${GREEN}✅ Podman is accessible${NC}"
        podman version --format "{{.Client.Version}}" | head -1
        log "Podman connectivity verified"
    else
        echo -e "${RED}❌ Cannot connect to Podman${NC}"
        echo -e "Run: podman machine start"
        log "ERROR: Podman connectivity failed"
        has_errors=true
    fi
    
    # Check OpenShift connectivity with detailed info
    echo -e "${CYAN}Testing OpenShift connectivity...${NC}"
    if oc status &> /dev/null; then
        echo -e "${GREEN}✅ Connected to OpenShift cluster${NC}"
        echo -e "${CYAN}Cluster info:${NC}"
        oc version --client
        oc whoami
        oc cluster-info | head -3
        log "OpenShift connectivity verified"
    else
        echo -e "${RED}❌ Cannot connect to OpenShift cluster${NC}"
        echo -e "${CYAN}Recovery options:${NC}"
        echo -e "  1. Start CRC cluster: ${YELLOW}crc start${NC}"
        echo -e "  2. Check cluster status: ${YELLOW}crc status${NC}"
        echo -e "  3. Login to cluster: ${YELLOW}oc login -u developer -p developer${NC}"
        echo -e "  4. Use start script: ${YELLOW}./start-openshift.sh${NC}"
        echo
        read -p "Would you like to continue setup after fixing OpenShift? [y/N]: " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}⚠️  Continuing setup - ensure OpenShift is available before proceeding${NC}"
            log "WARNING: OpenShift connectivity failed - user chose to continue"
        else
            echo -e "${RED}Setup cancelled. Fix OpenShift connectivity and try again.${NC}"
            log "ERROR: OpenShift connectivity failed - user cancelled"
            exit 1
        fi
    fi
    
    # Check system resources
    echo -e "${CYAN}System resource check...${NC}"
    if command -v free &> /dev/null; then
        free -h | head -2
    elif command -v vm_stat &> /dev/null; then
        echo "macOS memory info:"
        vm_stat | head -5
    fi
    
    if [ "$has_errors" = true ]; then
        echo -e "${RED}❌ Prerequisites check found critical errors${NC}"
        echo -e "${CYAN}Please fix the above errors and run the script again${NC}"
        log "ERROR: Prerequisites check failed"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Prerequisites check completed successfully${NC}"
    log "Prerequisites check completed successfully"
}

# Function to create and configure namespace
create_namespace() {
    echo -e "${BLUE}📦 Creating and configuring namespace: ${NAMESPACE}${NC}"
    log "Creating namespace: ${NAMESPACE}"
    
    if oc get namespace "${NAMESPACE}" &> /dev/null; then
        echo -e "${YELLOW}⚠️  Namespace ${NAMESPACE} already exists${NC}"
        echo -e "Checking existing resources..."
        oc get all -n "${NAMESPACE}" --no-headers | wc -l | xargs echo "Existing resources:"
        
        read -p "Delete and recreate namespace? [y/N]: " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}Deleting existing namespace...${NC}"
            oc delete namespace "${NAMESPACE}" --wait=true
            log "Deleted existing namespace"
        fi
    fi
    
    if ! oc get namespace "${NAMESPACE}" &> /dev/null; then
        oc create namespace "${NAMESPACE}"
        log "Created new namespace: ${NAMESPACE}"
    fi
    
    # Set namespace context
    oc project "${NAMESPACE}"
    
    # Configure namespace with resource quotas and limits
    cat <<EOF | oc apply -f -
apiVersion: v1
kind: ResourceQuota
metadata:
  name: hpc-quota
  namespace: ${NAMESPACE}
spec:
  hard:
    requests.cpu: "16"
    requests.memory: 32Gi
    limits.cpu: "32" 
    limits.memory: 64Gi
    pods: "20"
    persistentvolumeclaims: "10"
---
apiVersion: v1
kind: LimitRange
metadata:
  name: hpc-limits
  namespace: ${NAMESPACE}
spec:
  limits:
  - type: Container
    default:
      cpu: "2"
      memory: "4Gi"
    defaultRequest:
      cpu: "500m"
      memory: "1Gi"
    max:
      cpu: "8"
      memory: "16Gi"
EOF

    echo -e "${GREEN}✅ Namespace configured with resource quotas${NC}"
    log "Namespace configured successfully"
}

# Function to build container images using OpenShift BuildConfigs
build_images() {
    local modules_to_build="${1:-all}"
    echo -e "${BLUE}🔨 Building container images using OpenShift BuildConfigs...${NC}"
    log "Starting container image builds using OpenShift BuildConfigs"
    
    # Parse modules to build
    if [ "$modules_to_build" = "all" ]; then
        local build_base=true
        local build_aiml=true
        local build_milk=true
        echo -e "${CYAN}Building all modules: hpc-base, hpc-aiml, hpc-milk${NC}"
    else
        local build_base=false
        local build_aiml=false
        local build_milk=false
        
        IFS=',' read -ra MODULES <<< "$modules_to_build"
        for module in "${MODULES[@]}"; do
            case "$module" in
                base|hpc-base)
                    build_base=true
                    echo -e "${CYAN}Will build: hpc-base${NC}"
                    ;;
                aiml|hpc-aiml|ai)
                    build_aiml=true
                    echo -e "${CYAN}Will build: hpc-aiml${NC}"
                    ;;
                milk|hpc-milk)
                    build_milk=true
                    echo -e "${CYAN}Will build: hpc-milk${NC}"
                    ;;
                *)
                    echo -e "${RED}❌ Unknown module: $module${NC}"
                    echo -e "Available modules: base, aiml, milk"
                    exit 1
                    ;;
            esac
        done
        
        # If building dependent images, ensure base is built first
        if [ "$build_aiml" = true ] || [ "$build_milk" = true ]; then
            if [ "$build_base" = false ]; then
                echo -e "${YELLOW}⚠️  Dependent modules require hpc-base. Adding hpc-base to build list.${NC}"
                build_base=true
            fi
        fi
    fi
    
    # Build base image first (if selected)
    if [ "$build_base" = true ]; then
        build_single_image "hpc-base" "${SCRIPT_DIR}/containers/Containerfile.hpc-base"
    else
        echo -e "${YELLOW}⏭️  Skipping hpc-base build${NC}"
    fi
    
    # Build dependent images (if selected)
    if [ "$build_aiml" = true ]; then
        build_dependent_image "hpc-aiml" "${SCRIPT_DIR}/containers/Containerfile.aiml"
    else
        echo -e "${YELLOW}⏭️  Skipping hpc-aiml build${NC}"
    fi
    
    if [ "$build_milk" = true ]; then
        build_dependent_image "hpc-milk" "${SCRIPT_DIR}/containers/Containerfile.milk"
    else
        echo -e "${YELLOW}⏭️  Skipping hpc-milk build${NC}"
    fi
    
    echo -e "${GREEN}✅ Container image builds completed in OpenShift${NC}"
    log "Container builds completed in OpenShift"
}

# Function to build a single base image
build_single_image() {
    local image_name="$1"
    local dockerfile="$2"
    
    echo -e "${CYAN}Creating BuildConfig for ${image_name}...${NC}"
    log "Creating BuildConfig for image: ${image_name}"
    
    # Check if Containerfile exists
    if [ ! -f "${dockerfile}" ]; then
        echo -e "${RED}❌ Containerfile not found: ${dockerfile}${NC}"
        log "ERROR: Containerfile not found: ${dockerfile}"
        return 1
    fi
    
    # Create BuildConfig and ImageStream
    cat <<EOF | oc apply -f - -n "${NAMESPACE}"
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: ${image_name}
  labels:
    app: ${image_name}
spec:
  output:
    to:
      kind: ImageStreamTag
      name: ${image_name}:latest
  source:
    type: Binary
  strategy:
    type: Docker
    dockerStrategy:
      dockerfilePath: Dockerfile
  triggers: []
---
apiVersion: image.openshift.io/v1
kind: ImageStream
metadata:
  name: ${image_name}
  labels:
    app: ${image_name}
spec:
  lookupPolicy:
    local: true
EOF
    
    # Copy Containerfile to project root
    echo -e "${CYAN}Preparing build context for ${image_name}...${NC}"
    cp "${dockerfile}" "${PROJECT_ROOT}/Dockerfile"
    
    # Start build
    echo -e "${CYAN}Starting build for ${image_name}...${NC}"
    if ! oc start-build "${image_name}" --from-dir="${PROJECT_ROOT}" --follow --wait -n "${NAMESPACE}" > "${LOG_FILE}.${image_name}" 2>&1; then
        echo -e "${RED}❌ Failed to build ${image_name}${NC}"
        echo -e "Check log: ${LOG_FILE}.${image_name}"
        log "ERROR: Failed to build ${image_name}"
        return 1
    else
        echo -e "${GREEN}✅ ${image_name} built successfully in OpenShift${NC}"
        log "Successfully built ${image_name}"
    fi
}

# Function to build dependent images with internal registry base reference
build_dependent_image() {
    local image_name="$1"
    local dockerfile="$2"
    
    echo -e "${CYAN}Creating BuildConfig for ${image_name} (dependent)...${NC}"
    log "Creating BuildConfig for dependent image: ${image_name}"
    
    # Check if Containerfile exists
    if [ ! -f "${dockerfile}" ]; then
        echo -e "${RED}❌ Containerfile not found: ${dockerfile}${NC}"
        log "ERROR: Containerfile not found: ${dockerfile}"
        return 1
    fi
    
    # Create modified Containerfile with internal registry reference
    echo -e "${CYAN}Creating modified Containerfile for ${image_name}...${NC}"
    sed "s|FROM hpc-base:latest|FROM image-registry.openshift-image-registry.svc:5000/${NAMESPACE}/hpc-base:latest|g" \
        "${dockerfile}" > "${PROJECT_ROOT}/Dockerfile"
    
    # Create BuildConfig and ImageStream  
    cat <<EOF | oc apply -f - -n "${NAMESPACE}"
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: ${image_name}
  labels:
    app: ${image_name}
spec:
  output:
    to:
      kind: ImageStreamTag
      name: ${image_name}:latest
  source:
    type: Binary
  strategy:
    type: Docker
    dockerStrategy:
      dockerfilePath: Dockerfile
  triggers: []
---
apiVersion: image.openshift.io/v1
kind: ImageStream
metadata:
  name: ${image_name}
  labels:
    app: ${image_name}
spec:
  lookupPolicy:
    local: true
EOF
    
    # Start build
    echo -e "${CYAN}Starting build for ${image_name}...${NC}"
    if ! oc start-build "${image_name}" --from-dir="${PROJECT_ROOT}" --follow --wait -n "${NAMESPACE}" > "${LOG_FILE}.${image_name}" 2>&1; then
        echo -e "${RED}❌ Failed to build ${image_name}${NC}"
        echo -e "Check log: ${LOG_FILE}.${image_name}"
        log "ERROR: Failed to build ${image_name}"
        return 1
    else
        echo -e "${GREEN}✅ ${image_name} built successfully in OpenShift${NC}"
        log "Successfully built ${image_name}"
    fi
}

# Function to deploy OpenShift resources with verification
deploy_resources() {
    echo -e "${BLUE}🚀 Deploying OpenShift resources...${NC}"
    log "Starting OpenShift resource deployment"
    
    # Verify manifest files exist
    local manifest_dir="${SCRIPT_DIR}/manifests"
    if [ ! -d "${manifest_dir}" ]; then
        echo -e "${RED}❌ Manifests directory not found: ${manifest_dir}${NC}"
        log "ERROR: Manifests directory not found"
        exit 1
    fi
    
    # Count manifest files
    local manifest_count=$(find "${manifest_dir}" -name "*.yaml" -o -name "*.yml" | wc -l)
    echo -e "${CYAN}Found ${manifest_count} manifest files${NC}"
    log "Found ${manifest_count} manifest files"
    
    # Apply manifests
    echo -e "${CYAN}Applying manifests...${NC}"
    if ! oc apply -f "${manifest_dir}/" -n "${NAMESPACE}"; then
        echo -e "${RED}❌ Failed to apply manifests${NC}"
        log "ERROR: Failed to apply manifests"
        exit 1
    fi
    
    # Wait for deployments with progress tracking
    echo -e "${CYAN}Waiting for deployments to be ready (timeout: ${TIMEOUT_MINUTES}m)...${NC}"
    local deployments=$(oc get deployments -n "${NAMESPACE}" -o name)
    
    for deployment in $deployments; do
        echo -e "${CYAN}Waiting for ${deployment}...${NC}"
        if ! oc wait --for=condition=available "${deployment}" -n "${NAMESPACE}" --timeout="${TIMEOUT_MINUTES}m"; then
            echo -e "${YELLOW}⚠️  ${deployment} not ready within timeout${NC}"
            log "WARNING: ${deployment} not ready within timeout"
        else
            echo -e "${GREEN}✅ ${deployment} ready${NC}"
            log "${deployment} ready"
        fi
    done
    
    echo -e "${GREEN}✅ OpenShift resource deployment completed${NC}"
    log "OpenShift resource deployment completed"
}

# Function to build and setup all HPC examples
setup_all_examples() {
    echo -e "${BLUE}🛠️  Setting up all HPC examples...${NC}"
    log "Setting up all HPC examples"
    
    # Build MPI examples
    echo -e "${CYAN}Building MPI examples...${NC}"
    local mpi_pod=$(oc get pods -n "${NAMESPACE}" -l app=hpc-workspace -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -n "$mpi_pod" ]; then
        echo -e "Building MPI examples in pod: $mpi_pod"
        oc exec -it "$mpi_pod" -n "${NAMESPACE}" -- bash -c "
            cd /home/hpcuser/workspace/examples/mpi
            mkdir -p build && cd build
            cmake .. && make
            echo 'MPI examples built successfully'
        " || echo -e "${YELLOW}⚠️  MPI build failed - will retry in demo scripts${NC}"
        
        # Build MPI debugging examples
        oc exec -it "$mpi_pod" -n "${NAMESPACE}" -- bash -c "
            cd /home/hpcuser/workspace/examples/mpi_debugging
            mkdir -p build && cd build  
            cmake .. && make
            echo 'MPI debugging examples built successfully'
        " || echo -e "${YELLOW}⚠️  MPI debugging build failed - will retry in demo scripts${NC}"
        
        log "MPI examples setup completed"
    else
        echo -e "${YELLOW}⚠️  HPC workspace pod not found - examples will be built on first run${NC}"
        log "WARNING: HPC workspace pod not found"
    fi
    
    # Setup CUDA examples (if applicable)
    echo -e "${CYAN}Preparing CUDA examples...${NC}"
    if [ -f "${PROJECT_ROOT}/examples/cuda/CMakeLists.txt" ]; then
        echo -e "CUDA examples available (will be built with GPU support)"
        log "CUDA examples prepared"
    fi
    
    # Setup AI/ML examples
    echo -e "${CYAN}Preparing AI/ML examples...${NC}"
    local aiml_pod=$(oc get pods -n "${NAMESPACE}" -l app=aiml-workspace -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -n "$aiml_pod" ]; then
        echo -e "Verifying AI/ML environment in pod: $aiml_pod"
        oc exec -it "$aiml_pod" -n "${NAMESPACE}" -- bash -c "
            python3 -c 'import torch; print(f\"PyTorch {torch.__version__} available\")'
            python3 -c 'import reframe; print(f\"ReFrame {reframe.__version__} available\")'
            echo 'AI/ML environment verified'
        " || echo -e "${YELLOW}⚠️  AI/ML verification failed - will retry in demo scripts${NC}"
        
        log "AI/ML examples setup completed"
    fi
    
    # Make all example scripts executable
    echo -e "${CYAN}Making example scripts executable...${NC}"
    find "${SCRIPT_DIR}/examples" -name "*.sh" -exec chmod +x {} \;
    
    echo -e "${GREEN}✅ All HPC examples setup completed${NC}"
    log "All HPC examples setup completed"
}

# Function to perform comprehensive health checks
perform_health_checks() {
    echo -e "${BLUE}🔍 Performing comprehensive health checks...${NC}"
    log "Starting health checks"
    
    # Check namespace status
    echo -e "${CYAN}Namespace status:${NC}"
    oc get all -n "${NAMESPACE}"
    
    # Check resource usage
    echo -e "${CYAN}Resource usage:${NC}"
    oc top pods -n "${NAMESPACE}" 2>/dev/null || echo "Resource metrics not available yet"
    
    # Check pod logs for errors
    echo -e "${CYAN}Checking pod health...${NC}"
    local pods=$(oc get pods -n "${NAMESPACE}" -o name 2>/dev/null)
    
    for pod in $pods; do
        local pod_name="${pod##*/}"
        local pod_status=$(oc get "${pod}" -n "${NAMESPACE}" -o jsonpath='{.status.phase}')
        
        if [ "$pod_status" = "Running" ]; then
            echo -e "${GREEN}✅ ${pod_name}: ${pod_status}${NC}"
            log "Pod ${pod_name}: ${pod_status}"
        else
            echo -e "${YELLOW}⚠️  ${pod_name}: ${pod_status}${NC}"
            log "WARNING: Pod ${pod_name}: ${pod_status}"
            
            # Show recent logs if pod has issues
            echo -e "${CYAN}Recent logs for ${pod_name}:${NC}"
            oc logs "${pod}" -n "${NAMESPACE}" --tail=5 2>/dev/null || echo "No logs available"
        fi
    done
    
    # Check services and routes
    echo -e "${CYAN}Services status:${NC}"
    oc get svc -n "${NAMESPACE}" 2>/dev/null || echo "No services found"
    
    echo -e "${CYAN}Routes status:${NC}"
    oc get routes -n "${NAMESPACE}" 2>/dev/null || echo "No routes found"
    
    # Test basic functionality
    echo -e "${CYAN}Testing basic functionality...${NC}"
    local hpc_pod=$(oc get pods -n "${NAMESPACE}" -l app=hpc-workspace -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -n "$hpc_pod" ]; then
        echo -e "Testing MPI in pod: $hpc_pod"
        if oc exec "$hpc_pod" -n "${NAMESPACE}" -- mpirun --version &> /dev/null; then
            echo -e "${GREEN}✅ MPI functionality verified${NC}"
            log "MPI functionality verified"
        else
            echo -e "${YELLOW}⚠️  MPI test failed${NC}"
            log "WARNING: MPI test failed"
        fi
        
        echo -e "Testing Python environment..."
        if oc exec "$hpc_pod" -n "${NAMESPACE}" -- python3 --version &> /dev/null; then
            echo -e "${GREEN}✅ Python environment verified${NC}"
            log "Python environment verified"
        fi
    fi
    
    echo -e "${GREEN}✅ Health checks completed${NC}"
    log "Health checks completed"
}

# Function to setup monitoring and observability
setup_monitoring() {
    echo -e "${BLUE}📊 Setting up monitoring and observability...${NC}"
    log "Setting up monitoring"
    
    # Create a configmap for monitoring configuration
    cat <<EOF | oc apply -f - -n "${NAMESPACE}"
apiVersion: v1
kind: ConfigMap
metadata:
  name: hpc-monitoring-config
  labels:
    app: hpc-monitoring
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
    scrape_configs:
    - job_name: 'hpc-workloads'
      static_configs:
      - targets: ['localhost:9090']
  grafana.ini: |
    [server]
    http_port = 3000
    [security]
    admin_user = admin
    admin_password = admin
EOF

    # Create a simple monitoring service account
    cat <<EOF | oc apply -f - -n "${NAMESPACE}"
apiVersion: v1
kind: ServiceAccount
metadata:
  name: hpc-monitor
  namespace: ${NAMESPACE}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: hpc-monitor-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: view
subjects:
- kind: ServiceAccount
  name: hpc-monitor
  namespace: ${NAMESPACE}
EOF

    echo -e "${GREEN}✅ Monitoring setup completed${NC}"
    log "Monitoring setup completed"
}

# Function to validate all deployments
validate_deployments() {
    echo -e "${BLUE}✅ Validating all deployments...${NC}"
    log "Starting deployment validation"
    
    # Wait for all pods to be ready
    echo -e "${CYAN}Waiting for all pods to be ready...${NC}"
    local max_wait=300  # 5 minutes
    local wait_interval=10
    local elapsed=0
    
    while [ $elapsed -lt $max_wait ]; do
        local ready_pods=$(oc get pods -n "${NAMESPACE}" --field-selector=status.phase=Running --no-headers | wc -l)
        local total_pods=$(oc get pods -n "${NAMESPACE}" --no-headers | wc -l)
        
        echo -e "Ready: ${ready_pods}/${total_pods} pods"
        
        if [ "$ready_pods" -eq "$total_pods" ] && [ "$total_pods" -gt 0 ]; then
            echo -e "${GREEN}✅ All pods are ready${NC}"
            break
        fi
        
        sleep $wait_interval
        elapsed=$((elapsed + wait_interval))
    done
    
    # Final status check
    echo -e "${CYAN}Final deployment status:${NC}"
    oc get pods,svc,routes -n "${NAMESPACE}"
    
    # Test each major component
    echo -e "${CYAN}Component validation:${NC}"
    
    # Test HPC base environment
    local hpc_pod=$(oc get pods -n "${NAMESPACE}" -l app=hpc-workspace -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$hpc_pod" ]; then
        echo -e "HPC Base Environment:"
        oc exec "$hpc_pod" -n "${NAMESPACE}" -- bash -c "echo '  ✅ GCC:' && gcc --version | head -1" 2>/dev/null || echo "  ❌ GCC not available"
        oc exec "$hpc_pod" -n "${NAMESPACE}" -- bash -c "echo '  ✅ MPI:' && mpirun --version | head -1" 2>/dev/null || echo "  ❌ MPI not available"
        oc exec "$hpc_pod" -n "${NAMESPACE}" -- bash -c "echo '  ✅ Python:' && python3 --version" 2>/dev/null || echo "  ❌ Python not available"
    fi
    
    # Test AI/ML environment
    local aiml_pod=$(oc get pods -n "${NAMESPACE}" -l app=aiml-workspace -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$aiml_pod" ]; then
        echo -e "AI/ML Environment:"
        oc exec "$aiml_pod" -n "${NAMESPACE}" -- bash -c "python3 -c 'import torch; print(f\"  ✅ PyTorch: {torch.__version__}\")'" 2>/dev/null || echo "  ❌ PyTorch not available"
        oc exec "$aiml_pod" -n "${NAMESPACE}" -- bash -c "python3 -c 'import reframe; print(f\"  ✅ ReFrame: {reframe.__version__}\")'" 2>/dev/null || echo "  ❌ ReFrame not available"
    fi
    
    echo -e "${GREEN}✅ Deployment validation completed${NC}"
    log "Deployment validation completed"
}

# Function to display comprehensive usage information
display_usage() {
    echo
    echo -e "${GREEN}🎉 HPC Interview Environment Setup Complete!${NC}"
    echo
    echo -e "${BLUE}📊 Environment Summary:${NC}"
    echo -e "  Namespace: ${NAMESPACE}"
    echo -e "  Pods running: $(oc get pods -n "${NAMESPACE}" --field-selector=status.phase=Running --no-headers | wc -l)"
    echo -e "  Services: $(oc get svc -n "${NAMESPACE}" --no-headers | wc -l)"
    echo -e "  Routes: $(oc get routes -n "${NAMESPACE}" --no-headers 2>/dev/null | wc -l)"
    echo
    echo -e "${BLUE}🌐 Web Interfaces:${NC}"
    local jupyter_url=$(oc get route jupyter-route -n "${NAMESPACE}" -o jsonpath='{.spec.host}' 2>/dev/null || echo "Not deployed")
    local tensorboard_url=$(oc get route tensorboard-route -n "${NAMESPACE}" -o jsonpath='{.spec.host}' 2>/dev/null || echo "Not deployed")
    echo -e "  Jupyter: https://${jupyter_url}"
    echo -e "  TensorBoard: https://${tensorboard_url}"
    echo
    echo -e "${BLUE}📚 Available Demo Scripts:${NC}"
    echo
    echo -e "${YELLOW}🐛 MPI Debugging:${NC}"
    echo -e "  ${SCRIPT_DIR}/examples/run-mpi-debug.sh           # Deadlock & race condition demos"
    echo -e "  ${SCRIPT_DIR}/examples/run-mpi-debug.sh deadlock  # Specific deadlock demo"
    echo -e "  ${SCRIPT_DIR}/examples/run-mpi-debug.sh race      # Race condition demo"
    echo
    echo -e "${YELLOW}📊 Performance Testing:${NC}"
    echo -e "  ${SCRIPT_DIR}/examples/run-reframe-tests.sh       # Complete ReFrame test suite"
    echo -e "  ${SCRIPT_DIR}/examples/run-reframe-tests.sh basic # Basic functionality tests"
    echo
    echo -e "${YELLOW}🧠 AI/ML Training:${NC}"
    echo -e "  ${SCRIPT_DIR}/examples/run-aiml-demo.sh           # Distributed training demo"
    echo -e "  ${SCRIPT_DIR}/examples/run-aiml-demo.sh jupyter   # Start Jupyter notebook"
    echo
    echo -e "${YELLOW}🔬 Diffraction Analysis:${NC}"
    echo -e "  ${SCRIPT_DIR}/examples/run-milk-demo.sh           # MILK Rietveld analysis"
    echo -e "  ${SCRIPT_DIR}/examples/run-milk-demo.sh interactive # Interactive MILK session"
    echo -e "  ${SCRIPT_DIR}/examples/run-milk-demo.sh analysis  # Sample analysis workflow"
    echo
    echo -e "${YELLOW}🔧 Interactive Access:${NC}"
    echo -e "  ${SCRIPT_DIR}/examples/shell.sh                  # HPC environment shell"
    echo -e "  ${SCRIPT_DIR}/examples/shell.sh aiml             # AI/ML environment shell"
    echo -e "  ${SCRIPT_DIR}/examples/shell.sh milk             # MILK analysis environment"
    echo -e "  ${SCRIPT_DIR}/examples/simple-podman-test.sh     # Simple Podman testing"
    echo
    echo -e "${YELLOW}📈 Monitoring:${NC}"
    echo -e "  oc get pods -n ${NAMESPACE}                      # Check pod status"
    echo -e "  oc top pods -n ${NAMESPACE}                      # Resource usage"
    echo -e "  oc logs -f deployment/hpc-workspace -n ${NAMESPACE}   # Live logs"
    echo
    echo -e "${YELLOW}🧹 Cleanup:${NC}"
    echo -e "  ${SCRIPT_DIR}/cleanup.sh                         # Remove all resources"
    echo -e "  ${SCRIPT_DIR}/cleanup.sh namespace               # Remove just namespace"
    echo
    echo -e "${GREEN}🎯 Ready for comprehensive HPC interview demonstrations!${NC}"
    echo -e "${CYAN}💡 Pro tip: Start with './examples/shell.sh' for interactive exploration${NC}"
    
    # Save cluster access info
    cat > "${SCRIPT_DIR}/cluster-info.txt" << EOF
=== HPC Interview Environment Info ===
Generated: $(date)

OpenShift Cluster:
- API: https://api.crc.testing:6443
- Console: https://console-openshift-console.apps-crc.testing
- Namespace: ${NAMESPACE}

Login Commands:
oc login -u developer -p developer https://api.crc.testing:6443
oc project ${NAMESPACE}

Web Interfaces:
- Jupyter: https://${jupyter_url}
- TensorBoard: https://${tensorboard_url}

Demo Scripts:
- MPI Debugging: ${SCRIPT_DIR}/examples/run-mpi-debug.sh
- Performance Testing: ${SCRIPT_DIR}/examples/run-reframe-tests.sh  
- AI/ML Training: ${SCRIPT_DIR}/examples/run-aiml-demo.sh
- Interactive Shell: ${SCRIPT_DIR}/examples/shell.sh

Quick Start:
eval \$(crc oc-env)
oc project ${NAMESPACE}
${SCRIPT_DIR}/examples/shell.sh
EOF

    echo -e "${CYAN}📄 Cluster info saved to: ${SCRIPT_DIR}/cluster-info.txt${NC}"
    log "Setup completed successfully"
}

# Function to handle cleanup on errors
cleanup_on_error() {
    echo -e "${RED}❌ Setup failed. Cleaning up partial deployment...${NC}"
    log "ERROR: Setup failed, performing cleanup"
    
    if oc get namespace "${NAMESPACE}" &> /dev/null; then
        echo -e "${YELLOW}Removing namespace ${NAMESPACE}...${NC}"
        oc delete namespace "${NAMESPACE}" --wait=true &
    fi
    
    echo -e "${RED}Setup failed. Check log file: ${LOG_FILE}${NC}"
    exit 1
}

# Set up error handling
trap cleanup_on_error ERR

# Main execution function
main() {
    local modules_to_build="${1:-all}"
    log "Starting HPC Interview Environment Setup"
    
    echo -e "${CYAN}===== Phase 1: Prerequisites =====>${NC}"
    check_prerequisites
    
    echo -e "${CYAN}===== Phase 2: Namespace Setup =====${NC}"
    create_namespace
    
    echo -e "${CYAN}===== Phase 3: Container Images =====${NC}" 
    build_images "$modules_to_build"
    
    echo -e "${CYAN}===== Phase 4: OpenShift Resources =====${NC}"
    deploy_resources
    
    echo -e "${CYAN}===== Phase 5: HPC Examples =====${NC}"
    setup_all_examples
    
    echo -e "${CYAN}===== Phase 6: Monitoring =====${NC}"
    setup_monitoring
    
    echo -e "${CYAN}===== Phase 7: Health Checks =====${NC}"
    perform_health_checks
    
    echo -e "${CYAN}===== Phase 8: Final Configuration =====${NC}"
    validate_deployments
    
    echo -e "${CYAN}===== Setup Complete =====${NC}"
    display_usage
}

# Parse command line arguments
modules_to_build="all"
force_mode=false
quick_mode=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Sets up comprehensive HPC interview environment in RHOS/OpenShift"
            echo ""
            echo "Options:"
            echo "  --help, -h              Show this help message"
            echo "  --modules <modules>     Comma-separated list of modules to build"
            echo "                          Available: base, aiml, milk, all (default: all)"
            echo "  --force                 Force recreation of namespace and resources"
            echo "  --quick                 Skip health checks and validation"
            echo ""
            echo "Module Examples:"
            echo "  $0                                    # Build all modules (default)"
            echo "  $0 --modules milk                    # Build only MILK module"
            echo "  $0 --modules base,milk               # Build base and MILK modules"
            echo "  $0 --modules aiml --force            # Rebuild only AI/ML module"
            echo ""
            echo "Available Modules:"
            echo "  base     - HPC base environment (GCC, MPI, Python, tools)"
            echo "  aiml     - AI/ML environment (PyTorch, ReFrame, Jupyter)"
            echo "  milk     - MILK diffraction analysis (MAUD, Java, MILK library)"
            echo ""
            echo "Note: Dependent modules automatically include their dependencies."
            echo "      For example, 'milk' will also build 'base' if not already built."
            exit 0
            ;;
        --modules)
            modules_to_build="$2"
            shift 2
            ;;
        --force)
            force_mode=true
            shift
            ;;
        --quick)
            quick_mode=true
            shift
            ;;
        *)
            echo -e "${RED}❌ Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Set environment variables for legacy support
if [ "$force_mode" = true ]; then
    echo -e "${YELLOW}Force mode: Will delete existing namespace${NC}"
    export FORCE_RECREATE=true
fi

if [ "$quick_mode" = true ]; then
    echo -e "${YELLOW}Quick mode: Minimal validation${NC}"
    export QUICK_MODE=true
fi

# Execute main function with module selection
main "$modules_to_build"
