# RTX 5090D selective Tensor-throughput evidence

## Finding

Public source-backed measurements do exist. The strongest single dataset shows a sharp **MMA-mode-correlated throughput split**, rather than a uniform 29% reduction across all AI code. That pattern supports a mode-selective limiting hypothesis, but the available one-run data do not prove the limiter's implementation mechanism. They also do not establish executable-name detection, a three-second transition, or a CUDA-vs-Vulkan bypass.

## 1. Direct MMA issue benchmark

Source: <https://github.com/gakaki/mmapeak_5090_5090d>

- Commit inspected: `ec02e8ac47c925f0ab7e3ac2f52317122e024e02` (2025-06-05).
- Raw data: repository `result.txt`, SHA-256 `e04cb280e1a6cd570bc19d9593352343404c280591e1efbac5767141f0379151`.
- Source: `mmapeak.cu`, SHA-256 `5f0baa647685680fe9a9089a37a93bab03aae223e2bae1d88c089d8c4ebf9279`.
- Both GPUs appear in the same raw run: original 31.8-GiB RTX 5090 D as device 0 and 31.8-GiB RTX 5090 as device 1; both report 170 SMs.
- Each test launches 512 CTAs x four warps, repeats the native MMA 8,192 times in registers, calibrates, and then measures approximately three seconds with CUDA events. This isolates sustained MMA issue throughput rather than model, memory, or launch behavior.

| Native MMA mode | 5090D TFLOP/s | 5090 TFLOP/s | D/5090 | D loss |
|---|---:|---:|---:|---:|
| MXFP4 x MXFP4 -> FP32 | 859.6 | 1462.4 | 0.588 | 41.2% |
| NVFP4 x NVFP4 -> FP32 | 859.4 | 1463.6 | 0.587 | 41.3% |
| MXFP8 x MXFP8 -> FP32 | 426.5 | 731.5 | 0.583 | 41.7% |
| **FP8 E4M3 x E4M3 -> FP16** | **427.6** | **732.3** | **0.584** | **41.6%** |
| FP8 E4M3 x E4M3 -> FP32 | 352.3 | 369.9 | 0.952 | 4.8% |
| INT8 x INT8 -> INT32 | 428.6 | 740.9 | 0.578 | 42.2% |
| **FP16 x FP16 -> FP16** | **427.9** | **740.8** | **0.578** | **42.2%** |
| FP16 x FP16 -> FP32 | 337.0 | 369.9 | 0.911 | 8.9% |
| BF16 x BF16 -> FP32 | 340.5 | 369.9 | 0.921 | 7.9% |
| TF32 x TF32 -> FP32 | 85.5 | 93.3 | 0.916 | 8.4% |

The second FP16 shapes give the same pattern: FP16-accumulate D/5090 = 0.576, FP32-accumulate = 0.896. Unscaled FP4/FP6 and MXFP6 modes are also near full: 5090D reports 342.5--353.7 versus 369.9 TFLOP/s, only 4.4--7.4% lower. Across the reported slow modes the gap is approximately 4.8--10.4%. In this dataset, the roughly 42% gap is therefore not explained by input bit width or the presence of a scale alone; it correlates with the particular high-rate instruction form.

All of these modes are launched sequentially by the same executable and process. A process-name-only rule cannot by itself explain this within-process split; mode-dependent execution, power or scheduling behavior is still required. Without clock/power telemetry and repeats, the data do not identify which layer implements it.

The observed pattern is consistent with the proposed mechanism:

- fast FP8->FP16, FP16->FP16, INT8 and block-scaled FP4/FP8 modes report approximately 41--42% lower throughput on the 5090D;
- ordinary FP8->FP32, FP16/BF16->FP32 and TF32 report much smaller differences;
- MXFP8 block-scaled -> FP32 still reports a large difference, so this dataset does not support “FP32 accumulation is always exempt.”

A plausible interpretation is compatible with the BIS rule even though that rule uses input bit length rather than accumulator width: accumulator/mode selection changes the native MAC issue rate, so a slower ordinary FP8->FP32 path may need no additional cap while faster FP8->FP16 and block-scaled paths may. The one-run benchmark cannot prove that this regulatory rationale is the actual implementation.

