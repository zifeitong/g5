"""Pinned CUDA toolkit component archives.

Regenerate after changing CUDA_VERSION with:

    python3 bazel/cuda/toolkit/update_pins.py <version>

Only the components //bazel/cuda actually needs are pinned: the nvcc driver
and its sub-tools, the NVVM device frontend, the CUDA runtime, and headers.
The archives extract into one flat tree mirroring a normal toolkit install,
which is what lets bin/nvcc.profile resolve cicc, libdevice, the toolkit
headers and the stub libraries on its own.
"""

CUDA_VERSION = "13.4.3"

_BASE = "https://developer.download.nvidia.com/compute/cuda/redist/"

def _component(name, version, sha256, platform = "linux-x86_64"):
    stem = "{}-{}-{}-archive".format(name, platform, version)
    return struct(
        name = name,
        version = version,
        url = "{}{}/{}/{}.tar.xz".format(_BASE, name, platform, stem),
        sha256 = sha256,
        strip_prefix = stem,
    )

COMPONENTS = [
    # nvcc, ptxas, fatbinary, cudafe++, nvlink, nvcc.profile.
    _component("cuda_nvcc", "13.4.92", "60998f40cc9df5826b2a846e2dcc328133fbc5ef539398ce0a21cf5dcac7193d"),
    # cicc (the device frontend) and libdevice bitcode.
    _component("libnvvm", "13.4.92", "0e619cf3d5b27f7c812665599ca9761fc296e56129b24a85d822a5d8a1a3bd75"),
    # include/crt: the headers nvcc's generated host code includes.
    _component("cuda_crt", "13.4.92", "c969e61ded12dbf0cf20ace72867f1622ec0e8ea1e1d305e27761012025f7aaa"),
    # Runtime headers, libcudart_static.a, libcudadevrt.a, libcuda.so stub.
    _component("cuda_cudart", "13.4.92", "0ac5dbc538d04e9983bc493b410cce4b459e1ee9f5f6654b6464ef7b3e14a8b5"),
    # libculibos.a, which the static runtime needs. Its own component since
    # CUDA 13; before that it shipped inside cuda_cudart.
    _component("cuda_culibos", "13.4.92", "241c618719e0613ce73b781c4e84b5eccf04e5baa3bae57de07980edb68a0e55"),
    # Thrust, CUB and libcu++, which nvcc.profile exposes via -isystem.
    _component("cccl", "13.3.4.3.1", "6b7516074f42f80dd3feb9c11318c8e1c5ab56cdd9f18fff4c5ace2e7e0a8209"),
    _component("cuda_profiler_api", "13.4.92", "9d405e9b0fd9a5c29e680d6f6750b9ca79b7df91e253d4dffea3495057a75f08"),
]
