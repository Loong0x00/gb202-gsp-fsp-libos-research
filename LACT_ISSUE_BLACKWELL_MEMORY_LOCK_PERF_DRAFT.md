# Suggestion: clarify NVIDIA memory locked-clock behavior on Blackwell

## Summary

This is a documentation/UX suggestion, not a LACT bug report. LACT appears to submit the requested NVIDIA locked-clock control correctly. The surprising behavior described below is most likely produced by NVIDIA's driver/firmware performance arbiter; the LACT-side suggestion is only to make that distinction and its possible performance impact clearer to users.

On an RTX 5090, setting an NVIDIA memory locked-clock range through LACT causes a large and reproducible performance regression in a path-traced workload. On the latest upstream `master` tested here, removing the locked-clock range while retaining the same `+2000 MHz` memory offset increased average FPS by 19.7% relative to the locked result (equivalently, enabling the lock reduced FPS by 16.4%), restored about 118 MHz of average GPU clock, and allowed the board to use about 142 W more average power.

This does not appear to be caused by the memory offset or the custom GPU V/F curve. The regression is triggered specifically by the paired NVIDIA memory locked-clock request.

Additional low-level isolation after the original A/B test identified the
maximum half of the range as the trigger. A strict DRAM minimum of 15000 MHz
alone retained 11.7864 FPS, approximately 2894 MHz GPU clock, 560.6 W
one-second-average board power, and approximately 2356 MHz XBAR. A strict DRAM
maximum of 15000 MHz alone reduced those values to 9.9580 FPS, approximately
2775 MHz, 414.2 W, and approximately 1494 MHz XBAR. Both cases reported the
same approximately 15001 MHz actual memory clock.

A non-binding 16000 MHz maximum reproduced the same regression while actual
memory remained at approximately 15001 MHz. This rules out the achieved memory
frequency as the cause and shows that the finite maximum-range state itself is
the trigger.

A separate direct sufficiency test compared that non-binding MCLK maximum with
a direct XBAR maximum under the same FurMark Vulkan load. `MCLK MAX = 16000
MHz` produced an observed branch-1 state of 1498.2 MHz / 870.0 mV, workload
526.2, estimated branch power 234.1 W, and DG0 target 3018.9 MHz. Directly
setting `XBAR MAX = 1493 MHz` produced 1492.3 MHz / 870.0 mV, workload 522.4,
estimated branch power 233.8 W, and DG0 target 3021.8 MHz. This demonstrates
that the finite MCLK maximum induces the same downstream controller state as a
direct XBAR ceiling; it is not merely correlated with the XBAR reduction.

The low-level behavior is probably in the NVIDIA driver/firmware rather than LACT itself. Since LACT exposes this underlying NVIDIA control, a short explanation that it is a strict global performance-arbiter constraint rather than a simple memory-clock target could help Blackwell users avoid an unexpected performance loss.

## Hardware and software

- GPU: NVIDIA GeForce RTX 5090
- PCI device ID: `10de:2b85`
- PCI subsystem ID: `1043:89e3`
- VBIOS: `98.02.2E.40.E0`
- NVIDIA driver: `610.43.03` (`nvidia-open-dkms 610.43.03-3`)
- GSP-RM: enabled
- LACT package used by the daemon: `lact-git r1198.b3efeb27-1`
- LACT upstream commit: `b3efeb273f7e0ed9b83bc37b24938f6b51fb555f`
- LACT version: `0.9.2`
- Kernel: `7.1.4-arch1-1`
- Distribution: Arch Linux
- Game: Cyberpunk 2077 2.31

The commit was the upstream `master` HEAD at test time (2026-07-28). It was independently cloned and built successfully before the benchmark:

```bash
git clone --depth=1 --branch master https://github.com/ilya-zlobintsev/LACT.git
git -C LACT rev-parse HEAD
# b3efeb273f7e0ed9b83bc37b24938f6b51fb555f

cd LACT
cargo fetch --locked
cargo build -p lact --frozen --release
```

The independently built tree and the installed `lact-git` package resolved to the same commit. `lactd` was restarted after each configuration change so the running daemon used the updated installation.

