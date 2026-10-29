# Black Myth: Wukong Benchmark resolution sweep — 2026-08-01

## Controlled settings

- GPU: NVIDIA GeForce RTX 5090
- CPU: AMD Ryzen 9 9950X3D
- Benchmark version: 1.0.3.14649
- Full ray tracing: level 3
- Super-resolution sampling: 100% (native)
- Frame generation: off
- Quality preset and all reported sub-settings: 5 (cinematic)
- Motion blur: off
- Virtual display resolutions: 854x480, 1280x720, 1920x1080, 2560x1440
- The gamescope presentation window was fixed at 1280x720. Each result was accepted only after the benchmark's own JSON reported the intended internal `ScreenResolution`.

## Results

| Internal resolution | Mean FPS from records | Reported average FPS | 95% FPS | Minimum FPS | Maximum FPS | Mean CPU frame time | Mean GPU frame time | Driver power P10 / P50 / P90 | Clock P10 / P50 / P90 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 854x480 | 109.672 | 109 | 94 | 35 | 150 | 4.344 ms | 8.331 ms | 188.8 / 278.6 / 293.0 W | 3052 / 3052 / 3060 MHz |
| 1280x720 | 82.846 | 82 | 70 | 38 | 110 | 4.583 ms | 11.355 ms | 234.5 / 344.5 / 356.8 W | 3045 / 3052 / 3052 MHz |
| 1920x1080 | 53.899 | 53 | 46 | 32 | 72 | 4.824 ms | 17.899 ms | 306.9 / 418.9 / 436.8 W | 3030 / 3037 / 3052 MHz |
| 2560x1440 | 36.721 | 36 | 31 | 25 | 49 | 5.005 ms | 26.680 ms | 369.4 / 459.3 / 474.7 W | 3000 / 3022 / 3037 MHz |

The 720p telemetry sampler lost a middle segment when its first short-lived shell exited. The benchmark JSON is complete; the utilization and power row uses the longer detached second segment and should be treated as representative rather than full-run telemetry.

## Resolution-scaling fit

Using the benchmark's per-record mean GPU frame time and physical megapixels:

`GPU frame time (ms) = 6.1543 + 5.5908 * megapixels`

- R-squared: 0.999770
- Residuals: -0.115, +0.048, +0.151, -0.084 ms
- The fitted resolution-independent component is about 74% of total GPU time at 480p, 54% at 720p, 34% at 1080p, and 23% at 1440p.
- Extrapolating the fit to zero pixels gives a ceiling near 162.5 FPS before pixel-dependent work is added. This is a model of these four runs, not a literal no-render benchmark.

## Interpretation

The low-resolution ceiling is not explained by a conventional CPU bottleneck: mean CPU frame time stays near 4.3-5.0 ms. NVIDIA's busy-time utilization counter remains high, but it must not be interpreted as full-chip occupancy. At 720p the captured power drops as low as about 200 W and its P10 is 234.5 W despite a steady clock near 3.05 GHz. The GPU is therefore neither board-power-limited nor clock-throttled; a continuously busy but narrow, latency-bound, dependency-bound, or poorly parallelized path can report high utilization while leaving much of GB202 electrically idle.

The data show a large resolution-independent GPU latency/work component plus a nearly linear pixel-dependent cost. They do not by themselves distinguish unavoidable algorithmic work from avoidable engine inefficiency, but the low-resolution power behavior is evidence against saying that the whole GPU is being filled.

Compared with the prior Cyberpunk 2077 native-PT sweep (`8.639 + 3.334 * megapixels` ms), this benchmark has a smaller fitted fixed term but a much steeper pixel-dependent term. The workloads and engines differ, so that comparison identifies behavior rather than proving which title is intrinsically better optimized.

## Raw artifacts

- `wukong_resolution_sweep_20260801/480p.json`
- `wukong_resolution_sweep_20260801/720p.json`
- `wukong_resolution_sweep_20260801/1080p.json`
- `wukong_resolution_sweep_20260801/1440p.json`
- `wukong_480p_telemetry_20260801.csv`
- `wukong_720p_telemetry_20260801.csv`
- `wukong_720p_telemetry_20260801_part2.csv`
- `wukong_1080p_telemetry_20260801.csv`
- `wukong_1440p_telemetry_20260801.csv`
