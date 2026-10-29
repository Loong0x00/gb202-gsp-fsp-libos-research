# Camera-distance / screen-size darkening follow-up

## Finding

The observation is plausible and independently reported, but public reports mix three distinct effects: true luminance darkening, added makeup/shadows, and distance-dependent blur/oil-painting. They must not be conflated.

### Direct/near-direct community evidence

1. ResetEra's indexed opening summary for *Is DLSS 5 Good? (Full Analysis)* states: **“When zoomed further out, DLSS5 makes characters look darker, older, and shinier than they should be.”** Direct page access returned 403, so this quote is based on indexed text rather than a complete page capture:
   https://www.resetera.com/threads/is-dlss-5-good-full-analysis-hardware-unboxed.1631371/

2. In the Resident Evil Requiem discussion, a commenter reports that the **close-up cinematic shot looks like the character**, while the **more distant shot** is where DLSS 5 appears to add makeup and make her look like a different person. This is direct near/far appearance evidence, though it combines tone, local contrast, and identity rather than measuring mean luminance:
   https://www.reddit.com/r/ResidentEvilRequiem/comments/1rwthj0/dlss_5_characters_appear_inconsistent/

3. Kran's DLSS 5 test separately reports **“diminishing returns at a distance”** and that explicit game-side operator brightening can be replaced/darkened back toward inferred scene brightness. It supports both ingredients but is not itself a controlled statement that distance causes darkness:
   https://kran.gg/Blog/dlss-5-testing

Older Ray Reconstruction discussions consistently report that distant faces become blurrier, waxier, ghosted, or oil-painted. Direct inspection did not find an explicit brightness-vs-distance claim in those older threads, so they are supporting evidence for screen-size sensitivity only.

The Bilibili page `BV1kftw6UEbc` could not be directly inspected (HTTP 412); no claim is made from its title alone.

## Transparent-model scale audit already completed

A post-primary fixed-512 audit resized the same source into a fixed gray canvas at 0.50, 0.75, and 1.00 scale. Mean output delta-EV over the source support was:

| source | 0.50 scale | 0.75 scale | 1.00 scale | range |
|---|---:|---:|---:|---:|
| real portrait | -0.1498 | -0.0861 | -0.0393 | 0.1105 EV |
| MIT stylized figure | -0.0552 | -0.0200 | -0.0158 | 0.0394 EV |
| game/HSR frame | -0.0579 | -0.0233 | -0.0123 | 0.0456 EV |

All three become darker as the source occupies fewer pixels. Files: `results/SCALE_RESULTS.json` and `SCALE_CAPTURE_ACCEPTANCE.json`.

This is not yet a pure camera-distance experiment: shrinking exposes more gray surround and changes spatial-frequency content. Real camera motion additionally changes LOD, mips, perspective, occlusion, and motion history. Nevertheless, the same direction across real/stylized/game inputs shows that the distance observation is compatible with the transparent NR model itself and is not only a game LOD hypothesis.

## Most likely mechanism

The result does not require explicit semantic supervision. The public path compresses the 512-pixel visible dimension to an 8-cell bottleneck before/through the global ViT representation. One bottleneck cell corresponds to roughly 64 visible pixels. A distant 32-pixel face is sub-cell; a 128-pixel close face spans about two cells. At small screen size, skin color is mixed with hair, shadow, background, and silhouette before the global relighting field is inferred. At close range, local evidence occupies multiple cells and anchors color/brightness more strongly.

This is equivalent to a prior/likelihood tradeoff:

- close object: strong local evidence, less freedom to relight;
- distant/small object: weak and mixed evidence, global learned prior dominates;
- decoder then broadcasts the coarse relighting decision back through high-resolution skips.

The effect may combine learned scale correlations, fixed-window pooling/aliasing, FP8 quantization, and training-reference minification. Current evidence does not isolate their shares.

## Decisive next control

Use one fixed source patch at several pixel footprints on an otherwise identical uniform background, while independently controlling:

1. object footprint (16/32/64/128/256 px),
2. surround color and luminance,
3. total image histogram,
4. object position,
5. blur/mip bandwidth,
6. temporal history.

Measure cellwise delta-EV and block22/block38 directions. A monotonic footprint curve with surround held fixed would establish true scale dependence; disappearance after bandwidth matching would point to minification/aliasing; disappearance after bottleneck-direction removal would implicate the block38 relighting prior.
