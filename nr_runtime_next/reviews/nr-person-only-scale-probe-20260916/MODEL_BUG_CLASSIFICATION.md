# Model-bug classification

## Classification

**Root defect:** NR71 screen-space scale / photometric-consistency defect.

**Ordinary trigger:** a character face crossing approximately 46–76 input pixels during normal camera zoom or movement.

**Observed model behavior:** fixed-background, person-only resizing produces a non-input-driven face luminance trough of roughly -0.30 to -0.43 EV near the 512→8 bottleneck's 64-pixel cell scale. The registered whole-person monotonic hypothesis failed, but all four source-derived face regions share the scale-localized trough.

## Why this is a model defect rather than a game/bridge artifact

The reproduction contains no game engine, LOD, mip selection, physical camera, depth change, motion vector, temporal history, or community plugin compositor. It runs the transparent NR71 first-frame model directly and measures its final RGBA32F surface. The fixed background remains byte-identical outside the resized foreground input rectangle.

Therefore the controlled reproduction rules out game camera/LOD behavior and the external HDR/color bridge as necessary causes. Resize bandwidth remains a mechanistic contributor to separate, but a production reconstruction model should not convert that ordinary scale change into a repeatable 0.3–0.4 EV facial exposure error.

## Workaround versus fix

`NRTransferStrength` (HDR transfer strength) and `NRColorStrength` (original-color retention) are explicitly codec/bridge compositor controls in the current frontend, not NVIDIA DLSSNR native model keys (`dlss5_linux_frontend/app.py`). Lowering transfer strength and/or increasing original-color retention can attenuate parts of the visible transfer by reducing the model contribution or blending input color back. It cannot be treated as a fix. The current Wuthering Waves deployment was manually set to the extreme `NRTransferStrength=0`, `NRColorStrength=1`, yet the user still observes the distance-dependent character darkening. This is direct operational evidence that the global bridge controls cannot cancel the model's spatially and non-monotonically varying error.

A static global setting cannot simultaneously optimize near faces and the 46–76 px danger band: tuning for far characters sacrifices or suppresses the desired near-field effect, while tuning for near characters leaves the far-field defect. Because the measured curve is non-monotonic, even a single monotonic distance-strength curve is insufficient. A model fix requires scale-consistency training/validation, better spatial capacity/routing, or revised weights/objective. The only robust integration-side avoidance is to exclude characters from neural uplift using a stable object mask; any scale-aware dynamic compensation is an emergency workaround that adds temporal and per-object complexity.
