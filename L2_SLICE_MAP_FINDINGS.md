# GB202 L2 slice / memory-partition findings

Status: **relative-rollup deliverable complete; physical indexing remains an
explicit observability boundary** (updated 2026-07-13). The labels `verified`,
`inferred`, and `unknown` are used literally. In particular, this document does
not equate a PerfWorks rollup instance with a physical memory controller or an
officially named L2 slice.

## Outcome

- A runtime, allocation-scoped CUDA API now discovers or selects 48 relative
  LTS rollup classes without NCU and returns directly usable placement offsets.
  Its default is exhaustive; the optional 19 ms empirical selector fails
  closed unless exactly one of four observed maps passes a 40x timing gate.
- Same-allocation read placement reached 47.924 sectors/LTS-cycle and 47.83x
  the one-domain control with counter-uniform traffic over all 48 rollups.
- Race-free write probes measured 0.999782 sector/LTS-cycle in one calibrated
  class and 46.614 sectors/LTS-cycle over a nearly uniform 48-domain writer.
- Three 4 MiB allocation scans validated all 192 aligned 64 KiB windows; six
  checkpoints exactly matched exhaustive calibration and user data remained
  unchanged.
- Public rollups cannot reveal absolute instance indices. Therefore the
  supported primitive is `place_on_relative_class`, not a physical
  `place_on_slice`; an absolute PA-to-slice hash or MC/FBP identity map would
  require a genuinely indexed observation not available in this tool path.

## Scope and safety

- CUDA/ML-controlled allocations only; no graphics/game optimization work.
- No display-manager stop, TTY switch, display routing, iGPU/BIOS, or MIG work.
- No MMIO/PCIe-config, firmware, or VBIOS access.
- New probes cap explicit VRAM at `min(64 MiB, 1% of free VRAM)`, use a bounded
  device duration plus host watchdog, and never reset the GPU on timeout.
- Counter collection uses `--clock-control none --cache-control none`.
  Production clock locks are opt-in and always paired with `-rgc/-rmc` cleanup.

## Counter topology

### Verified

- All 64 archived GB202 `.ncu-rep` files agree on
  `device__attribute_l2s_count=96`,
  `device__attribute_num_l2s_per_fbp=12`, and
  `device__attribute_fbp_count=8`, together with a 512-bit FB bus and 96 MiB
  L2. Under Nsight Compute's attribute names this is **96 officially named L2
  slices = 8 FBP x 12 slices/FBP**.
- Thirteen archived reports with nonzero LTS counters give
  `lts__...sum / lts__...avg = 48`. Seven reports with nonzero DRAM counters
  give `dram__...sum / dram__...avg = 16`. These establish **48 LTS rollup
  instances** and **16 DRAM rollup instances**. The archive does not contain
  the brief's exact `lts__t_sectors_op_read` base metric, but other
  source-qualified and hit/miss LTS counters reproduce the LTS cardinality.
- The live topology run
  `l2_slice_re/raw/20260713T092611+0800.LGScei/` collected only
  `cycles_elapsed.{sum,avg}` for FBPA, DRAM, and LTS in the same launch. All
  three repeats returned exactly **8 FBPA rollup instances, 16 DRAM rollup
  instances, and 48 LTS rollup instances**. This is a cardinality result and
  does not correlate the identities of instances across unit families.
- Public CUPTI/NVPerf evaluation and ordinary `.ncu-rep` files expose these
  rollups, not indexed values for each hardware instance. Rollup results are
  invariant under permutation of the hidden instance labels.

### Inferred

- The simplest numerical reconciliation is two of the 96 device-reported
  `l2s` units behind each of the 48 LTS rollup domains.
