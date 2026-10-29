# Cyberpunk 2077 true NR-before-SR handoff

## Scope and ordering

This candidate is a new owned-router seam, not the old `DLSS5_PRE_SR=1`
prototype. The router intercepts the real `nvngx_dlss.dll` Feature 1 evaluate,
calls the versioned `DLSS5_PreEvaluateV2` service **before** the signed SR call,
binds only a successfully produced current-frame Color through the verified
MSVC overload slot 1, calls signed SR, then restores the original Color even
when signed SR returns failure. (The old local prototype's slot 6 was the float
overload, not a resource setter.) The service
uses its own NGX parameter object, so it never rewrites the game's Width,
OutWidth, flags, jitter, guide, or output parameters.

The SR output and its dimensions are never replaced. A 4096x2304 NR input can
therefore still feed the game's requested 6144x3456 signed-SR output. No image
is mapped or transferred to the CPU. The optional timing readback contains only
GPU timestamp query values.

The service stages `Width` x `Height` live pixels out of Color on every eligible
evaluate and returns that staging resource to NPSR before use. This matters for
the observed CP2077 6K Quality contract: after the initial 6K probe, `Width` and
`Height` become 4096x2304 while the reused Color/Depth/MV allocations and stale
`DLSS.Render.Subrect.Dimensions` can remain 6144x3456. Reading either as the current picture would include inactive
pixels, so the service does not do that. Color must have an origin-zero active
rectangle; nonzero Color
origin, out-of-bounds Color/Depth/MV subrects, a non-direct list, unsupported
format/layout, DLAA-sized input, or missing metadata all retain original SR.
Guide subrect bases are read and passed independently.

All three input states arrive and leave as
`D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE`. Scratch states are tracked as
NPSR/COPY_DEST, UAV/NPSR, and restored around Vulkan interop. Feature 18 is
created on a build-only frame and is not evaluated until ReShade API 18 reports
that creation command list executed. A reset/destroy before submission disables
the service rather than consuming an uncreated history.

## Community source references

Implementation decisions were checked directly against:

- `matiasLombo/neural-upstream` commit
  `c06c07b27c3c5af0d916c3d9545434735d624bdf`,
  `src/addon.cpp`: current Color/Depth/MVec are read before original evaluate;
  processed Color is bound for original DLSS and immediately restored. Its HDR
  codec develops the scene-linear input and composes the model result by
  luminance gain rather than forwarding raw neural RGB.
- `wilsjo2/OptiScaler-DLSSNR-PreSR-Multipass` commit
  `ec96f42f8d32a4fc82f7c4558c0ed12a9f90d853`,
  `OptiScaler/shaders/dlssnr/DlssNr_Dx12.cpp`: padded origin-zero active Color is
  copied to a compact resource, and RR is explicitly forced away from the
  pre-SR path.
- Local audit `benchmark_logs/dlss5-presr-static-20260908/README.md` (outside
  this isolated branch). It records the same source findings and the old
  2026-08-31 failure: codec-only and D3D12-copy prototypes showed repeated/stale
  regions. This candidate does **not** enable that old hook or copy decoded
  pixels back in-place; it substitutes a freshly written compact resource at
  the owned signed-SR boundary.

The branch codec shaders retain the referenced soft shoulder/sRGB conversion
and `upgrade_tonemap` luminance composition in `service/codec_encode.comp` and
`service/codec_decode.comp`.

## Build and local checks

From this branch root:

```bash
make -C router clean all
make -C service presr
make -C tests clean check

x86_64-w64-mingw32-objdump -p \
  service/build/presr/01-dlss5-presr-service.addon64 \
  | sed -n '/Export Table/,+35p'
sha256sum router/build/presr/dlss-ngx-router.addon64 \
  service/build/presr/01-dlss5-presr-service.addon64
```

The service export table must contain `DLSS5_PreEvaluateV2` and
`DLSS5_PreReleaseV2`, and must not contain `DLSS5_PostEvaluate`.

## Benchmark modes

Markers live in `.dlss-ngx-router` beside the add-ons. Stop the game and follow
the main worker's backup/hash process before copying either DLL. Do not use the
old `DLSS5_PRE_SR` environment variable.

Use only one diagnostic marker at a time (transport wins if both exist):

```bash
# Common pre-SR enable. The router suppresses enable-dlss5/post-NR regardless,
# but remove it so the test intent is unambiguous.
rm -f .dlss-ngx-router/enable-dlss5
: > .dlss-ngx-router/enable-dlss5-presr

# A: current Color -> compact D3D12 staging -> signed SR (no Vulkan/codec/NR)
: > .dlss-ngx-router/dlss5-presr-transport-only
rm -f .dlss-ngx-router/dlss5-presr-codec-only

# B: current Color -> HDR codec round trip -> signed SR (no Feature 18 evaluate)
rm -f .dlss-ngx-router/dlss5-presr-transport-only
: > .dlss-ngx-router/dlss5-presr-codec-only

# C: one Feature 18 pass at actual low input resolution -> signed SR
rm -f .dlss-ngx-router/dlss5-presr-transport-only \
      .dlss-ngx-router/dlss5-presr-codec-only
```

For a clean disable:

```bash
rm -f .dlss-ngx-router/enable-dlss5-presr \
      .dlss-ngx-router/dlss5-presr-transport-only \
      .dlss-ngx-router/dlss5-presr-codec-only
```

Main should use ordinary DLSS SR with RR disabled. If Feature 13/RR was created
in the process, the conservative RR latch prevents pre-SR even if an auxiliary
Feature 1 evaluate appears later; restart after changing RR/SR modes.

## Evidence gates

Expected `dlss-ngx-router.jsonl`/`dlss-ngx-frames.jsonl` facts for full mode:

- `create.begin` says role `sr`, feature `1`.
- `dlss5.presr.service` says ABI `131072` (`0x00020000`).
- service log says active/NR input 4096x2304 (or the configured low input), and
  signed-SR output 6144x3456.
- one `router pre-SR CreateFeature` line is followed by build-only fallback;
  later `router pre-SR Evaluate` counters increase once per serviced evaluate.
- router completion has `presr_bound=1`, `presr_restored=1`, and
  `effective_dlss5_mode=0`/`post_called=0`.
- `role=rr` or Feature 13 has `presr_called=0` and preserves the signed result.

Any invalid contract, service/create/evaluate/interop failure, missing current
output, or unverified parameter bind yields `presr_bound=0`; signed SR is still
called and its exact return value is returned. There is no cached-output or
cadence fallback.

`dlss5-gpu-timing.csv` is generated by the timing-enabled service. Use its
`feature18_ms` column for model cost and discard the Feature-create row. The
router's legacy `cpu_record_us` measures CPU recording around the whole route;
it is not NR GPU time and must not be reported as such.

## Artifacts

Benchmark-ready copies are under `copies/presr-single-pass/`:

```text
763ad8b698376656cc03f829398cd20c2a9d9e9c856a3a12b64222af5f791f1e  00-dlss-ngx-router.addon64
bfc4e5db018308b28f4eeffb148a367d4c8620788d36111474d15d329832a37b  01-dlss5-presr-service.addon64
```

`SHA256SUMS` there is generated from the final MinGW build. The package
intentionally contains only the router, the pre-SR service, a manifest, and no
signed NVIDIA DLL, game file, prefix, or configuration.
