# GB202 SYS clock runtime control and A/B result — 2026-08-11

## Runtime control

The same private RM client-clock-domain control already used by
`xbar_clock_demo` exposes SYS as client-domain record index 3.  The matching
hardware clock measurement mask is `0x4`.

The probe now supports:

```text
./xbar_clock_demo --sys
sudo ./xbar_clock_demo --sys SYS_OFFSET_KHZ HOLD_SECONDS
```

The write test used `+300000 kHz`.  RM returned `NV_OK`, GET readback returned
the exact requested offset, and termination restored the prior zero offset.
The installed driver is NVIDIA 610.57.04 on an RTX 5090 with the currently
active ASUS XOC VBIOS.  Both benchmark runs used the existing LACT V/F curve,
the existing +2000 memory setting (physical MCLK approximately 15001 MHz), and
a 600 W board limit.  The board limit was restored to 800 W afterward.

## FurMark Vulkan 4K, 20 seconds

| SYS offset | Hardware SYS avg | Hardware XBAR avg | GPU clock avg | FPS min/avg/max | Score |
|---:|---:|---:|---:|---:|---:|
| 0 MHz | 2147.1 MHz | 2170.0 MHz | 2630.4 MHz | 229 / 239 / 245 | 4791 |
| +150 MHz | 2297.7 MHz | 2159.7 MHz | 2602.0 MHz | 238 / 241 / 246 | 4824 |
| +300 MHz | 2433.8 MHz | 2166.4 MHz | 2589.8 MHz | 236 / 241 / 251 | 4814 |

FurMark shows a small positive step by +150 MHz and then a plateau.  The short
runs are not sufficient to distinguish the approximately 0.5–0.7% score change
from run variance, so this workload alone does not establish useful scaling.

Raw directories:

- `benchmark_logs/furmark_vk_3840x2160_sys0_20260811_105317/`
- `benchmark_logs/furmark_vk_3840x2160_sys150_20260811_105402/`
- `benchmark_logs/furmark_vk_3840x2160_sys300_20260811_105448/`

## Cyberpunk 2077 2.31, 6144x3456 path tracing

Both runs used the same current `UserSettings.json`, 972 rendered frames, no
frame generation, and the built-in fixed benchmark scene.

| SYS offset | Average FPS | Minimum FPS | Maximum FPS | Time | Hardware SYS avg | Hardware XBAR avg | GPU clock avg | Board power avg |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 0 MHz | 11.950357 | 10.435973 | 13.726817 | 81.3365 s | 2330.7 MHz | 2356.6 MHz | 3046.9 MHz | 589.0 W |
| +150 MHz | 12.103958 | 10.559550 | 13.997133 | 80.3869 s | 2488.9 MHz | 2357.1 MHz | 3047.7 MHz | 591.9 W |
| +300 MHz | 12.079484 | 10.523879 | 13.907162 | 80.4670 s | 2613.4 MHz | 2341.9 MHz | 3030.2 MHz | 592.3 W |

Relative changes for +300 MHz versus zero offset:

- average FPS: **+1.0805%**
- minimum FPS: **+0.8423%**
- scene time: **-1.0680%**
- measured SYS: **+12.1277%**
- reported GPU clock: **-0.5481%**
- measured XBAR: **-0.6238%**
- average board power: approximately **+3.3 W**

The intermediate point is not linear: +150 MHz produced +1.2853% average FPS,
while +300 MHz produced +1.0805%.  The difference between the two tuned runs is
only about 0.2%, so the useful gain has already plateaued within run-to-run
variance by +150 MHz.

Raw directories:

- `benchmark_logs/cp2077_sys0_6k_20260811_105615/`
- `benchmark_logs/cp2077_sys150_6k_20260811_111821/`
- `benchmark_logs/cp2077_sys300_6k_20260811_105837/`

## +600 MHz failure and MSVDD test

`SYS +600 MHz` without a rail offset was not stable.  During the Cyberpunk
launch/loading path, hardware SYS samples reached approximately 2.75 GHz on
average and 3.03 GHz maximum.  The driver then logged TLB invalidation failures,
`Xid 109 CTX SWITCH TIMEOUT`, recovery action `PF FLR`, and finally `Xid 8`.
The display froze and the machine required rebooting.

The control was extended to atomically set the SYS frequency offset and the
XBAR record's MSVDD rail offset.  Readback confirmed exactly:

