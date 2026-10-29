# WuWa 1440p telemetry/raw-capture preparation

Date: 2026-09-03 +08:00

## Active game state

- `GameUserSettings.ini` current, last-confirmed, desired, and
  last-confirmed-desired dimensions: `2560x1440`.
- `sg.ResolutionQuality=100` remains unchanged.
- `LocalStorage.db` was not modified.
- `dlss5-codec-only` is absent: normal Feature18 mode is restored.
- `dlss5-capture-raw` is absent: no raw capture is armed.
- `wuwa-dlss5-phase-gate.service` remains active and enabled.
- Game was not running during config or DLL replacement.

Resolution rollback (restores only the INI; intentionally does not roll back
later LoginTime/database state or diagnostic markers):

`/home/user/rt_5090_project/dlss5_vk_bridge/resolution-backups/20260903-060835-before-2560x1440/restore.sh`

## Deployed Router telemetry

Installed Router:

`/home/user/.local/share/Steam/steamapps/common/Wuthering Waves/Client/Binaries/Win64/00-dlss-ngx-router.addon64`

It emits `dlss-ngx-frames.jsonl`, one `dlss-ngx-frame/v1` record per SR/RR
Evaluate with UTC, QPC, global Evaluate ID, role sequence, Reset, jitter, MV
scale, exposure, flags, physical resource descriptions, signed result and
post-routing outcome.

Router rollback:

`/home/user/rt_5090_project/dlss_ngx_proxy/deployments/20260903-061951-wuwa-frame-telemetry/restore.sh`

OBS correlator:

`/home/user/rt_5090_project/dlss_ngx_proxy/tools/correlate_obs_dlss.py`

## Raw capture service (capture+timing installed, disarmed)

Two explicit non-default targets exist:

- raw only: `build/post-service-capture/01-dlss5-post-service.addon64`
- raw + existing GPU timing: `build/post-service-capture-timing/01-dlss5-post-service.addon64`

The active profile captures five surfaces only at exact 6144x3456: signed-RR
pre-NR, post-NR, original game Color, engine MV, and engine Depth. It uses D3D12
readback footprints, queue/fence completion, a worker thread, 32 slots, a 12
GiB allocation cap, tight rows, UTC/QPC metadata, finite frame count, and no
render-thread Map/wait.

Documentation:

`/home/user/rt_5090_project/dlss5_vk_bridge/RAW_CAPTURE_6K.md`

Safe deployment helper (game-exit check, hash, backup, atomic install, rollback):

`/home/user/rt_5090_project/dlss5_vk_bridge/tools/deploy_wuwa_raw_capture.sh`

Trigger/status helper:

`/home/user/rt_5090_project/dlss5_vk_bridge/tools/wuwa_raw_capture.sh`

The corrected 6K dynamic capture+timing service was backed up and atomically
installed while the game was exited. SHA-256:
`6e01cfef594cf877dede77ec49e3fbe49c66e9bf99691728ecf60645f303fc7d`.
It is idle and registration clears stale trigger/stop/active markers, so startup
cannot resume or begin raw capture. Deployment rollback:

`/home/user/rt_5090_project/dlss5_vk_bridge/raw-capture-deployments/20260903-083619-timing/restore.sh`

Dynamic control is temporarily bounded to 4 frames for callback/fence safety
validation (32 native hard maximum), and requires game process, open gameplay
phase gate, exact 6144x3456 telemetry and at least 15 GiB free.
Pressing the toggle again requests early stop and drains only submitted copies.
A short live validation of WuWa's same-thread submit→Present path and source
states is still required.

## Verification completed

- Telemetry Router and both raw-capture variants compile successfully.
- Raw-capture source has zero compiler warnings; bridge warnings are pre-existing
  Vulkan aggregate/function-cast warnings.
- OBS correlator passed Python compilation and synthetic frame/time/anchor tests.
- Capture arm/status/disarm helper passed and left no marker behind.
- Phase gate unit tests: 5/5 passed.
- Build/installed telemetry Router hashes match.
- Capture+timing service build/installed hashes match; raw marker is absent.
- Clean 2K run verified 7,748/7,748 outputs at 2560x1440, including 5,940
  successful Feature18 posts and zero post failures; user confirmed no bad frame.
- 6K launcher dry-run verifies config, Router/service hashes and active phase gate.

## GNOME launcher and hotkey

