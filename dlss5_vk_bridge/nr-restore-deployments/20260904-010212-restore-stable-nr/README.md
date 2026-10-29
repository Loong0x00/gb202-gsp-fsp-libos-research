# Restore stable WuWa NR after native replay

- Restored Router: 65be255fc529f18c7751666360f4748a743198f21fa7d17f3a757a295ec043ad
- Restored stable Feature18 post service: 6e1621581aa2a1a81b422a5870c07ed326a32299d4c1b2a098a1c8af42d29210
- Restored normal 6K launcher: a2c667e809f9e1fc5a842ccefc96fd30d43fbb722dfbc94f92a9d0ab907f28da
- Removed native replay/native RR-only and all capture markers.
- Preserved D5LC live-control.bin with NeuralUplift=1; removed stale live-status receipt.
- Disabled the raw-capture hotkey because the stable service is not a capture build.
- Rollback to the pre-cleanup capture components: /home/user/rt_5090_project/dlss5_vk_bridge/nr-restore-deployments/20260904-010212-restore-stable-nr/restore-native-replay.sh

## Capture cleanup

- Active game raw-capture root is empty.
- The decisive complete 150-frame source was moved intact to:
  `/home/user/rt_5090_project/capture_archives/wuwa-native-replay-final-20260904-0104/`
- The superseded 75-frame raw payload (10,657,591,200 bytes) was deleted only after its manifest, historical hash list, OBS, logs and contacts had been preserved in:
  `/home/user/rt_5090_project/benchmark_logs/wuwa-native-replay-75-pre-event-20260903-121233/`
- The three redundant OBS originals in `/home/user` were removed after byte comparison with their retained report copies.
- Capture-era active Router/ReShade/raw logs were moved into the final archive; the game directory now starts with fresh logs on next launch.

## GNOME/UI cleanup correction

The first cleanup pass intentionally retained the production controller but accidentally left the redundant experimental `鸣潮 6K DLSS5` application entry and dormant capture-hotkey object visible. They are now removed. The obsolete 2K launcher/icon were also retired. The normal `Wuthering Waves` entry still invokes the protected 6K launcher, and `DLSS5 通用控制器` remains because it is the production NR control surface rather than capture-test residue.
