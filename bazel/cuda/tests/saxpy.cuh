#ifndef BAZEL_CUDA_TESTS_SAXPY_CUH_
#define BAZEL_CUDA_TESTS_SAXPY_CUH_

#include <cuda_runtime.h>

namespace cuda_tests {

// Launches y = a*x + y over n elements on the current device.
cudaError_t Saxpy(int n, float a, const float* x, float* y);

}  // namespace cuda_tests

#endif  // BAZEL_CUDA_TESTS_SAXPY_CUH_
