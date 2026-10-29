# Original module02 4h inpview/block9 numeric-gap review (CPU/static)

## Result

This is **post-native analysis of the already-known fixture**, not a new native run, reference rewrite, or prediction fit. The accepted one-CTA record remains: `execution_pass=true`, `numeric_match=false`, **226/8192** E4M3 bytes differ by tile **125/56/26/19**, maximum decoded finite absolute error **0.015625**. `ANALYSIS.json` retains every differing byte with both E4M3 bytes, decoded values, and error. Native output `e86df801…`, frozen pre-run prediction `0422ff26…`, input, slab, and both output guards are pinned and rechecked. The prior Main record supplies full CUDA cleanup and Guardian=0.

A real, bounded source-to-SASS discrepancy is now identified at the **class level**:

| static operation class | PTX | SASS |
|---|---:|---:|
| half multiply | 320 | 288 `HMUL2` |
| packed half add | 160 | 128 `HADD2` |
| packed half FMA | 128 | 160 `HFMA2` |

Exactly 32 source `x*x; y*y; add` reduction nodes are dataflow-derived (all PC/producer pairs are retained). Replacing one source square/product/add pair by an `HFMA2` closes the full ledger exactly: `320-32=288`, `160-32=128`, `128+32=160`. This removes a half-product rounding before the half-add. A literal-source, no-output-comparison ablation finds that on this fixed old fixture either possible fused operand order changes 1843/4096 packed-half lane instances. It establishes sensitivity, **not** the native operand allocation, native result, or a correction.

The 32 `rsqrt.approx.ftz.f32` and four `rcp.approx.ftz.f32` source instructions count-match `MUFU.RSQ` and `MUFU.RCP`; the retained disassembly does not provide an approximation table or bit-exact FTZ behavior. The 272 static FP8 MMA / 2816 accepted complete-CTA dynamic MMA count match 272 `QMMA.16832.F16.E4M3.E4M3`, but this does not prove accumulator precision or rounding. Likewise, the retained SASS has no debug/register-allocation map permitting individual PTX-PC-to-SASS-PC operand identities.

**Verdict: unresolved.** The 32 contractions are a plausible contributor but are not proved to explain any of the 226 bytes. No finalpost/QK fusion was copied, no post-native policy clone was used as a proposed fix, and no tolerance, output fitting, NaN replacement, hole zeroing, input/seed selection, or prediction rewrite was performed. A future Main held-out fixture is needed before any generalization claim.

## Bounds and provenance

`analyze.py` parses the exact PTX through the previously accepted strict CPU interpreter and replays only the frozen 8x8 fixture after native observation. It rechecks 5404 parsed source instructions, 5384 exercised PCs on this geometry, 128 returned threads, all 8192 input bytes, 197136 unique slab bytes ending below 197184, and all 8192 output bytes exactly once. The accepted `nr-original-swin4h-probe-prep-20260911` evidence remains the source for the full 2456-SASS-instruction/encoding and 128-lane address-control review and all bounded source paths; this old fixture replay does not overclaim unexercised branch coverage.

All reads are pinned by SHA-256 in `ANALYSIS.json`. The analyzer invokes no subprocesses, CUDA/Driver API, GPU, Wine, or host executable and writes only this directory.

## Verification

```bash
env -u CUDA_VISIBLE_DEVICES PYTHONDONTWRITEBYTECODE=1 \
  bash reviews/nr-swin4h-numeric-gap-20260912/verify_cpu.sh
```

The verifier regenerates the local JSON/log, checks all 226 retained differences and the guard/read-only record, reruns literal source bounds, checks the exact contraction ledger, and runs in-memory negative mutants (drop a proved pair, admit a non-square add, alter MMA/approx counts). It does not execute historical or future GPU work.
