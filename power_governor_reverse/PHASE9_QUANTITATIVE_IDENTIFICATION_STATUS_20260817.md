# Phase-9 quantitative identification status

Date: 2026-08-17  
Contract: R610.57.04 / VBIOS 98.02.2E.80.50

## Verdict

The current digital twin is a structure/constraint simulator and a scoped
enumerated inverse planner. It is not yet a quantitatively identified complete
GSP inverse solver for arbitrary workloads and targets.

Passing software tests proves internal consistency. The 2137/2700/3000 MHz
prospective GPU runs validate several specific stage orders and steady-state
outputs, but they do not identify every private clock client, aggregate MSVDD
request winner or per-domain local voltage-selection state.

## Receipt-local Phase-9 replay without fitting the observations

Every Phase-9 telemetry receipt is now bound to the `combined-readback.txt` in
the same receipt directory. The baseline four-domain 127-point snapshots in
all three receipts have the same canonical SHA-256:
`b9a068ad3611b8ec541c7eeb3cfde8e6a73b55f872d5f27f74f94215e49ea6f9`.
The older banks in `gb202_61057_observed.json` came from the 2026-08-16 domain
rail probe and must not be used to score Phase-9 residuals.

At the observed 995 mV aggregate target, the fresh curve/headroom deltas and
mean physical contrasts are:

| Intervention | Domain | Fresh curve/headroom delta @995 | Mean physical contrast | Curve - mean diagnostic |
|---|---|---:|---:|---:|
| composite +20 mV | XBAR | -45.000 | -43.053 | -1.947 MHz |
| | SYS | -45.000 | -46.614 | +1.614 MHz |
| | NVD | -45.000 | -52.487 | +7.487 MHz |
| XBAR +450 MHz, composite +20 mV | XBAR | +405.000 | +407.608 | -2.608 MHz |
| | SYS | -45.000 | -46.369 | +1.369 MHz |
| | NVD | -45.000 | -45.708 | +0.708 MHz |
| composite -20 mV | XBAR | +37.000 | +3.212 | +33.788 MHz |
| | SYS | +30.000 | +5.658 | +24.342 MHz |
| | NVD | +38.000 | +11.131 | +26.869 MHz |

The table's last column compares a curve upper envelope with a workload mean;
it is not a forward-model residual unless the workload is known to remain
ceiling-bound. XBAR/SYS have narrow distributions and their positive means
track the fresh curve delta within 1.4--2.6 MHz.

NVD is frequently clocked down, so its mean must not be converted into a
fictitious local -5 mV selector. Its high envelope agrees with the fresh 995 mV
bank: Phase9b/c A1/A2 p90 spans 2287.161--2290.171 MHz around the 2287 MHz
baseline ceiling, and B p90 spans 2243.204--2244.979 MHz around the 2242 MHz
applied ceiling. The NVD mean response remains workload/client modulated and is
not yet a quantitatively identified forward output.

For -20 mV the curve/headroom envelope rises by 37/30/38 MHz, while the
workload request or another candidate remains binding. The workload-conditioned
prediction is therefore approximately 0/0/0, versus observed mean changes of
+3.212/+5.658/+11.131 MHz. The headroom row is not a complete forward
prediction. The previously claimed large missing non-V/F residual was an
artifact of scoring a stale curve snapshot.

Control restoration and STATUS restoration are also distinct. All three runs
have byte-identical domain/VF control blobs after restore. Phase9b's dynamic
effective STATUS curves nevertheless changed across the transaction because
VFE/tuple state drifted: XBAR/SYS/NVD changed-frequency point counts are
101/95/99, and their 995 mV values moved 2415->2407, 2400->2392 and 2287->2287
MHz. Phase9c/d STATUS equality is an observation, not a restore contract.

## Minimum missing state

For causal replay and prediction beyond these receipts, the minimum missing
state is:

1. the complete phase-local pre-V/F request set and binding winner for XBAR,
   SYS and NVD; `0x20809062` now supplies each domain's post-arbitration target
   and actual frequency, but not the simultaneous candidates or binding client;
