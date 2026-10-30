"""Module extension exposing the pinned CUDA toolkit as @cuda_sdk."""

load(":repo.bzl", "cuda_toolkit")

def _cuda_sdk_impl(_module_ctx):
    cuda_toolkit(name = "cuda_sdk")

cuda_sdk = module_extension(implementation = _cuda_sdk_impl)
