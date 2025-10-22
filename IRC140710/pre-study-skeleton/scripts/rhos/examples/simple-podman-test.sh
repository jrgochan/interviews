#!/bin/bash
# Simple Podman-based HPC testing (no OpenShift required)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🐳 Simple Podman HPC Testing Environment${NC}"
echo -e "${YELLOW}Note: This runs without OpenShift for quick testing${NC}"
echo

# Configuration
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")"/../../.. && pwd)"
CONTAINER_NAME="hpc-interview-test"

# Function to build test container
build_test_container() {
    echo -e "${BLUE}🔨 Building HPC test container...${NC}"
    
    cd "$(dirname "$0")/.."
    
    # Use the existing public base image containerfile
    if [ ! -f containers/Containerfile.simple ]; then
        echo -e "${YELLOW}Using existing Containerfile.simple${NC}"
    fi
    
    podman build -t hpc-simple:latest -f containers/Containerfile.simple "$PROJECT_ROOT"
    
    echo -e "${GREEN}✅ Test container built successfully${NC}"
}

# Function to run MPI debugging test
test_mpi_debugging() {
    echo -e "${BLUE}🐛 Testing MPI Debugging Examples${NC}"
    
    podman run --rm --name ${CONTAINER_NAME}-mpi \
        -v "$PROJECT_ROOT:/workspace:Z" \
        hpc-simple:latest \
        bash -c "
            cd /workspace
            echo '=== Building MPI debugging examples ==='
            cd examples/mpi_debugging
            mkdir -p build && cd build
            cmake .. && make
            
            echo '=== Testing deadlock detection ==='
            timeout 5s mpirun -np 2 ./mpi_deadlock || echo 'Deadlock detected (expected)'
            
            echo '=== Testing race condition ==='
            mpirun -np 2 ./mpi_race_condition || true
            
            echo '=== MPI debugging test completed ==='
        "
}

# Function to test ReFrame
test_reframe() {
    echo -e "${BLUE}📊 Testing ReFrame Framework${NC}"
    
    podman run --rm --name ${CONTAINER_NAME}-reframe \
        -v "$PROJECT_ROOT:/workspace:Z" \
        hpc-simple:latest \
        bash -c "
            cd /workspace
            echo '=== Testing ReFrame installation ==='
            python3 -c 'import reframe; print(f\"ReFrame version: {reframe.__version__}\")'
            
            echo '=== Running basic MPI test ==='
            cd reframe
            reframe -C reframe_settings.py -c tests/test_mpi_ring.py -r --system local:cpu || true
            
            echo '=== ReFrame test completed ==='
        "
}

# Function to test AI/ML
test_aiml() {
    echo -e "${BLUE}🧠 Testing AI/ML Environment${NC}"
    
    podman run --rm --name ${CONTAINER_NAME}-aiml \
        -v "$PROJECT_ROOT:/workspace:Z" \
        hpc-simple:latest \
        bash -c "
            cd /workspace
            echo '=== Testing PyTorch installation ==='
            python3 -c 'import torch; print(f\"PyTorch: {torch.__version__}\"); print(f\"MPI available: {torch.distributed.is_mpi_available()}\")'
            
            echo '=== Running simple training example ==='
            python3 examples/ai_ml/distributed_training.py --epochs 1 --batch-size 16 || true
            
            echo '=== AI/ML test completed ==='
        "
}

# Function to get interactive shell
interactive_shell() {
    echo -e "${BLUE}🖥️  Starting interactive HPC shell${NC}"
    echo -e "${YELLOW}Available commands:${NC}"
    echo -e "  - cd examples/mpi && ls"
    echo -e "  - cd examples/mpi_debugging && ls" 
    echo -e "  - cd examples/ai_ml && ls"
    echo -e "  - mpirun --version"
    echo -e "  - gcc --version"
    echo -e "  - python3 --version"
    echo
    
    podman run -it --rm --name ${CONTAINER_NAME}-shell \
        -v "$PROJECT_ROOT:/workspace:Z" \
        hpc-simple:latest \
        bash -c "cd /workspace && exec /bin/bash"
}

# Main execution
case "${1:-all}" in
    build)
        build_test_container
        ;;
    mpi)
        test_mpi_debugging
        ;;
    reframe)
        test_reframe
        ;;
    aiml)
        test_aiml
        ;;
    shell)
        interactive_shell
        ;;
    all)
        build_test_container
        echo
        test_mpi_debugging
        echo
        test_reframe
        echo
        test_aiml
        ;;
    *)
        echo "Usage: $0 [build|mpi|reframe|aiml|shell|all]"
        echo "  build    - Build the test container"
        echo "  mpi      - Test MPI debugging examples"
        echo "  reframe  - Test ReFrame framework"
        echo "  aiml     - Test AI/ML environment"
        echo "  shell    - Interactive shell for manual testing"
        echo "  all      - Run all tests (default)"
        echo
        echo "Quick start: $0 && $0 shell"
        exit 1
        ;;
esac

echo
echo -e "${GREEN}🎉 Simple Podman testing completed!${NC}"
echo -e "${BLUE}For interactive exploration: $0 shell${NC}"
