# H16 original-PTX audit: strict confirmation blocked

This is CPU/static evidence only. No game, GPU, network, or deployment was used.

1. Existing encoder22-low H16 predictions were hash-frozen first in
   `ORIGINAL_PTX_H16_PREDICTION_FREEZE.json`. The missing block30 pooled-H8
   prediction was derived before replay and explicitly labelled prediction-only.
2. Each replayed source entry is an untouched literal substring of pinned
   `module-04-dll-00bd0990.ptx` (`SHA-256
   6eaaebeca9c051660f7a9df9ac18c6c13e3a7e267b5392c98c73a0f6f2e21fe6`).
3. The fail-fast audit reached the first disagreement at block 29 layer 2;
   it did **not** substitute the transparent implementation or continue to
   claim downstream H16/H8/N64 equality.

## Preserved first failure

- Entry: `cc_split_swin_16h_qkv_512_fp8`
- Block/origin/CTA: `29`, `(-4, 0)`, `(0, 0, 2)` — left shift boundary
- Physical output offset: `4869`
- Frozen prediction byte: `0x23`
- Literal original-PTX byte: `0x22`

The immutable first record is `ORIGINAL_PTX_H16_FIRST_FAILURE.json`; the main
runner now fails closed rather than replacing it.

## Full failing-entry check

`ORIGINAL_PTX_H16_BLOCK29_LAYER2_DIAGNOSTIC.json` subsequently replayed all
`3 × 2 × 4 = 24` source CTAs without changing the first-failure file:

- all `131072` H16 output bytes are covered exactly once (zero writer overlap);
- source output SHA-256: `9cbe847d6a5a67db50ed1f146862be6eb5af8c699b6d7fe68ea0687215808db6`;
- frozen prediction SHA-256: `70374225776869c7604ec8699c5e8252ab32318374b2f4b582d81ce133fdca6b`;
- nine bytes differ, all in that left-boundary CTA's channel-slice-2 patch.

The exact source-produced bytes and all nine byte differences are retained in
`ORIGINAL_PTX_H16_BLOCK29_LAYER2_ORIGINAL.bin` and
`ORIGINAL_PTX_H16_BLOCK29_LAYER2_MISMATCHES.json`.

Therefore the frozen H16 chain — and consequently its downstream block29 L3,
block30 pool/head, and N64 repack claim — is **not strictly confirmed**.
