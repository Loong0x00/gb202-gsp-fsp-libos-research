# WuWa physical-desktop acceptance preparation (CPU/static only)

## Scope and disposition

`physical-wuwa-runner.patch` is a reviewed proposal against:

- `tools/run_wuwa_case.py` SHA-256 `af6f43b8...6656dc1`
- `tools/run_native_wuwa.sh` SHA-256 `d5da86dd...f49d0fe`

It was **not applied** to Main. This review launched no game, GPU workload,
Wine/Proton, Gamescope, service, network operation, deployment, or account/DB
write. Only files under `reviews/wuwa-physical-acceptance/` were written.

The patch preserves the old isolated-Gamescope path and adds a `--physical`
path. Physical defaults to the requested first case, POST/2, while order, pass
count, and duration remain selectable.

## Review findings

### Physical runner contract

The proposal:

- passes the caller's actual `DISPLAY` (and optional `XAUTHORITY`) into the
  transient user unit, then rejects a Gamescope display;
- starts no Gamescope/virtual display and makes no width, height, fullscreen,
  or `GameUserSettings.ini` setup write in physical mode;
- executes neither `xdotool` nor `gamescopectl` in physical mode; UI/login/menu
  work is done by the person at the desktop;
- allows physical `action.json` only for NR control, the exact PRE SR
  confirmation, or stop; those files must contain no credentials;
- starts NR disabled, explicitly packs temporary `NREnableUpscaling=0`, keeps it
  zero on every enable request, and restores the exact original D5LC bytes;
- does not alter SR/RR. PRE cannot be enabled until the operator submits
  `{"action":"confirm_actual_sr_no_rr","confirmed":true}` **and** a <=2 s
  runtime status identifies actual `reconstruction:"sr"` and the requested
  `pre_sr` pipeline. RR is rejected, not silently disabled or changed;
- retains the normal `Wuthering Waves.exe` root launcher and exact
  `dwproton-11.0-4/proton` path;
- retains the shared nonblocking `benchmark.lock`, 30..360 s inner limit,
  450 s systemd cgroup limit, and makes the 31,000 MiB guard fail closed if
  `nvidia-smi` is unavailable/malformed; every visible GPU row is checked;
- backs up settings, owned DLLs, live/pipeline controls and statuses, challenge/
  lease files, legacy add-ons/enable marker, signed hashes, and old gate state.
  Restored files use fsync + same-directory `os.replace`, with original mode set
  before replacement; restoration hashes are asserted only after game PIDs are
  gone. Normal game-owned account/DB changes are never rolled back.

The existing native phase-gate service stop/start contract is retained for an
eventual cold run and its original active state is restored. No service command
was executed by this CPU review.

### WuWa output rotation and deferred commit after HSR external POST

No static regression was found in the reviewed Main native host/runtime:

- `NativeRuntime` keeps only chain-owned `decoded`; `Chain` does not retain a
  game output. POST resolves `r.frame.output` on the current Evaluate, after
  EndInterop, copies to that current normalized output, and marks full success
  only after the copy was recorded.
- `FormatBridge::normalize` binds/AddRefs the current frame's rotating output in
  a per-frame slot. `commit()` records the R16G16B16A16 -> current R11 output
  only after an exact `EVALUATED` result/call count; the slot survives until its
  submitted fence retires.
- WuWa normalize -> runtime submit -> exact evaluated result -> bridge commit ->
  built-in host commit ordering remains intact. Ordinary SR and RR WuWa POST use
  `CommitChannel::builtin`; HSR alone can attach as non-self external POST.
- A built-in WuWa pending commit always blocks active publication. HSR's
  external channel can sustain publication only after a delivered frame is
  already proven; gate/reset/owner/game/reconstruction matching remains exact.

The current shared FormatBridge follow-up adds HSR typeless-33/FLOAT-34 support
inside the HSR profile branch; the WuWa format branch and the output-rotation
code above are unchanged. This is CPU/static evidence, not GPU execution proof.

### Current freeze blocker

At review time, Main's in-progress HSR FLOAT-34 follow-up had rebuilt files but
had not refreshed all frozen manifests:

- `native/package/SOURCE_SHA256SUMS` differs for
  `adapters/format_bridge/format_plan.cpp` and its CPU test;
- HSR source/candidate manifests are stale relative to the current source/PEs.

Therefore the existing WuWa runner's source/package preflight correctly refuses
any launch now. **Do not bypass it.** Main must finish/freeze/review its package
first; then rerun `test_review.py` and the exact preflights below. The proposed
physical patch does not weaken this guard.

### Existing live evidence is not expanded

The retained 1080p headless RR POST/1 run is the only positive WuWa result:
1,781 successful layer Evaluates and 890 completion samples. It is not a POST/2,
PRE, physical-desktop, quality, or long-stability acceptance.

The POST/10 attempt failed after connect while NR was still OFF, with zero layer
Creates/Evaluates/completions. The minidump locates a read AV in
`libcrypto-3-x64.dll + 0x363915`; it does not prove cause, does not implicate NR,
and is not a reason to patch/work around crypto, protection, anti-cheat, or the
kernel. Do not rerun POST/10 as the first physical case.

## Owner application gate (after Main freezes the package)

From the project root:

