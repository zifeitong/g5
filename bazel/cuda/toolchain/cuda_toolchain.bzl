"""The cuda_toolchain rule: binds nvcc + toolkit pieces into a Bazel toolchain."""

load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("//bazel/cuda/private:args_eval.bzl", "CUDA_COMPILE_ACTION_NAME", "CudaArgsInfo", "evaluate_args")
load("//bazel/cuda/private:providers.bzl", "CudaToolchainInfo")

def _single_executable(target, what):
    files = target.files.to_list()
    executables = [f for f in files if f.basename == what] or files
    if len(executables) != 1:
        fail("expected exactly one file for {}, got {}".format(what, files))
    return executables[0]

def _cuda_toolchain_impl(ctx):
    nvcc = _single_executable(ctx.attr.nvcc, "nvcc")

    compile_args, compile_args_files = evaluate_args(
        ctx.attr.args,
        CUDA_COMPILE_ACTION_NAME,
    )

    info = CudaToolchainInfo(
        nvcc = nvcc,
        toolkit_files = depset(ctx.files.toolkit_files + [nvcc]),
        headers = ctx.attr.headers,
        compile_args = compile_args,
        compile_args_files = compile_args_files,
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
        "args": attr.label_list(
            providers = [CudaArgsInfo],
            doc = "cuda_args targets bound to the cuda-compile action.",
        ),
        "cuda_std": attr.string(
            default = "c++23",
            doc = "C++ standard nvcc is told to use for .cu files; nvcc 13.4 " +
                  "accepts up to c++23. Note this does not decide what the " +
                  "libstdc++ headers in the TU expand as -- the cc " +
                  "toolchain's own -std, forwarded via -Xcompiler, does, and " +
                  "it is deliberately older. See compile.bzl.",
        ),
        "host_std": attr.string(
            default = "c++17",
            doc = "C++ standard for the host pass of a .cu, pinned after the " +
                  "cc toolchain's own -std so it wins regardless of what " +
                  "hermetic-llvm defaults to. This is what libstdc++'s " +
                  "headers expand against, and it is a floor, not a " +
                  "preference: C++20 library code that EDG cannot parse " +
                  "(std::atomic's __builtin_clear_padding) must stay out of " +
                  "the translation unit. Raise it only with the Thrust test " +
                  "green. A target can override it with host_copts.",
        ),
        "allow_unsupported_compiler": attr.bool(default = True),
    },
)
