# DLSSNR 310.8 native CUDA result on the Wuthering Waves frame

## Execution identity

- Runtime: `nvngx_dlssnr.dll`, SHA-256
  `e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e`.
- Embedded weights: `WEIGHTS_HT.bin`, SHA-256
  `836f445d06ecd2e59bb9f17b84b91c143396fd76ccda1c9dc7fe81d5edd548f4`.
- The CUDA trace loads the DLL's FP8 pre-block Swin, 512-channel split-Swin,
  one-dimensional ViT, decoder and post-block kernels.
- The measured call completed with `NVSDK_NGX_CUDA_EvaluateFeature = 1`,
  `cuStreamSynchronize = 0`, a complete RGBA32F readback, and no kernel Xid.

This is the native packed execution path. It is not the earlier ordinary-array
reshape in `dlssnr_full_pytorch.py`.

## Input and measurement

- Source: `/home/user/截图/截图 2026-08-30 07-45-14.png` (6144 x 3456).
- Character crop: `x=2500, y=1300, width=1000, height=1000`.
- Primary comparison: 384 x 384, zero motion, reset frame, no explicit control
  mask, intensity/tone/structure 1, skin structure -1, automatic mask off.
- The final image uses the same SDR decode rule as the Linux Vulkan bridge:
  transfer strength 1 and color strength 0. This preserves source chroma and
  transfers the neural result's luminance.
- `skin` below is a deterministic pale-color mask inside the normalized leg
  rectangle `x=[0.44,0.64), y=[0.64,0.99)`. It is an image-space proxy, not a
  semantic segmentation ground truth.

## Parameter result at 384 x 384

Values are output/input mean-luminance ratios.

| Variant | Whole crop | Skin proxy | Hair proxy |
| --- | ---: | ---: | ---: |
| Installed defaults | 0.9833 | 0.7356 | 0.8649 |
| Automatic mask on | 0.9824 | 0.7276 | 0.8533 |
| Intensity 0 | 0.9997 | 0.9997 | 0.9997 |
| Intensity 0.5 | 0.9915 | 0.8676 | 0.9323 |
| Intensity 2 | 0.9833 | 0.7356 | 0.8649 |
| Local tone 0 | 0.9941 | 0.8067 | 0.9228 |
| Local tone 2 | 0.9941 | 0.7306 | 0.8472 |
| Local structure 0 | 0.9855 | 0.9274 | 0.9212 |
| Local structure 2 | 0.9925 | 0.7127 | 0.8262 |
| Skin structure 0 or 2, auto mask off | 0.9833 | 0.7356 | 0.8649 |

The default output is visually available in
`wuwa-native-final-default/contact-sheet.png`; the final RGBA32F neural result
has SHA-256
`c3f1e7fc0bfc626825279bf2c764c3bc3adeeb763aa1dd32bc9ac675095ada4d`.

## Scale, depth and mask discrimination

With the same crop resized before inference, the skin-proxy luminance ratios
were:

| Long edge | 512 | 384 | 256 | 192 | 128 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Skin proxy ratio | 0.6920 | 0.7356 | 0.7789 | 0.9236 | 1.0142 |

Thus this isolated test does not reproduce "smaller/distant means darker". Its
scale trend is the reverse: the darkening weakens as the character becomes
smaller. That leaves a game-side distance trigger (LOD/material/lighting,
temporal history, proxy scaling, or resource integration) unresolved.

Constant depth values 0, 0.1, 0.5, 0.9 and 1, plus horizontal gradient,
vertical gradient and center-step depth maps, all produced the exact same
RGBA32F hash above. Scaling-ratio values 0.5, 0.6667, 1, 1.5 and 2 were also
bit-identical while NR upscaling was disabled. For this reset, zero-motion
single frame, neither depth values nor `ScalingRatio` cause the darkening.

An explicit one-channel control mask selects a separate control-mask post
kernel. Zero disables nearly all changes; any positive constant tested from 1
through 255 produces the same small residual. This proves runtime mask control,
but the mask's full multi-channel contract remains unknown.

## Boundary

Confirmed: the exact model/post-block can selectively darken pale character
regions far more than the whole frame, and intensity/local-structure controls
directly modulate it.

Not confirmed: that the network alone explains why a particular game changes
only at an LOD boundary. A screenshot has no genuine temporal history,
pre-tonemap HDR buffer, game motion vectors, or material/artist mask.
