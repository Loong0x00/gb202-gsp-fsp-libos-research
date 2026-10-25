# NVIDIA performance-control lineage: Fermi to Blackwell

Date: 2026-07-29

## Question

Is the RTX 5090 behavior in which a GPC V/F request selects a relatively high
NVVDD target before a separate power governor reduces the realized GPCCLK a
new Blackwell/GSP design, or inherited architecture?

## Fixed artifacts

The following official NVIDIA Linux driver archives were downloaded from
`https://us.download.nvidia.com/XFree86/Linux-x86_64/<version>/` and extracted
without installation:

| Era | Version | Archive SHA-256 |
|---|---|---|
| Fermi | 260.19.44 | `8526267407d71b1257e43abc2b98e588c8d271e30584a754b8b8ef426cc69c64` |
| late Fermi / pre-Kepler development | 285.05.09 | `7159a1f7e898b50dd49ea2273ac6facb870546ad5496bf70c6fbe1642d2c4970` |
| Kepler era | 295.59 | `4b1d96389abd2b804ad470c5189142a02ee4c82c1ac56cea37ecb45e8051313e` |
| Kepler era | 304.64 | `b3c3bb7f136ccd978c9c5a511a02199ec2498c4243baae19ac68e5d905ca5340` |
| Maxwell/M40 era | 367.57 | `a1615db29f1377817b610cca997e0339753ee9d58b28e1618b892691df3a8851` |

The modern comparison image is the locally fixed R570/MODS binary already
used for the GB202 voltage-arbiter analysis.

## Static timeline

The observations below are exact embedded identifiers in the proprietary RM
objects.  Their absence alone is not proof that no equivalent binary logic
existed, but their appearance gives a lower bound on the named architecture.

| Identifier or subsystem marker | 260.19.44 | 285.05.09 | 295.59 | 304.64 | 367.57 |
|---|---:|---:|---:|---:|---:|
| `RmPstate20` | no | yes | yes | yes | yes |
| `VDT_OVERVOLTAGE` | no | no | yes | yes | renamed/expanded |
| `PMU_DOM_GRP_0/1` | no | no | yes | yes | yes |
| GPC-specific strict clients | no | no | no | no | yes |
| `GPU_STATE_LOAD_BOOST_DOM_GRP_0/1` | no | no | no | no | yes |

The 295.59/304.64 client-name block already separates sources such as:

```text
VDT_OVERVOLTAGE
VDT_RELIABILITY
POWERMIZER_HARD
CLIENT_HARD
THERMAL
SYSPERF
AUX_PWR_STATE
PWR_SUPPLY_CAPACITY
PMU_DOM_GRP_0
PMU_DOM_GRP_1
SW_BATTPOWER
EXT_PERF_CONTROL
MXM_ACPOWER
AUX_POWER
MODS_RULES
```

By 367.57 the same family has expanded to include explicit GPC min/max
clients, application clocks, rated-TDP limits, SLI GPU Boost domain-group
clients, VMIN/reliability clients, and GPU-state-load Boost domain groups.

The R570/MODS image still supports PCI ID `0x17fd` (Tesla M40), contains a
GM200-specific clock schematic, and also contains the modern generic
`VOLTAGE_REQUEST`, voltage-client arbitration, `PROG_VOLT` performance-change
step, and independent `PWR_POLICY` framework.  This is strong evidence of
continuous evolution rather than a clean Blackwell rewrite.

## Official behavior boundary

NVIDIA's management API describes application clocks as requested clocks and
explicitly states that the actual clock may be reduced by an overspec event
such as power, thermal, or external hardware braking.  M40's board
specification separately describes an onboard current/voltage monitor and a
typical power-capping response time of about 100 ms.  These are observable
interfaces for a target-clock layer followed by an independent power-capping
layer.

## Runtime experiment on a real mobile Kepler

### Fixed system and display boundary

- Dell Precision M4800, BIOS A26, Ubuntu 24.04.4, kernel 6.8.0-110
- Quadro K2100M (GK106GLM, PCI ID `10de:11fc`), VBIOS `80.06.7d.00.06`
- NVIDIA server driver `470.256.02`
- the Intel display device was disabled in firmware; the internal 1920x1080
  eDP panel was directly attached to the K2100M

The ordinary display path was unusable with this driver. Loading it with DRM
KMS enabled caused `Display engine push buffer channel allocation failed:
0x65 (NV_ERR_TIMEOUT)`, left eDP disconnected, blocked Xorg in uninterruptible
sleep, and made `nvidia-smi` hang. This matches NVIDIA's known post-455
display-engine regression rather than an Optimus render/display handoff.