```text
sys_offset_khz=600000 xbar_msvdd_offset_uv=25000
```

This combination completed a 20-second 4K Vulkan FurMark run without an Xid,
at hardware SYS 2745.2 MHz average / 3033.6 MHz maximum.  Its score fell from
the zero-offset baseline 4791 to 4745 because the fixed 600 W budget left lower
GPC/XBAR clocks.

The same `SYS +600 MHz / MSVDD +25 mV` state froze Cyberpunk again at the
startup/logo path.  Telemetry stopped with SYS 2763.2 MHz average / 3036.9 MHz
maximum and no benchmark summary was produced.  The immediate reboot did not
preserve an additional Xid record, but the frozen display and truncated
telemetry independently reproduce the failure.  Reboot restored both offsets
to zero.

This rules out a simple claim that the +600 MHz failure is fixed by a modest
MSVDD increase.  The workload selectivity and the first failure's TLB/context
errors instead point to a SYS-clocked or SYS-derived fabric, VM, copy, command,
or clock-crossing path.  The exact dependent block remains unknown.

## SYS/XBAR synchronized test

To test whether the failure was caused only by an excessive SYS-to-XBAR clock
ratio, the control tool was extended to set all three values in one RM control
transaction:

```text
SYS offset   = +600 MHz
XBAR offset  = +450 MHz
MSVDD offset = +25 mV
```

The combination completed a 20-second 4K Vulkan FurMark run.  Hardware clocks
were SYS 2721.8 MHz average / 3029.6 MHz maximum and XBAR 2497.5 MHz average /
2841.2 MHz maximum.  FurMark increased from the zero-offset 239 FPS baseline to
256 FPS, with no Xid, and all offsets restored successfully.

The same combination then launched Cyberpunk in output directory
`benchmark_logs/cp2077_sys600-xbar450-msvdd25_6k_20260811_113545/` and again
froze at the startup/logo path.  The matching holder was started at 11:35:44.
The freeze occurred before userspace stdio buffers were flushed, so the new
telemetry and holder files are zero-length; the immediate reboot also left no
new persistent Xid record.

This negative result rules out a simple explanation in which raising XBAR to
approximately 2.8 GHz is sufficient to make a roughly 3.03 GHz SYS clock
stable.  It does not rule out another clock-ratio constraint, but it moves the
leading explanations toward an absolute SYS/consumer timing limit or a
different coupled domain used by command processing, copy, mapping, or context
management.

## Synchronous rail-voltage observation

A repeat of the known-stable 4K Vulkan FurMark case used the same atomic
control state (`SYS +600 MHz`, `XBAR +450 MHz`, XBAR-record MSVDD `+25 mV`) and
sampled the direct RM SYS/XBAR counters together with the policy model's
observed rail-voltage fields.  One strictly simultaneous high-SYS sample was:

```text
SYS measured       2950.741 MHz
XBAR measured      2480.830 MHz
observed NVVDD      915 mV (sensed 915000 uV)
observed MSVDD      885 mV (sensed 885000 uV)
```

Across the nine simultaneous samples with SYS above 2.70 GHz, measured SYS
averaged 2796.7 MHz and sensed MSVDD ranged from 875 to 885 mV.  The independent
high-rate holder again observed SYS bursts around 3.02--3.03 GHz and XBAR around
2.82--2.84 GHz, while the FurMark run completed at the 600 W cap.  Raw samples:

`sys600_xbar450_msvdd25_actual_voltage_20260811_114704.log`

This proves that the firmware permits near-3-GHz SYS operation while the
reported physical MSVDD rail remains below 0.9 V in this workload.  It does
**not** prove that this voltage is stable for all SYS consumers: Cyberpunk
still freezes at its logo path under the same requested state.  It also does
not yet prove that SYS is powered exclusively by MSVDD.  The `+25 mV` control
was applied through the XBAR record, so successful write/readback must not be
described as a dedicated SYS voltage request.

Two further 4K FurMark controls held `SYS +600 MHz`, `XBAR +450 MHz`, and the
600 W board limit constant while raising only the XBAR-record voltage offset:

| XBAR-record offset | sensed MSVDD under 2X load | hardware XBAR average | hardware SYS average / max |
|---:|---:|---:|---:|
| +50 mV | 875--890 mV, 879.1 mV average | 2448.1 MHz | 2736.8 / 3029.0 MHz |
| +100 mV | 875--895 mV, 878.8 mV average | 2276.4 MHz | 2747.3 / 3028.8 MHz |

