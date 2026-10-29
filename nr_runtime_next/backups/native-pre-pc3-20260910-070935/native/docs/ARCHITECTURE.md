# Native architecture and safety invariants

## Modules

| Module | Responsibility |
|---|---|
| `boot/dxgi_proxy.cpp` | system32 DXGI forwarding and loader-lock-free bootstrap |
| `host/loader.cpp` | owned IAT routing for `D3D12CreateDevice` and NGX core `GetProcAddress` |
| `host/queue_hooks.cpp` | identity-preserving native COM vtable hooks, exact-list reset/execute/release, post-forward fences |
| `host/pipeline.cpp` | signed SR/RR routing, DWORD handle identity, one-chain order, feature-map transaction restoration, adapter ingress |
| `host/telemetry.cpp` | D5LC/D5RP polling, atomic receipts/capabilities/status heartbeat |
| `runtime/interop.cpp` | direct vkd3d `ID3D12DXVKInteropDevice1` query, unchanged signed NR bootstrap, Vulkan dispatch, identity shim |
| `runtime/codec.cpp` | initial HDR encode and one final HDR composition |
| `runtime/ngx_parameters.cpp` | separate, proven core-allocated parameter-map ABI |
| `runtime/pipeline.cpp` | budget gate, owned resources, N independent Feature 18 contexts, raw ping-pong, retirement worker |

## Call graphs

POST:

```text
signed SR/RR Evaluate (once, original history/output)
  -> copy same-frame completed output + active MV/depth
  -> HDR encode once to base proxy
  -> Feature18 layer 1 (private handle/map/history) -> ping A
  -> ... layer N -> ping A/B
  -> HDR composition once into original output
  -> real queue ExecuteCommandLists
  -> same-queue Signal
  -> status may become active
```

PRE_SR:

```text
copy same-frame current Color + active MV/depth
  -> HDR encode once
  -> N private Feature18 layers through raw ping-pong
  -> HDR composition once into owned compact Color
  -> temporarily bind Color/base=(owned,0,0)
  -> original signed Feature 1 Evaluate (once, original history/output)
  -> restore and reread original feature-map fields
  -> real queue ExecuteCommandLists + same-queue Signal
  -> status may become active
```

The experimental two-SR/two-order graph is intentionally absent.

## Parameter ABIs

Two different local ABIs are retained rather than conflated:

- signed feature-boundary map: resource Get slot 9, u32 Get 11, i32 Get 12, f32 Get 14, resource Set 1, i32 Set 4;
- NGX-core allocated private map: pointer Set 0, i32 Set 3, u32 Set 4, f32 Set 6.

PRE mutates only `Color` and its X/Y base for the duration of the one original SR call. It verifies the temporary values and verifies restoration. POST never mutates the game's parameter map. Feature 18 receives clean flags containing only HDR bit 0 and depth-inverted bit 3, while the game map is untouched.

## Resource contract

Current CP native contract is deliberately narrow and fail-closed:

- direct graphics command list;
- Color/MV `DXGI_FORMAT_R16G16B16A16_FLOAT`;
- Depth `DXGI_FORMAT_R32_TYPELESS`;
- one 2D mip/layer/sample, unknown texture layout;
- source/MV/depth in `NON_PIXEL_SHADER_RESOURCE`, POST output in UAV;
- all active source/guide subrects fit their resources;
- work/output dimensions at most 16384 each;
- PRE only with reconstruction `sr`; POST with `sr` or `rr`.

Motion and depth are copied from the provided bases to owned `(0,0)` resources every frame. Feature 18 subrect origins are always zero. The current Color is copied on the same command list immediately before encode, so no old-frame staging path exists.

## VRAM gate

For work pixels `W` and guide pixels `G`, pass count `N`:

```text
owned surfaces = W * 8 * 5 + G * 12
history/workspace allowance = W * 8 * 4 * N
reserve = max(1 GiB, DXGI budget / 10)
required = surfaces + allowance + reserve
```

All arithmetic saturates. `QueryVideoMemoryInfo(LOCAL)` must succeed and `required <= Budget - CurrentUsage` before creating a chain resource, private map, or Feature 18 handle. The history term is a conservative admission estimate, not an NVIDIA-published allocation formula; status reports the exact estimate, reserve, budget, and observed usage.

## State and guard priority

1. D5LC off: disabled/pass-through regardless of D5RP.
2. A changed SR/RR reconstruction closes the gate until a strictly newer adapter gate generation (the built-in CP path requires restart for such a change).
3. PRE + RR or PRE without adapter-proven Feature 1: unsupported/pass-through, never moved to POST.
4. Wrong adapter phase/generation: gate_closed/pass-through.
5. Unsupported NR-upscaling control: unsupported/pass-through.
6. DXGI budget rejection: budget_exceeded before layer allocation.
7. Create waits for real post-forward execute acknowledgement.
8. Any partial create/evaluate/reset/lifetime failure permanently faults that chain; output composition happens only after all N evaluates succeed.

An in-flight old submission can never make a re-enabled path active: D5LC `0 -> 1` clears runtime status evidence and forces a new all-layer reset evaluation.

## Honest proof levels

- host loaded: only loader fact; never GPU proof;
- capability file: real production DLL + vkd3d interop + signed runtime Init + NGX/device/queue hooks;
- create pending: distinct handles recorded, no submission claim;
- active status: N successful calls + one compose + PRE commit if applicable + real Execute forward + successful same-queue Signal;
- GPU completion: used for retirement, not falsely inferred from record callbacks.
