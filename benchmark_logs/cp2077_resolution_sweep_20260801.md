# Cyberpunk 2077 native-resolution sweep — 2026-08-01

## Controlled settings

- Game: Cyberpunk 2077 2.31 built-in benchmark
- GPU/CPU: NVIDIA GeForce RTX 5090 / AMD Ryzen 9 9950X3D
- Upscaling: DLAA (native rendering), no frame generation, no DRS
- Ray tracing: path tracing enabled
- Same game settings and LACT state for all accepted runs
- A nested gamescope display exposed each target mode; the benchmark summary was used to verify the actual render size

## Accepted results

| Label | Verified render size | Pixels | Average FPS | Minimum FPS | Maximum FPS | Average frame time | Average GPU utilization | Average board power | Average GPU clock |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 480p | 854x480 | 409,920 | 97.133 | 38.073 | 209.459 | 10.295 ms | 54.6% | 207.3 W | 3074.6 MHz |
| 720p | 1280x720 | 921,600 | 87.993 | 35.558 | 160.267 | 11.365 ms | 64.1% | 282.4 W | 3052.6 MHz |
| 1080p | 1920x1080 | 2,073,600 | 64.269 | 41.260 | 98.493 | 15.560 ms | 72.1% | 376.0 W | 3037.4 MHz |
| 1440p | 2560x1440 | 3,686,400 | 47.665 | 36.627 | 67.151 | 20.980 ms | 80.3% | 444.0 W | 3005.8 MHz |

Linear least-squares fit over these four points:

```text
frame_time_ms = 8.639 + 3.334 * megapixels
R^2 = 0.9971
```

This fit is descriptive, not a proof that all of the 8.639 ms intercept is CPU work. It includes any work that is approximately resolution-independent over this range: game/CPU work, command generation and submission, BVH/update work, synchronization, and fixed GPU passes.

## Discarded validation runs

- Requested 854x480 without a virtual display; the game clamped to 1024x768. Discarded.
- First nested 720p attempt inherited an empty dynamic resolution value and rendered at 1152x720. Discarded and rerun after explicitly setting 1280x720.

## Raw result directories

- `cp2077_480p_20260801_183558`
- `cp2077_720p-valid_20260801_184018`
- `cp2077_1080p_20260801_184221`
- `cp2077_1440p_20260801_184413`

The original `UserSettings.json` was restored byte-for-byte after the sweep; both source backup and restored file had SHA-256 `0049e36cb1e76fc5c3bc6ec19582ab4fdd387cd77c477d48cd7fda2196cb34eb`.
