#!/bin/bash
#SBATCH -J mpi_ring
#SBATCH -A your_account
#SBATCH -p your_partition
#SBATCH -N 2
#SBATCH --ntasks-per-node=2
#SBATCH -t 00:05:00
#SBATCH -o mpi_ring.%j.out

module purge
# module load gcc openmpi  # site-specific
srun ./mpi_ring
