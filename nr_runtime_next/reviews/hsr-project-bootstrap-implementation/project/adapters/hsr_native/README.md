# HSR late native ingress candidate

This directory is the game-specific, native D3D11 ingress for Honkai: Star
Rail. It preserves the already-proven NVUnity-owned IAT route; it is **not** a
DXGI bootstrap, ReShade add-on, launcher, Guardian replacement, or deployment
script.

## Implemented path

1. `NVUnityPlugin.real.dll` is loaded from the proxy directory and all 68
   original exports are resolved. Assembly tail jumps preserve the existing
   binary calling convention and return values.
2. The retained NVUnity resolver is routed so the actual numeric application ID
   is captured only after the original `NVSDK_NGX_D3D11_Init[_Ext]` returns
   success. Project-ID initialization is forwarded but does not invent a numeric
   ID.
3. Only signed D3D11 `nvngx_dlss.dll` Feature 1 Create/Evaluate/Release is
   classified. Each original call is made exactly once. Feature 13 and a D3D12
   game reconstruction path are not claimed.
4. The host is considered for loading only inside the post callback of a
   successful original Feature 1 Evaluate, after coherent Output/MV/depth have
   been extracted at HSR's D3D11 parameter vtable slot **8**. There is no host,
   runtime, D3D12, or NVIDIA DLL import in the candidate PE.
5. The adapter creates same-adapter D3D12 resources and **two directional**
   shared fences. Only D3D11 signals the input/retirement fence; only D3D12
   signals the output-ready fence. Every submitted bridge list with a successful
   D3D12 Signal gets a D3D11 GPU Wait and a D3D11-produced retirement Signal,
   including `CREATE_PENDING` frames with no game copyback. The actual copy to
   game Output remains conditional. A failed D3D12 Signal never queues a wait on
   its unsignalled value.
6. `DLSS5_NativeHostStartV1`, Attach, Gate, SubmitRawFrame and CommitFrame use
   `native/include/native_adapter.h` directly (raw/result sizes 200/216). The
   native host remains the sole owner of order, 1--10 independent NR layers,
   budget, private maps, and active status.

The bridge uses the old proven D3D11-first/D3D12-first shared-resource fallback,
but its command queue is intentionally created only after native Submit has
registered the command list. That lets the already-loaded host hook the actual
owned queue without installing the CP/DXGI early bootstrap.

## Real format bridge, still acceptance-gated

The cross-compile now builds `dlss5-hsr-format-bridge.dll` from the other
worker's `adapters/format_bridge/bridge.*` and a narrow C wrapper in
`format_bridge_module.cpp`. NVUnity loads that exact module only at the same
late successful-Evaluate point. It records real GPU conversions:

- raw Output/MV/depth resources `26/33/19` to normalized `10/10/39`, but
  only after an owned pass-through observer sees actual same-resource D3D11
  SRV descriptors `37/21` during the successful signed SR call;
- state restoration for raw and normalized resources;
- exactly one final normalized Output to raw format 26 after an evaluated result
  with the host-confirmed layer count;
- helper resource lifetime through the owned queue's submission fence.

The adapter observes the host's frozen D5RP cold latch, then confirms the actual
layer count from the first `CREATE_PENDING` result. It does not implement an
order/layer manager. A mismatch rejects format commit and preserves game Output.
Typeless resource IDs 33/19 are not interpreted as SNORM/depth by inference:
without the actual observed 37/21 view pair, the post path is not format-ready.
The diagnostic observer patches only the Windows-SDK-verified
`ID3D11DeviceContext::CSSetShaderResources` slot 67 on the real context supplied
to signed Evaluate. It calls `GetDesc` and `GetResource` only for views actually
passed to that binding call during the signed scope, then compares exact
`IUnknown` Frame identities. Creation and generic cached views cannot attest
usage. Raw formats are reported even when they reject the strict contract.
The observer publishes its predecessor before a permission-guarded vtable CAS,
holds both a context and predecessor-module lifetime reference, preserves a
competing hook on collision, and disables capture if page-protection restoration
fails while retaining pass-through forwarding. Its vtable records, per-call
scan and raw samples are bounded. A later actual HSR run with no observed CS
binding calls or no exact-identity matches remains unproven. The external
native-build lease must
remain unattested until main finishes real GPU/state/format validation, so source
presence alone cannot open the gate.

