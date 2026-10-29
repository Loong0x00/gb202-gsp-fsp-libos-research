# Expanded procedural adapter v2 plan — frozen before new training captures

V1 passed3/4 new identities; the fairy/full-person failure indicates insufficient pose/clothing diversity. Keep architecture, objective, optimizer and gates unchanged. Only expand procedurally paired identities.

## Training identities

- Original development: `003,014,020,024`.
- V1 heldout, now explicitly released into v2 training after its result was frozen: `001,009,021,026`.
- Eight new training identities selected without output inspection: `000,002,004,005,006,007,008,010`.

New training identities use heights `32,48,64,96,128,192,320`; background, centering, controls and mask rules remain fixed.

## V2 model

Same zero-initialized `32->32 SiLU ->3` residual adapter, same deterministic region sampling, same danger-band target, same AdamW/lr/weight-decay/batch/30 epochs. Retrain from zero; do not warm-start v1.

## Untouched final identities

Freeze before any v2 training:

- `fluent-011` person lifting weights;
- `fluent-012` person running;
- `fluent-027` face with peeking eye;
- `fluent-028` face with raised eyebrow.

These receive eight scales only after v2 checkpoint is frozen. Acceptance gates are unchanged from `ADAPTER_PLAN.md`. No v3 tuning is permitted from final outputs without declaring another entirely new heldout cohort.

Ideogram is deferred: exact alpha-paired Fluent expansion is available and avoids identity/reference ambiguity. Generated data becomes necessary only after procedural identity/pose diversity is exhausted or for photoreal-domain transfer.