2. the workload-conditioned request/client duty state needed to predict the
   target itself. The target-to-actual/physical mapping is now directly
   observed for all four domains, including NVD;
3. the active aggregate MSVDD request client/value if the target must be
   predicted rather than supplied as an observed literal. Voltage PMUMON now
   timestamps the aggregate rail target itself, but does not expose the
   pre-arbitration requests or winner.

The receipt-local curves close the main Phase-9 equations; fitting the small
remaining deltas would only parameterize an observational equivalence class.
It would not identify whether they came from a clock client, tuple/relation
state, post-selection adjustment, policy/dwell state or workload drift.

## Can the existing receipts close it?

They close the boundary curve/headroom response once each telemetry file is
paired with its fresh bank snapshot. They do not close the workload-conditioned
inverse problem: the receipts contain baseline/applied/restored boundary VF
STATUS and rail STATUS, but no synchronized tuple/client/winner bracket during
the A1/B/A2 load phases. Many hidden state assignments produce the same means.

The next discriminating capture must bracket each settled phase with fresh,
read-only snapshots of:

- XBAR/SYS/NVD effective V/F STATUS banks (already present at transaction
  boundaries, but not synchronized with the in-load client-status bracket);
- VF-relation current tuple index/current MHz and VFE/tuple state;
- per-domain active clock-client candidates and binding client IDs. Final
  post-arbitration target and actual values are implemented for all four
  domains; the complete selector input set remains missing;
- propagation relation STATUS/CONTROL;
- voltage-request active/deferred masks, evaluated client values and winner;
- aggregate rail pre-clamp request/target plus the simultaneous four physical
  clocks and power-policy/DG0 state.

This can reuse the existing LACT composite A-B-A transaction and workload. It
needs new synchronized STATUS/client brackets, not a new write primitive.

## Synchronized relation telemetry now implemented

The LACT Phase-9 sampler now appends the five current type-9 VF-relation
records (relations 13..17) to every telemetry row in the same loop as the four
physical clock measurements and aggregate MSVDD target. Each relation adds its
relation-stage MHz, `STATUS +6` tuple index and `STATUS +4` one-based output
ordinal. The latter two CSV names retain an `_inferred` suffix: current R610
runtime transitions and older same-generation MODS labels support those field
interpretations, but the private R610 ABI does not publish their names.

A read-only live smoke test returned four complete 38-column rows at roughly
115--121 ms spacing. During that capture relation 13 reported
`3270 MHz / tuple 9 / output 9`, while relations 14..17 reported the warmer
temperature state `2715/47/6`, `2842/68/6`, `2302/89/6` and `2812/110/6`.
The same rows retain valid/frequency pairs for the known PERF limit IDs
`0x41/42/43/46/48/4d/e9/ea`. In the idle smoke, the valid nonzero GPC-class
candidates were 3262 MHz and the two known XBAR thermal/power candidates were
both 3135 MHz; ID `0x48` was valid with a zero frequency and remains raw rather
than being silently discarded.
No clock, voltage, propagation or workload control was changed.

A separate read-only 4-second L2 receipt then exercised the same 38-column
sampler under load. The GPC physical mean was 3192.617 MHz versus the known
`0x43` candidate at 3195 MHz. The known XBAR power candidate `0xea=2722 MHz`
was lower than thermal `0xe9=3135 MHz`, yet physical XBAR averaged only
2417.612 MHz: the known candidate minimum was still 304.388 MHz above the
grant, so another downstream/unobserved constraint remained binding. All
relation and PERF-limit fields stayed fixed across the 355 ms bracket while
aggregate MSVDD target changed 1000->995 mV. This independently demonstrates
that the rail winner has hidden state outside the captured clock candidates.
The complete receipt is `phase9_private_status_read_probe_20260817.Ve5wxm/`.

This closes the synchronized tuple/relation part and the bounded known
GPC/XBAR PERF-candidate part of the requested bracket. It does not provide a
complete clock-client candidate/winner set. The supplemental full inventory
below closes the PERF-limit search space itself, but not the hidden client
arbiter. In particular,
`0x20809025`/`0x20809027` are not a justified candidate surface: the current
GSP descriptors map them to the clock frequency-controller STATUS/CONTROL
handlers, and same-generation MODS identifies that feature as closed-loop
frequency controllers. Zero-buffer and simple type/mask-prefill STATUS calls
returned no objects. Those empty records must not be relabeled as client
arbitration state.