```bash
sha256sum tools/run_wuwa_case.py tools/run_native_wuwa.sh
python3 reviews/wuwa-physical-acceptance/test_review.py
patch --dry-run -p1 < reviews/wuwa-physical-acceptance/physical-wuwa-runner.patch
patch -p1 < reviews/wuwa-physical-acceptance/physical-wuwa-runner.patch
python3 -m py_compile tools/run_wuwa_case.py
bash -n tools/run_native_wuwa.sh
(cd native/package && sha256sum -c SHA256SUMS)
python3 native/tools/source_manifest.py | diff - native/package/SOURCE_SHA256SUMS
```

Stop if either tool preimage hash changed, the review test reports an unexpected
change, either patch command fails, or either native package check differs.
Applying/rebuilding remains Main-owned.

## Physical launch/operator plan

Use a terminal opened inside the actual graphical desktop session, not SSH,
Gamescope, a nested X server, or a virtual display. Do not run the frontend or
another benchmark concurrently. The scripts make no database write; the game
may perform its normal login/account writes, which are not restored.

### 1. First cold case: POST/2

```bash
printf 'DISPLAY=%s XAUTHORITY=%s\n' "$DISPLAY" "${XAUTHORITY:-<unset>}"
xrandr --current                    # must show the real desktop, not gamescope
OLD_RUN=$(cat WUWA_CURRENT_RUN 2>/dev/null || true)
tools/run_native_wuwa.sh --physical post 2 300
UNIT=$(cat WUWA_CURRENT_UNIT)
journalctl --user -u "$UNIT" -f
```

The transient unit returns independently; wait for `WUWA_CURRENT_RUN` to change,
then in another terminal:

```bash
RUN=$(cat WUWA_CURRENT_RUN)
cat "$RUN/condition.json"
cat "$RUN/native-test-scalars.json"  # NeuralUplift false; NREnableUpscaling false/0
```

At the desktop, use real keyboard/mouse input to complete normal launcher/login/
connect steps. Do not create click/key actions. Reach an actual stable world
scene and allow the publisher's login transition plus 15 s settle. Check the
latest status still says disabled before enabling NR.

Use same-directory rename for each operator action and wait for `actions.json`
to record it before sending another:

```bash
put_action() {
  local payload=$1 tmp="$RUN/.action.$$.tmp"
  printf '%s\n' "$payload" > "$tmp" && mv -f -- "$tmp" "$RUN/action.json"
}
put_action '{"action":"nr","enabled":true}'
```

A POST/2 execution pass requires a fresh `runtime-status.jsonl` record with:

- requested/effective order `post`, requested/effective passes `2`, state
  `active`, and `actual_nr_call_count:2`;
- two nonzero distinct layer handles, each created and evaluated;
- nonzero submit/completed samples with advancing completion frame IDs;
- no VRAM-guard, native error, Xid/device-removal, launcher-exit, or visual
  corruption/flicker observed while the user moves through the real scene.

POST supports the game's actual ordinary SR or RR; do not change RR merely to
make this case pass. Physical mode deliberately takes no screenshots, so record
operator observations separately and make no quality claim without a controlled
reference.

Stop through the control channel so cleanup/rollback is observed:

```bash
put_action '{"action":"stop"}'
# after the unit exits:
cat "$RUN/RESTORED.json"
```

Require `owned_restored:true`, `signed_unchanged:true`, `stop_requested:true`,
`physical_user_operated:true`, null `error`, and the original old-gate state.
The runner also asserts every restored file hash. Do not continue to PRE unless
POST/2 and restoration both pass.

### 2. Later cold case: PRE/1, only after explicit actual SR setup

Start a new cold run (a different pass count may be selected later, but PRE/1 is
the conservative first PRE case):

```bash
tools/run_native_wuwa.sh --physical pre_sr 1 300
UNIT=$(cat WUWA_CURRENT_UNIT)
# wait for the new pointer, then:
RUN=$(cat WUWA_CURRENT_RUN)
```

With NR still OFF, use only the real game menu to select ordinary DLSS Super
Resolution and disable/select away from Ray Reconstruction. The runner does not
make this setting change. Visually confirm the menu and wait until the newest
runtime status itself reports `reconstruction:"sr"`, requested/effective order
`pre_sr`, and requested passes `1`. If it says `rr`, do **not** confirm or enable;
stop the run.

Immediately after observing a fresh SR status:

```bash
put_action() {
  local payload=$1 tmp="$RUN/.action.$$.tmp"
  printf '%s\n' "$payload" > "$tmp" && mv -f -- "$tmp" "$RUN/action.json"
}
put_action '{"action":"confirm_actual_sr_no_rr","confirmed":true}'
# Wait for actions.json to record operator assertion + fresh runtime SR proof.
put_action '{"action":"nr","enabled":true}'
```

The runner rejects PRE enable before that exact assertion/fresh SR proof. A PRE
pass then requires `active`, `reconstruction:"sr"`, effective `pre_sr`, exact
requested pass count and actual call count, independent handle/counters,
completion samples, stable user-observed scene, and no errors. Stop and verify
`RESTORED.json` exactly as for POST; additionally require
`pre_sr_menu_confirmation_recorded:true`.

### Failure/rollback rule

The inner timer, fail-closed VRAM guard, and outer cgroup bound are independent.
On interruption/error the runner terminates the publisher and owned game PIDs,
waits until no WuWa PID remains, atomically restores the snapshot, restores the
old gate state, and writes `RESTORED.json`. If a game PID will not stop, it
intentionally refuses hot rollback. In that case do not copy DLL/settings/control
files over a live process and do not start another run; retain `RUN/before/` and
`before-manifest.json` for Main-directed cold recovery.

Nothing in this plan is GPU acceptance until the user-operated runs and their
restoration/evidence checks actually complete.
