# Post-fence sparse capture alternative — 2026-09-11

**CPU/static design only. NO runtime integration, shader build, GPU/Wine/harness execution, installed changes, or GPU approval.** This is a new alternative to `nr-block70-sparse-capture-20260911`, not its in-NR-stream OWN NVX copy. Main's ORIGINAL-CUBIN own-resource probe is separate and neither implemented nor authorized here.

## Decision

**Conditionally viable, currently blocked from enablement.** After the exact first Evaluate submission completes, use a **separate private D3D12 DIRECT command list with Vulkan interop**, ordinary Vulkan compute storage reads, and a second private fence. Keep the owning feature/workspace and next-Evaluate exclusion continuously pinned. This removes the need to insert a copy or bind ordinary compute state before original finalpost; it does **not** prove that the post-fence bytes equal the bytes original finalpost read, nor repair original before-post synchronization.

The captured finalpost variant is statically **global-read-only**: main/skip/weights/blend are not global-store targets. Following identified history/frontend shaders write images; codec compose reads base/final and writes decoded. Therefore the ordinary one-layer tail has **no identified logical writer of main/skip**. But the current observer does not cover all tail commands, physical aliases, binding/free paths or private workspace ownership. **“Untouched until next Evaluate” is a conditional dataflow conclusion, not an established live lifetime/content guarantee.** Fences alone cannot close those gaps.

## 1. Baseline and exact evidence

All source paths below are relative to `../nr-swin-consumer-main-20260911/source/native/` unless qualified. Current candidate and retained run DLL both hash to:

`0efd06383925b2e41a9c84d38746317de89ef8907ebb93c03be6858ee58c2690`

Retained evidence: `../nr-swin-consumer-main-20260911/runs/20260911-155526-observer_on/`. These files were **read**, not executed. This design does not use the old proposal's `0fef…`/`5ca2…` source baseline.

- Main run is POST1, two evaluated frames, work image 768×432. First actual Evaluate has runtime `frame_id=2`, cookie=2, fence value=3; create was frame=1/cookie=1/value=2. These are **historical examples**, never future hardcoded identifiers.
- First finalpost is observer **`submission=8`**, not 1; second is 16. The observer ordinal counts selected launch callbacks, not queue submits or cookies. Its log explicitly says `before_original_not_gpu_completion`.
- `nr-kernel-args-08.bin`: 184 bytes, SHA256 `8e21f280b689ede83e243f4877b378338ce50c29b5ba177151866a55244c9c14`, byte-identical to the old sparse proposal's input. Captured `(H,W,X,Y)=(448,768,-4,-4)`, grid `(97,57,1)`, block `(32,1,1)`. Do not replace padded H=448 with image height 432.
- Exact name `cc_tinlayout_fused_post_block_swin_1h_32_fp8`; original module 3,944,768 bytes, SHA256 `c11e2eb6f6eeabadffe340dba74ec8c3f474f4ac4a8ed601d59e04d1d49bda3d`. Keep exact live module/function relation and generations, extras ABI, dimensions, first-frame/layer gates. Broader `family()` acceptance is insufficient.
- Metadata reports workspace size 32,562,176, generation 3, main buffer offset 19,389,440, skip offset 121,856. Separate weight pool size 147,719,680, generation 1, slab offset 147,429,888 and blend offset 147,429,376. Historical addresses/handles are never usable live pins.
- Both source buffers have `usage=0x20032`: STORAGE `0x20`, UNIFORM `0x10`, TRANSFER_DST `0x2`, DEVICE_ADDRESS `0x20000`; **TRANSFER_SRC `0x1` absent**. No source usage modification or `vkCmdCopyBuffer` is permitted.

`evidence/SOURCE_PINS.json` pins inspected source/artifacts. `evidence/STATIC_CHECKS.json` rebases the old exact readset onto Main's firstpost metadata, explicitly without capture authorization.

## 2. What survives the original tail?

