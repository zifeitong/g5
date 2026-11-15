#pragma once

#if defined(__CUDACC__) && defined(__NVCC__)
#include <__config>

#if _LIBCPP_VERSION != 220108
#error "Revalidate the CUDA libc++ workaround for this LLVM version"
#endif
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
}  // namespace __math
_LIBCPP_END_NAMESPACE_STD
#endif
