# Live RTX 5090 D selective-MMA probe — 2026-09-23

## Scope

A short, source-pinned CUDA probe was run on a rented original 32 GB RTX 5090 D. This run tests native MMA-mode throughput. It does **not** by itself determine legal export classification, and it does not test a Vulkan/API bypass.

## Device and environment

- GPU: NVIDIA GeForce RTX 5090 D
- PCI device ID: `0x2B87`
- VRAM reported by NVML: 32,607 MiB
- SM count reported by CUDA: 170
- Compute capability: 12.0
- Driver/GSP: 595.71.05
- VBIOS: 98.02.31.00.5c
- Power limit: 450 W
- GPU UUID: `GPU-ad913325-726d-5d1e-1185-fe3fee99d588`

The allocation initially exhibited NVIDIA Blackwell bug 5446845's characteristic stale state: P0, 100% legacy NVML GPU utilization, 2 MiB used, no process, about 107 W, and about 2,925 MHz. A targeted `nvidia-smi --gpu-reset -i 0` was rejected as unsupported. Running the short CUDA probe and allowing its context to exit cleanly cleared the stale reading. Twelve subsequent idle samples were stable at P8, 0%, 2 MiB, 180 MHz and approximately 10 W. This confirms that the initial 100% reading was not a competing compute workload.

## Probe provenance

Upstream: `gakaki/mmapeak_5090_5090d`

- Pinned commit: `ec02e8ac47c925f0ab7e3ac2f52317122e024e02`
- Source SHA-256: `5f0baa647685680fe9a9089a37a93bab03aae223e2bae1d88c089d8c4ebf9279`
- Remotely compiled binary SHA-256: `511b8b4e30ad5ae6196d8da4bab8ae2d44b733559015aade29a0cd80780f77b4`
- Compiler: CUDA 12.8 `nvcc`
- Target: `compute_120a,sm_120a`
- Compile command: `nvcc -O2 mmapeak.cu -gencode arch=compute_120a,code=sm_120a -o mmapeak`

Disassembly contains both key native forms:

```text
QMMA.16832.F16.E4M3.E4M3
QMMA.16832.F32.E4M3.E4M3
```

## Clean-P8 run

The clean repeat used `./mmapeak -t 0.5`. The process completed normally (`rc=0`) in 11.88 seconds. Before the run the card was P8/0%/9.20 W; eight seconds after exit it was P8/0%/9.72 W.

| Native mode | Measured rate |
|---|---:|
| MXFP4 × MXFP4 → FP32 | 862.9 T(fl)op/s |
| NVFP4 × NVFP4 → FP32 | 862.9 T(fl)op/s |
| MXFP8 × MXFP8 → FP32 | 431.1 T(fl)op/s |
| **FP8 E4M3 × E4M3 → FP16** | **431.2 T(fl)op/s** |
| FP8 E4M3 × E4M3 → FP32 | 378.0 T(fl)op/s |
| INT8 × INT8 → INT32 | 431.4–431.7 T(op/s) |
| FP16 × FP16 → FP16 | 431.2–431.4 T(fl)op/s |
| FP16 × FP16 → FP32 | 378.2 T(fl)op/s |
| BF16 × BF16 → FP32 | 378.2 T(fl)op/s |
| TF32 × TF32 → FP32 | 94.7 T(fl)op/s |

The preceding 0.1-second-per-mode smoke run produced essentially the same key results:

- FP8→FP16: 431.8 T(fl)op/s
- FP8→FP32: 376.1 T(fl)op/s
- MXFP4→FP32: 861.6 T(fl)op/s

Thus the high-rate FP8 path was already limited in a sub-second measurement; this run supplies no evidence for a limiter that waits three seconds before engaging.

During the clean run:

- SM clock median/max: 2,925/2,925 MHz while active
- peak sampled power: 229.67 W, far below the 450 W limit
- memory utilization: 0%, as expected for a register-resident issue benchmark
- peak temperature: 40 °C

The observed FP8 result therefore is not explained by thermal throttling or the board power cap.

## Under-filled grid sweep: why many real workloads are nearly unaffected

The exact same CUDA 12.8 binary and `QMMA.16832.F16.E4M3.E4M3` SASS were run on this RTX 5090 D and on the local full RTX 5090. The kernel is register-resident and only the CTA count changes. Each point is the median of ascending and descending passes.

