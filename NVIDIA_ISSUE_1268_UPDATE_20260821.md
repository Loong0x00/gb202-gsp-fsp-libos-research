## Update: reproduced on 610.57.04 with a rising V/F tail and two RT workloads

I reproduced the same final-clock/voltage mismatch on a newer stack while
removing a potential confound in the original report: the active GPC V/F tail
now rises monotonically instead of remaining flat.

### Current system

- GPU: GeForce RTX 5090 / GB202 (`10de:2b85`, subsystem `1043:89e3`)
- Open kernel/GSP driver: `610.57.04`
- VBIOS: `98.02.2E.80.50`
- Configured board-power limit: 595 W
- Cyberpunk 2077 2.31 built-in benchmark, 6144 x 3456
- no upscaling, frame generation or dynamic resolution

The relevant runtime-read-back V/F points were:

```text
935 mV  -> 3000 MHz
1010 mV -> 3105 MHz
1050 mV -> 3150 MHz
>=1050 mV remains at 3150 MHz
```

The driver reported all 127 points after applying the curve. No clock lock was
installed.

### Result

| Workload | Avg FPS | Realized/reported GPC avg | NVVDD/reported voltage avg | Board power avg | policy-0 DG0 avg | PERF 0x43 avg | DG0 - realized |
|---|---:|---:|---:|---:|---:|---:|---:|
| Path Tracing | 11.3408 | 3028.1 MHz | 1009.8 mV | 572.0 W | 3097.7 MHz | 3099.5 MHz | +69.6 MHz |
| RT Ultra, no Path Tracing | 21.8783 | 2960.5 MHz | 985.7 mV | 559.5 W | 3085.7 MHz | 3088.7 MHz | +125.2 MHz |

The Path Tracing medians provide the cleanest single-bin comparison:

```text
NVVDD/reported voltage median: 1010 mV
active V/F point at 1010 mV:   3105 MHz
WORKLOAD_COMBINED_2X DG0:      3105 MHz
realized/reported GPC clock:   3030 MHz
```

Thus the rising V/F curve and the power-policy search both select the 3105 MHz
state, and the voltage is consistent with that state, but the realized clock
settles one or more stages later at about 3030 MHz. The unused voltage is not
explained by a flat user curve.

The RT-setting A/B also changed the policy model's internal workload and
candidate state while preserving the downstream mismatch:

```text
                              Path Tracing     RT Ultra
model workload branch 0/1:    285.3 / 251.7    311.7 / 269.4
estimated tuple MHz 0/1:      2838 / 2630      2761 / 2571
DG0 median:                   3105             3082 MHz
realized GPC median:          3030             2955 MHz
```

This does not by itself prove that an explicit RT-mode enum is an input; the
change may be mediated by activity counters, V/F residency, or workload-regime
selection. It does show that the policy model changes with the RT workload,
while a separate post-DG0 stage removes substantially more clock than the
ordinary physical clock-grid quantization can explain.

During both scene windows:

- the conventional active PERF-limit list was empty;
- software power capping was active;
- no hardware slowdown, thermal slowdown, power-brake slowdown, or software
  thermal slowdown was reported;
- no Xid, GSP reset-required condition, or PCIe AER error occurred.

### Revised requested fix

Please invalidate and re-evaluate the matching voltage request whenever any
downstream clock client, projection, filter, or finalizer materially lowers the
granted GPC clock after the power-policy result. A generation/version identifier
shared by the final clock grant and its voltage request would prevent a voltage
request computed for an older/higher candidate from surviving a later clock
grant.

Conceptually:

```text
policy candidate / DG0
  -> all downstream clock-client arbitration
  -> final granted GPC clock
  -> V/F re-evaluation for that exact grant generation
  -> rail request update
```

The high-rate NVML re-commit from the original report remains only a diagnostic
causal probe, not a proposed userspace fix. Raw per-sample policy, NVML, rail,
and clock telemetry for both runs is available if useful.