There is no CPU conversion fallback. `pre_sr` is intentionally absent: this port
does not extract Color and never sets
`D5N_ADAPTER_SUPPORTS_PRE_FEATURE1_V1`.

Other acceptance blockers remain explicit:

- The current `astral_hsr_guard.py` publishes only the legacy phase marker, not
  the challenge-bound Guardian lease in `GUARDIAN_PROTOCOL.md`. Process-name
  presence is never treated as Guardian health. Until a reviewed publisher is
  added, the native gate stays closed and the host is not loaded.
- The reviewed main integration adds separately probed
  `DLSS5_NativeAdapterCommitExternalPostV1` and the explicit Attach capability.
  It reuses the frozen 72-byte Commit layout, records POST/current gate+reset
  epoch internally, and keeps status closed until both copyback acknowledgement
  and later sampled GPU completion. The old
  `OPTIONAL_NATIVE_EXTERNAL_POST.patch` is superseded and must not be applied:
  its global self-identity rejection breaks built-in WuWa and its phase rule
  rejects WuWa RR POST.
- The same reviewed integration adds `DLSS5_NativeAdapterRetireV1`. Until that
  host is present this router still closes permanently after first routed owner
  release. With it, status proof is revoked before that owner's private runtime
  map is retired.

A successful external POST is reported by this router only after a nonblocking
poll sees completion of the private D3D11-produced retirement point ordered
after output Wait+game copy, then the explicit host acknowledgement accepts the
same frame/epoch. `CREATE_PENDING`, a queued D3D12 fence, a queued D3D11 copy,
or queuing the retirement Signal is not host-active proof. The router keeps one
bounded per-slot pending commit and bypasses without another host Submit while
its retirement value is busy, so moving frames cannot overwrite it. The
output-ready fence covers D3D12 NR and the shared R11 commit; it does not prove
final Present or completion of the D3D11 game copy.

## Files and build

The fresh candidate outputs are:

```text
adapters/hsr_native/build/NVUnityPlugin.hsr-native-candidate.dll
adapters/hsr_native/build/dlss5-hsr-format-bridge.dll
```

It expects, but does not install, the retained original and native core:

```text
StarRail_Data/Plugins/x86_64/NVUnityPlugin.real.dll
HSR root/dlss5-hsr-format-bridge.dll
HSR root/dlss5-native-host.dll
HSR root/dlss5-native-runtime.dll
```

The three DLLs loaded late by NVUnity are the format bridge, host, and runtime
(the host loads its adjacent runtime). The NVUnity candidate itself is loaded by
the game in the existing plugin-owned route.

No `dxgi.dll` is part of the HSR path. Build and run native CPU checks with:

```bash
make -C adapters/hsr_native clean check
make -C adapters/hsr_native harness   # cross-compile only; do not run here
```

`test_logic` also exercises the production CPU state helpers for directional
fence isolation, pending-frame dependencies, shared-texture reuse, busy-slot
bypass, failed-Signal no-wait behavior, explicit POST acknowledgement, and
fail-closed typed-view attestation. The hermetic host-native fake-COM test checks
exact identities, unexpected raw formats, bounded scanning, balanced references,
no cached-view acceptance, and exactly-once unchanged forwarding. A MinGW
compile-only translation unit uses `offsetof` on the Windows SDK's C-form
`ID3D11DeviceContextVtbl` to prove CS slot 67 and its adjacent entries.
The PE check compares all 68 exports, verifies slot 8, rejects early
host/runtime/D3D12/NVIDIA imports from NVUnity, and confirms the separate late
helper's real D3D12 API. The fake NVUnity/core/feature harness is built
for later owner-run Windows/Wine CPU acceptance; this worker did not run Wine,
the game, or GPU work.

See `INTEROP.md`, `GUARDIAN_PROTOCOL.md`, and `DEPLOYMENT_INVENTORY.md` before
main-owner integration. This is source-complete ingress with an explicit
late-loaded normalizer and lease seam, not a GPU-accepted deployable binary.
