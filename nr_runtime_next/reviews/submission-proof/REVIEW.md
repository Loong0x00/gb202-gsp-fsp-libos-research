# CPU review: truthful native submission/completion proof

## Critical findings in the reviewed snapshot

1. **`active` is currently a submission claim, not a GPU-completion claim.**
   `host/queue_hooks.cpp` correctly calls the real `ExecuteCommandLists` first and then queues a same-queue `Signal`, but `host/pipeline.cpp::runtime_submission_status` immediately changes a successful Evaluate acknowledgement to `D5N_FRAME_EVALUATED_V1`. The runtime only calls `GetCompletedValue` while retiring a chain. A recorded and signalled frame can therefore publish `active` before its NR, composition, and game output work has completed.

2. **The existing latest fence cannot be reused as live proof.**
   `runtime/pipeline.cpp::DLSS5_NativeRuntimeSubmittedV1` replaces `Chain::last_fence` on every Create/Evaluate submission. Requiring that moving value for `active` can fail forever under normal continuous two-frame GPU latency. It is appropriate for retirement after submissions stop, but not for first-live proof.

3. **A partial failed Evaluate still owns an Evaluate submission cookie.**
   Tracking intentionally begins before copies/interop/NR so Reset/Release can invalidate partial work. In the snapshot, however, `Pending` has no “whole Evaluate succeeded” bit. If that partially recorded list is later submitted, `SubmittedV1` accepts it exactly like a complete Evaluate. Host status often remains error because the latest result has zero calls, but the callback itself is not truthful full-frame evidence and is unsafe to use for completion telemetry.

4. **The PRE adapter commit is already materially correct and should be retained.**
   It matches pending frame/owner/game and requires successful original signed SR, verified parameter restoration, and output commit. Runtime Evaluate success alone must not establish the PRE successful-frame floor; the patch establishes that floor only when this commit succeeds.

5. **Existing output rotation and temporal-gap fixes are present.**
   POST composes into chain-owned `decoded`, ends interop, and only then copies into the current `r.frame.output`; the game output is not cached. `Chain::last_frame_id` forces reset on a frame-ID gap. The proposed patch leaves both paths intact.

6. **`current_usage_bytes` is not live usage.**
   It is captured by `QueryVideoMemoryInfo` during chain admission. The patch keeps the field for compatibility and adds `current_usage_sample:"chain_admission"`; it does not fabricate a fresh value.

## Proposed minimal design

The unified patch is `submission-proof.patch`; its buildable source copy is under `tree/`.

- Keep `last_fence` solely as the latest accepted lifetime/retirement fence.
- Add at most one `completion_fence` sample per chain. A successful full Evaluate submission fills an empty slot; newer submissions do not replace it. The existing retire worker polls `GetCompletedValue` nonblockingly every 100 ms and releases the extra fence reference when observed.
- Treat `UINT64_MAX` as device removal/failure, never completion.
- Add `Pending::full_success`, set only after every NR call, composition, EndInterop, and POST current-output copy have been recorded successfully. Create and partial Evaluate submissions cannot increment Evaluate evidence.
- Scope runtime evidence by owner chain plus gate generation and D5LC reset generation. Late old-epoch submissions remain valid lifetime bookkeeping but cannot repopulate live proof.
- Reuse the first four 64-bit words of internal pre-release `D5rQueryV1::reserved[6]` for an optional owner selector and three outputs. `sizeof(D5rQueryV1)` remains 80 bytes. Adapter-facing raw frame/result layouts remain 200/216 bytes; D5LC remains 72 bytes and D5RP remains 32 bytes.
- On the host, retain a `first_successful_frame` floor for the current enable/gate/owner epoch. POST sets it only after the original signed SR/RR and full NR recording succeed. PRE sets it only after the existing adapter commit succeeds. `active` requires a selected-chain completion sample with `last_completed_frame_id >= first_successful_frame`; it does **not** require the latest submitted frame.
- Apply manager enable/pending-restart and current adapter gate/reconstruction checks before completion proof.
- Clear host proof on disable/re-enable, gate generation changes, owner retirement, Reset/Release invalidation, signal/rejection, and hard frame failures. Runtime retirement hides/clears chain evidence while preserving pending lifetime safety.
- Keep runtime Query outside all host locks. `SubmittedV1` returns before the host status callback acquires `status_lock`, avoiding a host-status/runtime-lock inversion.
- Remove frame-path capability-file writes. Completion polling and all status/capability I/O stay on background workers; no fence wait or file I/O is added to Evaluate/Execute callbacks.

## Telemetry meaning

The patch adds optional status fields:

- `submit_ack_samples`: successful full-Evaluate post-forward acknowledgements observed for the selected live chain/epoch;
- `completed_frame_samples`: bounded fence samples observed complete;
- `last_completed_frame_id`: frame ID of the latest completed sample;
- `current_usage_sample:"chain_admission"`: labels the existing budget usage value.

These are lower-bound evidence samples, not exact presented-frame counters. A status heartbeat can skip the short acknowledgement-only transition, and many frames can pass while one completion sample is outstanding.

## Compatibility/risk notes

- No changes are proposed to `native_adapter.h`, `D5nRawFrameV1`, `D5nRawFrameResultV1`, D5LC, D5RP, game code, manager code, adapters, or signed DLLs.
- An old runtime paired with the patched host leaves the new zero-initialized query outputs at zero, so it fails closed and cannot become active. Host/runtime should still be shipped as a matched pair.
- Queue release after a submitted signal does not invalidate proof: the runtime holds its own fence reference. Before submission, pending records are list-scoped and have no queue association; list Reset/Release or owner Retire is the truthful invalidation path.
- GPU execution, presentation semantics after fence completion, device removal, and game integration were not executable in this CPU-only review. Main must own integration and cold GPU tests.

## Apply precondition

The patch was generated against the **pre-patch** hashes in `source-snapshot.sha256`. Apply it only if those hashes pass:

```bash
sha256sum -c reviews/submission-proof/source-snapshot.sha256
patch --dry-run -p1 < reviews/submission-proof/submission-proof.patch
patch -p1 < reviews/submission-proof/submission-proof.patch
```

A concurrent worker integrated byte-identical targets after this review's isolated verification; see `INTEGRATION_NOTE.md`. If `native/` still matches `tree/native/`, do not apply twice. If it differs from both the recorded baseline and review tree, rebase rather than forcing hunks.