| CTAs | Warps | RTX 5090 D | RTX 5090 | D/5090 | Clock-normalized D/5090 |
|---:|---:|---:|---:|---:|---:|
| 1 | 4 | 3.282 T | 3.389 T | 96.8% | 101.3% |
| 32 | 128 | 104.792 T | 108.346 T | 96.7% | 101.2% |
| 64 | 256 | 209.253 T | 215.883 T | 96.9% | 101.4% |
| 96 | 384 | 313.543 T | 323.516 T | 96.9% | 101.4% |
| 128 | 512 | 418.023 T | 429.799 T | 97.3% | 101.8% |
| 144 | 576 | 470.240 T | 483.625 T | 97.2% | 101.7% |
| **170** | **680** | **554.956 T** | **570.552 T** | **97.3%** | **101.8%** |
| 192 | 768 | 318.133 T | 582.323 T | 54.6% | 57.2% |
| 256 | 1,024 | 423.952 T | 776.457 T | 54.6% | 57.1% |
| **340** | **1,360** | **563.218 T** | **1,028.299 T** | **54.8%** | **57.3%** |
| 512 | 2,048 | 431.533 T | 772.211 T | 55.9% | 58.5% |

The active median clocks were approximately 2,925 MHz on the D and 3,060 MHz on the full 5090. Across 1–170 CTAs, the median raw D/5090 ratio was 96.9%; after this simple clock normalization it was 101.4%. In other words, an under-filled FP8→FP16 workload showed effectively no D-specific loss even though it used the nominally restricted native opcode.

The split appears only once the grid asks for more than roughly one CTA per physical SM. At the two exact multiples that avoid a tail-wave artifact:

```text
170 CTAs: D 555 T, full 5090 571 T
340 CTAs: D 563 T, full 5090 1028 T
```

Doubling the grid from 170 to 340 increased the D by only 1.5%, but the full card by about 80%. This is consistent with a chip-wide issue/arbitration ceiling or equivalent scheduling restriction becoming relevant only under sufficient concurrent QMMA work. The experiment does not identify the exact firmware/hardware mechanism.

This is not mathematical sparse-matrix arithmetic; it is a controlled **non-saturating/under-filled** use of the same dense QMMA instruction. It directly explains why small-batch, small-grid, irregular, synchronized, attention-heavy or memory-bound real models can remain close to the full 5090: they never request the second tranche of concurrent Tensor issue capacity that distinguishes the full card. Raw results and the complete comparison are in `sweep-d.stdout`, `sweep-5090.stdout`, and `sweep-comparison.csv`.

## Interpretation

This live run independently reproduces and refines the public mode-selective pattern on an original RTX 5090 D:

- the public probe's fixed 512-CTA FP8→FP16 result is about 431 T, but 512 is a tail-affected grid on 170 SMs;
- exact-multiple grids show the D's highest observed FP8→FP16 issue rate near 563 T, while the full 5090 continues to 1,028 T;
- ordinary FP8→FP32 in the fixed-grid probe remains near 378 T;
- the same executable and exact sweep binary distinguish mode and concurrency, so process-name-only detection cannot explain the result;
- the high-rate restriction is already visible in the early short run rather than appearing only after three seconds.

Using the benchmark's two-operations-per-MAC convention, the highest observed D FP8→FP16 issue rate converts arithmetically to about `563.218 × 8 = 4505.7` TPP units, below 4,800. This is a measured zero-operand issue-loop conversion, **not** a substitute for the regulatory theoretical-maximum classification calculation.

The source uses zero register operands. This makes absolute rates peak-issue proxies; public testing by the same author found FP16/BF16 modes more sensitive to zero versus random operands, while the FP8 accumulator split was much less affected. Accordingly, the FP8 rows are the stronger evidence here.

## Nonzero FP8 inputs with native FP16 accumulation

To remove the zero-register-input caveat, the exact grid sweep was rebuilt with every E4M3 input byte set to `0x20`, representing `0.125`. Each native QMMA therefore accumulates real nonzero products; after 8,192 iterations the expected magnitude remains finite in FP16. Disassembly verifies both the constants and opcode:

```text
MOV ... 0x20202020
QMMA.16832.F16.E4M3.E4M3
```

The same CUDA 12.8 binary was run on both cards at 450 W. Selected median results:

| CTAs | Nonzero RTX 5090 D | Nonzero RTX 5090 | D/5090 | D nonzero/zero | 5090 nonzero/zero |
|---:|---:|---:|---:|---:|---:|
| 32 | 104.626 T | 108.058 T | 96.8% | 99.84% | 99.73% |
| 96 | 313.045 T | 322.914 T | 96.9% | 99.84% | 99.81% |
| 170 | 554.068 T | 572.762 T | 96.7% | 99.84% | 100.39% |
| **340** | **562.908 T** | **1,025.914 T** | **54.9%** | **99.94%** | **99.77%** |
| 512 | 431.426 T | 772.603 T | 55.8% | 99.98% | 100.05% |

Nonzero operands changed the measured rates by less than about 0.4% at the selected points. Thus the mode split and concurrency ceiling are not artifacts of multiplying zero data.

