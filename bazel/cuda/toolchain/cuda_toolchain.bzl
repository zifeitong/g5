"""The cuda_toolchain rule: binds nvcc + toolkit pieces into a Bazel toolchain."""

load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

def _cuda_toolchain_impl(ctx):
    nvcc = ctx.file.nvcc

    return [platform_common.ToolchainInfo(
        # File: nvcc driver executable.
        nvcc = nvcc,
        # depset[File]: complete toolkit tree, including nvcc and its support files.
        toolkit_files = depset(ctx.files.toolkit_files + [nvcc]),
        # list[Target]: CcInfo targets supplying implicit toolkit headers.
        headers = ctx.attr.headers,
        # list[str]: extra nvcc flags for every cuda_library.
        compile_args = ctx.attr.compile_args,
        # str: nvcc's device dialect, passed through -std.
        cuda_std = ctx.attr.cuda_std,
        # str: host dialect outranking global flags; empty leaves them alone.
        host_std = ctx.attr.host_std,
        # bool: allow host compiler versions newer than nvcc's support matrix.
        allow_unsupported_compiler = ctx.attr.allow_unsupported_compiler,
    )]

cuda_toolchain = rule(
    implementation = _cuda_toolchain_impl,
    attrs = {
        "nvcc": attr.label(
            mandatory = True,
            allow_single_file = True,
            cfg = "exec",
            doc = "The nvcc driver executable.",
        ),
        "toolkit_files": attr.label_list(
            mandatory = True,
            allow_files = True,
            cfg = "exec",
            doc = "The whole toolkit tree: bin/, nvvm/, include/, lib/.",
        ),
        "headers": attr.label_list(
            providers = [CcInfo],
            doc = "Toolkit headers implicitly available to every cuda_library.",
        ),
        "compile_args": attr.string_list(
            doc = "Extra nvcc flags for every cuda_library.",
        ),
        "cuda_std": attr.string(
            default = "c++23",
            doc = "nvcc's -std for .cu device compilation.",
        ),
        "host_std": attr.string(
            doc = "Host -std for .cu compilation only, so CUDA can be held " +
                  "to an older dialect than the rest of the repo when nvcc " +
                  "cannot parse a standard library at the global one. Beats " +
                  "the cc toolchain and --copt/--cxxopt, loses to host_copts. " +
                  "Empty, the default, leaves the host dialect to those flags.",
        ),
        "allow_unsupported_compiler": attr.bool(
            default = True,
            doc = "Allow host compiler versions newer than nvcc's support matrix.",
        ),
    },
)
