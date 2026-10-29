# Strict same-input single-pass NR/SR order comparison plan

Status: architecture only. No game/GPU process was started and no existing router,
service, capture, deployment, result, or game file was changed.

## 1. Experiment being implemented (and nothing else)

For every eligible signed **Feature 1** evaluation in one continuous process:

```text
one current low-resolution scene-linear HDR source S_t
one current guide/metadata set G_t

A: S_t -> one persistent low-resolution NR_A evaluate -> signed SR_A -> A_t (6144x3456)
B: S_t -> independent signed SR_B              -> one persistent 6K NR_B evaluate -> B_t (6144x3456)
```

The comparison unit is `(evaluate_id, A_t, B_t)` from the same intercepted game
call. Both branches must execute on every eligible frame, including frames outside
the capture windows, so all four temporal histories advance exactly once per game
frame. This is not PRE-SR 1 versus PRE-SR 3, not recursive NR, not RR, not FG, and
not a comparison between separate game launches or nominally equal frame numbers.

The game continues to consume `A_t` in its original Output resource. `B_t` lives in
an owned output resource and exists only for comparison/capture.

## 2. Findings that constrain the design

### 2.1 The second SR history can use the exact original Create map

The router already captures the actual signed `nvngx_dlss.dll` D3D12 exports:

- ABI typedefs are `presr/router/ngx_proxy_abi.h:18-24`.
- `hook_get_proc_address` stores and replaces the real Create/Evaluate/Release
  addresses at `presr/router/router_addon.cpp:950-979`.
- `route_create` currently calls the captured signed Create exactly once at
  `presr/router/router_addon.cpp:514-541`.

There is no generic, exact parameter-map clone operation. The public parameter
interface has typed `Set`, typed `Get`, and `Reset`, but no enumeration or copy
method (`/home/user/rt_5090_project/nvidia-dlss-official/include/nvsdk_ngx_params.h:53-74`).
A hand-built named copy could silently omit a private key.

Therefore the smallest exact clone is to clone the **Create call**, not attempt to
clone the opaque map:

1. call the captured signed Feature-1 Create normally and preserve its handle/result
   as the game's `SR_A`;
2. before returning from the same hook, call that same captured function again on
   the same open command list, feature ID, and untouched original parameter object;
3. retain the second, distinct handle as owned `SR_B`; return only the game's first
   result/handle.

This preserves every public and private Create parameter because both calls see the
same map. NVIDIA's API contract explicitly permits multiple instances and says that
evaluating one should not change another's state
(`/home/user/rt_5090_project/nvidia-dlss-official/include/nvsdk_ngx.h:488-505`; the
Vulkan wording is identical at `nvsdk_ngx_vk.h:482-499`). It also allows a feature
to reject same-parameter duplication with `FeatureAlreadyExists`
(`nvsdk_ngx.h:529-540`), so duplicate-Create success is a mandatory smoke gate, not
an assumption.

For telemetry only, snapshot the documented D3D12 Create keys set by NVIDIA's
helper: `CreationNodeMask`, `VisibilityNodeMask`, `Width`, `Height`, `OutWidth`,
`OutHeight`, `PerfQualityValue`, `DLSS.Feature.Create.Flags`, and
`DLSS.Enable.Output.Subrects`
(`/home/user/rt_5090_project/nvidia-dlss-official/include/nvsdk_ngx_helpers.h:427-445`).
These snapshots do not replace reuse of the original opaque map.

Do **not** use `NVSDK_NGX_D3D12_AllocateParameters` as an unproven fallback and pass
that object directly to the captured feature-DLL function. The local code already
documents two different parameter-object ABIs: the signed feature-boundary helpers
in `presr/router/ngx_proxy_abi.h:35-93`, and the core-allocated object setters
(pointer/int/uint/float slots 0/3/4/6) in
`presr-multipass/service/dlss5_vk_bridge.cpp:2991-3025`.

