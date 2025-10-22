#!/bin/bash
#SBATCH -J cuda_saxpy
#SBATCH -A your_account
#SBATCH -p gpu
#SBATCH -N 1
#SBATCH --gpus=1
#SBATCH -t 00:05:00
#SBATCH -o cuda_saxpy.%j.out

module purge
# module load cuda  # site-specific
srun ./saxpy
