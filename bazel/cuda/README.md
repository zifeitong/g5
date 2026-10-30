# CUDA rules

Hermetic CUDA compilation: nvcc from NVIDIA's pinned redistributable
archives, driving hermetic-llvm's clang as host compiler, against
hermetic-llvm's hermetic libstdc++/GCC runtime. No system CUDA, compiler, or
sysroot.

## Usage

```starlark
load("//bazel/cuda:defs.bzl", "cuda_library", "requires_cuda")

cuda_library(
    name = "kernels",
    srcs = ["kernels.cu"],
    hdrs = ["kernels.cuh"],
)

cc_binary(
    name = "app",
    srcs = ["main.cc"],
    target_compatible_with = requires_cuda(),
    deps = [
        ":kernels",
        "@cuda_toolkit//:cudart_static",
    ],
)
```

Build with:

```sh
bazel build --config=cuda //path/to:app
```

Select architectures globally with `--//bazel/cuda:archs=sm_90a,compute_90`
(`sm_XX` emits SASS, `compute_XX` embeds PTX for forward compatibility) or
per target with the `archs` attribute. Extra flags: `copts` (nvcc),
`host_copts` (`-Xcompiler`), `ptxasopts` (`-Xptxas`).

## Bumping CUDA

Set `CUDA_VERSION` in `toolkit/repo.bzl`, then replace `_MANIFEST_SHA256`
with the sha256 of that release's manifest:

```sh
curl -sL https://developer.download.nvidia.com/compute/cuda/redist/redistrib_<label>.json |
  shasum -a 256
```

Building without updating the hash also works: Bazel reports the one it got,
and that is the value to paste in. Nothing else needs touching — component
versions, paths and hashes all come from the manifest, and the fetch fails
with a clear message if a listed component is missing from the new release or
is not published for the pinned platform.

## Why `--config=cuda`

nvcc's EDG-based device frontend cannot parse modern libc++ headers (this
repo's default C++ standard library), and CUDA's own headers depend on
libstdc++/older libc++ internals. The supported nvcc configuration is
libstdc++ — the same choice XLA/JAX ship with. `--config=cuda` selects
`//bazel/cuda/platforms:linux_x86_64`, which swaps the whole build onto
hermetic-llvm's hermetic libstdc++ (GCC 14.2 runtime, built from source). Do
not link libc++-built objects and libstdc++-built objects into one binary.

Outside the CUDA configuration, `cuda_library` targets (and anything marked
`requires_cuda()`) are skipped as incompatible, so `bazel build //...` stays
green on the default platform.

## Layout

- `defs.bzl` — public API: `cuda_library`, `requires_cuda`.
- `toolkit/` — the CUDA toolkit itself. `repo.bzl` pins a release label and
  the sha256 of NVIDIA's manifest for it, lists the 7 of ~40 published
  components these rules need, and stages them all at a single repository root
  so the result mirrors a normal toolkit install; the manifest supplies each
  component's version, path and hash. `toolkit.BUILD.bazel` exposes the
  headers, the static runtime and the driver link stub.
- `toolchain/` — toolchain type, `cuda_toolchain` rule, nvcc wiring, default
  nvcc flags as `cuda_args` targets.
- `private/compile.bzl` — the single `CudaCompile` action: nvcc with
  `-ccbin` pointed at the resolved cc_toolchain's clang, and host flags
  extracted via `cc_common` and forwarded through `-Xcompiler`. Because the
  toolkit is staged as one tree, `bin/nvcc.profile` locates cicc, libdevice,
  the toolkit headers and the link stubs on its own.
- `private/cuda_library.bzl` — `_cuda_objects` rule (produces `.o` files) +
  `cuda_library` macro wrapping them into a `cc_library`, which owns provider
  assembly and the full `cc_library` attribute surface. A rule returning
  `CcInfo` directly is possible — only `cc_common.create_library_to_link` is
  allowlisted, and it is not needed — and is the route to RDC, since a
  device-link step needs a `CudaInfo` propagated beside `CcInfo` and a macro
  cannot return providers.
- `platforms/` — libstdc++ platforms for CUDA builds.
- `tests/` — saxpy (mixed nvcc/clang binary), a Thrust compile stress test,
  and `flash_attn`, a FlashAttention-2 forward pass (KV-block tiling,
  online softmax, epilogue normalization, parallel over sequence length)
  with a double-precision host reference. Algorithmically faithful but not
  performance-tuned: no tensor cores, no warp specialization.

## Known limitations

- No RDC / device linking / DLTO (not needed for whole-program kernels,
  CUTLASS, Thrust, or the NCCL device API; NVSHMEM device-API code from
  source would need it). `libcudadevrt.a` and `libculibos.a` are already
  staged, and adding it is additive rather than an API break, so the missing
  pieces are the device-link action and a `CudaInfo` on `_cuda_objects`.
- Linux x86_64 only: `toolkit/repo.bzl` pins `_PLATFORM` to `linux-x86_64`,
  and `--config=cuda` selects
  `//bazel/cuda/platforms:linux_x86_64`. A `linux_aarch64` platform exists
  but would also need `linux-sbsa` pins, and nvcc.profile resolves headers
  under `targets/sbsa-linux/` for cross builds.
- nvcc only (no clang-CUDA mode yet).
- CUDA 13.4.3 pinned in `toolkit/repo.bzl`. nvcc 13.4 accepts up to `c++23`,
  and `cuda_std` (`c++23`) is the dialect its frontend is *told*. The
  libstdc++ headers inside a `.cu` still expand at the cc toolchain's own
  `-std`, which `compile.bzl` forwards through `-Xcompiler`, so the two
  differ on purpose: that older dialect keeps C++20 library code EDG cannot
  parse out of the device pass. Measured scope: a `.cu` reaching libstdc++'s
  `<atomic>` at C++20+ fails on `__builtin_clear_padding`, instantiated for
  `atomic<long double>` as the header is parsed — no user code needed. A TU
  containing only `#include <atomic>` reproduces it, and Thrust reaches it
  transitively. Everything else here built fine with the host pass at C++23.
  `cuda_std` is a toolchain attribute, so there is no per-target override.
- Running anything needs an NVIDIA driver. Without `libcuda.so.1` the loader
  fails before `main`, so the no-device guards inside the smoke binaries only
  fire where a driver is installed but exposes no GPU; on a build machine
  these targets are compile-and-link coverage only.
