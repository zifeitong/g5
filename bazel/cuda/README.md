# CUDA rules

Hermetic CUDA compilation: nvcc from NVIDIA's pinned redistributable
archives, driving hermetic-llvm's clang as host compiler, against
hermetic-llvm's hermetic libstdc++/GCC runtime. No system CUDA, compiler, or
sysroot.

## Usage

```starlark
load("@rules_cc//cc:cc_binary.bzl", "cc_binary")
load("//bazel/cuda:cuda_library.bzl", "cuda_library")

cuda_library(
    name = "kernels",
    srcs = ["kernels.cu"],
    hdrs = ["kernels.cuh"],
)

cc_binary(
    name = "app",
    srcs = ["main.cc"],
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

Headers, include prefixes, defines, dependencies, additional compiler inputs,
and features are explicit `cuda_library` attributes. `implementation_deps`
supplies headers and defines to CUDA compilation without exposing them to
consumers. Other `cc_library` options, such as `alwayslink`, `linkstatic`,
and `visibility`, are forwarded; `linkstatic` defaults to `True`.
Global `--copt` and `--cxxopt` flags are forwarded through `-Xcompiler`.

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
is not published for the host's platform.

## Why `--config=cuda`

nvcc's EDG-based device frontend cannot parse modern libc++ headers (this
repo's default C++ standard library), and CUDA's own headers depend on
libstdc++/older libc++ internals. The supported nvcc configuration is
libstdc++ — the same choice XLA/JAX ship with. `--config=cuda` selects
`//bazel/cuda/platforms:linux`, which swaps the whole build onto
hermetic-llvm's hermetic libstdc++ (GCC 14.2 runtime, built from source). Do
not link libc++-built objects and libstdc++-built objects into one binary.

Outside the CUDA configuration, `cuda_library` targets are skipped as
incompatible, and so is anything depending on one, since incompatibility is
transitive. `bazel build //...` stays green on the default platform.

## Layout

- `cuda_library.bzl` — public API: the macro creates a private header-only
  `cc_library`, a `cuda_objects` target, and the final `cc_library`. The
  header library supplies Bazel's include paths and header exports to both
  nvcc and C++ consumers; the final library packages and links the objects.
- `toolkit/` — the CUDA toolkit itself. `repo.bzl` pins a release label and
  the sha256 of NVIDIA's manifest for it, lists the 7 of ~40 published
  components these rules need, and stages them all at a single repository root
  so the result mirrors a normal toolkit install; the manifest supplies each
  component's version, path and hash. `toolkit.BUILD.bazel` exposes the
  headers, the static runtime and the driver link stub.
- `toolchain/` — toolchain type, `cuda_toolchain` rule, nvcc wiring, and the
  default nvcc flags as its `compile_args` attribute. The rule returns a
  native `ToolchainInfo` with its fields directly accessible; field types
  and attribute meanings are documented in `cuda_toolchain.bzl`.
- `private/compile.bzl` — one `CudaCompile` action per source: nvcc with
  `-ccbin` pointed at the resolved cc_toolchain's clang, and host flags
  extracted via `cc_common` and forwarded through `-Xcompiler`. Arguments
  and common inputs are prepared once per target and shared by its actions.
  Forwarded tool options are escaped for nvcc's parsing so embedded commas,
  quotes and backslashes survive. Because the
  toolkit is staged as one tree, `bin/nvcc.profile` locates cicc, libdevice,
  the toolkit headers and the link stubs on its own.
- `private/cuda_objects.bzl` — the `cuda_objects` rule, which produces the
  `.o` files and merges dependency compilation contexts through `cc_common`.
  `cc_library` owns header export, archiving and linking.
- `BUILD.bazel` — the architecture list flag, using bazel-skylib's
  `string_list_flag` and `BuildSettingInfo`.
- `platforms/` — the libstdc++ platform for CUDA builds.

## Known limitations

- No RDC / device linking / DLTO (not needed for whole-program kernels,
  CUTLASS, Thrust, or the NCCL device API; NVSHMEM device-API code from
  source would need it). `libcudadevrt.a` and `libculibos.a` are already
  staged, and adding it is additive rather than an API break, so the missing
  pieces are the device-link action and a `CudaInfo` on `_cuda_objects`.
- Native builds only: `toolkit/repo.bzl` picks the toolkit from the host
  arch and `platforms:linux` takes its CPU from the host, because the
  toolchains require exec arch to equal target arch. Linux x86_64 and
  aarch64 (NVIDIA's `linux-sbsa`) both work with no extra flags.
  Cross-compiling would stage the target's components under
  `targets/sbsa-linux/` and pass nvcc `--target-directory`, which breaks
  the single flat tree the toolkit relies on.
- nvcc only (no clang-CUDA mode yet).
- CUDA 13.4.3 pinned in `toolkit/repo.bzl`. nvcc 13.4 accepts up to `c++23`,
  and `cuda_std` (`c++23`) is the dialect its frontend is *told*. The
  libstdc++ headers inside a `.cu` expand at `host_std` (`c++17`), appended
  through `-Xcompiler` after the cc toolchain and global flags. The two
  dialects differ on purpose: C++17 keeps library code EDG cannot parse
  out of the device pass. Measured scope: a `.cu` reaching libstdc++'s
  `<atomic>` at C++20+ fails on `__builtin_clear_padding`, instantiated for
  `atomic<long double>` as the header is parsed — no user code needed. A TU
  containing only `#include <atomic>` reproduces it, and Thrust reaches it
  transitively. Everything else here built fine with the host pass at C++23.
  `cuda_std` and `host_std` are toolchain attributes. A target can override
  the host dialect with `host_copts = ["-std=c++23"]`, subject to the
  frontend limitation above.
- Running anything needs an NVIDIA driver. Without `libcuda.so.1` the loader
  fails before `main`. A build machine without a driver can still provide
  compile-and-link coverage.