- NVIDIA's local driver headers call FBPA the low-level DRAM controller and FBP
  an aggregation containing one or more FBPAs plus L2/ROP. One integer-consistent
  candidate is one observed FBPA domain per FBP, two observed DRAM domains per
  FBP/FBPA, six observed LTS domains per FBP/FBPA, three LTS domains per DRAM
  domain, and two `l2s` units per LTS domain. Cardinalities alone do not prove
  any of those cross-family edges.

### Unknown

- Whether the performance-relevant placement unit is a 48-entry LTS rollup
  domain, one of the 96 device-reported `l2s` units, or a lower bank/port unit.
- The identity mapping among the 8 FBP attributes, 8 FBPA rollups, 16 DRAM
  rollups, 48 LTS rollups, and 96 `l2s` attributes.
- The number and identity of physical memory controllers. **The 16 DRAM
  rollups are not identified here as 16 MCs.**

Consequently, the earlier statement "48 physical L2 slices is proven by
sum/avg" is narrowed to "48 LTS rollup instances is proven." The experiments
below name their observable target a **relative LTS rollup class**.

Local primary references are
`/usr/share/doc/nsight-compute/ProfilingGuide/index.html` for PerfWorks rollups,
LTS terminology, and attributes;
`/opt/cuda/extras/CUPTI/doc/html/main/main.html` for the lack of public indexed
hardware-unit collection; and the local NVIDIA `ctrl2080fb.h` for FBP/FBPA and
RM topology field definitions.

## Counter path and observation semantics

### Verified

- `l2_slice_re/slice_probe.cu` issues explicit `ld.global.cg.u32`, keeps a case
  inside one allocation, and pairs probes with equal-duration compute-only
  controls. `l2_slice_re/run_profile.sh` archives the report, raw CSV, console
  output, GPU state, exact command, exit code, and parsed rollups.
- The live path-validation run
  `l2_slice_re/raw/20260713T093003+0800.0XFeQ4/` observed a zero
  source-qualified baseline, `max=sum` for a single-offset probe, recorded
  loads and source reads agreeing to within 0.1%, an L2 hit fraction of 1.0,
  and 48 LTS rollup instances. Thus the selected counter path measures the
  intended warm L2 reads in this probe.
- For equal traffic, concentration `max/avg` has ideal values 48 for one active
  rollup domain, 24 for two, and 1 for uniform traffic over all 48. The reports
  retain `sum/avg/min/max`, hit/miss counts, recorded loads, and controls; the
  concentration is a relative-equivalence observation, not an indexed ID.

### Limitation

`max(probe) - max(background)` is not the maximum of a true per-instance
difference. Duration-matched controls bound noise but cannot reconstruct hidden
indexed counters. Relative same-domain tests therefore cannot reveal an
absolute LTS number. If an LTS rollup combines two official `l2s` units, these
rollups also cannot label or directly distinguish that pair.

## Relative address mapping

### Verified: single-bit tests

The five live batches under `l2_slice_re/raw/` beginning at `093542`, `093725`,
`093837`, `093945`, and `100530` tested multiple anchor groups and, for the high
bits, a 64 MiB allocation. In the tested offset window:

- toggling offset bit 7 preserved the relative class;
- toggling bit 8 changed the relative class;
- toggling bit 9 preserved the relative class; and
- toggling each bit from 10 through 25 changed the relative class.

These are single-bit effects at the tested anchors, not a complete physical
address dependency list. Unknown allocation base bits remain common hidden
inputs.

### Verified: stable relative invariants

- Across three new allocations, six anchors per allocation, and seven repeats
  per case (`095010`, `095031`, and `095051`), XOR offset masks `0x200` and
  `0x7100` always preserved the observed relative class. Their closure
  `0x7300 = 0x200 XOR 0x7100` did as well.
- Other tested composite masks, including `0x8900`, `0x8b00`, `0xf800`, and
  `0xfa00`, did not remain invariant across allocation runs. The `0x100`
  negative control consistently changed class.

The stable masks are verified members of the observed offset-equivalence
kernel over these tests. They are not asserted to be its complete basis, and
they do not identify an absolute hardware slice.

