# R610.57.04 GSP VFE / VF-tuple / VF-relation reconstruction

Date: 2026-08-16  
Target: GB202 RTX 5090, driver 610.57.04  
Safety boundary: static analysis, compilation and read-only RM control calls only. No fan,
clock, voltage, power or workload setter was invoked for this work.

## Result

The current public object graph is no longer a black-box collection of 127-point curves.
The read-back path now exposes a reproducible chain:

```text
thermal / voltage / caller / external VFE inputs
  -> 75-node VFE expression graph (21 sum/product nodes)
  -> signed-Q8.8 tuple interval matching
  -> one current tuple per VF relation
  -> relation-stage frequency
  -> later domain/client offsets, propagation, limits and clock realization
```

The checked-in simulator implements the VFE graph and tuple selector as a diagnostic
certificate in `bug_inverse/algorithm/gpu_inverse/vfe_tuple.py`. For tuple indexes seen in
the three read-only samples it also attaches the measured relation-stage MHz as a sparse
binding. It deliberately does not interpolate unobserved tuple outputs or feed the
diagnostic selector into final clock/voltage outputs: current-PMU selection tie-breaking,
sampling, filtering and product arithmetic are not all recovered.

## Public ABI recovered on this build

| Object | Method | Parameter size | Recovered public layout |
|---|---:|---:|---|
| VF tuple INFO | `0x20809044` | `0x9848` | entry base `0x48`, stride `0x4c`, 512 capacity; four `0x10` condition slots and trailing u32 at `+0x44` |
| VF relation INFO | `0x20809070` | `0x77b0` | entry base `0x28`, stride `0x78`, 255 capacity |
| VF relation STATUS | `0x20809071` | `0x1214` | entry base `0x24`, stride `0x12`, nine u16 fields |
| VF relation CONTROL | `0x20809072` | `0x37ec` | entry base `0x24`, stride `0x38`, 255 capacity |
| VFE variable INFO | `0x2080a0b1` | `0xc364` | entry base `0x28`, stride `0xc4`, 255 capacity |
| VFE variable CONTROL | `0x2080a0b3` | `0x2bfc` | entry base `0x28`, stride `0x2c`, 255 capacity |

The Pstate-5 tuple frequency-offset control is now independently closed from
R570.151 MODS `Perf50`, rather than inferred from method numbering:

```text
JsPerf wrapper 0x015e9b00
  -> Perf50 vtable +0x290
  -> 0x01669fe0
       GET  0x20809046, size 0x2048
       validate tupleIdx in the selected clock domain's [first,last] range
       write s32 freqOffsetKhz at payload + 0x50 + tupleIdx * 0x10
       SET  0x2080d047, size 0x2048
```

The usage string is explicit: `ModifyVfTupleFreqOffset(clkDomain, tupleIdx,
freqOffsetKhz)`. The `Perf50` RTTI/vtable path is also discriminating: older
`Perf`, `Perf20`, `Perf30` and `Perf40` vtables keep the unsupported stub in
that slot, while `Perf50` installs `0x01669fe0`. The executable offline encoder
is `bug_inverse/algorithm/gpu_inverse/vf_tuple_control.py`.

This closes the host control field, its units, width, capacity and exact byte
offset. It does not reveal when the current R610 PMU applies the offset relative
to automatic tuple matching, relation curve construction or later domain
adjustments.

`PERF_VFE_VARS_GET_STATUS` (`0x2080a0b2`) returns `0xffff` on this build, so current
values of all private VFE inputs are not directly available through that public method.

VF tuple INFO has 511 valid type-2 entries, but only indexes 0..166 contain meaningful
conditions. Entries 167..510 have all four condition IDs set to `0xffff`. Tuple condition
minimum and maximum fields are signed Q8.8. The first s32 payload is retained as an opaque
`payload_value_q8_8`: it is not generally the interval center.

## Relation and tuple-bank mapping

The relation INFO flat-point ranges and exact type-7 frequency keys identify all 18 banks:

| Relations | Type / consumer | VF-point or frequency mapping | Tuple indexes |
|---:|---|---|---:|
| 0..7 | type 7 / API40 rows | 675, 900, 1026, 1080, 1188, 1296, 1350, 1620 MHz | 125..145 |
| 8..12 | type 7 / MCLK rows | 405, 810, 7001, 13801, 15001 MHz | 146..166 |
| 13 | type 9 / GPC | flat VF points 0..126 | 0..40 |
| 14 | type 9 / NVD | flat VF points 386..512 | 41..61 |
| 15 | type 9 / SYS | flat VF points 259..385 | 62..82 |
| 16 | type 9 / PWR | flat VF points 513..639 | 83..103 |
| 17 | type 9 / XBAR | flat VF points 127..253 | 104..124 |

