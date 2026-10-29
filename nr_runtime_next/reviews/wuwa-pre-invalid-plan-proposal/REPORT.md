# WuWa PRE3 invalid_plan — isolated diagnostic proposal

## Outcome / safety

**Diagnostic-only proposal; NOT deployed. Do not swap the live DLL or restart the active game for this review.** The supplied live observation is ordinary SR after Engine DenoiserMode=0, NR OFF/zero NR, no adapter attach/caps, and budget-passing compatibility probes. I did not independently inspect live telemetry, game settings, GPU, Wine, or process memory.

All writes/builds are under `reviews/wuwa-pre-invalid-plan-proposal/`. Main, Game, and the frozen PRE3 source/package were not modified. All 94 files in the frozen source were hash-verified unchanged after testing. The cloned runtime and DXGI DLL were copied unchanged, not rebuilt. Only the isolated host/format library were crosscompiled; no Windows executable was run.

**Actual current Game Color format remains UNKNOWN.** A strict PRE format mismatch is a concrete candidate, not a measured diagnosis. The new receipt is needed to identify the exact rejection in one later, separately authorized cold retry.

## Exact frozen-source findings

Paths/line numbers below refer to `reviews/wuwa-pre3-cinematic-20260910-204000/source/`.

1. **Reason currently discarded:** `native/host/wuwa_ingress.cpp:649-684` builds the normalization request, calls `bridge->normalize()`, then publishes only `status_code_name(status.code)`. `Status` already contains `plan_reason` and `hresult`. `adapters/format_bridge/bridge.cpp:69-73` creates `invalid_plan` with the precise plan reason and **S_OK HRESULT (0)**; that HRESULT is not evidence of successful normalization.
2. **Exact rejection boundary:** `bridge.cpp:787-807` first checks raw identity/ABI/finite values/list type (failure = `invalid_argument`), then resource descriptors (`unsupported_texture`), then `validate_shape_plan()` (`invalid_plan` with its first failing reason). This precedes device/format-support checks, slot allocation, descriptor creation, and conversion recording. Thus `invalid_plan` is not an NR Evaluate failure or the bridge's `unsupported_format_support`/budget error. `format_owned=0` is consistent with refusal before owned-texture allocation, but does not identify which plan predicate failed. FormatBridge initialization itself can already have created shaders/PSOs.
3. **Hardcoded PRE Color:** `wuwa_ingress.cpp:656-668` chooses `source_rgba16_float` plus view `DXGI_FORMAT_R16G16B16A16_FLOAT` (10), without inspecting Color's actual format to select a contract. `format_plan.cpp:205-210` requires **resource=10 AND view=10**. The historical comment in `format_plan.h:40-43` is not proof of this running game's descriptor.
4. **Existing strict R11 option:** `format_plan.h:44-46` defines `explicit_rgba16_float_srv`: the caller must separately attest that this exact SR seam accepts an RGBA16F replacement despite an original R11 Color. `format_plan.cpp:210-215` requires **resource=26 AND view=26** (R11G11B10_FLOAT). The contract name refers to the **replacement**, not a legal RGBA16 view of an R11 resource. `bridge.cpp:544-554` uses the supplied typed source SRV and an owned RGBA16F destination; `shaders/normalize.hlsl` shader kind 0 performs typed Load/store. Static/CPU planning supports this route; current-game replacement acceptance is unverified.
5. **Guide contracts remain strict:** `format_plan.cpp:175-181` requires WuWa MV resource/view=34 (R16G16_FLOAT), depth resource/view=41 (R32_FLOAT). Typeless alternatives are not accepted for WuWa. The host hardcodes those view formats too. A Color-format observation alone cannot exclude a guide mismatch.
6. **Adapter PRE policy is not a format allowlist:** `adapters/common/policy.cpp:19-21,246-249,293-336` requires nonzero resource format/sample metadata, coherent identities/generations/extents and backend `format_conversion_ready`. `wuthering_waves/adapter.cpp` forwards resource evidence. `common/native_contract_bridge.cpp:194-246` checks topology/bindings/attestations/scalars, not a DXGI allowlist. CPU fixtures show PRE eligibility for Color=10, 26, and even an arbitrary nonzero 999 when all other fixture evidence is supplied. This is **eligibility only**, not permission to bypass FormatBridge validation.
7. **No attach does not prove a Color diagnosis:** `wuwa_ingress.cpp:254-285,830-834` tries attachment first; readiness failure leads to compatibility probing. A failed normalize prevents that probe reaching `probe_runtime_frame()`. The missing attachment can involve runtime/queue readiness; fixing a shape rejection would not by itself prove those prerequisites ready.

## Format-independent rejection investigation / CPU reproduction

The CPU tests link the unchanged frozen `format_plan.cpp` and adapter policy. Inputs are explicitly synthetic, NOT live resource measurements.

