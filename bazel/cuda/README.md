# CUDA rules

Hermetic CUDA compilation: nvcc from NVIDIA's pinned redistributable
archives, driving hermetic-llvm's clang as host compiler, against
hermetic-llvm's hermetic libc++ runtime by default. libstdc++ is also
supported. No system CUDA, compiler, or sysroot.

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
bazel build //path/to:app
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

## C++ standard library

CUDA builds use the default libc++ platform. `--config=libstdcxx` opts into
libstdc++ (GCC 14.2); it selects `//bazel/cuda/platforms:linux` for the
whole build. Do not mix objects built against the two standard libraries in
one binary.

LLVM 22.1.8 is selected in `MODULE.bazel` for both the compiler and its
runtimes. C++23 is the supported dialect for CUDA and host compilation.
CUDA targets require Linux.

Older dialects have additional compatibility requirements: libc++ C++17/20
requires additional annotations for device-side `std::signbit` calls.
Revalidate standard-library compatibility when updating LLVM or CUDA.

## Kernel linkage

CUDA 13 gives template kernel host stubs internal linkage by default. If a
kernel template is explicitly instantiated in one `.cu` file and launched from
another, apply this option to both targets (or their shared `cuda_library`):

```starlark
copts = ["--static-global-template-stub=false"]
```

This permits external template stubs, and nvcc documents the cost as a
correctness problem rather than a linkage detail: the stub gets weak linkage, so
the host linker keeps one instantiation, while each translation unit still forms
its own device program with its own copy of the kernel. A launch can therefore
dispatch into another translation unit's copy. Use it only where the
instantiations are genuinely identical, and keep the default when each
translation unit owns its kernel definitions and launches.

CUDA 13 also hides kernel symbols across shared-library boundaries.
`--device-entity-has-hidden-visibility=false` permits those references; template
kernels crossing that boundary need both options. The calling code and kernel
library must use the same CUDA runtime. Our linkage probes use one shared
CUDART; the public `cudart_static` target does not provide that setup. Exporting
a host launch function from the kernel library avoids exposing the kernel stub.
These options control host stub linkage and visibility; they do not add RDC or
device linking.

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
  quotes and backslashes survive. Because the toolkit is staged as one tree, `bin/nvcc.profile` locates cicc, libdevice,
  the toolkit headers and the link stubs on its own.
- `private/cuda_objects.bzl` — the `cuda_objects` rule, which produces the
  `.o` files and merges dependency compilation contexts through `cc_common`.
  `cc_library` owns header export, archiving and linking.
- `BUILD.bazel` — the architecture list flag, using bazel-skylib's
  `string_list_flag` and `BuildSettingInfo`.
- `platforms/` — the optional libstdc++ platform for CUDA builds.

## Known limitations

### Device-side std::bit_cast

With CUDA 13.5.37 and Clang 22.1.8, device-side `std::bit_cast` can generate
incorrect code when returning a non-literal, trivially copyable type, such as
an Eigen-like half type with non-constexpr constructors. We reproduced this
with both libc++ 22.1.8 and libstdc++ 14.2 in C++23: nvcc emitted warnings
`20011` and `20014`, but compilation succeeded and the kernel's expected
load/XOR/store became only `ret` in PTX. The toolkit applies no automatic shim.

Use `cuda::std::bit_cast` or `__builtin_bit_cast` in affected device code, or
provide a targeted host/device annotation pre-include as demonstrated by
[rules_ml_toolchain](https://github.com/google-ml-infra/rules_ml_toolchain/blob/9ff8598c6dfa182f4fd49f9af761c67bc2e50abd/gpu/cuda/clang/clang_cuda_runtime_wrapper.h).
To reject invalid host/device calls for a target, use:

```starlark
copts = ["--diag-error=20011", "--diag-error=20014"]
```

These diagnostics cover other host/device calls too and can be noisy in generic
code. Library pragmas or warning suppression can hide them; successful
compilation alone does not establish correct device code.

### Other limitations

- With libstdc++ 14.2, nvcc 13.5 rejects `std::tuple{...}` class template
  argument deduction in C++20/23. Explicit tuple types work; libc++ passes
  the deduction probe.
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
- CUDA 13.5.0 is pinned in `toolkit/repo.bzl`. `cuda_std`, a toolchain
  attribute defaulting to `c++23`, is the device dialect nvcc is told to use.
  The host dialect comes from the cc toolchain and the global
  `--copt`/`--cxxopt` -- `.bazelrc` sets `-std=c++23` -- and `host_copts`
  overrides it per target. The two are not independent: nvcc preprocesses
  with the host compiler before cicc, so the host `-std` also decides which
  standard-library code the device frontend sees. That is why an older host
  dialect is not a free lever -- on libc++ anything below `c++23` fails in
  the device pass on `std::signbit`.
- Binaries linked through `@cuda_toolkit//:cudart_static` need an NVIDIA
  driver: without `libcuda.so.1` the loader fails before `main`. Host-only
  checks can omit the driver dependency; GPU execution still needs it.
