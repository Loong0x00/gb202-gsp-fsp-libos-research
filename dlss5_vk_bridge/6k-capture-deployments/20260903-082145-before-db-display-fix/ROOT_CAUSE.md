# Startup 6K → smaller-window root cause

Observed process start: local 2026-09-03 08:19:31.

ReShade swapchain timeline:

- 08:19:43.341 — 6144×3456
- 08:20:17.754 — 2560×1440
- 08:20:18.362 — 634×448

This happened before the phase gate scheduled at 08:20:44, so Feature18, raw
capture and the phase service did not resize the game.

At process exit the game had persisted:

- `PcResolutionIndex=8`
- `PcWindowMode=1`
- `GameUserSettings.ini ResolutionSize=634×448`
- `FullscreenMode=2`

These LocalStorage values came from the prior 2K/window-mode test and were
reapplied after the initial 6K swapchain, overriding the INI-only launch setup.

Fix applied while the game was stopped:

- `PcResolutionIndex=0`
- `PcWindowMode=0`
- INI current/confirmed/desired restored to 6144×3456
- INI desktop-resolution mode and borderless mode restored
- 6K launcher now transactionally verifies both LocalStorage values without
  touching LoginTime or unrelated settings
- Steam's existing path-probe launch wrapper calls the 6K launcher in `--check`
  mode before `%command%`, so Steam-library launches receive the same fix

Rollback:

`/home/user/rt_5090_project/dlss5_vk_bridge/6k-capture-deployments/20260903-082145-before-db-display-fix/restore.sh`