| Stage | Static evidence | Consequence / boundary |
|---|---|---|
| Exact original finalpost | `../nr-static-followup-main-20260911/finalpost-original.ptx`: no global/generic store, global atomic, reduction, or call; two `sust.p.2d.v4.b32.zero` stores, lines 14126/16261, surface from argument +0x10. Selected original SM120 SASS has two SUST and no STG/ATOM/RED. | Main +0x00, skip +0x08, slab +0x18, blend +0x68 are read-only global inputs in this artifact. Surface backing must not alias them. Static artifact identity is not proof of driver-selected native/JIT execution or cache semantics. |
| NR history/frontend tail | `../nr-vulkan-sampling-history-20260911/REPORT.md`, §3–4: wrapper `0x1800228aa..2932`, outer `0x1800198ab..19907`, helper `0x18001c650`; conditional network Output/H+60/H+70 image routing. Original module14 `cg2r_copy_kernel` PTX has one surface store only; module13 `cg2r_post_process_kernel` has two surface stores plus shared stores. | Identified GPU tail shaders do not write global workspace pointers. History copy is a shader, not established byte identity. Conditional routing, physical image/buffer aliases, other commands and host-side allocator/free actions still require audit. |
| Wrapper codec/commit | `runtime/pipeline.cpp:502–581`, `runtime/codec.cpp:146–267`, `shaders/codec_decode.comp`: encode precedes NR; compose descriptors sample snapshot/base/final and only store decoded; commit copies decoded into owned harness output. | No raw main/skip workspace resource is passed to codec/commit. Base and final ping are read-only during compose. D3D12 chain textures are independently committed, but that alone is not proof about signed NR's raw buffer bindings. |
| Other layers / next Evaluate | `pipeline.cpp:509–543` runs all passes, ping-pongs outputs; `configure()` can request reset and next Evaluate re-encodes base and invokes NR. | Bound scope is **one Chain, one layer, first successful Evaluate**, no further create/evaluate on owned device until private fence/staging. Multiple layer handles do not prove private workspaces. |
| Between calls / release | Chain stores raw NGX handles/parameters, not VkBuffer/VkDeviceMemory owners (`pipeline.cpp:15–63,586–609`). `release_chain` calls `b.release`; retire worker may run once original fence completes. | Keeping a `Chain*` or COM device reference is not a workspace pin. No NGX handle AddRef exists here. Main trace ends with weight-buffer retire events, demonstrating that old address metadata is not permanent ownership. |

The observer's `family()` excludes history-copy/frontend kernels; it also does not intercept every Vulkan command, free, sparse bind, host write or resolver bypass. Thus absence of a logged tail write proves nothing beyond its coverage. A complete native tail/allocator audit or complete observational coverage must establish no selected-range overwrite/free **during the original Evaluate itself**, not merely freeze calls after return. Specifically include every later dispatch and its write footprint, `vkCmdFillBuffer`/`vkCmdUpdateBuffer`/buffer-copy destinations, aliasing image writes, clear/reset launches, mapped host writes, and allocator/suballocator recycle/free on all reachable return paths. Seeing `cc_cb_clear` as the next selected callback does not prove it is the next command or locate its frame without the ticket bridge. Even allocation lifetime alone does not prevent scratch suballocation reuse within a still-live VkBuffer.

**Capture semantics:** if nonalias + unchanged bytes through the tail are proved, the post-fence payload is the surviving firstpost input boundary. If not, it is only an end-of-frame workspace snapshot and must not be labeled actual firstpost input. Even with unchanged bytes, original `.ca`/`.cg`/weak loads and unsupported NVX visibility may have observed different/stale values; capture cannot retroactively attest original operand values or producer→finalpost correctness.

## 3. Required ownership proof (not bufferCreate metadata)

`runtime/finalpost_buffers.inc:1–190` tracks create/destroy and core/KHR/EXT buffer-device-address calls on two supplied resolver routes. The record contains handle/generation/size/usage/base, **not** memory, binding offset, allocation generation, sharing mode or family. Its own `lifetime_routes_ready()` means create/destroy wrappers available, **not memory lifetime proven**; `in_flight==0` is only an instant, not a lock against the next driver call.

Before a future private capture may record, require either:

1. **Complete observational attribution plus enforceable owned-call exclusion:** successful `vkAllocateMemory`/`vkFreeMemory`, `vkBindBufferMemory`, `vkBindBufferMemory2` and KHR aliases, memory requirements/type/size, memory object generations and binding offsets, buffer lifetime/address aliases, and relevant image bindings/imports to exclude physical aliasing. Observe before retirement/free forwarding; retain sticky uncertainty on overflow, missing calls, unknown pNext, unexpected resolver or in-flight callback. Reject sparse/external/imported/ambiguous memory, overlapping aliases and untracked queues. Allocation/binding observation is not permission to block someone else's free; private ownership must exclude such calls **before commands are issued**.
2. **Equivalent audited private ownership:** pinned signed-NR host allocation/destruction paths must establish that these exact workspace/pool ranges are owned by this exact feature generation, never freed/recycled/CPU-written until the excluded next evaluate/reset/release/shutdown, never shared with another feature/background task, and have the required live binding and queue ownership. Document relevant private suballocator lifetime too. Raw feature-handle retention alone is insufficient. This review has **not** proved that contract.

