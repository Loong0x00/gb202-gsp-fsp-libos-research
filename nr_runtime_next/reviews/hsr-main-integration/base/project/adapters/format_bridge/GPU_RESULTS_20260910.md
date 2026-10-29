# MAIN GPU verification — 2026-09-10

This tests real D3D12 conversion shaders on RTX 5090, **not Feature 18 or either
game**. NR results passed to commit are explicitly SIMULATED. Synthetic HSR
view 37/21 and shared-copy flags do not attest the actual game's SRVs/interop.

## Retained final run

`../../tests/format_gpu/runs/20260910-074055-validation-offscreen-no-wsi/`

- Exact adapter: NVIDIA RTX 5090, vendor 10de/device 2b85.
- GE-Proton10-34 in a test-only prefix; explicit native DXGI/D3D12 overrides.
- Offscreen owned queue/resources; no window/swapchain, NGX, game, host capability
  publication, game/profile/Guardian edits, or hardware setting changes.
- Seven actual GPU data cases passed (`data_pass:true`).
- R11 -> RGBA16F -> R11 noop conversion bit-exact for the finite fixtures.
- Modified commit updates only the selected rotating target; CREATE_PENDING
  leaves both game-like targets unchanged; double commit is rejected.
- WuWa Color/MV/depth subrect origins and metadata are preserved; finite outputs.
- HSR SNORM endpoint decoding and half quantization pass; tested fixture maximum
  error after correction: 0.000030517578125. This is not an exhaustive GPU sweep.
- HSR depth readback is exactly 0.375; stencil value 9 is not included.
- Real queue Signal, bounded wait, completed fence, readback and pool retirement
  were exercised. UINT64_MAX is explicitly rejected by the harness.
- Vulkan layer log confirms Core Checks, Synchronization, object lifetime,
  thread safety and handle wrapping enabled; no warning/error in the final log.

**Important:** D3D12GetDebugInterface returns 0x887a002d. Microsoft D3D12 debug
layer/info queue validation remains unavailable. The harness intentionally
retains overall `pass:false` / exit 1 for that limitation despite `data_pass:true`.
Do not relabel it as a clean D3D12-debug-layer test. Vulkan validation is separate.

## Real rounding correction

The initial native-DXGI GPU run at `20260910-073428-native-dxgi` passed all WuWa
cases but failed HSR MV quantization: direct SNORM -> float -> typed RGBA16F UAV
store had max fixture error 0.000457763671875, exceeding the CPU nearest-half
bound 0.000244140625. It was consistent with truncating storage conversion.

The shader now explicitly computes `f16tof32(f32tof16(motion))` before storage.
All seven GPU data cases pass afterward. CPU exhaustive SNORM reference remains
max 0.000244140625; finite R11 and already-half WuWa guides are unchanged. This
correction is in `shaders/normalize.hlsl` and regenerated embedded HLSL/DXBC;
consumers must relink the updated static library.

## Environment failures retained, not hidden

- First `proton run` attempts lost console output through the Steam wrapper.
  Direct `proton runinprefix` exposes the harness output.
- Without native DXGI override, the old Wine builtin adapter reported GTX 470
  device 06cd and was correctly rejected; it was not accepted as a 5090 run.
- Native override `dxgi,d3d12,d3d12core=n,b` plus `dxgi.hideNvidiaGpu=False`
  restores the actual adapter identity; no fake device ID is supplied.
- The first Vulkan-validation run (`073951`) had two instance-extension errors
  from the Gamescope WSI layer injecting surface extensions into an offscreen
  instance without VK_KHR_surface. The final offscreen-only harness sets
  DISABLE_GAMESCOPE_WSI=1 **inside its child wrapper**, while still using the
  isolated Gamescope X server. It does not change CP game tests or global settings.

Readbacks and hashes are in JSONL; build SHA256SUMS, command wrapper, layer settings,
validation log and exit code are retained per run. No real-game raw capture was
introduced. Remaining game acceptance requires actual view/phase/transport and
native submission/commit integration.
