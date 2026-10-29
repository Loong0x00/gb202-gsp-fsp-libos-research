# DLSSNR still-image tests: Honkai Impact 3rd and Houkai Gakuen 2

Exact DLSSNR 310.8 native/CUBIN backend, driven by
`dlssnr_native_pytorch.py`. All runs use a reset single frame, zero motion
vectors, constant depth 0.5, no control mask, and the installed bridge defaults:
intensity/tone/structure 1, skin -1, style 0, automatic mask off, transfer 1,
color strength 0.

## Sources

- `sources/hi3-steam-community-2560x1600.jpg`
  - Steam Community screenshot gallery:
    https://steamcommunity.com/app/1671200/screenshots/
  - Exact image:
    https://images.steamusercontent.com/ugc/15764658454266010245/561A82906EFCFDC1BB932C3F7C827097CBB315B9/
- `sources/hg2-qooapp-1280x720.png`
  - QooApp game page: https://apps.qoo-app.com/app/4117
  - Exact image:
    https://download.qoo-app.com/screenshots/054170906d53d126964577d5a4f194fffd9e19df.png

## Runs

- `hi3-default-2560/`: native 2560x1600 input.
- `hg2-default-2560/`: 1280x720 source resampled to 2560x1440 before inference.
- `hg2-default-native1280/`: source-native 1280x720 inference.
- `hg2-character-crop-1024/`: a 500x500 crop containing the right-hand sprite,
  resampled to 1024x1024 to test screen-size sensitivity; this is an ablation,
  not a representation of normal gameplay.

## Main observations

- HI3 face mean luminance changed to 0.8297x and the broader upper-body skin
  region to 0.8475x, while a stone-background region rose to 1.0569x. False
  high-frequency skin texture was added.
- HG2 was comparatively stable. At 2560 the two sprite regions changed to
  1.0228x and 1.0649x mean luminance; the full native-1280 frame changed to
  1.0212x. The dominant effect was local contrast/saturation rather than
  photorealistic face reconstruction.

The synthetic single-frame guides make this a model-prior test, not an exact
simulation of an engine integration.
