#ifndef BAZEL_CUDA_TESTS_SCALED_ADD_CUH_
#define BAZEL_CUDA_TESTS_SCALED_ADD_CUH_

#include <cuda_runtime.h>

namespace cuda_tests {

// y = a*x + y, computed through device helpers that arrive from a separate,
// header-only cuda_library. Exercises header propagation between two
// cuda_library targets, plus the SCALED_ADD_TAG define this target sets.
cudaError_t ScaledAdd(int n, float a, const float* x, float* y);

const char* ScaledAddTag();

}  // namespace cuda_tests

#endif  // BAZEL_CUDA_TESTS_SCALED_ADD_CUH_
