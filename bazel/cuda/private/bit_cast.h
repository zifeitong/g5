#pragma once

#if defined(__CUDACC__) && defined(__NVCC__) && __cplusplus >= 202002L
#include <bit>

#pragma nv_diagnostic push
#pragma nv_diag_suppress 20040  // Adding device annotations is intentional.

// nvcc drops device-call eligibility for non-literal bit_cast specializations.
#if defined(_LIBCPP_VERSION)
_LIBCPP_BEGIN_NAMESPACE_STD
template <class To, class From>
  requires(sizeof(To) == sizeof(From) && is_trivially_copyable_v<To> &&
           is_trivially_copyable_v<From>)
[[nodiscard]] _LIBCPP_HIDE_FROM_ABI __host__ __device__ constexpr To bit_cast(
    const From& value) noexcept;
_LIBCPP_END_NAMESPACE_STD
#elif defined(__GLIBCXX__)
namespace std _GLIBCXX_VISIBILITY(default) {
_GLIBCXX_BEGIN_NAMESPACE_VERSION
template <class To, class From>
[[nodiscard]] __host__ __device__ constexpr To bit_cast(
    const From& value) noexcept
  requires(sizeof(To) == sizeof(From)) && is_trivially_copyable_v<To> &&
          is_trivially_copyable_v<From>;
_GLIBCXX_END_NAMESPACE_VERSION
}  // namespace std _GLIBCXX_VISIBILITY(default)
#endif
#pragma nv_diagnostic pop
#endif