### Verified: full relative maps and in-process recalibration

Runs `095257`, `095937`, and `100239` each exhaustively compared all 2,016
pairs among 64 quotient representatives, plus controls. Each allocation
produced exactly **48 relative LTS rollup classes**:

- 32 representative classes were singletons and 16 were pairs;
- every paired representative differed by XOR `0x8800`; and
- after expanding representatives with the stable masks, the saved map has 256
  offsets: 32 classes of size 4 and 16 classes of size 8.

Which `0x8800` pairs merged depended on allocation state. In the current
quotient enumeration the merging selector values were either
`A={1,4,8,d}` or `B={0,5,9,c}`. This A/B selector is a description of the
relative tables, not a physical LTS label or a decoded hardware selector.

Run `102225` repeated the same 2,016-pair calibration inside the eventual
bandwidth process. It used three 1 ms same controls and three known-different
controls, classified a pair only outside a wide dead zone between their load
throughputs, and rejected the run unless it found exactly 32 singletons, 16
doubletons, 48 classes, and no ambiguous pair. The accepted calibration found
16 same edges and constructed 48 representatives without freeing or replacing
the CUDA allocation. This closes the cross-process gap: the table used by the
final bandwidth kernel was learned from the same live allocation.

After the reusable API refactor, unlocked qualification run `104317` added
controls after the pair sweep and rechecked every tentative same edge twice.
It again accepted exactly 32 singletons plus 16 doubletons with no ambiguous
pair, and the final adaptive set had `min/avg=max/avg=1` in all three NCU
repeats. In this allocation, however, **all 16 doubleton XOR deltas were
`0x8900` rather than `0x8800`**. Thus allocation dependence changes more than
the previously observed A/B phase; a fixed fold delta is not portable either.

### Verified: allocation dependence

Six fresh-allocation runs from `094630` through `094645` tested high masks
`0x30000` and `0xc0000`. Both masks preserved class in the first allocation and
changed class in the subsequent allocations. The three exhaustive maps also
changed between selector sets A and B. Therefore a relative table learned for
one device allocation is **allocation-bound**; the current offset-only mapping
is not portable to a new allocation.

### Inferred

- The repeatable masks plus per-allocation single-delta structures (`0x8800`
  in three full maps, `0x8900` in `104317`) are consistent with an affine/XOR
  substructure followed by an allocation-dependent non-binary selection or
  fold. Neither delta is a portable hash constant.
- A pure GF(2) linear map cannot have exactly 48 nonempty outputs because its
  image size must be a power of two. A 48-way model needs an additional factor
  or reduction, for example a `16 x 3` organization, a fold, range reduction,
  or lookup-like selector.
- Within an allocation, high physical-address bits act like common hidden
  state in relative comparisons. Their effect is a plausible explanation for
  the A/B and high-mask changes, but the current data do not distinguish base
  physical address, page placement, or another allocation-dependent input.

### Observed four-state fold model for bits 8--15

The stable kernel permits a six-bit quotient coordinate for a 256-byte chunk.
For allocation-relative address bits `b8..b15`, one convenient basis is:

```text
q0 = b8 xor b14
q1 = b10
q2 = b11
q3 = b12 xor b14
q4 = b13 xor b14
q5 = b15
```

Here `b9` is eliminated by stable mask `0x200`, and `b14` is eliminated through
`0x7100 = b8 xor b12 xor b13 xor b14`. This coordinate is a quotient label,
not a hardware selector output.

The allocation cohorts use six simultaneously alive 4 MiB buffers, so their
device VAs are exactly 4 MiB apart. The byte-delta pattern commonly repeats
after three allocations (12 MiB), with one `0x8900` state and two `0x8800`
states per group. Exhaustive selector fitting has now observed four distinct
fold states:

