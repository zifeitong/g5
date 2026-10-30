"""Build settings for the CUDA rules."""

load(":providers.bzl", "ArchsInfo")

def _archs_flag_impl(ctx):
    # Values are checked in compile.bzl, which also sees per-target archs.
    return ArchsInfo(archs = ctx.build_setting_value)

archs_flag = rule(
    implementation = _archs_flag_impl,
    build_setting = config.string_list(flag = True),
    doc = "CUDA archs, e.g. --//bazel/cuda:archs=sm_90a,compute_90. " +
          "sm_XX emits SASS, compute_XX emits PTX.",
)
