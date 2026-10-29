# Quality SR + RR / POST5 budget review — CPU only

## Bottom line

**Quality POST5 has not been shown to fit or to OOM.** The recorded switch was an adapter estimate refusal, not a five-layer Quality execution failure. Keep Quality as the target; Ultra Performance is only a calibration comparator, not a proposed workaround. No guard change is justified from the existing data.

All changes/artifacts are confined to this review directory. Nothing was installed, loaded into a game, or executed through Wine/GPU. Frozen source and package SHA256 manifests verify before/after the CPU checks. `AUDIT_INPUTS.json` pins the audited files; line references below refer to `reviews/wuwa-main-physical-20260910-142015/source/`.

## Evidence boundary

Run `wuwa-runs/20260910-155322-native-post-5-initial-off-physical-user-operated/QUALITY_SWITCH_FINDINGS.json`, plus the supplied user correction:

- User confirms initial **Ultra Performance**, then hot-switch to **Quality**. Menu enum and precise Quality render/guide dimensions were not captured.
- Five distinct actual NR handles; final reported Evaluate count **1235 each** (maximum in sampled active status **1233 each**), **613 sampled completed frames**, not proof that every Evaluate completed.
- Whole-device GPU usage: last 10 s before NR **10369–10402 MiB**; active **23608–24151 MiB**; after refusal **14527–14569 MiB**. Normal exit by 16:01 is supplied context, not an OOM exit.
- Uncontrolled active-minus-baseline envelope: **13206–13782 MiB**. This mixes scene/game/allocator/bridge/NR changes and is **not** the isolated five-layer NR increment. Quality's later ~14 GiB whole-device plateau is not DXGI process CurrentUsage and does not prove all old NR allocations were released.
- Status bytes `budget=31199264768`, `usage=8303083520`, `estimate=15809328152`, `reserve=3119926476` are **stale Ultra admission fields**. Do not use them as a Quality preflight or calculate a Quality safe pass count from them.

## Frozen-source audit

### Two guards, not two additive invoices

1. `native/host/wuwa_ingress.cpp:415–525, 771–818`: adapter preflight calls device-LUID `IDXGIAdapter3::QueryVideoMemoryInfo(0, LOCAL)` before FormatBridge normalize and runtime submission. The active shape/order/pass/owner key is matched against an earlier **accepted NativeRuntime CREATE_PENDING/EVALUATED** receipt. Shape mismatch resets this observation. Temporal-history eligibility alone never establishes residency.
2. `native/host/wuwa_budget_policy.h`: with checked arithmetic:

   ```text
   available = DXGI.Budget - DXGI.CurrentUsage
   nr_charge = matching_owner_admission ? 0 : nr_surfaces + nr_histories
   format_planned = aligned_bytes_per_slot * 4
   format_remaining = max(format_planned - global_format_owned_bytes, 0)
   required = nr_charge + format_remaining + reserve
   fits = complete && required <= available
   ```

   The reserve is never waived. Incomplete/overflow inputs fail closed. A stable, positively observed same-key allocation is NOT charged twice here. Failed/native-unknown calls or explicit invalidation clear the evidence even if some physical allocations still exist; the observation is not an allocation ledger.
3. `adapters/common/policy.cpp:340–360`: resolution change can cause a settling/refusal epoch first; `frame_budget_limit` follows complete preflight when required exceeds available (or requested pass count exceeds limit; POST5 is below limit 10). `budget_not_preflighted` is the distinct incomplete-receipt case. Preflight `fits` is not adapter dispatch, successful runtime execution, or completion.
4. `native/runtime/pipeline.cpp:163–186, 379–429`: a separate guard runs only when allocating a new runtime chain, after bridge normalize. It queries CurrentUsage again, adds its own NR estimate + reserve, **not** an additional four-slot FormatBridge estimate. The two guards do not accumulate estimates into one charge; the later query sees allocations recorded between stages. Existing chains reuse their stored admission byte receipt (`fill`, lines 464–478).
5. `native/host/telemetry.cpp:204–220`: `set_status(..., result=nullptr)` changes disposition/reason without refreshing budget fields. The adapter rejection path passes no runtime result. This directly explains why the sampled Quality rejection status carries an earlier Ultra receipt; it does not identify the missing Quality arithmetic.

### Conservative estimate versus real resources

