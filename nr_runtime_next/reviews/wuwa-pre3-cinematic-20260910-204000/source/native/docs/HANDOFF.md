# Main-owner cold CP handoff

## What is and is not proven

Proven without a game/GPU submission:

- Windows x64 production PE build;
- actual Wine system32 DXGI factory forwarding through the owned proxy;
- owned host/runtime load occurs outside `DllMain`;
- frozen D5RP32 and unchanged D5LC72 validation;
- pure state tests for one original reconstruction, N independent layer identities/counters, one final composition, PRE/POST order, parameter restoration, reset-before-execute rejection, RR/PRE and phase guards;
- fake runtime cannot write production capabilities;
- no ReShade/RenoDX symbols or signed NVIDIA file payload in the package.

Not proven here: actual CP2077 D3D12 device interception, signed Feature 18 Create/Evaluate on RTX 5090, GPU output, quality, performance, or long-run temporal behavior. This is why the artifact is labelled production candidate.

## Exact artifact set

Use only the three matching files from `native/package/bin/`:

```text
dxgi.dll
dlss5-native-host.dll
dlss5-native-runtime.dll
```

Verify `native/package/SHA256SUMS`. Keep the existing signed `nvngx_dlssnr.dll`, signed `nvngx_dlss.dll` / `nvngx_dlssd.dll`, and NGX core unchanged. Do not rename the owned runtime to an NVIDIA filename and do not mix this candidate with old order/ReShade/RenoDX modules.

No installation or launch was performed by this worker.

## First cold acceptance (main owner only)

Use a fresh process and begin with `post/1`, not ten layers. Keep D5LC `enable_upscaling=0`. Acceptance requires all of the following evidence from one session:

1. DXGI calls still return the actual Wine/Proton factory and game rendering initializes.
2. `D3D12CreateDevice` was forwarded successfully and the returned COM identity is unchanged.
3. the real direct queue was observed through either the hooked device creation path or an owned-factory `CreateSwapChain*` caller route;
4. NGX signed SR Feature 1 Create/Evaluate/Release entrypoints were captured without changing the signed file;
5. signed NR Vulkan bootstrap count is exactly one;
6. one Feature 18 handle has a nonzero DWORD ID, create count one, and evaluate count increments once per active frame;
7. first Feature 18 Create reports pending until a later real `ExecuteCommandLists` post-forward acknowledgement;
8. status heartbeat is fresh and becomes `active` only after actual evaluation/final compose, the same-queue signal, and a sampled fence completion for that enable/gate/owner epoch;
9. disabling D5LC is visual pass-through and re-enable produces one reset on every active layer;
10. no Xid/device loss and no stale old-frame output.

Then test `pre_sr/1` in a new cold process. Confirm only Feature 1 is eligible, the original SR Evaluate is called once, temporary Color/base values restore exactly, and no second signed SR history exists. Confirm `submit_ack_samples` can advance before `completed_frame_samples`, `active` remains false in that interval, and `last_completed_frame_id` eventually reaches the first successfully committed PRE frame. Test RR + `pre_sr` as a guard-only case: it must remain original RR with `unsupported`, no NR calls, and no hidden POST.

Only after 1-layer acceptance should cold processes test 2..10 requested layers. For every count N, require N distinct nonzero handle IDs, N distinct private parameter objects, each create count exactly one, each evaluate counter advancing exactly once per active frame, and one final composition. A `budget_exceeded` result is a valid fail-closed hardware outcome; `max_nr_passes:10` is not a fit guarantee.

## Known integration risk to resolve with evidence

The host now targets only the current CP main executable's statically verified
`sl.interposer.dll!D3D12CreateDevice` IAT. It does not enumerate arbitrary
modules or fall back to a global predecessor. If a future CP build moves device
creation to a dynamic path or another module, `queue_hook_seen` remains false,
no capability file is emitted, and NR stays unconfirmed. Capture that exact
module/import path and add an allowlisted target with its own wrapper; do not
restore whole-process scanning or synthesize readiness.

WuWa/HSR are intentionally not acceptance claims in this package. The configured
WuWa main executable has no `D3D12CreateDevice` import, so this patch proposes no
WuWa factory/device IAT target. Instead, a factory returned by any of the three
owned DXGI exports is observed after successful real forwarding. Its base and
Factory2 `CreateSwapChain*` methods best-effort detect a D3D12 queue, then reuse
the existing device/queue hooks before the original method returns. Observation
failure never changes the original factory/swapchain HRESULT, arguments, or COM
output.

WuWa scope must be recorded exactly as: **queue-at-swapchain route implemented
but UNVALIDATED**. Main must cold-test that the actual caller obtains its factory
through this owned proxy and invokes one tracked method before first SR; source
shape alone is not proof. Do not claim a nonexistent main factory IAT, add a
whole-process scan, guess a protected-executable `GetProcAddress`, or publish
capability without real NR proof. HSR already owns dynamic D3D12 device creation
and delayed queue setup after native submit tracking, so it does not need a
main-executable factory hook. No HSR Feature 1 capability is assumed.
