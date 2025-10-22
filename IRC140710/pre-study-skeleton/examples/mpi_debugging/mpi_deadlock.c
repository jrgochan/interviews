/*
 * MPI Deadlock Example - Demonstrates cyclic dependency deadlock
 * 
 * This program intentionally creates a deadlock situation where:
 * - Process 0 tries to send to process 1, then receive from process 1
 * - Process 1 tries to send to process 0, then receive from process 0
 * 
 * Both processes block on their sends, creating a deadlock.
 * 
 * Debugging techniques:
 * 1. Use `mpirun -np 2 gdb --args ./mpi_deadlock` 
 * 2. In GDB: (gdb) run, then Ctrl+C when hung, (gdb) where
 * 3. Use Valgrind: `mpirun -np 2 valgrind --tool=helgrind ./mpi_deadlock`
 * 4. TotalView: Shows all ranks, call stacks, and MPI message queues
 */

#include <mpi.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main(int argc, char** argv) {
    int rank, size;
    int send_data = 42;
    int recv_data = 0;
    
    MPI_Init(&argc, &argv);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);
    
    if (size != 2) {
        if (rank == 0) {
            printf("This program requires exactly 2 MPI processes\n");
        }
        MPI_Finalize();
        return 1;
    }
    
    printf("Process %d starting...\n", rank);
    fflush(stdout);
    
    if (rank == 0) {
        printf("Process 0: Attempting to send to process 1...\n");
        fflush(stdout);
        
        // This will block because process 1 is also trying to send first
        MPI_Send(&send_data, 1, MPI_INT, 1, 0, MPI_COMM_WORLD);
        
        printf("Process 0: Send completed, now receiving...\n");
        MPI_Recv(&recv_data, 1, MPI_INT, 1, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
        
        printf("Process 0: Received %d\n", recv_data);
        
    } else if (rank == 1) {
        printf("Process 1: Attempting to send to process 0...\n");
        fflush(stdout);
        
        // This will also block - deadlock!
        MPI_Send(&send_data, 1, MPI_INT, 0, 0, MPI_COMM_WORLD);
        
        printf("Process 1: Send completed, now receiving...\n");
        MPI_Recv(&recv_data, 1, MPI_INT, 0, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
        
        printf("Process 1: Received %d\n", recv_data);
    }
    
    printf("Process %d: Finalizing (this will never execute)\n", rank);
    MPI_Finalize();
    return 0;
}

/*
 * SOLUTION - Use non-blocking communication or change ordering:
 * 
 * Option 1: Non-blocking sends
 *   MPI_Request requests[2];
 *   MPI_Isend(&send_data, 1, MPI_INT, other_rank, 0, MPI_COMM_WORLD, &requests[0]);
 *   MPI_Irecv(&recv_data, 1, MPI_INT, other_rank, 0, MPI_COMM_WORLD, &requests[1]);
 *   MPI_Waitall(2, requests, MPI_STATUSES_IGNORE);
 * 
 * Option 2: Alternating send/receive order
 *   if (rank == 0) { send first, then receive }
 *   if (rank == 1) { receive first, then send }
 * 
 * Option 3: Use MPI_Sendrecv
 *   MPI_Sendrecv(&send_data, 1, MPI_INT, other_rank, 0,
 *                &recv_data, 1, MPI_INT, other_rank, 0,
 *                MPI_COMM_WORLD, MPI_STATUS_IGNORE);
 */
