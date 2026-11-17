# CUDA rules

Hermetic nvcc builds for native Linux x86_64 and aarch64. CUDA 13.5.0 and
Clang/libc++ 22.1.8 are pinned; CUDA and host code default to C++23.
No system CUDA, compiler, or sysroot is required.

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
    deps = [":kernels", "@cuda_toolkit//:cudart_static"],
)
```

```sh
bazel build //path/to:app
```

On Linux, the project targets glibc 2.43 (Ubuntu 26.04 LTS), including build tools.
libc++ is the default. `--config=libstdcxx` selects libstdc++ 16.1.0.
Keep the standard library consistent across linked objects.
CUDA targets are incompatible with Windows and macOS.

Set architectures with `--//bazel/cuda:archs=sm_90a,compute_90` or the target's
`archs` attribute. `sm_XX` emits SASS; `compute_XX` embeds PTX.
Use `copts` for nvcc flags, `host_copts` for `-Xcompiler`, and `ptxasopts`
for `-Xptxas`. Global `--copt` and `--cxxopt` flags also go through `-Xcompiler`.

Attribute routing is explicit:

| Attributes | Apply to |
| --- | --- |
| `copts`, `host_copts`, `ptxasopts`, `local_defines`, compiler inputs | CUDA compilation |
| Headers, include prefixes, `includes`, `defines`, `deps` | CUDA compilation and consumers |
| `implementation_deps` | Private compilation dependencies and final linking |
| Features, target compatibility, `exec_compatible_with`, `exec_properties`, tags, `testonly`, Make-variable `toolchains` | All generated targets |
| Remaining `cc_library` kwargs, including link options and `alwayslink` | Final `cc_library` |

`linkstatic` defaults to `True`. Kwargs do not automatically configure nvcc.
`cxxopts` is rejected; use `host_copts` or `copts`. `local_includes` is rejected;
use `implementation_deps` for private header/include dependencies.
`exec_group_compatible_with` uses native C++ exec-group names and applies only
to the final library; use `exec_compatible_with` to constrain CUDA execution.

`cuda_std` in the CUDA toolchain selects nvcc's dialect. The C++ toolchain and
global flags select the host dialect, with per-target overrides in `host_copts`.
The host dialect also controls which standard-library declarations nvcc sees
during preprocessing; lowering it can break device compilation.

## Kernel linkage

CUDA 13 makes template kernel host stubs internal by default. For a template
instantiated in one `.cu` file and launched from another, apply to both targets:

```starlark
copts = ["--static-global-template-stub=false"]
```

This makes stubs weak: the host linker can merge them while their device
programs remain separate. A launch can dispatch into another translation unit's
kernel. Use this only for identical instantiations; otherwise keep the default.

Cross-library kernel references also need
`--device-entity-has-hidden-visibility=false`; template kernels need both flags.
Calling code and kernel stubs must share the CUDA runtime. Our probes use one
shared CUDART, which the public `cudart_static` target does not provide. Export a
host launch function to keep kernel stubs private.
These flags do not add device linking.

## Limitations

- No RDC, device linking, DLTO, cross-compilation, or clang-CUDA mode.
- libc++ C++17/20 needs additional device annotations for `std::signbit`;
  C++23 is the supported dialect.
- `cudart_static` requires the installed driver's `libcuda.so.1` at process
  startup. Builds and host-only probes can run without a GPU.

### Device-side std::bit_cast

With nvcc 13.5.37 and the pinned LLVM, `std::bit_cast` returning a non-literal,
trivially copyable type (such as an Eigen-like half) can silently miscompile.
Our C++23 probe failed with both standard libraries: nvcc warned with `20011`
and `20014`, yet emitted only `ret` instead of the kernel's load/XOR/store.
No automatic shim is applied.

Use `cuda::std::bit_cast`, `__builtin_bit_cast`, or a
[targeted annotation header](https://github.com/google-ml-infra/rules_ml_toolchain/blob/9ff8598c6dfa182f4fd49f9af761c67bc2e50abd/gpu/cuda/clang/clang_cuda_runtime_wrapper.h).
To make invalid host/device calls errors for a target:

```starlark
copts = ["--diag-error=20011", "--diag-error=20014"]
```

These diagnostics can be noisy in generic code, and library pragmas can suppress
them. Successful compilation alone does not establish correct device code.

## Bumping CUDA

Update `CUDA_VERSION` and `_MANIFEST_SHA256` in `toolkit/repo.bzl`:

```sh
curl -sL https://developer.download.nvidia.com/compute/cuda/redist/redistrib_<label>.json |
  shasum -a 256
```

Component versions and hashes come from that manifest. Revalidate compiler and
standard-library compatibility when updating CUDA or LLVM.

## Layout

- `cuda_library.bzl`: header-only `cc_library`, CUDA objects, and final
  `cc_library` for archiving/linking.
- `private/`: nvcc actions using host flags from the resolved C++ toolchain.
- `toolchain/`: nvcc configuration and toolchain registration.
- `toolkit/`: pinned components extracted into one toolkit-shaped tree,
  plus headers, static runtime, and driver-stub targets.
