#!/bin/bash
# Troubleshooting script for hpc-base build issues in OpenShift/CRC
# This script addresses common build failures and provides alternative solutions

set -e

# Configuration
NAMESPACE="hpc-interview"
BUILD_NAME="hpc-base"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CONTAINERFILE="${SCRIPT_DIR}/containers/Containerfile.hpc-base"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logging
log() {
    echo -e "${BLUE}$(date '+%H:%M:%S')${NC} - $*"
}

error() {
    echo -e "${RED}$(date '+%H:%M:%S') ERROR${NC} - $*" >&2
}

success() {
    echo -e "${GREEN}$(date '+%H:%M:%S') SUCCESS${NC} - $*"
}

warn() {
    echo -e "${YELLOW}$(date '+%H:%M:%S') WARNING${NC} - $*"
}

info() {
    echo -e "${CYAN}$(date '+%H:%M:%S') INFO${NC} - $*"
}

# Function to cleanup existing builds and buildconfig
cleanup_existing_build() {
    log "Cleaning up existing builds and buildconfig..."
    
    # Cancel any running builds
    for build in $(oc get builds -n "${NAMESPACE}" -o name 2>/dev/null | grep "${BUILD_NAME}" || true); do
        warn "Cancelling ${build}"
        oc cancel-build "${build##*/}" -n "${NAMESPACE}" 2>/dev/null || true
    done
    
    # Wait for builds to be cancelled
    sleep 5
    
    # Delete buildconfig
    if oc get buildconfig "${BUILD_NAME}" -n "${NAMESPACE}" &>/dev/null; then
        log "Deleting existing BuildConfig"
        oc delete buildconfig "${BUILD_NAME}" -n "${NAMESPACE}"
    fi
    
    # Delete imagestream
    if oc get imagestream "${BUILD_NAME}" -n "${NAMESPACE}" &>/dev/null; then
        log "Deleting existing ImageStream"
        oc delete imagestream "${BUILD_NAME}" -n "${NAMESPACE}"
    fi
    
    success "Cleanup completed"
}

# Function to check cluster resources
check_cluster_resources() {
    log "Checking cluster resources..."
    
    # Check node status
    local node_status=$(oc get nodes --no-headers | head -1 | awk '{print $2}')
    if [ "$node_status" != "Ready" ]; then
        error "Node is not Ready: $node_status"
        return 1
    fi
    
    # Check available resources
    info "Node status: $node_status"
    
    # Check if there are resource constraints
    local quota_info=$(oc get resourcequota -n "${NAMESPACE}" --no-headers 2>/dev/null || echo "no quota")
    info "Resource quota: $quota_info"
    
    # Check running pods
    local pod_count=$(oc get pods -n "${NAMESPACE}" --no-headers 2>/dev/null | wc -l)
    info "Currently running pods in namespace: $pod_count"
    
    return 0
}

# Function to create optimized BuildConfig
create_optimized_buildconfig() {
    log "Creating optimized BuildConfig for CRC environment..."
    
    cat <<EOF | oc apply -f - -n "${NAMESPACE}"
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: ${BUILD_NAME}
  labels:
    app: ${BUILD_NAME}
spec:
  output:
    to:
      kind: ImageStreamTag
      name: ${BUILD_NAME}:latest
  source:
    type: Binary
  strategy:
    type: Docker
    dockerStrategy:
      dockerfilePath: Dockerfile
  resources:
    requests:
      cpu: 100m
      memory: 512Mi
    limits:
      cpu: 2
      memory: 4Gi
  nodeSelector:
    kubernetes.io/os: linux
  triggers: []
---
apiVersion: image.openshift.io/v1
kind: ImageStream
metadata:
  name: ${BUILD_NAME}
  labels:
    app: ${BUILD_NAME}
spec:
  lookupPolicy:
    local: true
EOF

    success "BuildConfig and ImageStream created"
}

