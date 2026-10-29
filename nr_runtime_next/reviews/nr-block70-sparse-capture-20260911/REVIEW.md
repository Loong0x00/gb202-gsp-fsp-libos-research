# Block70 ONE-TILE sparse capture — CPU-only proposal

**Status: design-only, NOT integrated, NOT GPU-tested, NOT experiment approval.**
Main must review before any GPU execution. This package deliberately contains no modified runtime DLL, harness executable, loader hook, or GPU runner. The shader is compiled, not loaded. No activation/output payload has been captured here.

## Decision and delivered scope

Use an OWN `nr_sparse_copy_v1` sm_120 CuBIN, launched through the original NVX function pointer, for GLOBAL loads from already-valid storage/device-address buffers into one OWN host-visible/coherent/storage/device-address buffer. Never add flags to observed buffers; never use `vkCmdCopyBuffer` on them. No texture/surface reads, GPU-address-to-CPU casts, VRAM scan, allocation-sized dump, or ordinary Vulkan compute pipeline binding.

The current observer does **not** prove the recording-to-fence bridge or bound-memory/queue lifetimes. NVX's public specification also leaves synchronization/state semantics unspecified. Therefore I stopped before wiring GPU recording. Deliverables are an executable CPU policy/lifecycle model, exact sparse manifest, own compiled shader and negative tests, plus the explicit integration contract below. Tests of the model are not tests of a future runtime implementation.

First scope: CTA `(1,1)` sparse inputs plus full 21,808-byte weight slab. Four-byte blend capture is optional, disabled by default; only bytes 0–1 are semantically valid, bytes 2–3 are unknown padding. **No output/P1 capture.** Image/sampler ownership, layout and output store mapping have not been proven. This cannot yet validate the final output pixel; it supplies the real numerical input boundary for CPU block70 replay once an authorized capture exists.

## Evidence and exact read set

Selected read-only baseline: **`../nr-vulkan-buffer-observer-20260911/source/`**, the worker's normal-reserve observer. Its `native/buffer-build/dlss5-native-runtime.dll` and the retained Main run DLL both actually hash to `0fef444c8461b2cf6faeabfd429ff8020064394bd7186cb0710cafbb8f54d24b`, matching the run `INPUT_HASHES.json`. `native/common/control.h:158` retains `max(budget/10, 1 GiB)` reserve. No reserve, old export, ABI struct, original PTX or production file was changed.

**Provenance finding:** the current Main `source/native/build/dlss5-native-runtime.dll` is now `5ca25ef7e0a5065c515324815a34fbf5ddf04a9eae436cc3882139498ed15f10`, not the retained run's `0fef…`. Its observer source has unrelated later pre-block 264-byte capture support and renamed `nr-kernel-args` files. These changes were preserved, not reverted or used as the final baseline. Main/worker `pipeline.cpp`, `control.h`, `finalpost_buffers.inc` and `native_runtime.h` compared byte-identical; initial lifecycle inspection of Main therefore remains applicable. Final baseline mock tests use the worker source. Both provenances are pinned.

Primary evidence: `../nr-block70-buffer-main-20260911/runs/20260911-141443-observer_on/finalpost-trace-v1.log`, submission 1. That number is an **observer launch ordinal, not a runtime cookie or completion proof**. Host arguments are `finalpost-args-01.bin`, SHA-256 `8e21f280b689ede83e243f4877b378338ce50c29b5ba177151866a55244c9c14`.

| Source | Observed allocation | Base | Buffer-relative argument offset | Generation |
|---|---:|---|---:|---:|
| main0 | 32,562,176 | `0x245e0000` | 19,389,440 | 3 |
| enc0skip | same workspace | same | 121,856 | 3 |
| weights | 147,719,680 | `0x12c00000` | 147,429,888 | 1 |
| blend | same pool | same | 147,429,376 | 1 |

Usage `0x20032` = STORAGE `0x20` + UNIFORM `0x10` + TRANSFER_DST `0x2` + SHADER_DEVICE_ADDRESS `0x20000`; **TRANSFER_SRC `0x1` is absent**. Observed addresses are historical evidence only, never future hardcoded GPU pointers. Even the log's two matching main/skip pointers do not make all four inputs one allocation.

