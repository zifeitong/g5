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
  * The per-thread record array base is hoisted out of the loop; leaving the
    vector-of-vector double indirection in the record path costs ~12%, as the
    two dependent pointer loads land on the update's address-generation chain.
  * At ~35 instructions per record the loop saturates the cores (~4 IPC per
    core with both SMT threads); streaming bandwidth (55 GB/s measured) and
    page faults are not the bottleneck, so manual two-cursor interleaving and
    `MADV_POPULATE_READ`/`MADV_COLLAPSE` were tried and rejected. `MAP_HUGETLB`
    does not apply: it is only valid for anonymous or hugetlbfs mappings, so
    `mmap` of the measurements file rejects it with `EINVAL` (`MAP_HUGE_1GB`
    without it was silently a no-op), and the kernel already uses large folios
    for the page-cache mapping.
* Tested on x86-64 and ARM64 (Apple Silicon).
* Finishes in ~0.46s on AMD Ryzen 5 7640U, down from 98s with a native
  implementation (210x speedup).
