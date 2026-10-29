# Cyberpunk 2077 owned DLSS5 route

Installed: 2026-09-03

## Active route

- `00-dlss-ngx-router.addon64`
  - SHA-256 `4db56af38c03ca903f01b556ad89f3effa5c7d36e846fd4ac430c6c77b53f692`
- `01-dlss5-post-service.addon64`
  - SHA-256 `6e1621581aa2a1a81b422a5870c07ed326a32299d4c1b2a098a1c8af42d29210`
- signed `nvngx_dlssnr.dll`
  - SHA-256 `e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e`

The previous `renodx-dlss5.addon64` resource owner and its old
`00-dlss5-vk-bridge.addon64` companion are no longer in the active add-on
directory. They remain in the rollback backup.

No NVIDIA DLSS, DLSSD, DLSSG, DLSSNR or Streamline DLL was replaced.

## Runtime validation

Official Cyberpunk benchmark:

- game 2.31;
- 6144×3456, path tracing, DLAA, frame generation off;
- 972 benchmark frames;
- 9.6879 FPS, 100.3318 seconds;
- mean whole-device VRAM 29480.5 MiB;
- router intercepted 1187 SR Evaluate calls from process startup through exit;
- original signed SR result: 1187/1187 success;
- owned post-service result: 1187/1187 success;
- one successful Feature 18 model creation;
- no owned post-service failure receipt;
- no Xid, NVRM assertion, `gpu_vaspace` or `intermap` kernel event.

Evidence:

`/home/user/rt_5090_project/benchmark_logs/cp2077-owned-route-smoke-20260903-031648/`

This post-service runs after the original signed DLSS reconstruction. It does
not replace or alter the original Evaluate return value. Removing the enable
marker returns to native DLSS only.

## Controls

- Disable owned Feature 18: `.dlss5-owned/disable.sh`
- Re-enable it: `.dlss5-owned/enable.sh`
- Restore the complete previous community route:
  `.dlss5-owned/restore-previous-route.sh`

The universal DLSS5 controller can also write the post-service D5LC control
block. The route marker must remain present for the router to invoke it.