`src/evidence_plan.py` calls the pinned `nr-ptx-prefix-20260911/layout_reference.input_read_set` with the captured 184-byte aggregate and CTA `(1,1)`. It deduplicates/merges only overlapping or touching intervals; predicate-zero paths remain absent reads, never zero-filled fabricated observations. Captured H/W/origin are `(448,768,-4,-4)`; CTA-adjusted coordinates are `(4,4)`. The harness's work-image height is 432, **not** the kernel's captured padded H=448.

| Source | Relative byte offsets | Bytes at each offset | Packed bytes |
|---|---|---:|---:|
| main | 12320,18464,24608,30752,1388576,1394720,1400864,1407008 | 64 | 512 |
| skip | 98816,197120 | 1024 | 2048 |
| weights | 0 | 21808 | 21808 |
| blend (optional) | 0 | 4 | 4 |

Default: **11 spans, 24,368 bytes** (2,560 input bytes + 21,808 weights). With blend: 12 spans, 24,372 bytes. Do not copy the main span's 1.4 MiB holes, skip gaps, workspace, pool or destination allocation padding. `evidence/READSET.json` records every source-relative, buffer-relative and packed destination offset. Its synthetic coverage flags are explicitly counterfactual: static range arithmetic, not live-capture authorization.

## Preflight: all conditions required BEFORE recording anything

1. Separate exact opt-in: `D5R_FINALPOST_SPARSE_CAPTURE=OWNED_STATIC_OFFSCREEN_ONE_TILE_V1`. This is a **proposed/model gate**, not an active runtime feature. It neither implies nor replaces `D5R_FINALPOST_TRACE=OWNED_STATIC_OFFSCREEN`. Wrong/absent value returns directly to the existing original forwarding path, with no allocations, capture callback, barriers, launch mutation, or additional GPU commands. One process-owned device, one capture, first eligible layer-0 finalpost, no retries/rearm or additional tile selection.
2. Exact live function name `cc_tinlayout_fused_post_block_swin_1h_32_fp8`, module hash `c11e2eb6f6eeabadffe340dba74ec8c3f474f4ac4a8ed601d59e04d1d49bda3d`, module size 3,944,768, live function→module relation and generations, same owned device. Do not authorize by `family()` or the observer's broader legacy hash allowlist. Unknown/destroyed/reused handles fail capture.
3. `VkCuLaunchInfoNVX` x64 size 88, expected sType, null pNext; grid `(97,57,1)`, block `(32,1,1)`, shared=0. Only `paramCount=0, extraCount=1`; safely snapshot FIVE host pointer words `[1,arg_buffer,2,&size_t_bytes,0]`, size exactly 184. The host reader must bound/check the two pointed host spans and full aggregate. No aggregate addresses are host-dereferenced. Reject pParams-only variants. H/W/origin must match exactly.
4. Sticky-complete observation coverage from owned initialization: create/destroy and all actual address resolver aliases, no capacity loss, unknown extension, changed original procedure, unknown lifetime, sparse buffer, other device or in-flight callback. For every argument base **and every copied interval**, require one unique live allocation, nonzero generation/base, checked uint64 arithmetic, STORAGE+DEVICE_ADDRESS usage, complete containment. Reject *any intersecting alternate interval*, including overlap starting in the middle of a read span. Revalidate immutable `(device,handle,generation,base,size,usage,binding_generation)` immediately before recording.
5. The present `finalpost_buffers.inc` observes create/destroy/address, not memory bind/free or queue-family ownership. It is metadata attribution, not a pin on Vulkan memory. A future bridge must cover successful bind/bind2 aliases and memory allocation/free (or provide an equally strong audited private ownership proof), reject sparse/external ambiguous aliases, and establish memory/queue lifetime through the captured list's fence. Never block/alter application frees to fake ownership. An unlocked snapshot followed by a driver call is not a lifetime guarantee. A generation race detected only after issuing an unsafe command is too late: unresolved lifetime means **do not inject**.
6. Resolve all OWN create/destroy/bind/address/launch/barrier/Map operations from the same owned device using private real dispatch, with recursion excluded. Prepare OWN module/function and destination **before entering the launch wrapper**. New compiler metadata/global descriptor ABI must be accepted by the target NVX import path; native compilation alone does not establish this.
7. Destination usage exactly STORAGE+DEVICE_ADDRESS is sufficient; own allocation must use `VK_MEMORY_ALLOCATE_DEVICE_ADDRESS_BIT`, compatible memoryTypeBits with HOST_VISIBLE|HOST_COHERENT, successful binding and queried device address. Reject absent coherent type; no automatic transfer/noncoherent fallback. Propose at most 32 KiB buffer/allocation budget, respecting actual memory requirements/alignment; reject if requirements exceed the cap. Account this and own module overhead **in addition to**, not instead of, the unchanged reserve. No CPU Map for initialization: each output payload byte is overwritten by the copy shader; host launch packets need no GPU descriptor/upload buffer. Verify destination cannot alias any source allocation. Never dump the allocation tail.

