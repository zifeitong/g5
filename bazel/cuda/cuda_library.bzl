"""cuda_library: nvcc-compiled objects wrapped in an ordinary cc_library."""

load("@rules_cc//cc:cc_library.bzl", "cc_library")
load(
    "//bazel/cuda/private:cuda_objects.bzl",
    "CUDA_TOOLKIT_HDRS",
    "cuda_objects",
    "incompatible_unless_libstdcxx",
)

def cuda_library(
        name,
        srcs = [],
        hdrs = [],
        deps = [],
        includes = [],
        defines = [],
        local_defines = [],
        copts = [],
        host_copts = [],
        ptxasopts = [],
        archs = [],
        alwayslink = False,
        linkstatic = True,
        target_compatible_with = [],
        visibility = None,
        **kwargs):
    """Compiles .cu files with nvcc; result is consumable as a cc_library.

    Args:
        name: target name.
        srcs: .cu sources (compiled by nvcc).
        hdrs: exported headers, visible to srcs and to dependents.
        deps: CcInfo dependencies, visible to srcs and propagated.
        includes: include dirs, relative to this package.
        defines: -D defines for srcs and dependents.
        local_defines: -D defines for srcs only.
        copts: flags passed to nvcc directly.
        host_copts: flags passed to the host compiler via -Xcompiler.
        ptxasopts: flags passed to ptxas via -Xptxas.
        archs: CUDA archs; defaults to --//bazel/cuda:archs.
        alwayslink: link all objects even if unreferenced (kernel registration).
        linkstatic: as cc_library; the objects are static by nature.
        visibility: standard.
        **kwargs: forwarded to the underlying cc_library (tags, testonly, ...).
    """
    objects_name = name + "_cuda_objs"
    cuda_objects(
        name = objects_name,
        srcs = srcs,
        hdrs = hdrs,
        deps = deps,
        includes = includes,
        defines = defines,
        local_defines = local_defines,
        copts = copts,
        host_copts = host_copts,
        ptxasopts = ptxasopts,
        archs = archs,
        target_compatible_with = target_compatible_with + incompatible_unless_libstdcxx(),
        visibility = ["//visibility:private"],
        **{k: v for k, v in kwargs.items() if k in ["tags", "testonly"]}
    )
    cc_library(
        name = name,
        srcs = [":" + objects_name],
        hdrs = hdrs,
        deps = deps + CUDA_TOOLKIT_HDRS,
        includes = includes,
        defines = defines,
        alwayslink = alwayslink,
        linkstatic = linkstatic,
        target_compatible_with = target_compatible_with + incompatible_unless_libstdcxx(),
        visibility = visibility,
        **kwargs
    )
