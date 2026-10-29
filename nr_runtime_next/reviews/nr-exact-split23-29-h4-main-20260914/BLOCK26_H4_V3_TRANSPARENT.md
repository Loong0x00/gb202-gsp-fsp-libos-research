# Block-26 shifted H4 transparent V3

## Scope

`split_standard_candidate_h4_v3_transparent.py` implements only the special
layer-2 geometry `(H, W, origin) = (4, 4, (0, -4))` with NumPy plus the
existing finite `num` primitives.  It does not delegate that forward path to a
replay, does not inspect an input digest, and does not read source-program
files.  Other geometries retain the existing standard-split implementation.

The exact sequence is:

1. unpack the 16 logical E4M3 tokens and perform the source-proven K32 QKV
   projection;
2. use the existing RN-half normalization, Q scale, E4M3 publication, and
   score map/reciprocal primitives;
3. place logical queries at physical positions
   `[32,33,34,35,40,41,42,43,48,49,50,51,56,57,58,59]` in the retained 8x8
   score plane;
4. use `4*((p//8)%4) + p%4` for the 64 physical K-fragment positions and
   `p%16` for V-fragment positions;
5. exchange physical score destinations `(query=3, keys=39/51)` and
   `(query=15, keys=11/19)` before the normal 64-key map/reduction; then run
   the two K32 PV reductions and pack C.

The two exchanges are layout operations, not learned constants and not
input-dependent patches.  They are applied to every head in one vectorized
operation.

## Why head 8 was the visible failure

The source head selector is `head = 4*cta.z + tid.y`; consequently the
captured `cta.z=2`, warp (`tid.y`) `0` slice is head 8.  Its C channels are
logical columns `256..287`.

The old generic H4 formula treated the shifted case as zero-padded H4 and
missed the physical K/V aliases and score-fragment exchanges above.  On the
current source, comparing that formula to the original output gives 209
mismatching bytes, all in head 8.  The other heads happened to publish the
same final E4M3 codes for this input after their map/reduction/quantization
boundaries; that is an observed numerical result, not a claim that their
fragment layout differs.  The corrected implementation therefore has **no
`head == 8` branch**: it models the shared source layout for all 16 heads.

Head 8 is special because its values make the missed score destinations survive
through probability and PV publication as different E4M3 codes.  This is why a
head-8-only output symptom exposed a geometry-wide mapping error.

## Evidence

Run:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -B verify_block26_h4_v3_transparent.py
```

The verifier evaluates V3 before loading its diagnostic VM oracle, statically
rejects replay/digest imports from the V3 model, and checks:

* current source `a3a2965168ee74216ec72d396d78d34a37820cd83c1d077811fbded25ec6bd2e`
  against both the preserved diagnostic output and four oracle slices;
* independent finite `HELDOUT_SOURCE.bin`
  (`051f58f631d837a3ce61d44170f32c2d1c50c19f018ae5e25188ae782b139a7e`)
  against four fresh oracle slices.

Both comparisons are 8192/8192 byte equal.  The generated V3 result report is
`BLOCK26_H4_V3_TRANSPARENT_RESULT.json`.  The prior V2 replay module and its
existing evidence are intentionally untouched.
