Source fact: original lines 10940–10952 apply `fma.rn.f16x2`, then `max.f16x2`, then `min.f16x2`, then raw-word `shl.b32 ..., 5` and `add.s32 ..., 2146992128` for the first shown pair.

Complete: source-only attention-tail report written for Main review. It records the half/packed map, reduction/reorder/floor/RCP, pre-FP8 reciprocal multiplication, PV A/B/C carry schedule, final-projection seed/coefficient sources, preserved `bar.sync 0` at 15136, eight-trip K loop, and final stores. Unproven shared-content identity and logical axes are explicitly retained as uncertainties.
