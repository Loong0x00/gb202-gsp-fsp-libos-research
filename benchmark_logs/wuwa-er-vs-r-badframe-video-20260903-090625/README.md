# Wuthering Waves ER-versus-R bad-frame video audit

Source: `/home/user/2026-09-03 09-06-25.mp4`

SHA-256: `98da4248451648837f408bb271d3977299def087fad33305d888e26de50aaac0`

## Recording integrity

- OBS start: 2026-09-03 09:06:25.753 CST.
- OBS stop: 2026-09-03 09:06:45.651 CST.
- AV1, 6144×3456, 60 fps, 1175 decodable video frames, 19.584 s.
- The complete file passes ffmpeg decode.
- OBS reported one skipped/lagged frame out of about 1192 (0.1%); the bad
  samples below are repeated source images, not isolated undecodable packets.
- User states the first/second tests cover ER pressed together and R alone, and
  that both showed the same issue. The audit does not infer which ordering was
  used beyond that statement.

## Visible events

Event A has two distinct corrupted game images, each sampled twice by OBS:

- OBS 184–185, PTS 3.0667–3.0833 s: structured bright red/teal block frame.
- OBS 188–189, PTS 3.1333–3.1500 s: a second, darker structured block frame.
- The within-pair downscaled RGB differences are only 0.265 and 0.285 levels,
  while entry into each pair changes by about 28.8 and 30.3 levels. Thus these
  are two actual game images, not four independent encoder errors.

Event B has one corrupted game image sampled twice:

- OBS 813–814, PTS 13.5500–13.5667 s.
- Within-pair downscaled RGB difference: 0.239 levels.

See `event-a-frames-180-191.jpg` and `event-b-frames-808-819.jpg`.

## Router/GPU correlation

The OBS Recording Start line is used as the wall-clock anchor. Since Present
was not instrumented, the nearest preceding Evaluate is a candidate with an
unknown small presentation offset, not an exact Present-to-Evaluate identity.

- A1 candidate: global 44686 / bridge 43027, 14.31 ms before the first OBS
  sample; Reset=0, Feature18 post success, Feature18 GPU 19.131392 ms.
- A2 candidate: global 44688 / bridge 43029, 12.83 ms before the first OBS
  sample; Reset=0, Feature18 post success, Feature18 GPU 19.010432 ms.
- B1 candidate: global 44976 / bridge 43309, 10.96 ms before the first OBS
  sample; Reset=0, Feature18 post success, Feature18 GPU 19.299232 ms.

Every Router frame in the ±2 windows around these candidates has Reset=0,
post-called=1, post success, no reset bypass, no settle bypass and no deferred
forced Reset. This new recording therefore excludes the old Reset-window
hypothesis for these occurrences.

## Relation to raw capture

The game was not restarted between the successful 24-frame raw capture and
this recording. Router IDs continue in the same process from the capture's
118xx range to this video's 446xx/449xx range. Raw capture was inactive during
this recording, and no third capture session was created.

The artifact returning after readback stopped proves that capture did not
permanently repair or warm-reset the model. It narrows the suppression to a
per-frame effect of active capture: the D3D12 output state transitions/copy
barriers, copy workload, or CPU command-recording disturbance. A barrier-only
build is the next controlled split.
