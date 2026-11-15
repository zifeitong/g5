#pragma once

#if defined(__CUDACC__) && defined(__NVCC__)
#include <__config>

#if _LIBCPP_VERSION != 230102
#error "Revalidate the CUDA libc++ workarounds for this LLVM version"
#endif
#include <__configuration/attributes.h>
// cudafe emits malformed pack expansions for these analysis-only attributes.
#undef _LIBCPP_ACQUIRE_CAPABILITY
#undef _LIBCPP_REQUIRES_CAPABILITY
#undef _LIBCPP_RELEASE_CAPABILITY
#define _LIBCPP_ACQUIRE_CAPABILITY(...)
#define _LIBCPP_REQUIRES_CAPABILITY(...)
#define _LIBCPP_RELEASE_CAPABILITY(...)

#include <cmath>
_LIBCPP_BEGIN_NAMESPACE_STD
namespace __math {
// Match libc++'s templates and make their definitions available in device code.
template <class T>
__host__ __device__ inline _LIBCPP_CONSTEXPR_SINCE_CXX23 bool signbit(
    float value) noexcept;
template <class T>
__host__ __device__ inline _LIBCPP_CONSTEXPR_SINCE_CXX23 bool signbit(
    double value) noexcept;
template <class T>
__host__ __device__ inline _LIBCPP_CONSTEXPR_SINCE_CXX23 bool signbit(
    long double value) noexcept;
// Supply the non-template overloads declared by CUDA's math_functions.h.
__host__ __device__ inline int signbit(float value) noexcept {
  return __builtin_signbit(value);
}
__host__ __device__ inline int signbit(double value) noexcept {
  return __builtin_signbit(value);
}
__host__ __device__ inline int signbit(long double value) noexcept {
  return __builtin_signbit(value);
}
}  // namespace __math
_LIBCPP_END_NAMESPACE_STD
#endif