## Controlled experiment

Three states were tested. The 600 W limit, fan curve, game settings, driver, VBIOS, and benchmark procedure were kept identical. The stock state provides a baseline; the controlled causal comparison is State B versus State C, which differ only by the two memory locked-clock fields.

The following workload settings were kept identical:

- 600 W requested and enforced power limit
- the same fan curve
- Cyberpunk 2077 built-in benchmark
- 6144 x 3456 output resolution
- Path Tracing enabled
- no DLSS Frame Generation or Multi Frame Generation
- the same game configuration and 972-973 rendered benchmark frames

### State A: stock clock controls

No `gpu_vf_curve`, `mem_clock_offsets`, `min_memory_clock`, or `max_memory_clock` fields were present. The 600 W power cap and fan curve remained configured.

### State B: custom V/F curve and memory offset, without a memory lock

```yaml
power_cap: 600.0
mem_clock_offsets:
  0: 2000
  8: 2000
gpu_vf_curve:
  # The same 127 points used in State C
```

### State C: the same V/F curve and memory offset, with a memory lock

```yaml
power_cap: 600.0
min_memory_clock: 15000
max_memory_clock: 15000
mem_clock_offsets:
  0: 2000
  8: 2000
gpu_vf_curve:
  # Byte-for-byte identical to State B
```

LACT requires the minimum and maximum VRAM locked-clock values to be configured together. Keeping only one field causes LACT to reject the GPU configuration with:

```text
Min and max VRAM clock must be set together
```

Therefore, both locked-clock fields were removed for State B. The `+2000 MHz` offset and all 127 V/F points remained present. A parsed YAML comparison confirmed that States B and C were identical after removing only `min_memory_clock` and `max_memory_clock`.

For each state:

1. Install the selected LACT configuration.
2. Restart `lactd` and verify that it applies the configuration without an error.
3. Verify the 600 W power limit. For States B and C, verify approximately 15001 MHz memory clock under the configured state with `nvidia-smi`/LACT telemetry.
4. Launch the same Cyberpunk 2077 built-in benchmark.
5. Record GPU clock, voltage, VRAM use and one-second-average board power throughout the benchmark.
6. Independently sample NVIDIA's 50 ms telemetry and the read-only RM power-policy status.
7. Use the benchmark's own `benchmark-summary.json` for average, minimum and maximum FPS.
8. Check the kernel journal for Xid events and the NVIDIA slowdown counters for thermal or hardware throttling.

The table below contains the new latest-`master` runs. Earlier testing on commit `ab83c4c28189d5fbf55e995029162a453d02f733` reproduced the same direction and magnitude across one locked and two unlocked runs; those older numbers are not mixed into this table.

## Benchmark results

| State | Average FPS | Minimum FPS | Maximum FPS | GPU clock min/avg/max | GPU voltage min/avg/max | 1 s board power min/avg/max |
|---|---:|---:|---:|---:|---:|---:|
| A: stock clock controls | 11.5038 | 10.0939 | 13.3273 | 2722 / 2743.9 / 2767 MHz | 1010 / 1019.0 / 1025 mV | 517.5 / 571.3 / 599.9 W |
| B: custom V/F, `+2000`, no memory lock | 11.8993 | 10.3161 | 13.9809 | 2827 / 2888.1 / 2932 MHz | 945 / 970.6 / 990 mV | 505.8 / 556.7 / 590.8 W |
| C: same custom V/F and `+2000`, memory locked at 15000/15000 | 9.9443 | 8.9323 | 11.3875 | 2715 / 2770.0 / 2827 MHz | 905 / 916.8 / 935 mV | 396.7 / 414.6 / 438.3 W |

Relative to State B, adding only the paired memory lock in State C:

- reduced average FPS by 16.43%;
- reduced minimum FPS by 13.41% and maximum FPS by 18.55%;
- reduced average GPU clock by 118.1 MHz (4.09%);
- reduced average one-second board power by 142.1 W (25.53%).

The stock baseline is also informative: State B was 3.44% faster than stock while using about 14.6 W less average board power. State C was slower than both State B and stock despite reporting a 600 W requested/enforced limit.

