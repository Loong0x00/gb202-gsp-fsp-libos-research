# Context-gated V4 plan — frozen before gate dataset/training

V3 supplies adequate correction amplitude but a per-pixel 32-channel adapter cannot reliably distinguish dangerous small/full-body faces from close faces. Freeze V3 and add only a spatial/context gate:

`correction = sigmoid(Linear16(SiLU(Linear128(context)))) * V3_correction`

Context at each pixel is the concatenation of exact block70 features at that pixel, clipped centered 16×16 box mean, clipped centered64×64 box mean, and frame-global mean (4×32=128 values). Pooling is float32 with explicit clipped bounds. Trainable gate:2,081 scalars. V3’s1,155 scalars and all original NR71 weights remain frozen.

## Gate labels

- face pixels at input-derived40–90px face height:1;
- face pixels outside that band:0;
- sampled person/non-face and background pixels:0.

Use the22 generated V3 training identities plus the now-archived V3 final inputs as gate development/training. V3 final results remain immutable historical evidence and are no longer a blind cohort for V4. Per case sample512 face,256 person/non-face and256 background pixels with deterministic seed2026091802. Train from zero for30epochs with AdamW using BCE-with-logits and fixed natural class `pos_weight`; no architecture or threshold sweep.

## New strict final cohort

Freeze before training:

- Fluent: `fluent-015`, `fluent-016`, `fluent-017`, `fluent-029`;
- six new Ideogram prompt/seed identities, not generated until checkpoint freeze.

Gates remain unchanged: worst danger-band improvement>=0.05EV, close change<=0.03EV, outside/background RGB MAE<=1/255, finite output, every identity passes. V4 is research-only unless quantized and replayed through the transparent exact suffix.