`CLK_CLIENT_VF_POINTS_GET_STATUS` (`0x2080902b`) is a better-named but still
non-winning surface. A read-only 4-second L2 discriminator showed that its
upper GPC points change with the dynamic VFE/thermal state while its CONTROL
offsets remain fixed. Paired client/main V/F captures then resolved the layout:
for all 125 normal GPC points, client STATUS `freq0` equals the main
`0x20809022` effective frequency; for all 127 points, client STATUS `freq1`
equals the main source-base frequency plus exactly 45 MHz, and both voltage
fields agree 127/127. Thus this method exposes the same curve as a useful
composition of firmware/VBIOS baseline, client CONTROL offset and grid
remainder. It does not enumerate simultaneous request candidates or identify
a binding client/final grant. The complete raw receipt is
`clk_client_vf_status_load_probe_20260817.dVz089/`.
Static tracing independently closes the same boundary: handler `0x010cc03c`
selects the ClockManager client-V/F embedded group and calls its `+0x18`
method, which is the generic BoardObjGrp serializer `0x01738d64`; the STATUS
entry accessor at `+0x68` serializes `output+0x28+index*0x18`. Neither method
is a scalar selector or arbiter.

## Complete PERF-limit inventory and controller-min boundary

The read-only probe now queries every PERF-limit ID `0x00..0xff` one at a time
in one RM session and cross-maps the result against the pinned current GSP
container SHA-256
`c0156954f3e048d56011524e0c2ae2881bb6db8173b53f9b2f4eb94197f02999`.
Exactly 20 IDs were valid in each inventory. The static PERF-CF controller
catalog contains:

```text
0xd0 DRAM_MIN   runtime valid
0xd1 GPC_MIN    runtime valid
0xd2 NVD_MIN    runtime state-dependent
0xd5 DRAM_MAX   runtime invalid
0xd6 GPC_MAX    runtime invalid
0xd7 NVD_MAX    runtime invalid
0xdb XBAR_MAX   runtime invalid
```

There is no `PERF_CF_CONTROLLER_SYS_*` catalog record. The only static name
containing `SYS` is generic ID `0x1b SYSPERF`, which is runtime-invalid and is
not a named SYS clock candidate. Therefore further blind PERF-limit ID scans
cannot recover the missing SYS request/winner on this build. NVD has only the
`0xd2` minimum endpoint; the named `0xd7 NVD_MAX` endpoint is not active.

The synchronized LACT row now adds `0xd0/0xd1/0xd2` after the original eight
candidates, bringing the row to 55 columns. A 6.5-second persistent sampler
under a passing 9-second L2 workload returned 53 complete rows. `d0` was valid
53/53 at `15001 MHz`, `d1` was valid 53/53 at `3180/3195/3240 MHz`, while
`d2` was valid only 4/53 between 397 and 788 ms at `637..697 MHz`. Physical NVD
at those four instants was `2234.762..2286.117 MHz`. Direct short-lived probe
processes could keep `d2` valid at other values, so process/session churn is a
measurement perturbation. Batch sizes 8, 9 and 10 behaved alike once the
endpoint became active; the earlier apparent tenth-entry cutoff was false.

Consequently `d0/d1/d2` are retained as raw, state-dependent PERF-CF
controller-min endpoint observations with the explicit boundary
`not_binding_upper_winners_or_final_grants`. They are not fed to the inverse
solver as physical grants. The complete receipt is
`phase9_perf_limit_inventory_20260817.Rg1EsO/`.

## Four-domain target/actual STATUS and official NVD programmed clock

The NVIDIA MIT-licensed R610 header defines `0x20801037` as clock-domain
PMUMON and names its fields programmed GPC, DRAM, NVD and active GPC clocks.
This interface is now sampled next to the voltage PMUMON timestamp.

