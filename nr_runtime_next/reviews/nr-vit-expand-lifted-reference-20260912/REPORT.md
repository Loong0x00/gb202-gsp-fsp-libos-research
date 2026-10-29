# Independent lifted CTA-0 proof

`lifted_reference.py` lifts the original source's packed A, packed B,
MMA-fragment/tail, and store programs into a CPU tensor slice. It does not call
a DLL, GPU, Wine, or host executable. The numerical loop is explicitly
`for k0 in range(0, 1024, 32): C = RN_f16(C + dot32(A, B))`; a once-rounded
dense GEMM is not used.

## Independent checks

* `test_lifted_reference.py` proves the 131,072 A addresses and first
  4,194,304 slab addresses are bijections, checks the source's 64 static MMA
  instructions/tail constants/prefetch guard, and derives the complete 16,384
  CTA-0 store-byte map.
* `verify_literal_cta0.py` performs a fresh **read-only**
  `nr-vit-expand-bounds-main-20260912/execute_reference.py.run(cx=0)` and
  compares every sparse byte against the lifted operator. It passed with
  `MMAs=4096`, 16,384 bytes, and SHA-256
  `c36e9fea219639f49aeb90e214eb9736a5bee6c4207492d323267f5420be4ada`.
* The prior false OOB premise is retained rather than rewritten: in the
  literal four-warp domain the audited masks are `r35/r465 =
  0,0,4096,4096` and the paired `r33` selector is `0,0,4,4`; the prefetch
  guard skips `k=960`'s successor (no `k=1024` load).

## Boundary

This proves the complete CTA-0 tensor/operator result, including the literal
cubic and FP8 pack. It does **not** prove the CTA-x logical-coordinate mapping
or slab range for all 32 CTAs, hence does not label the full grid a dense
128x4096 forward. Native MMA equivalence and whole-model equivalence remain
unproved.
