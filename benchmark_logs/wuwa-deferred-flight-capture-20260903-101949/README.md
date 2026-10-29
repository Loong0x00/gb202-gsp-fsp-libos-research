# Deferred Flight capture audit, 2026-09-03 10:19:49 CST

## Landing/integrity result

The capture did land successfully.

- Session: `20260903-101949-421-p320`
- requested/recorded/completed: `32/32/32`
- abandoned/write-failed: `0/0`
- 160 raw files (five resources × 32 frames)
- raw payload: `9,097,214,976` bytes (about 8.47 GiB)
- every file exists and exactly matches its manifest byte count
- `SHA256SUMS.capture` contains 161 hashes: 160 raw files plus manifest
- deferred preallocation: 9,120,514,048 charged bytes
- no capture/stop/ready marker remained after completion
- no UE4 crash, Xid, OOM or process kill

## Why no completion banner appeared

GNOME setting `org.gnome.desktop.notifications show-banners` is `false`.
Both helper invocations were nevertheless recorded in the user journal:

- 10:19:36: preparation requested
- 10:19:38: preparation ready
- 10:19:49: 32-frame recording started

The helper has now been changed to play audible cues for ready/start/complete;
the global notification preference was not modified.

## OBS versus raw timing

OBS recording start: 10:19:47.002 CST.

- raw frame 0: 10:19:49.421, equivalent OBS PTS about 2.419 s
- raw frame 31: 10:19:50.753, equivalent OBS PTS about 3.751 s
- R cinematic begins around OBS frame 239 / PTS 3.983 s
- first clearly corrupted pair: OBS 268–269 / PTS 4.467–4.483 s
- second clearly corrupted pair: OBS 272–273 / PTS 4.533–4.550 s

Thus the raw window ended approximately 0.232 s before the R cinematic began
and 0.716 s before the first corrupted image. It captured the preceding enemy
attack, not the target bad frames. The user followed the stated order; the
order was wrong for this queued combat situation because `C then R` spent the
short window while R waited behind the existing attack.

The next attempt should retain the same preparation phase, but after READY use
`R first, then immediately Super+Alt+C`. No game restart is required.
