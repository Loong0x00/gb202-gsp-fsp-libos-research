# DLSS5 frontend real-use CPU/static audit

Date: 2026-09-10

## Scope and safety

This was a read-only audit of the active frontend wiring, current `app.py` / `core.py`, the three saved profiles, installed backend/control evidence, desktop launchers, and source tests. No frontend source, saved profile, game file, Wine process, game, GUI, or GPU workload was started or changed. Profile environment values and unrelated private configuration were not read into this report.

## Executive result

The reported behavior is reproducible from the installed state and source:

1. **The new order/pass topology controls cannot work against the restored production installs.** CP2077, WuWa, and HSR currently contain the legacy **DLSS5 Post Service**, not the owned native runtime. None has `pipeline-capabilities.json`, `pipeline-control.bin`, or `pipeline-status.json`, and none has a native runtime/host evidence file. `core.py:383-394` therefore correctly rejects D5RP capability, and `app.py:565-579` deliberately disables both topology widgets. Enabling these widgets without a real native deployment would manufacture capability and would be wrong.
2. **WuWa has a real profile/backend mismatch.** Its installed backend is Post Service, but its saved `control_only` is `false`. The overview treats Post Service as attachable (`core.py:1409-1431`), while the install button branches only on `control_only` or native detection (`app.py:820-844`). WuWa consequently enters the historical ReShade/RenoDX installer, not the Post Service control path.
3. **CLI and some GUI messages can report success when controls were not acknowledged/applied.** `cli_apply()` returns nonzero only for exceptions. D5LC timeout and every non-active D5RP result, including `unsupported_capability` and `error`, still leave exit status 0 (`app.py:1054-1080`). The control-only install handler says “request saved” for any non-active D5RP result even when no request was written (`app.py:830-833`).
4. **The frontend's launch routes do not match the user's real launchers.** The GUI bypasses the CP Steam desktop route, the WuWa 6K/phase-gate wrapper, and the Honkers launcher. `Popen()` success is immediately labeled “game started” without checking an immediate exit or a real game process (`core.py:1580-1596`, `app.py:859-871`).
5. **Startup is synchronous, mutating, and incompletely guarded.** It scans game trees, prepares/writes the legacy component store, and rewrites `profiles.json` before constructing the UI (`app.py:87-108`; `core.py:1488-1523`). A load failure is silently converted to a default profile and can then overwrite the existing store. Several startup and callback I/O paths are uncaught.

The currently installed directories and profile store are readable and writable by the current user. The present failure is therefore **not explained by filesystem read-only permissions**; it is primarily the restored legacy topology plus control/launcher/error-reporting mismatches.

## Active frontend and launch wiring

### Frontend desktop entry

The installed desktop entry is the active one:

```text
~/.local/share/applications/io.github.local.DLSS5Linux.desktop
  Exec=/home/user/.local/bin/dlss5-linux

/home/user/.local/bin/dlss5-linux
  exec /usr/bin/python /home/user/rt_5090_project/dlss5_linux_frontend/app.py "$@"
```

At audit time, the running process command line was exactly `/usr/bin/python /home/user/rt_5090_project/dlss5_linux_frontend/app.py`. Thus the desktop does not point to an older copied `app.py`; edits in this source directory would be immediately active on the next process start.

Python 3.14.7, GI, GTK 4.22.4, and libadwaita 1.9.3 import successfully. No relevant frontend traceback was present in the inspected user-journal window. This does **not** prove GUI behavior is healthy; no GUI was opened or exercised in this audit.

### Current profiles and on-disk control evidence

| Profile | Saved/observed backend state | D5RP evidence | D5LC evidence on disk | GUI launch command built by `core.py` |
|---|---|---|---|---|
| CP2077 | `control_only=true`; Post Service add-on present; no native host/runtime | all three D5RP files absent | matching control/status, enabled; no D5LC freshness/session check exists | direct GE-Proton `waitforexitandrun` of `Cyberpunk2077.exe` |
| WuWa | **`control_only=false`**; Post Service add-on present; no native host/runtime | all three D5RP files absent | enabled control exists, status absent | `/usr/bin/steam -applaunch 3513350` |
| HSR | `control_only=true`; Post Service DLL present; no native host/runtime | all three D5RP files absent | matching control/status, disabled; no D5LC freshness/session check exists | launcher Wine binary directly executing `StarRail.exe` |

A matching saved D5LC status is only an on-disk sequence match. Unlike D5RP, `installation_status()` applies no age or live-session test, so CP/HSR can continue to be labeled “current control read back” after the producing runtime exits (`core.py:1415-1431`). WuWa truthfully lacks a D5LC acknowledgement in the current files.

The user's actual desktop routes are different:

- CP2077: `steam steam://rungameid/1091500`.
- WuWa: `/home/user/.local/bin/wuwa-dlss5-6k-launch`, which edits/validates its display state, manages router markers and the phase-gate service, then launches Steam. The frontend's direct Steam route bypasses that wrapper.
- HSR: `/usr/bin/the-honkers-railway-launcher`. The frontend's bare Wine route bypasses launcher orchestration/patching. The paths exist, but that is not evidence that the direct route is equivalent.

