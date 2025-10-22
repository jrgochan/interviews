#!/bin/bash
#SBATCH --job-name=distributed_pytorch
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=2
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=01:00:00
#SBATCH --partition=gpu
#SBATCH --gres=gpu:2
#SBATCH --account=hpc-ai
#SBATCH --output=pytorch_training_%j.out
#SBATCH --error=pytorch_training_%j.err

# Load required modules
module purge
module load python/3.11
module load cuda/11.8
module load openmpi/4.1.4
module load nccl/2.15.5

# Set up Python environment
export PYTHONPATH=$PYTHONPATH:/opt/pytorch/lib/python3.11/site-packages
export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK

# Set NCCL parameters for multi-node training
export NCCL_DEBUG=INFO
export NCCL_SOCKET_IFNAME=^docker0,lo
export NCCL_IB_DISABLE=0
export NCCL_IB_GID_INDEX=3
export NCCL_NET_GDR_LEVEL=2

# Set master node information
export MASTER_ADDR=$(hostname)
export MASTER_PORT=12345

# Set distributed training parameters
export WORLD_SIZE=$SLURM_NTASKS
export RANK=$SLURM_PROCID
export LOCAL_RANK=$SLURM_LOCALID

# Create output directory
mkdir -p ./logs/run_${SLURM_JOB_ID}

echo "========================================="
echo "SLURM Job ID: $SLURM_JOB_ID"
echo "Number of nodes: $SLURM_NNODES"
echo "Tasks per node: $SLURM_NTASKS_PER_NODE" 
echo "Total tasks: $SLURM_NTASKS"
echo "CPUs per task: $SLURM_CPUS_PER_TASK"
echo "Master node: $MASTER_ADDR"
echo "========================================="

# Print GPU information
echo "GPU Information:"
nvidia-smi
echo "========================================="

# Run distributed training
srun python distributed_training.py \
    --epochs 20 \
    --batch-size 128 \
    --lr 0.001 \
    --save-model \
    --log-dir ./logs/run_${SLURM_JOB_ID}

echo "Training completed!"
echo "Log files saved to: ./logs/run_${SLURM_JOB_ID}"

# Generate performance report
echo "========================================="
echo "Performance Summary:"
echo "Job ID: $SLURM_JOB_ID"
echo "Start time: $(date)"
echo "Nodes used: $SLURM_NNODES"
echo "Total tasks: $SLURM_NTASKS"
sacct -j $SLURM_JOB_ID --format=JobID,JobName,Partition,Account,AllocCPUS,State,ExitCode,Elapsed,MaxRSS,MaxVMSize
