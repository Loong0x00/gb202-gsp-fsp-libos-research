# Remaining Swin8h core: source-only handoff

## Result

Recovered and bounded the post-prefix source sequence: first MMA/activation/gate bank, post-FFN projection, QKV-sized projection, scalar RSQRT paths, seeded attention MMA, affine/clamp/table/reduction/reciprocal order, weighted-value bank, final projection, and four guarded output stores.

`PROGRESS.md` contains exact slab byte-load envelopes and equations:

- first bank `[0,262144)`;
- learned activation/gate reads `[262144,295424)`;
- post-FFN projection `[294912,360448)`;
- QKV-sized bank `[492544,689152)`;
- attention seed loads `[689152,711680)`;
- final projection `[754720,820256)`.

It also records loop trip counts, MMA register witnesses, raw decimal scalar immediates, final output byte-store equations, standard-kernel structural correspondences, and explicit rejected/unresolved interpretations. No tensor identity, axis map, serialization-derived tensor claim, or numerical/native equivalence is asserted.

## Files Changed

- `PROGRESS.md` — detailed source-only recovery notes.
- `REPORT.md` — this bounded handoff.

## Verification

Read-only inspection of the permitted five copied files only; no commands, tests, execution, or input modification. Source line citations refer to the numbered source views. MMA_INDEX counts are documented only as scoped corroboration.