The +100 mV run's 2X branch-1 candidate frequency fell to about 2277.5 MHz;
the direct hardware XBAR clock fell with it, while the physical rail voltage
did not materially rise.  Thus this control is being consumed as an XBAR V/F
constraint: under the fixed power state, arbitration chooses a lower-frequency
point at essentially the same rail voltage.  It is not a rail-1 voltage floor
and cannot by itself test whether additional physical MSVDD makes 3 GHz SYS
stable.

Raw runs:

- `benchmark_logs/furmark_vk_3840x2160_sys600_xbar450_msvdd50_2x_20260811_115202/`
- `benchmark_logs/furmark_vk_3840x2160_sys600_xbar450_msvdd100_2x_20260811_115413/`

The next discriminating control therefore needs to target a rail-1 voltage
client request or Vmin before max-client arbitration, while retaining both the
2X candidate fields and the final sensed rail target.  Merely increasing the
clock-domain voltage offset further has now been falsified as a way to raise
the supplied voltage in this state.

## Power-headroom and independent XBAR constraint

The apparent failure above was conditional on the 600 W budget.  Raising the
board limit to 800 W and applying a max-only GPC request of 3000 MHz changed the
same `SYS +600 / XBAR +450 / voltage +100 mV` FurMark state to:

```text
observed/sensed MSVDD   946.8 mV average, 985 mV maximum
hardware SYS            2906.0 MHz average, 3030.5 MHz maximum
hardware XBAR           2489.0 MHz average
board power             803.9 W instantaneous average
```

The matched zero-voltage-offset control at the same 800 W/GPC/SYS/XBAR settings
gave only 882.6 mV MSVDD, 2732.5 MHz SYS, and 2603.4 MHz XBAR.  Thus the
positive voltage offset really can raise the winning rail-1 request when power
headroom exists; because it changes the XBAR V/F relation, it simultaneously
lowers XBAR frequency at a given rail state.

Increasing the XBAR frequency offset from +450 to +600 MHz partly compensated
XBAR but also reduced the winning rail request: MSVDD averaged 920.1 mV, XBAR
2550.4 MHz, and SYS 2834.1 MHz.  Frequency and voltage offsets therefore move
along the same V/F surface and cannot independently hold both axes.

A strict 2600 MHz XBAR min/max client was then added.  With GPC max-only still
at 3000 MHz, the hardware could not fully obey it because board power remained
pinned at 800 W: XBAR averaged only 2471.9 MHz.  The 3000 MHz cap had not freed
budget because FurMark's realized GPC was already about 2713 MHz.

The final discriminating run lowered the temporary GPC maximum to 2400 MHz,
leaving the 800 W board limit unchanged.  During the strict 2600 MHz XBAR
window:

```text
GPC hardware            2370.0 MHz
board power             670.8 W average, 690.6 W maximum
2X CurrLimit/Value       566.2 / 420.8 W average
XBAR hardware            2592.3 MHz average, 2604.3 MHz maximum
SYS hardware             2985.5 MHz average, 2998.7 MHz maximum
MSVDD observed/sensed    993.5 mV average, 995 mV maximum
2X branch-1 model        2658.4 MHz at 1012.4 mV average
```

This closes the budget interaction: when GPC power is genuinely removed and
XBAR is not allowed to fall, the same rail-1 V/F request raises the programmed
MSVDD state to about 0.99 V and sustains approximately 3.0 GHz SYS plus 2.6 GHz
XBAR.  FurMark's earlier survival at transient 3 GHz SYS and about 0.88 V did
not demonstrate full-front-end stability.

Raw runs:

- `benchmark_logs/furmark_vk_3840x2160_p800_gpcmax3000_sys600_xbar450_msvdd100_20260811_120255/`
- `benchmark_logs/furmark_vk_3840x2160_p800_gpcmax3000_sys600_xbar450_msvdd0_20260811_120349/`
- `benchmark_logs/furmark_vk_3840x2160_p800_gpcmax3000_sys600_xbar600_msvdd100_20260811_120449/`
- `benchmark_logs/furmark_vk_3840x2160_p800_gpcmax2400_sys600_xbar450_msvdd100_xbarlock2600_20260811_120751/`

## Cyberpunk validation of the power-headroom state

The final FurMark state above was then carried into a Cyberpunk 2077 launch:

