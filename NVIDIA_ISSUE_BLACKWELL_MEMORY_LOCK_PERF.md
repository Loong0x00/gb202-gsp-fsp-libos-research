# RTX 5090: a finite memory-clock maximum silently constrains XBAR/SYS and changes performance by up to 32%

## NVIDIA Open GPU Kernel Modules Version

`610.43.03` (`nvidia-open-dkms 610.43.03-3`)

## Proprietary-driver comparison

Not applicable on this hardware: the tested GPU is Blackwell and the installed R610 stack uses the open kernel modules. The same GPU cannot be tested with the legacy proprietary kernel module.

## Operating System and Version

Arch Linux

## Kernel Release

`7.1.4-arch1-1` (stable release)

## Hardware: GPU

- NVIDIA GeForce RTX 5090 (GB202)
- PCI device ID: `10de:2b85`
- PCI subsystem ID: `1043:89e3`
- VBIOS: `98.02.2E.40.E0`
- GSP-RM: enabled
- Board power limit during the controlled runs: 600 W

## Describe the bug

On this RTX 5090, installing any finite maximum in NVIDIA's memory locked-clock range changes unrelated XBAR/SYS/shared-rail state even when the maximum is above the memory clock actually reached by the GPU.

The public symptom is a large, repeatable performance regression after `nvmlDeviceSetMemoryLockedClocks()` / `nvidia-smi -lmc`. Resetting the memory locked clocks restores normal behavior.

The decisive isolation is the maximum half of the range:

- a 15000 MHz minimum alone does not reproduce the regression;
- a 15000 MHz maximum alone does;
- a non-binding 16000 MHz maximum also does, while actual MCLK remains approximately 15001 MHz;
- XBAR collapses from approximately 2356 MHz to approximately 1493 MHz and SYS from approximately 2332 MHz to approximately 1500 MHz;
- no Xid, thermal slowdown, hardware slowdown, power-brake slowdown or software-thermal slowdown occurs.

This is not simply a conventional power-sharing effect. In the path-traced workload, board power falls by about 146 W and remains far below the unchanged 600 W limit while performance falls by about 15.5%. In FurMark, the same low-XBAR state makes the reported core clock rise, while measured rendered throughput falls by about 32%. It can therefore also produce false overclock-stability conclusions if only reported GPU clock is observed.

## Public reproduction

1. Reset memory locked clocks:

   ```bash
   sudo nvidia-smi --reset-memory-clocks
   ```

2. Run a repeatable GPU benchmark and record benchmark throughput plus GPU, memory, XBAR/SYS (if available), voltage and board-power telemetry.
3. Install a memory locked-clock range whose maximum is above the MCLK actually reached by the workload. On this card with a `+2000 MHz` memory offset, actual MCLK is approximately 15001 MHz, so the following maximum is non-binding:

   ```bash
   sudo nvidia-smi --lock-memory-clocks=15000,16000
   ```

4. Run the identical benchmark again.
5. Reset the range:

   ```bash
   sudo nvidia-smi --reset-memory-clocks
   ```

The independent report linked below used `nvidia-smi -lmc 810,16001` on another RTX 5090 and observed the same approximately 2500-2600 MHz core ceiling; `nvidia-smi -rmc` restored the normal state.

The controlled measurements below used the exported NVML control directly so that the minimum and maximum records could also be isolated independently. LACT was used for the ordinary paired-range A/B; it submits the same NVIDIA NVML API and is not suspected to be the source of the behavior.

## Controlled Cyberpunk 2077 result

All runs used Cyberpunk 2077 2.31, its built-in benchmark, 6144x3456, Path Tracing, the same 127-point GPU V/F curve, the same `+2000 MHz` memory offset, and the same 600 W board limit.

| Request | Avg FPS | GPU MHz | 1 s board W | Actual MCLK MHz | XBAR MHz | SYS MHz | Observed shared branch voltage | Normalized branch workload | Estimated branch power |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| MIN only, 15000 | 11.7864 | 2893.7 | 560.6 | 15001 | 2356.0 | 2332.4 | 967.2 mV | 257.3 | 188.2 W |
| MAX only, 14000 | 9.6948 | 2778.8 | 406.7 | 15001 | 1440.0 | 1238.7 | 870.0 mV | 372.3 | 281.1 W |
| MAX only, 15000 | 9.9580 | 2774.7 | 414.2 | 15001 | 1493.6 | 1501.0 | 870.0 mV | 369.2 | 275.1 W |
| MAX only, 16000 | 9.8533 | 2787.1 | 413.7 | 15001 | 1492.7 | 1500.0 | 870.0 mV | 356.5 | 278.4 W |

MAX-only 15000 versus MIN-only 15000 changes:

- average FPS: -15.51%;
- average GPU clock: -4.11%;
- one-second average board power: -26.11%;
- XBAR: -36.60%;
- observed shared-branch voltage: -10.05%;
- normalized branch workload: +43.49%;
- estimated branch power: +46.17%.

The 16000 MHz result is the important counterexample to an ordinary frequency cap: physical MCLK remains approximately 15001 MHz, but merely having a finite, non-binding maximum produces almost the same XBAR/SYS, voltage, performance and power state.

An ordinary paired-range A/B, with the V/F curve and memory offset byte-identical between states, produced:

