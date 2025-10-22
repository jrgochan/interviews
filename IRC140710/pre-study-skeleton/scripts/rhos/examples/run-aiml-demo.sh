#!/bin/bash
# Run AI/ML distributed training demo in OpenShift environment

set -e

NAMESPACE="hpc-interview"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🧠 Running AI/ML Distributed Training Demo${NC}"
echo

# Function to run in AI/ML pod
run_in_aiml_pod() {
    local pod_name=$(oc get pods -n ${NAMESPACE} -l app=aiml-workspace -o jsonpath='{.items[0].metadata.name}')
    if [ -z "$pod_name" ]; then
        echo -e "${RED}❌ No AI/ML workspace pod found. Run setup.sh first.${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}Using AI/ML pod: $pod_name${NC}"
    oc exec -it $pod_name -n ${NAMESPACE} -- "$@"
}

# Function to run single node training
run_single_node() {
    echo -e "${YELLOW}🎯 Single Node Training Demo${NC}"
    
    run_in_aiml_pod bash -c "
        cd /home/hpcuser/workspace
        echo 'Running single node PyTorch training...'
        python examples/ai_ml/distributed_training.py --epochs 3 --batch-size 32 --lr 0.01
    "
}

# Function to simulate distributed training
run_distributed_simulation() {
    echo -e "${YELLOW}🌐 Distributed Training Simulation${NC}"
    
    run_in_aiml_pod bash -c "
        cd /home/hpcuser/workspace
        echo 'Simulating distributed training with multiple processes...'
        echo 'Note: This simulates what would happen in a multi-node setup'
        mpirun -np 2 python examples/ai_ml/distributed_training.py --epochs 2 --batch-size 16
    "
}

# Function to start Jupyter notebook
start_jupyter() {
    echo -e "${YELLOW}📓 Starting Jupyter Notebook${NC}"
    
    # Get the route for Jupyter
    local jupyter_url=$(oc get route jupyter-route -n ${NAMESPACE} -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
    
    if [ -n "$jupyter_url" ]; then
        echo -e "${GREEN}Jupyter will be available at: https://${jupyter_url}${NC}"
    fi
    
    run_in_aiml_pod bash -c "
        cd /home/hpcuser/workspace
        echo 'Starting Jupyter notebook server...'
        echo 'Note: This will run in the foreground. Use Ctrl+C to stop.'
        jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser --allow-root
    "
}

# Function to start TensorBoard
start_tensorboard() {
    echo -e "${YELLOW}📊 Starting TensorBoard${NC}"
    
    # Get the route for TensorBoard
    local tensorboard_url=$(oc get route tensorboard-route -n ${NAMESPACE} -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
    
    if [ -n "$tensorboard_url" ]; then
        echo -e "${GREEN}TensorBoard will be available at: https://${tensorboard_url}${NC}"
    fi
    
    run_in_aiml_pod bash -c "
        cd /home/hpcuser/workspace
        echo 'Starting TensorBoard server...'
        echo 'Logs directory: ./logs'
        mkdir -p logs
        tensorboard --logdir=./logs --host=0.0.0.0 --port=6006
    "
}

# Function to show AI/ML environment info
show_environment() {
    echo -e "${YELLOW}🔧 AI/ML Environment Information${NC}"
    
    run_in_aiml_pod bash -c "
        echo 'Python Version:'
        python --version
        echo
        echo 'PyTorch Version:'
        python -c 'import torch; print(f\"PyTorch: {torch.__version__}\"); print(f\"CUDA Available: {torch.cuda.is_available()}\")'
        echo
        echo 'Available packages:'
        pip list | grep -E '(torch|numpy|scipy|matplotlib|jupyter)'
        echo
        echo 'MPI Version:'
        mpirun --version
        echo
        echo 'System Resources:'
        free -h
        echo
        nproc
    "
}

# Main execution
case "${1:-demo}" in
    single)
        run_single_node
        ;;
    distributed)
        run_distributed_simulation
        ;;
    jupyter)
        start_jupyter
        ;;
    tensorboard)
        start_tensorboard
        ;;
    info)
        show_environment
        ;;
    demo)
        show_environment
        echo
        run_single_node
        echo
        run_distributed_simulation
        ;;
    interactive)
        echo -e "${BLUE}🖥️  Starting interactive AI/ML session...${NC}"
        run_in_aiml_pod /bin/bash
        ;;
    *)
        echo "Usage: $0 [single|distributed|jupyter|tensorboard|info|demo|interactive]"
        echo "  single        - Run single node training demo"
        echo "  distributed   - Run distributed training simulation"
        echo "  jupyter       - Start Jupyter notebook server"
        echo "  tensorboard   - Start TensorBoard server"
        echo "  info          - Show environment information"
        echo "  demo          - Run complete demonstration (default)"
        echo "  interactive   - Start interactive shell in AI/ML environment"
        exit 1
        ;;
esac

echo
echo -e "${GREEN}🎉 AI/ML demonstration completed!${NC}"
echo -e "${BLUE}For more details, see: examples/ai_ml/ directory${NC}"
