// Mixed host/device binary: this file is compiled by hermetic-llvm's clang,
// flash_attn.cu by nvcc. The host side recomputes attention in double
// precision, so a run on a GPU machine self-checks instead of only printing.

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <vector>

#include "bazel/cuda/tests/flash_attn.cuh"

#include <cuda_runtime.h>

namespace {

constexpr int kBatch = 2;
constexpr int kHeads = 3;
constexpr int kSeq = 160;  // Deliberately not a multiple of the 64-row tile.
constexpr int kHeadDim = 64;
constexpr float kTolerance = 2e-3f;

#define CHECK_CUDA(expr)                                                       \
  do {                                                                         \
    cudaError_t err = (expr);                                                  \
    if (err != cudaSuccess) {                                                   \
      std::fprintf(stderr, "%s failed: %s\n", #expr, cudaGetErrorString(err)); \
      return EXIT_FAILURE;                                                     \
    }                                                                          \
  } while (0)

// Deterministic and bounded, so the softmax stays well conditioned.
float Sample(long long index, unsigned int salt) {
  unsigned int x = static_cast<unsigned int>(index) * 2654435761u + salt;
  x ^= x >> 15;
  x *= 2246822519u;
  x ^= x >> 13;
  return static_cast<float>(x % 2003u) / 2003.0f - 0.5f;
}

void ReferenceAttention(const std::vector<float>& q, const std::vector<float>& k,
                        const std::vector<float>& v, float scale, bool causal,
                        std::vector<float>& out) {
  std::vector<double> scores(kSeq);
  for (int head = 0; head < kBatch * kHeads; ++head) {
    const long long base = static_cast<long long>(head) * kSeq * kHeadDim;
    for (int i = 0; i < kSeq; ++i) {
      const int limit = causal ? i + 1 : kSeq;
      double max_score = -HUGE_VAL;
      for (int j = 0; j < limit; ++j) {
        double dot = 0.0;
        for (int d = 0; d < kHeadDim; ++d) {
          dot += static_cast<double>(q[base + static_cast<long long>(i) * kHeadDim + d]) *
                 static_cast<double>(k[base + static_cast<long long>(j) * kHeadDim + d]);
        }
        scores[j] = dot * scale;
        if (scores[j] > max_score) {
          max_score = scores[j];
        }
      }

      double total = 0.0;
      for (int j = 0; j < limit; ++j) {
        scores[j] = std::exp(scores[j] - max_score);
        total += scores[j];
      }

      for (int d = 0; d < kHeadDim; ++d) {
        double sum = 0.0;
        for (int j = 0; j < limit; ++j) {
          sum += scores[j] *
                 static_cast<double>(v[base + static_cast<long long>(j) * kHeadDim + d]);
        }
        out[base + static_cast<long long>(i) * kHeadDim + d] =
            static_cast<float>(sum / total);
      }
    }
  }
}

int RunCase(bool causal, const std::vector<float>& host_q,
            const std::vector<float>& host_k, const std::vector<float>& host_v,
            const float* device_q, const float* device_k, const float* device_v,
            float* device_o, std::size_t bytes) {
  const float scale = 1.0f / std::sqrt(static_cast<float>(kHeadDim));

  cuda_tests::FlashAttnParams params;
  params.q = device_q;
  params.k = device_k;
  params.v = device_v;
  params.o = device_o;
  params.batch = kBatch;
  params.heads = kHeads;
  params.seq = kSeq;
  params.head_dim = kHeadDim;
  params.scale = scale;
  params.causal = causal;

  CHECK_CUDA(cuda_tests::FlashAttentionForward(params));
  CHECK_CUDA(cudaDeviceSynchronize());

  std::vector<float> actual(host_q.size());
  CHECK_CUDA(cudaMemcpy(actual.data(), device_o, bytes, cudaMemcpyDeviceToHost));

  std::vector<float> expected(host_q.size());
  ReferenceAttention(host_q, host_k, host_v, scale, causal, expected);

  float worst = 0.0f;
  std::size_t worst_at = 0;
  for (std::size_t i = 0; i < expected.size(); ++i) {
    const float diff = std::fabs(expected[i] - actual[i]);
    if (diff > worst) {
      worst = diff;
      worst_at = i;
    }
  }

  const char* name = causal ? "causal" : "full";
  if (worst > kTolerance) {
    std::fprintf(stderr, "%s attention mismatch at %zu: %f vs %f (max diff %g)\n",
                 name, worst_at, expected[worst_at], actual[worst_at], worst);
    return EXIT_FAILURE;
  }
  std::printf("flash attention 2 %s ok (max diff %g)\n", name, worst);
  return EXIT_SUCCESS;
}

}  // namespace

int main() {
  int device_count = 0;
  cudaError_t err = cudaGetDeviceCount(&device_count);
  if (err != cudaSuccess || device_count == 0) {
    // Only reachable where a driver is installed but exposes no GPU; see
    // the note in saxpy_main.cc.
    std::fprintf(stderr, "CUDA driver present but no device; skipping\n");
    return EXIT_SUCCESS;
  }

  const std::size_t elements =
      static_cast<std::size_t>(kBatch) * kHeads * kSeq * kHeadDim;
  const std::size_t bytes = elements * sizeof(float);

  std::vector<float> host_q(elements);
  std::vector<float> host_k(elements);
  std::vector<float> host_v(elements);
  for (std::size_t i = 0; i < elements; ++i) {
    host_q[i] = Sample(static_cast<long long>(i), 1u);
    host_k[i] = Sample(static_cast<long long>(i), 2u);
    host_v[i] = Sample(static_cast<long long>(i), 3u);
  }

  float* device_q = nullptr;
  float* device_k = nullptr;
  float* device_v = nullptr;
  float* device_o = nullptr;
  CHECK_CUDA(cudaMalloc(&device_q, bytes));
  CHECK_CUDA(cudaMalloc(&device_k, bytes));
  CHECK_CUDA(cudaMalloc(&device_v, bytes));
  CHECK_CUDA(cudaMalloc(&device_o, bytes));
  CHECK_CUDA(cudaMemcpy(device_q, host_q.data(), bytes, cudaMemcpyHostToDevice));
  CHECK_CUDA(cudaMemcpy(device_k, host_k.data(), bytes, cudaMemcpyHostToDevice));
  CHECK_CUDA(cudaMemcpy(device_v, host_v.data(), bytes, cudaMemcpyHostToDevice));

  for (bool causal : {false, true}) {
    if (RunCase(causal, host_q, host_k, host_v, device_q, device_k, device_v,
                device_o, bytes) != EXIT_SUCCESS) {
      return EXIT_FAILURE;
    }
  }

  CHECK_CUDA(cudaFree(device_q));
  CHECK_CUDA(cudaFree(device_k));
  CHECK_CUDA(cudaFree(device_v));
  CHECK_CUDA(cudaFree(device_o));
  return EXIT_SUCCESS;
}