| State | quotient delta | byte delta | folded canonical-orbit condition |
|---|---:|---:|---|
| A | `0x25` | `0x8900` | parity(`0x1d & q`) = 0 |
| B | `0x25` | `0x8900` | parity(`0x1d & q`) = 1 |
| C | `0x24` | `0x8800` | parity(`0x07 & q`) = 0 |
| D | `0x24` | `0x8800` | parity(`0x07 & q`) = 1 |

The canonical endpoint has `q5=0`. Each state folds exactly 16 of the 32
delta-orbits and leaves the other 16 orbits as two distinct classes. Therefore
each state produces 16 doubletons plus 32 singletons, exactly 48 classes. These
four pairings are consistent with a two-bit prevalue followed by a three-way
reduction, but that hardware interpretation remains inferred.

The repeated **delta** cycle within cohorts is verified, but selector phase can
change between successive delta cycles. The full state is not a pure function
of visible VA modulo 12 MiB: independent cohorts shift both delta and selector
phase. Immediate free/reallocate run `110344` reused the exact same VA three
times and retained `0x8900` all three times, but likely reused backing as well;
it does not establish map persistence after arbitrary reuse.

`l2_slice_re/observed_fold_model.hpp` exposes these four candidate relative maps
and their quotient conversion. The optional `observed_fold_fast` API measures
all four maps and succeeds only when exactly one exceeds a 40x
spread/concentrated threshold. After fixing an offline parity implementation
bug that had safely caused rejection, held-out cohorts `112303`, `112356`, and
`112507` matched fast and exhaustive maps on all 18 allocations and covered all
four states. The default remains exhaustive because this is a finite observed
model, not a complete physical-address hash.

Three fresh-process 4 MiB scans (`113230.window_scan`, `113326.window_scan`,
`113602.window_scan`) then calibrated every 64 KiB-aligned window. All 192 fast
selections succeeded and covered states 0--3 with counts `62,66,41,23`.
Selected candidates measured 43.122--43.697x concentrated throughput, while
all rejected candidates measured 18.821--18.917x. At six first/middle/last
checkpoints, the fast and exhaustive maps were exactly equal. The final scan
also verified 3,072 placement-helper pointers, an exact-minimum 64 KiB
allocation, two invalid-window rejection cases, and unchanged user contents.

In each scan, the **delta family** had an exact three-window (192 KiB) period:
the `0x8900` family occupied one residue modulo three and `0x8800` occupied the
other two. The occupied residue shifted from 0 to 1 to 2 across the three fresh
allocations. The selector phase, and therefore the complete four-state
sequence, did not share that period. This is stronger evidence for the
three-way reduction component, but remains an allocation-relative observation;
it is not a physical-address formula or an identified hardware selector.

### Unknown

- The complete physical-address hash, the physical addresses of CUDA virtual
  pages, and the highest physical address bit consumed by the selector.
- Absolute LTS IDs, the mapping from a relative class to any FBP/FBPA/DRAM
  instance, and any split within a two-`l2s` LTS rollup domain.
- Whether the relative map remains stable across page migration, regions beyond
  the tested 4 MiB, contexts, boots, or driver/GPU revisions.

## Bandwidth experiments

All values below are verified observations for the named run. Each cell is
`GB/s / total source-read sectors per LTS cycle`; concentration is shown in
parentheses where it matters.

| Run and kernel | one class | two classes | raw 64 offsets | spread A | spread B | in-process adaptive spread |
|---|---:|---:|---:|---:|---:|---:|
| `100837`, 1 block/SM | 77.90 / 1.000 | 155.67 / 1.998 | 858.89 / 11.033 | 851.97 / 10.942 | 854.21 / 10.972 | -- |
| `101027`, 6 blocks/SM, scalar | 77.93 / 1.000 | 155.01 / 1.988 | 2134.59 / 27.418 (1.5) | 1600.45 / 20.562 (2) | 3096.32 / 39.796 (1) | -- |
| `101406`, 6 blocks/SM, 4-way ILP | 77.94 / 1.000 | 155.02 / 1.989 | 2139.13 / 27.474 (1.5) | 1606.61 / 20.630 (2) | 1606.82 / 20.633 (2) | -- |
| `102225`, 6 blocks/SM, 4-way ILP | 77.91 / 1.000 | 154.95 / 1.988 | 2137.50 / 27.479 (1.5) | -- | -- | **3726.11 / 47.924 (1)** |

