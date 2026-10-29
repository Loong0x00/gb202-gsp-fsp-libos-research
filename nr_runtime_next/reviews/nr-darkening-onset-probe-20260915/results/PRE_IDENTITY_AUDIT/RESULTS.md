# NR71 darkening-onset probe — locked result

## Bottom line

The earliest **captured** NR representation that satisfies the frozen associative onset rule is **block22**. Because block14 fails and no checkpoints from blocks15–21 were captured, the honest localization is:

> **The extra linearly decodable darkening information appears in the interval `(block14, block22]`; it is not justified to name an exact block inside 15–22.**

A much larger transition occurs at **block38**, after the global N96 ViT stack. A frozen suffix intervention found a selective, signed causal direction at block38 on all four held-out categories, while the analogous block22 direction did not beat an orthogonal matched-norm control. Therefore:

- **Associative onset:** by block22, after block14.
- **Strong/contextual representation:** block38.
- **Selective causal control demonstrated:** block38, not block22.
- **Near-final readout:** block66–69; the learned head adds almost no regression R² over block69 and is not used to claim onset.

This does **not** establish that the network detects “anime faces,” nor that block38 created the signal. It establishes where output darkening first becomes detectably encoded at the sampled boundaries and where one train-derived direction is causally upstream of output brightness.

![Layer curve](results/figures/layer_curve.png)

## Frozen design and leakage controls

`FIRST_PLAN.md` was frozen before any NR outputs. The primary label was the signed 8×8-cell residual

`delta_ev = log2((Y_output + 1e-4) / (Y_input + 1e-4))`.

The auxiliary fixed class was `delta_ev < -0.1`. Models were Ridge regression and L2 logistic regression only; no MLP result was needed or substituted for the linear conclusion.

The dataset was frozen before model outputs (`DATASET_FREEZE.json`, aggregate SHA-256 `c72194413242aff4a28a8fd57623034f5b5c379c52af142cb5a15a48501d3e60`):

- 90 cases, 69 source-identity groups.
- 33 real, 30 stylized, 20 game, 2 material, 1 synthetic, and 4 same-color/context controls.
- 50 train / 17 validation / 19 locked test / 4 context-test cases.
- After one target-blind input-variance exclusion: 49 train cases (39 groups), 17 validation (14 groups), and 19 test (15 groups).
- No source group crosses splits.
- No exact duplicates and no cross-split 17×16 dHash pair within Hamming distance 8.
- All crops, frames, variants, and transformations sharing an identity or clip remain in one split.

Regularization was selected on validation only. Every locked-test prediction array was written and hashed in `FIRST_PREDICTIONS.json` before scoring. Cross-domain, open-subset, and logistic predictions have separate first-prediction receipts.

The image-only comparator is not a weak RGB mean: it includes local RGB means/standard deviations, linear-light RGB, luminance, luminance gradients, global photometric statistics, and coordinates. NR-feature probes append aligned activation, local 3×3 activation mean, and global activation mean.

## Capture validity

All 90 primary cases have complete prefix, ViT, decoder, learned-head, and output receipts. `CAPTURE_ACCEPTANCE.json` reports:

- `PASS_ALL_90_TRANSPARENT_PROBE_CAPTURES`
- 90/90 cases, 69 groups
- aggregate ID/input/output SHA-256 `20526c10d89bcc5cb8161fb9fad1e75de793ef801c47c9432407ba1d9699fa4b`.

Capture was passive:

- White-reference instrumented output SHA-256 remained exactly `9481ad0f535d4f007c1b8eef28ac72d28a1105747e697546ea01c1460a53a6f2`.
- On frozen natural input `commons-006`, the guarded original-DLL/SM120 observer and transparent capture had **zero differing bytes** at pre0, blocks4/8/14/22/30/38, decoder blocks48/66/69, and the complete 4,194,304-byte output.
- Natural-input output SHA-256 on both sides was `85444c914dc1e2bf9fba2753d8019707905cf5a68465f58b937d9b3e58023542`.

Natural images exposed a real internal binary16 norm overflow. The first failures were retained. The probe-local correction permits only finite-input internal positive overflow followed by the measured SM120 operation `RSQRT(+Inf)=+0`; external NaN/Inf and invalid domains remain rejected. `POSITIVE_INF_NATIVE_COMPARISON.json` and `DECODER_CAPTURE_NATIVE_COMPARISON.json` validate this correction byte-for-byte. The accepted public package itself was not silently rewritten; details are in `NUMERIC_DOMAIN_CORRECTION.md`.

FP8 boundaries were decoded as E4M3FN using their physical A-planar, C-packed, or ViT sequence layouts. Only the visible square was pooled to the common 8×8 target: the right-side public-path padding was not offered to probes as an easy coordinate shortcut.

## Primary Ridge results

Locked test contains 1,216 cells from 19 cases / 15 source groups. Confidence intervals are 2,000-replicate source-identity-group bootstraps.