The type-7 constructor at R610 GSP function `0x011240f0` iterates a relation's tuple
range and stores a tuple selector at tuple object `+0x20`: the special/default tuple gets
`0x14`, while non-default tuples receive consecutive ordinals. The type-9 constructor is
at `0x01124484`. This matches the public tuple trailing values, every INFO range and the
STATUS transition below.

The nine u16 fields in a relation STATUS slot currently behave as follows:

```text
+0  relation type (7 or 9)
+2  current relation frequency in MHz
+4  one-based non-default output ordinal (supported inference)
+6  current global tuple index (supported inference)
+8  type-9 extra field; meaning unknown
+10..+16 currently unresolved
```

`+6` agrees with all 18 relation tuple ranges and old same-generation MODS labeling.
`+4` changes together with a known temperature-bin transition. The exact internal names
and lifecycle of these fields are still not claimed.

The current CONTROL read-back is not the automatic selector state. All 18 records are
default/zero apart from fixed sentinels: type 7 has `+0x2c = 0xffff`; type 9 additionally
has `+0x2e/+0x30/+0x32/+0x34 = 0xff00`. Old MODS code reads
`currentVfTupleIdx` from STATUS, then separately GETs CONTROL, changes its tuple selector
and issues SET. This proves the automatic STATUS value and the override object are
separate. It supports, but does not by itself prove, that current CONTROL `+0x2c` is the
override selector; the current field name and SET semantics remain unknown.

## GSP/PMU ownership boundary

R610 GSP constructors install these relation vtables:

```text
type 7 constructor 0x011240f0:
  +0x20 0x0111b738   +0x28 0x0111bc08   +0x30 0x0111c14c
type 9 constructor 0x01124484:
  +0x10 0x0111d87c   +0x08 0x0111e408
  +0x28 0x0111f1f0   +0x30 0x0111f594
```

Decompilation identifies these as INFO/STATUS/CONTROL import/export paths. The inherited
slot `+0x20` method `0x0111b738` is especially discriminating: it first invokes the
generic BoardObj status importer and then copies eight incoming u16 status values into
the live relation-status view. Type 9 calls the type-7 constructor and does not replace
slot `+0x20`, so it inherits this same importer. Base exporter `0x0111b07c`, followed by
the type-9 wrapper `0x0111e408`, later serializes those fields into the public response.
Thus current MHz/ordinal/tuple values arrive as PMU BoardObj status; the public GSP GET
path is not their evaluator. These methods copy and package relation state; none performs
interval evaluation or current-tuple choice.

The optional same-generation MODS host path gives the PMU boundary exact identities:

```text
VF relation: PMU unit 0x0d, group enum 0x0b,
             group/object sizes 0x30/0x80, transfer identity 0x2610b0
VF tuple:    PMU unit 0x0d, group enum 0x11, generic BoardObjGrp constructor
```

The GB202 R570 clear PMU independently registers group `0x0b` at `0x202f64d0` with the
same `0x2610b0 / 0x30 / 0x80` identity. Its CLK dispatch table also maps `0x0e` to the
known propagation-top-relations registration, but it has no `0x11` entry: it jumps from
`0x10` to `0x16`. Therefore R570 supplies no tuple evaluator that can honestly be labeled
as the R610 algorithm. The active tuple selector belongs beyond the R610 GSP serializer
boundary, in a newly present/current PMU group whose clear code is not available.

This absence was checked across all ten large clear PMU images in the local
R570.151 MODS package, not only the GB202-selected image. Every CLK descriptor
run jumps from group `0x10` to `0x16`; none contains `0x11`. The installed
R610.57.04 `ucodes_ga10x.bin` is a 31,744-byte `NVUCODES` placeholder with only
19 non-zero bytes, not a hidden PMU executable. See
`R570_PMU_CLK_GROUP_CROSS_PROFILE_20260817.md`.

Two tempting MODS call sites are now excluded from that selector boundary.
`0x016623a0` repeatedly GETs `0x2080901c` until a generated flag appears and
only reports timing/worst-case timing; `0x016c1ef0` optionally GETs tuple INFO
before running the same poll. The message "VF Tuple dependent VF curves for
every clock is not generated" is therefore a readiness timeout, not tuple
choice logic.

The R570 relation group is nevertheless useful for a different, narrower algorithm. Its
`0x202c5b28 -> 0x202c5c76` point evaluator returns an integer u16 MHz plus u32 voltage.
Functions `0x202c50a4` and `0x202c52d2` perform upper-midpoint binary searches over the
relation bank, inspect an adjacent point at a boundary, and resolve voltage-to-frequency
and frequency-to-voltage respectively. `0x202bba02` maps a primary-bank point into each
secondary bank by relative index. This same-generation relation-search math is now an
executable, separately scoped solver; it is not used as evidence for group-`0x11` tuple
selection. See `R570_PMU_VF_RELATION_SEARCH_20260816.md`.