```text
board limit             800 W
GPC request             max-only 2400 MHz
XBAR request            strict min=max 2600 MHz
SYS offset              +600 MHz
XBAR V/F offset         +450 MHz
MSVDD curve request     +100 mV
```

The display/system failed again at the Cyberpunk logo and the machine was
rebooted.  The new boot began at `2026-08-11 12:14:51`; the launch/control
directories were created at approximately `12:13:46`--`12:13:50`.  No Xid was
persisted in the previous boot's journal.  The telemetry files remained zero
length, so this run establishes the failure boundary but does not provide a
last-sample clock trace.

After reboot, all volatile controls read back clean: SYS, XBAR, and MSVDD
offsets were zero, the GPC lock was absent, and the retained board limit was
800 W.

This falsifies the simple explanation that the earlier Cyberpunk failure was
only caused by the 600 W budget preventing MSVDD from rising.  It does **not**
isolate SYS stability, however.  Active propagation relationship 0 is the
bidirectional type-3 GPC-to-XBAR relation with ratio
`0xe660/65536 = 0.89990234375`.  A realized GPC clock of about 2370 MHz would
therefore produce an approximately 2133 MHz propagated XBAR baseline, while
this experiment simultaneously imposed a strict approximately 2600 MHz XBAR
client request.  Runtime arbitration allowed the conflicting state under
FurMark, but Cyberpunk may have exposed either the SYS overclock or the
contradictory GPC/XBAR constraints during a transition/re-evaluation.

The next discriminating control must first preserve the active GPC/XBAR
relationship: with GPC capped near 2400 MHz, leave XBAR automatic or constrain
it near the approximately 2160 MHz propagated point, then vary SYS alone.

### Ratio-preserving SYS +450 MHz control

That control was run immediately afterward with an 800 W board limit, a
max-only 2400 MHz GPC request, automatic XBAR, zero XBAR frequency offset, zero
MSVDD offset, and a verified +450 MHz SYS offset.  The first attempted run was
discarded because the write lacked root permission (`NV_ERR_INSUFFICIENT_PERMISSIONS`,
`0x1b`) and therefore ran as an unmodified baseline.  It nevertheless supplied
an adjacent matched baseline.  The corrected write returned `NV_OK` and read
back exactly `sys_offset_khz=450000` before the game was launched.

Both runs completed the same 972-frame Cyberpunk 2077 6K benchmark:

```text
                              baseline       SYS +450       delta
GPC hardware average          2380.0 MHz     2379.3 MHz     -0.7 MHz
XBAR hardware average         2148.9 MHz     2149.1 MHz     +0.2 MHz
SYS hardware average          2134.1 MHz     2585.4 MHz     +451.3 MHz
board power average            410.1 W        412.4 W       +2.3 W
average FPS                     10.4451         10.5113      +0.634%
minimum FPS                      9.6148          9.5332      -0.849%
maximum FPS                     11.9415         11.9794      +0.317%
```

There was no Xid, reset-required event, or residual clock offset.  This is a
clean runtime counterexample to the claim that +450 MHz SYS itself is unstable:
with the GPC-to-XBAR propagation relationship left intact, the offset survived
both Cyberpunk startup and the complete benchmark.  One adjacent pair is not
enough to treat the small FPS changes as a precise performance estimate, but
the stability result is decisive for this run.  The prior +600/XBAR-2600 crash
therefore points more strongly to the conflicting forced XBAR state, to the
additional 150 MHz SYS step, or to their interaction.

Raw runs:

- Baseline: `benchmark_logs/cp2077_sys450_gpcmax2400_xbarauto_msvdd100_20260811_122718/`
- Verified +450: `benchmark_logs/cp2077_sys450_verified_gpcmax2400_xbarauto_20260811_123252/`

## Interpretation boundary

Confirmed by runtime write/readback and hardware measurement:

- SYS has an independently writable offset on this driver/GPU/VBIOS state.
- `+300 MHz` produces approximately +283 MHz measured SYS under the 2077 load.
- In this controlled sweep, the game completed about 1.1-1.3% faster despite slightly
  lower reported GPC and XBAR clocks.

The sweep therefore provides direct evidence that SYS throughput matters to
this path-traced workload, but not linearly: the measured benefit plateaus by
+150 MHz.  +600 MHz is outside the demonstrated stable region even with a
+25 mV MSVDD offset.  Alternating repeats are still needed before treating the
approximately 1.1-1.3% value as a precise long-run gain.
