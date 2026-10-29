# Wuthering Waves: community-good vs owned DLSS5 path

Static comparison date: 2026-09-01.

## Reference artifacts

- Community add-on: `renodx-dlss5.addon64`
  - SHA-256: `b842c25ee22bcd56904dfcfacdf5b575fe970a80aea77fc78fd7aeede0ff8e8b`
  - PE timestamp: `0x6a90d4a4`
- Community Vulkan bridge:
  - SHA-256: `ba6c126ca44b1ff4c96b45d7c575d0b891a9a210390edc2614613924e2852799`
- Preserved usable baseline:
  - `/home/user/.local/share/Steam/steamapps/common/Wuthering Waves/Client/Binaries/Win64/.dlss-ngx-router/backups/20260831-clean-owned-v1/baseline-community-good/`
- Owned source:
  - `dlss5_vk_bridge.cpp`, built with `DLSS5_POST_SERVICE=1`
  - `/home/user/rt_5090_project/dlss_ngx_proxy/src/router_addon.cpp`

## Paths that already match

- Both execute after the original SR `EvaluateFeature` succeeds.
- Both preserve the completed game Output in a same-format snapshot using:
  - game Output: `UNORDERED_ACCESS -> COPY_SOURCE -> UNORDERED_ACCESS`
  - snapshot: `NON_PIXEL_SHADER_RESOURCE -> COPY_DEST -> NON_PIXEL_SHADER_RESOURCE`
- Both encode the snapshot into RGBA16F, run Vulkan Feature 18, and decode directly into the original R11G11B10 game Output.
- The owned GLSL codec is a semantic translation of the community add-on's captured HLSL (`dlss5-codec-encode.hlsl` / `dlss5-codec-decode.hlsl`).
- Current live controls match the usable baseline: preset/style 0, intensity/tone/structure 1, skin -1, auto-mask off, transfer 1, color strength 0.
- Native WuWa guides are 4099x2306 motion and 4100x2308 depth.

## Material mismatches found

The relevant community routines were decompiled at RVA `0x139c0` (copy game parameters), `0xdcf0` (Feature 18 create), `0x14660` (per-frame evaluation parameters), and `0x12f15` (codec HDR selection).

### 1. Codec HDR mode

Community code sets codec `HdrMode = clean_feature_flags & 1`. WuWa's source flags are `0x4b`, so the usable path runs `HdrMode=1`: soft clip -> sRGB model domain -> UpgradeToneMap decode.

The owned service instead defaulted to `HdrMode=0` unless a diagnostic marker existed. That put bright HDR values directly through the raw linear path and is the strongest match for “strong light flickers much more than weak light”.

Fix: derive HDR mode automatically from source flag bit 0. The old marker remains only as a force-on diagnostic.

### 2. Native evaluation was mislabeled as NR upscaling

With `NREnableUpscaling=0`, community evaluation uses:

- `DLSSNR.ScalingRatio = 1.0`
- `DLSSNR.Scale = 1.0`
- `DLSSNR.Upscaling = false`
- native 4099x2306 / 4100x2308 guides

Only the 6K `CreateFeature` call is temporarily rewritten by the Vulkan bridge to scale 0.5, `Upscaling=true`, input 4096x2304. Community RVA `0x14660` restores native mode before every evaluation.

The owned service left scale 0.5 and `Upscaling=true` active during every evaluation.

Fix: reproduce the create-only compatibility rewrite, then restore scale 1/native mode before `EvaluateFeature`.

### 3. Feature flags were copied from SR without sanitizing

Community RVA `0x139c0` constructs a fresh NR flag word containing only HDR bit 0 and depth-inversion bit 3. For this WuWa run the Feature 18 word is `0x09`.

The owned service reused the original SR word `0x4b`, incorrectly retaining SR-only flags such as low-resolution motion-vector state.

Fix: set `DLSS.Feature.Create.Flags = (source & 1) | depth_inverted_bit` for Feature 18.

### 4. Other copied parameter differences

Community code explicitly sets:

- `PerfQualityValue = 0`
- `CreationNodeMask = 1`
- `VisibilityNodeMask = 1`
- motion/depth subrect bases copied from the game
- callback scale follows the actual `NREnableUpscaling` value

The owned service previously inherited SR quality, zeroed all guide bases, and hard-coded its scaling callback to 0.5.

Fix: copy/set the same values and make the callback return 1.0 in native mode.

### 5. The owned service shares the game's SR parameter object

The community add-on allocates a separate NR parameter object. The owned ABI currently receives the game's SR object, so generic NR setup must not remain in it. The first corrected live run exposed this directly: the router saw `PerfQualityValue` change from 2 to 0 and flags from `0x4b` to `0x09` on following SR frames.

Fix: save and restore `PerfQualityValue`, `DLSS.Feature.Create.Flags`, `CreationNodeMask`, and `VisibilityNodeMask` immediately around Feature 18. DLSSNR-prefixed keys may remain because SR does not consume them.

## Live validation

Built service SHA-256:

- `6e1621581aa2a1a81b422a5870c07ed326a32299d4c1b2a098a1c8af42d29210`

The game was restarted after deployment. The live contract was:

- source flags `0x4b`, Feature 18 flags `0x09`
- create input `4096x2304`, create compatibility enabled
- evaluation input/guides `4099x2306`, scale `1.0`, upscaling off
- codec HDR mode on
- original SR `PerfQualityValue` remained `2` for all observed frames
- Feature 18 returned `0x00000001` continuously; no Xid was observed

At the archive point, 3,055 router evaluations succeeded and the bridge had logged at least 3,000 Feature 18 frames. The user confirmed that DLSS5 was visibly enabled and no flicker remained, including the previously severe bright-light behavior.

## Game update boundary

The update encountered during validation was a hot-content update under `Client/Saved/Resources/3.6.0/.../3.6.13` (launcher/resource PAKs). It did not replace the August 20 executable, DLSS/RR DLLs, Streamline DLLs, router, service, or `nvngx_dlssnr.dll`. After the update the router still resolved all SR/RR NGX entry points, and dimensions/formats/flags remained compatible. It may change scene content but did not change this integration ABI.