# Function to start build with better monitoring
start_monitored_build() {
    local max_wait=1800  # 30 minutes
    local check_interval=30
    local elapsed=0
    
    log "Starting monitored build..."
    
    # Prepare Dockerfile
    if [ ! -f "${CONTAINERFILE}" ]; then
        error "Containerfile not found: ${CONTAINERFILE}"
        return 1
    fi
    
    cp "${CONTAINERFILE}" "${PROJECT_ROOT}/Dockerfile"
    
    # Start build
    log "Initiating build from directory: ${PROJECT_ROOT}"
    oc start-build "${BUILD_NAME}" --from-dir="${PROJECT_ROOT}" -n "${NAMESPACE}" &
    local build_pid=$!
    
    # Wait a moment for build to be created
    sleep 10
    
    # Get the build number
    local build_number=$(oc get builds -n "${NAMESPACE}" -l buildconfig="${BUILD_NAME}" --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}' 2>/dev/null || echo "")
    
    if [ -z "$build_number" ]; then
        error "Could not determine build number"
        return 1
    fi
    
    info "Monitoring build: $build_number"
    
    # Monitor build progress
    while [ $elapsed -lt $max_wait ]; do
        local build_status=$(oc get build "$build_number" -n "${NAMESPACE}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        local pod_status=$(oc get pods -n "${NAMESPACE}" -l openshift.io/build.name="$build_number" -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
        
        info "Build: $build_status | Pod: $pod_status | Elapsed: ${elapsed}s"
        
        case "$build_status" in
            "Complete")
                success "Build completed successfully!"
                return 0
                ;;
            "Failed"|"Error"|"Cancelled")
                error "Build failed with status: $build_status"
                log "Checking build logs..."
                oc logs build/"$build_number" -n "${NAMESPACE}" || true
                return 1
                ;;
            "New"|"Pending"|"Running")
                # Check if pod is stuck in Pending
                if [ "$pod_status" = "Pending" ]; then
                    if [ $elapsed -gt 300 ]; then  # 5 minutes
                        warn "Build pod stuck in Pending state for >5 minutes"
                        log "Pod details:"
                        oc describe pod -l openshift.io/build.name="$build_number" -n "${NAMESPACE}" | tail -20 || true
                    fi
                fi
                ;;
        esac
        
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done
    
    error "Build timeout after ${max_wait} seconds"
    return 1
}

