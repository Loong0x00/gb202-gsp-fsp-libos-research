# Fixed-range context gate V5 — frozen before new final generation

V4 proved that spatial context gating removes close/background drift, but its `[0,1]` multiplier produced danger-band false negatives. V4 final is now archived development evidence. No checkpoint is retrained.

Freeze the deterministic multiplier:

`correction_V5 = (0.5 + 1.5 * sigmoid(gate_V4)) * correction_V3`

Range is `[0.5,2.0]`. The 0.5 floor preserves part of the base repair for gate false negatives; upper gain restores amplitude for full-body faces. V4 archived close changes were near zero after gating, while V3’s largest generated close change was0.0454EV, so a0.5 floor remains below the unchanged0.03EV close gate in the observed development set. This observation selects the fixed formula; it is not evidence for the new final.

## New strict final cohort

-10 new frozen Ideogram prompts/seeds across photo/game/anime; objective pre-model source QC may reject incomplete faces, but at least8 must survive or the cohort is invalid.
- Untouched Fluent face identities `fluent-023` and `fluent-025`.

No weights, normalization, pooling, thresholds or multiplier may change after generation. Existing strict gates remain. If V5 fails, stop adapting block70 and move to a block48/38 representation-level repair.
