# Wuthering Waves single-frame reset-boundary audit — 2026-09-03

## Inputs

- User screenshot: `/home/user/截图/截图 2026-09-03 05-17-17.png`
  - SHA-256 `fe8c8511984a0e74f0c5f78e786f8750e6b287896169e8d4eeb97621f71541ed`
- Recording named in the screenshot: `/home/user/2026-09-03 05-15-53.mp4`
  - SHA-256 `d810ef7d66eb892362b934c6bf1086791c7426eefcbfadccc77489ce3743d438`
  - OBS Studio 32.2.2, `obs_nvenc_av1_tex`, 6144×3456, 60 FPS,
    389 frames, 6.483333 seconds.

FFmpeg decoded all 389 AV1 frames without a bitstream/decode error. Therefore
the observed image is not explained by a damaged MP4 frame.

## Frame localization

Ignoring the video player's chrome, the screenshot matches:

- video frame 156 at 2.600000 s: mean absolute RGB error 2.1168/255;
- video frame 157 at 2.616667 s: mean absolute RGB error 2.1741/255.

The next-best frame is more than 23/255 away. Frames 156 and 157 differ by only
0.282/255 at the 768×432 analysis scale. With the game overlay reporting about
26 FPS, OBS sampled one game-produced image twice at 60 Hz. It is therefore a
single rendered-game-frame event, represented by two recording samples.

The surrounding sequence also contains a shorter structured transition at
2.550 s, normal frames at 2.567–2.583 s, the reported structured frame at
2.600–2.617 s, then a hard radial transition from 2.633 s. This is a cut/reset
boundary, not a persistent texture corruption.

## Runtime correlation

This recording belongs to the Wuthering session detected at 05:09:34 local.
The startup phase gate opened at 05:12:37 after the successful-login event and
15-second settle. Recording began at 05:15:53, so this event occurred about
3 minutes 16 seconds after the startup gate opened. It is not a failure of the
startup gate.

The current session's NGX router records a game `Reset=1` RR Evaluate at QPC
25001.0488661 s, with stable Color, Output, Motion and Depth resource identities
and successful signed RR return. Correlating the gate's wall time and QPC mode
transition places that reset in the recording's 2.5–3.0 s interval (the router
poll contributes up to 0.5 s uncertainty), containing the 2.600 s frame.

Thus the machine evidence places a one-game-frame post-service artifact at a
game-declared temporal reset/hard cut. The user also observed this frame in the
live presentation and confirmed that the structured pixel-block image is not an
intentional native game transition. Classify it as a non-native bad frame
introduced somewhere in the owned Feature 18/codec post path, not as a phase
gate or recording artifact.

## Full-path isolation result

A subsequent replay ran the same transition with the router marker absent for
the entire session: 2742/2742 signed RR evaluations succeeded with
`dlss5_mode=0`, no owned post-service call occurred, and the user confirmed the
single structured frame was clean. This excludes the game-authored frame,
recording, startup gate, and signed RR output. The fault is introduced after RR
inside the combined owned Feature 18/codec path.

NR-off bypasses both the signed Feature 18 inference and the owned HDR codec, so
it does not by itself distinguish those two stages. A codec-only replay is the
next controlled discriminator: mode 1 executes capture/encode/decode without
Feature 18 inference.

## Targeted fix

The first Wuthering-specific router build preserved only the game-declared
`Reset=1` frame and forced Feature 18 reset on the immediately following frame.
A live retest produced 13/13 successful `reset_bypass -> forced_reset` pairs but
the visible bad image remained at the same apparent position. This proves the
bad output is associated with the first owned restart frame, not the bypassed
game Reset frame.

The active second build now implements:

1. original signed SR/RR Evaluate always runs first;
2. on game `Reset=1`, preserve the signed native output and defer Feature 18;
3. preserve the signed native output for the first following `Reset=0` frame as
   a one-game-frame settle interval;
4. on the second stable frame, temporarily force `Reset=1` into the owned post
   service;
5. restore the game's parameter value before returning;
6. clear deferred state only after a successful owned call.

The expected receipt sequence is:

`dlss5_reset_bypass=1 -> dlss5_settle_bypass=1 -> dlss5_forced_reset=1`

Multiple consecutive game Reset frames restart the settle countdown. At the
observed 26–30 FPS this adds roughly 33–38 ms of native RR around a hard cut and
does not affect steady gameplay.

Active router SHA-256:

`6c258f3c032e27252d2ff9ef5e0eeed0e48369c69589bbb51890e6728f35254c`

Rollback to the first reset-only build:

`/home/user/rt_5090_project/dlss5_vk_bridge/phase-gate-backups/20260903-054350-before-post-reset-settle/restore.sh`

The second build is compiled, statically validated, and atomically deployed
while the game is stopped. A replay of the transition is required to confirm
that the extra native settle frame removes the bad owned restart output.
