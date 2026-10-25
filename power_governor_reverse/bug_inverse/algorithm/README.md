# Bug-aware inverse governor — data/model/solver prototype

This directory is deliberately dependency-free (Python standard library only).
It does not write GPU state.

## 1. Canonicalize legacy runs

```bash
python canonicalize.py ../../../benchmark_logs \
  --output /tmp/gpu-canonical.csv --report /tmp/gpu-canonical-report.json
```

The canonicalizer accepts a run, multiple runs, shell-expanded globs, or a root
containing runs. It prefers `power-policy0-dynamic.csv` timestamps as anchors,
performs bounded absolute-nearest joins, records signed per-source skew, and
leaves missing sources empty. Legacy `telemetry.csv`/NVML clock is labelled as
such; `clock-hardware.csv` contains XBAR/SYS but no direct GPC clock.
Use `--scene-only` to honor each run's `scene_start_epoch.txt` and
`scene_end_epoch.txt` when those files exist. The report includes coverage,
median/p99/max absolute timestamp skew for every joined source.

`--candidate-field NAME` is intentionally explicit. The tool will not silently
rename `est_freq0_mhz` to a pre-DG0 candidate. Without that mapping and a
winning-client observation, voltage order is unidentifiable.

The reader also accepts unified JSONL `schema_version=1` records in canonical
form or envelopes containing `values`, `decoded`, and/or `timestamp.epoch_s`.
Passing an actual collector JSONL to `canonicalize.py` emits canonical CSV;
`clk_gpc_pre/post` become midpoint GPC plus signed drift, half-range
uncertainty, and bracket duration. The PCI `00000000:01:00.0` nvidia-smi row is
selected when several GPUs are present.

## 2. Compare four hypotheses

```bash
python compare_models.py /tmp/gpu-canonical.csv --output /tmp/gpu-models.json
```

The report compares voltage associations with final GPC, DG0, an explicitly
observed pre-DG0 candidate, and an asymmetric first-order hold on final GPC.
Every source uses a train-only 15 MHz binned, weighted-PAVA monotone step map
with 5 mV output quantization; a linear fit remains as a baseline. It reports
chronological/whole-run held-out error, fraction within 5 mV, and AIC/AICc/BIC.
These are predictive comparisons, not causal identification.
For collector data, select the response explicitly, for example
`--voltage-field nvvdd_target_mv` for rail-request order or
`--voltage-field policy_sensed_voltage_mv` for sensed-voltage association.
The report records `response_field`; it never silently substitutes sensed
voltage for a target request.
For pre/post direct-clock samples, `--max-clock-uncertainty-mhz 15` excludes
brackets whose half-range is larger than 15 MHz (and reports how many rows were
excluded); the canonical CSV retains all raw midpoint/drift/uncertainty fields.

## 3. Constrained discrete inverse query

Observed rows (diagnostic only):

```bash
python solve_inverse.py --candidates /tmp/gpu-canonical.csv \
  --target-mhz 3300 --voltage-limit-mv 1080 --power-limit-w 800 \
  --output /tmp/gpu-observed-query.json
```

Verified discrete control grid:

```bash
python solve_inverse.py --grid tests/fixtures/verified_grid.json \
  --target-mhz 3200 --voltage-limit-mv 1080 --power-limit-w 800 \
  --output /tmp/gpu-grid-query.json
```

The solver rejects any grid axis not explicitly marked `verified`. An
`infeasible` result is scoped to the enumerated discrete validity domain; it is
never presented as global physical impossibility. The included grid is purely
synthetic and makes no claim about verified GB202 control bounds. A grid must
also cite its baseline, each control axis, and a non-empty validity domain.
For collector observations, `--voltage-field nvvdd_target_mv` makes the 1080 mV
constraint apply to the rail target rather than the legacy/sensed `voltage_mv`;
the selected clock, voltage, and power fields are recorded in the query.

## Test

```bash
PYTHONPATH=. python -m unittest discover -s tests -v
PYTHONPATH=. python -m pytest -q
```

Sparse policy logs can be audited separately without pretending that their
sample-level gain is a PMU-cycle coefficient:

```bash
python fit_dg0_filter.py /path/to/run-or-policy-csv --pmu-period-ms 20
```

The report fits up/down effective gains, measures sampling alias, and always
states whether a per-cycle Q12 coefficient is identified. The current digital
twin replays the recovered GB202 R570 U16-Q12 `clkUpScale`/`clkDownScale`
arithmetic exactly with the current R610 status readback values, `0x0800`
(up) and `0x1000` (down). Optional dwell and hysteresis fields remain
separately labelled as extra parameterized hold layers.

