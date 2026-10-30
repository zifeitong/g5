#include "bazel/cuda/tests/saxpy.cuh"

#include <cuda_runtime.h>

namespace cuda_tests {
namespace {

__global__ void SaxpyKernel(int n, float a, const float* x, float* y) {
  int i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i < n) {
    y[i] = a * x[i] + y[i];
  }
}

}  // namespace

cudaError_t Saxpy(int n, float a, const float* x, float* y) {
  constexpr int kBlockSize = 256;
  const int blocks = (n + kBlockSize - 1) / kBlockSize;
  SaxpyKernel<<<blocks, kBlockSize>>>(n, a, x, y);
  return cudaGetLastError();
}

}  // namespace cuda_tests
