# RTX 50 DLSSNR proxy: SM, L2, and framebuffer bandwidth

Status: SM/L2 implementation and the five-card 1080p–4K matrix were completed on 2026-09-03; results are in [`rtx50-native-l2-matrix-20260903-004556/README.md`](rtx50-native-l2-matrix-20260903-004556/README.md). Physical framebuffer-bandwidth emulation was deliberately dropped and retained as an explicit error term. No result may be described as a complete emulation of another GPU: the test device remains one RTX 5090/GB202 with its physical memory controllers, cache slices, VRAM, power delivery, and boost controller.

## 1. Why SM-only is insufficient

The existing `cuda_feature_probe_green.exe` manually loads the signed DLSSNR DLL after making a CUDA Green Context current. This is useful: all opaque DLSSNR allocations and all internal/default-stream launches belong to the selected context, and `EvaluateFeature -> cuCtxSynchronize` covers its 156-kernel execution.

It does **not** partition the memory system. CUDA 13.3 exposes only these Green Context resource types:

- `CU_DEV_RESOURCE_TYPE_SM`;
- `CU_DEV_RESOURCE_TYPE_WORKQUEUE_CONFIG`;
- `CU_DEV_RESOURCE_TYPE_WORKQUEUE`.

There is no public Green Context **resource-descriptor partition** for an L2 slice, hard L2 capacity, memory controller, or DRAM bandwidth. Limiting the RTX 5090 to 30–84 SM therefore does not itself shrink the 96 MiB L2 or 512-bit memory system. This does not mean CUDA has no per-context L2 control: `CU_LIMIT_PERSISTING_L2_CACHE_SIZE` can set the current Green Context's persisting-L2 allowance, as verified in section 4, but it is a retention/set-aside mechanism rather than a hard total-cache quota.

The old 6K sweep already hints at a non-SM floor: `t = 2392.83 / SM + 4.67 ms`, but that intercept combines launch, synchronization, cache, bandwidth, and other weakly scaling costs. It is not an isolated memory-system measurement.

## 2. Target hardware axes

The first four L2 values are from NVIDIA's local RTX Blackwell architecture whitepaper (`/home/user/tmp/pdfs/nvidia-rtx-blackwell-gpu-architecture.pdf`, tables 3–6). RTX 5060-family L2 values require independent product/database sources because that revision of the NVIDIA whitepaper stops at GB205.

| Proxy label | Approx. SM | Official boost | L2 | Peak FB bandwidth | 5090 MCLK giving same aggregate theoretical BW |
|---|---:|---:|---:|---:|---:|
| RTX 5090 | 170 | 2.41 GHz | 96 MiB | 1792 GB/s | 14001 MHz |
| RTX 5080 | 84 | 2.62 GHz | 64 MiB | 960 GB/s | 7500 MHz |
| RTX 5070 Ti | 70 | 2.45 GHz | 48 MiB | 896 GB/s | 7000 MHz |
| RTX 5070 | 48 | 2.51 GHz | 48 MiB | 672 GB/s | 5250 MHz |
| RTX 5060 Ti | 36 | 2.57 GHz | 32 MiB | 448 GB/s | 3500 MHz |
| RTX 5060 | 30 | 2.50 GHz | 24 MiB | 448 GB/s | 3500 MHz |

For the RTX 5090's 512-bit GDDR7 interface, the nominal relation is:

`bandwidth_GB/s = MCLK_NVML_MHz * 2 * 512 / 8 / 1000 = MCLK * 0.128`.

Matching total GB/s by lowering a 512-bit interface is still not equivalent to a target card's narrower, faster interface. It preserves the RTX 5090's controller count and parallelism and changes memory-cycle latency. Every such point is a **bandwidth-matched wide-bus proxy**, not a memory-subsystem clone.

## 3. Recovered local L2 research

Primary records:

