# WuWa 6K-only dynamic capture deployment

The user confirmed the fixed-location bad frame is absent in a clean 2K run.
Router evidence for that process: 7,748/7,748 outputs at 2560×1440, 5,940
successful Feature18 post calls, zero post failures. Investigation therefore
proceeds as 6K-only.

Applied while the game was fully exited:

- Game launch profile restored to 6144×3456 borderless.
- `Super+Alt+W`: launch 6K profile.
- `Super+Alt+C`: dynamically start/stop raw capture.
- Raw capture never starts with the game; stale markers are removed at process
  registration, exit and launcher startup.
- Helper requires live game PID, open gameplay phase gate, latest telemetry at
  exactly 6144×3456, and at least 15 GiB free.
- Default 24 frames, native hard maximum 32 frames.
- Expected five-surface payload: about 7 GiB default, 10 GiB maximum.
- Readback allocation cap: 12 GiB; 32 non-dropped slots.

Installed capture+GPU-timing service SHA-256:

`d8e5b4ca33ecd46bf9577357936078eb7c2a17eddfe892cfb1fdc14529204c46`

Service rollback:

`/home/user/rt_5090_project/dlss5_vk_bridge/raw-capture-deployments/20260903-081251-timing/restore.sh`

Launch/config rollback:

`/home/user/rt_5090_project/dlss5_vk_bridge/6k-capture-deployments/20260903-081243-before-6k-dynamic/restore-launch-config.sh`

Current state after deployment: game stopped, phase service active, capture
trigger/stop/active markers absent. No runtime raw capture has yet been run with
this 6K build.
