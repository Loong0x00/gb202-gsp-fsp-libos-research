# Autonomous virtual PRE3 runner — CPU-only proposal

Status: **this worker did not install or execute anything against the game**. Main owns diagnostic packaging, review/integration, the actual Gamescope launch and the explicit stop after its diagnostic. This worker changed only this new review directory. `baseline/` contains exact copies of the latest Main runner/tests, including the temporary-disable-rr prepared/applying/applied/restored journal and scoped rollback.

## Proposed changes

- `tools/run_wuwa_case.py`: adds `--autonomous-virtual-pre3`. It requires `--experimental-pre3-cinematic --order pre_sr --passes 3 --no-time-limit`, no `--physical`, initial NR OFF, and exactly **6144x3456**. All frozen/POST5/zero-reserve flags are rejected in this scope.
- Physical and virtual actions now use **one shared SR confirmation and NR-enable route**. There is no virtual `nr` bypass. Explicit confirmation requires fresh (0–2 seconds old) ordinary-SR runtime evidence, matching cold-request sequence, requested PRE3 and effective PRE order. Enable rechecks that evidence. RR/none/stale/future/wrong-sequence evidence never enables NR. Lease, signature, reserve/admission, hardware and graphics-error guards remain unchanged.
- `--temporary-disable-rr` can be used in this explicit virtual scope. The existing cold-only Engine.ini journal/one-key restore functions and rollback block are unchanged. The only Engine.ini change is `r.NGX.DLSS.DenoiserMode=0`; no Quality/other RT changes. Virtual GameUserSettings.ini edits remain backed up/restored and are limited to resolution/window keys. Existing Quality bytes are preserved, **not inferred as proof of effective in-game Quality**; Main must verify effective 6K Quality using its diagnostic/evidence/screenshots.
- Existing inherited Gamescope DISPLAY/xrandr checks, read-only display-selection DB checks, virtual click/Return/Escape actions and periodic/action-followup screenshots remain. Physical mode still rejects automated input and takes no screenshots. No account DB backup/restore or writes were added.
- `tools/run_autonomous_virtual_pre3.sh`: new separate launcher proposal, **not a modification of the old bounded launcher**. Uses `--property=RuntimeMaxSec=infinity`, `--no-time-limit`, 6K, cold RR override, initial OFF, Cinematic PRE3, strength maxima and HDR transfer .6. Does not issue confirm/enable actions. Stop/fault/game exit still rolls back; `TimeoutStopSec=90` is teardown grace, not a session limit. Screenshots accumulate as before; Main must stop after collecting its diagnostic.

## Main integration / usage

`proposal.patch` is a unified patch against the recorded Main baseline, covering the Python runner, new launcher and test changes. **Concurrent Main adoption detected at final verification:** Main's runner now already contains the proposed runner changes plus its diagnostic pins and normalize-failure sidecar ownership (observed SHA256 `07c7f3bc00e968819b6d64d7d9c2976dc01ef3636005df327e7552457aa709f8`). See `main-concurrent-delta.diff`; these Main additions were not edited by this worker. **Do not overwrite Main with this review copy or reapply the baseline patch**; preserve its pins/sidecar changes. The remaining new tests/launcher can be reviewed separately. Full proposed files are also included. The review-copy ROOT intentionally remains its own directory: it is not a hidden pointer into Main and is not a ready-to-run game deployment. Main must integrate the reviewed tools into its project (with its existing adapters, frontend and pinned bundles) before actual use. Use ordinary Python, not `-O`, because existing safety checks use assertions.

CPU-only command preview, safe in this review directory:

```sh
bash tools/run_autonomous_virtual_pre3.sh --dry-run
```

After Main integration, the same launcher **without** `--dry-run` is the proposed actual launch. Do not use `tools/run_native_wuwa.sh` for this scope: the unchanged old wrapper has `RuntimeMaxSec=450` and does not forward the new flags.

Main sends individual atomic `action.json` requests in the actual run directory, waiting for each `actions.json` receipt:

