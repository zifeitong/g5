"""The cuda_toolchain rule: binds nvcc + toolkit pieces into a Bazel toolchain."""

load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("//bazel/cuda/private:providers.bzl", "CudaToolchainInfo")

def _single_executable(target, what):
    files = target.files.to_list()
    executables = [f for f in files if f.basename == what] or files
    if len(executables) != 1:
        fail("expected exactly one file for {}, got {}".format(what, files))
    return executables[0]

def _cuda_toolchain_impl(ctx):
    nvcc = _single_executable(ctx.attr.nvcc, "nvcc")

    info = CudaToolchainInfo(
        nvcc = nvcc,
        toolkit_files = depset(ctx.files.toolkit_files + [nvcc]),
        headers = ctx.attr.headers,
        compile_args = ctx.attr.compile_args,
        cuda_std = ctx.attr.cuda_std,
        host_std = ctx.attr.host_std,
        allow_unsupported_compiler = ctx.attr.allow_unsupported_compiler,
    )
    return [
        platform_common.ToolchainInfo(cuda = info),
        info,
    ]

cuda_toolchain = rule(
    implementation = _cuda_toolchain_impl,
    attrs = {
        "nvcc": attr.label(
            mandatory = True,
            allow_files = True,
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
            doc = "nvcc's -std for .cu files. nvcc 13.4 accepts up to c++23.",
        ),
        "host_std": attr.string(
            default = "c++17",
            doc = "What libstdc++'s headers expand against in a .cu. A " +
                  "floor, not a preference: above c++17, <atomic> reaches " +
                  "__builtin_clear_padding, which EDG does not implement. " +
                  "Overridable per target with host_copts.",
        ),
        "allow_unsupported_compiler": attr.bool(default = True),
    },
)
