// Mixed host/device binary: this file is compiled by hermetic-llvm's clang,
// saxpy.cu by nvcc. Exercises kernel launch, cudart linking, and the ABI
// boundary between the two toolchains.

#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

#include "bazel/cuda/tests/saxpy.cuh"

#include <cuda_runtime.h>

namespace {

#define CHECK_CUDA(expr)                                                     \
  do {                                                                       \
    cudaError_t err = (expr);                                                \
    if (err != cudaSuccess) {                                                \
      std::fprintf(stderr, "%s failed: %s\n", #expr, cudaGetErrorString(err)); \
      return EXIT_FAILURE;                                                   \
    }                                                                        \
  } while (0)

}  // namespace

int main() {
  int device_count = 0;
  cudaError_t err = cudaGetDeviceCount(&device_count);
  if (err != cudaSuccess || device_count == 0) {
    // Only reachable where a driver is installed but exposes no GPU. With
    // no libcuda.so.1 at all the loader fails before main, so on a plain
    // build machine this binary is compile-and-link coverage only.
    std::string message = "CUDA driver present but no device; skipping\n";
    std::fprintf(stderr, "%s", message.c_str());
    return EXIT_SUCCESS;
  }

  constexpr int kN = 1 << 20;
  constexpr float kA = 2.0f;
  std::vector<float> host_x(kN, 1.0f);
  std::vector<float> host_y(kN, 3.0f);

  float* device_x = nullptr;
  float* device_y = nullptr;
  CHECK_CUDA(cudaMalloc(&device_x, kN * sizeof(float)));
  CHECK_CUDA(cudaMalloc(&device_y, kN * sizeof(float)));
  CHECK_CUDA(cudaMemcpy(device_x, host_x.data(), kN * sizeof(float), cudaMemcpyHostToDevice));
  CHECK_CUDA(cudaMemcpy(device_y, host_y.data(), kN * sizeof(float), cudaMemcpyHostToDevice));

  CHECK_CUDA(cuda_tests::Saxpy(kN, kA, device_x, device_y));
  CHECK_CUDA(cudaMemcpy(host_y.data(), device_y, kN * sizeof(float), cudaMemcpyDeviceToHost));

  for (int i = 0; i < kN; ++i) {
    if (host_y[i] != 5.0f) {
      std::fprintf(stderr, "mismatch at %d: %f != 5.0\n", i, host_y[i]);
      return EXIT_FAILURE;
    }
  }
  std::printf("saxpy ok (%d elements)\n", kN);

  CHECK_CUDA(cudaFree(device_x));
  CHECK_CUDA(cudaFree(device_y));
  return EXIT_SUCCESS;
}