At the exact 340-CTA grid, which avoids the 512-CTA tail-wave artifact, the highest observed nonzero FP8→FP16 issue rates were 562.9075 T(fl)op/s on the D and 1,025.9135 T(fl)op/s on the full card. Under the benchmark's two-operations-per-MAC convention, the arithmetic TPP conversions are:

```text
RTX 5090 D: 562.9075 × 8 = 4503.26
RTX 5090:   1025.9135 × 8 = 8207.31
```

Both tests remained below their configured 450 W limits in sampled power (D peak 190.13 W; full-card peak 266.5 W), with active median SM clocks of 2,925 and 3,060 MHz. The D/full raw ratio at 340 CTAs was 54.9%, or 57.4% after simple clock normalization.

This is direct native FP8 arithmetic with FP16 accumulation, but still a register-resident issue-throughput test rather than a materialized end-to-end GEMM. The conversion is measured evidence, not a replacement for the formal regulatory theoretical-maximum calculation. Full raw results are preserved in `sweep-nz-d.*`, `sweep-nz-5090.*`, and `sweep-nonzero-comparison.{csv,json}`.

## BF16 model-level comparison at equal 450 W power limits

A pure-PyTorch synthetic benchmark was then run on both cards with an exactly matched software stack: PyTorch `2.8.0+cu128`, CUDA 12.8 packages, and cuDNN 9.10.2. Both cards were configured to a 450 W power limit. Random seeds, model definitions, resident input tensors, warmups and measured iterations were identical; matching first losses verify matching initialization and inputs.

Workloads:

- convolutional UNet: batch 8, `4×256×256`, three down/up levels, residual blocks, BF16 autocast;
- Transformer: 8 layers, width 1,024, 16 heads, sequence 1,024, batch 8, SDPA attention and 4× MLP, BF16 autocast;
- training includes forward, FP32 loss, backward and AdamW update;
- inference uses `torch.inference_mode()` and BF16 autocast;
- data loading and host transfers are excluded.

| Workload | RTX 5090 D at 450 W | RTX 5090 at 450 W | D throughput difference | D latency difference |
|---|---:|---:|---:|---:|
| UNet training | 75.411 ms; 106.09 images/s | 68.626 ms; 116.57 images/s | **−9.0%** | **+9.9%** |
| UNet inference | 28.075 ms; 284.95 images/s | 25.627 ms; 312.18 images/s | **−8.7%** | **+9.6%** |
| Transformer training | 43.950 ms; 186,392 tokens/s | 40.606 ms; 201,746 tokens/s | **−7.6%** | **+8.2%** |
| Transformer inference | 11.955 ms; 685,220 tokens/s | 11.337 ms; 722,598 tokens/s | **−5.2%** | **+5.5%** |

These raw differences are much smaller than the saturated native-QMMA gap. They also include a material clock/tuning advantage for the local full card despite equal power limits:

- active median SM clock: approximately 2,808.5 MHz on the D versus 2,955 MHz on the full card;
- memory clock: 13,801 MHz on the D versus the locally overclocked 17,001 MHz on the full card;
- local desktop processes remained resident but showed negligible compute utilization.

A crude SM-clock normalization changes the D/full throughput ratios from 91.0/91.3/92.4/94.8% to approximately 95.7/96.0/97.2/99.8% for UNet train, UNet inference, Transformer train and Transformer inference respectively. This is not a full normalization because UNet and attention mix compute, memory and launch effects; the 23.2% local memory-clock advantage remains. The result nevertheless supports the under-filled-grid finding: practical mixed graphs at matched board power lose only single-digit throughput, with simple Transformer inference closest to parity.

Raw JSON, CUDA-event timings, wall times, memory peaks, telemetry and the exact benchmark source are stored as `model-d.*`, `model-5090.*`, `model-comparison.{csv,json}`, and `model_bench.py`.

## Full DLSS 5 model on the RTX 5090 D

The complete unpacked DLSSNR `310.8.0.0` PE DLL was deployed to the cloud card and executed through its native CUDA NGX path. The DLL, probe and inputs were byte-identical to the local full-5090 run. On the headless cloud host, the patched Wine nvcuda bridge's `CUDA_FAKE_LUID=1` path was required to synthesize the Windows-style device identity from the real CUDA UUID; this affects identity lookup, not the subsequently captured CUDA work. `CreateFeature`, all `EvaluateFeature` calls, release and shutdown returned success, and both cards produced bit-identical outputs.

Nsight captured 156 CUDA kernel launches per frame. CTA demand is resolution- and kernel-dependent rather than one fixed number:

| Input | CTA range per launch | Cumulative CTAs/frame | Launches at ≤170 CTAs | Typical ViT grids |
|---|---:|---:|---:|---:|
| 512×512 | 8–4,745 | 26,336 | 137/156 | 40×32 CTA, 2×96 CTA |
| 3840×2160 | 160–131,313 | 704,986 | 1/156 | 32×544 CTA, 8×288 CTA |