`native/common/control.h:140–162`, with work pixels W and guide pixels G:

```text
surfaces = 40*W + 12*G
histories = passes * (128*W + 256 MiB)
reserve = max(1 GiB, floor(DXGI.Budget/10))
```

- The five work textures are snapshot/base/two ping-pong/decoded; motion is RGBA16F and depth R32. `allocate_resources` creates them once per chain, NOT once per layer. Surface estimates are nominal texel bytes, whereas bridge slots use D3D allocation sizes including alignment.
- NR layers have separate handles/parameter maps. The 128 B/work-pixel + 256 MiB/layer is explicitly conservative weights/workspace/history uncertainty, not measured internal tensor sizes. It cannot be cut just because a whole-device delta looks smaller.
- **For POST with unchanged output dimensions/pass count, the model's history term is unchanged by Ultra→Quality guide resizing.** NR surfaces increase by 12 times the guide-pixel increase; four planned bridge slots also grow by their aligned guide allocation differences. Higher game SR/RR usage and/or changing DXGI Budget may be the dominant change. This is conditional on dimensions that were not logged, not a reconstruction of this run.
- Actual NR internals may still depend on guide/input shape: `runtime/pipeline.cpp:242–307` passes render `Width/Height`, `DLSSNR.InputWidth/InputHeight`, full work output dimensions and guide subrects to signed NR. Its POST create scaling contract uses 0.5 when work exceeds render, then the scaling callback returns 1.0. Calibration must preserve this exact behavior; NR's hard-coded `PerfQualityValue=0` is NOT evidence of the game's selected SR quality.
- `native/runtime/interop.cpp:219–258` imports the existing D3D resources and creates VkImageViews; it does not allocate a second set of these textures. Do not double-count the D3D/Vulkan alias. Whether the deployed DXGI/vkd3d accounting sees all signed-NR private Vulkan allocations must itself be calibrated; whole-device and DXGI process accounting are not interchangeable.

### Resize, retirement and legitimate overlap

- `native/runtime/pipeline.cpp:346–362, 730–743`: one occupied runtime chain per owner. A **same-owner shape/order/pass/reconstruction change does not rebuild automatically**; the old chain causes an error/failed state if execution reaches runtime. Resetting adapter admission does not retire/free it. Thus an old allocation plus prospective full charge after same-owner mismatch is conservative lost-evidence accounting, not proof of two simultaneously created same-owner chains.
- `native/host/pipeline.cpp:396–412` routes signed feature Release to owner-history removal and runtime Retire. A newly created **different owner** can allocate while another owner's chain is retiring; that overlap is legitimate only while both allocations genuinely remain live.
- `native/runtime/pipeline.cpp:588–653, 824–835`: retirement releases NR handles/parameters, views and textures only once no pending records remain and the latest fence completed (or safe never-recorded case). `lifetime_unproven` blocks release; device-removal sentinel is not completion. Worker wait is up to 100 ms. New-owner and retained-failed-chain cases can leave old bytes in CurrentUsage. Nothing in current telemetry proves which happened during this switch.
- `adapters/format_bridge/bridge.cpp:399–505, 701–718, 819–869, 1011–1051`: global four-slot pool. Fence completion frees external references but keeps owned slot textures cached. A free incompatible slot releases its old owned resources **before** allocating replacements; busy old slots are never reused prematurely. Resident accounting includes cached/free and in-flight owned textures. Subtracting global resident bytes from the final four-slot plan is not a blanket extra four-slot charge. It is a final-pool net-growth estimate, **not** a per-slot physical-residency or transient-peak proof; heterogeneous old/new slots and delayed driver release warrant measurement. For example (synthetic units), three busy 20-byte slots give resident=60 while a new shape plans four 10-byte slots (=40): net remaining=0, yet an empty fourth slot can still allocate 10 bytes before old slots retire. This is a possible transient undercount, not evidence of duplicate charging or this particular Quality refusal. Descriptor/driver overhead is not included in this byte counter. The 3 GiB bridge cap is separate and unchanged.

### What would discriminate causes

