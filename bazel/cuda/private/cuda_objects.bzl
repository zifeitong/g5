"""Compiles .cu files; cc_library handles headers, archiving, and linking."""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cc_toolchain", "use_cc_toolchain")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load(":compile.bzl", "compile_cuda_object", "prepare_cuda_compilation")

visibility(["//bazel/cuda/..."])

CUDA_TOOLCHAIN_TYPE = "//bazel/cuda/toolchain:toolchain_type"

# Export toolkit headers to native C++ consumers as well as CUDA sources.
CUDA_TOOLKIT_HDRS = [Label("@cuda_toolkit//:headers")]

def _merged_compilation_inputs(ctx, toolkit_header_targets):
    """Merge dependency and toolkit compilation contexts."""
    return cc_common.merge_compilation_contexts(
        compilation_contexts = [
            dep[CcInfo].compilation_context
            for dep in list(ctx.attr.deps) + list(toolkit_header_targets)
        ],
    )

def _cuda_objects_impl(ctx):
    cuda_toolchain = ctx.toolchains[CUDA_TOOLCHAIN_TYPE]
    cc_toolchain = find_cc_toolchain(ctx)

    if not ctx.files.srcs:
        return [DefaultInfo(files = depset())]

    archs = ctx.attr.archs or ctx.attr._default_archs[BuildSettingInfo].value
    if not archs:
        fail("no CUDA archs: set --//bazel/cuda:archs or the archs attribute")

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
