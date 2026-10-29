# Frozen nonlinear RGB-head adapter plan

The original 96-weight linear head cannot isolate the 40–90 px danger band without changing close faces/background. Before generating new held-out identities, freeze this one nonlinear pilot.

## Architecture

- Input: exact frozen block70 pre-head feature, 32 channels per pixel.
- Normalize with train-sample mean/std.
- Zero-initialized residual MLP: `Linear(32,32) -> SiLU -> Linear(32,3)`.
- Output is added to the original exact learned RGB head; original head and all NR71 weights remain frozen.
- Trainable scalars: 1,155. No mask, scale, identity, coordinates or control values are provided at inference.

## Training data

Use only the four already-developed identities. For every frozen scale case sample deterministically:

- 1,024 background pixels;
- 1,024 person-alpha pixels;
- 2,048 warm-face pixels;
- 4,096 pixels from the background-only control.

Correction targets are the frozen close-teacher head deltas only for 40–90 px apparent faces; every other target is zero/original distillation. Sampling seed `2026091601`.

## Optimization

- AdamW, lr `1e-3`, weight decay `1e-4`;
- batch8192, 30 epochs;
- fixed seed `2026091602`;
- MSE target in learned-head RGB-logit units;
- no hyperparameter selection after held-out generation.

GPU execution must use benchmark.lock, no-games gate, Guardian, <31,000 MiB cap, >=4GiB free and a 30-second command watchdog.

## New untouched held-out identities

After the adapter checkpoint and hash are frozen, generate/capture exactly four new MIT Fluent identities at the same eight scales and background:

- `fluent-001` man construction worker;
- `fluent-009` person fairy;
- `fluent-021` face with hand over mouth;
- `fluent-026` face with open mouth.

No retraining or threshold changes after any held-out output is inspected.

## Acceptance

On every held-out identity:

1. worst danger-band face darkening improves >=0.05 EV;
2. mean absolute change on apparent face height >=160 px is <=0.03 EV;
3. maximum outside-person RGB MAE is <=1/255;
4. background-only RGB MAE is <=1/255;
5. outputs are finite.

This adapter is a research proof. Passing does not make it drop-in compatible with the original DLL graph.
