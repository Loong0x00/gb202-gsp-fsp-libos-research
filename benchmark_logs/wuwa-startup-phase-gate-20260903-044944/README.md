# DLSS5 startup red-texture phase-gate fix — 2026-09-03

## Symptom and cause

Wuthering Waves and HSR can submit successful native DLSS calls while their
visible presentation is in a black/white startup or loading transition. Those
frames do not provide a valid temporal NR contract: exposure changes abruptly
and motion/depth can describe a loading UI, an unfinished scene, or stale
content. Passing them through Feature 18 can turn a normal black/white flash
into a structured red frame. A successful NGX return does not make those guides
semantically valid.

The fix is fail-closed phase gating, not a red-channel clamp:

- preserve the untouched native DLSS output during startup/loading;
- enable Feature 18 only after a reliable gameplay transition plus a settle
  interval;
- make the first enabled Feature 18 frame reset temporal history;
- close the gate again on exit/loading/relogin.

No NVIDIA-signed DLL or anti-cheat component is changed.

## Wuthering Waves fix

Installed user service:

`~/.config/systemd/user/wuwa-dlss5-phase-gate.service`

It only reads `/proc` and the game's SQLite `LocalStorage.db`. At process start
it removes `.dlss-ngx-router/enable-dlss5`. It waits for this launch's
`LoginTime_<UID>` to increase, waits another 15 seconds for the final fade and
scene settle, then atomically creates the router marker. Process exit removes
the marker. A same-process relog closes the gate and starts a new settle. A
watcher restart mid-game stays closed until a new login transition.

The SQLite connection is `mode=ro` plus `PRAGMA query_only`; poll interval is
0.5 seconds. Missing/locked/unreadable state before login cannot open the gate.
The service is enabled for the user session and currently active. While the
game is not running the marker is deliberately absent.

### Live validation

Actual online launch, existing 6144×3456 RR configuration:

- game process detected at epoch `1788382189.580866055`;
- prior login timestamp: `1788380332.8237264`;
- new login timestamp: `1788382264.6421788`;
- process-start to login event: 75.172 seconds;
- login event to gate enable: 15.004 seconds;
- first 5 seconds: marker absent and service log remained 0 bytes;
- before gate: 1914 successful native RR evaluations with `dlss5_mode=0`;
- after gate: 985 successful owned calls with `dlss5_mode=2` and no failure;
- Feature 18 created once successfully;
- first Feature 18 frame had `reset=1`;
- game exit removed the marker;
- no Xid, NVRM assertion, `gpu_vaspace` or `intermap` event.

This proves the red-prone startup sequence was no longer submitted to Feature
18. Visual confirmation remains observational; this run did not create an
independent high-frame-rate capture.

## HSR fix

`/home/user/rt_5090_project/astral_pin_monitor/astral_hsr_guard.py` now defaults
to a 3-second settle after
`RPG.Client.AdventurePhase:_OnLoadingFinish()` instead of opening the marker
immediately. Any `LoadingTips:Show`, `_EnterStep2`, EnterGame, ServerSelect,
RestartApp, log replacement/truncation, or parser error cancels a pending enable
and removes the marker. The existing HSR-specific service forces temporal reset
when the delayed marker appears.

A read-only Guardian simulation validated:

1. `_OnLoadingFinish` schedules the gate;
2. marker remains absent for the settle interval;
3. marker appears after the interval;
4. `LoadingTips:Show` removes it immediately;
5. Guardian exit leaves it absent.

The HSR hardware thresholds are unchanged: any pin >9.3 A, max/min >1.25 at
sum >=25 A, or I2C failure still kills the game. A full live HSR login was not
needed for this source-only timing change and was not run in this test.

## Tests

- Wuthering state machine: 5 tests passed.
- Wuthering live route: 1914 native-only startup calls, then 985/985 owned
  successes.
- HSR synthetic phase sequence: scheduled -> enabled -> loading-disabled.
- Python compilation succeeded for both guards.

## Rollback

Complete pre-fix rollback:

`/home/user/rt_5090_project/dlss5_vk_bridge/phase-gate-backups/20260903-044904-before-startup-red-flash-fix/restore.sh`

The rollback refuses to run while either target game is active. It disables the
Wuthering user service, restores the previous always-present marker behavior,
and restores the pre-settle HSR Guardian.

## Remaining boundary

The Wuthering signal covers initial startup and same-process relog. Its encrypted
Client log did not expose a reproducible public event for every later teleport
or map load, so those transitions are not yet automatically gated. If a red
texture is observed during an in-game teleport rather than startup/login, a
second engine-side phase signal or a GPU content/guide validity guard is still
required.