| boundary | R² | source-macro MAE EV | Spearman | AUPRC from signed regression |
|---|---:|---:|---:|---:|
| image baseline | 0.155 | 0.0936 | 0.496 | 0.372 |
| pre0 | 0.091 | 0.0985 | 0.375 | 0.330 |
| block4 | 0.089 | 0.0966 | 0.429 | 0.320 |
| block8 | 0.126 | 0.0938 | 0.477 | 0.371 |
| block14 | 0.185 | 0.0897 | 0.518 | 0.428 |
| block22 high | 0.273 | 0.0856 | 0.602 | 0.503 |
| block22 low | 0.277 | 0.0869 | 0.605 | 0.485 |
| block30 | 0.303 | 0.0857 | 0.634 | 0.512 |
| block38 | 0.590 | 0.0641 | 0.772 | 0.744 |
| block48 | 0.665 | 0.0586 | 0.839 | 0.807 |
| block66 | 0.742 | 0.0464 | 0.909 | 0.901 |
| block69 | 0.760 | 0.0449 | 0.910 | 0.906 |
| learned head (positive control) | 0.761 | 0.0451 | 0.909 | 0.921 |

### Frozen onset decision

The plan requires positive bootstrap lower bounds for both R² and AUPRC improvement over the image baseline, reproduction at the next later checkpoint, and a permutation-null check.

| boundary | ΔR² 95% CI vs image | ΔAUPRC 95% CI vs image | 200-permutation p for MAE gain | decision |
|---|---:|---:|---:|---|
| block14 | [-0.010, 0.062] | [-0.032, 0.115] | 0.0647 | fail |
| block22 high | [0.064, 0.158] | [0.030, 0.225] | 0.00498 | pass |
| block22 low | [0.053, 0.176] | [0.015, 0.194] | 0.00995 | pass |
| block30 | [0.075, 0.199] | [0.025, 0.230] | 0.00498 | reproduces |
| block38 | [0.282, 0.540] | [0.217, 0.512] | 0.00498 | large transition |

The permutation null moves complete source-group target bundles only among equal-sized train groups, keeps selected alphas fixed, and scores the untouched locked test. Raw bootstrap and null samples are retained in `results/BOOTSTRAP_RAW.npz` and `results/PERMUTATION_NULL_RAW.npz`.

## Auxiliary classification

The converged fixed-layer L2 logistic refit used the validation-selected C values from the preserved first run. The first run's convergence warnings and predictions remain archived rather than overwritten.

| boundary | AUROC | AUPRC | F1 @ 0.5 | Brier | ECE10 |
|---|---:|---:|---:|---:|---:|
| image baseline | 0.733 | 0.409 | 0.236 | 0.147 | 0.034 |
| pre0 | 0.723 | 0.434 | 0.269 | 0.148 | 0.050 |
| block22 low | 0.855 | 0.618 | 0.500 | 0.118 | 0.032 |
| block38 | 0.943 | 0.808 | 0.679 | 0.080 | 0.034 |
| block69 | 0.985 | 0.949 | 0.873 | 0.039 | 0.022 |

This supports the continuous result but is secondary; the threshold was never used to define onset. Source-group bootstrap intervals for AUROC, AUPRC, F1, Brier, and ECE are retained in `results/LOGISTIC_BOOTSTRAP_CI.json` (for example, block38 AUROC 95% CI [0.919, 0.968] and AUPRC [0.716, 0.905]).

## Cross-domain and open-license sensitivity

Cross-domain probes were retrained on one domain's train/validation groups and evaluated on another domain's locked-test groups.

| direction | image R² | block22 R² | block38 R² | block66 R² | block69 R² |
|---|---:|---:|---:|---:|---:|
| real → stylized | 0.326 | -0.983 | 0.380 | 0.758 | 0.728 |
| stylized → real | -1.534 | 0.010 | 0.294 | 0.700 | 0.731 |
| real+stylized → game | -0.020 | 0.107 | 0.550 | 0.709 | 0.694 |

The unstable early transfer, followed by consistent block38/66 transfer, argues for a shared later representation rather than an effect unique to one art domain. Game locked test has only two source groups, so its number is supporting evidence, not a population estimate.

An independent sensitivity fit using only the 27 recorded-open-license Commons cases and 30 MIT Fluent cases reproduces the curve: R² is 0.193 at image-only, 0.307 at block22 low, 0.636 at block38, 0.805 at block66, and 0.806 at block69 (`results/OPEN_SUBSET_RESULTS.json`).

![Cross-domain](results/figures/cross_domain.png)

## Frozen suffix intervention

`FIRST_SUFFIX_INTERVENTION_PLAN.md` (SHA-256 `2ef748f4b068bd5e6336d371635464638dbc135d5cebc5e9c2fffd7886aac4e2`) fixed the direction, amplitude, controls, identities, and acceptance rule before intervention execution.

At each boundary, a train-Ridge-derived effective activation direction was perturbed by ±0.10 channel SD, re-quantized to E4M3FN, and passed through the untouched transparent suffix. A fixed-seed orthogonal direction with identical norm was the control. Every unmodified suffix first reproduced its stored output byte-for-byte.