| Fixture | Result |
|---|---|
| PRE ordinary SR, expected_calls=3, render/guide=4099x2306, output=6144x3456; typed RGBA16/34/41, single mip/array/sample, fitting bases, state 0x40 | **ready** |
| Same valid fixture with expected_calls=1..10 | **ready** |
| Hypothetical Color resource=26 with host's contract=1/view=10 | unsupported_format |
| Change only view to 26, leave contract=1 | unsupported_format |
| Explicit contract=2 and resource/view=26 (fixture attestation only) | **ready** |
| Change only contract to 2, leave view=10 | unsupported_format |
| expected_calls=0 or 11 | invalid_extent, irrespective of otherwise-valid formats |
| PRE with RR | unsupported_topology |
| Active rect exceeds resource / negative base | invalid_subrect |
| Positive base with sufficient padding | **ready** |
| DENY_SHADER_RESOURCE, multiple mips, multisampling | unsupported_texture |
| Color aliases MV | alias_conflict |
| Combined UAV + non-pixel-read declared state | invalid_state |
| Missing same-frame attestation | missing_attestation |
| WuWa typeless MV/depth | unsupported_format |

**No guaranteed format-independent invalid_plan follows from the supplied dimensions and ordinary-SR/PRE3 topology.** Odd widths/heights have no divisibility constraint in the validator. The bridge's descriptor prefilter additionally requires TEXTURE2D, array=1, mip=1, sample count=1, layout=UNKNOWN (`bridge.cpp:107-112`); the receipt includes these fields.

The compatibility budget receipt deliberately uses `passes=0` for disabled NR allocation (`wuwa_ingress.cpp:584-598`). The normalize call uses **`control.pipeline.effective_passes`**, not that zero (`:709-710`). The latch defaults to 1 (`native/common/control.h:87-103`) and startup accepts protocol passes 1..10 (`host/host_state.cpp:123-129`, `protocol/pipeline_v1.h:20`). A displayed effective NR count of zero also is not this latch. Do not “fix” the probe to accept zero calls based on the budget receipt. The new receipt captures the actual expected count.

## PRE GPU-input state finding

`wuwa_ingress.cpp:633-637` (probe) and `:900-907` (normal dispatch) hardcode Color/MV/depth to `NON_PIXEL_SHADER_RESOURCE` = **0x40**. The normal binding marks resource states attested; this is a declaration, not a query or tracked barrier history. `WuwaFrameSnapshot` has no state fields. No host ResourceBarrier state-tracking hook was found.

`format_plan.cpp:53-68` validates only the declared state's bitmask. 0x40 passes. `bridge.cpp:608-669` transitions external inputs from the declared state to 0x40 and back. For PRE's 0x40 -> 0x40, **no external-input transition or restore is recorded**. A real resource still in render-target/UAV/another state could cause a later GPU correctness problem, but cannot explain a CPU `invalid_state` when these unchanged declarations are 0x40. The SR Evaluate occurs after the PRE ingress (`native/host/pipeline.cpp:318-337`), so it cannot retroactively prepare inputs for earlier bridge reads.

**GetDesc does not expose actual GPU state.** The sidecar explicitly says `actual_gpu_states_verified:false` and labels values `declared_state`. This review neither verifies nor changes the seam-state contract. A format fix alone must not be portrayed as GPU-state validation.

## Minimal diagnostic implementation

Changed production source (all inside the clone):

- `source/native/host/wuwa_ingress.cpp`: capture only on the existing failed normalize path when `status.code == invalid_plan`; mark compatibility-probe versus ordinary dispatch; publish from the existing worker.
- `source/native/host/wuwa_normalize_diagnostics.h`: private CPU value records and bounded JSON formatting.
- `source/native/Makefile`: header dependency; full proposal also adds CPU test integration.
- `source/native/tests/wuwa_normalize_diagnostics_test.cpp`: shape, adapter-policy, bounded recorder and serializer fixtures (full patch only).

Future sidecar: `<existing host state_directory>\\wuwa-normalize-failure.jsonl`.

- First **8 invalid_plan failures per process**, fixed storage; preserves earliest failures, no rollover. Additional failures only increment observation/suppression counters. `GetDesc`/`GetType` capture itself stops after the cap.
- Header carries PID, session nonce, publication time, capacity/counts/capture policy. Rows carry frame/owner/time, probe flag, numeric status code + name, numeric/text plan reason, HRESULT bits/hex, profile/phase/reconstruction/contract, expected calls, all plan attestations, render/output extents, raw flags/reset/ABI/list type.
- Source/MV/depth/POST-output records include **every GetDesc field**, host-requested view format, declared state, subrect base, and frame-local equality token for alias detection. PRE normalize has no game_output resource; its null record is intentional, not a missing game SR Output.
- Descriptors are read immediately after the failed call while its borrowed resources are still in scope. GetDesc metadata is immutable. Returned `Status` is recorded directly; normalize/validator are **not rerun** by the diagnostic. No retained COM references or raw pointer addresses in receipts.
- Only the existing telemetry worker formats/writes, at most once/second, atomically replacing a sidecar smaller than **33,280 bytes**. No extra thread. Failed I/O is retried on a subsequent worker poll; no partial JSON is published. Abrupt process exit before polling may prevent publication.
- No resource data readback, resource mutation, barriers, dispatch, queue submissions, GPU waits, parameter edits, state/status/admission/capability changes, or validator relaxation are added. This is read-only with respect to game/graphics state, not with respect to the diagnostic file. Existing baseline compatibility behavior is unchanged.
- Limited deliberately to `invalid_plan`; absent output does not prove success. Other failure codes, unattempted normalization, publication failure or a stale PID/session need separate interpretation. First eight rows might capture only an early topology; check phase/reconstruction/frame before drawing conclusions.

