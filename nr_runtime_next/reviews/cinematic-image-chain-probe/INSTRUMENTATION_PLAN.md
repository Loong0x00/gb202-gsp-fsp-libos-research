# Next isolated diagnostic clone — not implemented in this baseline delivery

The user explicitly permits baseline final POST1-vs-POST5 first. That is the delivered EXE. **No per-layer capture, instrumented runtime binary, or claimed decoded-before-commit comparison exists yet.** Do not substitute final ping0 copies for L1/L3/L5.

## Target and unchanged invariants

Clone `../quality-post5-cinematic-20260910-173726/source/` into a **new subdirectory of this review** before modifying anything. Keep the original runtime DLL/ABI/source hashes in `frozen-inputs.json`; do not replace the baseline DLL pin. Instrumented harness must use a separate explicit diagnostic DLL-hash pin and output labels. Preserve existing D5R exported structs and Initialize/Execute/Submitted/Reset/Retire semantics, numeric bootstrap, signed dependency path, budget admission, configure keys, independent layer handles, shader payloads and pass loop. No per-pass calls to another runtime.

At default 768x768, each tight RGBA16F image is 4,718,592 bytes. An eight-image bundle S/B/L1..L5/D is 37,748,736 bytes (36MiB), before footprint alignment; owned current-output G adds 4.5MiB. Initial instrumentation should cap one bundle in flight and capture only first and last evaluated frames, sequentially drained by this fixture. Include staging/texture allocations in actual resource pressure before runtime admission; retain existing DXGI budget checks and add a bounded capture allocation cap. Never silently reduce layers or weaken budget gates.

## Candidate D3D12 route (avoids assuming Vulkan TRANSFER_SRC usage)

Add an **additional test-only export/header**, not fields in frozen ABI, to register one capture request containing immutable native READBACK buffers/footprints, owner/frame/list identity and stage indices. Harness preallocates/references these buffers, runtime only records copies. Harness alone handles queue submission, fence wait, Map, file I/O and reuse. No GPU waits or disk I/O inside runtime.

1. S: capture chain snapshot after its existing `copy_active` call and before BeginInterop, or retain the baseline original-output before capture with explicit distinct label. B: capture after codec encode using the interop-boundary procedure below.
2. L_i: immediately after successful `b.evaluate(cb, layer.handle, layer.parameters, nullptr)`, **inside the loop and before next Evaluate**, keep the existing post-Evaluate memory barrier. Log stage index, frame, parameter pointer, handle ID, input/output wrapper and VkImage/VkImageView identities, reset condition and dimensions before Evaluate. Do not add alias parameter keys as a guessed fix.
3. D3D12 copies cannot be issued while Vulkan interop is active. Before each diagnostic break, restore every temporarily read ping image from its current SRV Vulkan layout to the canonical UAV layout that the native list still tracks; preserve read/write visibility. The `ping_read[]` logical routing state must be saved, not discarded.
4. Issue conservative write-completion/global post barrier and **EndVkCommandBufferInterop**. On failure invalidate whole capture/frame and do not issue the native copy or submit partial work.
5. Copy only this layer's **current** physical D3D12 ping texture (UAV→COPY_SOURCE→UAV) to this layer's **unique** READBACK footprint. L1/L3/L5 may share the source texture but MUST NOT share capture storage or defer copying until after the loop. Canonical native resource tracking and actual Vulkan layout must agree before/after the break.
6. Begin a new interop region on the **same native list**, refresh `cb` (never reuse old CB), apply global pre barrier, then restore saved ping-read layouts from canonical UAV→SRV, with correct producer/consumer visibility. Continue original loop and original `ping_read[]` bookkeeping. Keep original Evaluate ordering/barriers; do not add extra Create/Evaluate/reset calls. Verify the signed feature accepts new Vulkan command buffers between layers and interop Begin/End permits this split.
7. D: after successful original final compose and original EndInterop, before the existing POST CopyTextureRegion commit, D3D12 capture `c.decoded` via UAV→COPY_SOURCE→UAV into distinct D buffer. G remains harness's after-Execute current output capture, on the exact same list. D vs G should be byte-exact in this same-format, same-extent fixture; this is the requested **decoded-before / actual-output-after native commit** comparison unavailable in baseline.
8. Any diagnostic failure marks sample invalid and fails the frame; no successful partial-layer output publication. Entire recorded command list follows existing tracked cookie and submission/fence receipt. Harness rejects wrong list/owner/frame/shape, duplicate stage, missing stage or unknown fence. No buffer release/reuse before exact GPU fence completion and CPU copy-out.

This is intentionally a **perturbing diagnostic**: interop breaks can change command buffer scheduling. If baseline and instrumented final pixels differ, investigate instrumentation before using layer captures as original-pipeline evidence. Baseline-with-capture-disabled must retain exact original recording behavior. This route needs review/CPU command-model tests before cross-build, then Main-only GPU validation. It is not claimed safe merely because the plan names the barriers.

## Alternative Vulkan route if usage is verifiable

A less disruptive route is `vkCmdCopyImageToBuffer` immediately after each Evaluate, with one host-visible transfer buffer per stage or nonoverlapping aligned slices, correct image layout/access transitions and transfer→host visibility. First **prove** mapped vkd3d texture VkImage usage includes TRANSFER_SRC; D3D12 flags alone do not establish this interop contract. If proof is absent, do not guess. Extend test-only Vulkan dispatch/allocation/invalidation helpers, retain exact queue/fence lifetime, flush/invalidate noncoherent mappings correctly and preserve original shader-write→shader-read dependency after transfer. This avoids Begin/End splits but requires more Vulkan allocation/memory-contract work.

## CPU gates before instrumented build

- Stateful command recorder models all ping layouts/native canonical states across 1/5 layers and 1/8 frames, including every Begin/End break, RAW/WAR/WAW dependencies, final compose and native commit.
- Capture contents are sampled at recorded copy position, not at end-of-loop. Mutation: postpone L1 copy until after L5 and test must fail (minimal witness already in `cpu_checks.py`).
- Fail each Begin/End/copy-registration/allocation/Evaluate position; no partial submitted success, no reuse before known fence. Wrong queue/cookie/frame/list, device-removed UINT64_MAX fence and CPU copy-out delay tests.
- Verify per-layer raw stage count and separate immutable buffer slices, D/G row-pitch stripping, no readback Map before exact submission fence.
- Source diff whitelist only instrumentation/helper/build changes. Original configure, handles, codec payloads, bootstrap/dependency loading/admission and existing export ABI remain unchanged. Crosscompile only; worker never launches Wine/GPU.

Then Main runs same static input/controls with matched guides first. Compare instrumented G to baseline G, D→G exact commit, B→L1→...→L5 proxy-domain changes. Raw layer values are **not** HDR output values: reproduce frozen codec using captured S/B/L1 vs S/B/L5 before attributing final attenuation to NR itself. Do not compare separate-process POST1 to POST5 L1 as if histories were shared.
