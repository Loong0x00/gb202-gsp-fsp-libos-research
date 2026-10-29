# NR71 person-scale RGB-head fine-tune pilot

## Outcome

A controlled synthetic dataset and minimal existing-weight fine-tune were successfully constructed and executed. The 96 trainable FP16 RGB output-head weights consistently reduced the held-out scale-darkening trough, but **no fold met preservation gates**. No checkpoint was promoted or deployed.

The result is diagnostic:

> The frozen block70 linear RGB head has enough leverage to brighten the danger band, but not enough conditional capacity to distinguish that band from close faces and background. The scale defect is already encoded upstream; tuning only the final 96 image weights cannot cleanly repair it.

## Data

The pilot reuses the frozen 33-case fixed-background/person-only matrix:

- four MIT Fluent source identities;
- eight foreground scales per identity;
- exact alpha and input-derived face masks;
- fixed controls and background;
- one background-only control.

For every case, the exact transparent decoder was rerun passively and the block70 attention prequantization tensor presented to the output head was captured. All 33 reruns reproduced the previously stored output byte-for-byte. Frozen feature storage is about595MiB.

No image generator was required. Procedural alpha compositing is superior for this first objective because it gives exact same-identity multi-scale pairs, deterministic masks and known photometry. Local Ideogram4 remains optional for diversity; no local ComfyUI install or HF token/license acceptance was present. Official NF4 weights are gated/non-commercial and approximately16.1GB total.

## Trainable scope

Only the live block70 RGB columns were updated:

- 32 input features × 3 RGB channels = **96 weights**;
- blocks0–69 frozen;
- block70 FFN/QKV/attention frozen;
- temporal/history channel3 frozen;
- controls frozen;
- graph and package unchanged.

The self-distillation target rescales each source's h320 learned residual into smaller person rectangles while retaining original background. The first solver used exact closed-form ridge regression and FP16 weight quantization.

## Leave-one-identity-out result

| held-out identity | worst-point improvement | large-face mean change | max outside-person RGB MAE | accepted |
|---|---:|---:|---:|---|
| fluent-003 | +0.1768 EV | 0.1442 EV | 0.01035 | no |
| fluent-014 | +0.1146 EV | 0.0554 EV | 0.00821 | no |
| fluent-020 | +0.0996 EV | 0.0177 EV | 0.00812 | no |
| fluent-024 | +0.0940 EV | 0.0113 EV | 0.00935 | no |

Every evaluation path reproduced the original untuned FP16/HMMA head bit-for-bit before applying the tuned weights. The intended trough improves substantially, but background drift exceeds1/255 in every fold; two person folds also alter large faces far beyond the0.03-EV gate.

## Danger-band-only development follow-up

A second, explicitly post-first-result development sweep restricted correction targets to the known40–90px face band and increased background preservation weights. It found no 96-weight candidate satisfying all gates.

Closest candidate:

- minimum danger-band improvement: +0.0386 EV, below the +0.05 gate;
- large-face change: 0.0523 EV, above the0.03 gate;
- outside-person RGB MAE: 0.00325, within1/255.

This confirms a Pareto conflict in the linear head: preserving background/close faces suppresses useful correction; correcting the trough spills into other content.

## Frozen nonlinear adapter follow-up

A zero-initialized 1,155-parameter residual adapter (`32 -> 32 SiLU -> 3`) was then trained on the exact frozen block70 features. It receives no mask, identity, coordinates, scale or control parameters at inference. GPU training used the full safety gate and consumed a maximum of3,793MiB.

V1 was frozen before four new identities. It passed3/4:

| V1 heldout | danger improvement | close change | outside RGB MAE | pass |
|---|---:|---:|---:|---|
| fluent-001 | +0.0835 EV | 0.00010 EV | 0.00137 | yes |
| fluent-009 fairy | +0.0199 EV | 0.04053 EV | 0.00198 | no |
| fluent-021 | +0.0961 EV | 0.00096 EV | 0.00121 | yes |
| fluent-026 | +0.1444 EV | 0.00612 EV | 0.00214 | yes |

The V1 failure was preserved. Architecture/hyperparameters were kept unchanged, eight new procedural training identities were added, and V2 was retrained from zero on16 identities. V2 was frozen before a second, completely new four-identity final set.

V2 passed both standalone-face identities but failed both full-person identities:

| V2 final identity | danger improvement | close change | outside RGB MAE | pass |
|---|---:|---:|---:|---|
| fluent-011 lifting weights | +0.0297 EV | 0.00321 EV | 0.00191 | no |
| fluent-012 running | +0.0239 EV | 0.00782 EV | 0.00162 | no |
| fluent-027 face | +0.1055 EV | 0.00288 EV | 0.00177 | yes |
| fluent-028 face | +0.1261 EV | 0.00224 EV | 0.00096 | yes |

Background-only V2 RGB MAE was0.000677. V2 is conservative and clean, but its correction does not generalize strongly enough to small faces embedded in full-body poses. It was not promoted and no post-final tuning occurred.

![Adapter v2 final curves](results/adapter-v2-final.png)

## Interpretation

The pilot supports fine-tuning as a viable direction, but not at the final linear head alone, and a per-pixel nonlinear head trained mainly on clean alpha assets is still insufficient for full-body character diversity. A clean repair requires at least one of:

1. fine-tuning block70 nonlinear FFN/attention in addition to the RGB projection;
2. a small nonlinear residual adapter driven by frozen block70 features;
3. fine-tuning an earlier scale-aware stage around block38/48;
4. retraining the full network with object-normalized and paired scale-consistency losses.

Option2 is the safest next experiment but changes architecture. Options1/3 preserve the graph but require a differentiable surrogate and later exact quantized validation. The community PyTorch graph is not bit-identical and cannot be silently promoted; any learned weights must be quantized into the exact transparent model and revalidated.

## Safety and deployment

- No accepted package, DLL, manager profile or game file was modified.
- No fine-tuned checkpoint passed acceptance.
- No generated-image model was downloaded or executed. Ideogram4 is now justified for expanding full-body pose/material/background diversity, but its official local weights are gated and this machine has no configured Hugging Face token/license acceptance.
- All artifacts remain isolated in this review directory.

## Evidence

- Plans: `FIRST_PLAN.md`, `FIRST_SOLVER_AMENDMENT.md`, `SECOND_DEVELOPMENT_PLAN.md`
- Frozen targets: `TARGET_FREEZE.json`, `TARGET_MANIFEST.json`
- Exact features: `features/*/RECEIPT.json`
- First folds: `results/FOLD_RESULTS.json`
- Danger-band development: `results/DEVELOPMENT_SWEEP.json`
- Adapter plans/freezes: `ADAPTER_PLAN.md`, `ADAPTER_FREEZE.json`, `EXPANDED_ADAPTER_PLAN.md`, `ADAPTER_V2_FREEZE.json`
- V1/final results: `results/ADAPTER_HELDOUT_RESULTS.json`, `results/ADAPTER_V2_FINAL_RESULTS.json`
