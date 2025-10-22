#!/bin/bash
# Cleanup RHOS/OpenShift HPC Interview Environment

set -e

NAMESPACE="hpc-interview"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🧹 Cleaning up HPC Interview Environment${NC}"
echo

# Function to cleanup namespace
cleanup_namespace() {
    echo -e "${BLUE}🗑️  Removing namespace: ${NAMESPACE}${NC}"
    
    if oc get namespace "${NAMESPACE}" &> /dev/null; then
        echo -e "${YELLOW}Deleting all resources in namespace...${NC}"
        oc delete namespace "${NAMESPACE}" --wait=true
        echo -e "${GREEN}✅ Namespace ${NAMESPACE} deleted${NC}"
    else
        echo -e "${YELLOW}⚠️  Namespace ${NAMESPACE} does not exist${NC}"
    fi
}

# Function to cleanup container images
cleanup_images() {
    echo -e "${BLUE}🏗️  Removing container images${NC}"
    
    local images=("hpc-base:latest" "hpc-mpi-debug:latest" "hpc-reframe:latest" "hpc-aiml:latest")
    
    for image in "${images[@]}"; do
        if podman image exists "$image" 2>/dev/null; then
            echo -e "Removing image: $image"
            podman rmi "$image" || echo -e "${YELLOW}⚠️  Could not remove $image${NC}"
        else
            echo -e "${YELLOW}Image $image does not exist${NC}"
        fi
    done
    
    echo -e "${GREEN}✅ Container images cleanup completed${NC}"
}

# Function to cleanup volumes and data
cleanup_data() {
    echo -e "${BLUE}💾 Cleaning up persistent data${NC}"
    
    # Remove any local build artifacts
    find . -name "build" -type d -exec rm -rf {} + 2>/dev/null || true
    find . -name "*.log" -type f -delete 2>/dev/null || true
    find . -name "*.out" -type f -delete 2>/dev/null || true
    find . -name "*.err" -type f -delete 2>/dev/null || true
    
    echo -e "${GREEN}✅ Local build artifacts cleaned${NC}"
}

# Function to show status
show_cleanup_status() {
    echo
    echo -e "${GREEN}🎉 Cleanup Complete!${NC}"
    echo
    echo -e "${BLUE}Status Check:${NC}"
    echo -e "Namespace: $(oc get namespace ${NAMESPACE} 2>/dev/null && echo 'Still exists' || echo 'Deleted')"
    echo -e "Container Images:"
    
    local images=("hpc-base:latest" "hpc-mpi-debug:latest" "hpc-reframe:latest" "hpc-aiml:latest")
    for image in "${images[@]}"; do
        if podman image exists "$image" 2>/dev/null; then
            echo -e "  ❌ $image (still exists)"
        else
            echo -e "  ✅ $image (removed)"
        fi
    done
    
    echo
    echo -e "${BLUE}To rebuild the environment:${NC}"
    echo -e "  ./setup.sh"
}

# Main execution
case "${1:-all}" in
    namespace)
        cleanup_namespace
        ;;
    images)
        cleanup_images
        ;;
    data)
        cleanup_data
        ;;
    all)
        cleanup_namespace
        cleanup_images
        cleanup_data
        show_cleanup_status
        ;;
    --force)
        echo -e "${RED}🚨 Force cleanup - removing everything${NC}"
        cleanup_namespace
        cleanup_images
        cleanup_data
        
        # Also cleanup podman system
        echo -e "${YELLOW}Running podman system prune...${NC}"
        podman system prune -f || true
        
        show_cleanup_status
        ;;
    *)
        echo "Usage: $0 [namespace|images|data|all|--force]"
        echo "  namespace  - Remove OpenShift namespace and resources"
        echo "  images     - Remove container images"
        echo "  data       - Clean local build artifacts"
        echo "  all        - Clean everything (default)"
        echo "  --force    - Force cleanup including podman system prune"
        exit 1
        ;;
esac
