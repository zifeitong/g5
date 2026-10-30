"""cuda_args: flag bundles for CUDA actions, in the style of rules_cc's cc_args.

rules_cc's own ArgsInfo/ArgsListInfo providers have restricted load visibility
(only ExecutionRequirementsInfo is re-exported publicly as of 0.2.22), so this
is a minimal local equivalent: literal args bound to named actions, with
optional data files. No variable expansion — dynamic flags belong in the
compile action.
"""

CUDA_COMPILE_ACTION_NAME = "cuda-compile"

CudaArgsInfo = provider(
    doc = "Literal arguments contributed to CUDA actions.",
    fields = {
        "actions": "list[str]: action names these args apply to.",
        "args": "list[str]: the arguments.",
        "files": "depset[File]: files required when these args are used.",
    },
)

def _cuda_args_impl(ctx):
    return [CudaArgsInfo(
        actions = ctx.attr.actions,
        args = ctx.attr.args,
        files = depset(ctx.files.data),
    )]

cuda_args = rule(
    implementation = _cuda_args_impl,
    attrs = {
        "actions": attr.string_list(default = [CUDA_COMPILE_ACTION_NAME]),
        "args": attr.string_list(mandatory = True),
        "data": attr.label_list(allow_files = True),
    },
    provides = [CudaArgsInfo],
)

def evaluate_args(targets, action_name):
    """Collects flags/files from cuda_args targets for one action name.

    Returns:
        (list[str] flags, depset[File] files)
    """
    flags = []
    transitive_files = []
    for target in targets:
        info = target[CudaArgsInfo]
        if action_name not in info.actions:
            continue
        flags.extend(info.args)
        transitive_files.append(info.files)
    return flags, depset(transitive = transitive_files)