| boundary | positive held-out groups | median absolute target +/- contrast EV | median absolute orthogonal +/- contrast EV | accepted |
|---|---:|---:|---:|---|
| block22 low | 3/4 | 0.000929 | 0.002067 | no |
| block38 | 4/4 | 0.015066 | 0.000158 | **yes** |

At block38 the signed target contrasts were +0.01882 EV (real), +0.00751 (stylized), +0.01686 (game), and +0.01328 (material). All 32 raw intervention outputs match their hashes.

![Suffix intervention](results/figures/suffix_intervention.png)

The block22 negative result is important: block22 is the first sampled boundary with reproducible extra predictive information, but this particular uniform Ridge direction is not selective enough for a causal-direction claim. Block38 is the first tested boundary with a strong, category-consistent and control-separated causal direction.

## Context and scale controls

Four generated controls contain an identical center 64×64 RGB patch in different surroundings. Its actual output range is 0.09186 EV: context matters even when local color is identical. The block38 probe predicts all six pairwise contrast signs with contrast MAE 0.0357 EV. However, this is one synthetic source group, the face-like context is not the darkest condition, and the range is below the proposed 0.20-EV strong-context gate. It is therefore explicitly reported as noncausal exploratory evidence (`results/CONTEXT_RESULTS.json`).

A post-primary fixed-512 scale extension used three already-scored identities at scales 0.50/0.75/1.00. Mean support darkening became stronger at smaller scale for all three; ranges were 0.1105 EV (real), 0.0394 EV (stylized), and 0.0456 EV (game). Because shrinking also exposes more fixed gray surround, this is a scale-plus-context sensitivity result, not independent onset evidence.

![Scale sensitivity](results/figures/scale_sensitivity.png)

## Provenance and licensing

`PROVENANCE_AUDIT.json` verifies every source path/hash and every transformed input hash, and finds no cross-split group.

- 40 downloaded Commons source records are retained with page URL, attribution, license, and SHA in `source_inventory/COMMONS_MANIFEST.json`; 27 enter the frozen dataset.
- 30 MIT Fluent Emoji sources are retained in `source_inventory/FLUENT_MANIFEST.json`; all enter the dataset.
- 4 context controls were generated locally.
- 29 game/local portrait/material/synthetic cases are conservatively marked **local research evidence**. No redistribution permission is asserted for those source images or derived activation tensors.
- In total, 61 cases are recorded-open-license or generated; 29 are local-research-only.

The local evidence improves domain coverage, but the Commons+Fluent-only sensitivity result prevents the main layer curve from depending solely on those restricted cases.

## Scope and limitations

1. This remains the proved public route only: first/reset frame, 512×512 RGBA32F, fixed controls, no motion/mask. It does not generalize to later temporal counters, arbitrary formats, or live game resource lifecycles.
2. Only sampled boundaries are localized. The result cannot distinguish blocks15–21, nor determine exactly where inside the ViT stack the block38 jump forms.
3. The target and features are pooled to 8×8. Fine facial subregions and SDF facial shading are not separately labeled.
4. Locked test has 15 source groups; game has 2 and material 1. Confidence intervals are grouped, but category-specific claims remain data-limited.
5. Same-color context and scale extensions are small controls, not semantic face interventions.
6. The block38 suffix intervention uses four held-out categories and a spatially uniform train-derived direction. It proves signed causal influence of that encoded direction, not a unique biological/semantic “face-darkening neuron.”
7. The learned head is deliberately treated as a positive control, never as onset evidence.

## Primary artifacts

- Freeze and plan: `FIRST_PLAN.md`, `DATASET_FREEZE.json`, `DATASET_MANIFEST.json`
- Provenance: `PROVENANCE_AUDIT.json`, `source_inventory/*MANIFEST.json`
- Capture acceptance: `CAPTURE_ACCEPTANCE.json`
- Native equality: `POSITIVE_INF_NATIVE_COMPARISON.json`, `DECODER_CAPTURE_NATIVE_COMPARISON.json`
- First predictions: `FIRST_PREDICTIONS.json`, `FIRST_LOGISTIC_PREDICTIONS.json`, `FIRST_CROSS_*.json`
- Primary scores: `results/PROBE_RESULTS.json`, `results/LOGISTIC_RESULTS.json`
- Uncertainty/null: `results/BOOTSTRAP_CI.json`, `results/LOGISTIC_BOOTSTRAP_CI.json`, `results/PERMUTATION_NULL.json`
- Cross-domain/open-only: `results/CROSS_DOMAIN_RESULTS.json`, `results/OPEN_SUBSET_RESULTS.json`
- Causal follow-up: `results/SUFFIX_INTERVENTION_RESULTS.json`, `interventions/`
- Controls: `results/CONTEXT_RESULTS.json`, `results/SCALE_RESULTS.json`
- First failures and correction: `activations/*-FIRST_INCOMPLETE/`, `NUMERIC_DOMAIN_CORRECTION.md`, `logs/*FIRST*`
