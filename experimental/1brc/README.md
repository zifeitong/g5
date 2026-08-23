One Billion Row Challenge (1BRC) solution in C++

* Tricks:
  * Compile-time perfect hash with [mph](https://github.com/qlibs/mph) library.
  * SIMD (AVX-512 on Zen4) with [highway](https://github.com/google/highway) library.
* Tested on x86-64 and ARM64 (Apple Silicon).
* Finishes in ~0.65s on AMD Ryzen 5 7640U, down from 98s with a native implementation (150x speedup).