At arm and immediately before recording, revalidate `(owned device, buffer handle/generation, address interval, size/usage, allocation handle/generation, binding offset/generation, sharing/family, suballocation/content epoch)`. Resolve **every entire span uniquely**, including aliases starting inside it, with checked uint64 addition/subtraction and containment. Unique virtual-address matching alone misses physical-memory aliases. Loss of proof before recording refuses capture; loss after possible submission quarantines and preserves resources. Detection after an unsafe read is too late to call the design safe.

## 4. Continuous runtimeMutex / featureLifetime lease

These are design roles, **not existing fields**: candidate's runtime mutex is `g_lock`; `Backend::lock` only covers initialization; the observer has `s.lock`. None is currently a multi-call capture lease.

- Install a one-shot private owner/device lease **under `g_lock` while admitting the first Evaluate**, before its `b.evaluate` callback and before Execute returns. Scope: one owned static offscreen POST1 process. Original current Evaluate may finish normally; no subsequent Evaluate/create/reset/drop/retire/release, gate/reset-epoch mutation or device/backend teardown may proceed until disposition. Acquiring a mutex only after first fence completion leaves a next-Evaluate race and is rejected.
- Add a private monotonically generated Chain/feature/content epoch. A reused `g_chains` slot or owner ID is not identity. Store exact layer handle, parameters and generation; pin resource owner, not just the pointer. A future private retirement predicate must include this lease: today's `last_fence` only covers original work and would permit `release_chain` while the second list is running.
- Under the existing `g_lock`, install a non-reentrant RAII thread-local Evaluate context around **layer 0** `b.evaluate`, containing ticket `(cookie, exact list, list-recording generation, cb, owned device, Chain/feature generations, owner, frame, gate/reset generations, kind=Evaluate, layer=0)`. Observer snapshots only host args and immutable buffer facts; no added GPU commands in original stream, no additional NVX launch, no argument edit. Callback on another thread/nested context/no context fails capture.
- Lock order: runtime `g_lock` → short private/observer snapshot lock. Observer callbacks must **not reacquire `g_lock`** while Evaluate owns it; real driver dispatch remains outside `s.lock`. Do not hold runtime/observer locks while waiting fences, doing file I/O, or holding interop queue locks. Use lease state to preserve exclusion across unlock, submit and wait. No long locked wait that deadlocks Submitted/retire.
- In this owned harness-only proposal, conflicting requests are rejected before any mutation or the capture is cancelled before exposure with explicit proof. Never let a generic failure path mark/release the Chain underneath an active bundle. Any **actual** reset/drop/free/rebind/coverage loss/retire conflict after exposure is terminal quarantine; do not pretend an old reset return code proves unsubmitted. Keep owner/device/library/list resources until safe completion or isolated process exit. No retry/rearm; no production game-hook adaptation.

## 5. Exact two-submission sequence

### A. Original list: untouched recording, exact receipt

Established candidate path:

- `pipeline.cpp:313–343,481–505`: reserve `Pending`, assign nonzero cookie and exact D3D12 list, call host track **before** original copies/interop/evaluation.
- `pipeline.cpp:575–582`: `Pending.full_success/frame_id` set only after all layers, compose, EndInterop and output commit succeed.
- `pipeline.cpp:751–805`: Submitted matches cookie/list, success/fence/nonzero value, and queue COM identity. It stores latest retirement fence and maybe an older completion sample, then **clears Pending**. Return 1 is bookkeeping, not GPU completion; runtime does not itself prove Signal followed Execute or fence device identity.
- Main `harness/probe.cpp:137–143,364–375`: exact list/device/cookie tracking; close → ExecuteCommandLists(original list) → Signal(original fence,value) → Submitted(exact tuple) → bounded wait rejecting UINT64_MAX. Existing code immediately clears cookie, later resets allocator/list at line 401.

