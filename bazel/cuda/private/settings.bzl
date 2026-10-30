"""Build settings for the CUDA rules (self-contained, no skylib dependency)."""

load(":providers.bzl", "ArchsInfo")

def _archs_flag_impl(ctx):
    archs = [a.strip() for a in ctx.build_setting_value.split(",") if a.strip()]
    for arch in archs:
        if not (arch.startswith("sm_") or arch.startswith("compute_")):
            fail("--{}: bad arch '{}'; expected sm_XX or compute_XX".format(ctx.label, arch))
    return ArchsInfo(archs = archs)

archs_flag = rule(
    implementation = _archs_flag_impl,
    build_setting = config.string(flag = True),
    doc = "Comma-separated CUDA archs, e.g. 'sm_90a,compute_90'. sm_XX emits SASS, compute_XX emits PTX.",
)