For `control_only` CP/HSR, `validate_profile()` returns after executable/backend checks and never reaches runner validation (`core.py:626-637` versus `664-678`). For mismatched WuWa it does the opposite: it validates the historical bridge/RenoDX/ReShade bundle even though Post Service is the selected backend.

## Concrete findings

### F1 — D5RP UI disablement is correct for the restored installs (blocker, not a widget defect)

`pipeline_capability_for_game()` accepts D5RP only when a strict capability object and an owned native host/runtime file coexist. All three current installs lack both. The project restoration record also says production CP/WuWa/HSR deployments were restored rather than permanently migrated.

Result: the UI always executes the `capabilities is None` branch and disables order and pass count. Saving `nr_pipeline={post,1}` in a legacy profile does not install or enable D5RP.

**Do not “fix” this by relaxing the evidence gate or synthesizing a capability file.** Either deploy the native backend through the separately reviewed migration path, or present topology as unavailable on this legacy backend while leaving D5LC scalar controls usable.

### F2 — WuWa's `control_only` mismatch sends Install to the wrong implementation (high)

`ProfileStore.load()` refreshes `profile.backend`, but only `autofill_components()` converts a profile to control-only, and it does so only for a proven native backend (`core.py:746-758`, `1488-1514`). It never normalizes an already installed Post Service profile. Therefore WuWa remains `control_only=false` after every load.

The resulting branches disagree:

- Overview: treats Post Service as installed/attachable regardless of `control_only`.
- Apply: writes D5LC and skips RenoDX INI because Post Service wins backend detection.
- Install: enters `install_profile()`, whose job is explicitly the historical installer. It can copy bridge/add-on/runtime/ReShade files and edit `ReShade.ini` (`core.py:1227-1284`).

This is not merely cosmetic. “Connect / install” can perform a legacy installation over a directory already using Post Service.

### F3 — Control result handling is internally inconsistent (high)

- `set_neural_uplift()` writes one D5LC request, then `apply_runtime_control()` immediately writes a second request and waits only for the second sequence (`app.py:823-826`; similarly `735-750`). This creates unnecessary races/noise.
- `apply_pipeline_control()` is comparatively sound: absent capability returns `unsupported_capability`; write errors become structured `error`; D5LC can never prove D5RP active (`core.py:1073-1119`). The GUI/CLI discard that distinction.
- The install toast reports “request saved” for `unsupported_capability`, although `request_written` is false.
- `cli_apply()` counts only raised exceptions. `live=False`, `pipeline.outcome="error"`, `unsupported_capability`, stale/mismatch/unconfirmed, and pending results all still return 0.
- `on_master_toggled()` and `on_apply_settings()` do not catch store/game-state I/O errors (`app.py:735-774`). A read-only state directory raises out of the GTK callback instead of producing the Advanced-page error handling used by Install/Launch.
- “Apply all” reports a target as processed even when D5LC timed out and D5RP was unsupported; its top-level profile save is also outside its per-target error handling (`app.py:776-811`).

### F4 — Read-only capability handling is good; D5LC/UI handling is not (medium)

A temporary CPU-only harness with a readable capability file in a non-writable state directory established:

- capability read succeeds;
- D5RP apply returns structured `outcome="error"`, `request_written=false` on permission denial;
- D5LC apply raises raw `PermissionError`.

Capability/status parsing itself is bounded, strict, fail-closed, and request-correlated. Actual CP/WuWa/HSR state directories are writable now, so this is an error-path defect rather than the cause of today's legacy-topology disablement.

`detect_dlss5_backend()` also calls `directory.iterdir()` without an `OSError` guard (`core.py:407-425`), so an unreadable game directory can still escape otherwise graceful capability handling.

### F5 — Startup can stall, rewrite state, hide the original error, or fail invisibly (high)

Before the window is built, `MainWindow.__init__`:

1. loads profiles;
2. for the current WuWa mismatch, prepares the legacy component store;
3. synchronously scans configured Steam/common, HSR, and Games roots for backends;
4. auto-fills every non-control-only profile again;
5. unconditionally saves all profiles.

`ProfileStore.load()` also calls `recommend_render_executable()` for every executable; for a non-Shipping Steam executable this may recursively glob that game's tree. All of this happens on the GUI thread. The explicit “Scan installed” button already exists, so the startup scan is unnecessary.

Error behavior compounds this:

- A `FrontendError` while loading is discarded with no visible diagnostic (`app.py:87-92`).
- The code then creates a default and unconditionally saves, which can overwrite a readable but semantically failed store.
- `default_profile()`, component status, discovery, and `store.save()` can raise outside that narrow catch.
- Store schema is not explicitly checked. A non-object JSON root or non-object profile entry can raise `AttributeError`, which `ProfileStore.load()` does not catch.
- `do_activate()` has no exception boundary, while the desktop entry has `Terminal=false`; callback/activation tracebacks are not presented in the application.
- `gi` is imported before CLI argument parsing, so even non-GUI validation/apply commands unnecessarily require the GUI Python stack.