- `/home/user/rt_5090_project/L2_SLICE_MAP_FINDINGS.md`
- `/home/user/rt_5090_project/l2_slice_re/README.md`
- `/home/user/rt_5090_project/rt_cache_probe/CLAUDE_SW_CACHE_CONTROL_FINDINGS.md`
- `/home/user/rt_5090_project/rt_cache_probe/L2_PERSIST_RT_FINDINGS.md`

Verified on this RTX 5090:

- total L2: 100,663,296 bytes = 96 MiB;
- maximum persisting set-aside: 62,914,560 bytes = 60 MiB;
- maximum access-policy window: 128 MiB;
- 96 NVIDIA-named `l2s` units, 48 observable LTS PerfWorks rollup instances, and 16 DRAM rollup instances;
- a same-allocation CUDA API can discover 48 **relative** LTS classes and place selected caller-owned linear addresses across or within them;
- persisting access policy is a retention preference, not a lock and not physical isolation.

The relative-LTS mapper does not directly control DLSSNR:

1. It is allocation-scoped and supports caller-owned linear `cudaMalloc` memory.
2. The bare probe supplies CUDA arrays/textures/surfaces, whose physical/tiled placement is opaque.
3. The DLL allocates its internal weights and temporary tensors itself.
4. Relative rollup classes have no absolute physical slice IDs.
5. Contiguous DLSSNR tensors naturally span the memory hash; selecting a base address cannot shrink total L2 or disable paths.

The mapper remains useful for building a uniform, non-hotspotted L2/DRAM pressure generator and validating that dummy traffic covers all 48 observed rollups. It must not be described as assigning the DLL to target-card slices.

Dangerous raw L2 mask/re-enable work in `L2_REENABLE_STATIC_FINDINGS.md` is explicitly out of scope. It has no proven rollback contract and is neither required nor acceptable for this proxy.

## 4. Feasible L2-capacity-pressure method

Manual DLL invocation provides the remembered control point: before loading/evaluating DLSSNR, the Green Context can set `CU_LIMIT_PERSISTING_L2_CACHE_SIZE`. A local native probe created a 16-SM Green Context and proved that set/get/restore works there:

- initial allowance: 18 MiB;
- 0, 24, 30, 36, 42, 48, 54, and 60 MiB requests read back exactly;
- a 32 MiB request rounded upward to 36 MiB;
- the initial 18 MiB value was restored and `cuCtxResetPersistingL2Cache()` succeeded.

Evidence:

- `green_context_l2_limit_probe.cpp`
- `green_context_l2_limit_probe`
- `green-context-l2-limit-probe-20260903.log`

The observed allocation granularity is 6 MiB, and all future logic must use the **readback**, not assume the request was exact.

This setting is still not a hard cap on all cache used by the program. It determines how much L2 can receive persisting treatment. Because unused set-aside capacity can be used by normal accesses, changing the limit alone is insufficient for a smaller-total-L2 proxy. The probe must also allocate a dummy linear buffer, mark its accesses `CU_ACCESS_PROPERTY_PERSISTING`, and prime enough lines with an embedded `sm_120` kernel before every measured Evaluate. Priming must complete before the GPU timing interval, and the output hash must remain unchanged.

Approximate capacity-pressure settings on a 96 MiB L2 are:

| Desired ordinary working capacity | Requested reserve | Actual supported reserve | Result |
|---:|---:|---:|---|
| 96 MiB | 0 MiB plus persisting reset | 0 MiB | directly available |
| 64 MiB | 32 MiB | rounds to 36 MiB | bracket with 30/36 MiB reserve, leaving about 66/60 MiB |
| 48 MiB | 48 MiB | 48 MiB | directly representable as capacity pressure |
| 36 MiB | 60 MiB | 60 MiB | maximum directly representable pressure |
| 32 MiB | 64 MiB | exceeds 60 MiB maximum | not directly available |
| 24 MiB | 72 MiB | exceeds 60 MiB maximum | not directly available |

