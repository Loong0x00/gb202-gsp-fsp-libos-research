# Submission-proof test plan

## CPU/MinGW review checks

Run without Wine, a game, or GPU execution:

```bash
make -C reviews/submission-proof/tree/native clean all
make -C reviews/submission-proof/tree/native \
  build/policy_test build/wine_harness.exe build/fake/dlss5-native-runtime.dll
reviews/submission-proof/tree/native/build/policy_test
python3 reviews/submission-proof/tree/native/tests/source_checks.py
patch --dry-run -p1 < reviews/submission-proof/submission-proof.patch
```

The dry run applies only to the pre-patch hashes. If `native/` already matches `tree/native/`, skip it (or expect “reversed/already applied”); see `INTEGRATION_NOTE.md`.

Expected on the pre-patch baseline:

- no compiler warnings/errors;
- policy test exit 0;
- source check prints the sampled completion-proof PASS line;
- PE host/runtime/fake/harness compile, but the Wine harness is **not executed**;
- patch dry run checks all 13 files.

After integration, rerun the repository's normal CPU/Wine suite only when main authorizes Wine execution.

## Main-owned cold GPU/game acceptance

Preserve the known working no-ReShade cases; do not replace them with a synthetic harness:

1. Cold `post/1`, `pre_sr/1`, `post/2`, `pre_sr/3`, and `post/10` using the existing matrix and frozen D5LC-72/D5RP-32 controls.
2. For the first qualifying frame, confirm the order:
   - Create remains `gate_closed` until real post-forward acknowledgement;
   - full Evaluate/POST copy or PRE adapter commit remains non-active after mere recording;
   - `submit_ack_samples` becomes nonzero only after real `ExecuteCommandLists` forward plus successful same-queue Signal;
   - `active` appears only after `completed_frame_samples > 0` and `last_completed_frame_id` reaches the first successful current-epoch frame.
3. Under steady rendering with at least two frames of GPU latency, verify `active` becomes and stays true even while the newest retirement fence remains ahead. This proves the implementation samples an older fence rather than chasing `last_fence`.
4. Re-run output rotation: rotate/recreate the game reconstruction output over thousands of frames. Verify current-frame POST output is copied only after all NR/composition/EndInterop work and no old output is retained.
5. Confirm `current_usage_sample` is `chain_admission`; do not interpret `current_usage_bytes` as live polling.

## Negative/fault cases

1. **Never execute:** record one otherwise successful frame and neither execute nor reset it. It must never produce an acknowledgement/completion sample or first-time `active`.
2. **Reset/release before execute:** Reset successfully or release the tracked list. The pending cookie and host proof must invalidate; no later callback may reactivate it.
3. **Partial Evaluate:** inject failure in layer 1, a later layer, compose, Begin/EndInterop, and (where injectable) final POST setup. A submitted partial command list may be retained for lifetime safety but must not increment full-Evaluate acknowledgement/completion evidence.
4. **Signal failure:** force same-queue `Signal` failure. Status must fail closed and no completion sample may be queued.
5. **Device removed:** make `GetCompletedValue` return `UINT64_MAX`. It must fault evidence, never increment `completed_frame_samples`, and never release the chain as normally fenced.
6. **PRE commit failures:** independently fail original signed SR, parameter restore verification, and output-commit proof. Runtime PRE work may have been recorded/submitted, but no failed frame may set the host successful-frame floor.
7. **Epoch replay:**
   - submit an old frame late across D5LC disable/re-enable;
   - submit an old frame late across adapter gate-generation change;
   - release/retire the selected owner and allow old pending callbacks;
   - switch to a new owner.
   In every case, old samples must not make the new epoch active; one new matching successful GPU-completed frame is required.
8. **Manager gate priority:** while valid old completion evidence exists, test D5LC off, D5RP pending restart, gate closed, reconstruction change, unsupported RR+PRE, and owner retirement. None may publish `active`.
9. **Queue/list lifetime:** release a queue after successful submission while the runtime fence reference remains; completion may still prove. Release/reset an unsubmitted list; it must invalidate. Retire with pending work must remain safely deferred rather than freeing referenced resources.

## Evidence to retain

- active DLL/control hashes and build ID `d5native-pc3-submission-proof-20260910`;
- pipeline status JSONL including the three sample fields;
- queue forward/Signal and fence-completion diagnostics;
- cold-process condition JSON for each order/pass case;
- reset/re-enable/gate/owner fault receipts;
- screenshots and existing no-ReShade process/module evidence.
