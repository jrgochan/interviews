# MPI Debugging Guide

This guide provides systematic approaches for debugging MPI applications, covering common issues and debugging tools.

## Common MPI Issues

### 1. Deadlocks

**Symptoms:**

- Application hangs indefinitely
- No output or progress after a certain point
- MPI processes remain running but inactive

**Causes:**

- Circular dependencies in communication (e.g., all ranks trying to send first)
- Mismatched send/receive operations
- Improper use of collective operations

**Detection Methods:**

```bash
# Method 1: Use GDB to examine call stack
mpirun -np 2 gdb --args ./mpi_deadlock
(gdb) run
# When hung, press Ctrl+C
(gdb) where
(gdb) info threads
(gdb) thread apply all bt

# Method 2: Use timeout and kill signals
timeout 30s mpirun -np 2 ./mpi_deadlock
echo $?  # Exit code 124 indicates timeout

# Method 3: Use MPI debugging tools
mpirun -np 2 --debug ./mpi_deadlock  # OpenMPI debug mode
```

**Resolution Strategies:**

1. Use non-blocking communication (`MPI_Isend`/`MPI_Irecv`)
2. Order operations differently between ranks
3. Use `MPI_Sendrecv` for symmetric exchanges
4. Implement timeouts for critical sections

### 2. Race Conditions

**Symptoms:**

- Inconsistent results across runs
- Data corruption or incorrect calculations
- Intermittent failures

**Detection Methods:**

```bash
# Thread sanitizer (requires OpenMPI with thread support)
mpicc -fsanitize=thread -g -O0 mpi_race_condition.c
mpirun -np 4 ./a.out

# Valgrind Helgrind
mpirun -np 4 valgrind --tool=helgrind ./mpi_race_condition

# Intel Inspector (if available)
inspxe-cl -collect ti2 -- mpirun -np 4 ./mpi_race_condition
```

**Resolution:**

1. Use proper synchronization (`MPI_Barrier`, `MPI_Win_fence`)
2. Implement atomic operations (`MPI_Accumulate`)
3. Use locks for critical sections (`MPI_Win_lock`)

### 3. Memory Errors

**Common Issues:**

- Buffer overruns in MPI communication
- Uninitialized memory in message buffers
- Memory leaks from unreleased MPI objects

**Detection:**

```bash
# Address sanitizer
mpicc -fsanitize=address -g -O0 program.c
mpirun -np 4 ./a.out

# Valgrind Memcheck
mpirun -np 4 valgrind --tool=memcheck --leak-check=full ./program

# For MPI-specific issues
export OMPI_MCA_mpi_show_handle_leaks=1
mpirun -np 4 ./program
```

### 4. Message Mismatches

**Symptoms:**

- `MPI_ERR_TAG` or `MPI_ERR_RANK` errors
- Unexpected message contents
- Hanging on receive operations

**Debugging:**

```bash
# Enable MPI error handling
export OMPI_MCA_mpi_show_mca_params=1
export OMPI_MCA_mpi_abort_print_stack=1

# Detailed MPI debugging
mpirun -np 4 --mca btl_base_debug 10 ./program
```

## Systematic Debugging Approach

### Phase 1: Initial Assessment

1. **Reproduce the Issue**

   ```bash
   # Document exact conditions
   echo "MPI Version: $(mpirun --version)"
   echo "Compiler: $(mpicc --version)"
   echo "System: $(uname -a)"
   
   # Run multiple times to check consistency
   for i in {1..5}; do
       echo "Run $i:"
       mpirun -np 4 ./program
   done
   ```

2. **Identify Failure Mode**
   - Immediate crash vs hanging
   - Consistent vs intermittent failure
   - Rank-specific vs global issue

### Phase 2: Code Analysis

1. **Static Analysis**

   ```bash
   # Check for obvious issues
   grep -n "MPI_Send\|MPI_Recv" *.c | head -20
   grep -n "malloc\|free" *.c
   
   # Look for unmatched operations
   comm_ops=$(grep -c "MPI_Send\|MPI_Isend" *.c)
   recv_ops=$(grep -c "MPI_Recv\|MPI_Irecv" *.c)
   echo "Sends: $comm_ops, Receives: $recv_ops"
   ```

2. **Review Communication Patterns**
   - Check send/receive rank calculations
   - Verify tag consistency
   - Ensure proper collective operation usage

### Phase 3: Runtime Debugging

1. **Add Debug Output**

   ```c
   #ifdef DEBUG_MPI
   printf("Rank %d: About to send to rank %d, tag %d\n", rank, dest, tag);
   fflush(stdout);
   #endif
   ```

2. **Use MPI Profiling Interface**

   ```bash
   # Link with PMPI wrapper
   mpicc -DPMPI program.c pmpi_wrapper.c
   ```

3. **Progressive Isolation**
   - Start with 2 processes, increase gradually
   - Comment out sections of code systematically
   - Use synthetic data to isolate computation vs communication

