# RTX 50 standalone DLSSNR SM/L2 proxy matrix

Run: 2026-09-03 00:45:56–00:47:24 +08:00

Status: **33/33 process points and 3300/3300 Evaluate calls succeeded.**

This is a bare CUDA call into the signed DLSSNR 310.8 runtime at native 1:1 output resolution. It is not a game benchmark and not a complete emulation of another GPU.

## Fixed evidence

- Runtime: `nvngx_dlssnr.dll`
- Runtime SHA-256: `e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e`
- L2-aware probe SHA-256: `0926e70d77860b2d964cafb51a2de1965ad02d177a209d50a97e59bf8e0a556b`
- Embedded `sm_120` L2-prime CUBIN SHA-256: `5265bd33857dd38c6493bf472b91604a1408d2a245a28e40e85501cc1434de1d`
- GPU: RTX 5090/GB202, driver 610.57.04, CUDA 13.3, Wine 11.16
- Power cap: stock 600 W
- MCLK: stock 14001 MHz throughout; **memory bandwidth was not emulated**
- Feature parameters: intensity/tone/structure 1, skin -1, automatic mask off, depth 0.5, 1:1 scaling
- Each point: 100 Evaluate calls; iterations 0–9 discarded; median/mean/P90 use iterations 10–99
- Authoritative timing: wall time from immediately before `EvaluateFeature` through `cuCtxSynchronize`
- The caller-stream CUDA event measures submission-side work and is retained only as non-authoritative evidence.

The 1080p and 1440p RGBA32F inputs were generated from the exact 4K float input with OpenCV `INTER_AREA`; hashes and dimensions are in `METADATA.json` and the input directory's metadata.

## L2 method

Before every timed Evaluate, the same Green Context:

1. sets `CU_LIMIT_PERSISTING_L2_CACHE_SIZE`;
2. reads back the actual driver-selected value;
3. marks a dummy linear allocation with `CU_ACCESS_PROPERTY_PERSISTING`;
4. reads every byte with an embedded `sm_120` kernel;
5. synchronizes before starting the Evaluate timer.

The median prime cost was 0.018–0.074 ms and is excluded from the reported NR time. Every process cleared the access-policy window, freed the allocation, reset persisting status, restored the initial 18 MiB allowance, and emitted `L2_CLEANUP success=1`.

This creates **capacity pressure**, not physical L2-slice isolation. It retains the RTX 5090's cache ports, hash, associativity, 48 observed LTS rollups, and memory-controller topology.

Target handling:

- RTX 5070/5070 Ti: directly representable 48 MiB capacity-pressure point.
- RTX 5080: 64 MiB is not representable at the observed 6 MiB granularity; result is linearly interpolated one third of the way from the measured 66 MiB point toward the measured 60 MiB point.
- RTX 5060 Ti: target 32 MiB; maximum reserve leaves approximately 36 MiB, so the result remains a 36 MiB-capacity lower-pressure proxy.
- RTX 5060: target 24 MiB; likewise limited to the 36 MiB-capacity proxy.

## Primary result

Times are isolated NR Evaluate latency. `Eval/s` is `1000 / median_ms`; it is **not game FPS**.

| Proxy | SM | Target/represented L2 | Resolution | Median ms | P90 ms | Eval/s |
|---|---:|---:|---:|---:|---:|---:|
| RTX 5060 | 30 | 24 / 36 MiB | 1920×1080 | 12.5539 | 13.2107 | 79.66 |
| RTX 5060 | 30 | 24 / 36 MiB | 2560×1440 | 18.9230 | 19.5908 | 52.85 |
| RTX 5060 | 30 | 24 / 36 MiB | 3840×2160 | 39.2029 | 39.8295 | 25.51 |
| RTX 5060 Ti | 36 | 32 / 36 MiB | 1920×1080 | 10.7970 | 11.1675 | 92.62 |
| RTX 5060 Ti | 36 | 32 / 36 MiB | 2560×1440 | 16.0910 | 16.7129 | 62.15 |
| RTX 5060 Ti | 36 | 32 / 36 MiB | 3840×2160 | 32.3214 | 32.9711 | 30.94 |
| RTX 5070 | 48 | 48 / 48 MiB | 1920×1080 | 9.1331 | 9.4839 | 109.49 |
| RTX 5070 | 48 | 48 / 48 MiB | 2560×1440 | 13.0698 | 13.6979 | 76.51 |
| RTX 5070 | 48 | 48 / 48 MiB | 3840×2160 | 25.4718 | 26.1354 | 39.26 |
| RTX 5070 Ti | 70 | 48 / 48 MiB | 1920×1080 | 7.3699 | 7.3934 | 135.69 |
| RTX 5070 Ti | 70 | 48 / 48 MiB | 2560×1440 | 10.2615 | 10.3159 | 97.45 |
| RTX 5070 Ti | 70 | 48 / 48 MiB | 3840×2160 | 19.1060 | 19.7856 | 52.34 |
| RTX 5080 | 84 | 64 / interpolated 64 MiB | 1920×1080 | 6.1829 | 6.2552 | 161.74 |
| RTX 5080 | 84 | 64 / interpolated 64 MiB | 2560×1440 | 8.6753 | 8.7547 | 115.27 |
| RTX 5080 | 84 | 64 / interpolated 64 MiB | 3840×2160 | 16.1397 | 16.7068 | 61.96 |

The exact machine-readable values and interpolation labels are in `primary-results.csv` and `summary.json`.

