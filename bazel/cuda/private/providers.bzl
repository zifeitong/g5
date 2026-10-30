"""Providers for the CUDA rules."""

CudaToolchainInfo = provider(
    doc = "Describes how to invoke nvcc against the hermetic CUDA toolkit.",
    fields = {
        "nvcc": "File: the nvcc driver executable.",
        "toolkit_files": "depset[File]: the whole toolkit tree; nvcc.profile resolves cicc, libdevice, headers and stubs relative to bin/nvcc.",
        "headers": "list[CcInfo]: toolkit headers implicitly available to every cuda_library (cudart, crt, cccl).",
        "compile_args": "list[str]: extra nvcc flags from the toolchain.",
        "cuda_std": "str: C++ standard nvcc is told to use, via -std.",
        "host_std": "str: C++ standard pinned for the host pass, appended after the cc toolchain's own, so it wins deterministically.",
        "allow_unsupported_compiler": "bool: pass --allow-unsupported-compiler for host compilers newer than nvcc's support matrix.",
    },
)

ArchsInfo = provider(
    doc = "Parsed value of the --//bazel/cuda:archs build flag.",
    fields = {"archs": "list[str]: e.g. [\"sm_90\", \"compute_90\"]"},
)
