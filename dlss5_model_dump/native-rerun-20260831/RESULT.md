# DLSSNR 310.8 original-DLL rerun

## Execution identity

- `nvngx_dlssnr.dll`: SHA-256
  `e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e`
- The bridge calls `NVSDK_NGX_CUDA_EvaluateFeature` with real CUDA arrays and
  reads the DLL-produced RGBA32F output back.
- All cases use reset single frames, zero motion vectors, depth 0.5, no control
  mask, intensity/tone/structure 1, skin -1, style 0 and automatic mask off.

## Repetition and old/new numeric comparison

The network has no sampling temperature. Under these fixed inputs it was also
measured to be deterministic rather than merely assumed to be deterministic:

- Trump 256 and Wuthering Waves 384 were each executed in three separately
  created Wine/NGX feature instances. Pairwise maximum pixel difference: `0`.
- 51 newly generated outputs were compared with the corresponding earlier
  native RGBA32F files by subtracting every float in chunks.
- Compared values: `163,315,712` floats.
- Global maximum absolute difference: `0`.
- Global mean absolute difference: `0`.
- Unequal floats: `0`.

The old results therefore came from the same deterministic original-DLL path;
they were not outputs of the approximate full-PyTorch reconstruction.

## Skin-region result

All luminance ratios below are output/input means over masks derived only from
the input image. A value below one is darker.

| Input and ROI | Resolution | Luminance ratio | Darker pixels |
| --- | ---: | ---: | ---: |
| MetaHuman Creator face | 256 | 1.049 | 23.5% |
| MetaHuman Hero face | 256 | 0.980 | 40.1% |
| Obama face | 256 | 0.865 | 72.6% |
| Trump face | 256 | 0.868 | 83.5% |
| Xi face | 256 | 0.915 | 77.2% |
| Wuthering Waves pale leg | 384 | 0.731 | 99.4% |
| Honkai: Star Rail Castorice face | native 6K frame | 0.725 | 96.8% |
| Honkai Impact 3rd face | native 2560 frame | 0.646 | 98.2% |
| UE character diffuse texture A | 1024 | 0.984 | 57.7% |
| UE character diffuse texture B | 1024 | 0.979 | 54.9% |

The effect is not a uniform exposure shift. For example, at 256 the Obama
skin-region channel ratios were R/G/B = `0.766/0.907/1.066`, and Xi was
`0.836/0.949/1.067`. MetaHuman Creator instead became slightly brighter while
its channels shifted to `0.917/1.131/1.321`.

## Scale result

The Wuthering Waves pale-leg ratio as the same crop was resized was:

| Size | 512 | 384 | 256 | 192 | 128 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Luminance ratio | 0.702 | 0.731 | 0.790 | 0.929 | 1.015 |

Thus the original model definitely contains a selective skin/tone failure on
these lit frames, but this still-image experiment does not reproduce the
specific rule “farther/smaller is darker.” In this Wuthering Waves crop the
effect weakens as the character becomes smaller. The game-only distance/LOD
transition may additionally require temporal history, real motion vectors,
engine depth/masks, pre-tonemap color, or a material/LOD change.

The two diffuse textures were comparatively stable, which points away from a
simple unconditional skin-texture transform and toward the network's learned
lighting/structure interpretation or its final control/post-processing path.

## Files

- `skin-comparison.png`: input, original DLL output, and 4x display-space
  absolute difference.
- `skin-summary.csv`: selected skin measurements.
- `skin-metrics.csv`: all sizes and regions.
- `old-new-numeric-comparison.csv`: numeric old/new comparisons.
- `rerun_suite.sh`: exact rerun command set.