1. Navigate only as needed using existing virtual `click`/`key` actions; inspect screenshots and diagnostics. Confirm 6K Quality and ordinary SR while NR remains OFF.
2. For the supplied cold-override launcher: `{"action":"confirm_cold_startup_sr","confirmed":true}`. Runner checks its applied RR journal, Engine.ini RR0, and fresh matching runtime SR evidence. This is **not a claim that a physical user toggled a menu**.
3. Only after a successful confirmation receipt: `{"action":"nr","enabled":true}`. The runner revalidates evidence before writing control; a control receipt is not GPU completion.
4. Main collects its diagnostic and sends `{"action":"stop"}` (or NR OFF first if needed), then checks `RESTORED.json` and `startup-rr-override.json`. No elapsed-time stop is added by this proposal.

Without `--temporary-disable-rr`, explicitly select actual ordinary SR and use `confirm_actual_sr_no_rr` instead. False menu assertions during a cold override are rejected. Invalid confirmation/action faults still stop and roll back, following the existing runner behavior.

**Known evidence blocker:** the archived current PRE3 run initially reports `reconstruction: none` with NR OFF. This proposal deliberately does not reinterpret that as SR or enable NR to discover SR. If the current bundle cannot produce fresh ordinary-SR evidence while OFF, Main needs its reviewed diagnostic package; otherwise stay OFF and stop. CPU tests establish neither effective rendering configuration nor PRE3 GPU completion.

## Optional diagnostic package: disabled until Main fills pins

The existing PRE3 bundle and all its original manifest/DLL/controller pins are retained:
`reviews/wuwa-pre3-cinematic-20260910-204000`.

`--pre3-diagnostic-package /absolute/project/reviews/EXACT_REVIEW/package` is accepted **only** with explicit autonomous virtual PRE3 and an exact entry in the Python `PRE3_DIAGNOSTIC_PINS` constant. The shipped dictionary is empty. There is no caller-supplied hash override, wildcard, arbitrary development package fallback or POST5 authorization reuse.

Main must fill a ROOT-relative `reviews/...` directory key and six exact SHA256 fields: `manifest`, `source_manifest`, `dxgi`, `host`, `runtime`, `controller`. The controller must retain the existing approved controller hash. All six are verified before manifest verification/source-manifest generation or controller import. The diagnostic layout must provide `package/{SHA256SUMS,SOURCE_SHA256SUMS,bin/...}`, `source/native/` and `controller-core.py`. Path aliases/symlinks to alternate bundle directories are rejected. Main must audit that diagnostic source preserves normal nonzero reserve and all existing gates; a pinned hash alone does not establish those semantics.

Forward the optional exact path through the new shell wrapper using the same flag. Adding placeholders without complete real pins fails closed.

## Verification

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -B run_cpu_tests.py
bash -n tools/run_autonomous_virtual_pre3.sh
PYTHONDONTWRITEBYTECODE=1 python3 -B tools/run_wuwa_case.py --help
```

36 tests pass in both ordinary discovery and the guarded harness (`cpu-tests.log`, `cpu-tests-audited.log`). The harness restricts Python mutations/SQLite connections to its temporary tree and external execution to the launcher **dry-run** only. The copied publisher regression uses actual SQLite solely in temporary fixtures; frontend/publisher modules are imported read-only from the existing local project. No Wine, GPU commands, game/service/display launch, account DB access or secrets are needed by these tests.

Coverage includes scope/6K CLI rejection, original physical frozen POST2/experimental POST5 scope, initial OFF/unlimited operation, shared physical/virtual actions, fresh SR and cold RR checks, no virtual auto-enable, every diagnostic-pin mismatch, arbitrary-path rejection, quality-preserving INI transformation, cold RR journal/scoped rollback, and launcher infinity/no POST5 flags. Archived baseline-copy hashes were rechecked unchanged; patch replay is checked only in a temporary copy. A recheck against live Main detected the concurrent runner adoption described above (all six original Main test files still match the baseline). `main-baseline-check.log` records that expected runner mismatch; it is not a claim that Main remained unchanged.
