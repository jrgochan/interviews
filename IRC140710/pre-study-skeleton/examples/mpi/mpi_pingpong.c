#include <mpi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#ifndef MSG_SIZE
#define MSG_SIZE 8
#endif

int main(int argc, char** argv) {
    MPI_Init(&argc, &argv);
    int rank, size;
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);

    if (size < 2) {
        if (rank == 0) fprintf(stderr, "Need at least 2 ranks.\n");
        MPI_Finalize();
        return 1;
    }

    int partner = (rank + 1) % 2;
    char* buf = (char*)malloc(MSG_SIZE);
    memset(buf, 0, MSG_SIZE);

    int iters = 10000;
    double t0 = MPI_Wtime();
    for (int i = 0; i < iters; ++i) {
        if (rank == 0) {
            MPI_Send(buf, MSG_SIZE, MPI_CHAR, 1, 0, MPI_COMM_WORLD);
            MPI_Recv(buf, MSG_SIZE, MPI_CHAR, 1, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
        } else if (rank == 1) {
            MPI_Recv(buf, MSG_SIZE, MPI_CHAR, 0, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
            MPI_Send(buf, MSG_SIZE, MPI_CHAR, 0, 0, MPI_COMM_WORLD);
        }
    }
    double t1 = MPI_Wtime();
    double elapsed = t1 - t0;
    double latency = (elapsed / (2.0 * iters)) * 1e6; // microseconds

    if (rank == 0) {
        printf("PingPong: size=%d bytes, latency=%.3f us\n", MSG_SIZE, latency);
    }

    free(buf);
    MPI_Finalize();
    return 0;
}