Separately, `0x20809062` accepts up to 32 frequency-domain records. Its payload
is an 8-byte header followed by 20-byte records whose input API domain is at
record `+4`. Same-generation MODS contains the exact diagnostic field order
`clkDomain, actualFreq, targetFreq, clkSource, flags`; current GPC/XBAR/SYS/NVD
runtime values track direct measurements and the official programmed-NVD
sample independently. LACT now captures `actual_khz`, `target_khz`,
`clock_source` and `flags` for all four domains in every row. The same query is
now part of the formal schema/daemon response rather than test-only telemetry.
The MSVDD GUI plots firmware target, firmware actual and the independent
physical counter as distinct markers at the fresh aggregate MSVDD target; it
labels the reads as non-atomic because idle gating and sampling lag can make
them temporarily disagree.

Under settled L2, mean physical/STATUS-actual/STATUS-target MHz were
`3190.15/3187/3195` GPC, `2414.48/2413.91/2426.73` XBAR,
`2402.11/2398.18/2407` SYS and `2276.40/2286.05/2299.14` NVD. Pure NVENC
instead held targets at `2580/2317/2302/2197 MHz`. Thus the previously hidden
workload-conditioned final target is now observed for SYS and NVD as well as
GPC/XBAR. It is still a post-arbitration result, not the candidate set or
binding client ID. All four domains returned `clock_source=0` and `flags=0` in
the tested boot, so those fields do not identify the winner.

The combined row is now 79 columns. The read-only idle/L2/compute/VRAM/NVDEC/
NVENC/transcode receipt is `nvd_sys_workload_matrix_20260817.nyD453/`.

## Single-domain MSVDD causal perturbation

A restored SET experiment changed only one rail-1 domain offset at a time by
`+5000 uV` under a continuous checked L2 workload. The complete CONTROL
readback differed only at XBAR offset `0x90`, SYS `0x110`, or NVD `0x150`, and
every restored/global-final block matched its original preimage byte for byte.

Only the perturbed domain's `0x9062` final target moved during B and returned in
A2: XBAR `2422 -> 2415 -> 2422 MHz`, SYS `2407 -> 2400 -> 2407 MHz`, and NVD
`2295 -> 2287 -> 2295 MHz`. Thus the three rail-1 fields are independent
domain-map translations feeding one shared MSVDD rail. They are not aliases for
one XBAR-only voltage control.

The aggregate rail stayed at `995000 uV` for most samples. Four consecutive
`1000000 uV` rows appeared in XBAR and NVD B, but a 13-second read-only L2
control also produced four such rows among 105 samples. Those transients cannot
identify a voltage winner. No single `+5 mV` perturbation caused a stable rail
increase, so the binding voltage-request client remains unobserved. Receipt:
`single_domain_msvdd_aba_root_20260817.Wo2MGs/`.

## Timestamped aggregate voltage telemetry and public-status closure

The current GSP voltage family exposes read-only method `0x2080b216` with a
`0x658`-byte payload. Its structure is exactly the public PMUMON super header
(`0x18` bytes) followed by fifty `0x20`-byte samples. Latest-only mode returns
one `u64` nanosecond timestamp and six raw `u32` voltage words. A paired fresh
read on the current build/boot returned word0/word2 = 830000/880000 uV and the
ordinary rail STATUS returned rail0/rail1 targets = 830000/880000 uV. Words
1/3 remained 1200000/1000000 uV and are not assigned semantic names; words 4/5
were `UINT32_MAX` sentinels.

The Phase-9 sampler appends the PMUMON queue identity, sample timestamp,
host Unix timestamp and all six raw words. With the three supplemental
PERF-CF controller-min endpoints, current captures are 55 columns.
The evidence loader keeps the sample age and per-phase raw channels, with an
explicit `timestamped_aggregate_voltage_channels_not_request_client_or_winner`
boundary. Old 38-column receipts remain valid and report this block as absent.

Static tracing also closes why this does not solve the winner. The
`0x2080b202` rail STATUS handler resolves a BoardObj rail-status object and
calls its `+8` serializer; constructor `0x017f7c00` installs the base/derived
serializers `0x017efc1c`/`0x017efe64`. They serialize the public aggregate rail
record and one derived byte, not controller offsets `+0xad8`, `+0xadc`,
`+0xae4`, `+0xae8` or `+0xb10`. Therefore the retail public status path genuinely does not
export the ten request slots or winner ID; this is now a closed observability
boundary rather than an untested guess. The static and loaded read-only receipt
is `phase9_voltage_pmumon_probe_20260817.YSxUzm/`.