The signed Feature-18 side is also identified rather than guessed. Its local ABI is
`CreateFeature1(VkDevice, VkCommandBuffer, feature, const params, out_handle)`,
`EvaluateFeature(VkCommandBuffer, const handle, const params, callback)`, and
`ReleaseFeature(handle)` at `presr/service/dlss5_vk_bridge.cpp:60-68`; the pointers
are resolved by those exact export names from `nvngx_dlssnr.dll` at
`presr/service/dlss5_vk_bridge.cpp:1264-1268`. PRE proves the intended calls with
feature ID 18 at `presr/service/dlss5_vk_bridge.cpp:3175-3190`.

### 2.2 Evaluation must use two handles, not one handle twice

The independent-history rule is already explicit in the multipass source:
`presr-multipass/service/dlss5_vk_bridge.cpp:125-139` states that reusing one handle
would advance one temporal history multiple times in one frame. The order comparison
therefore owns exactly these histories:

- signed `SR_A`: original game handle;
- signed `SR_B`: second signed Create result;
- `NR_A`: one Feature-18 handle in the PRE service;
- `NR_B`: one Feature-18 handle in the POST service.

Each is evaluated at most once per successful comparison frame. No handle arrays,
ping-pong pass loop, or `DLSS5_PRE_PASSES` setting belongs in this experiment.

### 2.3 The current PRE seam already preserves the source and states

The router currently declares Color/Motion/Depth arrival as NPSR at the signed SR
boundary (`presr/router/router_addon.cpp:688-694`). The PRE service:

- allocates compact owned active/proxy/neural/decoded textures at
  `presr/service/dlss5_vk_bridge.cpp:2739-2779`;
- copies the current Color active rectangle to immutable staging and restores both
  D3D12 states at `presr/service/dlss5_vk_bridge.cpp:2783-2823`;
- records one Feature-18 evaluate and one HDR decode/composition at
  `presr/service/dlss5_vk_bridge.cpp:3138-3214`;
- exposes the decoded texture in NPSR state at
  `presr/service/dlss5_vk_bridge.cpp:3244-3249`.

The current router temporarily binds this texture as Color, evaluates signed SR,
and immediately restores Color with pointer readback verification
(`presr/router/router_addon.cpp:697-733`). That seam is the base for branch A, but
the new router must also guard Output and any changed Color subrect bases.

### 2.4 The POST-NR guide contract is mixed-resolution by design

For branch B, Feature 18 consumes the completed 6144x3456 signed-SR image while
using the same current low-resolution motion/depth guides. Existing POST code
establishes this exact shape contract:

- reject unless Output exactly matches output dimensions and guide allocations
  cover the render extent: `presr/service/dlss5_vk_bridge.cpp:3866-3879`;
- Color/Output subrects are 6K at origin zero, while MVec/Depth subrects retain game
  bases and the low-resolution render extent:
  `presr/service/dlss5_vk_bridge.cpp:3428-3485`;
- copy the current MV scale, clean the NR flags to HDR bit 0 plus DepthInverted bit
  3, and bind persistent Vulkan wrappers:
  `presr/service/dlss5_vk_bridge.cpp:3487-3548`;
- snapshot signed SR output from UAV and restore it before Vulkan NR work:
  `presr/service/dlss5_vk_bridge.cpp:3570-3591`.

A retained real-frame metadata record confirms the target call contract is
4096x2304 guides, bases 0, flags `0x4b`, cleaned NR flags `0x09`, MV scale
4096x2304, and 6144x3456 output
(`captures/20260909-104246-paired-300/frames/frame-000000.json`). This is evidence
for the target configuration, not permission to hard-code unverified future frames.

### 2.5 Create success is command recording, not execution

The stronger PRE implementation associates each created handle with the exact
native command list, invalidates it on reset/destroy, and acknowledges it only from
ReShade API-18 execute event 72
(`presr-multipass/service/dlss5_vk_bridge.cpp:1090-1167`). It then makes creation
build-only and does not evaluate until acknowledgement
(`presr-multipass/service/dlss5_vk_bridge.cpp:3647-3693` and `3701-3729`).