### Verified conclusions

- The controlled one-class case repeatedly delivered about **77.9 GB/s** and
  one source-read sector per LTS cycle. The controlled two-class case delivered
  about **155 GB/s** and two sectors per LTS cycle. Its concentration changed
  from 48 to 24 as expected. This is reproducible near-linear scaling from one
  to two **relative LTS rollup domains**, not proof of one/two physical slices.
- Raising concurrency from 1 to 6 blocks/SM increased raw-64 throughput from
  858.9 GB/s to about 2.135 TB/s. The later 4-way-ILP run reproduced the scalar
  run's one-, two-, and raw-64 results closely.
- In `101027`, allocation-specific `spread B` achieved concentration 1 and
  3.096 TB/s, i.e. counter-uniform traffic across all 48 LTS rollup domains in
  that run. `spread A` did not match that allocation.
- In the latest `101406` allocation, both previously generated spread tables
  had concentration 2 and only about 1.607 TB/s. They therefore did not produce
  a uniform 48-domain spread on that allocation. This independently validates
  the allocation-bound limitation and falsifies use of A or B as a portable
  `spread_across_all_slices` primitive.
- In `102225`, the in-process adaptive calibration produced 48 unique offsets.
  Across all nine 10 ms measurement repeats, both `min/avg` and `max/avg` were
  exactly 1.0 over 48 LTS rollup instances. Median throughput was **3.726
  TB/s**, median aggregate rate was **47.924 source-read sectors per LTS
  cycle**, and the hottest instance delivered 0.9984 sector/cycle. Throughput
  was 47.83 times the same-run one-domain control, with a coefficient of
  variation of 0.017%. This is a same-allocation, counter-uniform 48-domain
  placement demonstration.
- The reported GB/s is 32-byte LTS-sector service bandwidth derived from the
  source-qualified counter, not DRAM bandwidth and not four-byte `u32` useful
  payload bandwidth. The result is also not an absolute physical-slice label.

### Inferred / not established

- Approximately 77.9 GB/s and one sector/LTS-cycle is an empirical saturation
  rate for one observed rollup domain under this read kernel and clock state.
  It is not yet assigned to an official `l2s`, MC, FBP, bank, or port.
- The 3.096 TB/s prebuilt-table result and 3.726 TB/s adaptive result
  demonstrate allocation-specific placement wins. The latter is within 0.16%
  of 48 aggregate sectors/LTS-cycle, but neither result identifies 48 physical
  slices or a universal DRAM peak.
- `raw64` concentration 1.5 and the map structure indicate substantially wider
  distribution than the one/two controls, but a scalar concentration alone
  does not reveal every hidden per-instance count.

## Aggregate LTS write ingress

### Verified

- `write_stream_kernel` uses `st.global.cg.u32`. Each of the 8,160 active
  warps owns 32 disjoint 128-byte lines, for a 33.4 MiB working set with no
  cross-warp writer race. The kernel uses 37 registers and no
  local/shared/stack memory; SASS contains four
  `STG.E.STRONG.GPU` instructions in the write kernel only.
- Unlocked one-pass validation run `105021` had zero source-qualified baseline
  writes and exactly one LTS TEX write sector per recorded store in all three
  repeats. Across 48 rollup instances, `min/avg` stayed at 0.9962--0.9964 and
  `max/avg` at 1.0049--1.0062. Median aggregate rate was 46.164
  sectors/LTS-cycle and 3.590 TB/s of 32-byte sector service.
