"""One nvcc action per .cu, with host flags from the resolved C++ toolchain."""

load("@rules_cc//cc:action_names.bzl", "ACTION_NAMES")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")

visibility(["//bazel/cuda/..."])

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

def _host_compile_flags(ctx, feature_configuration, cc_toolchain):
    compile_variables = cc_common.create_compile_variables(
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        user_compile_flags = ctx.fragments.cpp.copts + ctx.fragments.cpp.cxxopts,
        use_pic = True,
    )
    return cc_common.get_memory_inefficient_command_line(
        feature_configuration = feature_configuration,
        action_name = ACTION_NAMES.cpp_compile,
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

def _quote_tool_option(flag):
    # nvcc splits comma-separated options and unquotes twice; escape both passes.
    for _ in range(2):
        flag = flag.replace("\\", "\\\\").replace('"', '\\"')
    return '"' + flag + '"'

def prepare_cuda_compilation(
        ctx,
        cuda_toolchain,
        cc_toolchain,
        compilation_context,
        archs):
    """Prepares the arguments and inputs shared by a target's compile actions."""
    feature_configuration = _host_feature_configuration(ctx, cc_toolchain)
    host_compiler = cc_common.get_tool_for_action(
        feature_configuration = feature_configuration,
        action_name = ACTION_NAMES.cpp_compile,
    )
    host_flags = _host_compile_flags(ctx, feature_configuration, cc_toolchain)

    args = ctx.actions.args()

    args.add("-ccbin=" + host_compiler)
    args.add("-std=" + cuda_toolchain.cuda_std)
    if cuda_toolchain.allow_unsupported_compiler:
        args.add("--allow-unsupported-compiler")
    args.add_all(_generate_code_flags(archs))
    args.add_all(cuda_toolchain.compile_args)

    args.add_all(compilation_context.includes, before_each = "-I")
    args.add_all(compilation_context.quote_includes, before_each = "-I")
    args.add_all(compilation_context.system_includes, before_each = "-isystem")
    args.add_all(compilation_context.external_includes, before_each = "-isystem")
    args.add_all(compilation_context.defines, before_each = "-D")
    for define in ctx.attr.local_defines:
        expanded = ctx.expand_location(define, targets = ctx.attr.additional_compiler_inputs)
        tokens = ctx.tokenize(ctx.expand_make_variables("local_defines", expanded, {}))
        if len(tokens) != 1:
            fail("local_defines entry must expand to one token: " + define)
        args.add("-D", tokens[0])

    args.add_all(host_flags, map_each = _quote_tool_option, format_each = "-Xcompiler=%s")

    args.add_all(ctx.attr.copts)
    args.add_all(ctx.attr.host_copts, map_each = _quote_tool_option, format_each = "-Xcompiler=%s")
    args.add_all(ctx.attr.ptxasopts, map_each = _quote_tool_option, format_each = "-Xptxas=%s")

    inputs = depset(
        direct = ctx.files.additional_compiler_inputs,
        transitive = [
            compilation_context.headers,
            cuda_toolchain.toolkit_files,
            cc_toolchain.all_files,
        ],
    )
    return struct(args = args, inputs = inputs)

def compile_cuda_object(ctx, cuda_toolchain, compilation, src):
    """Compiles one .cu file to an object file. Returns the object File."""
    # Preserve package paths and keep external repositories in a separate namespace.
    relative = ("external/" + src.short_path[3:]) if src.short_path.startswith("../") else ("workspace/" + src.short_path)
    obj = ctx.actions.declare_file(
        "_objs/{}/{}.o".format(ctx.label.name, relative.removesuffix(".cu")),
    )
    args = ctx.actions.args()
    args.add("-c", src)
    args.add("-o", obj)

    ctx.actions.run(
        mnemonic = "CudaCompile",
        progress_message = "Compiling CUDA " + src.short_path,
        executable = cuda_toolchain.nvcc,
        arguments = [args, compilation.args],
        inputs = depset([src], transitive = [compilation.inputs]),
        outputs = [obj],
        toolchain = Label("//bazel/cuda/toolchain:toolchain_type"),
    )
    return obj
