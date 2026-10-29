# Person-only screen-space scale experiment

## Result

The preregistered simple prediction, “the smaller the whole person, the darker it becomes monotonically,” **failed**. The effect is stronger and more specific:

> **Face darkening has a scale resonance. All four sources are darkest when the input-derived face component is approximately 46–76 pixels high, clustered around one 64-pixel cell of the 512→8 global bottleneck. Very small faces become less dark again, and close/large faces recover.**

This is much more consistent with a fixed-window/downsampling/receptive-field transition than with a model reading physical camera distance.

![Face scale curve](results/face_scale_curve.png)

## Frozen input matrix

- Four MIT Fluent RGBA cutouts: two upper-body people and two standalone faces.
- Person foreground heights: 32, 48, 64, 96, 128, 192, 256, 320 px.
- Fixed 512×512 canvas; fixed sRGB `(0.35,0.35,0.35)` background; fixed center `(256,256)`.
- Only the cropped foreground was isotropically Lanczos-resized and source-over composited.
- No camera metadata, depth, LOD, motion, temporal history, histogram correction, or output-driven case removal.
- 32 person cases plus one background-only control.

`INPUT_ACCEPTANCE.json` confirms every pixel outside the foreground rectangle remains exactly the same float32 background value. `CAPTURE_ACCEPTANCE.json` confirms all 33 transparent NR71 runs, all boundaries, finite outputs, and hashes.

## Registered whole-foreground endpoint

The strong monotonic rule required positive EV/octave slope and Spearman >=0.8 for all four sources. It failed:

| source | whole-foreground EV/octave | Spearman | interpretation |
|---|---:|---:|---|
| health worker | -0.0228 | -0.357 | non-monotonic; larger initially darker |
| woman artist | +0.0220 | 0.548 | weak/non-monotonic |
| diagonal-mouth face | +0.0649 | 0.929 | strong recovery with size |
| monocle face | +0.0514 | 0.905 | strong recovery with size |

The whole-person metric mixes bright clothing, tools and skin. Its failure was preserved; the face-only follow-up was declared separately before extracting an input-derived warm face component.

## Face-region follow-up

The face mask uses source pixels only: a frozen warm-color threshold, connected components, upper/central location, and largest eligible component. No output pixel influences it.

| source | darkest apparent face height | darkest face ΔEV | smallest-face ΔEV | largest-face ΔEV |
|---|---:|---:|---:|---:|
| health worker | 76.0 px | -0.4267 | -0.1900 at 19 px | -0.3190 at 190 px |
| woman artist | 49.3 px | -0.4225 | -0.2320 at 16 px | -0.2430 at 164 px |
| diagonal-mouth face | 46.3 px | -0.3180 | -0.2410 at 31 px | -0.0700 at 309 px |
| monocle face | 61.7 px | -0.2983 | -0.2360 at 31 px | -0.0870 at 309 px |

Observed darkest sizes are `[46.3, 49.3, 61.7, 76.0]` px, median about 55.5 px. Input face luminance is nearly stable after the smallest sizes, while output luminance develops the trough, so the result is not explained by the resized input simply becoming darker.

For example, the diagonal-mouth input face luminance stays near 0.51, while output luminance is 0.411 at 46 px and recovers to 0.490 at 309 px. The health-worker input face stays near 0.53, but output falls to about 0.393 at 76 px.

![Input/output face luminance](results/face_input_output_luma.png)

## Architectural correspondence

Along the visible 512-pixel dimension, the public route has approximate spatial steps:

- block4: 256 cells → 2 px/cell;
- block8: 128 → 4 px/cell;
- block14: 64 → 8 px/cell;
- block22-high: 32 → 16 px/cell;
- block22-low: 16 → 32 px/cell;
- block38 global ViT: 8 → **64 px/cell**.

The darkening trough around 46–76 face pixels therefore falls almost exactly where a face changes from sub-cell to roughly one global-token cell. The two upper-body sources look different when indexed by whole-person height, but align with the standalone faces when indexed by face height.

A plausible mechanism is:

1. much smaller than one cell: the face is not represented strongly enough to trigger the full relighting prior;
2. around one cell: it is recognizable as a face/material region but local color evidence is maximally mixed with hair, silhouette and background, producing the strongest inferred shadow/relighting;
3. multiple cells: local color evidence constrains the reconstruction and brightness recovers.

This is a scale resonance, not simply “farther is always darker.” A normal game camera often moves a face from multiple cells into the one-cell band, which appears as distance-dependent darkening; at extreme distance the face may collapse or switch LOD before the curve's smallest-scale recovery is noticed.

## Internal fixed-probe readout

The previously frozen image/block22/block38 Ridge probes also show non-monotonic scale curves, commonly reaching their darkest prediction around person heights 96–128 px. Their 8×8 readout cannot resolve the smallest face ROIs accurately and is diagnostic only. Actual alpha/face-weighted output is the primary evidence.

## Scope and caveats

- This is an exact transparent first-frame public-path experiment, not a fresh original-DLL run for these 33 inputs. A new native run would require separate guarded GPU approval.
- The face-region result is explicitly post-primary/exploratory, although its mask rule was frozen before region extraction.
- Lanczos resampling bandwidth changes with size; the test establishes foreground-size dependence but does not yet separate learned priors from minification/aliasing.
- The sources are 3D Fluent Emoji assets on one fixed background. Real/anime segmented characters and multiple fixed backgrounds are needed for external validity.
- No temporal camera movement, motion vectors, LOD or mip changes are present.

## Artifacts

- Frozen plan and inputs: `FIRST_PLAN.md`, `FREEZE.json`, `MANIFEST.json`, `INPUT_ACCEPTANCE.json`
- Captures: `CAPTURE_ACCEPTANCE.json`, `activations/`
- Registered result: `results/RESULT.json`
- Face follow-up plan/result: `FACE_REGION_FOLLOWUP_PLAN.md`, `results/FACE_REGION_RESULT.json`
- Figures: `results/face_scale_curve.png`, `results/face_input_output_luma.png`, `results/contact-*.jpg`
