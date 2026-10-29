# DLSS5 / Feature18 input coverage

Audited runtime: `nvngx_dlssnr.dll`, SHA-256
`e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e`.

Static string inventory contains exactly 61 `DLSSNR.*` keys. These are private
runtime parameter names recovered from the binary, **not an NVIDIA-published
Feature18 SDK schema**. They are not 61 user-facing settings:

- 16 scalar/control semantics;
- 9 resource groups, each consisting of a resource pointer and X/Y/Width/Height
  subrect (9 × 5 = 45).

## Scalar/control semantics (16/16 handled)

| Runtime key | Controller/backend handling |
|---|---|
| `DLSSNR.Enabled` | Neural Uplift master gate; disabled path preserves native DLSS |
| `DLSSNR.Width`, `Height` | derived from output dimensions |
| `DLSSNR.ScalingRatio` | derived from dimensions and NR upscaling switch |
| `DLSSNR.Reset` | game reset, first frame, phase transition and controller re-enable |
| `DLSSNR.Hint.Render.Preset` | Model preset |
| `DLSSNR.Style` | Style |
| `DLSSNR.Intensity` | Intensity |
| `DLSSNR.LocalToneStrength` | Local tone |
| `DLSSNR.LocalStructureStrength` | Local structure |
| `DLSSNR.SkinStructureStrength` | Skin structure |
| `DLSSNR.UseAutoMask` | Auto mask |
| `DLSSNR.UICorrection` | UI correction flag |
| `DLSSNR.DepthInverted` | game-derived with optional depth-mode override |
| `DLSSNR.MVecScaleX`, `MVecScaleY` | game scale multiplied by controller override |

Width, height and scaling ratio are deliberately not free-form text fields:
invalid combinations violate the Feature18 create/evaluate contract. Reset is a
one-frame temporal event rather than a persistent numeric preference.

## Resource groups (automatic, conditional)

The runtime names these groups: Backbuffer, BidirectionalDistortionField, Color,
ControlMask, Depth, MVec, Output, UI and UIAlpha. Every group also has four
subrect keys.

HSR's upstream NGX contract exposes Color/Output/Depth/MVec. The router obtains
those resources without changing the signed NVIDIA DLL, and the service binds
all four pointers and their active subrects. The other five groups are optional
runtime inputs but HSR does not expose corresponding resources. A controller
cannot synthesize valid per-frame textures or GPU addresses; a backend may bind
them only when the game/API actually supplies them.

## Adapter and bridge-only controls

`NeuralUplift` is the controller/RenoDX master gate. `NREnableUpscaling` is a
bridge-level switch that derives `DLSSNR.ScalingRatio` and the create contract;
neither name is a native `DLSSNR.*` key. `NRDepthMode` is a three-state UI
wrapper around the native boolean `DLSSNR.DepthInverted`.

Paper white, HDR transfer and original-color blend are codec/bridge controls,
not native `DLSSNR.*` keys. They are explicitly labelled as such in the UI.

The Feature18 preset in this controller is `DLSSNR.Hint.Render.Preset` (0..3).
It is unrelated to the game's DLSS Ray Reconstruction Preset F or DLSS Super
Resolution Preset K. Legacy post-service builds choose the Feature18 network at
CreateFeature, so a hot preset change is only guaranteed after restart.

Therefore “all settings” means all known scalar/control semantics are handled.
It does **not** mean that optional resource channels absent from a game's render
contract are fabricated.