The current descriptor-defined retail voltage GET family was then exhausted,
including `b201/b202/b205/b207/b209/b210/b211/b212/b213/b214/b216/b217/b218`
with their exact current sizes. Public rail, device, policy, threshold and
telemetry records were returned, but none had the 10-bit active/deferred masks
or ten 16-byte request records. `b214` was the only tempting false positive:
its eleven repeated values are raw quantization-code/uV/valid triples and its
handler calls the generic PMU telemetry copier, not the voltage-request
serializer. Same-generation MODS metadata also proves that voltage command
numbers moved between R570 and R610, so unconfirmed current methods remain
named by number rather than inheriting stale labels.

The remaining winner ID is therefore not identifiable from the retail outputs:
two latent states can swap the winning client while preserving the same
aggregate and quantized target. This counterexample is executable as
`test_aggregate_target_does_not_identify_the_winning_client`. Recovering the
boot winner requires a slot dump or instrumentation of a request-update path;
more aggregate sampling cannot supply the missing information.

## Artifacts and validation

- Fresh-curve loader: `bug_inverse/algorithm/gpu_inverse/aba_evidence.py`
- Bound Phase-9 manifest: `bug_inverse/algorithm/tests/fixtures/lact_phase9_aba_manifest.json`
- Residual regression: `bug_inverse/algorithm/tests/test_aba_evidence.py`
- Current general config: `bug_inverse/algorithm/configs/gb202_61057_observed.json`
- Client/main V/F discriminator receipt: `clk_client_vf_status_load_probe_20260817.dVz089/`
- Loaded synchronized candidate receipt: `phase9_private_status_read_probe_20260817.Ve5wxm/`
- Voltage PMUMON/status-path receipt: `phase9_voltage_pmumon_probe_20260817.YSxUzm/`
- Full PERF-limit inventory and synchronized endpoint receipt:
  `phase9_perf_limit_inventory_20260817.Rg1EsO/`
- Four-domain target/actual and programmed-NVD workload matrix:
  `nvd_sys_workload_matrix_20260817.nyD453/`
- Restored single-domain MSVDD `+5 mV` A-B-A and no-SET control:
  `single_domain_msvdd_aba_root_20260817.Wo2MGs/`
- Production-compiler independent XBAR/SYS/NVD `+5 mV` adoption/restore:
  `lact_independent_msvdd_production_20260817.BHKv9b/`
- NVD domain-frequency `+15 MHz` adoption plus NVD point-96 `±15 MHz`
  non-adoption discriminator: `lact_nvd_controls_20260817.iZlKUI/`
- Current R610 voltage descriptors and R570 method-name boundary:
  `gsp61057_voltage_descriptor_region_20260817.txt`,
  `gsp61057_voltage_descriptor_tail_20260817.txt`,
  `mods570_voltage_metadata_20260817.txt`, and
  `mods570_voltage_method_names_20260817.txt`
- Current voltage telemetry/static discriminator:
  `gsp61057_018151d8_telemetry_copy_20260817.c` and
  `gsp61057_018151d8_callers_20260817.c`
- Pinned static/runtime catalog auditor:
  `bug_inverse/perf_limits_61057/audit_perf_limit_catalog.py`

Validation on this tree:

```text
compileall: pass
algorithm unittest discovery: 186/186 pass
data-pipeline unittest discovery: 8/8 pass
algorithm + data-pipeline + catalog pytest: 196/196 pass
LACT daemon tests: 51 pass, 11 ignored
LACT GUI tests: 34/34 pass
LACT schema tests: 11/11 pass
LACT workspace tests and doctests: pass
LACT workspace all-target clippy with warnings denied: pass
LACT release build: pass
79-column read-only live sampler: pass across seven workload classes
complete PERF-limit catalog audit: 256 IDs, 20 runtime-valid, pass
```
