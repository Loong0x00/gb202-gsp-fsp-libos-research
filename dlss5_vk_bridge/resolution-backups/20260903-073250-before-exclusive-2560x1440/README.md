# Force actual 2560x1440 instead of 6K borderless

The 2026-09-03 07:28 run proved through 2,956 Router frame records that the
runtime output remained 6144x3456. `FullscreenMode=1` selected desktop-sized
borderless output, so pixel dimensions in the INI alone were not sufficient.

Applied while the game was stopped:

- Resolution/current/confirmed/desired: 2560x1440
- `bUseDesktopResolutionForFullscreen=False`
- `FullscreenMode=0`
- `LastConfirmedFullscreenMode=0`
- `PreferredFullscreenMode=0`
- Launcher now also passes `-ResX=2560 -ResY=1440 -Fullscreen` via Steam

Rollback restores only the pre-change GameUserSettings.ini and refuses while
the game is running.
