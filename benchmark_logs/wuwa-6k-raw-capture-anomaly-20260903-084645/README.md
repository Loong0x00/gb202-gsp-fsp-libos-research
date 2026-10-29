# Wuthering Waves 6K 24-frame raw capture, 2026-09-03 08:46:45 CST

## Capture integrity

PASS.

- Capture session: `20260903-084645-877-p320`, session 2.
- Requested/recorded/completed: `24/24/24`.
- Abandoned/write-failed: `0/0`.
- 120 raw files (five resources × 24 frames).
- All file lengths match the manifest.
- Raw payload: `6,822,911,232` bytes (about 6.35 GiB).
- `SHA256SUMS.capture` contains hashes for all 120 raw files plus the manifest.
- No new UE4 crash, kernel Xid/NVRM fault, OOM, or process kill. The game
  continued running after the capture.

## Visual/decoded result

The window covers the transition from the arena into the fixed character
cinematic and includes the pose associated with the old OBS bad sample.
Capture frame 20 / bridge frame 10184 is the closest pose match.

All 24 signed-RR pre-NR and post-NR images decode cleanly. No structured red or
block-corruption frame exists in either sequence. Color and motion resources
also contain no NaN or infinity. Depth has positive infinity only after the
cut, corresponding to sky/no-geometry pixels; it has no NaN or negative
infinity.

At capture frame 20:

- pre-NR non-finite components: 0
- post-NR non-finite components: 0
- post red-dominant pixel fraction: 0.00025968
- Router global frame: 11835
- signed RR result: success
- Feature18 post result: success
- Reset: false
- Feature18 GPU time: 18.109344 ms

`old-bad-vs-new-post-frame20.jpg` compares the old corrupted OBS sample with
this clean post-NR frame at the matching pose.

## Viewable videos

- `pre-nr-6k-24fps.mp4`: signed-RR pre-NR, native 6144×3456, 24 frames.
- `post-nr-6k-24fps.mp4`: Feature18+codec post-NR, native 6144×3456,
  24 frames.
- `pre-vs-post-4k-slow-6fps.mp4`: left/right 3840×1080 comparison at 6 fps,
  with capture and bridge frame labels.

All are HEVC Main10 and passed full ffmpeg decode validation. The packed raw
files remain the bit-exact source. Since R11G11B10 data is scene-linear and
cannot be shown directly as a normal desktop video, these previews use one
fixed Reinhard transform (`x/(1+x)`) plus gamma 2.2 and then lossy video
encoding; they do not reproduce the game's later HDR/tone-mapping stage.

## Reset discontinuity

Raw capture frames 0–7 map to Router globals 11813–11820. The existing Router
then bypassed Feature18 for:

- global 11821: game Reset frame (`dlss5_reset_bypass=1`)
- global 11822: one settle frame (`dlss5_settle_bypass=1`)

Because the raw hook is inside the Feature18 service, those two bypassed native
RR frames have no raw record. Capture resumes at raw frame 8 / Router global
11823 with the deferred forced Reset. The later matching bad-frame pose is
inside the captured region, so this early two-frame gap does not remove frame
20 from the evidence.

All 24 captured Feature18 invocations succeeded. Their measured Feature18 GPU
time ranges from 17.735552 to 19.577760 ms.

## Interpretation boundary

There was no OBS recording created for this run. Whether a red frame was seen
live determines the next conclusion:

- If it was seen live during this capture, the same-pose pre-NR and post-NR
  textures are clean, moving the fault downstream of the captured Feature18 +
  codec output (UE post/HDR/presentation or a synchronization/resource-state
  interaction).
- If it was not seen live, raw capture itself may have masked the issue. Its
  output transition to `COPY_SOURCE` and back introduces synchronization/cache
  barriers. The next controlled A/B should therefore be barrier-only without
  readback, rather than treating this run as proof the defect disappeared.