Apply this rule to all three owned creates: `SR_B`, `NR_A`, and `NR_B`. The existing
single-pass POST path creates and evaluates `NR_B` in one invocation
(`presr/service/dlss5_vk_bridge.cpp:4065-4109`); that shortcut is not acceptable for
this strict capture build.

### 2.6 Existing readback ordering is suitable after changing the planes

The paired recorder already has the needed submission proof:

- recording stores the exact native command list and records state-restoring GPU
  copies (`paired-capture/service/paired_capture.cpp:1979-2030`);
- API-18 execute only associates the list with its native queue and explicitly does
  not signal because the callback is pre-submit
  (`paired_capture.cpp:1564-1621`);
- a later matching Present enqueues the queue fence signal
  (`paired_capture.cpp:1623-1680`);
- only the writer thread maps after `GetCompletedValue >= fence_value`
  (`paired_capture.cpp:1394-1411`).

The current capture explicitly says its old planes are 4K before signed SR, not
paired final 6K outputs (`paired-capture/CAPTURE.md:77-90` and
`paired_capture.cpp:1330-1338`). That implementation cannot be relabeled; its plane
schema must be replaced for this experiment.

## 3. Smallest viable architecture

Create a new self-contained `order-comparison/` implementation later; do not edit
or repurpose `presr/`, `presr-multipass/`, `paired-capture/`, or their reports.
Use one router and two role-specific service builds:

```text
00-dlss-order-router.addon64
01-dlss-order-pre.addon64   exports DLSS5_OrderPreEvaluateV1/PreReleaseV1
02-dlss-order-post.addon64 exports DLSS5_OrderPostEvaluateV1/PostReleaseV1
                           and links the two-plane paired writer
```

The router must resolve by **exact basename plus exact unique export**, reject zero,
duplicate, or wrong-ABI providers, and cache both module handles. Do not copy the
current “first module exporting this generic name wins” discovery loops
(`presr/router/router_addon.cpp:184-233`). Neither service exports generic
`DLSS5_PostEvaluate`, so existing post routing cannot accidentally add another NR
layer.

Two PE images isolate the code-owned statics that are currently process-global:
`g_vk_state`, `g_codec_state`, `g_images`, and `g_codec_descriptors`
(`presr/service/dlss5_vk_bridge.cpp:268-339`), as well as PRE and POST resources and
parameter blocks. Each role owns one clearly named NR handle/history.

### Signed-runtime initialization caveat

Both services must not independently patch and initialize the one loaded
`nvngx_dlssnr.dll`; the current `ensure_vk` both patches its IAT and calls
`NVSDK_NGX_VULKAN_Init_Ext2` (`presr/service/dlss5_vk_bridge.cpp:1243-1268`), and
there is no local proof that doing that twice is harmless.

For the two-build design, make PRE the sole runtime-bootstrap owner. It exports a
small versioned runtime lease containing AddRef'd interop, Vulkan instance/device,
GIPA/GDPA, signed-runtime module identity, and Create/Evaluate/Release pointers.
POST borrows that already initialized runtime, resolves only its own Vulkan codec
functions, and keeps its own image/view/descriptor/parameter/NR-handle state. PRE
must stay pinned and must not call Shutdown until POST has released its lease and
handle. If this lease cannot be made explicit and testable, use one service binary
refactored around two explicit context objects instead; do not ship two independent
`Init_Ext2` callers.

## 4. Exact per-frame command sequence

All steps are recorded on the one intercepted open direct command list. Before step
1, acquire/AddRef and validate original `Color`, `Output`, `MotionVectors`, `Depth`,
dimensions, subrect bases, flags, reset, jitter, MV scales, and exposure values.
Latch one immutable NR control snapshot for both services.

1. **Preserve S_t / PRE NR_A.** PRE copies the original Color active rectangle to
   its immutable staging, restores original Color to NPSR, and evaluates exactly one
   `NR_A`. It returns an origin-zero scene-linear HDR `A_low` in NPSR.