For the control experiment, DRM KMS and the physical display were disabled.
A separate X server was started with `UseDisplayDevice=None` solely to expose
NV-CONTROL. In this configuration CUDA, NVML, and NV-CONTROL all worked and
no display-engine channel was allocated.

### Explicit policy layers

`GPUPerfModes` exposed three firmware-defined layers:

| Layer | Graphics range | Memory clock | Editable |
|---|---:|---:|---|
| perf 0 | 135--405 MHz | 405 MHz | no |
| perf 1 | 135--666 MHz | 810 MHz | no |
| perf 2 | 135--666 MHz | 1504 MHz | graphics and memory |

Changing only `GPUPowerMizerMode` while idle selected four observably
different states:

| Mode | Pstate | Graphics | Memory |
|---:|---|---:|---:|
| 0 | P8 | 135 MHz | 405 MHz |
| 1 | P0 | 666 MHz | 1504 MHz |
| 2 | P5 | 536 MHz | 810 MHz |
| 3 | P0 | 666 MHz | 1504 MHz |

Under the same FP32 FMA load, all four modes converged to P0 at 666/1504 MHz
within one approximately 140 ms `nvidia-smi` sampling interval. Every
10-second segment had 74 or 75 steady P0 samples and about 98% mean reported
utilization. Transition samples included `P8 + 666/1504` and
`P5 + 666/1504`, combinations absent from the static table. Because NVML
queries these fields separately, this proves non-atomic observable state
transition/telemetry, not by itself separate hardware controllers.

The highest performance layer's two clock domains were independently
controllable:

- graphics offset `-100` produced 562/1504 MHz both idle and at 100% load;
- after reset, memory-transfer offset `-1000 MT/s` produced 666/1004 MHz while
  idle;
- both commands were accepted inside the ranges advertised by NV-CONTROL.

The second configuration exposed a validation/execution failure. Starting
the same CUDA kernel at 666/1004 caused the kernel to remain outstanding for
more than a minute; `nvidia-smi` and the NV-CONTROL request to restore the
memory offset then timed out while CPU and SSH remained responsive. No Xid
was logged before reboot. A normal reboot eventually cleared the condition,
and the offsets returned to zero. This configuration was not retried.

The K2100M exposes neither board power nor electrical rail voltage through
NVML/NV-CONTROL, and it rejects application clocks, locked clocks, memory
locks, and power-limit controls. Therefore this experiment cannot reproduce
the M40's controlled downstream power-cap test. It does establish that by
mobile Kepler the architecture already had a policy selector, discrete
performance layers, independently editable graphics/memory domains, and
non-atomic transitions between requested policy state and reported clocks.

Runtime files are under `k2100m_history/`. The four raw mode traces are
`k2100m_powermizer/mode_0.csv` through `mode_3.csv`; the load source and the
NoScanout X configuration are retained beside them.

## Runtime experiment on a real Tesla M40

### Fixed system

- Dell PowerEdge C4130, Ubuntu 22.04.5, kernel 5.15.0-181-generic
- Tesla M40 24 GB, PCI ID `10de:17fd`, VBIOS `84.00.56.00.03`
- NVIDIA server driver `580.173.02`
- requested application clocks fixed at memory 3004 MHz / graphics 1114 MHz
- power limits alternated in one continuous process between 250 W and 180 W
- workload: repeated 8192-square FP32 cuBLAS SGEMM plus asynchronous PCIe DMA
- synchronized sampling interval: 50 ms

The load, target clocks, process, and sampling path were held constant while
only the software power limit changed.  The first 0.75 s after every limit
transition and the last 0.25 s before the next transition were excluded from
the aggregate below.

| Power-limit segments | Samples | Requested graphics clock | Pstate | Realized graphics clock | SW-power-cap samples | Mean reported power |
|---|---:|---:|---:|---|---:|---:|
| 250 W | 516 | 1114 MHz in all samples | P0 in all samples | 1113 MHz in all 516 samples | 0 | 178.050 W |
| 180 W | 362 | 1114 MHz in all samples | P0 in all samples | 1113 MHz: 193; 1088 MHz: 169 | 144 | 174.231 W |

This is a direct runtime proof that Maxwell has a downstream power limiter
which can reduce realized GPCCLK without changing the requested application
clock or leaving P0.

### Voltage observation and its boundary

Neither `nvidia-smi -q -d VOLTAGE`, NV-CONTROL
`GPUCurrentCoreVoltage`, nor LACT's undocumented NvAPI voltage query exposes
an electrical rail-voltage reading on this M40.  Their respective results are
absent, zero, and `NVAPI_NOT_SUPPORTED`.

