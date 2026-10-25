# GB202 multi-domain control model status

Date: 2026-08-17  
Target: RTX 5090 / GB202 / R610.57.04  
Safety boundary: reconstruction was offline first, followed by bounded live
validation explicitly authorized on 2026-08-17. Live validation changed only a
temporary GPC clock lock, ran a three-second PTX compute workload, and reset the
lock afterward. The initial standalone XBAR/ratio/voltage tools were rejected
before any workload began and independent GETs showed no state change. Later
exact-contract LACT transactions successfully adopted and restored domain
offset, V/F point, relation CONTROL and composite three-domain MSVDD curve
offset fields; ratio physical adoption remains separately unproven. Fan control
was never touched.

## Outcome

Status boundary: this is a structure/constraint simulator plus a scoped
enumerated inverse planner, not a quantitatively identified complete GSP
inverse solver for arbitrary workloads. Specific live points are predictive;
unobserved private request winners, workload-conditioned clock-client/duty
state and aggregate rail-winner provenance remain explicit inputs.
The Phase-9 no-fit residual audit is in
`PHASE9_QUANTITATIVE_IDENTIFICATION_STATUS_20260817.md`.

The virtual solver now has an evidence-separated end-to-end pipeline:

```text
VBIOS BIT C
  -> nine clock-domain records
  -> 18 clock-program/VF-relation records
  -> 75-node VFE graph and 167 meaningful tuple conditions
  -> relation/VF-point selection
  -> power candidate and DG0 tracking
  -> client limits and GPC-to-XBAR/SYS/NVD propagation
  -> clock-grid/divider projection for F-to-V lookup
  -> per-domain VF voltage requests
  -> ten-slot voltage arbitration and rail quantization
  -> optional final effective-clock arbitration without voltage relookup
  -> per-domain voltage ceilings
  -> physical clock-grid/divider projection
  -> GPC/XBAR/SYS/NVD clocks and NVVDD/MSVDD targets
```

The model does not label current encrypted-PMU code as recovered when only its
R570 clear-PMU counterpart or current wire ABI is known. Every trace carries
the corresponding confidence boundary.

## Live solver validation

The decisive prospective run froze this prediction before starting the GPU
workload:

| Domain/rail | Predicted | Live p95/max | Error |
|---|---:|---:|---:|
| GPC | 2700 MHz | 2701.947 MHz p95 | +1.947 MHz |
| XBAR | 2430 MHz | 2430.820 MHz p95 | +0.820 MHz |
| SYS | 2422 MHz | 2424.140 MHz p95 | +2.140 MHz |
| NVD | 2310 MHz | 2310.213 MHz p95 | +0.213 MHz |
| NVVDD | 885 mV | 885 mV max | 0 mV |
| MSVDD | 995 mV | 995 mV max | 0 mV |

The PTX compute run covered 170/170 SMs, completed 9,356 rounds and
49,703.750 GiB in 3.000240 seconds with zero data errors, zero Xids and no
safety-gate event. The restored readback was XBAR offset 0 kHz, ratio raw
`0x0000e660`, and rail deltas 0/-50000 uV.

This run also closes the voltage-decision ordering for the tested R610 P0
state. At GPC 2700 MHz the ratio ceiling makes XBAR 2430 MHz; that final XBAR
point requests 995 mV, exactly the observed MSVDD maximum. A pre-propagation
request from XBAR 2812 MHz would instead saturate the 1000 mV rail cap. The
default model is therefore `voltage_request_stage = final`; the older
`pre_power_requested` path remains available only as an explicit
counterfactual.

Full receipts and the limits of this conclusion are recorded in
`SOLVER_LIVE_VALIDATION_20260817.md`.

## Issue 1268 stale-voltage path

The exact bug the issue describes is now a separate, explicit stage rather
than being conflated with propagation or shared-rail plateaus:

```text
provisional/policy GPC
  -> clock projection and one F-to-V lookup
  -> voltage request/rail arbitration
  -> later final effective GPC maximum
  -> no second F-to-V lookup
```

`post_voltage_clock_max_mhz` supplies the still-opaque final grant. The trace
emits a `stale_voltage_certificate` containing the lookup frequency, retained
rail target, final effective clock, hypothetical relookup voltage and retained
voltage delta. The controlled #1268 result confirms the stale-voltage effect
and refresh after a new clock-control commit; it does not identify the private
R610 client/equation that produced the final grant, so the solver never invents
that value when it is absent.

The runnable example replays policy/final values 2968/2893 MHz from the report:

- `bug_inverse/algorithm/examples/issue1268_stale_voltage_scenario.json`
- `bug_inverse/algorithm/examples/control_issue1268_stale_voltage.json`

## Byte-exact/current-build results

- BIT C v2 resolves current ROM Clocks, Clock Programming, NAFLL, ADC and
  Frequency Controller pointers. The strict parser recovers all nine domains,
  18 active program rows and the exact relation graph.
- GPC/XBAR/SYS/NVD/PWR public clock lists use the exact effective integer ratio
  15/2. The current R610 row serializer and R570 PMU importer agree on the wire
  fields consumed by the physical grid object.
- The current R610 GSP constructs the VF tuple/relation tables and imports live
  relation STATUS from PMU. It does not evaluate the selected tuple in the
  public GET path.
