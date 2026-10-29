# NR71 darkening-onset probe — identity-corrected result

## Bottom line

After a post-result source-identity audit and a stricter capacity analysis, **no single exact creation layer is proven**. The evidence has three tiers:

1. **Registered full-channel Ridge screen:** block22 is the first sampled checkpoint satisfying the nominal frozen bootstrap gate; block14 does not qualify and block30 repeats the direction.
2. **Explicitly capped low-capacity screen:** with train-only PCA32 and at most 98 probe columns, block22 no longer beats the image baseline. **Block38 is the first sampled checkpoint with positive R²/AUPRC bootstrap lower bounds.**
3. **Causal suffix check:** the corrected train-derived direction at block38 moves output brightness with the declared sign in 4/4 held-out categories and is about 100× the median orthogonal-control contrast. The block22 direction fails in 3/4 categories and is smaller than its control.

Therefore the most defensible result is:

> **Darkening is strongly and causally encoded by block38. Block22 contains a fragile full-channel associative signal, but it is not robust to the explicit capacity cap or the suffix-direction control. The exact onset before block38 remains unresolved.**

If one additionally requires max-checkpoint family-wise significance for R², AUPRC, and MAE simultaneously under a full train/validation pipeline permutation, the first qualifying sampled checkpoint is block48. This is a deliberately stricter post-hoc sensitivity criterion, not a rewrite of the frozen rule.

![Capacity comparison](results/figures/capacity_sensitivity.png)

## Audit correction and analysis populations

The 90-case dataset was frozen before NR execution, but two audit findings must be explicit.

### Pre-output split revision

The archived first hash split was written at 22:18:53 and replaced at 22:20:14 by a deterministic category-stratified group split because the first split was category-unbalanced. The first NR failure occurred at 22:29:12. Thus the 65 split changes predated outputs; both versions are retained. See `IDENTITY_AND_SPLIT_ERRATUM.md`.

### Semantic identity leak and correction

`commons-011` (train) and `commons-012` (test) are two views from the same artwork/subject series, *The Gobblin Child* HK7155-10002-1/-2. Hash and dHash checks did not detect this semantic identity. Both cases were excluded from every corrected confirmatory fit and score; neither was reassigned. The frozen manifest and all first/pre-correction results remain preserved in `results/PRE_IDENTITY_AUDIT/`.

The corrected primary population is:

- 48 train cases / 38 source groups;
- 17 validation cases / 14 groups;
- 18 locked-test cases / 14 groups / 1,152 spatial cells;
- 4 context-test cases / 1 generated group.

One nearly black game training frame was also excluded by a target-blind RGB-variance rule frozen before target inspection. Corrected predictions were newly hashed before corrected scoring. Because the semantic correction happened after first scores existed, the corrected analysis is transparent and target-blind in rule, but not claimed to be a pristine never-seen-test replication.

## Frozen target and estimators

`FIRST_PLAN.md` fixed the primary 8×8-cell label:

`delta_ev = log2((Y_output + 1e-4) / (Y_input + 1e-4))`.

The auxiliary class is `delta_ev < -0.1`. Ridge and L2 logistic are the only supervised estimators. The learned head is a positive control only.

The image comparator includes cell RGB means/standard deviations, linear-light RGB, luminance, luminance gradients, per-image photometric summaries, and coordinates. Activation probes use aligned activation, 3×3 local activation mean, global activation mean, and coordinates. They do not receive output pixels or labels as features.

Separate baseline ablations confirm that position/padding is not sufficient:

| baseline | test R² | source-macro MAE EV | regression AUPRC |
|---|---:|---:|---:|
| coordinate only | 0.001 | 0.1075 | 0.201 |
| global photometry only | -0.001 | 0.1077 | 0.220 |
| local RGB/linear-light/luminance/gradient | 0.163 | 0.0934 | 0.369 |
| full registered image baseline | 0.169 | 0.0933 | 0.377 |

## Capture and numeric validity

`CAPTURE_ACCEPTANCE.json` reports 90/90 complete passive captures and aggregate ID/input/output SHA-256 `20526c10d89bcc5cb8161fb9fad1e75de793ef801c47c9432407ba1d9699fa4b`. The hardened verifier now hashes each actual activation input, every captured boundary, and every output rather than trusting receipt text alone. Feature extraction repeats those lineage checks, and training binds each NPZ to `FEATURE_EXTRACTION.json`.

Passive-capture checks:

- Instrumented white output remains exactly `9481ad0f535d4f007c1b8eef28ac72d28a1105747e697546ea01c1460a53a6f2`.
- A **single** frozen natural witness, `commons-006`, was checked against the guarded original DLL/embedded SM120 route at pre0, blocks4/8/14/22/30/38, blocks48/66/69, and the complete 4,194,304-byte output: zero differing bytes at every recorded boundary.
- The natural-witness output SHA-256 on both sides is `85444c914dc1e2bf9fba2753d8019707905cf5a68465f58b937d9b3e58023542`.
- This is not a claim of native execution for all 90 cases. Exact scope, DLL/checkpoint/package hashes, and the missing historical command-log caveat are recorded in `CAPTURE_IMPLEMENTATION_PROVENANCE.json`.

