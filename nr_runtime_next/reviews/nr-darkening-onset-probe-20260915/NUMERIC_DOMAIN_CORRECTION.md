# Internal positive-infinity normalization correction

The first four natural portrait attempts all failed closed in block4 because the accepted bounded transparent package rejected a binary16 overflow while summing Q/K squared norms. External inputs were finite. Continuing would have selected only easy finite examples, so all four low-priority shards were stopped and their original `FAILURE.json` files retained.

A probe-specific candidate distinguishes an invalid external NaN/Inf from a source-defined internal positive-overflow path:

1. half square/add operations may produce `+Inf` from finite Q/K;
2. the original max-with-epsilon retains `+Inf`;
3. the already measured exhaustive SM120 half-domain table gives `RSQRT(+Inf) = +0` (`0x7c00 -> 0x00000000`);
4. finite Q/K multiplied by this factor produces signed/positive zero; NaN, negative denominator and non-finite external color remain rejected.

This was predicted after the transparent failure, then checked against a fresh guarded original-DLL public CUDA run on frozen `commons-006` input SHA-256 `4a7f01c853d9e9f2fb9e7b3c2c1e70a99e8e9d126653deb331953f41c560f3bc`.

`POSITIVE_INF_NATIVE_COMPARISON.json` reports zero differing bytes at pre0, block4, block8, block14, block22 high/low, block30, block38 and the complete 4,194,304-byte output. Final SHA-256 on both sides is `85444c914dc1e2bf9fba2753d8019707905cf5a68465f58b937d9b3e58023542`.

`DECODER_CAPTURE_NATIVE_COMPARISON.json` additionally reports zero differing bytes for passively captured block48, block66 and block69. The correction is currently scoped to `instrumented_runner.py`; it has not silently rewritten the previously accepted package or its manifest.
