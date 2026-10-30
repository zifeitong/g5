"""Module extension exposing the pinned CUDA toolkit as @cuda_toolkit."""

load(":repo.bzl", "cuda_toolkit_repository")

def _cuda_toolkit_impl(_module_ctx):
    cuda_toolkit_repository(name = "cuda_toolkit")

cuda_toolkit = module_extension(implementation = _cuda_toolkit_impl)
