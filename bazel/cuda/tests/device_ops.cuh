#ifndef BAZEL_CUDA_TESTS_DEVICE_OPS_CUH_
#define BAZEL_CUDA_TESTS_DEVICE_OPS_CUH_

// A header-only cuda_library: no srcs, just device code for dependents to
// inline. Everything here has to be inline-able, because non-RDC compilation
// gives each translation unit its own self-contained device image -- a
// __device__ function *defined* in another cuda_library's .cu could not be
// called across the boundary, only one declared in a header like this.

namespace cuda_tests {

__device__ __forceinline__ float Scale(float x, float a) { return a * x; }

__device__ __forceinline__ float FusedScaleAdd(float x, float a, float y) {
  return Scale(x, a) + y;
}

}  // namespace cuda_tests

#endif  // BAZEL_CUDA_TESTS_DEVICE_OPS_CUH_
