# DG0 to V/F feedback bridge: PT experiment (2026-07-29)

## Scope

GPU and software state:

- NVIDIA GeForce RTX 5090, ASUS Astral VBIOS `98.02.2E.40.E0`
- NVIDIA driver `610.43.03`
- Cyberpunk 2077 `2.31`
- 6144x3456, DLAA, frame generation disabled, path tracing enabled
- active LACT config SHA-256:
  `72c89a17b3f2467e474e38173992467f2622fecfa29c94fffe2e86ada9c34b9f`

The experiment tested whether the PMU power policy's downstream GPC result
(`WORKLOAD_COMBINED_2X` policy-0 `DG0`, exported as PERF limit `0x43`) can be
fed back into the V/F/clock range through client GPC limits.

## Max-only transaction: accepted but not enforced

Artifact paths:

- benchmark: `benchmark_logs/cp2077_6k_20260729_092741/`
- bridge log: `benchmark_logs/dg0-vf-bridge-pt-20260729_092741.log`

The first bridge wrote only `0x4c CLIENT_STRICT_GPC_MAX`.  SET succeeded and
the configured value read back.  A later isolated check also showed that a
max-only transaction can report the requested value in both configured and
effective fields.

During the actual PT scene, however, the requested cap was approximately
2670/2778/2880 MHz min/mean/max while the reported graphics clock was
2835/2905/2940 MHz.  The clock therefore did not obey this transaction.

Results:

- average/minimum/maximum FPS: 11.7420 / 10.1708 / 13.5021
- graphics clock: 2905.0 MHz average
- visible GPU voltage: 977.8 mV average
- one-second board power: 546.3 W average

This run is effectively a negative control.  A successful RM status and
configured/effective readback is not sufficient evidence that a max-only
entry reached the active hardware arbitration path.

## Paired max/min transaction: hardware path proven

Before the second PT run, an isolated three-second test submitted both
`0x4c CLIENT_STRICT_GPC_MAX` and `0x4d CLIENT_STRICT_GPC_MIN` at 2700 MHz in
one transaction.  The reported hardware clock moved to 2692 MHz.  After the
entries were cleared, the idle clock returned to 225 MHz and both entries
read invalid.  This establishes a working runtime actuation path.

Artifact paths:

- benchmark: `benchmark_logs/cp2077_6k_20260729_093900/`
- bridge log: `benchmark_logs/dg0-vf-pair-bridge-pt-20260729_093859.log`

PT results:

- average/minimum/maximum FPS: 11.5106 / 9.9853 / 13.4908
- graphics clock: 2737/2816.7/2865 MHz min/mean/max
- visible GPU voltage: 885/910.4/925 mV min/mean/max
- one-second board power: 438.4/487.2/531.3 W min/mean/max
- GPU temperature: 61/64.3/69 C min/mean/max
- hotspot temperature: 72/77.7/86 C min/mean/max
- no Xid, GPU-lost, reset-required, thermal slowdown, or power-brake event

The paired bridge's scene cap was approximately 2790/2862/2910 MHz
min/mean/max.  The physical clock followed it, unlike the max-only run.

At the same time, the PMU itself still published much more headroom:

- independent `0x43`: 2987.7 MHz average
- policy-0 `DG0`: 2984.2 MHz average
- bridge pair target: approximately 2862 MHz average
- actual graphics clock: 2816.7 MHz average

The feedback transport is therefore closed, but the first controller is too
conservative.  Its `fast-down` rule reacts to every transient DG0 dip, while
its `slow-up` rule recovers only 15 MHz after one second of headroom.  During
the scene it performed five fast-down events and only 21 slow-up events, so
short low samples ratcheted the target down despite a roughly 2.98 GHz mean
PMU target.

## NVML max-only feedback: V/F recomputation without a forced minimum

The bridge was then changed to call NVIDIA's exported API directly:

```text
nvmlDeviceSetGpuLockedClocks(device, 0, DG0_MHz)
```

Unlike the paired raw-RM test, this leaves the minimum at zero.  It therefore
does not force the core to the requested clock.  It only continuously gives
the normal clock/V/F path the PMU's latest maximum so that rail-0 voltage
client 1 can be recomputed.

