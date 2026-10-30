// Compile-only stress test: Thrust drags in the deepest template machinery
// the EDG frontend will face (CUB, tuple metaprogramming, iterator adaptors).

#include <thrust/device_ptr.h>
#include <thrust/execution_policy.h>
#include <thrust/sort.h>

namespace cuda_tests {

void SortOnDevice(float* data, int n) {
  thrust::device_ptr<float> begin(data);
  thrust::sort(thrust::device, begin, begin + n);
}

}  // namespace cuda_tests