`NvAPI_GPU_GetPstates20`, however, works and reports the current software P0
V/F description:

- graphics range 532--1114 MHz;
- voltage range approximately 0.82--1.106 V (the low endpoint moves in VID
  steps during the run);
- an editable P0 base-voltage setting near 1.0 V.

In the alternating run, the P0 base-voltage setting moved slowly through
1005.972, 999.728, 993.484, and 987.239 mV in approximately 6.24 mV steps.
Those movements did not follow the 250/180 W transitions.  Most importantly,
adjacent steady 250 W and 180 W segments both reported 993.484 mV, while the
250 W segment stayed at 1113 MHz and the 180 W segment repeatedly dropped to
1088 MHz.

This value is an RM/NvAPI Pstate setting, not a direct oscilloscope or VRM
telemetry reading.  It therefore cannot prove the instantaneous physical
NVVDD waveform.  It does prove that the power-cap clock action is not merely
implemented by replacing the visible P0 V/F description with a lower fixed
point.

### Rejected first load

The initial hand-written FP32 FMA kernel held 100% reported utilization and
1113 MHz but drew only about 132--135 W.  Because the M40's minimum permitted
software limit is 180 W, that workload could not distinguish the two
conditions.  This is retained as a useful counterexample: 100% utilization is
not sufficient evidence that a workload stresses the power governor.

### Runtime artifacts

All files are under `m40_history/` beside this note.

| File | Purpose | SHA-256 |
|---|---|---|
| `nvapi_voltage_probe.py` | confirms the direct voltage query is unsupported | `9e4891f6a7ae226f7ea2a9b9b4f6f5d7193c68f6a59d4e417be3957a13f01512` |
| `nvapi_pstates20_probe.c` | dumps the M40 Pstate20 V/F description | `304384cbfaed4f97f7f208a6e7b01dc3584d21c7da03d356f1792959bade0481` |
| `m40_nvapi_nvml_sampler.py` | synchronized NVML clock/power/reason and Pstate20 sampler | `2b27a6f598798fa1fde17dba26cde4c93eeb7afa96cbfdd0d48e10d8408b684c` |
| `cuda_fma_burn.c` | rejected pure-FMA discriminant | `94bcb609c5690eed457fd81a7c29d7dd6ddae34c8890e7b49a311ca16ea33598` |
| `cublas_sgemm_burn.c` | discriminating SGEMM plus DMA workload | `7c78c243d1d25169f256965b28d03d6e9e399f51e071ac42fa667900ef259766` |
| `m40_alternating_250_180w.csv` | 50 ms synchronized alternating-limit telemetry | `9e9e6b850354dcf2cea2a2e9c1adb259e754a3dbcfa70a62d70e66325c987c79` |
| `m40_alternating_250_180w_markers.csv` | exact limit-transition timestamps | `653ef3bf00c5bf6c2c2ab282095ee0fcd41ca6f2d14fb2a72c3e3f4b844f7dbb` |

## Current conclusion

**PROVED AT RUNTIME:** Maxwell has an architectural split between requested
application clocks/P0 V/F state and a later software-power clock limiter.
The real M40 kept a 1114 MHz request and P0 while the 180 W limiter reduced
realized GPCCLK to 1088 MHz.

**PROVED AT RUNTIME ON MOBILE KEPLER:** PowerMizer policy selection, discrete
performance-layer selection, and independently editable graphics/memory
clock domains already existed on GK106GLM. A driver-accepted memory-domain
configuration could be read back successfully yet wedge subsequent GPU work
and management requests, demonstrating that configuration validation and the
runtime execution path were not one indivisible mechanism.

**PROVED STATICALLY:** named multi-client Pstate/PMU domain-group machinery
appears in the late-Fermi/Kepler driver lineage and becomes substantially more
explicit by Maxwell.  The modern R570 code retains the M40 paths alongside
the newer voltage-request and power-policy frameworks.

**STRONG INFERENCE:** the RTX 5090's non-converged steady state is facilitated
by that inherited separation: a GPC V/F request can remain high while a later
power governor reduces realized GPCCLK.  Blackwell/GSP enlarged an inherited
control architecture rather than introducing this separation from scratch.

**NOT PROVED:** the M40's instantaneous physical NVVDD under each 50 ms sample.
The public and undocumented management paths tested here do not expose its
electrical rail voltage.  The Pstate20 setting is sufficient to distinguish
the software control layers, but not to reconstruct regulator transients.
