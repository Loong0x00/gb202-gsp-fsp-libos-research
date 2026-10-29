# Clean native host + Feature 18 runtime candidate

This directory builds a standalone x86-64 Windows/Wine production candidate. It does not import, discover, register with, or export any ReShade or RenoDX API. It does not replace an NVIDIA DLL.

## Exact basenames

The owned files are:

```text
dxgi.dll                       boot proxy
dlss5-native-host.dll          NGX/order/queue host
dlss5-native-runtime.dll       Vulkan-interoperable Feature 18 runtime
```

`dxgi.dll` forwards the six exports present in the audited Wine/Proton DXGI (`CreateDXGIFactory`, `CreateDXGIFactory1`, `CreateDXGIFactory2`, `DXGID3D10CreateDevice`, `DXGID3D10RegisterLayers`, and `DXGIGetDebugInterface1`) to the actual system32 DXGI. Its first API call loads the two owned DLLs outside `DllMain`. It never uses an NVIDIA basename. The signed `nvngx_dlssnr.dll`, signed SR/RR feature DLLs, NGX core, `winevulkan.dll`, and vkd3d-proton remain external, unchanged prerequisites.

## One production chain

The cold-latched D5RP request selects exactly one chain:

- `post`: original signed SR **or** RR is evaluated once, then N independent Feature 18 histories run.
- `pre_sr`: N independent Feature 18 histories run, then the original ordinary Feature 1 SR history is evaluated once.

There is no shadow SR, order-comparison branch, shared temporal handle loop, or hidden RR fallback. `RR + pre_sr` is `unsupported` and bypasses NR.

For N=1..10, the runtime allocates N core parameter maps and invokes signed Feature 18 Create once for each distinct handle. The same-frame current HDR Color is encoded once. Neural outputs move through two raw RGBA16F ping-pong surfaces; the final neural result is composed back to HDR exactly once. Motion/depth active subrects are copied bit-preservingly into owned origin-zero padded resources. PRE returns an owned compact Color to the same signed SR call; POST composes into the successful signed reconstruction output.

Before any chain resource or Feature 18 handle allocation, `IDXGIAdapter3::QueryVideoMemoryInfo` must succeed and cover the complete estimate plus reserve. Ten is the implementation syntax maximum, not a hardware-fit promise.

## Native submission and lifetime proof

The host forwards the real `D3D12CreateDevice` result and returns the same COM pointer. It patches native vtable methods in place (no wrapper identity):

- `ID3D12Device::CreateCommandQueue` / `CreateCommandList`;
- `ID3D12GraphicsCommandList::Reset` / `IUnknown::Release`;
- `ID3D12CommandQueue::ExecuteCommandLists` / `IUnknown::Release`.

`ExecuteCommandLists` is called first. Only after that real forward returns does the host acknowledge exact-list work and enqueue `Signal` on that same queue. Feature 18 Create remains pending until this post-forward acknowledgement. Reset/Release before submission invalidates the recorded work. Owned handles, parameter maps, image views, resources, and fence references retire only on the background worker after the matching fence completes. `DllMain` performs no DLL load, NGX/Vulkan initialization, COM wait, shader work, disk I/O, or teardown.

The game's signed Create/Evaluate/Release return values are preserved. NGX feature ownership is matched by the DWORD handle ID (the locally proven signed-SR boundary reads the ID, while NGX may copy the handle payload), not by Create-return pointer identity. Unrelated signed-module exports and unrelated feature calls are forwarded to their originating SR/RR module.

## Controls and telemetry

The host consumes frozen `protocol/PIPELINE_V1.md` / `pipeline_v1.h` without changing them and implements unchanged packed D5LC v1 (72 bytes):

- missing D5RP defaults to `post/1`;
- order/pass count are process-latched; a later difference reports `pending_restart` while effective values remain unchanged;
- invalid/partial/checksum-bad blocks are ignored atomically;
- D5LC `neural_uplift=0` is pass-through;
- `0 -> 1` increments a reset generation applied independently to every layer;
- `enable_upscaling=1` is currently an explicit unsupported guard, not silently ignored.

A 50 ms background poller writes D5LC receipt and D5RP JSON status atomically. `active` is impossible until all real Feature 18 calls and final compose succeeded, PRE signed-SR commit/parameter restoration succeeded, and native `ExecuteCommandLists` was forwarded followed by a successful same-queue fence signal. A D5LC receipt is never treated as a D5RP/order acknowledgement.

`pipeline-capabilities.json` is written only after the production runtime has actually initialized signed NR against a real vkd3d interop device, NGX routing is installed, and native device/queue hooks have been observed. The fake test runtime cannot produce it.

## Build and CPU/Wine checks

```bash
make -C native clean check package
(cd native/package && sha256sum -c SHA256SUMS)
(cd native && python3 tools/source_manifest.py | diff - package/SOURCE_SHA256SUMS)
```

The checks compile both PE DLLs, validate D5RP/D5LC and policy paths, verify independent layer identities/counters, one-compose order, parameter restoration, reset-before-submit rejection, PE exports, source isolation, actual Wine DXGI forwarding, owned loader behavior, and fake-runtime non-advertisement. They do not start a game or submit D3D12 GPU work.

## Acceptance boundary

No game deployment or GPU launch was performed for this delivery. The package is therefore a **production candidate**, not GPU-accepted production. The main owner must perform the first cold CP2077 Create/Evaluate test and preserve logs/status before any deployment decision. In particular, that test must confirm CP's actual D3D12 creation path reaches the base-interface hooks, all requested distinct Feature 18 handles create, native execute acknowledgements arrive, and a fresh status becomes `active`. See `docs/HANDOFF.md`.