Natural inputs exposed finite-input internal binary16 squared-norm overflow. The probe-local correction allows only the source-defined path `+Inf -> measured RSQRT(+Inf)=+0`; external NaN/Inf still fails closed. The first failures are retained, and the corrected natural witness is byte-identical to native. The accepted transparent package was not silently modified; see `NUMERIC_DOMAIN_CORRECTION.md`.

FP8 E4M3FN boundaries are decoded using A-planar, C-packed, or ViT sequence layouts. Only the visible square is pooled; right-side physical padding is excluded from probe features.

## Full-channel Ridge screen

Confidence intervals use 2,000 source-group bootstrap replicates.

| boundary | R² | source-macro MAE EV | Spearman | regression AUPRC |
|---|---:|---:|---:|---:|
| image baseline | 0.169 | 0.0933 | 0.518 | 0.377 |
| pre0 | 0.100 | 0.0986 | 0.389 | 0.351 |
| block4 | 0.096 | 0.0969 | 0.449 | 0.336 |
| block8 | 0.135 | 0.0934 | 0.494 | 0.400 |
| block14 | 0.197 | 0.0893 | 0.535 | 0.436 |
| block22 high | 0.280 | 0.0860 | 0.610 | 0.512 |
| block22 low | 0.287 | 0.0871 | 0.615 | 0.498 |
| block30 | 0.309 | 0.0862 | 0.639 | 0.521 |
| block38 | 0.592 | 0.0640 | 0.773 | 0.748 |
| block48 | 0.668 | 0.0580 | 0.844 | 0.812 |
| block66 | 0.752 | 0.0453 | 0.915 | 0.910 |
| block69 | 0.770 | 0.0437 | 0.915 | 0.912 |
| learned head, positive control | 0.769 | 0.0440 | 0.913 | 0.922 |

For the frozen nominal gate:

| checkpoint | ΔR² bootstrap 95% CI | Δ regression-AUPRC CI | Δ logistic-AUPRC CI | nominal decision |
|---|---:|---:|---:|---|
| block14 | [-0.016, 0.064] | [-0.039, 0.119] | [-0.088, 0.182] | does not qualify |
| block22 high | [0.054, 0.152] | [0.021, 0.225] | [0.090, 0.330] | qualifies |
| block22 low | [0.046, 0.171] | [0.012, 0.197] | [0.082, 0.329] | qualifies |
| block30 | [0.061, 0.188] | [0.020, 0.232] | [0.136, 0.381] | repeats direction |
| block38 | [0.270, 0.534] | [0.211, 0.500] | [0.243, 0.504] | large transition |

“Block14 does not qualify” is not evidence that block14 contains no information. It only failed this test with 14 held-out groups. Consequently, no interval of absence/appearance is asserted.

## Explicit low-capacity sensitivity

The post-audit plan `LOW_CAPACITY_SENSITIVITY_PLAN.md` caps every activation at 32 train-only unsupervised PCs and at most 98 final columns. Test predictions were frozen before scoring.

| boundary | PCA32 R² | source-macro MAE EV | ΔR² CI vs image | result |
|---|---:|---:|---:|---|
| image baseline | 0.169 | 0.0933 | — | comparator |
| block14 | 0.107 | 0.0989 | [-0.149, -0.010] | worse |
| block22 high | 0.155 | 0.0949 | [-0.089, 0.035] | no gain |
| block22 low | 0.145 | 0.0951 | [-0.102, 0.029] | no gain |
| block30 | 0.224 | 0.0895 | [-0.032, 0.113] | uncertain |
| block38 | 0.562 | 0.0677 | [0.236, 0.490] | first capped nominal pass |
| block48 | 0.642 | 0.0607 | [0.333, 0.573] | pass |
| block66 | 0.734 | 0.0527 | [0.399, 0.659] | pass |
| block69 | 0.731 | 0.0564 | positive | pass |

At block38, capped ΔMAE, ΔR², and ΔAUPRC bootstrap lower bounds are all positive. This capacity sensitivity is why block22 is not promoted to the robust headline.

## Permutation nulls and multiplicity

The corrected pipeline null permutes complete source-group target bundles separately within train and validation, redoes all nine-alpha validation selection choices, and scores the untouched test. Two hundred permutations give minimum attainable p=`1/201=0.00498`.

