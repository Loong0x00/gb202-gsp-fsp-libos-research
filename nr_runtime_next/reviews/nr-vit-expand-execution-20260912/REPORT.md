# `cc_vit_1d_ffn_expand_fp8` — canonical CPU execution preflight

This review uses the corrected, static host contract: one 72-byte record
(`p0` input, `p16` output, `p24` MMA-B, factors at `p64/p68`), CTA `(32,4,1)`,
`grid=(32*ceil(N/128),1,1)`, and the explicit canonical domain
`N0=128,N1=1`.  Therefore the first CTA is `(0,0,0)` and the source-derived
full grid is `(32,1,1)`.  The constructor constraint supplied for this launch
is `Cin=1024,Cout=4096`.

## What was implemented and checked

`execution_preflight.py` is CPU/static-only and retains the literal source
schedule facts: 24,576 B shared storage; three 8-byte barriers; `bar.sync`;
24 static `cp.async.bulk...complete_tx` / `expect_tx` forms; `elect.sync`;
arrival/poll forms; and the `r1138=0..960 step 64` loop.  Its `Barrier` model
requires all 128 arrivals and an exact `expect_tx == complete_tx` byte total
before publication.  The initial canonical branch evaluates to 48 elected
512-B transfers, 16 transfers / 8192 B per barrier, and fills exactly the
24,576 B staging allocation—no zero-fill or early/synchronous publication.

The local `mma_rn` implements the actual PTX ISA m16n8k32 row/col fragment
mapping and an E4M3FN dot plus C rounded at the f16 result boundary.  Its test
uses nonzero A, B and C and proves D=2 rather than returning C.  E4M3FN NaN
encodings reject.  This is a primitive semantic test, not a substituted MMA
or an activation-tail stub.

This review independently extracts the source tail immediates and checks the
finite `-4 -> f16 -0 -> E4M3 80` boundary; the coefficients are `ab28`,
`3728`, `3b28`.  The preceding review's exhaustive finite-half work remains
preserved and is not overwritten here.

## Source-derived byte results (not a guessed dense reshape)

For the first CTA the exact intervals calculated directly from load/store
address expressions have these extents:

| role | max end-exclusive offset | actual result |
|---|---:|---|
| `p0` cp-async reads | 117,760 | sparse reads, 24,576 bytes total |
| `p24` MMA-B loads | 4,329,472 | exceeds the supplied raw slab |
| shared MMA loads | 26,624 | exceeds declared 24,576 B shared allocation |
| `p16` stores | 460,800 | sparse stores only |

Across the derived `(32,1,1)` grid, p24's maximum end is **4,456,448**.  The
output address extent is 524,288 but only 458,752 bytes are stored; holes are
explicitly retained rather than filled.

## Hard fail-closed result

The only supplied real block32/layer0 physical checkpoint range is the pinned
F16 byte range `[35618354,39812674)`, 4,194,320 B, SHA-256
`f94a…f916`.  It is 135,152 B short even for first-CTA p24 loads and 262,128 B
short for the full derived grid.  It is also serialized F16, not an asserted
prepared E4M3 p24 allocation.  The preflight checks this real range and stops
before any undefined/OOB byte is read; it neither pads, aliases, nor invents a
dense F16->FP8 transformation.  The shared MMA load expression independently
reaches 26,624, beyond the literal 24,576-byte declaration under the corrected
`tid.y=0..3` CTA.

Consequently this review **does not claim all 128 threads reach original
`ret` with real weights**.  That would require a complete, tagged prepared-FP8
p24 allocation of at least 4,456,448 bytes plus resolution of the literal
shared-address discrepancy.  These are source-derived incompatible physical
preconditions, not an unsupported-instruction hook, so refusing the replay is
intentional.  Runtime pointer binding/native execution and the block31 repack
path remain separate and were not used.