The exact DLSS NR SASS recovered locally, `QMMA.16832.F16.E4M3.E4M3`, has the same operand/accumulator form as the benchmark's FP8->FP16 PTX. A locally built/available `mmapeak` binary and the public [`sass-king` SM120a corpus](https://github.com/florianmattana/sass-king/blob/main/corpus/tensor_cores/14_qmma_fp8/14j_qmma_e4m3_e4m3_f16.sass) show that this PTX form can lower to that QMMA opcode. The published `mmapeak` result does not include its original CUBIN hash or disassembly, so this is an opcode-class correspondence, not proof of the exact SASS used in the reported run. If one conditionally attributes all counted work to that 8,192-FLOP instruction, 427.6 and 732.3 TFLOP/s correspond to about 52.2 and 89.4 G-instruction/s (307 and 526 M-instruction/s/SM); these are arithmetic conversions, not measured SASS issue counters. None of this shows that a DLSS kernel reaches the synthetic issue ceiling or that a 5090D limits it. A future controlled 5090D/5090 DLSS equality result could still be explained by under-saturating the ceiling, but that remains a conditional hypothesis.

### RTX 5080 scaling countercheck

A public NBA 2K27 comparison reports an inferred incremental DLSS 5 cost of approximately 7.9 ms on a 5090 versus 13.7 ms on a 5080 at 4K, and 3.6 versus 6.1 ms at 1440p: <https://www.techspot.com/article/3170-real-dlss-5-performance/>. These are whole-game on/off frame-time differences, not GPU timestamps around an isolated neural pass; the 5090 1440p value is extrapolated. They nevertheless show approximately 1.69--1.73x end-to-end scaling between the cards.

The 5080 has 84 SMs versus 170 on the 5090, and 960 versus 1,792 GB/s memory bandwidth. Thus this comparison cannot isolate SM count from bandwidth, clocks, power or engine behavior. It does establish that the full DLSS 5 graph is substantially resource-sensitive. The earlier local 32-CTA/5.56%-Tensor observation covered one N64 contract kernel, not all approximately 156 launches; it must not be generalized to the complete model. Local 6K decomposition likewise found the ViT kernels at about 3.63 ms but the spatial Swin kernels at about 14.50 ms.

For a purely illustrative 5080-Ti-like card with 121 SMs (29% fewer than 170), fitting the two observed cards to `T = a + b/SM` predicts approximately 10.19 ms at 4K and 4.59 ms at 1440p: 29.0% and 27.5% longer than the 5090 incremental costs. This is an interpolation, not a product prediction, because the two real cards also differ in bandwidth and clocks. A fully SM-throughput-bound limit would instead be 40.8% longer latency (29% lower throughput).

The comparison with 5090D must keep two different mechanisms separate. Physically removing 29% of SMs reduces many resources throughout the graph. A selective Tensor ceiling can have no effect until a relevant kernel reaches it. However, the reported `mmapeak` FP8->FP16 ratio is 0.584, equivalent to only about 99 of 170 full-rate SMs under a linear analogy, not the 121 SMs implied by the advertised 2,375/3,352 ratio. Therefore, if a controlled DLSS trace showed the relevant QMMA work exceeding the 5090D ceiling, no slowdown would be difficult to reconcile without an exemption or another measurement error. Current public data do not supply that trace.

### Method caveats

- No per-card clock, power or thermal CSV accompanies `result.txt`.
- Inputs are register-resident zeros and every MMA is followed by `__syncwarp()`. The same author previously showed on a 5090 that replacing zero operands with random data left FP8->FP16/FP32 almost unchanged but materially reduced FP16/BF16 results: <https://main-horse.github.io/posts/5090-mm-perf/>. The absolute zero-input numbers are therefore peak issue proxies, not application throughput; the FP8 accumulator split is less exposed to this specific caveat than the FP16/BF16 rows.
- Each measured mode is an aggregate approximately-three-second interval; there is no sub-second throughput trace, so it cannot prove or disprove a cliff exactly at three seconds.
- The identical source applied to both SKUs and the slow-mode controls nevertheless make the mode-correlated contrast meaningful evidence, while remaining insufficient to locate its implementation.

## 2. CUTLASS block-scaled real-GEMM screenshots

Source: <https://github.com/TuKJet/5090_5090d_tensorcore_compare>

- Commit inspected: `169ae894e43dd055b6ba5493aba6325b3aad9ec4` (2025-04-18).
- README SHA-256: `0c834fc88bfce2d4a3b69e1600a12adf0af3a6c796ed67d6de7131f0655e78be`.
- Original 31.8-GiB 5090D screenshot SHA-256: `6e1f288ec65493452aea800cfaa633b8a00b396c5ff9837a7761d5e8e6a83fb0`.
- RTX 5090 screenshot SHA-256: `2af6594c0255d2f329be885bb97b84c0905dc3aaf70f6708f028a4188f98309a`.

CUTLASS SM120a block-scaled GEMM, `M=2048, N=5120, K=5120`, mixed FP6/FP8 inputs and FP32 accumulation:

- RTX 5090D: **527,223 GFLOP/s**, 0.2037 ms.
- RTX 5090: **719,651 GFLOP/s**, 0.149232 ms.
- D/5090 = **0.7326**, or **26.7% lower throughput**.

