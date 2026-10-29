# Native architecture and safety invariants

## Modules

| Module | Responsibility |
|---|---|
| `boot/dxgi_proxy.cpp` | system32 DXGI forwarding, loader-lock-free bootstrap, and post-success owned-factory notification |
| `host/loader.cpp` | owned IAT routing for `D3D12CreateDevice` and NGX core `GetProcAddress` |
| `host/factory_hooks.cpp` | bounded known-factory vtable hooks and D3D12 swapchain-queue observation |
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
  -> background sample observes that fence complete
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
  -> background sample observes that fence complete
  -> status may become active
```

The experimental two-SR/two-order graph is intentionally absent.

## Exact loader targets

The loader never enumerates the process module list. It acquires and revalidates
only two normal loader references outside `DllMain`: the CP main executable for
its current `sl.interposer.dll!D3D12CreateDevice` IAT, and `_nvngx.dll` for its
`KERNEL32.dll!GetProcAddress` IAT. PE32+ headers, import directory, descriptors,
thunks and bounded names must all fit `SizeOfImage`; a matching descriptor with
`OriginalFirstThunk == 0` fails closed rather than interpreting the resolved IAT
as `IMAGE_IMPORT_BY_NAME` data.

Each exact target owns a separate predecessor and wrapper. The predecessor is
published with `InterlockedCompareExchangePointer` before the IAT CAS makes the
wrapper callable. Already-installed hooks are skipped; a CAS mismatch or a slot
changed after this host installed its wrapper is reported as a conflict and is
never forcibly overwritten. Temporary references are released after each pass.
One ordinary (not `PIN`) `_nvngx.dll` reference is deliberately retained after a
successful patch so the recorded slot/predecessor continues to describe one
live core generation rather than an unload/reload ABA; arbitrary modules are
never pinned or retained.

WuWa's configured main executable has no `D3D12CreateDevice` import, and HSR owns
a dynamic device plus delayed queue path after native submission tracking. This
candidate therefore invents no main-EXE hook for either game.

Independently of exact IAT routing, all three exports on the owned DXGI proxy
notify one additive host export after the real system32 factory call succeeds.
The host QIs the returned opaque interface for `IDXGIFactory2`,
`IDXGIFactory1`, and `IDXGIFactory`; this supports newer requested interfaces
without casting the output to a guessed revision and preserves a base fallback
when Factory2 is unavailable. Per-vtable records patch only the SDK-verified
`CreateSwapChain` slots 10 and Factory2 `CreateSwapChainForHwnd` 15,
`CreateSwapChainForCoreWindow` 16, and `CreateSwapChainForComposition` 24.
Originals are published before exact slot CAS, one QI reference keeps each
successfully patched vtable live, duplicate observations are idempotent, and a
concurrent replacement is never overwritten. No QI, Release, GetDevice, or
other COM call occurs while the private factory patch lock is held.

Each wrapper best-effort QIs `pDevice` for a real `ID3D12CommandQueue`, obtains
its real `ID3D12Device`, and calls the existing device and queue hook
implementations before forwarding the factory method exactly once with all
original arguments and output. A D3D11 QI miss or any observation/patch failure
cannot replace the original factory result or force swapchain creation to fail.
This queue-at-swapchain route covers pre-existing direct queues presented to a
tracked factory, but remains **UNVALIDATED in WuWa** until main cold-tests the
actual caller route. It is not evidence of a WuWa IAT target or working game
coverage.

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

All arithmetic saturates. `QueryVideoMemoryInfo(LOCAL)` must succeed and `required <= Budget - CurrentUsage` before creating a chain resource, private map, or Feature 18 handle. The history term is a conservative admission estimate, not an NVIDIA-published allocation formula. Status reports the estimate, reserve, budget, and `current_usage_bytes` captured at chain admission; `current_usage_sample:"chain_admission"` explicitly says that usage is not a fresh live query.

## State and guard priority

1. D5LC off: disabled/pass-through regardless of D5RP.
2. A changed SR/RR reconstruction closes the gate until a strictly newer adapter gate generation (the built-in CP path requires restart for such a change).
3. PRE + RR or PRE without adapter-proven Feature 1: unsupported/pass-through, never moved to POST.
4. Wrong adapter phase/generation: gate_closed/pass-through.
5. Unsupported NR-upscaling control: unsupported/pass-through.
6. DXGI budget rejection: budget_exceeded before layer allocation.
7. Create waits for real post-forward execute acknowledgement.
8. A fully recorded Evaluate waits for a real post-forward acknowledgement and then a nonblocking background fence-completion sample.
9. Any partial create/evaluate/reset/lifetime failure permanently faults that chain; output composition happens only after all N evaluates succeed.

An in-flight old submission can never make a re-enabled path active: D5LC `0 -> 1`, every adapter gate generation, and owner retirement clear host/runtime completion evidence and force a new all-layer reset evaluation. Pending records carry gate/reset epochs, so a late acknowledgement from an older epoch cannot repopulate proof.

## Honest proof levels

- host loaded: only loader fact; never GPU proof;
- capability file: real production DLL + vkd3d interop + signed runtime Init + NGX/device/queue hooks;
- create pending: distinct handles recorded, no submission claim;
- submit acknowledgement: N successful calls + one compose + PRE commit if applicable + real Execute forward + successful same-queue Signal;
- active status: the manager/adapter gate is still current and at least one such successful frame in the current enable/gate/owner epoch has a sampled GPU-completed fence;
- retirement: separately follows the latest accepted fence, so active proof never waits for a continuously moving latest fence.

Each chain holds at most one completion-sample fence reference. The worker polls `GetCompletedValue` without waiting; it keeps the oldest outstanding sample rather than replacing it with every newer frame. `UINT64_MAX` (device removal) faults evidence and is never completion. Query/status sample counters are lower-bound observations, not exact frame totals.
