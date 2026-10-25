## NVIDIA Open GPU Kernel Modules Version

`610.43.03` (`nvidia-open-dkms 610.43.03-3`)

## Proprietary-driver comparison

Not applicable on this hardware. The tested GPU is Blackwell and uses the open kernel modules with GSP-RM enabled.

## Operating System and Version

Arch Linux

## Kernel Release

`7.1.4-arch1-1` during the controlled measurements

## Hardware: GPU

- NVIDIA GeForce RTX 5090 (GB202)
- PCI device ID: `10de:2b85`
- VBIOS: `98.02.2E.40.E0`
- GSP-RM: enabled
- Configured board-power limit: 600 W

## Feature request

Please re-evaluate the voltage request after the final effective GPC-clock arbitration result changes, or expose a supported API that asks the normal V/F path to re-evaluate voltage for the current effective clock without imposing a minimum or maximum clock lock.

On this RTX 5090, read-only policy telemetry shows that the active `WORKLOAD_COMBINED_2X` policy can publish a GPC candidate/ceiling around 2.97 GHz while the realized graphics clock is around 2.89 GHz. The observed voltage appears to remain closer to the earlier/higher clock request instead of being fully recomputed for the final realized clock.

A diagnostic max-only feedback experiment makes this visible. Re-submitting the PMU's current GPC result through NVIDIA's exported API as:

```c
nvmlDeviceSetGpuLockedClocks(device, 0, pmu_dg0_mhz);
```

leaves the minimum open, does not force the GPU to the submitted maximum, but causes the normal clock/V/F path to re-evaluate. In the same Cyberpunk 2077 path-tracing workload, this retained essentially the same throughput while reducing reported voltage and board power.

## Controlled results

Workload and configuration:

- Cyberpunk 2077 2.31 built-in benchmark
- 6144 x 3456
- Path Tracing enabled
- DLAA
- Frame Generation disabled
- identical 127-point V/F curve, memory offset, power limit and game settings

| State | Average FPS | GPU clock average | GPU voltage average | 1 s board power average |
|---|---:|---:|---:|---:|
| Existing configuration, 10-run baseline | 11.7911 | 2897.6 MHz | 973.1 mV | 555.3 W |
| PMU-result max-only feedback, one diagnostic run | 11.7763 | 2892.5 MHz | 962.2 mV | 539.7 W |

The measured differences were:

- average FPS: -0.13%, within ordinary run-to-run variation;
- graphics clock: -5.1 MHz;
- reported voltage: -10.9 mV;
- one-second average board power: -15.6 W.

During the diagnostic scene:

- PMU PERF limit `0x43` / policy-0 DG0: approximately 2968 MHz average;
- submitted max-only value: approximately 2965 MHz average;
- reported physical graphics clock: approximately 2893 MHz average;
- power-model observed branch-0 frequency: approximately 2885 MHz average.

No Xid, GPU-lost, reset-required, thermal slowdown, hardware slowdown or power-brake event occurred. The locked-clock range was reset successfully after the run.

## Why an internal or event-driven implementation is requested

The diagnostic bridge polled the policy result and issued 942 NVML SET calls during an 82.5-second scene because the candidate moves frequently. This is not proposed as a userspace solution.

A follow-up controller that required a 30 MHz change to remain in the same 15 MHz bin for 150 ms submitted only four updates, but largely lost the voltage/power reduction. That run measured 11.7088 FPS, 2907.5 MHz, 978.3 mV and 550.1 W. The policy output moves too often for exact-bin debouncing, while high-rate userspace polling is undesirable.

The desired internal sequence appears conceptually simpler:

```text
final granted/effective GPC frequency
  -> normal V/F lookup
  -> updated rail voltage request
```

This would avoid an additional userspace feedback controller and would let the existing firmware retain responsibility for stability, slew limits and arbitration.

## Expected behavior / requested API

Could NVIDIA consider either of the following?

1. After all power/performance constraints produce the final effective GPC target, re-evaluate the associated voltage request when the final target is materially below the frequency used for the current request.
2. Expose a supported API to request V/F re-evaluation for the current effective clock, without installing a locked-clock minimum or maximum.

If retaining the higher voltage is intentional for transient-response or stability reasons, documentation of that behavior and any supported energy-efficiency control would also be helpful.

## Related controller reports

These existing issues concern a different but adjacent Blackwell clock/power-arbitration interaction:

- #1265 — memory locked-clock request reduces RT performance and leaves substantial board-power headroom unused
- #1266 — a finite memory-clock maximum constrains XBAR/SYS and changes performance

Complete benchmark summaries, per-sample telemetry, bridge logs and read-only policy-status captures are available if useful.
