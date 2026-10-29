# Main: HDR transfer vs learned contrast / volume cues

2026-09-11. CPU-only, no new GPU inference or game launch. Latest physical game exit was independently verified: no game PIDs, original owned/signed hashes restored, Engine startup RR key=1, user unit inactive/Result=success. Evidence: physical100724/MAIN_COLD_RECHECK.json. User reports transfer1 made the current scene dark/black but more dimensional; this is user feedback, not a measured black-pixel rate.

## Proven mechanism in exact frozen PRE3 source

`runtime/pipeline.cpp:284–285` passes intensity/local tone into NGX. Transfer strength is instead copied by `runtime/codec.cpp` into the compositor push constants. `shaders/codec_decode.comp::upgrade_tonemap` uses `mix(original, scaled, TransferStrength)`. With the tested color1/paper1 controls, and holding the input/history/model outputs fixed, the composite is `(1-t) * original + t * HDR-reconstructed NR output`. It is not an NN contrast/geometry control. PRE mode then sends this result through original SR and later game processing; this formula alone does not describe final Present or future-frame feedback.

At t=.6, 40% of original remains. At t=1, none remains. Thus a region the model/HDR reconstruction darkened is no longer protected by original-image mixing. Our validator caps t at 1: this run is NOT a >1 extrapolation/clipping experiment.

## CPU checks with retained fenced GPU tensors

`analyze.py` freezes existing raw NR tensors and varies ONLY external composition t=0/.6/1. Source encode/decode shaders are byte-identical between the retained Style2 POST package and current fixed PRE3 package. This does NOT equate their complete pipelines or scenes.

- Two prior WuWa still frames, synthetic guides, POST5. All strengths2, Style2; not current live PRE3 dark scene.
- Reconstructed t=.6 vs saved GPU D mean RGB errors 8.42e-5 / 8.86e-5 before reproducing GPU FP16 rounding; prior dedicated audit established near-exact rounded agreement.
- Identity NR=B has luminance mean absolute error 5.28e-8 relative to source in this fixture. The compositor does not intrinsically blacken this unchanged fixture; no universal claim about arbitrary HDR inputs/color management.
- Source mean linear Y=.1673. At t=1, P3 composites have mean Y=.2177/.2306; P5 .2538/.2724. However deep-shadow fraction increases and selected character regions darken. This is compatible with selective contrast/relighting, not uniform exposure reduction.
- PLAYER_ROI.json is an explicitly posthoc illustrative box [356,218,400,306], not semantic segmentation or unbiased character-wide inference. The P3 box median pixel EV change is -.55/-.48 while the whole image brightens. Contains background; means/medians differ strongly.

`*-transfer.png` uses identical fixed preview tone mapping for every panel. It is not a monitor capture, not a new GPU run, and not latest PRE3 output.

## Independent global-tone ablation

See `../nr-contrast-shortcut-20260911/REPORT.md`. Main read the comparison image and reran verify.py plus SHA256SUMS (all passed). Old WuWa B→P5 raw model brightness increases 52–63%; deep shadows increase. A separate old Style0 portrait slightly darkens overall but lifts deepest shadows. Block-held-out global RGB tone curves leave edit-residual energy ratios .53–.60 for WuWa and .31 for the portrait. These are NOT fractions of geometry or perceived volume. Matching global brightness/contrast still leaves spatially structured appearance differences, but has NOT eliminated local contrast or proven semantic/material/geometric reasoning.

## Interpretation and remaining decisive tests

Evidence supports selective tonal/lighting changes and increased shadow contrast as a plausible contributor to apparent volume. It rejects neither complex local-contrast processing nor texture hallucination; it does not establish the training shortcut '3D=dark'. Exact model training data/loss/provenance remain unknown, and newer public NVIDIA research claims cannot be assigned to this retained binary.

Latest PRE3/transfer1 scene lacks raw inputs/NR outputs, so its root cause remains unresolved. A better causal next experiment is same source/guides/history, transfer1, varying LocalTone independently of LocalStructure, then global AND local-contrast controls plus visual comparisons. Depth interventions may test guide dependence but are not by themselves proof of physical geometry. No such new GPU sweep has been run in this task.
