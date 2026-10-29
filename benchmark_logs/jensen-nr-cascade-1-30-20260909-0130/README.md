# Jensen Huang: true NR cascade, passes 1–30

## Result

All 30 passes completed and independently verified. Pass 1 is byte-identical to
our archived 1920x1920 all-default baseline. Each pass consumes the previous
unmodified float32 neural output, **not** the original image or a PNG.

Visually, repeated inference progressively changes the face, eyeglasses, hair,
jacket and background. In the raw neural output, the previously clear eyeglasses
become dark/asymmetric, facial spots/textures strengthen, and the jacket loses
its original leather highlights. The high-pass results are not a monotonic
improvement in faithful detail. At pass 30, the fixed input-derived face/skin ROI
has about 59.14% of the original luma, while the whole image reaches about 117.42%.

Step-to-step raw RGB MAE drops initially but remains about 0.00555 at pass 30;
within these 30 passes there is no byte-identical fixed point. Face-luma drift
slows, but the whole image continues brightening.

## Viewing

- `all-passes-neural-full.jpg` / `all-passes-neural-face.jpg`: all passes, **raw neural RGB**, only display quantization.
- `selected-neural-full.png` / `selected-neural-face.png`: original, 1, 2, 3, 5, 10, 20, 30, raw neural RGB.
- `all-passes-full.jpg` / `all-passes-face.jpg` and `selected-*.png` without `neural`: luminance-only composition against the immutable original; **these composed images are not fed back**.
- `pass-NN/neural.rgba32f`: exact raw output consumed by pass NN+1.
- `pass-NN/neural.png`: raw neural viewing image.
- `pass-NN/final.png`: composed viewing image.

The conspicuous colored rims in composed previews must not be confused with raw
neural colors. Raw-neural sheets are the primary evidence for model-output drift.

## Protocol / limits

Source: NVIDIA official 1920x1920 JPEG; RGB/255 with no linearization; alpha1.
All 30 passes use Intensity/Tone/Structure=1, Skin=-1, Style/Preset=0, AutoMask off,
constant depth0.5, zero motion, no control mask, fresh feature and Reset=1.
Every raw result is finite, in [0,1], and has alpha1. No intermediate clipping,
resize, JPEG/PNG quantization or display composition is fed into the cascade.

This is repeated application of a static-photo NR operator, not motion/FG
validation, a denoising-diffusion sampling schedule, or the exact community
multipass policy (which can apply tone only on its first pass and retain
independent histories across game frames). A photograph and synthetic guides
also do not establish behavior on properly integrated game inputs.

The existing Wine probe uses identity/architecture compatibility shims. On-disk
DLL/model identity is unchanged. Per-pass event/readback success is verified;
wall time includes process startup/IO and is not inference performance.

## Measurements

Luma below is the experiment's RGB-domain weighted luma, not a physical
linear-light exposure measurement. ROI is fixed from the original input.

| NR passes | Face luma / original | Whole luma / original | Raw RGB MAE vs previous |
|---:|---:|---:|---:|
| 1 | 85.07% | 98.69% | 0.027701 |
| 2 | 77.21% | 98.88% | 0.018021 |
| 3 | 73.16% | 99.37% | 0.011545 |
| 4 | 70.45% | 99.94% | 0.008501 |
| 5 | 68.61% | 100.52% | 0.007150 |
| 6 | 67.40% | 101.11% | 0.006265 |
| 7 | 66.16% | 101.70% | 0.005906 |
| 8 | 65.35% | 102.28% | 0.005500 |
| 9 | 64.63% | 102.88% | 0.005324 |
| 10 | 63.82% | 103.50% | 0.005151 |
| 11 | 63.24% | 104.12% | 0.004976 |
| 12 | 62.54% | 104.73% | 0.004847 |
| 13 | 62.31% | 105.37% | 0.004788 |
| 14 | 62.04% | 105.99% | 0.004717 |
| 15 | 61.68% | 106.65% | 0.004735 |
| 16 | 61.66% | 107.32% | 0.004697 |
| 17 | 61.28% | 107.99% | 0.005005 |
| 18 | 61.12% | 108.69% | 0.005249 |
| 19 | 60.95% | 109.38% | 0.005250 |
| 20 | 60.70% | 110.12% | 0.005456 |
| 21 | 60.45% | 110.81% | 0.005352 |
| 22 | 60.44% | 111.51% | 0.005567 |
| 23 | 60.27% | 112.21% | 0.005580 |
| 24 | 60.25% | 112.96% | 0.005576 |
| 25 | 60.16% | 113.70% | 0.005745 |
| 26 | 59.81% | 114.46% | 0.005715 |
| 27 | 59.67% | 115.19% | 0.005629 |
| 28 | 59.36% | 115.89% | 0.005629 |
| 29 | 59.15% | 116.66% | 0.005693 |
| 30 | 59.14% | 117.42% | 0.005549 |

## Files and bounds

Run directory stayed below its 3 GiB hard bound; approximately 2.03 GiB before
these supplemental plots. No game deployment, driver, or GPU clocks were changed.
See `METADATA.json`, `VERIFICATION.json`, `metrics.csv`, and per-pass logs.
