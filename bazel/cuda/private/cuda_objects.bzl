"""The nvcc rule behind cuda_library: one .o per .cu, nothing else.

Reads compilation contexts from dependencies and the private header library.
The wrapping cc_library owns archiving, linking and header export.
"""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cc_toolchain", "use_cc_toolchain")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load(":compile.bzl", "compile_cuda_object", "prepare_cuda_compilation")

visibility(["//bazel/cuda/..."])

CUDA_TOOLCHAIN_TYPE = "//bazel/cuda/toolchain:toolchain_type"

# Toolkit headers implicitly visible to every cuda_library, on both the nvcc
# side (via the toolchain's headers attr) and the exported cc_library side.
CUDA_TOOLKIT_HDRS = [Label("@cuda_toolkit//:headers")]

def _merged_compilation_inputs(ctx, toolkit_header_targets):
    """Read-only merge of dep/toolkit compilation contexts."""
    return cc_common.merge_compilation_contexts(
        compilation_contexts = [
            dep[CcInfo].compilation_context
            for dep in list(ctx.attr.deps) + list(toolkit_header_targets)
        ],
    )

def _cuda_objects_impl(ctx):
    cuda_toolchain = ctx.toolchains[CUDA_TOOLCHAIN_TYPE]
    cc_toolchain = find_cc_toolchain(ctx)

    archs = ctx.attr.archs or ctx.attr._default_archs[BuildSettingInfo].value
    if not archs:
        fail("no CUDA archs: set --//bazel/cuda:archs or the archs attribute")
    if not ctx.files.srcs:
        return [DefaultInfo(files = depset())]

    compilation = prepare_cuda_compilation(
        ctx,
        cuda_toolchain,
        cc_toolchain,
        _merged_compilation_inputs(ctx, cuda_toolchain.headers),
        archs,
    )

    objects = [
        compile_cuda_object(ctx, cuda_toolchain, compilation, src)
        for src in ctx.files.srcs
    ]
    return [DefaultInfo(files = depset(objects))]

cuda_objects = rule(
    implementation = _cuda_objects_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = [".cu"]),
        "deps": attr.label_list(providers = [CcInfo]),
        "additional_compiler_inputs": attr.label_list(allow_files = True),
        "local_defines": attr.string_list(),
        "copts": attr.string_list(),
        "host_copts": attr.string_list(),
        "ptxasopts": attr.string_list(),
        "archs": attr.string_list(),
        "_default_archs": attr.label(
            default = Label("//bazel/cuda:archs"),
            providers = [BuildSettingInfo],
        ),
    },
    fragments = ["cpp"],
    toolchains = [CUDA_TOOLCHAIN_TYPE] + use_cc_toolchain(),
)

def incompatible_unless_libstdcxx():
    # nvcc requires libstdc++ for its host pass. On any other configuration
    # (notably the default libc++ platform) cuda targets are skipped as
    # incompatible instead of failing wildcard builds like //... .
    return select({
        "@llvm//runtimes/cxxstdlib:libstdcxx_linux": [],
        "//conditions:default": ["@platforms//:incompatible"],
    })