2. **Signed SR_A.** In a scoped parameter guard, bind `Color=A_low`. If the original
   Color base was not zero, also bind Color base `(0,0)` for this compact texture.
   Keep `Output=original game Output`. Evaluate only the original game `SR_A` handle,
   passing the game's callback only here. Restore/verify all changed keys even on
   failure. The game Output now contains `A_t` and remains UAV.
3. **Signed SR_B.** In a second scoped guard, bind the original full Color pointer,
   original Color base, and `Output=owned_B`. Evaluate only owned `SR_B`, with a null
   auxiliary progress callback. Restore/verify original Color, Output, and bases.
   `owned_B` now contains raw signed-SR B in UAV.
4. **POST NR_B.** POST copies `owned_B` to its 6K immutable source, runs exactly one
   persistent `NR_B` using the latched controls and the same current guides/metadata,
   and HDR-decodes/composes back into `owned_B`. Its dedicated allocated NR map means
   it never mutates the game's signed-SR parameter object. `owned_B` is now `B_t` in
   UAV.
5. **Capture.** After POST `EndVkCommandBufferInterop` succeeds, record two D3D12
   copies, `game Output (A_t)` and `owned_B (B_t)`, each UAV -> COPY_SOURCE -> UAV.
   Do no display transform. Return from the hook; actual submission and later fence
   proof follow the existing execute/Present/worker protocol.

A frame enters the paired ordinal only if PRE-NR, SR_A, SR_B, POST-NR, both interop
ends, every resource/parameter restore, and both capture-copy recordings succeed.
Any auxiliary failure permanently aborts that capture session; it must never resume
after only one temporal history has advanced. The game-facing return remains the
original `SR_A` result, and the best available original game output is left intact.

## 5. Parameter and resource invariants

### Original signed-SR parameter object

Use the validated feature-boundary getter/setter ABI, especially D3D12 resource Get
slot 9 and resource Set slot 1 (`presr/router/ngx_proxy_abi.h:65-93`). Implement an
RAII guard around every branch mutation. On every exit path it must restore and
read back:

- `Color` = original full game Color resource;
- `Output` = original full game Output resource;
- `DLSS.Input.Color.Subrect.Base.X/Y` = original values if changed.

No PRE/POST service may set Width/Height, flags, quality, nodes, jitter, or any
`DLSSNR.*` key on this object. The existing POST code only partially restores a
shared object after sanitizing it (`presr/service/dlss5_vk_bridge.cpp:4115-4128`);
the strict build instead allocates a private POST NR map.

### Owned textures and expected states

| Resource | Allocation | Arrival/rest state | Use |
|---|---|---|---|
| original Color/MV/Depth | game-owned, full allocation | NPSR | read only; always restore |
| original Output (`A_t`) | game-owned 6144x3456 RGBA16F | UAV | SR_A target and capture plane A |
| PRE immutable source | owned active 4096x2304 | NPSR | exact S_t snapshot |
| PRE decoded `A_low` | owned 4096x2304 RGBA16F | NPSR | SR_A Color |
| `owned_B` | clone original Output `D3D12_RESOURCE_DESC`, DEFAULT heap | UAV | SR_B target, then in-place POST-NR final/capture B |
| POST source/proxy/neural | owned 6144x3456 | NPSR/NPSR/UAV as existing path | preserve SR_B and run one NR_B |
| readbacks | owned buffers | COPY_DEST | worker-only Map after fence |

Lazily allocate `owned_B` from the first valid original Output descriptor using
`CreateCommittedResource`, preserving dimension, width/height, format, sample,
mips/array/layout, flags, and node masks; only the initial state is explicitly UAV.
For this fixed experiment reject anything except single-sample 2D
`DXGI_FORMAT_R16G16B16A16_FLOAT` at 6144x3456. Do not convert an R11 output and call
it the same HDR plane.

PRE and POST each allocate/destroy a dedicated core parameter map. Populate them
with the allocated-object setters already proven by PRE, not the feature-boundary
slots. Both receive the same per-frame snapshot of jitter, MV scale, exposure,
reset, flags, guide bases, and NR controls. The cleaned Feature-18 flags must be the
same derivation `(source_flags & HDR_bit) | DepthInverted_bit` for both.