## VFE graph

VFE INFO reports 75 valid objects, indexes 0..74:

| Public type | Count | Recovered role |
|---:|---:|---|
| 2 | 13 | product |
| 3 | 8 | sum |
| 8 | 6 | temperature input |
| 9 | 1 | voltage input |
| 10 | 1 | caller input |
| 13 | 46 | external/private input |

For types 2 and 3, the little-endian IDs at INFO `+4` identify both operands. All 21
derived nodes are:

```text
8=sum(3,7)             18=prod(14,17)         20=prod(18,19)
21=sum(20,14)          45=prod(14,44)         46=prod(14,15)
47=prod(15,44)         51=prod(22,50)         52=sum(51,49)
53=prod(49,50)         55=sum(53,54)           57=prod(14,56)
58=prod(57,19)         59=sum(58,14)           68=prod(14,67)
69=prod(68,19)         70=sum(69,14)           71=prod(15,50)
72=sum(71,16)          73=prod(43,50)          74=sum(73,15)
```

Temperature objects are 15=channel1, 16=channel0, 22/43=channel5, 49=channel4 and
54=channel3. Object 44 is voltage and 48 is caller-supplied. Current CONTROL object 50
contains two IEEE-754 `-1.0` values. With the CONTROL lower clamps of the sum objects:

```text
VFE52 = max(0, temp4 - temp5)
VFE55 = max(0, temp3 - temp4)
VFE72 = max(0, temp0 - temp1)
VFE74 = max(0, temp1 - temp5)
```

The graph topology, object types, operand IDs, clamps and VFE50 constant are direct
read-backs. Exact signed multiplication rounding/saturation on the current PMU remains a
parameter; the simulator labels its deterministic Q8.8 half-away implementation as such.

## Runtime discriminator: natural 30 C transition

No workload was started. During ordinary CPU-side analysis, public thermal channel 1
naturally crossed the 30 C tuple boundary:

| therm channel 1 | NVD rel14 | SYS rel15 | PWR rel16 | XBAR rel17 |
|---:|---:|---:|---:|---:|
| 29.39..29.63 C | tuple 46 / 2730 MHz | 67 / 2857 MHz | 88 / 2302 MHz | 109 / 2827 MHz |
| 30.99609375 C | tuple 47 / 2715 MHz | 68 / 2842 MHz | 89 / 2302 MHz | 110 / 2812 MHz |

All four tuple indexes and STATUS `+4` advanced by one at the decoded 30 C boundary.
NVD, SYS and XBAR each lost exactly 15 MHz; PWR did not change. GPC relation 13 remained
at tuple 9 and 3270 MHz because it uses internal VFE49/52/55 rather than channel 1 alone.
These five observed tuple-to-MHz pairs, plus their previous-temperature neighbors, are
stored in the model. The certificate labels them
`sparse_current_r610_runtime_observation_not_generalized`; an unseen tuple stays unknown
rather than being assigned an invented 15 MHz slope. PWR tuple 88→89 is the measured
counterexample to such an unconditional slope because both yield 2302 MHz.

A later read-back added a second independent transition. At public channel 1 =
31.34765625 C, every VFE43-dependent type-7 relation moved from tuple 130 to 131
(API40) or 151 to 152 (MCLK). Those tuple intervals constrain the otherwise private
VFE43/channel-5 value to 30..35 C. The public thermal method still returned the 255 C
unavailable sentinel for channels 3/4/5, so this is an interval observation through the
firmware selector rather than a fabricated exact temperature.

This also corrects an earlier false interpretation: STATUS `+4 = 5` was briefly treated
as a selected output value. The complete INFO ranges and the transition show it is instead
consistent with a one-based output ordinal; the selected global tuple is at `+6`.

## Why GPC, XBAR and SYS do not all equal the initially selected value

The simultaneous read-back does **not** show a post-relation GPC residual. A read-only
relation/VF-bank/relation bracket stayed stable at channel 1 = 30.47265625 C:

| Domain | relation STATUS MHz | interleaved effective bank point 126 | delta |
|---|---:|---:|---:|
| GPC | 3270 | 3270 | 0 |
| NVD | 2715 | 2715 | 0 |
| SYS | 2842 | 2842 | 0 |
| PWR | 2302 | 2302 | 0 |
| XBAR | 2812 | 2812 | 0 |