This is a materialized GEMM rather than a register-only issue loop, but it is **not a controlled independent A/B**. The two single-run, self-reported screenshots use the same named kernel and shape, yet the 5090D reports `raster_order=heuristic` while the 5090 reports `raster_order=along_m`. They do not provide a shared CUTLASS commit, CUDA/driver version, clocks/power, repetitions, or raw CSV. The screenshots therefore provide supporting evidence only; configuration/environment differences cannot be excluded.

## 3. Related public evidence for compile-time kernel-name sensitivity

Merged Triton PR [#7298](https://github.com/triton-lang/triton/pull/7298) contains a publicly inspectable author claim that an FP8 attention kernel became up to roughly 100--150 TFLOP/s faster when its generated kernel symbol was prefixed with lowercase `cutlass_`. In the review:

- the author replied that they believed `cutlass` itself was specially cased;
- another contributor posted a reverse-engineering screenshot and asserted that the tested `ptxas` contained logic equivalent to `strstr(kernel_name, "cutlass")`;
- a later third-party investigation reproduced name-sensitive compilation on its tested toolchains, comparing PTX that differed only in the symbol and observing different SASS scheduling/register behavior: <https://maknee.github.io/blog/2025/Maybe-Consider-Putting-Cutlass-In-Your-CUDA-Kernels/>.

This is evidence for a **compile-time, kernel-symbol-sensitive `ptxas` heuristic in the tested versions**, not an NVIDIA-documented guarantee. It is not evidence of runtime process-name detection, it was not a 5090D same-SASS test, and the generated SASS changes. Once a CUBIN is built, launching that same CUBIN through CUDA or Vulkan cannot retroactively invoke this compiler pass. It therefore does not establish a DLSS/5090D whitelist or an API bypass.

## 4. What is not found

No auditable public test was found for:

1. identical Tensor CUBIN through `cuLaunchKernel` versus `vkCmdCuLaunchKernelNVX` on 5090D;
2. process/executable rename changing sustained throughput while the loaded CUBIN/SASS remains identical;
3. 100-ms throughput samples showing a reproducible cliff at exactly three seconds;
4. driver/VBIOS A/B unlocking Tensor issue rate while holding clocks and opcode constant.

The “three-second” claim can be traced to the 2025-01-16 Chiphell thread [#2666266, `RTX5090D驱动给了，说点能聊的`](https://www.chiphell.com/thread-2666266-1-1.html), whose quoted assertion was “AI直接3秒真男人，炼丹3秒锁算力”. HKEPC and international media repeated it the next day. The indexed thread supplies no per-interval throughput/clock trace or reproducible kernel, so this remains an anonymous pre-release claim rather than measured public evidence.

The pre-release video [`BV1s3cLeyEYh`](https://www.bilibili.com/video/BV1s3cLeyEYh/) discussed possible vBIOS- or driver-based limiting, but provided no ROM diff, driver diff, reproducible patch, or before/after Tensor benchmark. High-power XOC vBIOS reports establish power-limit changes, not removal of a Tensor-mode limit.

### Multi-GPU claim

A later single-author video report, [`BV1AcQ4YUEPQ`](https://www.bilibili.com/video/BV1AcQ4YUEPQ/), claims that rebuilding/updating NCCL enabled dual-5090D TensorRT-LLM inference with `mpirun -n 2`. This is useful counterevidence against the absolute claim that multi-GPU use is API-blocked, but it supplies no raw NCCL log, inter-GPU bandwidth, throughput comparison, or 5090 control. NCCL `v2.26.2-1` officially notes a fix for shared-memory usage on recent Blackwell GPUs, not a 5090D-specific unlock. The report therefore shows, at most, that some multi-GPU software configurations can run; it does not establish an unrestricted or bypassed Tensor path.

## Deferred hardware acquisition decision

Do not buy the approximately CNY 40,000 used RTX 5090D HOF solely for this experiment. It is economically disproportionate, and its extreme PCB/XOC vBIOS would be a worse representative control than a stock 32GB 5090D. Wait for an hourly-rental stock card instead. The first SeetaCloud allocation was verified as an original 32GB RTX 5090D but was not benchmarked because it arrived stuck at P0/99--100% SM utilization with 2MiB used and no visible process under driver 595.71.05; releasing/restarting the scarce allocation then lost availability. On a future allocation, retain the reservation and request a host-level GPU reset rather than releasing it.

## Live hardware follow-up (2026-09-23)

A rented original 32 GB/170-SM RTX 5090 D was tested with the source-pinned public `mmapeak` probe after a stale Blackwell/NVML 100%-utilization state was cleared by a clean CUDA context run. From a verified P8/0% idle baseline, the card reported 431.2 T(fl)op/s for native FP8 E4M3→FP16, 378.0 T(fl)op/s for FP8 E4M3→FP32, and 862.9 T(fl)op/s for MXFP4→FP32. The same key rates were already present in a 0.1-second-per-mode smoke run, providing no evidence for a three-second grace interval. Active clocks held at 2,925 MHz, sampled power peaked at 229.67 W against a 450 W limit, and temperature peaked at 40 °C.

An exact-binary FP8→FP16 grid sweep against the local full 5090 then isolated the low-impact regime. From 1 through 170 CTAs, the D delivered a median 96.9% of the full card raw and 101.4% after simple active-clock normalization. At exactly 170 CTAs the cards measured 555 versus 571 T(fl)op/s. Doubling to 340 CTAs left the D almost flat at 563 T while the full card rose to 1,028 T. Thus the restricted opcode itself is not materially slower in an under-filled launch; the large SKU difference appears only when enough concurrent QMMA work requests the additional issue capacity. This supplies a direct mechanism for small-grid, small-batch, irregular, synchronized or memory-bound models showing little loss. It is an occupancy sweep, not mathematical sparse-matrix arithmetic, and does not locate the limiter implementation.

The FP8→FP16 sweep was repeated with every E4M3 operand byte set to nonzero `0x20` (0.125), and disassembly verified `MOV 0x20202020` feeding `QMMA.16832.F16.E4M3.E4M3`. Nonzero versus zero rates changed by less than about 0.4% at selected points. At the exact 340-CTA grid the D measured 562.9075 T(fl)op/s against 1,025.9135 T on the full card; using the benchmark's two-operations-per-MAC convention gives arithmetic TPP conversions of 4,503.26 and 8,207.31. Sampled power peaked at only 190 and 267 W under the 450 W limits. This directly removes the zero-input issue-proxy caveat for native FP8 arithmetic with FP16 accumulation, while remaining a register-resident measured proxy rather than the formal regulatory theoretical-maximum calculation.

A matched PyTorch 2.8/CUDA 12.8/cuDNN 9.10.2 model-level comparison at 450 W then measured the D against the local full 5090. BF16 convolutional-UNet training/inference throughput was 9.0%/8.7% lower, while an 8-layer width-1024 SDPA Transformer was 7.6% lower in training and 5.2% lower in inference. The local full card also held a 5.2% higher active median SM clock and a 23.2% memory-clock overclock, so these raw gaps are not pure SKU effects; crude SM-clock-normalized throughput ratios were about 95.7%, 96.0%, 97.2%, and 99.8%. These synthetic resident-tensor graphs are not full application suites, but they directly reproduce the previously reported single-digit practical gap.

A same-CUBIN Vulkan comparison was intentionally left unresolved because the rental container denied access to `/dev/nvidia-modeset`; the NVIDIA ICD could not initialize. This is an environment limitation and does not count as a negative `VK_NVX_binary_import` result. Full source, binary, hashes, raw output and telemetry are preserved in `../rtx5090d-live-20260923/`; see its `REPORT.md`.

## Static mechanism update: fuse-derived issue mask and credit

NVIDIA's R580+ open RM headers expose a separate `NV2080_CTRL_CMD_GR_GET_SM_ISSUE_THROTTLE_CTRL` (`0x2080123d`) path in addition to the older issue-rate/speed-select interface. Its documented entries are `MASK`; and, beginning in R595, `CREDIT`. A zero-sized query returns all **fuse values**. The exact cloud driver, 595.71.05, contains both entries. Open RM obtains the values per GR engine through internal GSP control `0x20800b05`, caches them as static graphics information, and publishes a read-only GET.

This is now the leading implementation candidate because `MASK` naturally matches mode selection while `CREDIT` naturally matches the observed concurrency boundary. It supports a chain of SKU/fuse identity → GSP/RM static configuration → GR/SM hardware issue-credit enforcement. It still does not reveal the mask-bit mapping, credit unit, physical register or actual 2B85/2B87 values, so it is strong mechanism evidence rather than final attribution. See `../../../power_governor_reverse/RTX5090D_SM_ISSUE_THROTTLE_REVERSE_20260923.md`.

## Conclusion

The strongest public dataset, now supplemented by a live original-5090D reproduction, shows a **selective, MMA/data/accumulator-mode-correlated throughput pattern**: high-rate modes are much slower; several ordinary FP32-accumulate modes are near the full card, but fast block-scaled FP32-accumulate modes are not. This strongly supports a mode-selective limiter implementation. Ordinary model benchmarks can show little difference without requiring benchmark-name recognition. The within-process split rules out a process-name-only explanation, and the short run supplies no evidence for a three-second grace period. A Vulkan whitelist/bypass remains possible as a hypothesis but is currently unproven.