## 6. Creation, warm-up, reset, and release

- At original Feature-1 Create, issue both signed Creates on the same original map.
  Require success, non-null distinct handles, identical captured contract hash, and
  exact native-list execute acknowledgement for `SR_B`.
- On the first valid evaluation, PRE and POST may each create one NR handle, but the
  invocation is build-only for NR. Both signed SR handles still evaluate the
  original S_t that frame so their SR histories remain aligned. No paired ordinal
  is consumed.
- `NR_A` and `NR_B` begin evaluation together only after both exact creation lists
  are acknowledged. If either is still pending, evaluate neither NR handle.
- Require `SR_B` to have been acknowledged before the first game SR evaluation. If
  the game evaluates before that acknowledgement, abort strict capture rather than
  start histories at different frames.
- Propagate every game Reset to both SR evaluations unchanged and set both NR reset
  keys for that same source call. A role/config/raster change invalidates the whole
  comparison generation; wait for GPU idle, release both NR handles and `SR_B`,
  rebuild, and start a new explicitly recorded generation. Do not bridge capture
  windows across generations.
- Release only acknowledged handles. Follow the PRE precedent that waits for GPU
  quiescence and refuses premature release (`presr-multipass/service/dlss5_vk_bridge.cpp:3187-3222`
  and `3911-3951`). Call both service releases and signed `ReleaseFeature(SR_B)` in
  the matching game `SR_A` release path. NVIDIA states handles are not ref-counted
  and become invalid immediately after Release (`nvsdk_ngx.h:557-575`).

Before enabling NR, add a short **dual-SR calibration mode**: feed the original
S_t/G_t to both SR handles every frame and capture a few paired 6K outputs. Require
matching dimensions/contracts and deterministic equality (or a predeclared tiny
floating tolerance) before accepting that handle creation/order itself is not a
confound. This is a smoke gate, not production evidence.

## 7. Final-HDR capture plan

Adapt `paired_capture.cpp`; do not reuse its old five-plane schema.

- Two planes only: `frame-NNNNNN-nr-before-sr.bin` and
  `frame-NNNNNN-sr-before-nr.bin`.
- Each plane is top-left, tightly packed little-endian RGBA16F at 6144x3456,
  169,869,312 bytes (162 MiB).
- Pair size is 339,738,624 bytes (324 MiB); 300 pairs are 101,921,587,200 bytes
  (94.921875 GiB), coincidentally the same payload as the deleted old five-plane
  capture. Keep the existing 120-GiB disk, 32-GiB readback, 96-slot, 8-GiB host
  reserve, and 360-second bounds.
- Copy directly from final A/B UAV textures after all model/codec recording and
  before Present. No game/display tone mapping, PNG, screenshot, OBS frame, or
  refeed is allowed. Preview tone mapping is analysis-only and must be labeled.
- Worker thread only: fence poll, Map, direct sequential write, metadata, atomic
  terminal status. Render thread: no wait, Map, hashing, or file I/O.
- Metadata must include the one router evaluate ID, successful paired ordinal,
  service call/generation for both NR roles, all four handle identities, create and
  evaluate success counts, reset flags, original/current resource identities and
  descriptors, guide bases/formats, jitter/MV/exposure availability, source and NR
  flags, exact latched controls, signed DLL/service/router hashes, QPC/Unix time,
  and `gpu_fence_completed_before_map=true` only after actual proof.

Default production windows remain zero-based successful-paired ordinals
`256..355`, `576..675`, and `896..995` (100 each), with a metadata-only timing run
allowed to adjust them before production. They are early/middle/late points on the
continuous dual-history run, not benchmark frame numbers. Selected ordinals are
never shifted to hide a drop, reset, or failure.

The old 1510 raw planes are confirmed absent and are not input to this plan:
`paired-capture/RAW_CLEANUP_20260909.json:1-5` records the corrected reason/status;
a local count found zero remaining `captures/**/*.bin` files. Existing metadata,
previews, and reports remain untouched.

