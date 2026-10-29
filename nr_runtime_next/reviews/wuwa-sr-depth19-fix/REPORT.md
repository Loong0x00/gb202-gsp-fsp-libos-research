# WuWa ordinary-SR depth19 fix — CPU-only candidate

## Result

Based solely on frozen `../wuwa-pre3-normalize-main-20260910-211925/source`.
All work/output stays in this new review. No Main, frozen, game/config, signed
DLL, GPU, or Wine operations. Host/runtime DLLs are cross-build artifacts only;
nothing was installed, loaded, signed, or tested in the game.

The copied live receipt is byte-identical to:
`/home/user/rt_5090_project/nr_runtime_next/wuwa-runs/20260910-212737-native-pre_sr-3-initial-off-6144x3456/MAIN_NORMALIZE_FAILURES.jsonl`

All eight records have ordinary SR/PRE3, `unsupported_format`, and:

| Resource | Resource / caller view | Size | Flags | Declared state |
|---|---|---|---|---|
| Color | 10 / 10, RGBA16F | 4100x2308 | 1 | 64 |
| Motion | 34 / 34, FLOAT2 | 4099x2306 | 4 | 64 |
| Depth | 19 / **wrong 41** | 4100x2308 | 2, depth/stencil | 64 |

Active render 4099x2306; output 6144x3456; bases zero; single mip/array/sample.
The fix derives its **own** view21 (`R32_FLOAT_X8X24_TYPELESS`) from actual
GetDesc resource19, for ordinary SR only. This is NOT evidence that the game
used view21. The receipt's caller view41 is the old normalizer's request.
Actual GPU states remain unverified by these receipts/CPU tests.

## Contracts updated (and deliberately not updated)

1. **Host view selection**: replace unconditional depth41 with a narrow shared
   selector: resource19 -> view21 for ordinary SR; resource41 -> view41 for
   existing SR/RR; everything else -> UNKNOWN, subsequently rejected.
   This applies to the shared ordinary-SR PRE/POST normalization path, not RR19.
2. **make_evidence**: explicitly document/preserve actual GetDesc format19.
   Its existing field mapping was already correct and is not rewritten to
   21 or 41. `ResourceEvidence.format` is a resource format, not a game SRV
   observation. CPU normalization test verifies evidence retains 19.
3. **Adapter policy**: formerly checked only nonzero formats. Add a WuWa-only
   depth-resource allowlist matching the selector (SR19/41, RR41). Unsupported
   nonzero depth formats return the existing `format_contract_not_ready` reason.
   No ABI field/reason-enum changes. Color/MV policy remains as before; exact
   color/MV/view/descriptor validation remains the format bridge's job.
4. **Format-plan validation**: accept only the exact new WuWa SR pair19/21,
   alongside existing41/41. Wrong19/41, resource21, stencil-view22, DSV20,
   unrelated typeless39, unknown formats, and RR19 remain rejected.
5. **Build/test dependencies**: track the shared header and add CPU regression,
   cross-compile enum mapping, source/descriptor/scope checks.

No change to bridge descriptor/shader implementation was needed: it already
creates its own plane0 SRV, default R-component mapping, `Texture2D<float>`
load into `RWTexture2D<float>` on an owned R32_FLOAT UAV. Existing device format
support checks remain mandatory. This reuses the depth-only path already used
by HSR; no stencil copy, unlike-format copy, shader regeneration, or runtime
format expansion was added.

HSR exact-guide/typeless-MV/shared-copy contracts, RR41 POST, RR PRE prohibition,
RGBA16F PRE color, normal reserve, style2, PRE one-original-SR control flow,
reset/settle/loading/budget/lease/commit/lifetime guards, protocol/native/evidence
ABIs, runtime sources, and all shader bytes remain unchanged. A scope check
compares every frozen source file; only five existing files differ (listed below).
The first live reset frame still bypasses normal adapter dispatch; accepting a
shape is not a claim of full frame eligibility or GPU execution.

## Files changed relative to frozen source

All paths below are relative to this review directory:

- `source/native/host/wuwa_ingress.cpp`: own depth view selector; evidence clarification.
- `source/adapters/common/wuwa_depth_contract.h` (new): narrow shared selector/pair contract.
- `source/adapters/common/policy.cpp`: WuWa depth-resource gate only.
- `source/adapters/format_bridge/format_plan.cpp`: exact SR19/21 pair validation.
- `source/adapters/format_bridge/Makefile`: shared-header dependencies.
- `source/native/Makefile`: new CPU/mapping/source checks.
- `source/native/tests/wuwa_sr_depth19_test.cpp` (new): exact live shape, frozen/new comparison, policy, rejects, RR/HSR/guards.
- `source/native/tests/wuwa_sr_depth19_mapping_test.cpp` (new): compile-only DXGI/D3D12/native enum/ABI mapping assertions.
- `source/native/tests/wuwa_sr_depth19_source_checks.py` (new): all-eight live descriptor match, actual descriptor/shader wiring, complete frozen-source scope comparison.
- `run_cpu_checks.sh` (new): reproducible CPU-only verification.
- `evidence/MAIN_NORMALIZE_FAILURES.jsonl`: unmodified evidence copy.
- `REPORT.md`, `verification/`: this report, patch/manifests, logs, isolated CPU comparison executable.
- `source/native/build/`, `source/adapters/format_bridge/build/`: local CPU/cross-build products only.

## Verification

Run `bash run_cpu_checks.sh` from this directory. PASS:

- `make -C source/native cpu-check -j2`: host/runtime/bootstrap cross-build;
  new regression/mapping/source checks; existing diagnostics, policy, commit,
  loader, factory, ABI/export/isolation/completion checks.
- `make -C source/adapters/format_bridge build/test_format_plan source-check`
  and `source/adapters/format_bridge/build/test_format_plan`: existing format,
  state, commit, lifetime, shader-source checks, including HSR SNORM behavior.
- Same new exact live fixture compiled against frozen `format_plan.cpp`:
  **19/41 rejected; legal19/21 also rejected**. Against fixed planner:
  **19/41 still rejected; SR19/21 accepted**.
- Read-only all-eight receipt comparison; descriptor mapping static assertions
  against installed MinGW D3D12/DXGI headers; shader/descriptor wiring checks.
- Copied proof compared with original using `cmp` (identical).

Logs: `verification/native-cpu-check.log`, `verification/format-cpu-check.log`,
`verification/frozen-regression.log`, `verification/run.log`.
Artifact/evidence SHA256: `verification/SHA256SUMS`.

## Required next step — Main-owned GPU test BEFORE game

Not executed here. Main must use owned resources and the actual bridge/shader:

1. Create resource19 depth/stencil (flags2), legal DSV20 for initialization,
   and the bridge's own depth-only SRV21/plane0. Use exact live padding/active
   extents and correct explicitly tracked GPU states.
2. Initialize distinct representable depth values (e.g. 0, .25, .75, 1) in
   regions, independently vary stencil (0, 0x7f, 0xff), and poison padding.
   Convert with the real bridge to owned R32F; read back after fence completion.
3. Verify depth values exactly for these representable inputs, identical output
   when only stencil changes, correct active cropping/odd edges, and R32F output
   (not packed/stencil data). Check validation-layer errors, state restoration,
   resource lifetime/fence completion, and device format support. Keep declared
   states and actual states distinct in the resulting proof.
4. Only after that passes, Main may decide on game validation. No game success,
   depth/stencil GPU separation, signed SR delivery, or quality claim is made here.
