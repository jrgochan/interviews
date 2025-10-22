/*
 * MPI Race Condition Example - Demonstrates shared memory race conditions
 * 
 * This program creates a race condition where multiple MPI processes
 * modify the same shared data without proper synchronization.
 * 
 * The race occurs when processes simultaneously read-modify-write
 * a shared counter, leading to lost updates.
 * 
 * Debugging techniques:
 * 1. Use MPI_Win_fence() for proper synchronization
 * 2. Compile with -fsanitize=thread to detect races
 * 3. Use Intel Inspector or similar tools
 * 4. TotalView can show memory access patterns
 */

#include <mpi.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <assert.h>

#define NUM_INCREMENTS 1000

int main(int argc, char** argv) {
    int rank, size;
    int *shared_counter;
    MPI_Win win;
    int i, local_value, result;
    
    MPI_Init(&argc, &argv);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);
    
    // Allocate shared memory window
    if (rank == 0) {
        MPI_Alloc_mem(sizeof(int), MPI_INFO_NULL, &shared_counter);
        *shared_counter = 0;  // Initialize counter
    } else {
        shared_counter = NULL;
    }
    
    // Create window for one-sided communication
    MPI_Win_create(shared_counter, (rank == 0) ? sizeof(int) : 0,
                   sizeof(int), MPI_INFO_NULL, MPI_COMM_WORLD, &win);
    
    MPI_Barrier(MPI_COMM_WORLD);
    
    printf("Process %d: Starting race condition test...\n", rank);
    
    // THIS IS THE PROBLEMATIC CODE - RACE CONDITION!
    for (i = 0; i < NUM_INCREMENTS; i++) {
        // Start access epoch (but no synchronization between processes)
        MPI_Win_fence(0, win);
        
        // Read current value
        MPI_Get(&local_value, 1, MPI_INT, 0, 0, 1, MPI_INT, win);
        MPI_Win_fence(0, win);
        
        // Simulate some work (increases chance of race)
        usleep(1);
        
        // Increment and write back - RACE CONDITION HERE!
        local_value++;
        MPI_Win_fence(0, win);
        MPI_Put(&local_value, 1, MPI_INT, 0, 0, 1, MPI_INT, win);
        MPI_Win_fence(0, win);
        
        if (i % 100 == 0 && rank == 0) {
            printf("Process %d: Iteration %d, counter should be %d\n", 
                   rank, i, (i + 1) * size);
        }
    }
    
    MPI_Barrier(MPI_COMM_WORLD);
    
    // Check final result
    if (rank == 0) {
        int expected = NUM_INCREMENTS * size;
        printf("Final counter value: %d (expected: %d)\n", 
               *shared_counter, expected);
        
        if (*shared_counter != expected) {
            printf("RACE CONDITION DETECTED! Lost updates: %d\n",
                   expected - *shared_counter);
        } else {
            printf("No race detected in this run (but race still exists!)\n");
        }
    }
    
    // Cleanup
    MPI_Win_free(&win);
    if (rank == 0) {
        MPI_Free_mem(shared_counter);
    }
    
    MPI_Finalize();
    return 0;
}

/*
 * PROPER SOLUTION - Use atomic operations or proper locking:
 * 
 * Option 1: Use MPI_Accumulate for atomic operations
 *   int increment = 1;
 *   MPI_Win_fence(0, win);
 *   MPI_Accumulate(&increment, 1, MPI_INT, 0, 0, 1, MPI_INT, MPI_SUM, win);
 *   MPI_Win_fence(0, win);
 * 
 * Option 2: Use MPI_Win_lock for exclusive access
 *   MPI_Win_lock(MPI_LOCK_EXCLUSIVE, 0, 0, win);
 *   // Read-modify-write operations here
 *   MPI_Win_unlock(0, win);
 * 
 * Option 3: Use MPI collective operations
 *   int local_contribution = NUM_INCREMENTS;
 *   MPI_Reduce(&local_contribution, &total, 1, MPI_INT, MPI_SUM, 0, MPI_COMM_WORLD);
 * 
 * DEBUGGING TIPS:
 * - Compile with: mpicc -g -fsanitize=thread -O0 mpi_race_condition.c
 * - Run with: mpirun -np 4 ./a.out
 * - Use Intel Inspector: inspxe-cl -collect ti2 -- mpirun -np 4 ./a.out
 * - In TotalView: Set watchpoints on shared_counter memory location
 */
