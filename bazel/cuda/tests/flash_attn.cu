// A FlashAttention-2 forward pass in one translation unit: key/value block
// tiling with an online softmax, where the running sum is folded in once in
// the epilogue instead of after every tile. That deferred normalization is
// what distinguishes FlashAttention-2 from the original formulation.
//
// Deliberately not performance-tuned -- no tensor cores, no warp
// specialization, one thread per query row. The purpose is to put real
// shared-memory, template and register pressure through nvcc, which saxpy
// does not, while staying small enough to check against a CPU reference.

#include "bazel/cuda/tests/flash_attn.cuh"

#include <cuda_runtime.h>

#include <cfloat>

namespace cuda_tests {
namespace {

constexpr int kBlockM = 64;  // Query rows per CTA, and threads per CTA.
constexpr int kBlockN = 64;  // Key/value rows per tile.

template <int kHeadDim>
__device__ float QueryKeyDot(const float (&query)[kHeadDim],
                             const float (&keys)[kBlockN][kHeadDim], int row) {
  float sum = 0.0f;
#pragma unroll
  for (int d = 0; d < kHeadDim; ++d) {
    sum += query[d] * keys[row][d];
  }
  return sum;
}

template <int kHeadDim>
__global__ void FlashAttentionForwardKernel(FlashAttnParams p) {
  __shared__ float k_tile[kBlockN][kHeadDim];
  __shared__ float v_tile[kBlockN][kHeadDim];

  const int query = blockIdx.x * kBlockM + static_cast<int>(threadIdx.x);
  const bool active = query < p.seq;

  const long long head_base =
      (static_cast<long long>(blockIdx.z) * p.heads + blockIdx.y) *
      static_cast<long long>(p.seq) * kHeadDim;
  const float* q_head = p.q + head_base;
  const float* k_head = p.k + head_base;
  const float* v_head = p.v + head_base;
  float* o_head = p.o + head_base;

  float q_row[kHeadDim];
  float acc[kHeadDim];
#pragma unroll
  for (int d = 0; d < kHeadDim; ++d) {
    q_row[d] =
        active ? q_head[static_cast<long long>(query) * kHeadDim + d] : 0.0f;
    acc[d] = 0.0f;
  }

  float running_max = -FLT_MAX;
  float running_sum = 0.0f;

  for (int tile = 0; tile < p.seq; tile += kBlockN) {
    for (int i = static_cast<int>(threadIdx.x); i < kBlockN * kHeadDim;
         i += kBlockM) {
      const int row = i / kHeadDim;
      const int col = i - row * kHeadDim;
      const int key = tile + row;
      const long long offset = static_cast<long long>(key) * kHeadDim + col;
      k_tile[row][col] = key < p.seq ? k_head[offset] : 0.0f;
      v_tile[row][col] = key < p.seq ? v_head[offset] : 0.0f;
    }
    __syncthreads();

    if (active) {
      const int rows = min(kBlockN, p.seq - tile);

      // Two passes over the tile. Holding the scores in registers would cost
      // another kBlockN per thread on top of q_row and acc, which spills.
      float tile_max = -FLT_MAX;
      for (int row = 0; row < rows; ++row) {
        if (p.causal && tile + row > query) {
          break;
        }
        tile_max = fmaxf(tile_max,
                         QueryKeyDot<kHeadDim>(q_row, k_tile, row) * p.scale);
      }

      if (tile_max > -FLT_MAX) {
        const float new_max = fmaxf(running_max, tile_max);
        const float rescale =
            running_max == -FLT_MAX ? 0.0f : __expf(running_max - new_max);
        running_sum *= rescale;
#pragma unroll
        for (int d = 0; d < kHeadDim; ++d) {
          acc[d] *= rescale;
        }

        for (int row = 0; row < rows; ++row) {
          if (p.causal && tile + row > query) {
            break;
          }
          const float weight = __expf(
              QueryKeyDot<kHeadDim>(q_row, k_tile, row) * p.scale - new_max);
          running_sum += weight;
#pragma unroll
          for (int d = 0; d < kHeadDim; ++d) {
            acc[d] += weight * v_tile[row][d];
          }
        }
        running_max = new_max;
      }
    }
    __syncthreads();
  }

  if (active) {
    const float inv_sum = running_sum > 0.0f ? 1.0f / running_sum : 0.0f;
#pragma unroll
    for (int d = 0; d < kHeadDim; ++d) {
      o_head[static_cast<long long>(query) * kHeadDim + d] = acc[d] * inv_sum;
    }
  }
}

}  // namespace

cudaError_t FlashAttentionForward(const FlashAttnParams& params) {
  if (params.batch <= 0 || params.heads <= 0 || params.seq <= 0) {
    return cudaErrorInvalidValue;
  }

  const dim3 grid((params.seq + kBlockM - 1) / kBlockM, params.heads,
                  params.batch);
  switch (params.head_dim) {
    case 32:
      FlashAttentionForwardKernel<32><<<grid, kBlockM>>>(params);
      break;
    case 64:
      FlashAttentionForwardKernel<64><<<grid, kBlockM>>>(params);
      break;
    default:
      // head_dim 128 would want 64 KiB for the two tiles, past the 48 KiB
      // default shared-memory carveout; it needs an opt-in carveout first.
      return cudaErrorInvalidValue;
  }
  return cudaGetLastError();
}

}  // namespace cuda_tests