The original/full-channel screen gives block22 nominal R² p=0.0199/0.00995 (high/low), but AUPRC p=0.114/0.0697. Max-checkpoint family-wise p-values are not significant for block22. At block38, full-channel unadjusted p is 0.00498 for R²/AUPRC/MAE; max-checkpoint p is 0.00995 for R² and MAE but 0.831 for AUPRC.

The lower-capacity null is more stable. At block38, unadjusted p is 0.00498/0.00995/0.00498 for R²/AUPRC/MAE, while max-checkpoint p is 0.00498/0.0995/0.00498. Block48 is the first capped checkpoint with all three max-checkpoint p-values below 0.05: 0.00498/0.0348/0.00498.

These post-hoc family-wise results are reported as a robustness ceiling, not retrofitted into the original acceptance rule. They also show why an exact early-onset claim would be too strong.

## All-layer L2 logistic screen

All 13 layer models converged before the 5,000-iteration limit. C was selected on validation only, and corrected test probabilities were frozen before scoring. Test dark fraction is 0.208.

| boundary | AUROC | AUPRC | F1 @ 0.5 | Brier | ECE10 |
|---|---:|---:|---:|---:|---:|
| image baseline | 0.753 | 0.415 | 0.239 | 0.144 | 0.033 |
| pre0 | 0.740 | 0.475 | 0.291 | 0.143 | 0.046 |
| block4 | 0.730 | 0.391 | 0.226 | 0.149 | 0.041 |
| block8 | 0.768 | 0.397 | 0.422 | 0.151 | 0.053 |
| block14 | 0.804 | 0.466 | 0.406 | 0.136 | 0.032 |
| block22 high | 0.870 | 0.639 | 0.492 | 0.113 | 0.034 |
| block22 low | 0.867 | 0.630 | 0.518 | 0.115 | 0.032 |
| block30 | 0.892 | 0.688 | 0.606 | 0.102 | 0.023 |
| block38 | 0.946 | 0.813 | 0.687 | 0.077 | 0.029 |
| block48 | 0.966 | 0.872 | 0.754 | 0.063 | 0.031 |
| block66 | 0.985 | 0.948 | 0.861 | 0.040 | 0.021 |
| block69 | 0.985 | 0.950 | 0.876 | 0.039 | 0.019 |
| learned head | 0.972 | 0.932 | 0.852 | 0.045 | 0.013 |

All-layer source-group intervals for AUROC, AUPRC, F1, Brier, ECE, and paired baseline deltas are in `results/LOGISTIC_BOOTSTRAP_CI.json`.

## Identity-corrected suffix intervention

`IDENTITY_CORRECTED_SUFFIX_PLAN.md` (SHA-256 `15165a292e0a647d45b5f496acefbcb8afb6fe46a691a217c23d00474f2ab61e`) preserves the first intervention's amplitude, direction construction, controls, closure test, and acceptance rule, while replacing contaminated `commons-012` with the next lexicographic eligible real identity, `commons-016`.

Each direction is derived from corrected train-only Ridge coefficients, applied at ±0.10 channel SD, re-encoded to E4M3FN, and passed through the untouched suffix. A fixed-seed orthogonal matched-RMS direction is the control. Every unmodified suffix first reproduces its stored output byte-for-byte. All 32 intervention outputs match receipt hashes and contain exactly 512×512×4 finite float32 values.

| boundary | positive categories | median absolute target contrast EV | median absolute orthogonal contrast EV | declared rule |
|---|---:|---:|---:|---|
| block22 low | 1/4 | 0.000570 | 0.001452 | fail |
| block38 | 4/4 | 0.011041 | 0.000110 | pass |

Block38 signed target contrasts are +0.00879 EV (real), +0.00722 (stylized), +0.01696 (game), and +0.01329 (material). This demonstrates causal influence of this specific encoded direction on these four cases. It does not prove that block38 created the information, that no other block22 direction can matter, or that a unique face-selective neuron exists.

![Suffix intervention](results/figures/suffix_intervention.png)

## Cross-domain, context, and scale

Corrected cross-domain locked-test R²:

| direction | image | block22 low | block38 | block66 | block69 |
|---|---:|---:|---:|---:|---:|
| real → stylized | 0.317 | -0.829 | 0.402 | 0.736 | 0.712 |
| stylized → real | -1.608 | 0.024 | 0.310 | 0.712 | 0.751 |
| real+stylized → game | -0.026 | 0.112 | 0.532 | 0.701 | 0.692 |

Late transfer is consistent across domains; early transfer is unstable. Game test has only two source groups, so this is supporting evidence only.

The corrected open-source-only sensitivity uses 25 Commons plus 30 MIT Fluent cases: R² is 0.208 image-only, 0.295 block22-low, 0.647 block38, 0.818 block66, and 0.823 block69.

