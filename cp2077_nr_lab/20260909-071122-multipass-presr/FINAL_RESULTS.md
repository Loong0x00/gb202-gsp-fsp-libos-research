# Actual Cyberpunk2077 multipass and Pre-SR reproduction — results

Both independently developed branches have completed controlled real-game tests.
The host remains ReShade plus owned router/service, with community algorithm/ABI
reference; a complete OptiScaler/RenoDX plug-in package was not deployed.

## Common configuration

Cyberpunk2.31, RTX5090/610.57.04, GE-Proton10-34.6144x3456 output, ordinary DLSS
SR Quality (actual rendering/input4096x2304), path tracing ON, RR OFF, FG OFF,
dynamic resolution OFF. Existing NR controls: preset/style0, intensity/tone/
structure1, skin-1, AutoMask/UI correction OFF, HDR luminance composition with
paper-white/transfer1 and color-strength0.

All numbers are first-run comparisons, not repeated statistical estimates.
Three bounded X11 window screenshots were taken in each case. They may perturb
pacing; clean `--no-images` repeats are still appropriate before fine performance
claims. GPU NR statistics use valid whole-run timestamp samples after the first
8 invocations, not CPU recording duration or MFG output FPS. Inter-pass barriers
are inside the measured NR intervals. Create/setup is excluded from the means.

| Case | Official benchmark averageFPS | NR GPU mean | Peak GPU memory MiB |
|---|---:|---:|---:|
| baseline-sr-quality-nr-off | 25.16 | — | 21892 |
| existing-owned-onepass | 16.99 | — | 24589 |
| multipass-1 | 17.08 | 17.06 ms | 24358 |
| multipass-2 | 12.86 | 34.11 ms | 26654 |
| multipass-3 | 10.49 | 51.53 ms | 29108 |
| presr-transport | 25.21 | — | 21736 |
| presr-codec | 25.26 | — | 21971 |
| presr-nr | 20.71 | 7.59 ms | 23029 |

## Multipass: actual execution

The same c220fdc6... artifact was cold-launched at1/2/3 passes. One-pass performance
matches the previously installed one-pass service within this run's variation.
Two/three layers create independent persistent Feature18 handles on separate
build-only invocations, then evaluate every layer before one final composition.
The three-pass trace shows creates[1,1,1] and successful evaluations for all three;
GPU-timing evidence alone reaches1064 recorded evaluations per layer. Timing uses
a120-invocation readback lag, so the final queued samples are not all drained at
benchmark termination; do not mistake that last CSV count for the entire run.

Three-pass mean GPU intervals:16.952/17.098/17.480ms, total51.530ms. Work and
composition surfaces are6144x3456; current compatibility creation advertises
4096x2304 only during Create. These are distinct facts: the runtime's private
internal tensor dimensions were not inspected and are not asserted from that
compatibility value.

## Pre-SR: actual ordering and diagnostics

- Transport-only:1929 signedSR calls succeeded with current Color bound/restored;
  no NR evaluations and no post pass. Fresh compact4096x2304 input was used.
- Codec-only: full benchmark succeeded, no Feature18 evaluations. Its legacy
  CSV `feature18_ms` field measures a GPU copy (~0.03ms), NOT inference.
- RealNR: one CreateFeature, one deliberately unbound creation/submission frame,
  then1600 successful NR evaluations and1600 matching Color binds/restores.
  All1601 originalSR calls succeeded. Post mode remained0 throughout.
- RealNR input/work4096x2304 → original signedSR output6144x3456.
  NR mean7.588ms, median7.580ms, p957.785ms. Lower pixel count is the source of
  the cheaper work; this does not prove equal image quality to post-SR NR.
- A concrete old-prototype ABI bug was corrected using the community's verified
  MSVC boundary: resource Set(Color) is vtable slot1, not slot6 (float Set).
  Runtime pointer readback now verifies binding/restoration. This is a verified
  defect in the old approach, not proof it was the sole prior visual-failure cause.

## Image evidence and limits

Every case has three1920-wide window JPEGs. The three-pass15s capture is black
and is NOT counted as positive scene evidence; its precise loading/capture cause
was not isolated. The35s/55s three-pass samples show actual rendered benchmark
scenes, as do the checked transport/codec/PreSR samples. No claim of universally
clean output is made from these few images. Cameras/NPCs are NOT frame-aligned
between runs. X11 captures
also contain horizontal tearing in the NR-off baseline as well as modified
cases, so those seams cannot be attributed to NR. They are not suitable for
pixelwise quality scoring or claiming multi-pass looks better. No claim of
long-term temporal stability or official6K support is made.

A useful next experiment is combining low-resolution Pre-SR with2/3 passes, but
that combined route was NOT implemented/tested here. These remain two separately
validated candidates as requested.

## Cleanup / preservation

All8 cases completed and restored their pre-run router, service, UserSettings,
ReShade settings, D5LC controls/status, and prior runtime logs after game exit.
Pre-SR test markers were removed/restored to their original presence. Final
production owned-file and signed/loader DLL hashes match the initial baseline.
No new kernel NVRM/Xid event was found in any case. No raw capture, clock/power
adjustment, campaign save, account, Minecraft/WuWa/HSR modification was performed.
The harness never invokes a global wineserver kill; systemd may reap a remaining
Wine server created inside that test's own cgroup after the owned game exits.

Production still has the original4db56af3... router and8f7a9847... one-pass service
and original6K/DLAA settings. Experimental binaries are not left installed.

Candidates:

- Multipass: `multipass/service/build/multipass/01-dlss5-post-service.addon64`
  SHA256 `c220fdc6359a3c3da3e512ed0e4a6b01856de757bac0613d92bd1e22d3d38912`.
- PreSR router: `presr/copies/presr-single-pass/00-dlss-ngx-router.addon64`
  SHA256 `763ad8b698376656cc03f829398cd20c2a9d9e9c856a3a12b64222af5f791f1e`.
- PreSR service: `presr/copies/presr-single-pass/01-dlss5-presr-service.addon64`
  SHA256 `bfc4e5db018308b28f4eeffb148a367d4c8620788d36111474d15d329832a37b`.

See branch docs for exact source attribution and ABI, `RESULTS.json` for counters,
statistics and restoration records, and each `runs/*` for original evidence.