The model represents these proof inputs explicitly; it cannot discover them. `Coverage()` defaults to refusal. Historical trace-derived buffers in the manifest use counterfactual proof inputs solely to calculate ranges.

## Own shader and recording sequence

`src/sparse_copy.cu` is new code. CPU `nvcc 13.3.73 -arch=sm_120` produced a 6,336-byte native CuBIN and PTX 9.3. No original module/PTX was modified or version-downgraded. Inline `ld.global.u32`/`st.global.u32` compile to `LDG.E`/`STG.E`; no texture/surface or atomics. Own kernel ABI is **24 bytes**, distinct from original's 184: `<QQII>` source VA, owned destination VA, count, reserved=0; CuBIN parameter metadata offsets 0/8/16/20. One OWN NVX launch per span, grid `(1,1,1)`, block `(128,1,1)`, shared=0. Source/count/destination are aligned to 4, no overread tails, count≤21808. Warp lanes read consecutive words. The kernel additionally rejects wrong dimensions/alignment/count/reserved.

Proposed sequence, on the exact already-recording VkCommandBuffer and outside any render pass:

```
preflight everything; retain immutable private RecordingTicket and all OWN resources
VkMemoryBarrier: ALL_COMMANDS / MEMORY_WRITE -> ALL_COMMANDS / SHADER_READ
for each validated span:
    real_vkCmdCuLaunchKernelNVX(cb, own_copy_launch)  // 24-byte host extras ABI
// Explicit GPU execution dependency: later original/workspace writes cannot race reads.
VkMemoryBarrier: ALL_COMMANDS / (SHADER_READ|SHADER_WRITE)
                 -> ALL_COMMANDS / (MEMORY_READ|MEMORY_WRITE)
// Visibility of exactly the owned buffer's used payload to the host.
VkBufferMemoryBarrier(own_dst, payload_range):
    ALL_COMMANDS / SHADER_WRITE -> HOST / HOST_READ
real_original_vkCmdCuLaunchKernelNVX(cb, original_info_pointer) // unchanged, once
```

No `vkCmdBindPipeline`, descriptor binding, push-constant edit, interop split, image transition or ownership transfer. Queue-family indices for own buffer barrier are IGNORED **only after same-queue ownership is proven**. The extra post-copy GPU dependency matters: HOST visibility alone does not necessarily serialize later original device accesses with diagnostic source reads. Pre/post barriers and copies must precede the original finalpost0 call; no early input Map/read/disk. Existing original launch info, pParams/pExtras and aggregate remain byte- and pointer-identical; original exceptions/failures are not reported as capture success.

**Unresolved NVX contract:** local Vulkan headers expose no NVX-specific pipeline-stage bit. Public `VK_NVX_binary_import` documentation explicitly states there is no specification language, only stubs. Using ALL_COMMANDS instead of inventing a CUDA/NVX stage is conservative, but does not itself prove how NVX GLOBAL loads/stores participate in Vulkan barriers or preserve normal compute bindings. These need target implementation/vendor evidence before runtime enablement. The newer `VK_NV_cuda_kernel_launch` API is not a drop-in substitute. The saved public extension document and source URL are below.

## Exact recording → Submitted → fence → host proof

### What is locally established