Required private bridge: consume the successful matching Pending/Submitted pair **before clear_pending**, require full-frame/generation agreement and audited owned harness Execute→Signal provenance, independently verify queue/list/fence/device COM identities, and AddRef the exact original queue and **F1/value**. Include list recording generation; pointers can be reused. Retain receipt privately, not via `Chain.last_fence`, sampled completion, query counters, latest cookie, callback ordinal or caller-supplied `completed=true`.

Keep frozen runtime exports/ABI structs and reserve policy unchanged: any future harness control is a new isolated debug-only entrypoint/private side table, not new meanings for old fields or sampled Query proof. Future private harness entrypoint goes **after the first actual Evaluate's exact wait at line 375, before cookie=0/list Reset/next Execute**. It must repoll its internally retained F1 and reject `UINT64_MAX`. A successful create fence, unrelated fence with a larger number, next-frame fence, failed/partial recording, reset or missing Submitted never authorizes this step. Original receipt establishes original completion only; no host access to the later diagnostic destination yet.

### B. Private storage-read list: new state, second fence

After F1 completion and final lease/binding/tail/visibility preflight:

1. Retain the **same owned D3D12 DIRECT queue accepted for original submission**, same device/interop object and underlying VkQueue/family. Query `GetVulkanQueueInfo`; independently audit no queue remapping/split relevant to these source accesses in staged interop. No new Vulkan queue, separate D3D12 COPY queue, naked `vkQueueSubmit`, device-idle flush or external raw VkCommandPool. A DIRECT list is required because this “copy-list” performs compute.
2. Create private allocator/list using existing `ID3D12DXVKInteropDevice1` contract (`runtime_internal.h:46–63`): `CreateInteropCommandAllocator(DIRECT, audited family selection, ...)`, `device->CreateCommandList(DIRECT, private allocator, ...)`, then BeginVkCommandBufferInterop(private list). Choose family/default semantics from the **staged implementation**, not guesswork. Upstream reference test uses `VK_QUEUE_FAMILY_IGNORED`; it is supporting API-shape evidence, not a staged binary contract or queue-family proof.
3. Vulkan cb/pool belong to the interop allocator. Only record between successful Begin/End; do not independently begin/end/reset/free that cb or reset/destroy its pool. Only one thread uses list/allocator; keep them and the interop object alive through F2. Bind **all** private pipeline/descriptors/push constants on this private cb; never restore guessed NR state. Main's original list is already closed/completed and receives no additional commands.
4. Use private real dispatch from **the same owned Wine/Vulkan device handle namespace** already exposed by `Backend.gdpa`, with recursion excluded. Never mix native loader handles or return original observed buffers as OWN objects. Ordinary compute descriptor/SPIR-V modules, pool/sets/layout/pipeline and destination belong exclusively to this bundle.
5. Record candidate dependencies below, bounded span dispatches, host barrier; EndInterop, Close(private list), ExecuteCommandLists(**that** private list) on retained queue, then Signal a **new private D3D12 fence F2** value 1. No original runtime `SubmittedV1` cookie reuse: private list has its own internal capture/list generation and accepted Execute→Signal receipt. Check End/Close/Signal and object/device identity; ExecuteCommandLists has no success HRESULT, so failures/removal/uncertainty require quarantine, not invented success.
6. Submission uses D3D12 queue machinery, not manual Vulkan queue submission. `LockCommandQueue` is for audited direct queue access, not an automatic lock to wrap D3D12 Execute/Signal (which could recurse/deadlock); do not hold it while invoking D3D12 submissions. Single owned host submitter plus interop implementation must establish queue host synchronization. Exact staged lock/family/command-pool implementation remains an audit blocker.
7. Poll internally retained **F2/value**, with deadline and UINT64_MAX rejection. Before completion: no Map/read/payload disk, no private allocator/list reset/destruction, no feature release/next Evaluate. Missing/failed private signal after Execute is ambiguous in-flight work: retain bundle + owner lease to process exit, never reclaim on the already-complete F1.
8. After F2 completion and proof still intact, Map **only OWN coherent destination**, copy precisely packed payload into CPU staging, Unmap. File I/O outside runtime locks; CREATE_NEW in private non-reparse directory, exact lengths/hashes, completion manifest last. Record both receipts/values, generations, args/module hash, ranges, unknown blend padding, `postfence_surviving_bytes` semantics and remaining NVX caveat. No successful capture on Map/short-write/close/manifest failure. Release exclusion only after safe staging and explicit completed disposition; one-shot quarantine is retained on uncertainty.

