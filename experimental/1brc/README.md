One Billion Row Challenge (1BRC) solution in C++

* Tricks:
  * Compile-time perfect hash with [mph](https://github.com/qlibs/mph) library.
  * SIMD (AVX-512 on Zen4) with [highway](https://github.com/google/highway) library.
  * Records are located by scanning a 64-byte window for `;` and `\n` at once,
    then walking the two bit masks in general purpose registers with `blsr`, so
    the loop-carried dependency chain never touches memory.
  * Fully branchless record body: SWAR value parsing, a name hash with no
    length special case (guard pages on both sides of the mapping make the
    backwards read at the first record and the window/value overreads at the
    last record valid), and a merge-masked 128-bit update of
    `{sum, count, min, max}`.
  * At ~35 instructions per record the loop saturates the cores (~4 IPC per
    core with both SMT threads); streaming bandwidth (55 GB/s measured) and
    page faults are not the bottleneck, so manual two-cursor interleaving and
    `MADV_POPULATE_READ`/`MADV_COLLAPSE` were tried and rejected.
* Tested on x86-64 and ARM64 (Apple Silicon).
* Finishes in ~0.46s on AMD Ryzen 5 7640U, down from 98s with a native
  implementation (210x speedup).