- `source/native/runtime/pipeline.cpp:313–343`: `reserve_pending` stores nonzero cookie, chain, exact D3D12 list, kind and gate/reset generations; `track` passes that cookie/list/device to the harness before recording.
- `pipeline.cpp:481–583`: `evaluate` reserves Pending before `BeginVkCommandBufferInterop`; obtains `cb`, runs `b.evaluate(cb,...)` per layer, and marks `full_success/frame_id` only after full normal evaluation/EndInterop/output commit.
- `pipeline.cpp:751–800`: `SubmittedV1` matches cookie and exact list, checks success/fence/value and queue COM identity, AddRefs fence, then clears Pending. Chain `last_fence` may be replaced. Chain `completion_fence` deliberately samples an older frame. **Neither field is an exact capture fence.**
- `harness/probe.cpp:138–141,354–375`: harness tracks exact list/device/cookie, closes/submits that list, signals its owned queue *after ExecuteCommandLists*, invokes `SubmittedV1` with that cookie/list/queue/fence/value, then waits. This is a usable future Main harness path, but the observer is not connected to it today.
- `source/native/host/queue_hooks.cpp:216–294`: production host has a similar post-forward Execute→Signal→Submitted route, with device matching. Do not broaden this proposal to game hooks.

### Proposed private bridge (NOT implemented)

1. Under existing runtime `g_lock`, after obtaining cb, install an RAII per-thread layer-evaluate context immediately around layer 0 `b.evaluate`. Capture the complete ticket `(cookie, exact list, private list-recording generation, cb, owned device, owner/chain generation, frame, gate/reset generations, kind=evaluate, layer=0)`. The observer launch wrapper may consume only this matching context, once. Clear it on every return/failure. An NVX callback on another thread, reused cb, nested evaluation or no context means skip capture. **Never infer list/cookie from callback count, frame timestamp, latest chain, cb address alone, or the log's `submission=1`.** Enforce nonwrapping private ticket generations.
2. Capture resource retirement is a separate private bundle keyed by the ticket, not an extension of frozen structs. Record completion of *all* planned copies and barriers; partial or uncertain recording makes the bundle quarantined, never eligible for host read. Existing original launch still forwards exactly once. Do not reacquire `g_lock` from an observer callback while `evaluate` holds it; define one lock order and snapshot handoff, avoid driver calls/file I/O under observer locks.
3. Inside the existing `SubmittedV1` implementation, before `clear_pending(p)`, provide a **private side-observation** of the already-validated matching Pending/Submitted pair to this bundle. Do not change old validation, return values, frozen structs or old exports. Independently require complete ticket agreement, one-owned-device queue/fence COM identities, same queue that executed the list, signal-after-execute provenance, no reset/drop, full evaluate success and no chain/lifetime uncertainty. AddRef the exact fence/queue objects and retain the exact value in the bundle; never substitute latest/sample fence. Incorrect cookie/list cannot consume another bundle's fence. Unmatched observations cannot authorize a capture; deadline on missing matching acknowledgment quarantines it.
4. Reset/drop/release/retire/failure paths must notify the private bundle **before** clearing Pending, with original export semantics intact. Current Reset matches cookie only; do not promote it into proof of safe unsubmitted resource release. Any ambiguity, wrong cookie/list/generation, duplicate ack, failed signal, exception or missing notification quarantines/retains the bundle. Do not release submitted/copy resources, module or function while inflight; no wait-on-destroy, guessed idle or destructor-based flush.
5. Prefer a **new isolated debug-only export**, e.g. `DLSS5_DebugFinalpostSparseFlushV1(uint64_t cookie)`, in a future isolated clone, rather than transplanting POST5 capture worker special cases. Main calls it after successful original Submitted and its exact harness wait, **before clearing its saved cookie or resetting/reusing the list**. It must use only the bundle's internally AddRef'd accepted fence, never caller-supplied fence/completion or a new empty submission. Poll `GetCompletedValue()` again: `UINT64_MAX` is device removal, not completion; value<target returns pending with no host access. Export is nonblocking, performs no submission/signal/wait, refuses wrong/zero cookie. Proposed new-only statuses: 0 unavailable/refused, 1 pending, 2 completed-and-saved, 3 quarantined. Existing structs/exports remain frozen.
6. Only after exact accepted fence completion may the export call `vkMapMemory` for the OWN coherent memory, copy exactly 24,368 (or 24,372) bytes to CPU-owned staging, Unmap, then CREATE_NEW payload/manifest files. No CPU cast/read of source addresses. Map failure, short data, any write/flush/close error or missing manifest is capture failure, partial files not proof. Check actual payload length, hash payload and 184-byte host args, store all span/generation/ticket/fence identities/value/completed/provenance, mark blend padding unknown and `output_capture=false`. Write a successful completion manifest last, never overwrite. Do not log payload bytes early. Use an owned non-reparse/private output directory.
7. One bounded bundle only. Quarantine is terminal, no rearm/retry/reuse; retain its Vulkan/COM resources until process teardown if uncertainty remains. A timeout must cover both missing Submitted and missing completion. Do not unload/destroy the owning Vulkan device while diagnostic commands could still reference its resources. If shutdown cannot prove completion, Main ends the isolated process rather than pretending successful cleanup. The model conservatively never offers release, even after success.

