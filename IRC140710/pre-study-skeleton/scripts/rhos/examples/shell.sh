#!/bin/bash
# Get interactive shell in HPC environment

set -e

NAMESPACE="hpc-interview"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🖥️  HPC Interactive Shell${NC}"
echo

# Function to get interactive shell
get_shell() {
    local workspace_type="${1:-hpc}"
    local pod_label=""
    
    case "$workspace_type" in
        hpc|base)
            pod_label="app=hpc-workspace"
            ;;
        aiml|ai)
            pod_label="app=aiml-workspace"
            ;;
        *)
            echo -e "${RED}❌ Unknown workspace type: $workspace_type${NC}"
            echo "Available types: hpc, aiml"
            exit 1
            ;;
    esac
    
    local pod_name=$(oc get pods -n ${NAMESPACE} -l $pod_label -o jsonpath='{.items[0].metadata.name}')
    if [ -z "$pod_name" ]; then
        echo -e "${RED}❌ No $workspace_type workspace pod found. Run setup.sh first.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Connecting to $workspace_type environment: $pod_name${NC}"
    echo -e "${YELLOW}Available commands:${NC}"
    echo -e "  - MPI examples: cd examples/mpi && ls"
    echo -e "  - Debugging: cd examples/mpi_debugging && ls"
    echo -e "  - AI/ML: cd examples/ai_ml && ls"
    echo -e "  - ReFrame tests: cd reframe/tests && ls"
    echo -e "  - Documentation: cd docs && ls"
    echo
    
    # Execute directly into the pod - let it start from current working directory
    # The container WORKDIR is set to /home/hpcuser/workspace in the Containerfile
    oc exec -it $pod_name -n ${NAMESPACE} -- /bin/bash
}

# Main execution
case "${1:-hpc}" in
    hpc|base)
        get_shell "hpc"
        ;;
    aiml|ai)
        get_shell "aiml"
        ;;
    *)
        echo "Usage: $0 [hpc|aiml]"
        echo "  hpc   - Interactive shell in HPC base environment (default)"
        echo "  aiml  - Interactive shell in AI/ML environment"
        exit 1
        ;;
esac