The face-vs-flat same-center-color control has an actual face-minus-flat contrast of **+0.06197 EV**: the face-like surround is less dark, not more dark. Across all four contexts the identical center patch spans 0.09186 EV, and block38 predicts all six pairwise contrast signs with 0.0346-EV contrast MAE. This is one generated group and does not establish semantic face causality.

The post-primary fixed-512 scale audit uses three already-scored identities and is exploratory. Smaller source scale with more fixed gray surround increases mean support darkening; ranges are 0.1105 EV real, 0.0394 stylized, and 0.0456 game. Scale and surround are confounded.

![Cross-domain](results/figures/cross_domain.png)

## Provenance and distribution scope

`PROVENANCE_AUDIT.json` verifies all retained source and transformed-input hashes and records the semantic identity correction.

- 40 Wikimedia Commons source records are retained; 27 entered the original dataset and 25 remain in corrected analysis.
- 30 Microsoft Fluent Emoji files are pinned to commit `1ffb34c752ecf5d402f04cfb4b392c77f57c54bc` under MIT.
- 4 controls were generated locally.
- 29 cases are conservatively marked `local research evidence`; no redistribution rights are asserted for their images or derived tensors.

`THIRD_PARTY_NOTICES.md` contains per-item Commons attribution and license links plus the Fluent MIT notice. `OPEN_DISTRIBUTION_SCOPE.json` lists 61 recorded-open/generated IDs and explicitly excludes the 29 local-research-only IDs. No distributable bundle containing restricted local inputs or derivatives has been produced. `prepare_dataset.py` was a discovery-time assembler that can scan optional paths; it is not an authoritative rebuild recipe. Reproduction is bound to the frozen manifest and verified source/input hashes, and must fail rather than substitute a newly discovered file.

## Limitations

1. The route is fixed first/reset frame, 512×512 RGBA32F, fixed controls, no motion or mask. Later temporal counters and live game resource lifecycles are outside proof.
2. Corrected test has only 14 groups; category-specific game/material estimates are particularly small.
3. Spatial pooling is 8×8. Fine face, skin, and SDF-shading regions are not separately segmented.
4. The original nominal screen exposes many channels despite strong L2 regularization. The PCA32 result is more consistent with the requested low-capacity interpretation and moves the robust boundary later.
5. Two hundred permutations limit p-value resolution. Family-wise AUPRC is conservative and unstable with few groups and correlated checkpoints.
6. The semantic identity issue was found after first scoring. Excluding both views is target-blind, but only a new independent identity cohort can restore a pristine confirmatory test.
7. The block38 causal result is one direction, one amplitude, four categories, and a uniform spatial intervention.
8. `learned_head` remains a positive control and never supports onset.

## Main artifacts

- Plan/freeze/erratum: `FIRST_PLAN.md`, `DATASET_FREEZE.json`, `DATASET_MANIFEST.json`, `IDENTITY_AND_SPLIT_ERRATUM.md`, `IDENTITY_EXCLUSIONS.json`
- Provenance/licenses: `PROVENANCE_AUDIT.json`, `CAPTURE_IMPLEMENTATION_PROVENANCE.json`, `THIRD_PARTY_NOTICES.md`, `OPEN_DISTRIBUTION_SCOPE.json`
- Capture/native: `CAPTURE_ACCEPTANCE.json`, `POSITIVE_INF_NATIVE_COMPARISON.json`, `DECODER_CAPTURE_NATIVE_COMPARISON.json`, `NUMERIC_DOMAIN_CORRECTION.md`
- Corrected first predictions: `FIRST_PREDICTIONS.json`, `FIRST_LOGISTIC_PREDICTIONS.json`, `FIRST_LOW_CAPACITY_PREDICTIONS.json`, `FIRST_CROSS_*.json`
- Full-channel results: `results/PROBE_RESULTS.json`, `results/BOOTSTRAP_CI.json`, `results/PERMUTATION_NULL.json`
- Low-capacity results: `results/LOW_CAPACITY_RESULTS.json`, `results/LOW_CAPACITY_BOOTSTRAP_CI.json`, `results/LOW_CAPACITY_PERMUTATION_NULL.json`
- Classification: `results/LOGISTIC_RESULTS.json`, `results/LOGISTIC_BOOTSTRAP_CI.json`
- Intervention: `IDENTITY_CORRECTED_SUFFIX_PLAN.md`, `results/SUFFIX_INTERVENTION_RESULTS.json`, `interventions/`
- Controls/generalization: `results/BASELINE_ABLATIONS.json`, `results/CROSS_DOMAIN_RESULTS.json`, `results/OPEN_SUBSET_RESULTS.json`, `results/FACE_SAME_COLOR_CONTROL.json`, `results/CONTEXT_RESULTS.json`, `results/SCALE_RESULTS.json`
- Preserved pre-correction evidence: `results/PRE_IDENTITY_AUDIT/`, `activations/*-FIRST_INCOMPLETE/`, `logs/*FIRST*`