## 4. Multi-domain digital twin

`multidomain_twin.py` composes the measured GPC/XBAR/SYS/NVD F(V) banks,
bit-exact 2X dynamic-power arithmetic, DG0, client/PERF bounds, the recovered
R610.57 type-3 U16.16 ratio/reciprocal representation, GB202 R570 PMU
half-up multiplication and directional domain-grid normalization, shared MSVDD type-5
interval constraints, the recovered R610.57 ten-slot voltage
arbiter, integer rail quantization and domain-specific clock grids. It supports
`simulate`, two-control `compare`, and enumerated
`solve`; see `../MULTIDOMAIN_DIGITAL_TWIN_20260816.md` for commands and current
evidence boundaries.
It is a structure/constraint simulator and scoped enumerated inverse planner,
not a claim that all private GSP state is quantitatively identified. In
particular, Phase-9 A-B-A data still require per-domain upstream request
winners, workload-conditioned clock-client/duty state and the aggregate MSVDD
request winner to predict the full response without observed literals. See
`../../PHASE9_QUANTITATIVE_IDENTIFICATION_STATUS_20260817.md`.
Every simulated domain also emits an ordered decision certificate: the curve
candidate, each upper/lower-bound candidate with before/after/changed state,
the winner chain, and the final decisive constraint.  This distinguishes
many-to-one saturation from a control that was never applied.

### Target/constraint to GSP input plan

The multi-domain `solve` command accepts a target and constraints in its grid
JSON. The caller also supplies the discrete control values that the solver is
allowed to consider; every axis must be explicitly marked `verified`:

```json
{
  "base_control": {
    "clock_max_mhz": {"gpc": 3000},
    "gpc_xbar_ratio": 1.0,
    "rail_min_mv": {"nvvdd": 800, "msvdd": 870},
    "rail_max_mv": {"nvvdd": 980, "msvdd": 1000}
  },
  "axes": [
    {
      "path": "freq_offset_mhz.xbar",
      "values": [390, 420, 430],
      "verified": true
    }
  ],
  "target_clock_mhz": {"gpc": 3000, "xbar": 3000},
  "clock_tolerance_mhz": 8,
  "voltage_limit_mv": {"nvvdd": 980, "msvdd": 1000},
  "allowed_stability_status": ["pass_no_error_observed"]
}
```

Each candidate now contains both `full_control` and `gsp_input_plan`. The plan
compiles known controls to their actual surfaces: GPC/MCLK maxima to NVML,
clock-domain offsets to `CLK_DOMAINS_SET_CONTROL 0x2080d01c`, relation 0 ratio
to `CLK_PROP_TOP_RELS_SET_CONTROL 0x2080d084`, rail limits to the recovered
voltage wrapper, and per-tuple signed-kHz offsets to `0x2080d047`. Internal
inputs such as `post_voltage_clock_max_mhz` are explicitly labelled observed
private state rather than emitted as fictitious setters.

The plan is a recipe, not an executor. Model feasibility does not establish
current-session authorization or stability; a live executor must still save
full preimages, SET, independently GET/read back every field, run a bounded
workload, and restore.

The current-contract example is
`examples/ptx_xbar_solver_grid_current_contract.json`. With the pinned rail-1
maximum of 1000 mV, the old GPC/XBAR 3000/3000 target is infeasible inside the
enumerated stability-qualified offsets: the closest stability-allowed point is
XBAR +430 MHz, which predicts GPC/XBAR 3000/2872 MHz and misses the XBAR target
by 120 MHz after tolerance. The older 1065 mV file remains only as a historical
regression fixture and is explicitly marked stale for the current contract.

Per-domain curve-coordinate voltage controls use the unambiguous canonical
field `domain_vf_voltage_offset_mv`. They are not aggregate rail/VOUT offsets.
`composite_msvdd_curve_offset_mv` is only an input macro that expands to equal
XBAR/SYS/NVD values, which the compiler emits as one full `0x83c`
`CLK_DOMAINS_SET_CONTROL` RMW with signed-uV fields at `0x090`, `0x110` and
`0x150`. `rail_min_mv`, `rail_max_mv` and output `rail_target_mv` remain
separate concepts.

Each of those three slot entries has confirmed control adoption but explicitly
unknown individual physical adoption: no single-slot physical intervention has
isolated XBAR, SYS or NVD. Physical evidence belongs to the equal-three-slot
composite at plan level. `composite_group_physical_evidence` records the tested
value, stock-ratio/no-GPC-lock L2 base and receipt, and only marks a candidate
physically validated when that exact base also matches. It never transfers the
group observation to a ratio-1 or GPC-locked candidate.
Historical provenance is retained independently:
`observed_group_receipts` lists every physical group observation for that
composite value, while `candidate_qualifying_receipts` contains only receipts
whose complete observed base matches the candidate. A base mismatch empties
the latter and keeps candidate physical validation false without erasing the
former.

