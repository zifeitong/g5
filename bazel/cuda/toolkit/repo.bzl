"""Downloads pinned CUDA components into one toolkit-shaped tree.

The manifest hash pins component versions and hashes. The flat layout lets
nvcc.profile resolve tools, headers, and libdevice relative to the driver.
"""

# Update the release and manifest hash together; see README's "Bumping CUDA".
# Check release_label too: a content-addressed cache can serve an old manifest
# when a new URL is accidentally paired with the old hash.
CUDA_VERSION = "13.5.0"

_BASE_URL = "https://developer.download.nvidia.com/compute/cuda/redist/"
_MANIFEST_URL = "{}redistrib_{}.json".format(_BASE_URL, CUDA_VERSION)
_MANIFEST_SHA256 = "401529e951b845788177f999c0756c520c4d0db1cd4cd05c0a295e331884b596"

# Native Linux archives; rctx.os.arch uses Java's architecture names.
_PLATFORMS = {"amd64": "linux-x86_64", "aarch64": "linux-sbsa"}
_MANIFEST = "redistrib.json"

_COMPONENTS = [
    "cccl",
    "cuda_crt",
    "cuda_cudart",
    "cuda_nvcc",
    "cuda_profiler_api",
    # Static runtime support, separate from cuda_cudart since CUDA 13.
    "cuda_culibos",
    # cicc and libdevice.
    "libnvvm",
]

def _cuda_toolkit_repository_impl(rctx):
    platform = _PLATFORMS.get(rctx.os.arch)
    if not platform:
        fail("no CUDA toolkit is published for {}".format(rctx.os.arch))

    rctx.download(
        url = _MANIFEST_URL,
        output = _MANIFEST,
        sha256 = _MANIFEST_SHA256,
    )
    manifest = json.decode(rctx.read(_MANIFEST))
    rctx.delete(_MANIFEST)

    if manifest["release_label"] != CUDA_VERSION:
        fail("CUDA_VERSION is {} but _MANIFEST_SHA256 pins CUDA {}; update one to match the other".format(
            CUDA_VERSION,
            manifest["release_label"],
        ))

    for name in _COMPONENTS:
        if name not in manifest:
            fail("{} is not in CUDA {}'s manifest".format(name, CUDA_VERSION))
        component = manifest[name]
        if platform not in component:
            fail("{} has no {} build in CUDA {}".format(name, platform, CUDA_VERSION))

        # Each archive wraps the toolkit files in a directory named after itself.
        relative_path = component[platform]["relative_path"]
        rctx.download_and_extract(
            url = _BASE_URL + relative_path,
            sha256 = component[platform]["sha256"],
            stripPrefix = relative_path.rsplit("/", 1)[-1].removesuffix(".tar.xz"),
        )

    rctx.template(
        "BUILD.bazel",
        rctx.attr._build_file,
        substitutions = {"{CUDA_VERSION}": CUDA_VERSION},
        executable = False,
    )

cuda_toolkit_repository = repository_rule(
    implementation = _cuda_toolkit_repository_impl,
    attrs = {
        "_build_file": attr.label(
            default = Label("//bazel/cuda:toolkit/toolkit.BUILD.bazel"),
            allow_single_file = True,
        ),
    },
    doc = "The pinned CUDA toolkit, extracted as a single toolkit-shaped tree.",
)
