# Lifted CPU tensor reference — `cc_vit_1d_ffn_expand_fp8`

`lifted_reference.py` is a standalone, CPU-only tensor implementation for the
**complete proven CTA-0 slice**. It consumes the literal packed 131,072-byte
FP8 activation and 4,194,320-byte raw slab, exposes source-derived A/B/output
maps, does 32 K=32 FP8 dot products with one RN-f16 result per dot, and runs
the literal cubic (`ab28`, `3728`, `3b28`) plus E4M3 packing.

It is not a DLL hook, GPU runner, or a once-rounded dense GEMM. The output map
is explicitly CTA-local and sparse: CTA-0 writes 16,384 FP8 bytes at the PTX
store addresses (maximum 460,799), rather than silently inventing a dense
layout.

## Proof boundary

The original CPU literal execution independently established CTA `[32,4,1]`,
grid `[32,1,1]`, four returns, 4,096 executed MMA calls per CTA, and no
preflight OOB for CTA-0. The source map here expands the actual address/fragment
program and validates map ranges. It does **not** claim a complete 32-CTA
logical 128×4096 neural-network output: CTA-x logical coordinate ownership and
the last-CTA slab range still require an independent proof. Native MMA
semantics/full-model equality also remain unproved.
