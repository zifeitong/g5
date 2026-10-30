#ifndef BAZEL_CUDA_TESTS_FLASH_ATTN_CUH_
#define BAZEL_CUDA_TESTS_FLASH_ATTN_CUH_

#include <cuda_runtime.h>

namespace cuda_tests {

// Q, K, V and O are [batch, heads, seq, head_dim], contiguous in that order.
struct FlashAttnParams {
  const float* q;
  const float* k;
  const float* v;
  float* o;
  int batch;
  int heads;
  int seq;
  int head_dim;  // 32 or 64; see the shared-memory note in flash_attn.cu.
  float scale;   // Conventionally 1 / sqrt(head_dim).
  bool causal;
};

// Launches a FlashAttention-2 forward pass on the current stream.
cudaError_t FlashAttentionForward(const FlashAttnParams& params);

}  // namespace cuda_tests

#endif  // BAZEL_CUDA_TESTS_FLASH_ATTN_CUH_
