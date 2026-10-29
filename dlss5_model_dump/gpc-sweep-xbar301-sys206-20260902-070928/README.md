# DLSSNR 6K CUDA Green Context sweep — XBAR +301 / SYS +206

## Contract

- Runtime: signed `nvngx_dlssnr.dll` 310.8, SHA-256 `e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e`.
- Frame: 6144×3456 RGBA32F; identical input and parameters to the previous 2026-08-30 sweep.
- CUDA Green Context partitions: 16, 32, …, 160, 170 SM.
- Five Evaluate calls per feature instance; iteration 0 discarded; median of iterations 1–4.
- Every Evaluate, stream sync and context sync succeeded.
- All eleven final outputs were byte-identical: `028e7fa578b62928031494f1a0c399ef12d5a8a26c7e013a858eac5963116a24`.
- No new Xid, `nvAssert`, GPU-lost or reset-required event occurred.

## Active controls

- XBAR frequency offset: `+301449 kHz`.
- SYS frequency offset: `+205797 kHz`.
- GPC→XBAR relation: `62259 / 65536 = 0.9499969482`.
- Memory clock: 15001 MHz.
- Power limit: 600 W.
- Peak sampled GPC clock during this sweep: 2992 MHz; previous sweep: 3097 MHz.
- Peak temperature/power: 41 °C / 155.71 W.

## Results

| Eq. | SM | Current ms | Previous ms | Delta | Peak GPC |
|---:|---:|---:|---:|---:|---:|
| 1 | 16 | 164.735 | 155.170 | +6.16% | 2970 MHz |
| 2 | 32 | 84.588 | 78.382 | +7.92% | 2992 MHz |
| 3 | 48 | 57.496 | 53.575 | +7.32% | 2992 MHz |
| 4 | 64 | 44.074 | 41.551 | +6.07% | 2992 MHz |
| 5 | 80 | 36.172 | 33.794 | +7.04% | 2992 MHz |
| 6 | 96 | 30.842 | 28.856 | +6.88% | 2992 MHz |
| 7 | 112 | 27.348 | 25.576 | +6.93% | 2992 MHz |
| 8 | 128 | 25.101 | 23.639 | +6.18% | 2992 MHz |
| 9 | 144 | 22.568 | 22.069 | +2.26% | 2992 MHz |
| 10 | 160 | 22.097 | 20.686 | +6.82% | 2992 MHz |
| 11 | 170 | 21.220 | 20.129 | +5.42% | 2992 MHz |

## Fits

- Current: `time_ms = 2549.57 / SM + 4.956`, R²=0.999720.
- Previous: `time_ms = 2392.83 / SM + 4.67`, R²=0.99949.
- 16→170 SM speedup: current 7.763×; previous 7.709×; ideal 10.625×.
- Fitted weak/fixed fraction at 170 SM: current 24.84%; previous 24.91%.

## Interpretation

- The XBAR/SYS offsets did **not** improve absolute throughput. The 170-SM median changed from 20.129 ms to 21.220 ms (+5.42%).
- The whole curve moved almost uniformly and the fitted weak/fixed fraction stayed about 24.9%. There is no evidence that the extra XBAR/SYS frequency removed the high-SM scaling wall.
- Current GPC clock was lower. A simple frequency normalization (`current × 2992/3097`) estimates 20.501 ms at the old-clock basis, still about +1.85% slower; this is only a heuristic, not an isolated clock-domain A/B.
- The exact old Green probe binary (recorded hash `88e516…`) is no longer present; the current probe hash is `4de4b8…`. The native DLL, input, outputs and synchronization contract are verified identical, but harness identity is a remaining confound.
- Therefore the defensible conclusion is: under the current complete clock tuple, XBAR +301/SYS +206 does not help this single-model DLSSNR workload. It does not yet answer whether those domains help multiple independent models running concurrently.

## Files

- `results.csv`: parsed timings and old-point deltas.
- `summary.json`: fit and safety maxima.
- `gpc-*.log`: full native probe logs.
- `gpc-*-nvml.csv`: per-point telemetry.
- `lact-config.yaml`: exact active clock-control configuration.
- `SHA256SUMS`: artifact hashes.