The three 2026-08-17 LACT phase-9 physical A-B-A runs are registered by
`tests/fixtures/lact_phase9_aba_manifest.json`. `gpu_inverse/aba_evidence.py`
computes one grouped `B - mean(A1,A2)` contrast per run; raw 100 ms samples are
retained for block uncertainty and are never treated as independent fit rows.
Manifest schema 2 requires every telemetry receipt to bind `domain_readback`
to the fresh `combined-readback.txt` from the same directory. It validates the
three sections of four 127-point domain banks, index/curve monotonicity, exact applied control deltas,
rail-1 target against the receipt-specific manifest expectation (995 mV for
Phase-9) and byte-identical control-blob restoration. The generic parser never
hard-codes 995 mV; replay reads the target from each STATUS section. Dynamic
baseline/restored STATUS equality is recorded but never required because
tuple/VFE state can drift. Capture time and tuple state are explicitly marked
missing rather than inferred, and snapshots are scoped to one receipt rather
than cached by driver/VBIOS. A stale global config curve is rejected as
Phase-9 evidence.

The current multi-axis example is
`examples/ptx_xbar_composite_solver_grid_current_contract.json`. Axis evidence
only establishes that a control value was adopted; it never qualifies a
Cartesian product as stable. `combination_evidence.required_controls` must
match the complete relevant control tuple, including base controls such as GPC
lock and propagation ratio. Otherwise the candidate is still simulated but is
reported as `unknown_unqualified_combination` and fails any requested stability
constraint. This prevents independent XBAR +430 and composite +20 observations
from being silently promoted into an untested (+430,+20) stability claim.
For the same GPC/XBAR 3000/3000 target, the current 3x3 grid evaluates nine
combinations and qualifies zero. The numerically closest is XBAR +450 MHz with
composite -20 mV: predicted GPC/XBAR/SYS/NVD is
3000/2932/2475/2362 MHz at 935/1000 mV, leaving a 60 MHz XBAR violation after
the 8 MHz tolerance. Its stability remains unknown because the observed
(+450,+20) phase-9 tuple used stock ratio and no GPC lock, not this target's
ratio-1/GPC-max base control.

The firmware-derived voltage core is also usable independently:

```bash
python gpu_inverse/voltage_arbiter.py \
  examples/voltage_arbiter_example.json
PYTHONPATH=. python -m unittest tests.test_voltage_arbiter -v
```

It replays ten 16-byte records, active/deferred masks, direct/source modes,
controller/record/client offsets, the later-client-wins equality rule, and the
integer grid/clamp method. Mapping that recovered controller core to each
physical rail and the current boot's live slot contents remains explicitly
parameterized.

The recovered clock submodules can also be tested independently:

```bash
PYTHONPATH=. python -m unittest \
  tests.test_clock_program tests.test_clock_propagation \
  tests.test_type5_propagation -v
```

`clock_program.py` replays the current R610 static list path from a domain's
inclusive clock-program interval through program modes 0/1/2.  Its mode-2
clock-table-row implementation includes the asymmetric frequency-to-divider
boundary, inclusive divider enumeration, u32 arithmetic, and
`floor(numerator*divider/denominator)` output.  An effective reduced ratio of
15/2 with dividers 2..466 exactly reproduces all 465 live GPC/XBAR values;
the unreduced raw row fields remain unknown.

`pmu_clock_programmer.py` closes the same-generation physical write layer from
the clear R570 PMU. It replays the object/global affine source grid at
`0x202ba5f6`, the asymmetric frequency-to-divider and inverse maps at
`0x202c2d2a/0x202c2e00`, and the two-lane saturated MMIO packing at
`0x202bbf3a`. These maps are many-to-one even after all V/F arbitration has
finished. Current R610 serializer `0x0112d0ac` maps row
`+0x21/+0x22/+0x24/+0x3e` to the 0x40-byte PMU transfer
`+0x05/+0x0a/+0x0c/+0x25`; clear-R570 importer `0x202f74d2` installs those
exact fields in the physical grid object. The checked-in config therefore uses
the current live main-domain effective ratio 15/2 for GPC/XBAR/SYS/NVD and
executes the physical projection. The unreduced factorization is still
unknown, but exhaustive comparison through 3999 MHz proves that direct 15/2
and the equivalent doubled-input 15/1 representation produce identical
divider/readback results. The downstream implementation remains a clear-R570
cross-build algorithm, not a claim that the encrypted R610 body is
byte-identical.