- Locked run `105043` used the same 2.895 GHz graphics and 14.001 GHz memory
  settings as the read experiment and restored both locks successfully. Across
  nine 10 ms repeats it retained one sector/store, zero health failures,
  `min/avg=0.9971`, and `max/avg=1.0047`. Median aggregate write ingress was
  **46.614 sectors/LTS-cycle** and **3.626 TB/s**, with 0.044% throughput CV.
  This is 97.3% of the `102225` adaptive read result (47.924 sectors/cycle,
  3.726 TB/s). Averaged over the 48 counter domains it is about 0.971 write
  sector/LTS-cycle/domain.
- Because every instruction stores one four-byte word but touches a 32-byte
  sector, 3.626 TB/s is sector service bandwidth; the corresponding useful
  `u32` payload rate is about 453 GB/s.
- `class_write_kernel` independently constructs 16 unique 128-byte lines in
  one calibrated relative class: two quotient representatives from a
  doubleton, four stable-kernel variants each, and the verified-same bit-7
  line pair. Each of 16 warps owns one line and cycles over its four sectors;
  there is no cross-warp line sharing or data race. SASS has four
  `STG.E.STRONG.GPU` instructions, 14 registers, and no local/shared/stack
  memory.
- Unlocked exploratory run `114720.class_write` established the signal shape;
  locked production run `114835.class_write` supplies the clean result. For
  the tested address subsets in this allocation, read-calibrated equivalence
  was consistent with write-counter equivalence. All nine locked single-class
  samples had one write sector per recorded store, `min/avg=0`, `max/avg=48`,
  and zero health failures. The median measured one-domain rate was
  **0.999782 write sector/LTS-cycle**, or **78.140 GB/s** of sector service.
- A same-run control used one line from each of 16 read-calibrated classes. It
  retained one sector/store and measured `max/avg=3.000006 = 48/16`, consistent
  with 16 distinct, near-equally loaded anonymous write rollups. With only two
  global blocks, this control was instruction-issue limited at 1.185
  sectors/LTS-cycle; it is a subset routing check, not a 16-domain
  peak-bandwidth measurement.
- The measured one-domain read and write ingress rates are both approximately
  one sector/LTS-cycle. The separately qualified one-domain and near-uniform
  aggregate write rates have a 46.6x cross-kernel endpoint ratio, consistent
  with wide domain parallelism. The endpoints change warp count, working-set
  size, grid size, and placement, so this ratio does not isolate domain count
  as a same-kernel causal speedup or establish a hardware peak.

### Descriptive validation and limits

Run `105207` collected write requests, hit/miss, total LTS writes, and DRAM
bytes. It required five replay passes, so its counters describe the path but
are not treated as one synchronous ratio. The L1TEX store-request and LTS TEX
write-request totals agreed, write misses were zero, and approximately 4.28 GB
of LTS sector traffic accompanied only 23.7 MB of DRAM writes and 1.26 MB of
DRAM reads during the profiled write kernel. This is consistent with repeated
updates to resident dirty L2 lines; it does not measure delayed dirty eviction
or establish DRAM writeback bandwidth.

These write results concern L1TEX-source LTS ingress into anonymous rollup
domains. They do not identify a physical slice or official `l2s` write port,
and they do not measure dirty eviction or DRAM writeback.

## Current API boundary and remaining work

The evidence supports an allocation-scoped primitive such as
`place_on_relative_class(allocation, class_id)`. Run `102225` demonstrates a
correct in-process `spread_across_observed_classes` workflow: calibrate the
same live allocation, require the exact 48-class structure, select one
representative per class, then verify `min/avg=max/avg=1`. The names
`place_on_slice(..., physical_id)` and a portable, calibration-free
`spread_across_all_slices` remain unsupported.

