# DLSSNR 6K CUDA Green Context scaling sweep

## Scope

- Model: `nvngx_dlssnr.dll` 310.8, exact packed CUDA/CUBIN path.
- Frame: 6144x3456 RGBA32F, DLAA/image-to-image parameters.
- GPU: RTX 5090, 170 SMs reported by CUDA.
- Power limit: 600 W, verified before every partition run.
- Memory clock: 15001 MHz reported by NVML.
- Each point: five forwards in one feature instance; iteration 0 discarded;
  median of iterations 1-4 reported.
- No kernel Xid, GPU-lost, or reset-required event was observed.

## Partition method

CUDA Green Contexts spatially restricted the process to a verified number of
SMs. CUDA reported an 8-SM minimum and 8-SM co-scheduling alignment. The
1-through-10 "GPC-equivalent" points used 16, 32, ..., 160 SMs. Point 11 used
the full 170-SM resource. These are safe SM partitions, not destructive
physical GPC enable-mask changes, and do not guarantee exact whole-GPC identity.

The NGX runtime submits fused kernels to an internal/default stream. Therefore
events placed on the caller's explicit Green Context stream measure only about
1.9 ms of submission-side work. The authoritative sweep time is wall time from
before `EvaluateFeature` through `cuCtxSynchronize`, which covers every stream
in the Green Context.

## Result

| GPC equivalent | Actual SMs | Median wall time (ms) |
|---:|---:|---:|
| 1 | 16 | 155.170 |
| 2 | 32 | 78.382 |
| 3 | 48 | 53.575 |
| 4 | 64 | 41.551 |
| 5 | 80 | 33.794 |
| 6 | 96 | 28.856 |
| 7 | 112 | 25.576 |
| 8 | 128 | 23.639 |
| 9 | 144 | 22.069 |
| 10 | 160 | 20.686 |
| 11 | 170 | 20.129 |

All eleven final outputs had the same SHA-256:
`028e7fa578b62928031494f1a0c399ef12d5a8a26c7e013a858eac5963116a24`.

A least-squares fit gives `time_ms = 2392.83 / SM + 4.67` with R^2=0.99949.
This is an empirical scaling model, not proof that 4.67 ms is literally serial;
it also includes weakly scaling bandwidth, launch, synchronization, and fixed
work. Scaling from 16 to 170 SMs is 7.71x versus the ideal 10.625x. The final
160-to-170-SM step improves time by 2.69%.

NVML observed peak GPU utilization 100%, memory utilization 33%, power 152.72 W,
graphics clock 3097 MHz, and 6941 MiB process-era VRAM. These are coarse NVML
samples; per-SM active, occupancy, Tensor utilization, and DRAM throughput were
not available because NVIDIA GPU Metrics returned `ERR_NVGPUCTRPERM`.

