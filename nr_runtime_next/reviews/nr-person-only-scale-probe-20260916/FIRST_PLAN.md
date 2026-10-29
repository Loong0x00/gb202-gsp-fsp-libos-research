# Person-only screen-space scale experiment — frozen plan

Goal: test whether the transparent NR71 route darkens an otherwise unchanged person as only the foreground person's screen-space size changes.

## Inputs

- Canvas: fixed 512×512 RGBA32F.
- Background: fixed uniform sRGB `(0.35, 0.35, 0.35)`, unchanged byte-for-byte in every case.
- Position: alpha-bounding-box center fixed at canvas `(256,256)`.
- Sources: four pinned MIT Fluent Emoji RGBA cutouts with native alpha:
  - `fluent-003` man health worker;
  - `fluent-014` woman artist;
  - `fluent-020` face with diagonal mouth;
  - `fluent-024` face with monocle.
- Only transformation: isotropic Lanczos resize of the cropped RGBA foreground to heights `32,48,64,96,128,192,256,320` pixels, preserving aspect ratio, then source-over compositing onto the fixed background.
- NR controls fixed to tone=.25, structure=.75, style=0, skin=-1, auto-mask=false.
- A background-only input is included as an integrity control.

Changing foreground size necessarily changes its occupied area and resampling bandwidth. No histogram compensation, background resize, camera metadata, LOD, temporal history, or target-dependent case removal is allowed in this first test.

## Primary endpoint

Within each case's stored alpha mask:

1. weighted mean output-vs-input luminance `delta_ev` in inverse-sRGB Rec.709 luminance;
2. weighted mean of per-pixel `delta_ev` for alpha-core pixels (`alpha>=0.9`);
3. slope in EV per octave of foreground height and Spearman correlation across the eight fixed scales.

Prediction frozen before execution: larger foregrounds will be less dark, so slope and Spearman(height, delta_ev) are positive. Strong replication requires positive slope and Spearman >=0.8 for all four sources.

## Internal readout

Passively retain block22-low and block38 boundaries. Apply the already-frozen, identity-corrected image/block22/block38 Ridge probes from `nr-darkening-onset-probe-20260915` without retraining, and report alpha-weighted 8×8 predicted delta-EV versus scale. These are diagnostic; actual output ROI is primary.

## Interpretation limits

- A positive result establishes screen-space-size dependence with a fixed background, not physical camera-distance sensing.
- It does not by itself distinguish learned scale priors, resize/minification bandwidth, encoder pooling, FP8 quantization, or the 8×8 bottleneck.
- This first-frame 512×512 result cannot be extrapolated to LOD/mips, motion, later temporal counters, or live-game camera movement.
