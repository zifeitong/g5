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
        textual_hdrs = [],
        deps = [],
        implementation_deps = [],
        additional_compiler_inputs = [],
        includes = [],
        defines = [],
        local_defines = [],
        include_prefix = None,
        strip_include_prefix = None,
        copts = [],
        host_copts = [],
        ptxasopts = [],
        archs = [],
        features = [],
        target_compatible_with = [],
        **kwargs):
    """Compiles .cu files with nvcc; result is consumable as a cc_library.

    Args:
        name: target name.
        srcs: .cu sources (compiled by nvcc).
        hdrs: headers available to srcs and consumers.
        textual_hdrs: textual headers available to srcs and consumers.
        deps: dependencies available to srcs and consumers.
        implementation_deps: dependencies whose headers are private to srcs.
        additional_compiler_inputs: extra files available during compilation.
        includes: exported include directories, relative to this package.
        defines: defines for srcs and consumers.
        local_defines: defines for srcs only.
        include_prefix: prefix added to exported header paths, as in cc_library.
        strip_include_prefix: prefix removed from header paths, as in cc_library.
        copts: flags passed to nvcc directly.
        host_copts: flags passed to the host compiler via -Xcompiler.
        ptxasopts: flags passed to ptxas via -Xptxas.
        archs: CUDA archs; defaults to --//bazel/cuda:archs.
        features: toolchain features for CUDA and C++ actions.
        target_compatible_with: additional target platform constraints.
        **kwargs: remaining cc_library attributes; linkstatic defaults to True.
    """
    kwargs.setdefault("linkstatic", True)
    compatible_with = target_compatible_with + incompatible_unless_libstdcxx()
    private_kwargs = dict(
        {k: v for k, v in kwargs.items() if k in ["tags", "testonly"]},
        features = features,
        target_compatible_with = compatible_with,
        visibility = ["//visibility:private"],
    )
    headers_name = name + "_cuda_headers"
    objects_name = name + "_cuda_objs"

    # Share cc_library's header paths between nvcc and C++ consumers.
    cc_library(
        name = headers_name,
        hdrs = hdrs,
        textual_hdrs = textual_hdrs,
        deps = deps + CUDA_TOOLKIT_HDRS,
        additional_compiler_inputs = additional_compiler_inputs,
        includes = includes,
        defines = defines,
        include_prefix = include_prefix,
        strip_include_prefix = strip_include_prefix,
        **private_kwargs
    )
    cuda_objects(
        name = objects_name,
        srcs = srcs,
        deps = [":" + headers_name] + implementation_deps,
        additional_compiler_inputs = additional_compiler_inputs,
        local_defines = local_defines,
        copts = copts,
        host_copts = host_copts,
        ptxasopts = ptxasopts,
        archs = archs,
        **private_kwargs
    )
    cc_library(
        name = name,
        srcs = [":" + objects_name],
        deps = [":" + headers_name],
        implementation_deps = implementation_deps,
        additional_compiler_inputs = additional_compiler_inputs,
        local_defines = local_defines,
        features = features,
        target_compatible_with = compatible_with,
        **kwargs
    )