`vbios_clock_tables.py` now closes the ROM-side graph that precedes those
objects. The official BIT C v2 payload resolves `C+0x08` to the v0x50 Clocks
table and `C+0x0c` to the v0x50 Clock Programming table. The recovered R610
parsers prove 21-byte and 47-byte entry strides respectively. On the exact
98.02.2E.80.50 ROM, GPC/XBAR/SYS/NVD/PWR map to relationship/program rows
13/17/15/14/16, MCLK maps to 8..12, and API40 maps to 0..7. PCIe and API08 use
type-2 domain references to MCLK and API40 instead of direct rows. The parser
also reproduces the type-9 tuple banks 0..40, 41..61, 62..82, 83..103 and
104..124. `inspect_vbios_clock_graph.py` emits this graph as JSON. ROM defaults
remain distinct from runtime state: ROM GPC/XBAR maxima are 3450 MHz while
current GET_INFO reports 3495 MHz, and ROM relationship 12 is 14001 MHz while
runtime reports 15001 MHz. That measured mismatch is preserved as evidence of
post-ROM object construction/translation, not silently normalized away.

`clock_propagation.py` replays the current R610 reciprocal constructor exactly
(`floor(2^32 / ratio_raw)` with zero/overflow rejection).  It also replays the
matching GB202 R570 MODS PMU evaluator: integer-MHz U16.16 multiplication
rounds half-up, then a parameterized destination frequency-grid object (the
R570 object group is `0x7bfb0`) rounds
down on a forward edge and up on a reverse edge.  The current GB202 PMU image
and its per-domain normalization fields remain the current-specific boundary.
It also exposes the separate R570 `0x202c9662` byte-percentage projection,
including floor division and optional destination V/F reprojection; this is a
second proven many-to-one clock-domain stage whose current R610 table bytes are
not yet available.
The same module now materializes all current R610 `CLK_DOMAIN_GET_INFO` lists;
GPC/XBAR/SYS/NVD/PWR use the exact integer projection
`15+floor(i*15/2)`.  These lists provide floor/ceil brackets in every twin
trace but remain diagnostic-only until their position in every final
arbitration path is proven.

`artifacts/ptx_xbar_boundary_certificate_20260816.json` binds six raw compute
`hardware-clocks.csv` files to replayed XBAR decision certificates.  It shows
the decisive constraint changing from the 1065 mV MSVDD V/F ceiling at
+330..+420 MHz to the 1:1 GPC-to-XBAR ratio ceiling at +430/+440 MHz.  The test
suite rereads the raw CSVs, recomputes their statistics, and reruns the model.

`clock_topology.py` replays the PMU relationship walk over the current R610
top-ID 7 `domainsDstPath` matrix; the checked-in graph makes GPC->XBAR `[0]`,
GPC->SYS `[0,1]`, and GPC->NVD `[0,2]` directly inspectable in every trace.
`frequency_filter.py` replays the GB202 R570 `clkUpScale`/`clkDownScale` U16-Q12
tracker, including `mulw`, bit-11 half-up rounding, and zero-scale bypass; the
observed R610 config supplies the directly read back `0x0800/0x1000` pair.
`type5_propagation.py` replays the same-generation interval ordering:
source FREQ_TO_VOLT endpoints, target VOLT_TO_FREQ endpoints, then independent
endpoint clamp.  Current R610 private object fields and transition sequencing
remain parameterized.

`perf_change_protocol.py` replays the current R610 GSP side of the event-driven
PERF exchange exactly: the 0x214-byte type-0x0c snapshot, the 0x54-byte
type-0x0d domain-mask request, 16-domain masked result imports, and the
active/response-valid cache lifecycle.  The `Perf+0x560` post-BoardObj hook is
separately proven to be a return-zero compatibility stub in this build. It
also encodes the now-proven R570 protocol migration: 0x10-byte trigger C,
BoardObjGroup exchange, 0x214-byte large D, and 0x54-byte finalize E became
group/large C/finalize D in R610. The clear R570 PMU route and periodic solver
are recovered, while current encrypted-R610 field compatibility remains an
explicit boundary.

`pmu_voltage_matrix.py` replays the clear R570 PMU's exact 32-object by
three-rail signed matrix update: active-object and rail masks, replacement
versus wrapping-add mode, and untouched lanes. Physical current-R610 rail
names/indexes remain configuration rather than guessed constants. It also
replays `equation_output_finalize_impl`: zero-step behavior, mathematical
floor/ceil quantization for positive and negative inputs, and optional inclusive
object-range clamping.

