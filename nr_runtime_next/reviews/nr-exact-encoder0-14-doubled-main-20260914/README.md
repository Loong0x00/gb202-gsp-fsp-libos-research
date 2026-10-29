# Exact encoder0–14 doubled CPU recovery

CPU-only composition of the accepted transparent encoder families at:

`pre H256x256 → block1 H128 → block4 low H64 → block8 low H32 → block14 low H16`.

`chain.py` only widens conservative geometry/source-extent guards needed for this grid:

- pre0: H128 → H256;
- 1H families (blocks 1–4): max H64 → H128;
- 2H families (blocks 5–8): max H32 → H64;
- 4H families (blocks 9–14): existing H32 domain.

No weights, PTX literal, layout, packing, rounding point, or family arithmetic is replaced. No generic/ordinary BLAS fallback is introduced.

## Evidence order

1. `python3 freeze.py` preloads all files, audits the forward for no I/O, then freezes full outputs in `FIRST_*`.
2. `python3 verify_original.py` uses the original source-family CPU literals CTA-by-CTA, assembles each complete output, and compares every byte to the frozen prediction. Failures are retained under `FAILURES/`.
3. `python3 check_connection.py` feeds the actual original block14 low H16 planar-A bytes to the completed `nr-encoder15-22-h16-main-20260914` CPU implementation.

`BLOCK14_LOW_H16_PLANAR_A.bin` is the frozen handoff; after literal comparison, `ORIGINAL_BLOCK14_LOW_H16_PLANAR_A.bin` is the actual original-literal handoff. Both are `16 planar groups × H16 × W16 × 16 FP8` (65,536 bytes).

Scope excludes GPU, game execution, network activity, deployment, temporal/history behavior, and blocks 15–70 recovery.
