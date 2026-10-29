# DLSS5 Vulkan bridge for vkd3d-proton

This experimental ReShade companion add-on leaves `renodx-dlss5.addon64` in
charge of capture and parameters, but replaces the signed runtime's D3D12
Feature 18 calls with its Vulkan API on the same vkd3d command list and images.
It also recreates the add-on's captured encode/decode shaders as native Vulkan
compute passes and skips the D3D12 post-codec path that renders incorrectly
under Wine.

The RVA patch is intentionally restricted to the observed add-on build:

- SHA-256: `87aef9ddd937c7241e6bf8d8efea0045d63559135e254c60dab316db3d3a4aee`
- PE timestamp: `0x6a90d4a4`
- image size: `0x67000`

Build with `make`, then place `00-dlss5-vk-bridge.addon64` beside the target
add-on and ReShade proxy. No external NGX SDK checkout is needed. The runtime
log is `dlss5-vk-bridge.log` beside the game executable. The direct path is the
default; set `DLSS5_VK_BRIDGE_DIRECT_OUTPUT=0` only to fall back to the target
add-on's original D3D12 path. The Wine launch must use native DXGI/D3D12/NVAPI/
NGX DLLs and vkd3d-proton's command-list interop (tested with GE-Proton10-34).

Validated configuration on 2026-08-30: Cyberpunk 2077 2.31, 6144x3456 DLAA,
path tracing, RTX 5090, driver 610.57. The fixed run completed 972 frames at
9.223 FPS versus 10.940 FPS with Neural Uplift disabled. Peak VRAM was
31,538 MiB versus 29,200 MiB.

## Owned Cyberpunk post-service route

The active Cyberpunk deployment was migrated on 2026-09-03 from the community
resource owner plus companion bridge to the same owned topology used by the
Wuthering Waves integration:

```text
signed DLSS SR/RR Evaluate
    -> 00-dlss-ngx-router.addon64
    -> 01-dlss5-post-service.addon64
    -> signed nvngx_dlssnr.dll Feature 18 through Vulkan
    -> decode directly into the game Output
```

`renodx-dlss5.addon64` and the old `00-dlss5-vk-bridge.addon64` are absent from
the active directory. NVIDIA and Streamline DLLs remain untouched. The router
runs the owned service only after the original signed reconstruction succeeds
and always preserves the original Evaluate return value.

Active hashes:

- router: `4db56af38c03ca903f01b556ad89f3effa5c7d36e846fd4ac430c6c77b53f692`
- service: `8f7a9847598b163910344b06ad2fd5ce045d913e51b7bd9b2a60046cb1c6acbe`
- signed DLSSNR: `e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e`

The final 6144x3456 path-traced benchmark completed 973 frames at 9.633 FPS.
The router recorded 1187/1187 successful original and owned post-service calls,
one successful Feature 18 creation, exact 72-byte D5LC status readback, and no
Xid/NVRM event. Evidence and rollback paths are documented in
`../benchmark_logs/cp2077-owned-route-d5lc-current-20260903-032547/DEPLOYMENT.md`.

## Replace DLAA with Feature 18

Set `DLSS5_REPLACE_DLAA=1` while the game is configured for DLAA to skip the
original Feature SR evaluation and run Feature 18 as the sole neural pass:

```text
game full-resolution Color + MVec + Depth
    -> copy raw Color into the game's existing Output
    -> target codec encode
    -> Feature 18
    -> target codec decode into the same game Output
```

This is an adapter, not a DLL swap: Feature SR and Feature 18 have different
feature IDs and parameter contracts. The bridge only replaces DLAA when the
Color, render subrect, and Output extents and formats match; otherwise it logs
the refusal and calls the original DLAA path.

Validated on 2026-08-31 with the same 6144x3456/path-traced configuration. The
replacement completed 972 frames with visually correct output at 9.780 FPS,
versus 9.223 FPS for DLAA followed by Feature 18 and 10.940 FPS for DLAA alone.
Those historical, non-paired runs reported average VRAM of 29,420 MiB, 30,973
MiB, and 28,524 MiB respectively. A stricter six-run paired rerun on 2026-09-03
did **not** reproduce the apparent 1.55 GiB replacement saving: two-run means
were 29,454 MiB for replacement and 29,537 MiB for the dual chain, only 83 MiB
apart and within residency variation. Skipping DLAA Evaluate saved a repeatable
1.72 ms but did not release the already-created DLAA feature resources. Treat
the old VRAM difference as an uncontrolled cross-run observation, not an
attributable saving. Full evidence is in
`../benchmark_logs/cp2077-dlss5-vram-ab-20260903-025400/README.md`.

The 6K compatibility path still runs the Feature 18 network at 4096x2304 and
decodes into the 6144x3456 game Output.

## Experimental pre-SR mode

Set `DLSS5_PRE_SR=1` to move Feature 18 in front of DLSS Super Resolution:

```text
game low-resolution Color + MVec + Depth
    -> DLSSNR at the game's render subrect
    -> replace DLSS SR Color with the neural result
    -> original DLSS SR output
```

This mode is off by default. It creates low-resolution codec proxy, neural,
and decoded `R16G16B16A16_FLOAT` resources, owns a separate Vulkan Feature 18
history, and replaces the target add-on's full-resolution post-SR feature with
an inert sentinel. The normal post-SR model and its large working set therefore
do not run a second time.

The first prototype deliberately accepts only a fixed render subrect and an
`R16G16B16A16_FLOAT` game Color resource. Dynamic-resolution changes or a
different Color format fall back to unmodified DLSS SR for that process and
are logged. UI correction is disabled at this point because the game UI has
not yet been composited. No visual or performance claim is made until a game
A/B confirms the pre-SR color domain, depth convention, motion-vector scale,
output correctness, frame time, and VRAM delta. The 2026-08-31 Cyberpunk test
failed that gate: both the full codec+Feature 18 path and codec-only/D3D12-copy
diagnostics produced repeated/stale screen regions. Do not use this mode for
gameplay; use `DLSS5_REPLACE_DLAA=1` instead.
