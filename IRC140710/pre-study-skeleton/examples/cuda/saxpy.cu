#include <cstdio>
#include <cuda_runtime.h>

__global__ void saxpy(int n, float a, const float *x, float *y) {
  int i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i < n) y[i] = a * x[i] + y[i];
}

int main() {
  int N = 1<<20;
  float *x, *y, *d_x, *d_y;
  x = (float*)malloc(N * sizeof(float));
  y = (float*)malloc(N * sizeof(float));
  for (int i = 0; i < N; i++) { x[i] = 1.0f; y[i] = 2.0f; }
  cudaMalloc(&d_x, N*sizeof(float));
  cudaMalloc(&d_y, N*sizeof(float));
  cudaMemcpy(d_x, x, N*sizeof(float), cudaMemcpyHostToDevice);
  cudaMemcpy(d_y, y, N*sizeof(float), cudaMemcpyHostToDevice);
  saxpy<<<(N+255)/256, 256>>>(N, 2.0f, d_x, d_y);
  cudaMemcpy(y, d_y, N*sizeof(float), cudaMemcpyDeviceToHost);
  printf("y[0]=%f y[N-1]=%f\n", y[0], y[N-1]);
  cudaFree(d_x); cudaFree(d_y);
  free(x); free(y);
  return 0;
}
