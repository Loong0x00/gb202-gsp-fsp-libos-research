# NR-before-SR static source audit (2026-09-08)

No game deployment/configuration changes; no DLL execution or GPU benchmark.

## Confirmed true upstream processing

1. https://github.com/matiasLombo/neural-upstream
   Inspected commit c06c07b27c3c5af0d916c3d9545434735d624bdf.
   src/addon.cpp eval_body reads the game's Color/Depth/MotionVectors before
   the original NGX evaluate. Around lines 1347–1364 it encodes Color and calls
   g_snip_eval; around 1456–1472 it binds the processed feed as Color, calls
   t_orig_eval, then restores the original Color parameter. Thus its low-resolution
   route is genuinely NR -> SR, not SR -> downsample -> NR -> resize.
   HDR output is composed through a luminance-gain transfer; it is not simply
   handing raw neural RGB unchanged to the upscaler.
   README reports testing GTA V Enhanced and Bright Memory Infinite; GPU-timestamp
   network cost ~3.27 ms at 1280x720 on RTX 4070 Ti is author-reported, not our measurement.
   Cadence skipping and delta reuse are separate experiments; README documents
   flashes/stutter with FG and recommends every-frame Quality cadence.

2. https://github.com/Dagherbou/OptiScaler_DLSSNR/pull/6
   sadbee166's RunBeforeSR change adds EvaluateBeforeUpscale immediately before
   native/upscaler evaluation. Full diff preserved beside this report.
   PR-reported limits include loss of fine detail, tone/lighting changes, and
   incompatibility with Ray Reconstruction's input contract.

3. https://github.com/wilsjo2/OptiScaler-DLSSNR-PreSR-Multipass
   Inspected commit ec96f42f8d32a4fc82f7c4558c0ed12a9f90d853.
   Adds persistent per-pass histories, padded-origin-zero active Color staging,
   and optional multipass. In shaders/dlssnr/DlssNr_Dx12.cpp around 2952–3052,
   forcePost explicitly excludes RR from pre-SR processing. RR instead uses
   ApplyAfterRR and independent RRWorkingScale/RRPasses controls.
   Unsupported/nonzero-offset active layouts retain post-SR fallback.

## Relevance to current WuWa experiment

Our last observed chain was signed RR (including upscaling) -> NR, not independent
RR -> separate SR -> NR. Moving NR in front of that combined RR call would put it
on noisy pre-RR inputs and break the matching G-buffer/radiance contract. The
community pre-SR result does not validate this modification.

For a separate ordinary-SR experiment, NR could run at render size and SR alone
produce 6K. With the last observed render size 3564x2005, that is ~33.7% of the
6144x3456 output pixel count. This is not an FPS prediction, equivalent-image
claim, proof of official support for the modified pipeline, or a fix for the
new intermittent sky/character-disappearance flicker.