Artifact paths:

- benchmark: `benchmark_logs/cp2077_6k_20260729_095523/`
- bridge log: `benchmark_logs/dg0-vf-nvml-max-pt-20260729_095523.log`

PT results:

- average/minimum/maximum FPS: 11.7763 / 10.1654 / 14.0379
- graphics clock: 2812/2892.5/2940 MHz min/mean/max
- visible GPU voltage: 915/962.2/1010 mV min/mean/max
- one-second board power: 498.6/539.7/583.7 W min/mean/max
- GPU temperature: 61/67.0/72 C min/mean/max
- hotspot temperature: 76/82.9/91 C min/mean/max
- no Xid, GPU-lost, reset-required, thermal slowdown, or power-brake event

Within the scene window:

- PMU `0x43/DG0`: 2968.1 MHz average
- submitted NVML maximum: 2964.7 MHz average
- reported physical graphics clock: 2892.5 MHz average
- power-model observed branch-0 frequency: 2884.9 MHz average

The transport therefore did exactly what was requested: it passed the PMU
power controller's published result back through the normal max-only V/F
control path without setting a minimum clock.  Relative to the existing
ten-round baseline, this single run retained essentially the same throughput
(11.7763 versus 11.7911 FPS) while reducing average visible voltage by about
10.9 mV and average board power by about 15.6 W.

The remaining mismatch is now precise.  The PMU publishes a roughly 2.97 GHz
raw ceiling, while the realized/observed core is roughly 2.89 GHz.  Feeding
the raw ceiling back makes V/F select voltage for approximately 2.97 GHz, so
it cannot reach the approximately 0.92 V state associated with the lower
realized frequency.  Directly feeding the realized clock would need either a
stable translation that avoids a downward self-locking loop, or a direct
voltage-client-1 reevaluation primitive that does not also impose a clock
maximum.  No public primitive of the latter form has yet been found.

This first implementation also issued 942 NVML SET calls during the 82.54 s
scene because the raw target moved frequently.  A production controller
should coalesce identical 15 MHz bins and rate-limit updates; this call count
is not needed to establish the causal result.

## Comparison with existing controls

Previously validated curve, ten PT rounds:

- 11.7911 FPS
- 2897.57 MHz
- 973.07 mV
- 555.28 W

Previously tested manual low-voltage plateau, four completed PT rounds:

- 11.9424 FPS
- 2897.13 MHz
- 920.65 mV
- 514.73 W

The NVML max-only feedback run is the relevant result: it made the normal V/F
path reevaluate voltage without forcing a minimum clock, retained essentially
the baseline throughput, and reduced visible voltage and board power.  The
older paired run remains above only as a transport/path experiment; it is not
the intended controller.

## Next discriminating controller

Do not restore the paired max/min controller.  The tested max-only path is the
correct functional bridge.  Its immediate engineering cleanup is to coalesce
updates: keep the minimum at zero, quantize DG0 to 15 MHz bins, and send a new
NVML maximum only after the target has remained stable for roughly 100-200 ms
or moved by at least two bins.  This reduces the 942 SET calls without changing
the causal experiment.

The remaining research question is not transport but target semantics.  Raw
DG0 averaged about 2.97 GHz while the realized core averaged about 2.89 GHz.
Getting the voltage appropriate to the realized frequency without imposing a
clock floor requires either:

1. a measured, stable DG0-to-realized-frequency translation that cannot form a
   downward self-locking loop; or
2. the internal rail-0 voltage-client-1 reevaluation primitive, if one exists,
   without any accompanying clock bound.

Feeding the instantaneous realized clock directly into the maximum is not a
safe next controller: its own cap can lower the next observation and ratchet
the loop downward.  The current result already proves that stage feedback is
effective; it does not yet identify a clock-independent voltage request ABI.

## Cleanup state

- both client GPC limit entries were cleared;
- the bridge reported successful restoration;
- the LACT config hash remained unchanged;
- no new NVIDIA Xid was present in the tested kernel-log interval.