The current saved JSON is structurally valid and the active GUI process exists, so no unsupported claim is made that one of these latent exceptions caused the present running instance to fail.

### F6 — Launch success is process-spawn success, not game success (medium)

`launch_profile()` returns immediately after `Popen()`, and `on_launch()` immediately reports “game started (PID ...)”. There is no immediate-exit check, launcher handoff classification, or game-process confirmation. A CP frontend log proves Proton setup was invoked, but does not by itself prove the game became healthy. The WuWa frontend launch log is empty, and there is no corresponding frontend HSR log; absence is not proof of failure, but there is no end-to-end proof of success either.

The generic runner model cannot represent the actual WuWa wrapper or Honkers launcher. It also cannot guarantee that environment changes passed to a second `steam -applaunch` client become the environment of a game launched by an already-running Steam process.

## Source unit tests versus installed end-to-end

`tests/test_core.py` contains 26 tests and imports only `core.py`. It does not cover `app.py`, `MainWindow`, button handlers, `cli_apply()`, the installed desktop entry/wrapper, or `launch_profile()`/real launcher handoff.

CPU-only verification results:

- Python AST parse: `app.py`, `core.py`, and `tests/test_core.py` pass.
- With a temporary copy of the user's existing archived component store, all **26/26 core tests pass** in 1.097 s.
- With an empty isolated component store, **3 tests fail/error** because no current known source has the hard-coded expected Vulkan bridge hash. This shows the suite is not hermetic and depends on a pre-populated per-user artifact store/real installation state.

These are source/unit results only. No real desktop click, GTK interaction, profile rewrite, Wine/Proton launch, game launch, D5LC live exchange, native D5RP exchange, or GPU path was tested here. Existing native runtime acceptance artifacts do not make the currently restored Post Service installs native end-to-end tests.

## Minimal recommended edits for Main

1. **Keep the D5RP evidence gate.** For Post Service/RenoDX/Vulkan Bridge, label topology “Unavailable on restored legacy backend (D5LC scalars only)” rather than presenting it as a potentially savable/applicable request. Do not enable order/passes until real capability plus native evidence exists.
2. **Normalize attachable backend state in one helper.** On load and immediately before Install, derive mode from actual backend evidence. At minimum, set Post Service and native profiles to `control_only=true`; use that same helper in overview, validation, component visibility, Apply, and Install. This fixes current WuWa without relaxing native D5RP checks.
3. **Make Install truthful and non-destructive for an installed Post Service.** The Post Service branch should write D5LC once, skip D5RP as unsupported, and never call the historical bundle installer. Show separate D5LC and D5RP outcomes; never say a D5RP request was saved when `request_written=false`.
4. **Use one operation-result policy.** Catch `FrontendError`/`OSError` in Master, Apply, Apply-all, Validate, startup load/save, and Launch. Record `{channel, requested, written, acknowledged/applied, outcome, detail}` and render it consistently. Remove the duplicate D5LC write.
5. **Fix CLI exit semantics.** Suggested contract: `0` only for fully acknowledged/active requested channels; `3` for queued, pending, unsupported, stale, mismatch, or otherwise partial results; `1` for hard operational errors; retain `2` for no selector match. If legacy scalar-only success is desired, make it an explicit `--scalars-only` operation rather than silently treating unavailable D5RP as full success.
6. **Make startup read-mostly and preserve failures.** Load/validate only; do not scan, prepare component artifacts, auto-fill, or save until an explicit user action. Move installed scanning to the existing button/background worker. Validate JSON root/profile types and retain/show the original store error without replacing the file.
7. **Represent the real launch target.** Add a safe argv/desktop-launcher mode (no shell string): CP should use its Steam route, WuWa its existing wrapper, and HSR the installed Honkers launcher unless a proven direct game command is supplied. Call launcher startup a launcher handoff; only call a game started after an appropriate confirmation. Do not rewrite current profiles until Main/user explicitly approves the migration.
8. **Add controller/CLI tests separate from core protocol tests.** Cover the current WuWa Post Service + `control_only=false` migration, Install branch selection, no-write legacy D5RP behavior, permission errors, CLI partial exit codes, startup preservation of malformed/unreadable stores, and launcher dispatch. A real installed desktop/UI/live exchange remains a separate end-to-end acceptance step.

## Bottom line

No frontend fix was applied by this audit. The immediate real-use blockers are concrete: restored legacy deployments have no D5RP capability; WuWa's stale `control_only=false` selects the wrong Install path; result/exit messages overstate success; and generic launch routes bypass the actual supported launchers. Main should fix those frontend semantics first, while keeping topology disabled until a genuine native deployment supplies capability and status evidence.