## 8. Proposed implementation units (after approval)

Only new files under `order-comparison/`:

1. `router/ngx_proxy_abi.h` — copied validated boundary ABI plus checked setters.
2. `router/order_abi.h` — versioned PRE, POST, runtime-lease, result/status structs.
3. `router/router_addon.cpp` — exact service discovery, dual Create/Release,
   duplicate-create acknowledgement, scoped parameter restoration, and five-step
   orchestration.
4. `service/common_runtime.*` — PRE-owned one-time signed-runtime bootstrap/lease.
5. `service/order_pre.cpp` — extracted **single-pass** PRE staging/codec/one handle;
   no multipass policy or post export.
6. `service/order_post.cpp` — extracted **single-pass** POST codec/one handle using
   a private allocated parameter map and borrowed runtime lease.
7. `capture/order_pair_capture.*` — two 6K planes using the proven queue/fence/writer
   state machine.
8. `tests/` — ABI sizes, exact service selection, Create call/handle pairing,
   parameter guard failure paths, state transitions, one-evaluate-per-handle
   counters, acknowledgement state machine, capture scheduling/budgets, and source
   assertions forbidding RR/FG/multipass exports/loops.
9. `Makefile` and package manifest — exactly the three uniquely named add-ons and
   hashes; capture remains explicitly off by default.

No change to signed NVIDIA DLLs, game binaries/settings, existing branches, or old
reports is part of implementation.

## 9. Verification gates and stop conditions

CPU/static gates before any game launch:

- cross-compile all three PE files with warnings enabled;
- unit/source tests prove one PRE and one POST `g_vk_evaluate` per successful frame,
  two distinct signed handles, unique exports/basenames, no RR/FG route, and no
  multipass loop/configuration;
- `objdump -p` verifies exports/imports and that PRE/POST do not export generic post
  names;
- failure-injection tests prove parameter restore on every return path and capture
  fail-closed behavior;
- byte-budget/footprint tests prove two 6K RGBA16F planes and bounded slots.

Only after those pass may the main GPU/game owner perform, in order:

1. duplicate-Create/execute-ack smoke with NR disabled;
2. 2-8 frame dual-SR equality calibration capture;
3. 2-frame full-order capture, verifying both branch counters, pointer restores,
   resource states, fence proof, finite raw planes, and no Xid/device removal;
4. a short continuous-history window test;
5. the 300-pair early/middle/late run.

Stop and produce no quality comparison if duplicate signed Create is rejected;
handles alias; any Create list lacks exact execute acknowledgement; either service
independently reinitializes/shuts down the signed runtime; original params fail
readback restoration; guide/output contracts drift; an A/B plane is not 6K
RGBA16F; either branch misses/duplicates a temporal evaluation; a reset/generation
boundary crosses a window; a fence is not after actual queue submission; or any raw
pair/drop/finite-value audit fails.

Principal remaining risks are doubled signed-SR cost/history memory, simultaneous
4K and 6K Feature-18 memory, total VRAM pressure, signed Feature-1 refusal of an
identical second instance, undocumented private parameter behavior, cross-instance
scratch/global behavior despite the documented independence contract, service
runtime-lease lifetime, and Present-thread/queue association. None is resolved by
compilation alone.

## 10. Sequential replay alternative

A separate-run replay is valid only if it records **every** source frame from the
history start plus the full signed-SR evaluation contract: all resources (including
optional exposure/masks actually present), exact pixels/subrects/states, every
scalar/private key, reset and timing order, and then replays them through two newly
created signed handles with the exact original Create contract. The current old
capture selected only three windows, omitted parts of the signed-SR contract, and
its raw planes have been removed. It cannot replay signed SR and cannot be used as
an “exact-input” alternative.

Therefore sequential disk replay is not the MVP. Unless a future contract-complete,
continuous signed-SR recorder first proves bit-equivalent replay against live SR,
the only acceptable comparison is the same-call dual-handle branch above.
