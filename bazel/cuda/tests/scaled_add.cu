#include "bazel/cuda/tests/scaled_add.cuh"

#include <cuda_runtime.h>

// Comes from //bazel/cuda/tests:device_ops through deps, which is the point:
// a cuda_library's hdrs have to reach another cuda_library's nvcc compile.
#include "bazel/cuda/tests/device_ops.cuh"

#ifndef SCALED_ADD_TAG
#error "SCALED_ADD_TAG should arrive from the cuda_library defines attribute"
#endif

namespace cuda_tests {
namespace {

__global__ void ScaledAddKernel(int n, float a, const float* x, float* y) {
  const int i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i < n) {
    y[i] = FusedScaleAdd(x[i], a, y[i]);
  }
}

}  // namespace

cudaError_t ScaledAdd(int n, float a, const float* x, float* y) {
  constexpr int kBlockSize = 256;
  const int blocks = (n + kBlockSize - 1) / kBlockSize;
  ScaledAddKernel<<<blocks, kBlockSize>>>(n, a, x, y);
  return cudaGetLastError();
}

const char* ScaledAddTag() { return SCALED_ADD_TAG; }

}  // namespace cuda_tests
