"""The nvcc compile action.

One nvcc invocation per .cu file. nvcc drives the whole pipeline internally
(host preprocess via -ccbin clang, cudafe++, cicc, ptxas, fatbinary), so this
is a single Bazel action with the entire nvcc package declared as inputs.

Host-compiler flags are extracted from the resolved cc_toolchain (hermetic-llvm)
so CUDA objects see the same sysroot/libc++/ABI configuration as every other
object in the build, and are forwarded via -Xcompiler.
"""

load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load(":providers.bzl", "CudaToolchainInfo")

CPP_COMPILE_ACTION_NAME = "c++-compile"

# Host-toolchain features that make no sense for nvcc's host pass.
_UNSUPPORTED_HOST_FEATURES = [
    "module_maps",
    "layering_check",
    "parse_headers",
    "cpp_modules",
]

def _host_feature_configuration(ctx, cc_toolchain):
    return cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features + _UNSUPPORTED_HOST_FEATURES,
    )

def _host_compile_flags(feature_configuration, cc_toolchain):
    compile_variables = cc_common.create_compile_variables(
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        use_pic = True,
    )
    return cc_common.get_memory_inefficient_command_line(
        feature_configuration = feature_configuration,
        action_name = CPP_COMPILE_ACTION_NAME,
        variables = compile_variables,
    )

def _generate_code_flags(archs):
    flags = []
    for arch in archs:
        if arch.startswith("sm_"):
            virtual = "compute_" + arch[len("sm_"):]
            flags.append("--generate-code=arch={},code={}".format(virtual, arch))
        elif arch.startswith("compute_"):
            flags.append("--generate-code=arch={},code={}".format(arch, arch))
        else:
            fail("bad CUDA arch: " + arch)
    return flags

def compile_cuda_object(
        ctx,
        cuda_toolchain,
        cc_toolchain,
        src,
        compilation_context,
        local_defines,
        copts,
        host_copts,
        ptxasopts,
        archs):
    """Compiles one .cu file to an object file. Returns the object File."""
    obj = ctx.actions.declare_file(
        "_objs/{}/{}.o".format(ctx.label.name, src.basename.removesuffix(".cu")),
    )

    feature_configuration = _host_feature_configuration(ctx, cc_toolchain)
    host_compiler = cc_common.get_tool_for_action(
        feature_configuration = feature_configuration,
        action_name = CPP_COMPILE_ACTION_NAME,
    )
    host_flags = _host_compile_flags(feature_configuration, cc_toolchain)

    # nvcc's EDG device frontend cannot parse libc++ 22 headers (extern
    # template lists, removed internals CUDA's own headers rely on). Only the
    # libstdc++ C++ standard library is supported; fail early with a pointer
    # to the right invocation instead of surfacing hundreds of EDG errors.
    for flag in host_flags:
        if "libcxx" in flag:
            fail(
                "cuda_library requires the libstdc++ platform; " +
                "build with --config=cuda (or --platforms=//bazel/cuda/platforms:linux_x86_64). " +
                "nvcc's device frontend cannot parse libc++ headers.",
            )

    args = ctx.actions.args()
    args.add("-c", src)
    args.add("-o", obj)

    # The toolkit is staged as one toolkit-shaped tree, so nvcc.profile
    # resolves cicc, libdevice, the toolkit headers and the link stubs itself.
    args.add("-ccbin=" + host_compiler)
    args.add("-std=" + cuda_toolchain.cuda_std)
    if cuda_toolchain.allow_unsupported_compiler:
        args.add("--allow-unsupported-compiler")
    args.add_all(_generate_code_flags(archs))
    args.add_all(cuda_toolchain.compile_args)

    # Include paths and defines feed nvcc directly; nvcc forwards them to the
    # host preprocessor and its own frontends.
    args.add_all(compilation_context.includes, before_each = "-I")
    args.add_all(compilation_context.quote_includes, before_each = "-I")
    args.add_all(compilation_context.system_includes, before_each = "-isystem")
    args.add_all(compilation_context.external_includes, before_each = "-isystem")
    args.add_all(compilation_context.defines, before_each = "-D")
    args.add_all(local_defines, before_each = "-D")

    # Everything the cc_toolchain would pass to a C++ compile goes to the host
    # compiler. -Xcompiler= keeps each flag a single token (no comma splitting).
    args.add_all(host_flags, format_each = "-Xcompiler=%s")

    # Then pin the host dialect, last so it wins. This is what libstdc++'s
    # headers expand against, and it has to stay below the C++20 library code
    # EDG cannot parse (std::atomic's __builtin_clear_padding). nvcc's own
    # -std sets a host dialect too, but -Xcompiler flags land after it on the
    # host command line, so this is the value that takes effect. Without the
    # pin the floor would be whatever hermetic-llvm happens to default to.
    args.add("-Xcompiler=-std=" + cuda_toolchain.host_std)

    args.add_all(copts)
    args.add_all(host_copts, format_each = "-Xcompiler=%s")
    args.add_all(ptxasopts, format_each = "-Xptxas=%s")

    inputs = depset(
        direct = [src],
        transitive = [
            compilation_context.headers,
            cuda_toolchain.toolkit_files,
            cuda_toolchain.compile_args_files,
            cc_toolchain.all_files,
        ],
    )

    ctx.actions.run(
        mnemonic = "CudaCompile",
        progress_message = "Compiling CUDA " + src.short_path,
        executable = cuda_toolchain.nvcc,
        arguments = [args],
        inputs = inputs,
        outputs = [obj],
        toolchain = Label("//bazel/cuda/toolchain:toolchain_type"),
    )
    return obj
