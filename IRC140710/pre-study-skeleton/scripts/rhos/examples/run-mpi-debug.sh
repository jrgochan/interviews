#!/bin/bash
# Run MPI debugging examples in OpenShift environment

set -e

NAMESPACE="hpc-interview"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🐛 Running MPI Debugging Examples${NC}"
echo

# Function to run in pod
run_in_pod() {
    local pod_name=$(oc get pods -n ${NAMESPACE} -l app=hpc-workspace -o jsonpath='{.items[0].metadata.name}')
    if [ -z "$pod_name" ]; then
        echo -e "${RED}❌ No HPC workspace pod found. Run setup.sh first.${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}Using pod: $pod_name${NC}"
    oc exec -it $pod_name -n ${NAMESPACE} -- "$@"
}

# Function to demonstrate deadlock
demo_deadlock() {
    echo -e "${YELLOW}📍 Demonstrating MPI Deadlock${NC}"
    echo -e "This will show a deadlock scenario that hangs..."
    echo
    
    run_in_pod timeout 10s mpirun -np 2 examples/mpi_debugging/build/mpi_deadlock || {
        echo -e "${GREEN}✅ Deadlock detected (timeout after 10s as expected)${NC}"
        echo -e "In a real debugging session, you would:"
        echo -e "  - Use GDB to examine call stacks"
        echo -e "  - Check MPI message queues"
        echo -e "  - Analyze communication patterns"
    }
}

# Function to demonstrate race condition
demo_race_condition() {
    echo -e "${YELLOW}🏃 Demonstrating Race Condition${NC}"
    echo -e "Running race condition example..."
    echo
    
    run_in_pod mpirun -np 4 examples/mpi_debugging/build/mpi_race_condition
    echo
    echo -e "${GREEN}✅ Race condition example completed${NC}"
    echo -e "Note: Race conditions are intermittent - run multiple times to observe different results"
}

# Function to show debugging tools
show_debugging_tools() {
    echo -e "${YELLOW}🔧 Available Debugging Tools${NC}"
    
    run_in_pod bash -c "
        echo 'MPI Version:'
        mpirun --version
        echo
        echo 'GDB Version:'
        gdb --version | head -1
        echo
        echo 'Valgrind Version:'
        valgrind --version
        echo
        echo 'Environment Variables for Debugging:'
        env | grep -E '(OMPI_MCA|MALLOC)' | sort
    "
}

# Main execution
case "${1:-all}" in
    deadlock)
        demo_deadlock
        ;;
    race)
        demo_race_condition
        ;;
    tools)
        show_debugging_tools
        ;;
    all)
        show_debugging_tools
        echo
        demo_deadlock
        echo
        demo_race_condition
        ;;
    interactive)
        echo -e "${BLUE}🖥️  Starting interactive debugging session...${NC}"
        run_in_pod /bin/bash
        ;;
    *)
        echo "Usage: $0 [deadlock|race|tools|all|interactive]"
        echo "  deadlock     - Demonstrate deadlock detection"
        echo "  race         - Demonstrate race condition"
        echo "  tools        - Show available debugging tools"
        echo "  all          - Run all demonstrations (default)"
        echo "  interactive  - Start interactive shell in MPI debugging environment"
        exit 1
        ;;
esac

echo
echo -e "${GREEN}🎉 MPI debugging demonstration completed!${NC}"
echo -e "${BLUE}For more details, see: docs/debugging_mpi.md${NC}"
