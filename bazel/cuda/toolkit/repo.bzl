"""Downloads the pinned CUDA toolkit components into one flat tree."""

load(":pins.bzl", "COMPONENTS", "CUDA_VERSION")

def _cuda_toolkit_repository_impl(rctx):
    # Every component extracts at the repository root, so the result mirrors a
    # normal toolkit install: bin/nvcc beside bin/nvcc.profile, nvvm/bin/cicc,
    # nvvm/libdevice, include/, lib/. The archives do not share file paths
    # apart from LICENSE.
    for component in COMPONENTS:
        rctx.download_and_extract(
            url = component.url,
            sha256 = component.sha256,
            stripPrefix = component.strip_prefix,
        )

    cudart = [c for c in COMPONENTS if c.name == "cuda_cudart"]
    if len(cudart) != 1:
        fail("expected exactly one cuda_cudart pin")

    rctx.template(
        "BUILD.bazel",
        rctx.attr._build_file,
        substitutions = {
            "{CUDA_VERSION}": CUDA_VERSION,
            # libcudart.so's full version suffix tracks the component version.
            "{CUDART_VERSION}": cudart[0].version,
        },
        executable = False,
    )

cuda_toolkit_repository = repository_rule(
    implementation = _cuda_toolkit_repository_impl,
    attrs = {
        "_build_file": attr.label(
            default = Label("//bazel/cuda/toolkit:toolkit.BUILD.bazel"),
            allow_single_file = True,
        ),
    },
    doc = "The pinned CUDA toolkit, extracted as a single toolkit-shaped tree.",
)
