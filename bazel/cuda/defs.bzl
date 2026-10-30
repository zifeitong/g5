"""Public API for the CUDA rules.

Usage:
    load("//bazel/cuda:defs.bzl", "cuda_library")
"""

load(
    "//bazel/cuda/private:cuda_library.bzl",
    _cuda_library = "cuda_library",
    _incompatible_unless_libstdcxx = "incompatible_unless_libstdcxx",
)

cuda_library = _cuda_library

def requires_cuda():
    """target_compatible_with value for cc targets that link CUDA code.

    Marks the target incompatible outside the CUDA (libstdc++) configuration so
    wildcard builds skip it instead of failing. cuda_library applies this
    automatically; use it on cc_binary/cc_test targets that depend on one.
    """
    return _incompatible_unless_libstdcxx()