## Clock tuple

GPC was locked near each card's official boost; the driver/hardware readback remained slightly below the request. Per-point GPC/XBAR/SYS/MCLK, GPU voltage, power, ratio, locked-state NVVDD/MSVDD targets, and probe hash are retained in `clock-tuples.csv`.

| Proxy | Lock request | Observed GPC range | Typical XBAR | Typical SYS | MCLK | GPC→XBAR ratio |
|---|---:|---:|---:|---:|---:|---:|
| RTX 5060 | 2497 MHz | 2490 MHz | 2235 MHz | 2227 MHz | 14001 MHz | 58976 |
| RTX 5060 Ti | 2572 MHz | 2565 MHz | 2302 MHz | 2295 MHz | 14001 MHz | 58976 |
| RTX 5070 | 2512 MHz | 2497–2505 MHz | 2250 MHz | 2242 MHz | 14001 MHz | 58976 |
| RTX 5070 Ti | 2452 MHz | 2430–2445 MHz | 2197 MHz | 2182–2190 MHz | 14001 MHz | 58976 |
| RTX 5080 | 2617 MHz | 2580–2610 MHz | 2340–2347 MHz | 2325–2332 MHz | 14001 MHz | 58976 |

All user GPC/XBAR/SYS/NVD and MSVDD offsets remained zero. The ratio is the restored board-default propagation value, not a target-card topology claim.

## Measured L2 sensitivity

Across the 15 matched comparisons, the smaller-capacity-pressure median changed by:

- range: **-1.156% to +0.522%**;
- median absolute change: **0.237%**;
- median signed change: **+0.186%**.

Most changes are smaller than run-to-run/timing-tail variation and some reverse sign. For this runtime, image set, and 1080p–4K range, reducing the available ordinary-capacity proxy from 96 MiB to 48 or 36 MiB did not produce a resolved slowdown. This does not prove that physical 24/32 MiB cards, with fewer slices and different memory systems, behave identically.

Raw A/B values are in `l2-effects.csv`.

## Why 480p/720p were not added

The three primary resolution points fit `time = slope × megapixels + intercept` with:

| Proxy | ms/MP | Intercept ms | R² |
|---|---:|---:|---:|
| RTX 5060 | 4.3097 | 3.3697 | 0.999534 |
| RTX 5060 Ti | 3.4738 | 3.4624 | 0.999798 |
| RTX 5070 | 2.6408 | 3.5199 | 0.999619 |
| RTX 5070 Ti | 1.8938 | 3.3736 | 0.999811 |
| RTX 5080 | 1.6044 | 2.8153 | 0.999917 |

All R² values exceed the predefined 0.995 extension gate, intercepts are positive, and none exceeds half of the corresponding 1080p time. Therefore 480p/720p would not resolve an ambiguity in the requested 1080p–4K range and were not run.

## NVIDIA 6× output cadence comparison

Where NVIDIA published NBA 2K27 full-stack `NR + SR + 6×MFG` FPS, `6000 / output_FPS` gives only a coarse real-endpoint cadence budget:

| Proxy | Resolution | Endpoint budget ms | Local NR proxy ms | NR share of budget |
|---|---:|---:|---:|---:|
| RTX 5060 | 1080p | 23.256 | 12.554 | 54.0% |
| RTX 5060 Ti | 1080p | 18.462 | 10.797 | 58.5% |
| RTX 5070 | 1080p | 15.544 | 9.133 | 58.8% |
| RTX 5070 Ti | 1080p | 11.321 | 7.370 | 65.1% |
| RTX 5080 | 1080p | 9.967 | 6.183 | 62.0% |
| RTX 5070 | 1440p | 22.901 | 13.070 | 57.1% |
| RTX 5070 Ti | 1440p | 16.997 | 10.261 | 60.4% |
| RTX 5080 | 1440p | 14.528 | 8.675 | 59.7% |
| RTX 5080 | 4K | 25.751 | 16.140 | 62.7% |

This does not isolate rendering, SR, MFG, latency, or official-runtime cost and must not be used to infer MFG-off FPS. The machine-readable table is `official-budget-comparison.csv`.

## Determinism and health

All resource variants at each resolution produced one common output hash:

- 1080p: `478dd82257b9aa86b44f9a582d3a021700f9cee8a60d5a6d4cf6c70f055aba9b`
- 1440p: `03bc680ccf97a8cde7f3130d7103e3b9453737ad3e85ae75f31ab861d30b96ef`
- 4K: `a655ec1ca03d296d04eb8830af9c4db49139040e0b2f1c81a53d7afe78482dab`

The 4K hash also matches the earlier independent C++ bare-runtime output. Generated per-point raw outputs were hashed and then removed; logs and hashes remain.

Post-run checks:

- core lock reset;
- MCLK 14001 MHz;
- 600 W current/default power cap;
- LACT GPU config still absent/default;
- GPU Recovery Action `None`;
- PCIe replays since reset `0`;
- `KERNEL_EVENTS.txt` empty: no new Xid, NVRM assertion, VA-space, or intermap event.

## Interpretation boundary

These numbers are **RTX 5090 compute/L2-capacity-pressure proxies**. The largest unresolved bias is memory bandwidth: every point retained the RTX 5090's 1792 GB/s-class 512-bit subsystem, while the target cards have much lower aggregate bandwidth and different controller counts. The results can therefore be optimistic, especially for 5060/5060 Ti. L2 pressure being nearly neutral does not remove that bandwidth/topology error.