The independent 50 ms telemetry reported:

| State | Instantaneous power min/avg/max | GPU utilization |
|---|---:|---:|
| A: stock | 428.5 / 571.0 / 615.8 W | 97.4% |
| B: custom V/F, `+2000`, unlocked | 444.4 / 559.7 / 610.1 W | 97.6% |
| C: same settings, locked | 320.8 / 415.0 / 449.1 W | 99.2% |

The instantaneous samples can briefly exceed the 600 W one-second power limit; the one-second-average values remained below the configured limit.

No run reported an Xid, hardware slowdown, thermal slowdown, power-brake slowdown, or software thermal slowdown. Private active PERF-limit enumeration returned zero active traditional limits in all three runs. The NVIDIA software power-capping controller itself was active in 91.8% of stock samples and 100% of both custom-curve runs.

## Read-only power-policy evidence

Read-only `NV2080_CTRL_CMD_PMGR_PWR_POLICY_GET_STATUS` / dynamic-status sampling identifies policy type `0x14` as the active `WORKLOAD_COMBINED_2X` policy on this system.

Scene means from the latest-master runs were:

| Field | A: stock | B: custom V/F, unlocked | C: same V/F, locked |
|---|---:|---:|---:|
| Policy `CurrLimit` | 396.90 W | 400.87 W | 456.07 W |
| Policy `CurrValue` | 360.70 W | 354.47 W | 264.37 W |
| DG0 candidate | 2997.27 MHz | 2944.12 MHz | 2787.91 MHz |
| DG1 candidate | 2665.29 MHz | 2646.82 MHz | 2505.49 MHz |
| Branch-1 normalized workload | 258.30 | 250.83 | 374.18 |
| Branch-1 estimated value | 165.70 W | 188.25 W | 276.76 W |

The important anomaly is that adding the memory lock raises the second model branch from approximately 188 W to approximately 277 W, even though actual board power falls from approximately 557 W to approximately 415 W. The policy then lowers its DG0/GPC2CLK candidate and leaves a large amount of the 600 W board limit unused.

This is not evidence that a physical memory rail actually consumed 277 W. The policy's observed subchannels on this board are fixed-ratio logical decompositions of board power. It is evidence that the candidate model and arbiter enter a substantially different state when the strict memory lock is present.

## Independently verifiable NVIDIA control path

The behavior can be reproduced without any firmware analysis: compare the benchmark with and without LACT's paired memory locked-clock fields while retaining the same memory offset.

For additional control-path verification, the official installed NVIDIA userspace library was inspected:

```text
/usr/lib/libnvidia-ml.so.610.43.03
SHA-256: ad88c4a3e6c72b30d2f59f06d404abab119eb8a24a6785e3a55b4abcda8bfc6b
```

Exported function virtual addresses:

```text
nvmlDeviceSetMemoryLockedClocks   0x0004dc00
nvmlDeviceResetMemoryLockedClocks 0x0004dfa0
```

The normal numeric set path resolves to an internal helper at file VA `0x001101d0`. The installed library contains a legacy pointer-wrapper path using `0x2080e078`; direct ABI probing of the active R610 GSP method table and successful runtime requests identify the current inline-array set operation as `0x2080e0af`, with parameter size `0x13c08` and 0x13c-byte client entries. The exact GSP dispatch descriptor points to handler `0x0165e598` with flags `0x44`.

This can be verified directly with:

```bash
objdump -T /usr/lib/libnvidia-ml.so.610.43.03 \
  | grep -E 'nvmlDevice(Set|Reset)MemoryLockedClocks'

objdump -d -M intel \
  --start-address=0x1101d0 \
  --stop-address=0x110570 \
  /usr/lib/libnvidia-ml.so.610.43.03
```

In this build, the memory-domain pair uses limit/client identifiers `0x78` for the minimum record and `0x75` for the maximum record. This confirms that NVML "memory locked clocks" is implemented as a strict input to the global performance-limit arbiter, not merely as a direct memory PLL write.

