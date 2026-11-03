"""The nvcc rule behind cuda_library: one .o per .cu, nothing else.

It reads dep CcInfos to assemble include paths, defines and headers, and
leaves provider assembly, archiving and header export to the cc_library that
cuda_library wraps it in. That split buys cc_library's whole attribute surface
(alwayslink, linkstatic, implementation_deps, ...) for free; it is not forced
by Bazel. CcInfo, cc_common.compile, create_compilation_outputs and
create_linking_context_from_compilation_outputs are all callable from a
root-module .bzl and the result links and runs. Only
cc_common.create_library_to_link is allowlisted private API
(_PRIVATE_STARLARKIFICATION_ALLOWLIST), and nothing here needs it.

So this could return a CcInfo directly. The reason it stays a rule feeding a
macro is relocatable device code: a device-link step needs the device objects
of the whole transitive closure, which means propagating a CudaInfo next to
CcInfo, and a macro cannot return providers.
"""

load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cc_toolchain", "use_cc_toolchain")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load(":compile.bzl", "compile_cuda_object")
load(":providers.bzl", "ArchsInfo")

CUDA_TOOLCHAIN_TYPE = "//bazel/cuda/toolchain:toolchain_type"

# Toolkit headers implicitly visible to every cuda_library, on both the nvcc
# side (via the toolchain's headers attr) and the exported cc_library side.
CUDA_TOOLKIT_HDRS = [Label("@cuda_toolkit//:headers")]

def _merged_compilation_inputs(ctx, toolkit_header_targets):
    """Read-only merge of dep/toolkit compilation contexts plus our own attrs."""
    own_includes = []
    for inc in ctx.attr.includes:
        path = (ctx.label.package + "/" + inc).rstrip("/").removesuffix("/.")
        own_includes.append(path)
        own_includes.append(ctx.bin_dir.path + "/" + path)

    contexts = [
        dep[CcInfo].compilation_context
        for dep in list(ctx.attr.deps) + list(toolkit_header_targets)
    ]
    return struct(
        headers = depset(
            ctx.files.hdrs,
            transitive = [c.headers for c in contexts],
        ),
        includes = depset(own_includes, transitive = [c.includes for c in contexts]),
        quote_includes = depset(
            [".", ctx.bin_dir.path],
            transitive = [c.quote_includes for c in contexts],
        ),
        system_includes = depset(transitive = [c.system_includes for c in contexts]),
        external_includes = depset(transitive = [c.external_includes for c in contexts]),
        defines = depset(ctx.attr.defines, transitive = [c.defines for c in contexts]),
    )

def _cuda_objects_impl(ctx):
    cuda_toolchain = ctx.toolchains[CUDA_TOOLCHAIN_TYPE].cuda
    cc_toolchain = find_cc_toolchain(ctx)

    archs = ctx.attr.archs or ctx.attr._default_archs[ArchsInfo].archs
    if not archs:
        fail("no CUDA archs: set --//bazel/cuda:archs or the archs attribute")

    compilation_inputs = _merged_compilation_inputs(ctx, cuda_toolchain.headers)

    objects = [
        compile_cuda_object(
            ctx,
            cuda_toolchain,
            cc_toolchain,
            src,
            compilation_inputs,
            ctx.attr.local_defines,
            ctx.attr.copts,
            ctx.attr.host_copts,
            ctx.attr.ptxasopts,
            archs,
        )
        for src in ctx.files.srcs
    ]
    return [DefaultInfo(files = depset(objects))]

cuda_objects = rule(
    implementation = _cuda_objects_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = [".cu"]),
        "hdrs": attr.label_list(allow_files = True),
        "deps": attr.label_list(providers = [CcInfo]),
        "includes": attr.string_list(),
        "defines": attr.string_list(),
        "local_defines": attr.string_list(),
        "copts": attr.string_list(),
        "host_copts": attr.string_list(),
        "ptxasopts": attr.string_list(),
        "archs": attr.string_list(),
        "_default_archs": attr.label(
            default = Label("//bazel/cuda:archs"),
            providers = [ArchsInfo],
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
