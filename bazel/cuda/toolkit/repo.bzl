"""Downloads the pinned CUDA toolkit components into one flat tree.

The release label is pinned together with the sha256 of NVIDIA's manifest for
it; the manifest then supplies each component's version, path and hash.
Pinning the manifest is what keeps this hermetic -- without it NVIDIA could
republish redistrib_<label>.json and the components would change underneath a
fixed label.

Everything extracts at the repository root, so the result mirrors a normal
toolkit install and bin/nvcc.profile resolves cicc, libdevice, the toolkit
headers and the stub libraries on its own.
"""

# Bump: set CUDA_VERSION, then replace _MANIFEST_SHA256 with the sha256 of
# that release's manifest. See "Bumping CUDA" in ../README.md.
#
# The hash alone does not keep these two honest. Bazel's repository cache is
# content-addressed, so a URL naming one release paired with another release's
# hash is served from cache without a download, and the build silently
# reports the version in CUDA_VERSION while containing the other release's
# components. The impl therefore checks CUDA_VERSION against the label the
# manifest states about itself.
CUDA_VERSION = "13.4.3"

_BASE_URL = "https://developer.download.nvidia.com/compute/cuda/redist/"
_MANIFEST_URL = "{}redistrib_{}.json".format(_BASE_URL, CUDA_VERSION)
_MANIFEST_SHA256 = "1420d5c676cad98a5ff423d529f116fee92f6b99559a3afdad41e782d6a11dba"
_PLATFORM = "linux-x86_64"
_MANIFEST = "redistrib.json"

_COMPONENTS = [
    "cccl", "cuda_crt", "cuda_cudart", "cuda_nvcc", "cuda_profiler_api",
    # libculibos.a, needed by the static runtime. Its own component since
    # CUDA 13; before that it shipped inside cuda_cudart.
    "cuda_culibos",
    # cicc, the device compiler itself, plus libdevice bitcode.
    "libnvvm",
]

def _cuda_toolkit_repository_impl(rctx):
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
        if _PLATFORM not in component:
            fail("{} has no {} build in CUDA {}".format(name, _PLATFORM, CUDA_VERSION))
        # Every component NVIDIA publishes uses its archive's basename, minus
        # the .tar.xz suffix, as the single top-level directory inside it.
        relative_path = component[_PLATFORM]["relative_path"]
        rctx.download_and_extract(
            url = _BASE_URL + relative_path,
            sha256 = component[_PLATFORM]["sha256"],
            stripPrefix = relative_path.rsplit("/", 1)[-1].removesuffix(".tar.xz"),
        )

    rctx.template(
        "BUILD.bazel",
        rctx.attr._build_file,
        substitutions = {"{CUDA_VERSION}": CUDA_VERSION},
        executable = False,
    )

_cuda_toolkit_repository = repository_rule(
    implementation = _cuda_toolkit_repository_impl,
    attrs = {
        "_build_file": attr.label(
            default = Label("//bazel/cuda:toolkit/toolkit.BUILD.bazel"),
            allow_single_file = True,
        ),
    },
    doc = "The pinned CUDA toolkit, extracted as a single toolkit-shaped tree.",
)

def _cuda_toolkit_extension_impl(_module_ctx):
    _cuda_toolkit_repository(name = "cuda_toolkit")

cuda_toolkit = module_extension(implementation = _cuda_toolkit_extension_impl)
