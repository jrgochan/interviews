# MPI Debugging with TotalView / Arm DDT

1. Build `examples/mpi`.
2. Launch under the debugger, e.g.:
   - `totalview srun -a ./mpi_ring -np 4`
   - or use DDT/Forge integration with Slurm.
3. Inspect message queues and stacks to locate barrier or collective mismatches.
