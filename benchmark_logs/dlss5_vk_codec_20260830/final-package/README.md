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
