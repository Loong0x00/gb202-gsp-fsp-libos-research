# Minimal per-layer capture plan — design only, DO NOT DEPLOY

Requires separate authorization and an isolated diagnostic copy/build. No implementation, GPU execution, game launch, control/style change or deployment is part of this audit. Preserve the exact frozen production source/package/Main.

## Bounded sample

- One owner, POST5, unchanged controls; at most **two successfully captured frames**, **one staging bundle in flight**. Capture first eligible frame and a later ordinary-history frame only after the first bundle retires/is drained. Record reset flags; do not force reset or change pass count. No render-thread waits or per-frame file I/O.
- Hard cap **640 MiB staging allocation**, plus explicit existing budget admission; if insufficient, skip capture rather than lower quality/change controls/evict live resources. Primary bundle: snapshot, base, L1..L5, decoded (8 RGBA16F images) plus final game output (WuWa R11G11B10F). Raw payload `68*W*H` bytes (~538 MiB at 3840x2160), before footprint/alignment overhead. Precompute exact size; refuse oversized extents. At most two bundles on disk. Ring cannot be reused until GPU retirement AND CPU copy-out finish.
- Preallocate once outside hot recording, log only bounded metadata. If capturing perturbs/fails the frame, label sample invalid; never use it as production quality acceptance. Keep stop/deadline and dropped-capture counters.

## Capture points in frozen source

All native paths below relative to the frozen `source/native`.

| Capture | GPU command insertion point | Why |
|---|---|---|
| S = current reconstructed input | After `copy_active` / within BeginInterop before encode (`runtime/pipeline.cpp:482-508`), snapshot image | Proves same-frame baseline independent of later in-place output commit. |
| B = encoded base | After successful encode, before first Evaluate (`508-509`) | Actual first layer input, before any NR work. |
| P1..P5 = raw output of each successful Evaluate | After `b.evaluate` success at `535-538`, **inside the loop**, before next layer; stage-specific staging offsets | P1 must survive L3 overwrite; P2 must survive L4; P3 must survive L5. Immediate copy avoids parity false equality. |
| D = decoded composition | Immediately after successful compose (`547-548`) before EndInterop/native copyback | Separates NR raw changes from codec suppression. |
| G = actual current game output | Native direct POST: after copyback/state restoration (`574`). WuWa: after `bridge->commit` success (`host/wuwa_ingress.cpp:948-961`), following R11 conversion on same native list | Must capture the game's current output, not merely `c.decoded` or normalized owned_color. This is not a Present/screenshot claim. |

Bind metadata immediately before every Evaluate (`runtime/pipeline.cpp:534-535`): owner/frame/gate/reset, layer, handle pointer/ID, map pointer, original host Color/Output pointers, current normalized source/output, all resource key readback results using **verified core getter ABI** (not host feature-map slots), wrapper address plus nested image/view/format/range/extent/ReadWrite, source/destination content-generation labels, scaling/input/output/subrect values, reset, actual return code, command list/CB identity. Preserve exact control snapshot, do not modify it. Inspect bare resource aliases for conflicts but do not add/set them as a guessed fix.

Assert expected sequence `B→P1→P2→P3→P4→P5`, disjoint input/output images within each call; P1/P3/P5 share physical ping0 but get **distinct staging offsets**. Expected physical image identities alone do not prove signed descriptor use. If readback disagrees, capture the **actual selected input** before that Evaluate, not the expected predecessor. Optional second diagnostic tier adds pre-Evaluate input copies for L2..L5 (one frame / new cap approval), or a signed descriptor-consumption trace, to test hidden input writes/caching; do not quietly exceed the primary cap.

## Correct staging and retirement