The implementation now shares this logic between the executable and
`l2_slice_re/adaptive_placement.hpp`. The directly callable wrapper in
`adaptive_placement_cuda.cuh` supplies scalar-offset `ld.global.cg` kernels and
needs no runtime NCU session. It repeats controls before and after the full
pair sweep, rechecks every tentative same edge twice, validates at least a 40x
spread/concentrated timing ratio, and returns a base-address-bound
`RelativeClassMap` only after the exact 48-class structure passes.
`l2_slice_re/placement.hpp` provides
`place_on_relative_class` and `spread_across_observed_classes`; it rejects a
different allocation base. These APIs intentionally expose relative class IDs
only.

Run `104317` is the post-refactor qualification artifact. It verifies that the
shared API's before/after controls and same-edge rechecks still yield a
counter-uniform 48-representative set while correctly accommodating a new
allocation-specific `0x8900` fold delta.

Independent API qualification run `110028.api` profiled only the six final
validation kernels. The example returned 48 classes, passed a 43.60x runtime
speedup gate, and preserved every byte of its initialized 4 MiB allocation.
All three NCU spread samples used one replay pass and measured
`min/avg=0.999983`, `max/avg=1.000542` across 48 LTS rollup instances. Thus the
callable API, not only the research probe, has a counter-verified
same-allocation spread primitive.

Fast-mode qualification `112606.api_fast` selected state D with a runtime
43.59x speedup. In all three NCU repetitions, the selected candidate measured
`min/avg=0.999982--0.999983` and `max/avg=1.000542--1.000543`; each of the three
rejected candidates had an empty rollup (`min/avg=0`) and approximately
`max/avg=2`. Every action used one replay pass.

The window-scoped API was subsequently exercised over all 64 aligned windows
of three fresh 4 MiB allocations (`113230`, `113326`, `113602`): 192/192 fast
decisions succeeded and six edge/middle exhaustive checkpoints matched
exactly. Returned offsets remained relative to the allocation base, all checked
placement pointers stayed inside their chosen windows, and contents remained
unchanged.

Remaining work is to:

- qualify the 19 ms observed-fold fast selector across contexts, boots, and
  driver revisions; keep exhaustive calibration as the compatibility default;
- test read/write behavior beyond the qualified 4 MiB region, page migration,
  persistence, and bank/set/way effects without assuming an absolute LTS label;
- seek an indexed or otherwise independent observation before correlating
  relative classes with FBP, FBPA, DRAM, MC, or the 96 official `l2s` units;
  and
- compare candidate fold/hash models on held-out allocations rather than
  presenting the observed relative table as a complete physical-address hash.

## Live raw evidence index

- Topology: `20260713T092611+0800.LGScei`
- Counter-path validation: `20260713T093003+0800.0XFeQ4`
- Bits 7--25: `093542`, `093725`, `093837`, `093945`, `100530`
- Allocation dependence: `094630`, `094633`, `094636`, `094639`, `094642`,
  `094645`
- Stable masks: `095010`, `095031`, `095051`
- Full maps: `095257`, `095937`, `100239`, `102225`, `104317`
- Bandwidth: `100837`, `101027`, `101406`, `102225`
- Write ingress: `105021`, `105043`; descriptive write path: `105207`
- Concentrated write ingress exploration: `114720.class_write`; clean locked run:
  `114835.class_write`
- Callable API qualification: `110028.api`; fast qualification: `112606.api_fast`
- Allocation reuse: `110344.reuse`; 4 MiB-spaced cohorts: `110441.cohort`,
  `110532.cohort`, `110712.cohort`; held-out fast/exhaustive cohorts: `112303`,
  `112356`, `112507`
- 4 MiB window scans: `113230.window_scan`, `113326.window_scan`,
  `113602.window_scan`

All shortened timestamps in this index refer to directories under
`l2_slice_re/raw/` on 2026-07-13 with the `+0800` timezone suffix.