- The current VFE/tuple readback gives 75 VFE objects, 21 derived sum/product
  edges and 167 meaningful tuples covering all 18 relations.
- R570.151 MODS `Perf50` closes the tuple frequency-offset control ABI:
  GET `0x20809046` (0x2048 bytes), validate the clock-domain tuple range,
  write signed kHz at `0x50 + tupleIndex*0x10`, SET `0x2080d047`.
- The R610 voltage controller core uses ten 16-byte request slots. The recovered
  reduction compares evaluated values in client order and lets a later active
  client replace an equal winner. Rail realization rounds to the device grid
  before min/max clamping.
- Current GPC-to-XBAR ratio object construction stores U16.16 ratio and exact
  floor reciprocal with zero/overflow checks.

## Exact clear-PMU kernels reused with an explicit version boundary

- Relation frequency-to-voltage and voltage-to-frequency use upper-midpoint
  binary search, adjacent-point evaluation and endpoint clamp.
- Type-3 propagation uses 64-bit U16.16 multiplication with half-up rounding,
  followed by directional destination-domain normalization.
- Type-5 propagation converts both frequency-range endpoints to voltage, maps
  both voltage endpoints to the target relation and clamps them independently.
- Candidate tracking uses separate Q12 up/down gains with bit-11 half-up
  rounding.
- Post-selection domain adjustment supports signed kHz/1000 and signed-Q12
  forms, then s16 narrowing, negative clamp and relation reprojection.
- The physical programmer builds divider descriptors and packs the per-clock
  control words. With the current effective 15/2 ratio, it reproduces the
  present main-domain readback grid.

These bodies are exact for the GB202 R570 clear PMU. Their use in an R610 trace
is marked as same-generation code plus current R610 transfer ABI, not as a
byte-identical decryption of R610.

## Two discriminating examples

The checked-in FurMark scenario chooses GPC 3330 MHz in the power stage. A
2992 MHz user maximum then wins, and the physical grid realizes 2985 MHz with
divider 398. This is the concrete reason an initially selected GPC value is not
the final clock: the values belong to different ordered stages.

The +450 and +500 XBAR controls both realize XBAR 2992 MHz, divider 399. In both
cases the GPC-to-XBAR ceiling is decisive:

| XBAR offset | pre-propagation XBAR | final XBAR | MSVDD | SYS | NVD |
|---:|---:|---:|---:|---:|---:|
| +450 MHz | 3262 | 2992 | 1050 mV | 2542 | 2430 |
| +500 MHz | 3312 | 2992 | 1025 mV | 2490 | 2377 |

The equal XBAR output is therefore a many-to-one constraint result, not proof
that the second offset was ignored. The higher curve offset also changes the
voltage required to support the same capped XBAR frequency; because SYS and NVD
share MSVDD in this model, their voltage-derived ceilings remain distinguishable.

## Current hard boundary

Automatic tuple choice belongs to PMU CLK group `0x11`. The selected R570 GB202
clear PMU lacks that group. A structural scan of all ten large clear PMU images
in the same MODS package found the same jump from group `0x10` to `0x16`, with
no `0x11` in any profile. The installed R610 `ucodes_ga10x.bin` is an
`NVUCODES` placeholder with only 19 non-zero bytes, not a hidden executable.

Consequently the following current-R610 details remain parameters rather than
fabricated constants:

- VFE product rounding/saturation and sampling/filter timing;
- exact inclusive-boundary tie break, dwell and hysteresis;
- the PMU ordering of tuple signed-kHz control versus curve generation;
- live private VFE inputs and private active/client masks;
- byte-identical R610 physical-programmer confirmation.

The tuple selector still provides useful certificates: it evaluates the known
graph and intervals, replays every observed natural transition, reports missing
private inputs, and refuses to interpolate unseen tuple-to-MHz outputs.

## Artifacts and validation

- Digital twin: `bug_inverse/algorithm/gpu_inverse/digital_twin.py`
- VBIOS graph parser: `bug_inverse/algorithm/gpu_inverse/vbios_clock_tables.py`
- Tuple graph/selector: `bug_inverse/algorithm/gpu_inverse/vfe_tuple.py`
- Tuple control encoder: `bug_inverse/algorithm/gpu_inverse/vf_tuple_control.py`
- Physical grid: `bug_inverse/algorithm/gpu_inverse/pmu_clock_programmer.py`
- Current config: `bug_inverse/algorithm/configs/gb202_61057_observed.json`
- MODS control proof: `mods_perf50_vf_tuple_offset_20260817.c`
- Cross-profile audit: `R570_PMU_CLK_GROUP_CROSS_PROFILE_20260817.md`

Validation on this tree:

```text
compileall: pass
algorithm unittest discovery: 167/167 pass
data-pipeline unittest discovery: 8/8 pass
algorithm + data-pipeline + catalog pytest: 177/177 pass
simulate CLI: pass
compare CLI: pass
enumerated solve CLI: feasible_candidate_found (6 evaluated, 2 feasible)
prospective live PTX validation: pass (170/170 SM, 0 errors, 0 Xid)
automated prediction-vs-live runner smoke test: pass
low-voltage/VMin four-domain prospective validation: pass
```