### Phase 4: Tool-Assisted Debugging

1. **GDB for MPI**

   ```bash
   # Debug specific rank
   mpirun -np 4 xterm -e gdb ./program
   
   # Or use rank-specific debugging
   mpirun -np 4 ./debug_wrapper.sh ./program
   ```

   Contents of `debug_wrapper.sh`:

   ```bash
   #!/bin/bash
   if [ "$OMPI_COMM_WORLD_RANK" = "0" ]; then
       exec gdb --args "$@"
   else
       exec "$@"
   fi
   ```

2. **TotalView/DDT Usage**

   ```bash
   # Launch TotalView
   totalview mpirun -a -np 4 ./program
   
   # Key features to use:
   # - Message queue viewer
   # - Parallel stack view
   # - MPI message matching
   # - Deadlock detection
   ```

## Advanced Debugging Techniques

### Communication Logging

Create a wrapper to log all MPI calls:

```c
// mpi_logger.c
#include "mpi.h"
#include <stdio.h>

int MPI_Send(const void *buf, int count, MPI_Datatype datatype,
             int dest, int tag, MPI_Comm comm) {
    int rank;
    PMPI_Comm_rank(comm, &rank);
    printf("TRACE: Rank %d sending %d items to rank %d, tag %d\n",
           rank, count, dest, tag);
    return PMPI_Send(buf, count, datatype, dest, tag, comm);
}

int MPI_Recv(void *buf, int count, MPI_Datatype datatype,
             int source, int tag, MPI_Comm comm, MPI_Status *status) {
    int rank;
    PMPI_Comm_rank(comm, &rank);
    printf("TRACE: Rank %d receiving from rank %d, tag %d\n",
           rank, source, tag);
    return PMPI_Recv(buf, count, datatype, source, tag, comm, status);
}
```

### Performance Debugging

For performance issues:

```bash
# Profile with Score-P
scorep mpirun -np 4 ./program
scalasca -examine scorep_*/

# Use TAU profiling
export TAU_MAKEFILE=/path/to/tau/Makefile.tau-mpi-pdt
tau_exec mpirun -np 4 ./program
paraprof
```

### Environment Variables for Debugging

```bash
# OpenMPI debugging
export OMPI_MCA_btl_base_verbose=10           # Communication debugging
export OMPI_MCA_mpi_show_handle_leaks=1       # Show resource leaks
export OMPI_MCA_mpi_abort_print_stack=1       # Stack trace on abort
export OMPI_MCA_orte_base_help_aggregate=0    # Don't aggregate help messages

# Intel MPI debugging
export I_MPI_DEBUG=5                          # Debug level
export I_MPI_STATS=20                         # Communication statistics

# MPICH debugging
export MPICH_DBG=VERBOSE                      # Verbose debugging
export MPICH_DBG_LEVEL=VERBOSE               # Debug level
```

## Best Practices for Debuggable Code

1. **Error Checking**

   ```c
   int err = MPI_Send(buf, count, MPI_INT, dest, tag, MPI_COMM_WORLD);
   if (err != MPI_SUCCESS) {
       char err_string[MPI_MAX_ERROR_STRING];
       int length;
       MPI_Error_string(err, err_string, &length);
       fprintf(stderr, "MPI_Send failed: %s\n", err_string);
       MPI_Abort(MPI_COMM_WORLD, err);
   }
   ```

2. **Defensive Programming**

   ```c
   // Validate ranks before communication
   assert(dest >= 0 && dest < size);
   assert(dest != rank);  // Prevent self-communication
   
   // Initialize buffers
   memset(recv_buffer, 0, buffer_size);
   ```

3. **Resource Cleanup**

   ```c
   // Track and free MPI objects
   MPI_Request *requests = malloc(num_requests * sizeof(MPI_Request));
   // ... use requests ...
   free(requests);
   
   // Free communicators, datatypes, etc.
   if (comm != MPI_COMM_WORLD) {
       MPI_Comm_free(&comm);
   }
   ```

## Troubleshooting Checklist

**Before Starting:**

- [ ] Can you reproduce the issue consistently?
- [ ] Have you identified the minimal failing case?
- [ ] Are you using the correct MPI implementation/version?

**During Debugging:**

- [ ] Check rank calculations and bounds
- [ ] Verify send/receive matching (rank, tag, communicator)
- [ ] Ensure proper collective operation participation
- [ ] Look for unfreed MPI objects
- [ ] Check for proper error handling

**Performance Issues:**

- [ ] Profile communication vs computation time
- [ ] Check for load imbalance
- [ ] Identify communication hotspots
- [ ] Verify optimal process placement

**Before Reporting Bug:**

- [ ] Test with different process counts
- [ ] Try different MPI implementations
- [ ] Create minimal reproduction case
- [ ] Document environment details