## One later cold retry — decision plan, NOT an instruction to act now

1. Keep the current game session and NR OFF untouched. This proposal does not make the existing loaded DLL diagnostic-capable. Any installation/restart requires a separately approved cold deployment/package review; no automatic installer or game runner is provided.
2. If authorized later, use the **diagnostic-only** change with the same intended latched PRE3 + ordinary-SR configuration; do not combine it with an R11 fix. The already-observed compatibility-probe failure can be diagnosed with NR OFF; enabling NR is not required for this probe path. No request here to re-enter the game now.
3. From that single session, preserve the normalize sidecar and budget sidecar, matched by PID/session/frame/owner. Read status/plan_reason first, then all three resource descriptors, bases, declared states, topology, and expected_calls. Do not infer the source format from the SR mode, shader code or a POST output format.
4. Only if the captured Color is 26, the guides/shapes pass the unchanged strict requirements, **and independent evidence attests RGBA16F replacement acceptance at this exact signed SR seam**, consider a later scoped mapping of contract=2 **and** view=26. Neither a blind format-auto-detect fallback nor changing the validator is proposed. If Color=10, leave contract/view unchanged and investigate the actual recorded failing predicate. If the actual format is something else, the existing explicit R11 contract is not the answer.
5. The sidecar will not verify live GPU resource states, replacement acceptance, runtime NR execution or image quality. Do not claim a format correction safe/complete solely from this CPU review.

## Verification and artifacts

All commands ran in the isolated proposal directory:

- `make -C source/native build/wuwa_normalize_diagnostics_test` and execute the **Linux CPU binary**: all fixtures passed.
- `make -B -C source/adapters/format_bridge build/test_format_plan source-check`; execute CPU `test_format_plan`: passed.
- New fixture compiled/run with `-fsanitize=address,undefined`: passed; Python parsed synthetic JSON and verified status/HRESULT fields, integer extremes, resource formats and null PRE output.
- Rebuilt/executed existing Linux policy, adapter_commit_policy, loader_hardening and factory_hooks tests; crosscompiled DXGI vtable object; native `tests/source_checks.py`: passed.
- `make -B -C source/native build/dlss5-native-host.dll`: isolated MinGW host + format-library link passed. It also crosscompiled shader/link-smoke EXEs but did **not execute** them. No Wine, shader-check, game run or GPU test.
- Both patches reverse dry-run cleanly against the proposal clone. Full patch forward-applied to `patch-check/` inside the proposal and reproduced all four changed source files byte-for-byte.
- Scope checks: exactly four non-build source content changes; unchanged validator/shaders/adapter policy/runtime source; all frozen source hashes unchanged.

Artifacts:

- `diagnostic-only.patch`: production host/header change + Makefile header dependency only.
- `proposal.patch`: **alternative** full patch, production diagnostic plus CPU test/Makefile integration. Do not apply both patches cumulatively.
- `source/`: exact frozen clone plus the four scoped source changes and isolated build outputs. Crosscompiled DLL is **not deployed or claimed game-validated**.
- `CPU_TESTS.log`, `REGRESSION_TESTS.log`, `SANITIZER_JSON.log`, `CROSSCOMPILE_HOST.log`, `PATCH_VERIFY.log`, `SCOPE_VERIFY.log`.
- `SYNTHETIC_RECEIPTS.jsonl`: serializer fixtures only; first row is a hypothetical R11 mismatch, second is integer/HRESULT stress. **Neither is a live-game receipt.**
- `FROZEN_SOURCE_SHA256SUMS`, `PROPOSAL_SOURCE_SHA256SUMS`: sorted `sha256  relative-path` manifests of all source-tree files including copied/build artifacts. Tree identity is SHA256 of the corresponding manifest bytes, not a Git commit.
- `CHANGED_SOURCE_SHA256SUMS`, `ARTIFACT_SHA256SUMS`: scoped-source and top-level artifact checksums.

### Identities

- Frozen/initial exact clone tree manifest SHA256: `4c8a2cd06c6de1f1db7cdad95b9c1299f076794d3b8614a5ec35e5b858d7d3ea`.
- Final proposal clone tree manifest SHA256: `0bdc50aefe18dad94fb3fe4737eda70b06d0b281ce00163d80b9c49421f167a9`.
- Frozen host DLL SHA256: `14756feb6ab43e3bfb6dae5c6fe4fdc40fcadf75c54e25557ec004c7c639a072`.
- Isolated diagnostic host DLL SHA256: `1d2052265991fc15c22ad602229a48dd1c04c54c32eb0f8c9bdcb3e759885991`.
- Runtime DLL unchanged: `9e0154fac9d821f9d51a18e7fe163114e12b9f0924e93e7bb724aeb3bf80caaa`.
