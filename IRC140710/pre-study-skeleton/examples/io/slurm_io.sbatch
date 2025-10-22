#!/bin/bash
#SBATCH -J io_bw
#SBATCH -A your_account
#SBATCH -p your_partition
#SBATCH -N 1
#SBATCH -t 00:05:00
#SBATCH -o io_bw.%j.out

srun ./ior_like.sh