| Candidate | Needed evidence | Present conclusion |
|---|---|---|
| Real old/new-owner overlap | Owner transition, retirement submission/fence proof, usage before/after actual release; old/new private allocation accounting | Possible, not established |
| Duplicate charge of reusable NR | Fresh same-key admitted receipt yet nonzero NR charge, or proven live reusable allocation with lost observation | Normal matched policy charges zero; invalidation cases need lifecycle proof |
| Conservative estimate exceeds true new cost | Isolated signed NR five-layer incremental peak for exact Quality shape/scalars versus recorded model terms | Plausible, not calibrated |
| Higher Quality base game usage / lower live DXGI Budget | Fresh Quality preflight Budget/CurrentUsage and shape, no old NR owners remaining | Plausible, not captured |

No guard reduction, residency credit for an unproven chain, fake completion, or quality downgrade is included.

## Diagnostics-only review patch

`diagnostics.patch` targets three paths relative to the frozen `source/` root:

- `native/host/wuwa_ingress.cpp`: snapshot the **same actual preflight query and inputs used by the guard**, including failures, before normalization/runtime. Capture prior owner admission before reset, actual NGX render/guide and output-derived work dimensions, phase order, requested order, passes, owner, reconstruction, frame and collection timestamp. No extra DXGI query and no guard change.
- `native/host/wuwa_budget_diagnostics.h`: private CPU receipt/formatter and 64-entry ring. Stable epoch sampled once/second; changed key/query-validity/admission-match/budget-result captured immediately. Explicit observation/suppression/overwrite counters. All receipt objects start empty, so a failure cannot inherit stale byte fields.
- `native/Makefile`: add the private header dependency. No public ABI headers, exports, runtime, policy, signing or safety/gate behavior changed.

The existing worker writes `.dlss5-linux/wuwa-budget-preallocation.jsonl` via atomic replace, at most once/second, fixed maximum **131584 bytes** (+ one same-sized temporary file during replace), no unbounded append. Render thread only takes a short independent diagnostics lock; formatting/disk work is on the worker. A fresh PID/session nonce in metadata distinguishes old files. Main should collect each snapshot and deduplicate `(pid, session_nonce, sequence)`.

**Interpretation:** `memory_ok` and `slot_ok` validate query stages; `complete/fits` describe only the budget predicate. On early failure, later-stage zero fields are unavailable, not measured zero cost. `nr_admission_match` is the policy's accepted-allocation observation, not current physical residency. `prior_key` is `[owner,reconstruction,order,passes,render_w,render_h,output_w,output_h]`. `format_owned_accounted` is the bridge's aligned owned resource byte ledger, not an OS residency query. Physical NR/format residency fields are explicitly `null`. Work/guide dimensions are requested active subrects/allocations, not arbitrary larger game resource backing sizes. This patch cannot reveal opaque signed-NR history bytes or retiring-chain residency through the frozen ABI.

Use each receipt's `unix_ns/frame`, not the sidecar publication timestamp, for freshness. Stopping NR can leave the last receipts published without new queries; a write failure can also leave an older file. Ring overflow is explicit; frequent owner churn can evict a switch before collection. This is bounded sampled diagnostics, not a lossless lifecycle trace. Main must verify worker I/O timing and sidecar capture on its owned test before game use.

## Verification and handoff

Run `bash reviews/wuwa-quality-post5-budget/verify.sh` from the project root; all outputs stay in this review. `build/verification.log` records the result.

- Pure CPU fixture: same-key reuse; same-owner resize invalidation; rotate-back non-resurrection; changed owner/order/pass/reconstruction; synthetic retained-old usage versus released-old usage; format net charge; reserve/boundary/overflow refusal; failed query fresh receipt; bounded sampling/overwrite/serialization. JSON equations are checked independently in Python. Resize/retirement usage transitions are **models**, not a dynamically executed runtime/fence test.
- ASan/UBSan fixture run, plus frozen CPU policy/ABI, commit-policy, loader-hardening, factory-hook and FormatBridge plan tests.
- `build/dlss5-native-host-diagnostics-review.dll` fully MinGW-cross-linked against unchanged frozen host/adapter/FormatBridge sources. Eight exported names match the frozen host. `build/budget_diagnostics_fixture.exe` is a cross-compiled **CPU policy fixture**, not a GPU calibration harness. Neither Windows artifact was executed or installed.
- Frozen source/package checksum manifests pass before/after; patch dry-run passes. No live Quality budget was measured and no fit improvement is claimed. See `CALIBRATION_PLAN.md` for the separately authorized next step.