The preceding roughly 29.5 C sequential sample also matched all five endpoints at
3270/2730/2857/2302/2827 MHz. In these two observed states, type-9 relation current MHz
is therefore an exact summary of the effective V/F-bank endpoint. This does not yet prove
that it is an alias in every P-state or transition.

The saved GPC CSV showing base/effective `3225/3337` MHz belongs to an earlier controller
snapshot with a 112 MHz total curve offset. The later live bank had an endpoint of
3270 MHz and a 45 MHz total offset. Their 67 MHz difference cannot be assigned to a
same-cycle downstream client. It is evidence that the effective curve state changed
between snapshots; the exact cause remains unknown. The checked-in model deliberately
keeps the sparse relation observation separate from the older curve CSV.

“Initially selected” can still differ from realized frequency through the recovered
power candidate, keyed/client limits, propagation, V/F rail ceiling, domain-grid
normalization and P-state/context stages. The correction above only removes an invalid
cross-snapshot decomposition; it does not collapse those real stages.

Separately, the already-recovered GPC-to-XBAR propagation and shared MSVDD limits can
collapse different user XBAR offsets to the same output. That is a many-to-one constraint
effect, not evidence that the offset write was ignored. See
`bug_inverse/MULTIDOMAIN_DIGITAL_TWIN_20260816.md` for the measured +430/+440 MHz case.

## Reproduction

Build only:

```bash
cd /home/user/rt_5090_project
cc -O2 -Wall -Wextra -Werror power_cap_limit_probe.c -o power_cap_limit_probe
```

Read-only queries:

```bash
./power_cap_limit_probe --clk-vf-tuples-info-table
./power_cap_limit_probe --clk-vf-rels-info-table
./power_cap_limit_probe --clk-vf-rels-status-summary
./power_cap_limit_probe --clk-vf-rels-control-table
./power_cap_limit_probe --perf-vfe-vars-info-table
./power_cap_limit_probe --perf-vfe-vars-control-table
./power_cap_limit_probe --therm-channels-summary
```

Model verification:

```bash
cd /home/user/rt_5090_project/power_governor_reverse/bug_inverse/algorithm
python -m json.tool configs/gb202_61057_observed.json >/dev/null
PYTHONPATH=. python -m unittest discover -s tests -v
```

## Evidence boundary

Confirmed on current R610.57.04:

- public entry sizes/strides, 167 meaningful tuple entries and all relation ranges;
- all 75 VFE nodes, 21 derived operand pairs, temperature inputs, clamps and VFE50=-1;
- relation-to-domain mapping and current tuple indexes;
- the natural 30 C tuple/frequency transition;
- current relation CONTROL layout/default state and its separation from automatic STATUS;
- the GSP type-9 STATUS path inherits importer `0x0111b738`, which transports eight u16
  values from PMU BoardObj status before `0x0111b07c/0x0111e408` export them publicly;
- MODS host group enums `0x0b/0x11`, R570 PMU's exact relation identity, and absence of a
  tuple-group `0x11` registration in the R570 clear-PMU CLK dispatch table;
- R570 group-`0x0b` point output layout and the two upper-midpoint V/F relation searches;
- a stable read-only bracket in which all five type-9 relation frequencies exactly matched
  their current effective V/F-bank point 126.

Supported inference:

- relation STATUS `+6` is the active global tuple index and `+4` is the one-based
  non-default output ordinal;
- VFE52/55 are non-negative internal temperature differences;
- equal 29.5 C values for currently unreadable channels 3/4/5 replay all 18 observed tuple
  indexes. This is a parameterized witness, not a direct measurement of those channels.

Still unknown:

- current PMU VFE sampling instant, filters, exact multiplication rounding/saturation and
  boundary/dwell/hysteresis policy;
- exact runtime values for VFE43/49/52/55 because public channels 3/4/5 report the 255 C
  unavailable sentinel and VFE STATUS is unsupported; tuple indexes now bound VFE43 to
  30..35 C in the latest sample;
- meaning of type-9 STATUS `+8` (currently 78 only for GPC relation 13);
- exact lookup/interpolation that converts each selected tuple/output ordinal into the
  relation frequency outside the sparse observed bindings;
- whether relation current MHz always aliases effective bank point 126, and what changed
  the saved GPC curve state from endpoint 3337 MHz/offset 112 MHz to 3270 MHz/offset
  45 MHz; these are different snapshots, not a measured same-cycle 67 MHz stage;
- the R610 PMU implementation of CLK group `0x11`; the R570 clear firmware has no such
  group, so it cannot close current selector rounding/filter/state behavior;
- exact current CONTROL `+0x2c` name and the type-9-only `+0x2e..+0x34` semantics;
- active per-rail voltage request slots and the complete keyed-limit/P-state arbitration
  order.
