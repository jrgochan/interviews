#!/bin/bash
#SBATCH -J gpu_smoke
#SBATCH -A your_account
#SBATCH -p gpu
#SBATCH -N 1
#SBATCH --gpus=1
#SBATCH -t 00:03:00
#SBATCH -o gpu_smoke.%j.out

srun ./gpu_smoke.sh