This preserves all RTX 5090 LTS paths and only applies cache-capacity pressure. It does not emulate target L2 latency, associativity, slice count, hash, ports, or controller topology. The RTX 5080's 64 MiB point needs a 60/66 MiB capacity bracket or interpolation; RTX 5060 Ti/5060 need a clearly labelled 36 MiB lower-pressure bound plus a separately calibrated contention bound or real-card validation. None may be reported as exact physical L2 emulation.

A victim-size microbenchmark must still verify that a populated reserve produces the intended effective ordinary-capacity boundary for every readback value. Nsight Compute's `launch__persisting_l2_cache_size`, L2 hit/miss metrics, and raw reserve readback should be archived. The fresh-context 18 MiB allowance does not itself mean 18 MiB is occupied; baseline runs must explicitly reset persisting status and set the requested limit.

## 5. Feasible framebuffer-bandwidth method

The cleanest candidate is a physical memory lock at the MCLK values in section 2, with mandatory readback. The post-reset LACT/NVML view reports a VRAM lock range of 405–14001 MHz, but `nvidia-smi --query-supported-clocks` lists only 14001 MHz. Acceptance of 7500/7000/5250/3500 MHz therefore remains unproven until a short, restore-guarded calibration is performed.

This machine also has a documented finite-MCLK-MAX propagation anomaly: a maximum endpoint can alter XBAR/SYS even when it does not physically constrain MCLK. Therefore every memory point must record:

- requested MCLK min/max and physical MCLK readback;
- GPC, XBAR, SYS, and NVD measured clocks;
- GPC→XBAR ratio;
- NVVDD/MSVDD targets;
- power limit, power, temperature, and throttle reasons;
- a guaranteed `nvmlDeviceResetMemoryLockedClocks`/`nvidia-smi -rmc` restore trap.

A point is rejected if physical MCLK does not adopt, if XBAR/SYS leaves the intended controlled tuple, or if reset does not restore the pre-test state. A max-only endpoint is not a valid bandwidth control.

If low MCLK cannot be adopted, the fallback is a second, disjoint Green Context running a uniformly distributed streaming kernel on the remainder SMs. It can consume calibrated FB bandwidth, but it also adds queueing, XBAR/L2 pressure, latency, and power. Such results are **contention bounds**, not bandwidth-matched card proxies.

For observation, repeated Evaluate loops should be long enough for NVML/RM FB-util sampling. `nvidia-smi dmon` memory utilization is coarse. Preferred evidence is Nsight Compute DRAM bytes/throughput and L2 traffic for representative launches, supplemented by the RM GPUMON FB-bandwidth-util samples where accessible.

## 6. Required experiment order

Do not immediately combine all knobs. Establish causal sensitivity first:

1. **Stock baseline:** explicit persisting reset, 14001 MHz MCLK, no user clock offsets, full 170 SM.
2. **SM-only matrix:** target SM allocations, stock MCLK/L2 state.
3. **MCLK-only matrix:** 14001/7500/7000/5250/3500 at full SM, only if physical readback adopts.
4. **L2-pressure-only matrix:** 96/48/36 MiB direct pressure points plus the 60/66 MiB bracket around the 5080's 64 MiB target, at full SM.
5. **Interaction subset:** at least 170, 84, 48, and 30 SM crossed with stock/target MCLK and stock/target L2 pressure.
6. Fit a response surface only after interaction terms are measured; do not multiply independent scaling ratios by assumption.
7. Run the official-resolution points (1080p Quality, 1440p Quality, 4K Performance) with fixed DLL, inputs, Feature18 parameters, 100 timed iterations after warmup, output hashes, and full clock tuple.

The final table should retain separate columns for:

- raw SM-only time;
- boost-normalized compute time;
- bandwidth-matched wide-bus time, if valid;
- L2-capacity-pressure time;
- combined proxy time;
- known topology and measurement caveats.

Any comparison with NVIDIA's `output FPS / 6` uses that value only as an endpoint cadence budget. It cannot isolate native rendering, SR, NR, or MFG costs.