The saved upstream interop test is read-only reference code, not imported or run. Its exact commit/URL/hash is in `evidence/NETWORK.json`; it demonstrates allocator/Begin/End API use, **not** a recipe to copy its test reset/idle behavior. Candidate's declarations are insufficient to establish all staged interop ownership details.

## 6. Legal ordinary Vulkan storage reads and remaining memory dependency

**No added source flags, no source transfer copy, no OWN NVX/CUDA kernel.** A storage-buffer descriptor is legal given existing STORAGE usage, a valid live binding and required limits. Device address is used only for checked CPU integer attribution of original arguments; the new shader needs neither buffer-device-address instructions nor shaderInt64.

Private shader design (not implemented): read-only source SSBO of uint32 words → write-only OWN SSBO, guarded by exact span word count; all words copied once, no vector overread, atomics, texture/surface read, conversion, source store or speculative padding read. One dispatch per span, constants `(src_word_delta,dst_word_offset,word_count)`; use explicit descriptor ranges and validate the compiled SPIR-V accesses in any later implementation.

For source descriptor offset, align down the actual buffer-relative span start to `minStorageBufferOffsetAlignment`, use checked `delta=span_start-descriptor_offset`, and range `delta+span_bytes`, bounded by buffer size and `maxStorageBufferRange`. Shader reads only `[delta,delta+span_bytes)`; descriptor padding is not a dump permission. Check 4-byte alignment, range/dispatch/push-constant limits and descriptor counts. Bindings/ranges must remain immutable through F2.

OWN destination: STORAGE usage only suffices; dedicated bounded allocation bound to a compatible HOST_VISIBLE|HOST_COHERENT type selected through memoryTypeBits. No TRANSFER_SRC/DST or DEVICE_ADDRESS required. Proposed payload/allocation cap 32 KiB, **including actual memory requirements/alignment**; refuse absent coherent type or requirements above cap, no hidden larger/noncoherent fallback. Account pipeline/descriptor overhead separately with unchanged reserve and explicit bounded admission. Destination cannot alias any source. No CPU initialization or early Map is necessary.

CTA `(1,1)`, unchanged old manifest (relative to each captured argument):

| Source | Offsets | Span bytes | Packed total |
|---|---|---:|---:|
| main | 12320,18464,24608,30752,1388576,1394720,1400864,1407008 | 64 each | 512 |
| skip | 98816,197120 | 1024 each | 2048 |
| slab | 0 | 21808 | 21808 |
| blend, optional OFF | 0 | 4 | 4 (only bytes 0–1 valid) |

Default **11 spans / 24,368 bytes**; optional 12 / 24,372. No holes, workspace/pool dump, allocation tails, full activation capture or invented padding. Fixed one tile/first frame/one attempt. Off path must remain the original pointer-identical forwarding once, with no new allocations, bridge actions or GPU recording.

Candidate private-cb barriers, **conditional on verified same-VkQueue submission ordering and NVX participation**:

```
// After host observes original F1. Original pre/post barriers remain unchanged.
ALL_COMMANDS / MEMORY_WRITE -> COMPUTE_SHADER / SHADER_READ
    // device memory dependency covering original source producers, including aliases
private ordinary compute reads exact source spans -> OWN destination
COMPUTE_SHADER / SHADER_WRITE -> HOST / HOST_READ  [OWN destination payload]
EndInterop; Close; Execute(private list); Signal(F2); wait/poll exact F2;
Map OWN HOST_COHERENT allocation; CPU staging; Unmap;
```

Use queue-family IGNORED in barriers **only after same-family ownership is proved**; otherwise this proposal refuses rather than improvising ownership transfer. Same queue plus a valid cross-submission memory barrier can cover earlier **standard Vulkan** writes. HOST_COHERENT removes the need to invalidate mapped ranges after correct synchronization; it does not manufacture execution/visibility or make Map a wait.

**Hard unresolved caveat:** public `VK_NVX_binary_import` still states there is no specification language for `vkCmdCuLaunchKernelNVX`. There is no audited NVX stage/cache contract here. F1 proves execution completion under the accepted interop fence mapping; it does not prove NVX writes became available/visible to ordinary Vulkan compute, clear stale CUDA/global/texture caches, fix producer publication, or guarantee that original finalpost consumed current main/skip. ALL_COMMANDS/MEMORY_WRITE is conservative intent, **not vendor proof**. F2 plus own compute→HOST barrier only closes the ordinary compute destination side once the interop fence mapping is audited. Do not claim fences alone solve GPU memory dependencies.