The old `diagnostic_capture.inc` is useful for exact-fence AddRef, timeout, worker Map separation and quarantine patterns only. Its POST5 eight-image allocations, eligibility and interop transitions are unrelated and were not merged. A new debug export with internal exact-fence ownership is simpler to audit than its full worker integration for this one-tile scope.

## Risk review / remaining blockers

| Risk | Mitigation / disposition |
|---|---|
| Source lacks TRANSFER_SRC | Shader GLOBAL reads only; never add observed usage or transfer-copy source. |
| Read wrong allocation, overlap or recycled address | Unique whole-span resolution, checked bounds, device + object/binding generations; old log alone insufficient. |
| Memory freed/rebound/other queue while recording/submitting | Full lifetime and queue ownership proof required before injection; unresolved = no implementation enablement. |
| Read too early or attribute sampled/latest fence | Private cb/list/cookie ticket + exact Submitted side-observation + immutable AddRef'd fence; poll exact value before any Map/read/payload disk. Bridge not yet implemented. |
| NVX synchronization/ABI/state uncertainty | Public spec is stub-only; own compiler/SASS verified statically, driver acceptance and barrier/binding contract remain unproven. |
| Capture clobbers ordinary pipeline state or original args | No ordinary compute binding commands; separate OWN NVX function; pointer-identical original forwarding. Runtime off path unchanged because no integration exists. Enabled pixel invariance is **not** claimed. |
| Original reuses source after copy | Explicit copy→original GPU execution barrier, not just HOST barrier. |
| Inflight release/failed dump reported successful | Terminal quarantine, no resource release/retry on uncertain lifecycle; manifest success only after exact completion and all payload writes. |
| Broad dump / invented replay data | 2,560 used input bytes only, full 21,808 slab explicit, optional 4 blend, no holes/allocation tails/output. Missing non-padding reads stay missing. |
| Compiler/PTX target mismatch | Own sm_120 CuBIN + untouched compiler PTX9.3; no downgrade of original; target NVX compatibility still a blocker. |

## Verification and handoff

`make -C reviews/nr-block70-sparse-capture-20260911 all` ran entirely on CPU:

- 14 unittest groups covering exact readset/coalescing, strict module/name/184-extras/dimensions, bounds/overflow, usage, partial-overlap ambiguity, metadata/binding generation changes, coverage gaps, destination ABI/alignment/alias, exact/missing/wrong cookie/list/fence, drops/timeouts/removal, no early host callbacks, errors, and pointer-identical once-only forwarding.
- 6 original NVX observer mock modes and 35 original buffer-observer mock modes built directly from the **unmodified** selected source, outputs only in this directory. These provide real existing-wrapper forwarding tests; added lifecycle tests exercise only the proposal model.
- Own CUDA CPU compilation, CuBIN/SASS/parameter metadata inspection, PTX GLOBAL access check and CPU word-coverage model for all used range lengths. No CUDA/Vulkan device initialization, Wine, nvidia-smi, GPU telemetry, runtime execution or capture run by this worker.
- `evidence/SOURCE_PINS.json` records inspected baseline and reference source hashes. `SHA256SUMS` pins this package. Verification logs are in `build/`.

Next work is **static integration review**, not GPU execution: start from the pinned worker `0fef` normal-reserve source (not Main's later `5ca2` build), establish the NVX GLOBAL/barrier/state contract, close memory lifetime coverage, implement the isolated private ticket/submission/flush bridge in a separate reviewed clone, then test that actual bridge with fake device/fence/Map callbacks and crossbuild. Main decides any later experiment separately. Keep CPU block70 validation primary and dynamic capture auxiliary.

Network verification: fetched `https://raw.githubusercontent.com/KhronosGroup/Vulkan-Docs/main/appendices/VK_NVX_binary_import.adoc`, saved verbatim as `evidence/VK_NVX_binary_import.adoc` (retains CC-BY-4.0 header). The document explicitly describes absent specification language. Two guessed chapter paths returned HTTP 404 and supplied no evidence. No claim of a published NVX stage/state guarantee is made.
