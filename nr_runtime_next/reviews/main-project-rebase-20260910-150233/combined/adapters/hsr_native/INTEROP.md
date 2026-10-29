# D3D11 to owned D3D12 POST contract

## Observed game inputs

The audited HSR route is D3D11 Feature 1. `router.cpp` uses only parameter
resource getter vtable slot 8 and these observed keys:

- resources: `Output`, `MotionVectors`, `Depth`;
- dimensions: `DLSS.Render.Subrect.Dimensions.Width/Height` (with the old
  `Width/Height` compatibility fallback) and `OutWidth/OutHeight`;
- temporal metadata: `Reset`, `Jitter.Offset.X/Y`, `MV.Scale.X/Y`,
  `DLSS.Feature.Create.Flags`, and optional `DLSS.Pre.Exposure`.

The frame is rejected before native work unless textures are single-sample,
one-mip, one-array-layer, origin-zero exact extents and exactly:

| role | DXGI number | DXGI enum | extent |
|---|---:|---|---|
| Output | 26 | `R11G11B10_FLOAT` | output |
| MotionVectors | 33 | `R16G16_TYPELESS` | render |
| Depth | 19 | `R32G8X24_TYPELESS` | render |

There is no game D3D12 Feature 13 path and no PRE Color binding.

## Ownership and ordering

The transport holds AddRef references to the three game resources across the
whole routed call. Persistent shared textures hold independent D3D11 and D3D12
references plus NT handles. The linked formatter owns normalized resources and
must retain them through `submitted(fence, value)`.

For each submitted bridge frame whose D3D12 output Signal succeeds:

```text
D3D11 game queue: Copy(Output/MV/depth to shared) -> Signal(input-ready)
D3D12 direct queue: Wait(input-ready) -> format prepare -> host NR/prepare
                    -> optional format commit -> Execute -> Signal(output-ready)
D3D11 game queue: Wait(output-ready) -> [optional Copy(shared Output to game)]
                  -> Signal(d3d11-retired)
```

Input-ready and D3D11-retired values share the D3D11-produced directional fence;
output-ready values use a distinct D3D12-produced directional fence. Values are
never compared across directions. The D3D11 `Wait` is enqueued for every
successfully signalled bridge submission, including `CREATE_PENDING`; only the
game-output copy is conditional. Therefore later copies into the global shared
textures remain behind the prior D3D12 consumer. A failed D3D12 Signal queues no
D3D11 Wait (which would deadlock the game queue), permanently disables reuse,
and retains uncertain references for process lifetime.

An unsubmitted native list is reset so the host invalidates its exact runtime
cookie. If Reset/discard cannot be proven, formatter bookkeeping is not aborted
and its references are retained rather than retired prematurely.

The shared resources enter and leave formatter work in `COMMON` with
`ALLOW_SIMULTANEOUS_ACCESS`. The late helper wraps
`nr::format_bridge::FormatBridge` and returns normalized Output in
`UNORDERED_ACCESS`, MV/depth in `NON_PIXEL_SHADER_RESOURCE`. It restores the
shared raw states after conversion and the normalized states after its final
format-26 record. Resource formats 33/19 do **not** imply views 37/21. The router
patches only the SDK-layout-verified ID3D11DeviceContext
`CSSetShaderResources` slot 67 on the context actually supplied to signed
Evaluate. Its owned pass-through observer forwards the original arguments once
and unchanged. During that signed scope it calls each passed view's `GetDesc`
and `GetResource`, compares the returned resource's exact `IUnknown` identity
to the current Frame motion/depth identities, logs raw formats even when they
are unexpected, and accepts only exact resource/view contracts 33/37 and 19/21.
A creation event or a typed view cached for a different identity cannot attest
SR usage. If a later HSR run has no CS binding calls or no identity matches, the
contract remains unproven. The host's raw ingress receives only owned D3D12
resources; no D3D11 pointer is cast to D3D12.

## Synchronization caveat

The render-thread transport does not call `WaitForSingleObject` or
`SetEventOnCompletion`. Allocator pressure is fence-polled and bypasses while
busy. Resolution-dependent resources are replaced only after the actual
D3D11-produced retirement point completes; otherwise reconfiguration bypasses,
and device-removal/unknown-completion paths leak safely for process lifetime.
`UINT64_MAX` is always device-removal/invalid evidence, never completion.

The helper's owned-byte cap comes from actual local DXGI budget minus current
usage and a `max(10%, 512 MiB)` reserve; its single in-flight format slot is
allocated before the native runtime's separate budget query, so current usage
is visible to that second guard. If that slot's fence is incomplete, a later
game frame bypasses instead of allocating a second unbudgeted slot or presenting
old work. The D3D12 output-ready fence covers NR plus commit to the shared R11
resource. It is not final-Present proof and is not D3D11 copyback-completion
proof. The adapter keeps one bounded per-slot commit record, bypasses new native
submits while it is busy, and acknowledges external POST only after a
nonblocking `GetCompletedValue` poll sees the later D3D11-produced retirement
point complete. Merely enqueueing that Signal is never completion. No GPU, Wine,
or game validation has been performed.

The D3D12 queue is deferred until after host Submit tracks the list. The host's
in-place device-vtable hook therefore observes creation of this exact queue and
can acknowledge its forwarded `ExecuteCommandLists` plus same-queue fence. The
HSR package must not contain the native CP `dxgi.dll` bootstrap. The format
helper imports D3D12, but NVUnity does not; it loads the helper only after the
signed-success/Guardian/build gate preconditions.
