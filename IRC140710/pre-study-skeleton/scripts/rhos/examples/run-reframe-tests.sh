#!/bin/bash
# Run ReFrame performance tests in OpenShift environment

set -e

NAMESPACE="hpc-interview"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}📊 Running ReFrame Performance Tests${NC}"
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

# Function to run basic tests
run_basic_tests() {
    echo -e "${YELLOW}🧪 Running Basic ReFrame Tests${NC}"
    
    run_in_pod bash -c "
        cd /home/hpcuser/workspace
        echo 'Installing ReFrame if needed...'
        pip3 install --user reframe-hpc || true
        export PATH=\$PATH:\$HOME/.local/bin
        
        echo 'Running module tests...'
        reframe -C reframe/reframe_settings.py -c reframe/tests/test_modules.py -r --system local:cpu || true
        
        echo 'Running MPI ring test...'
        reframe -C reframe/reframe_settings.py -c reframe/tests/test_mpi_ring.py -r --system local:cpu || true
    "
}

# Function to run performance tests
run_performance_tests() {
    echo -e "${YELLOW}⚡ Running Performance Tests${NC}"
    
    run_in_pod bash -c "
        cd /home/hpcuser/workspace
        export PATH=\$PATH:\$HOME/.local/bin
        
        echo 'Running MPI bandwidth tests...'
        reframe -C reframe/reframe_settings.py -c reframe/tests/test_mpi_bandwidth.py -r --system local:cpu || true
        
        echo 'Running I/O bandwidth tests...'
        reframe -C reframe/reframe_settings.py -c reframe/tests/test_io_bw.py -r --system local:cpu || true
    "
}

# Function to show test results
show_test_results() {
    echo -e "${YELLOW}📈 ReFrame Test Results${NC}"
    
    run_in_pod bash -c "
        cd /home/hpcuser/workspace
        echo 'Recent test outputs:'
        find . -name '*.out' -type f -mmin -10 | head -5 | while read file; do
            echo \"=== \$file ===\"
            tail -10 \"\$file\"
            echo
        done
    "
}

# Main execution
case "${1:-all}" in
    basic)
        run_basic_tests
        ;;
    performance)
        run_performance_tests
        ;;
    results)
        show_test_results
        ;;
    all)
        run_basic_tests
        echo
        run_performance_tests
        echo
        show_test_results
        ;;
    interactive)
        echo -e "${BLUE}🖥️  Starting interactive ReFrame session...${NC}"
        run_in_pod /bin/bash
        ;;
    *)
        echo "Usage: $0 [basic|performance|results|all|interactive]"
        echo "  basic        - Run basic functionality tests"
        echo "  performance  - Run performance regression tests"
        echo "  results      - Show recent test results"
        echo "  all          - Run all test suites (default)"
        echo "  interactive  - Start interactive shell for custom testing"
        exit 1
        ;;
esac

echo
echo -e "${GREEN}🎉 ReFrame testing demonstration completed!${NC}"
echo -e "${BLUE}For more details, see: reframe/tests/ directory${NC}"