## 7. Optional smaller D3D12 tile readback: source A / layer-visible P1

This is a separable, **default-off** diagnostic option, not a replacement activation capture or a raw finalpost-surface attestation.

- `c.base` is encoded source A, **not the unencoded original input image**. `configure()` layer0 selects it as Color. `c.ping[0]` is requested layer1 output (P1). With one pass, compose samples both and does not overwrite them. NR's conditional history routing may produce P1 via a later shader copy; therefore P1 is layer-visible output, not necessarily byte-identical to the finalpost's direct surface stores. Prove current A/output handle mapping if making semantic claims.
- Success path restores `c.base` to NON_PIXEL_SHADER_RESOURCE (`codec.encode`) and both pings to UNORDERED_ACCESS (`compose` restores final; `pipeline` restores non-final temporary reads). Original EndInterop must succeed. For POST1, separate private **DIRECT D3D12-only** list can transition base NPSR→COPY_SOURCE→NPSR and ping0 UAV→COPY_SOURCE→UAV around bounded CopyTextureRegion into OWN readback footprints. No interop split inside NR. Never transition raw Vulkan activation buffers as D3D12 resources.
- Retain AddRefs to these independently committed chain textures and prevent next Evaluate/retire with the same lease; validate exact format RGBA16F, dimensions, mip/subresource/sample count, no aliases and states. AddRef keeps texture objects alive but does not prevent subsequent writes. More than two passes can overwrite ping0 with a later layer; default POST1 avoids this entirely.
- Define one explicit in-bounds physical-image ROI, e.g. at most 16×16 per texture: ≤4,096 packed bytes for two RGBA16F tiles. Derive selected source-A sampling footprint and P1 store coordinates independently before claiming the ROI covers CTA(1,1); **do not equate padded tensor coordinates with image pixels**. Until that mapping is proved, label only physical ROI data, not complete tile replay input/output.
- Compute valid tile-sized placed footprints (format, width/height, 256-byte row pitch alignment, 512-byte placement alignment, allocation bounds) and source box. Destination READBACK heap stays COPY_DEST. Map only after the private list's own exact F2; write only `width*8` bytes per row, omit row/placement padding. Do not call full-texture GetCopyableFootprints then claim tile-sized allocation automatically. Source states restored before submission completion; unknown before-state means refuse, not COMMON/promotion guesswork.
- Reuse `../cinematic-layer-capture-runtime/native/runtime/diagnostic_capture.inc:100–110,179–243` **patterns only**: before/after transitions, exact fence retention, removal/deadline quarantine, Map on worker after proof, tight rows/CREATE_NEW. Do **not** transplant its POST5/eight-full-image allocations, two-attempt lifecycle, or `capture_interop` End/Begin split at lines 116–147. Those would reintroduce original-stream disturbance and are unnecessary after the original list ends.

D3D12 resource-state/interop/NVX producer visibility must also be proved for image reads; F1 alone is no exemption. This option has simpler explicit COM ownership than raw NR workspace, but current static source does not authorize running it.

## 8. Verification and bounded next handoff

CPU checks run:

```
python -B reviews/nr-postfence-sparse-capture-design-20260911/verify_static.py
python -B reviews/nr-postfence-sparse-capture-design-20260911/test_lifecycle_model.py
```

Static checks pass: candidate0efd/run identity; exact Main args equal old readset; bounded spans/usage arithmetic; PTX store inventories and selected SASS no-global-store check. **14 model tests pass**, including every missing proof, all ticket field mismatches, early/wrong/create receipts, first-fence-only read, private list/fence/queue mismatch, removal, lease exclusion, duplicate receipts, observed free/generation invalidation, timeout and I/O failure. `Proofs()` defaults to all false. Synthetic all-true tests demonstrate desired ordering only; the model implements no real locks, API calls, ownership discovery or GPU memory semantics.

Remaining before any implementation proposal: (1) exact native tail/suballocation/nonalias/lifetime audit or complete bind/free observation plus private exclusion; (2) actual private ticket and retirement-lease bridge tests; (3) staged interop queue/family/pool/fence ownership audit; (4) NVX producer→ordinary compute visibility contract; (5) exact source/destination limits/admission and optional image mapping. Any unresolved item means **do not record**. No GPU approval is conferred by this review or by Main's separate ORIGINAL-CUBIN probe.
