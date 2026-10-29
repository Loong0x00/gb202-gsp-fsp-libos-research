# Layer-2 FP8 QKV attention — bounded CPU execution

## Result

This new directory continues the pinned `cc_split_swin_16h_qkv_512_fp8`
layer-2 work beyond the former `cvt.s64.s32` instruction-153 boundary.  It
parses and executes all **3,360** original PTX instructions, including the
original learned-loop and both polling backedges, through the source `ret`.
The prior `nr-split16h-attention-reference-20260911` static-boundary review is
unchanged.

The executor accepts only the original 56-byte aggregate and the exact
917,568-byte `block23-layer2.bin` (`441802...12e3a7`).  It records only the
physical input and that one slab as readable regions; it has no adjacent-layer
record, dense-F16 bridge, zero C seed, softmax library, GELU substitution, or
synchronous-copy replacement.  The four conditional source slices (`cta.z`
0--3) each retire, produce disjoint output portions, collectively cover the
32,768 bytes of an 8x8 output, and source-read every byte `[0,917568)` of the
real slab.

## Restored operation boundary

The own typed-form checks admit only the forms actually present in this source:

* `cvt.s64.s32 %rd*, %r*`, `shl.b64 %rd*, %rd*, 2`, and the four full-mask
  `elect.sync _|P_OUT, %r*` issuer sites;
* four `cp.async.bulk.shared::cta.global.mbarrier::complete_tx::bytes`
  sites and their four typed `expect_tx` sites;
* the original `selp.b64` and `not.b32` forms needed after the old boundary.

The shared implementation is intentionally QKV-specific: allocations are
**8192 + 16** and mbarrier addresses are only **8192** and **8200**.  It does
not reuse the projection executor's 12288/24 layout or 12288-series barrier
addresses.  An elected lane 0 issues each 512-byte transfer.  Bytes become
visible only on the matching 128th original `mbarrier.arrive`; each completed
source phase records exact `expect_tx == complete_tx` bytes and issuer count.
The test exercises pre-completion false readiness and post-128-arrival true
readiness, rather than treating a bulk load as synchronous.

For the 8x8 conditional exercise, each barrier address completes four phases,
each with 4,096 expected/transferred bytes and eight elected issuers.  Each
CTA records 64 512-byte async events, eight mbarrier completions, and its one
original 128-thread `bar.sync`.

## Numeric policy boundary

The execution API requires caller-supplied MMA, RSQRT, and RCP policies.  The
confined test supplies recording structural policies: they receive the actual
source-derived MMA A/B/C fragments (and verifies C is nonzero) and all dynamic
approximation calls, but it does **not** claim their CPU results are the
native FP8 MMA or approximate RCP/RSQRT result.  This is an explicit policy
boundary, not a guessed softmax/GELU or an implicit fallback.  Consequently
this report establishes original-instruction/control/storage execution through
`ret` under declared policies; it does not claim GPU equivalence or a native
numeric attention result.

## Route and geometry boundary

The earlier static catalog report proves the catalog rewrite applies `_fp8` to
all 152 names before manager consumption, so its static path reaches the FP8
name.  It does **not** observe base-vs-tilesync selection, a live submission,
or a live QKV grid.  This executor therefore requires the explicit
`conditional-fp8-qkv-nontilesync-route-unresolved` acknowledgement.

The source proves CTA `(32,4,1)` construction and uses `4*CTA.z + tid.y` for
a scalar path.  This execution is deliberately fail-closed to the one complete
canonical 8x8 CTA at `(cta.x, cta.y)=(0,0)`, with the four z slices exercised
as explicit bounded conditional geometry.  It is **not** an observed host
`grid.z` contract; in particular the old pre-resume `<4` condition is not
presented as host proof.  Other spatial/OOB geometries are rejected pending
separate async-count proof rather than being approximated.

## Provenance and verification

`original.ptx`, `block23-layer2.bin`, `module-header.txt`, static host anchors,
and their pin file were copied byte-for-byte from
`nr-split16h-attention-reference-20260911` solely as immutable inputs.  The
execution model, typed-form checks, tests, and this report are new here.  The
generic instruction handlers were started from the completed projection review
only after this directory added QKV-source typed-form tests; the scheduler and
shared/barrier state are owned here.

```sh
PYTHONDONTWRITEBYTECODE=1 python -B \
  reviews/nr-split16h-attention-execution-20260912/test_attention_execution.py
```

The four local CPU tests rehash inputs, parse the full source, exercise all
conditional slices through `ret`, verify nonzero C and full slab coverage, and
check issuer/count/arrival/readiness failures.  No GPU, Wine, DLL/host
execution, installed-file mutation, sibling write, or network action is used.