The isolated requests establish that client `0x75` causes the regression while
client `0x78` does not. This distinction is not visible in LACT because the
current UI correctly requires both sides of the locked range together.

## Official GSP firmware identification and verification

The firmware used by the tested driver is installed from the official NVIDIA/Arch package at:

```text
/usr/lib/firmware/nvidia/610.43.03/gsp_ga10x.bin
SHA-256: 572373620a37418f24dc16b5031c39338778c3257e48e8408de9a57291b24f3a
```

The embedded GSP-RM ELF begins at outer-file offset `0x19f040`:

```text
Inner ELF SHA-256: bda917c95547644398eaf77fefe6c7f1b701c962db91f88bffaed6448a218a47
Format: ELF64, little-endian RISC-V, stripped, RVC
```

The location can be independently checked without executing the firmware:

```bash
xxd -l 16 -s 0x19f040 /usr/lib/firmware/nvidia/610.43.03/gsp_ga10x.bin
```

The bytes at that offset begin with the ELF magic. Carving the inner image according to its ELF extents produces the inner SHA-256 listed above.

In that R610 GSP-RM image, the method descriptor for read-only control `0x2080a619` (`PowerPoliciesGetDynamicStatus`) is located at file offset `0x00c1d020`, corresponding to GSP VA `0x01c1d020`, with parameter size `0x00060af8`. This is the runtime query used to collect `CurrLimit`, `CurrValue`, DG0/DG1, per-branch workloads, candidate voltages and estimated values. The control does not set clocks or power limits.

### Firmware-side algorithm coordinates (secondary corroboration)

The current R610 GB202 PMU images embedded in GSP-RM are encrypted Falcon-v6 images, so the exact governor instruction addresses cannot be recovered from the official R610 image alone. The following algorithm coordinates come from a clear R570 GB202 PMU image and are included only as secondary structural corroboration; they are not required to reproduce the regression and must not be treated as proof that R610 uses identical instruction addresses:

```text
PMU image SHA-256: 333d8c4ea22659f65c898579d70806640b7e26357eb6305bd900a807627d2db0
RV64 code range: 0x20298000..0x202fa000

0x202ac2de  reverse-normalizes observed power/current into workload
0x202a817e  online candidate-frequency search
0x202ac6ae  evaluates the two physical-model candidate branches
0x202afc3e  merges domain-group constraints by taking the minimum
```

The runtime R610 evidence is independent of these R570 static addresses: every dynamic-status sample satisfies the branch-sum identities, and the model's estimated value tracks the selected DG0 boundary under the configured `CurrLimit`.

## Observed compatibility impact

Locking the memory clock at the same frequency already reached under load should not reduce path-traced performance by 16.4%, lower average GPU clock by approximately 118 MHz, and lower average board-power use by approximately 142 W under an unchanged 600 W outer limit.

At minimum, users should be told that NVIDIA memory locked clocks are strict global arbiter constraints and can behave very differently from a memory frequency offset.

## Possible LACT-side mitigation

Even if the root cause must be fixed by NVIDIA, LACT could mitigate accidental regressions by:

1. Adding a warning beside NVIDIA VRAM minimum/maximum locked-clock controls, especially on Blackwell.
2. Explicitly distinguishing memory offset from memory locked clocks in the UI and documentation.
3. Advising users who only want memory overclocking to use the offset without forcing a locked range.
4. Optionally linking to this issue or documenting affected driver/GPU combinations as more reports become available.

## Available evidence

The following raw artifacts are available for attachment:

- Cyberpunk 2077 `benchmark-summary.json` for each run
- per-frame benchmark CSV files
- GPU clock/voltage/power telemetry
- NVIDIA 50 ms telemetry
- read-only RM `WORKLOAD_COMBINED_2X` dynamic-status samples
- slowdown and private PERF-limit summaries
- kernel-journal Xid checks
- the exact LACT configuration and its pre-change backup

Latest-master artifact directories:

```text
State A: benchmark_logs/cp2077_6k_20260728_054158
State B: benchmark_logs/cp2077_6k_20260728_054455
State C: benchmark_logs/cp2077_6k_20260728_054744
```