`perf_type5_output.py` materializes the post-arbitration boundary recovered at
R570 PMU `0x202c840e`: a fixed 0x780-byte PERF/type-5 packet containing up to
seven clock domains, ten six-u32 value sets per domain, and four rail results.
The six words are the raw/bounded forms of an ordered lower/middle/upper
constraint triplet. The exact invalid-order repair and independent terminal
bound clamp are executable. R570.144 GSP `0x016254ec` is now also replayed:
it copies those six words into 0x40-byte per-client records at word indexes
`0/1/5/6/10/11`, imports non-type-5 voltage objects, and preserves the
firmware's producer/consumer mismatch where voltage indexes 4..7 alias the
next 16-byte domain preamble.

The same module replays the recovered core of GSP `0x016115f0`. After PMU
import, that path can replace the three raw endpoints from one of three local
candidate triplets, optionally pass kHz values through the clock client's
MHz-grid callback, and independently cap low/high/middle again. Therefore a
PMU-selected GPC value is not the last value in the GSP clock cache. It now
also replays current-R610 `0x01ba5814`'s gated signed-offset stage: cache words
4/9 and the selected program frequency are offset, reprojected through
`0x01ae0808`, and the result is mirrored to word 14. The two apparent R610
post-apply writers were separately resolved to no-op/predicate targets; the
physical writer is present in the clear PMU path above. Current-R610 object
values and HAL activation remain evidence boundaries rather than guessed
defaults.

`vf_relation_search.py` replays the clear GB202 R570 group-0x0b relation search:
both FREQ_TO_VOLT and VOLT_TO_FREQ use an upper-midpoint binary search, explicitly
evaluate a neighboring point at the bracket boundary, and clamp at bank endpoints.
It also replays the cross-bank relative-index mapping and point-type-0x0c/0x0d
mode-1 voltage replacement. `VFCurve` uses this search and every digital-twin trace
exports its midpoint/comparison sequence. Exact endpoint status codes and equivalence
to current R610 private implementation remain outside the claim.

`domain_adjustment.py` replays the later R570 post-selection layer at
`0x202c2c28/0x202c4746/0x202c4786`: signed kHz or signed-Q12 adjustment, s16
narrowing and zero clamp, primary/secondary object selection, then a relation
reprojection after each active domain. It also replays the non-commutative
four-object order at `0x202c8fde` and the mode-1/mode-2 linked-object dispatch at
`0x202c904a`. It is tested independently but remains disabled by default because
current R610 adjustment-object values are unavailable.

`relation_arbitration.py` replays the R570 relation-range `0/0x41` control-flow
sentinel, the independent-per-relation clamp/min reduction at `0x202c40f6`, and
the terminal-bound minimum at `0x202c3fbe`. Tests preserve the otherwise easy to
miss distinction that equal clamp candidates pick the later relation while equal
terminal bounds retain the earlier relation.

`vfe_tuple.py` reconstructs the current R610.57 public VFE graph and VF-tuple
banks as a stateful diagnostic selector. The checked-in config contains all 75
VFE variables, 21 recovered sum/product edges, seven tuple banks covering all
18 relations and all 167 meaningful tuple entries. A natural channel-1
transition across 30 C replays the observed NVD/SYS/PWR/XBAR tuple changes and
their relation-frequency changes. Sparse measured tuple-to-MHz bindings are
emitted in the certificate; unseen tuples are not interpolated (PWR 88->89 is
already a same-MHz counterexample). Static host/PMU matching identifies VF
relations as CLK group 0x0b, while the optional tuple group is 0x11; the R570
clear-PMU dispatch table has no 0x11 entry, so it cannot stand in for the
current selector. Current-PMU product rounding,
sampling/filtering and boundary tie-breaking remain explicitly parameterized;
this stage is not yet allowed to drive simulated clocks or voltages. Full ABI,
domain mapping and reproduction notes are in
`../../GSP_61057_VFE_TUPLE_MODEL_20260816.md`.

`vf_tuple_control.py` adds the byte-exact Pstate-5 tuple frequency-offset
control ABI recovered from the R570.151 MODS `Perf50` vtable. It reproduces the
0x2048-byte GET/SET payload, signed-kHz entry field at
`0x50 + tuple_index * 0x10`, the 512-entry bound and clock-domain tuple-range
validation. The digital-twin trace emits these writes as an offline certificate;
it does not send either RM method or assume the still-encrypted R610 PMU apply
ordering.