- App menu entry: `鸣潮 6K DLSS5`
- Game launch hotkey: `Super+Alt+W`
- Dynamic raw capture start/stop hotkey: `Super+Alt+C`
- Launcher: `/home/user/.local/bin/wuwa-dlss5-6k-launch`
- Capture toggle: `/home/user/rt_5090_project/dlss5_vk_bridge/tools/wuwa_raw_capture.sh toggle 4`
- The launcher atomically enforces 6144x3456, clears stale diagnostic markers,
  starts the phase gate and launches Steam app 3513350.
- GNOME/launcher rollback:
  `/home/user/.local/share/wuwa-dlss5/backups/20260903-072650-launcher-hotkey/restore.sh`
- Dynamic capture hotkey rollback:
  `/home/user/.local/share/wuwa-dlss5/backups/20260903-073954-dynamic-capture-hotkey/restore.sh`
- Current 6K launch/config rollback:
  `/home/user/rt_5090_project/dlss5_vk_bridge/6k-capture-deployments/20260903-081243-before-6k-dynamic/restore-launch-config.sh`

## 07:28 live launch audit

The shortcut was invoked at 07:30:46 and 07:30:52, but the game had already
been running since 07:28, so the launcher correctly refused to modify a live
process. Telemetry is valid and contains 2,956/2,956 successful signed RR
Evaluate records. All 2,956 outputs were still 6144x3456; 845 Feature18 post
calls also succeeded. No raw files exist because capture was not armed, and no
matching kernel Xid/NVRM event was found.

The cause was `FullscreenMode=1` desktop-sized borderless output: setting only
ResolutionSize did not determine the swapchain. After exit, configuration was
updated to actual-resolution mode with `FullscreenMode=0`, all confirmed and
preferred modes set to 0, and `bUseDesktopResolutionForFullscreen=False`.
The launcher now additionally passes `-ResX=2560 -ResY=1440 -Fullscreen`, and
the original generic `Wuthering Waves.desktop` entry now routes through this
launcher too.

Display-mode rollback:

`/home/user/rt_5090_project/dlss5_vk_bridge/resolution-backups/20260903-073250-before-exclusive-2560x1440/restore.sh`

A later clean-process run resolved that caveat: 7,748/7,748 frames were
2560x1440, 5,940 Feature18 posts succeeded, and the user confirmed the bad frame
was absent at the same location. Investigation now accepts the issue as 6K-only.
The active launch profile and bounded raw capture were therefore returned to
6144x3456. A short 6K raw fence/copy validation is still required.

## 08:19 startup resolution regression

Logs show the game initially created 6144x3456 at 08:19:43, then resized to
2560x1440 at 08:20:17 and 634x448 at 08:20:18. This preceded the phase gate at
08:20:44, excluding Feature18/capture as the resize source. The game had retained
`PcResolutionIndex=8` and `PcWindowMode=1` from the prior 2K/window-mode test and
reapplied them after initial swapchain creation; it then persisted 634x448 and
FullscreenMode=2 to the INI.

Both LocalStorage values are restored to the known 6K pair `0/0`. The 6K
launcher now verifies the DB transactionally, and Steam's existing launch
wrapper invokes that check before `%command%`, so launching directly from the
Steam library is covered too. Detailed evidence and rollback:

`/home/user/rt_5090_project/dlss5_vk_bridge/6k-capture-deployments/20260903-082145-before-db-display-fix/ROOT_CAUSE.md`

## 08:29 first raw-trigger UE4 crash

The first 6K trigger crashed the render thread before any raw file completed.
Minidump exception RIP `0x6fffb4810000` and stack return
`01-dlss5-post-service+0x2fe35` map exactly to the cold path of
`on_command_list_reset_or_destroy`. MinGW had devirtualized the locally declared
pure-virtual `get_native()` into an invalid placeholder call. This was a capture
callback defect, not the original red frame, Feature18 inference, OOM, or GPU
Xid.

Containment was immediate: markers removed and stable service restored. The
callback now uses an opaque object plus explicit vtable slot-0 dispatch; fixed
assembly contains the expected `call *%rax`, persistent raw-capture logging was
added, and the fixed build is limited to four frames for the next validation.
Evidence:

`/home/user/rt_5090_project/benchmark_logs/wuwa-6k-raw-capture-crash-20260903-082929/README.md`
