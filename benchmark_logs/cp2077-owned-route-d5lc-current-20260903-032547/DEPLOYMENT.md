# Cyberpunk 2077 owned DLSS5 route

Installed and validated: 2026-09-03

## Active route

- `00-dlss-ngx-router.addon64`
  - SHA-256 `4db56af38c03ca903f01b556ad89f3effa5c7d36e846fd4ac430c6c77b53f692`
- `01-dlss5-post-service.addon64`
  - SHA-256 `8f7a9847598b163910344b06ad2fd5ce045d913e51b7bd9b2a60046cb1c6acbe`
- signed `nvngx_dlssnr.dll`
  - SHA-256 `e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e`

The active post-service was built from
`/home/user/rt_5090_project/dlss5_vk_bridge/dlss5_vk_bridge.cpp` at source
SHA-256 `93154cea2faf8acf2675ce2d4bd7733c9aeabbceb70faa27daf80b8d45c68cc8`.
It adds the current 72-byte D5LC control/readback implementation to the already
validated post-service path.

The previous `renodx-dlss5.addon64` resource owner and old
`00-dlss5-vk-bridge.addon64` companion are no longer in the active add-on
directory. They remain in the rollback backup.

No NVIDIA DLSS, DLSSD, DLSSG, DLSSNR or Streamline DLL was replaced.

## Final runtime validation

Official Cyberpunk benchmark:

- game 2.31;
- 6144×3456, path tracing, DLAA, frame generation off;
- 973 benchmark frames;
- 9.6330 FPS, 101.0071 seconds;
- mean whole-device VRAM 29566.5 MiB;
- router intercepted 1187 SR Evaluate calls from process startup through exit;
- original signed SR result: 1187/1187 success;
- owned post-service result: 1187/1187 success;
- one successful Feature 18 model creation;
- no owned post-service failure receipt;
- D5LC `live-status.bin` exactly matches the 72-byte `live-control.bin`,
  including sequence `1788376925184894286` and enabled state;
- no Xid, NVRM assertion, `gpu_vaspace` or `intermap` kernel event.

Evidence:

`/home/user/rt_5090_project/benchmark_logs/cp2077-owned-route-d5lc-current-20260903-032547/`

Two preceding migration runs using the earlier `6e162...` service also
completed with all Feature 18 calls successful. That older build predates D5LC
status support, so it was replaced only after the current build passed the same
benchmark and returned an exact control receipt.

The post-service runs only after the original signed DLSS reconstruction has
succeeded. Its result cannot replace or alter the original Evaluate return
value. Removing the route marker returns to native DLSS only.

## Controller and controls

The universal-controller Cyberpunk profile is now `DLSS5 Post Service` and
`control_only=true`, preventing it from reinstalling the previous community
components. The controller reports `已连接并启用` with exact D5LC readback.
Its test suite passes: `15 passed`.

Manual controls, all refusing changes while the game is running:

- Disable owned Feature 18: `.dlss5-owned/disable.sh`
- Re-enable it: `.dlss5-owned/enable.sh`
- Restore the complete previous community route and controller profile:
  `.dlss5-owned/restore-previous-route.sh`
- Restore only the earlier owned service build:
  `.dlss5-owned/backups/20260903-032541-before-d5lc-service/restore.sh`

Current state is enabled. Configuration hashes remained unchanged after the
benchmarks:

- `ReShade.ini`: `79350b08d5ee796081bc91f434c92b0865b40add3611e57690c411bbfdc7a7c6`
- `UserSettings.json`: `82f3a8aa38aece353486e5b8ab674c0671b0d11edb97eb0d902056d2cd0aad57`
- `/etc/lact/config.yaml`: `cc3940dd896843bbb975502ee718d3ec1f762f5a1d8d12a4ae32c3d61459a7d9`
