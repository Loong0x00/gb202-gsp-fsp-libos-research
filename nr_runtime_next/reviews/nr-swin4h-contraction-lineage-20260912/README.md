# 4h contraction operand-lineage certificate (CPU/static)

## Result

This independent review advances the previous **class-count-only** finding. It
extracts all **32** actual SASS `HMUL2`/`HFMA2` contraction def-use chains:
for each chain, the equal `HFMA2` multiplicands come directly from a `QMMA`,
while its addend is the other `QMMA` result after `HMUL2 x,x`. Thus every
admitted native fold has a direction: **fused raw square + rounded other
square**, never an unordered opcode-count match.

The PTX side independently derives the same 32 source `x*x + y*y` nodes. Both
source operands are traced through their producing MMA to real slab coefficient
loads. The source first/second operands are distinct in all 32 nodes. Six PTX
coefficient-load sites and their six SASS counterparts are compared over all
retained warp/lane/byte events (8192 byte events each); four shared MMA fragment
loads are also compared with the established SASS physical `+1024` bias.
Static FP8/MMA anchors are checked: 272 source MMA/272 SASS QMMA, 320
satfinite E4M3 packs, and 64 E4M3-to-half unpack classes.

This proves the native **SASS-side operand direction** and rules out a
class-count-only explanation. It does **not** prove a per-node PTX-to-SASS
permutation, QMMA rounding/accumulation semantics, MUFU behavior, or numerical
replay. Accordingly, **no correction or policy is proposed**. The retained
post-native residual remains **226/8192 bytes** (tile 125/56/26/19; maximum
finite decoded error 0.015625); frozen prediction
`0422ff26…dacd312` and native `e86df801…a5a9f3` are only pinned, never edited.

`lineage_review.py` is read-only outside this directory, invokes no subprocess,
CUDA, GPU, Wine, or host executable, and rejects unknown SSA values/fragments or
missing/non-callable actual normalizer policy keys (`mma`, `rsqrt`,
`reciprocal`). It does not invoke numerical policy arithmetic, so it cannot
silently accept a non-finite result.

## Verification

```sh
env -u CUDA_VISIBLE_DEVICES PYTHONDONTWRITEBYTECODE=1 \
  bash reviews/nr-swin4h-contraction-lineage-20260912/verify_cpu.sh
```

The verifier regenerates `CERTIFICATE.json` and rejects in-memory negative
mutants (dropped fold, swapped role, non-QMMA admission, collapsed coefficient
anchor, or dropped source pair). No fixture, slab, frozen PTX, reference, or
native record is modified.