The cumulative count is not simultaneous residency: each kernel is launched separately and large grids execute in waves. Grid size alone therefore does not determine whether the selective FP8 issue ceiling is reached.

Both cards were limited to 450 W. After discarding the first ten frames, CUDA-event medians around the complete `EvaluateFeature` were:

| Input | RTX 5090 D | RTX 5090 | D latency difference | D throughput difference |
|---|---:|---:|---:|---:|
| 512×512, 100 frames | 5.392 ms | 5.047 ms | +6.8% | −6.4% |
| 3840×2160, 30 frames | 12.264 ms | 10.946 ms | +12.0% | −10.8% |

These are cross-host end-to-end spans around 156 submissions. At 4K, cloud/local CPU submission medians were 3.706/2.584 ms, so the raw 12% gap is not all GPU time. In separate one-frame Nsight captures, sums of the 156 actual kernel intervals were 2.092/1.924 ms at 512² and 8.793/9.061 ms at 4K (D/full). The profiled samples should not be used to claim that the D is faster at 4K, but they rule out a roughly 45% kernel-time collapse in this complete graph.

After 100 evaluations at 512², both outputs had SHA-256 `1c6bf93b5e2997b378be66e823c931fdacdca842e1e18581cbdc5789c92b79d5`; after 30 evaluations at 4K, both had `6e17efb2fdd38513eb6b16511d7bf0e3ed19bef05e87573f0a75d7818682b0cf`. Full methodology, raw logs, outputs, telemetry, Nsight reports/SQLite, per-launch CTA tables and source snapshots are preserved in `DLSS5_FULL_MODEL_TEST.md` and the `dlss5-*` artifacts.

## Static mechanism follow-up: SM issue-throttle mask and credit

A subsequent static audit found a more specific mechanism candidate than the previously recovered MODS `OverrideIssueRate()` path. NVIDIA's open RM headers added a separate `NV2080_CTRL_CMD_GR_GET_SM_ISSUE_THROTTLE_CTRL` (`0x2080123d`) interface in R580. It initially exposed fuse index 0, `MASK`; R595 added fuse index 1, `CREDIT`. The exact cloud driver version, 595.71.05, defines both. The documentation says these are throttle-control values for instruction types and that a zero-sized query returns all **fuse values**.

Open RM's GR initialization retrieves the per-engine values through internal control `0x20800b05`, caches them in `KGRAPHICS_STATIC_INFO`, and exposes only a GET interface. The signed 610.57.04 GSP main ELF independently contains exact-size descriptors for both commands (`0x07fc` public and `0x3fe0` for eight GR engines); the public handler dispatches through the active KernelGraphics HAL. This establishes a real GSP/RM static-info path, not merely unused header names.

The `MASK+CREDIT` shape matches the observed behavior unusually well: a mask can select only high-rate instruction modes, while a credit budget can preserve the first approximately one-CTA-per-SM tranche and cap additional concurrent issue capacity. It therefore becomes the leading implementation candidate: SKU/fuse identity → GSP/RM per-GR configuration → GR/SM hardware credit enforcement. Ordinary VBIOS power tables and application-name detection remain poor fits. This is not yet proof: no 2B85/2B87 read-only value comparison was captured, and the mask bits, credit units, physical fuse field and privileged register remain unknown. Full static evidence and caveats are in `../../../power_governor_reverse/RTX5090D_SM_ISSUE_THROTTLE_REVERSE_20260923.md`.

## Vulkan/API-bypass status

A Vulkan instance could not be created in this rental container. The NVIDIA ICD and `/dev/dri/card4`/`renderD131` were present, but the container did not expose permission to `/dev/nvidia-modeset`; opening a temporary matching device node returned `EPERM`. The ICD therefore returned `VK_ERROR_INCOMPATIBLE_DRIVER` through the loader. This is an environment limitation, not a negative result for `VK_NVX_binary_import`.

Consequently, the decisive same-CUBIN comparison remains unperformed:

```text
cuLaunchKernel
vs.
vkCmdCuLaunchKernelNVX
```

## Bottom line

The live data strongly confirm that the original 5090 D applies an immediate, native-MMA-mode-correlated CUDA throughput restriction. They provide no evidence of a CUDA process-name bypass or a three-second grace period. The complete DLSS 5 CUDA model nevertheless runs correctly and bit-identically; its measured end-to-end throughput loss was about 6.4% at 512² and 10.8% at 4K in this cross-host comparison, not the saturated microbenchmark's roughly 45%. They neither prove nor disprove a Vulkan/NVX bypass, because this container lacks the required graphics/modeset device access.
