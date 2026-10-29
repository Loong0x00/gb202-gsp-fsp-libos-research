# NR71 person-scale block70 RGB-head fine-tune — frozen pilot plan

## Goal

Test whether a minimal, image-only weight update can reduce the 46–76 px person/face darkening resonance without changing controls, graph topology, temporal alpha/history behavior, or existing deployment.

## Data

Use the already frozen 33-case fixed-background/person-only scale matrix from `nr-person-only-scale-probe-20260916`: four MIT Fluent source identities at foreground heights 32/48/64/96/128/192/256/320 plus one background control. Inputs, alpha masks, controls and original exact NR71 boundaries remain immutable.

No generative model is needed for this pilot: procedural alpha compositing provides exact same-identity/multi-scale pairs and masks, which text-to-image cannot provide as reliably. Ideogram 4 may later expand identity/background diversity, but its local checkpoint is gated and no Hugging Face token/license acceptance is currently configured.

## Frozen/trainable scope

- Freeze all feature inputs and controls: tone=.25, structure=.75, style=0, skin=-1, auto-mask=false.
- Freeze blocks0–69 and all block70 attention/FFN/QKV/normalization weights.
- Freeze block70 channel3/history logit and unused channels4–15.
- Train only the 32×3 live RGB columns of the block70 output head: **96 scalar weights**.
- Start from the recovered original FP16 head weights.

This is deliberately a minimal image-head fine-tune, not a claim that it repairs the underlying block38 scale representation.

## Exact frozen features

Re-run only the accepted transparent suffix on each frozen case while passively capturing the exact block70 attention prequantization feature presented to the output head. Capture must not change the original output hash.

## Self-distilled scale-consistency target

For each source identity, use the h=320 learned RGB residual field as its fixed close-scale teacher. Crop its foreground rectangle, resize it to every smaller frozen foreground rectangle, and alpha-composite that teacher residual into the original learned residual field. Thus the desired person residual is the same close-scale NR behavior transformed only by scale; background and pixels outside the person remain the original model target.

The target is generated before optimization and hashed. No target comes from a post-hoc brightness scalar or held-out output fitting.

## Loss and splits

- Person alpha-weighted RGB residual MSE: weight4.
- Input-derived warm face-component residual MSE: additional weight8.
- Background distillation to original head output: weight1.
- L2 weight drift from original RGB head.

Run four leave-one-source-identity-out folds. Select optimizer steps/L2 only using the three training identities through a fixed, predeclared grid; report every fold. A final all-identity pilot may be exported only after held-out folds are scored.

## Acceptance

A fold passes only if, after FP16 quantization of the 96 weights:

1. held-out face-region worst darkening improves by at least 0.05 EV;
2. held-out large-face (>=160 px apparent face height) mean change relative to original is <=0.03 EV absolute;
3. background-only and outside-person output drift is <=1/255 mean absolute RGB;
4. all outputs are finite;
5. the original untuned head is exactly reproduced by the evaluation path before comparison.

The result is a research checkpoint/slab only. It must not modify the accepted package, DLL, manager, or game deployment.