| State | Average FPS | Minimum FPS | Maximum FPS | GPU clock min/avg/max | GPU voltage min/avg/max | 1 s board power min/avg/max |
|---|---:|---:|---:|---:|---:|---:|
| Custom V/F, `+2000`, no memory lock | 11.8993 | 10.3161 | 13.9809 | 2827 / 2888.1 / 2932 MHz | 945 / 970.6 / 990 mV | 505.8 / 556.7 / 590.8 W |
| Same settings, memory locked at `15000/15000` | 9.9443 | 8.9323 | 11.3875 | 2715 / 2770.0 / 2827 MHz | 905 / 916.8 / 935 mV | 396.7 / 414.6 / 438.3 W |

Adding only the paired memory lock reduced average FPS by 16.43% and average board power by 142.1 W. Independent 50 ms telemetry showed 97.6% average GPU utilization unlocked and 99.2% locked, so this was not caused by the workload becoming CPU-bound.

## FurMark Vulkan throughput counterexample

A separate 3840x2160 Vulkan FurMark A/B tested whether the low-XBAR state itself is causal. The benchmark settings, MCLK (15001 MHz) and GPU configuration were unchanged.

| State | Score | FPS min/avg/max | Loaded GPU MHz | Instant board W |
|---|---:|---:|---:|---:|
| No temporary clock limit | 2548 | 250 / 256 / 263 | approximately 2588 | approximately 601 |
| XBAR maximum 1493 MHz | 1725 | 171 / 173 / 177 | approximately 2952 | approximately 566 |

The low-XBAR state reduced average rendered FPS by 32.42% even though the reported GPU clock increased by roughly 364 MHz. This is why the issue is more serious than a simple lower boost clock: reported clock can move in the opposite direction from actual useful work.

Under the same FurMark load, a non-binding MCLK maximum and a direct XBAR maximum entered the same downstream controller state to measurement precision:

| State | Observed shared-branch MHz | Voltage | Normalized workload | Estimated branch power | DG0 target |
|---|---:|---:|---:|---:|---:|
| MCLK MAX 16000 | 1498.2 | 870.0 mV | 526.2 | 234.1 W | 3018.9 MHz |
| XBAR MAX 1493 | 1492.3 | 870.0 mV | 522.4 | 233.8 W | 3021.8 MHz |

This establishes that the MCLK maximum is sufficient to impose the low-XBAR/shared-rail state, and that the low-XBAR state is sufficient to reproduce the abnormal estimator/throughput behavior.

## Observed controller chain

Read-only power-policy and clock-topology telemetry is consistent with the following sequence:

```text
finite MCLK maximum
  -> XBAR/SYS/shared-rail range constraint
  -> observed shared branch falls to about 870 mV and 1.44-1.49 GHz
  -> workload normalization rises because it is normalized against that low state
  -> the candidate evaluator applies the larger normalized workload at a much
     higher candidate frequency/voltage
  -> estimated branch power rises despite actual board power falling
  -> WORKLOAD_COMBINED_2X changes the GPC target
```

For MAX-only 15000 in Cyberpunk:

```text
observed shared branch:  1493.6 MHz / 870.0 mV
candidate branch state: 2553.3 MHz / 1091.2 mV
```

The active clock topology remains unchanged and contains bidirectional shared-voltage-rail relationships between MCLK and XBAR and between MCLK and SYS. This looks like unintended cross-domain coupling or incorrect handling of a non-binding finite endpoint, rather than a user-requested XBAR cap.

## Expected behavior

A finite memory maximum that is above the memory clock actually reached by the GPU should not silently impose a much lower XBAR/SYS/shared-rail state, change an unrelated performance model, leave substantial board-power headroom unused, or make reported GPU clock diverge from rendered throughput.

If this behavior is intentional, the NVML and `nvidia-smi` documentation should state that a memory locked-clock range can constrain XBAR/SYS and globally alter Blackwell's performance estimator even when the maximum is non-binding.

## Independent reports and related measurements

- Independent RTX 5090 reproduction using `nvidia-smi -lmc 810,16001`; core boost falls to approximately 2500-2600 MHz and `nvidia-smi -rmc` restores it: https://www.reddit.com/r/techsupport/comments/1ml5pz1/im_looking_for_a_way_to_increase_the_5090s/
- RTX 5090 VRAM-OC/latency report; the author later found a reproducible 1% low correlation and noted the effect below the board power limit: https://www.reddit.com/r/overclocking/comments/1kxt2mj/vram_overclocking_and_latency_problems_on_rtx_5090/
- RTX 5090 core-versus-memory OC discussion with multiple users observing core-clock/power interaction: https://www.reddit.com/r/overclocking/comments/1jyjmqo/5090_uvoc_memory_or_core_which_to_prioritize/
- RTX 5090 XBAR measurements across VBIOSes and core-frequency ranges: https://www.hardwareluxx.de/community/threads/offizieller-nvidia-rtx-5090-overclocking-und-modding-thread.1363289/page-142
- LACT-side controlled A/B and raw-artifact inventory: https://github.com/ilya-zlobintsev/LACT/issues/1128

These community links are corroboration only. The causal minimum/maximum isolation, non-binding-maximum test and direct XBAR equivalence above were measured on the system described in this report.

## Additional information

A fresh `nvidia-bug-report.sh --safe-mode` archive was collected on driver 610.43.03. Complete benchmark summaries, per-sample telemetry, read-only power-policy captures and the exact configurations are available if NVIDIA wants the raw artifacts.