1. Preferred inside existing Vulkan interop region: copy raw image to dedicated host-visible VkBuffer slice using `vkCmdCopyImageToBuffer`. Load capture-only dispatch functions in the isolated build. First verify the mapped images legally have TRANSFER_SRC usage in this vkd3d interop contract; do not infer Vulkan usage just from D3D12 flags. If unavailable, design/review a D3D12 READBACK route with proper interop boundaries instead; never issue D3D12 copies while Vulkan interop is active.
2. For each output, barrier from the actual writer/stage/layout to TRANSFER_READ / TRANSFER_SRC_OPTIMAL; enqueue copy; barrier transfer-read back to the **exact pre-capture layout and future access/stage** expected by existing code. Add a dependency that also orders the original producer's writes for the next shader read; do not substitute a transfer-read-only source for required shader-write visibility. Preserve original barriers and state bookkeeping. For read-only snapshot/base, likewise restore read layout and cover future read/write reuse. Use a valid reviewed conservative all-command/memory-write source if signed producer stages are not yet established. Vulkan buffer offsets meet texel-block/alignment requirements, one immutable slice per stage.
3. For G, use D3D12 READBACK with `GetCopyableFootprints`, correct DXGI format/row pitch and COPY_SOURCE transition; restore original resource state. The copy must be recorded **after the final format commit but before any subsequent game recorder can overwrite it**. If native-copy loss suspected, an optional additional capture of normalized output just after `runtime/pipeline.cpp:574` separates native CopyTextureRegion from FormatBridge conversion.
4. Associate all slices with the exact native command list and post-forward same-queue submission/fence tuple. Existing hooks signal after forwarding (`host/queue_hooks.cpp:224,274-290`); diagnostics need their **own exact frame sample**, not the runtime's one-older-frame completion counter. No extra queue execution or hidden flush. Record a transfer-write→host-read visibility dependency as required for Vulkan staging.
5. Poll completion only on worker; require expected queue/fence/value and `completed != UINT64_MAX && completed >= value`. Only then map/read staging (invalidate noncoherent Vulkan mapped ranges with atom-aligned bounds). D3D12 readback obeys footprint row pitches; retain buffers until CPU output saved. No read of live ping0 after the fence: it may already contain another frame even though this frame retired.
6. Reset/Release before submission, failed Execute/Signal, wrong queue, failed Evaluate/EndInterop/commit: invalidate sample. Do not free/reuse buffers associated with potentially submitted work without a trustworthy retirement proof; quarantine on unproven lifetime/device loss. No pointers to per-call stack descriptor/capture records may survive recording.

## Offline interpretation (raw arrays, not screenshots)

- Preserve lossless raw half-float / packed R11 bytes and metadata, row-pitch stripped for hashing. Report SHA256, nonfinite counts, min/max, per-channel mean and luminance mean. Compare B→P1, every Pi→Pi+1, and **P1→P5**: exact equality fraction, MAE/RMSE/max, p95/p99 absolute difference and per-tile distribution. Decode half/R11 correctly; compare alpha separately (raw NR alpha need not be meaningful).
- Raw P1..P5 are proxy-domain outputs; S/D/G are HDR-domain. Do not compare their RGB numbers directly as if same transfer function. Reproduce frozen decoder on CPU using captured S/B/P1 vs S/B/P5 and the same controls: hypothetical composed-C1 vs composed-C5 isolates codec attenuation **within one POST5 frame**, not an independent POST1 run with different history.
- Compare CPU composed-C5 with D (account for GPU floating-point tolerances); compare D against G after expected R11 quantization for WuWa. Large Pi deltas but small composed deltas implicate composition; matching D but wrong G implicates commit/format path. Equal Pi with valid bindings may mean near-idempotence, ignored input, wrong history, or no writes—**equality alone does not pick a cause**.
- A real standalone POST1-vs-POST5 visual comparison would need separate authorization, controlled histories/scene and controls; this plan intentionally does not change controls. GPU-retired stage captures establish pixels at those points, not later game tone mapping/Present.

## CPU tests worth adding before any capture build

- Mock core parameter vtable: record configure calls/types for five distinct maps, distinct handles, pointer lifetimes, unchanged predecessor routing at Create/Evaluate; inject duplicate parameter/handle IDs and getter failures/conflicting aliases.
- Mock Vulkan/D3D command stream: for N=1..10 test distinct input/output, RAW/WAR/WAW order and layout restoration across frames; snapshot stage contents at **copy command time**, not end-of-frame. Mutation test: delay P1 capture until after L5 and require test to detect false-equal parity labels.
- Mock descriptor writes: encode [S,B], decode [S,B,Pn,D]; frame A/B rotate host Output while chain remains constant; pass-count change rejects rather than reusing wrong final parity. Capture exact FormatBridge current slot output after frame A is retired before descriptor rewrite.
- Submission lifetime model: reverse lists, wrong queue, multiple pending frames, failed Signal, Reset-before-execute, UINT64_MAX completion, and CPU copy-out delay. Never recycle captured slices on call-count or submission acknowledgement alone.
- CPU decoder synthetic perturbations: distinct spatial patterns in B/P1/P5; confirm final binding affects output and quantify clamping/luminance projection with unchanged captured controls. These tests expose wrapper/codec mistakes, not signed NR internals.