# Function to try podman build as fallback
try_podman_fallback() {
    log "Attempting Podman fallback build..."
    
    if ! command -v podman &> /dev/null; then
        warn "Podman not available - cannot use fallback"
        return 1
    fi
    
    # Build locally with podman
    log "Building image locally with Podman..."
    if ! podman build -f "${CONTAINERFILE}" -t "${BUILD_NAME}:latest" "${PROJECT_ROOT}"; then
        error "Podman build failed"
        return 1
    fi
    
    # Get OpenShift registry route
    local registry_route=$(oc get route default-route -n openshift-image-registry -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
    
    if [ -z "$registry_route" ]; then
        warn "OpenShift registry route not available - creating one..."
        oc patch configs.imageregistry.operator.openshift.io/cluster --patch '{"spec":{"defaultRoute":true}}' --type=merge
        sleep 30
        registry_route=$(oc get route default-route -n openshift-image-registry -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
    fi
    
    if [ -n "$registry_route" ]; then
        # Tag and push to OpenShift registry
        local target_image="${registry_route}/${NAMESPACE}/${BUILD_NAME}:latest"
        log "Pushing to OpenShift registry: $target_image"
        
        # Get token for push
        local token=$(oc whoami -t)
        if podman login -u kubeadmin -p "$token" "$registry_route" --tls-verify=false; then
            podman tag "${BUILD_NAME}:latest" "$target_image"
            if podman push "$target_image" --tls-verify=false; then
                success "Successfully pushed image using Podman fallback"
                
                # Create ImageStream if it doesn't exist
                if ! oc get imagestream "${BUILD_NAME}" -n "${NAMESPACE}" &>/dev/null; then
                    log "Creating ImageStream..."
                    oc create imagestream "${BUILD_NAME}" -n "${NAMESPACE}"
                fi
                
                return 0
            fi
        fi
    fi
    
    error "Podman fallback failed"
    return 1
}

# Function to create minimal test deployment to verify the image works
test_build_result() {
    log "Testing build result with minimal deployment..."
    
    cat <<EOF | oc apply -f - -n "${NAMESPACE}"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${BUILD_NAME}-test
  labels:
    app: ${BUILD_NAME}-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${BUILD_NAME}-test
  template:
    metadata:
      labels:
        app: ${BUILD_NAME}-test
    spec:
      containers:
      - name: test-container
        image: image-registry.openshift-image-registry.svc:5000/${NAMESPACE}/${BUILD_NAME}:latest
        command: ["/bin/sh", "-c", "echo 'HPC Base image test successful' && sleep 30"]
        resources:
          requests:
            cpu: 100m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 1Gi
      restartPolicy: Always
EOF

    log "Waiting for test deployment..."
    if oc wait --for=condition=available deployment/${BUILD_NAME}-test -n "${NAMESPACE}" --timeout=300s; then
        success "Test deployment successful - image is working"
        
        # Show test logs
        local test_pod=$(oc get pods -n "${NAMESPACE}" -l app=${BUILD_NAME}-test -o jsonpath='{.items[0].metadata.name}')
        if [ -n "$test_pod" ]; then
            log "Test pod logs:"
            oc logs "$test_pod" -n "${NAMESPACE}"
        fi
        
        # Cleanup test deployment
        oc delete deployment ${BUILD_NAME}-test -n "${NAMESPACE}"
        return 0
    else
        error "Test deployment failed"
        return 1
    fi
}

# Main execution
main() {
    log "Starting HPC Base Build Fix Script"
    log "Namespace: ${NAMESPACE}"
    log "Build Name: ${BUILD_NAME}"
    log "Containerfile: ${CONTAINERFILE}"
    echo
    
    # Step 1: Check prerequisites
    if ! oc whoami &>/dev/null; then
        error "Not logged into OpenShift"
        exit 1
    fi
    
    if ! oc get namespace "${NAMESPACE}" &>/dev/null; then
        error "Namespace ${NAMESPACE} does not exist"
        exit 1
    fi
    
    # Step 2: Check cluster resources
    if ! check_cluster_resources; then
        error "Cluster resource check failed"
        exit 1
    fi
    
    # Step 3: Cleanup existing build artifacts
    cleanup_existing_build
    
    # Step 4: Create optimized build configuration
    create_optimized_buildconfig
    
    # Step 5: Attempt monitored build
    if start_monitored_build; then
        success "OpenShift build completed successfully!"
        
        # Step 6: Test the result
        if test_build_result; then
            success "Build verification completed - hpc-base is ready!"
            exit 0
        else
            warn "Build completed but verification failed"
            exit 1
        fi
    else
        warn "OpenShift build failed - attempting Podman fallback..."
        
        # Step 5b: Try Podman fallback
        if try_podman_fallback; then
            if test_build_result; then
                success "Podman fallback successful - hpc-base is ready!"
                exit 0
            else
                warn "Podman build completed but verification failed"
                exit 1
            fi
        else
            error "Both OpenShift build and Podman fallback failed"
            
            # Provide troubleshooting information
            echo
            log "Troubleshooting Information:"
            echo "1. Check CRC cluster status: crc status"
            echo "2. Restart CRC if needed: crc stop && crc start"
            echo "3. Check cluster resources: oc get nodes && oc top nodes"
            echo "4. Check build events: oc get events -n ${NAMESPACE}"
            echo "5. Check container runtime: oc describe nodes"
            echo
            exit 1
        fi
    fi
}

# Run main function
main "$@"
