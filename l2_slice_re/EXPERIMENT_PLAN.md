# Live experiment gate and sequence

No command in this file is to be run while Minecraft or another intentional GPU
workload is active.  The user must explicitly confirm that it is safe to start.
Closing applications is manual; the scripts never kill processes or alter the
desktop/display stack.

## Offline readiness (complete)

- `sm_120` compile succeeds.
- SASS contains `LDG.E.STRONG.GPU` only in `read_set_kernel`; the compute control
  has no `LDG`.
- Read kernel uses 35 registers, no local/shared/stack memory. On sm_120 this
  permits exactly 6 resident 256-thread blocks/SM; startup also verifies the
  actual limit with `cudaOccupancyMaxActiveBlocksPerMultiprocessor`.
- Shell syntax, strict CLI rejection, wide/long NCU CSV parsing, paired-control
  joining, topology parsing, GF(2) nullspace fitting, and block-bootstrap pair
  inference have offline tests.
- Explicit allocation cap is `min(64 MiB, 1% free VRAM)`; requested kernel time
  is capped at 30 seconds/process; per-kernel device duration and host watchdog
  are both bounded.

## Phase 0: post-confirmation smoke (no counters, no locks)

```bash
timeout --signal=TERM --kill-after=2s 10s \
  l2_slice_re/build/slice_probe \
  --buffer-mib 4 --duration-ms 1 --timeout-ms 2000 --repeats 1 \
  --case single=0
```

Acceptance:

- exit 0 within 10 seconds;
- one baseline and one probe JSON launch;
- no CUDA/watchdog error;
- no unexpected persistent change in clocks, memory use, thermals, or active
  compute processes in before/after read-only checks.

Stop immediately on a timeout, Xid, display instability, or unexplained state
change.  The code deliberately does not reset the GPU.

## Phase 1: same-launch counter topology (no locks)

```bash
l2_slice_re/run_profile.sh --metric-set topology -- \
  --buffer-mib 4 --duration-ms 1 --timeout-ms 2000 --repeats 3
```

This automatically runs only `baseline_kernel` and collects
`fbpa/dram/lts__cycles_elapsed.{sum,avg}` in the same launch.  The parser
requires one replay pass.  The completed first run returned 8, 16, and 48 in
all three repeats; the pre-run 16-FBPA candidate was falsified.

This can verify counter-domain counts.  It cannot by itself prove that a 48-way
LTS counter domain is the physical address-selector domain, nor map either
domain onto the 96 official device-attribute slices.

## Phase 2: explicit L2-path validation (no locks)

```bash
l2_slice_re/run_profile.sh --metric-set validation -- \
  --buffer-mib 4 --duration-ms 2 --timeout-ms 2000 --repeats 3 \
  --case single=0
```

Acceptance:

- LTS TEX-source reads rise strongly over the compute control;
- steady traffic is overwhelmingly L2 hits after the bounded warm portion;
- `sum/avg` consistently identifies the same rollup divisor;
- replay count and raw report are retained.  If validation needs multiple
  passes, its hit/miss results are descriptive only and are not mixed into a
  synchronous concentration verdict.

## Phase 3: control separation before any class merge

Generate a positive control and several power-of-two offset candidates.  The
first run intentionally has no claimed negative control:

```bash
python3 l2_slice_re/plan_cases.py \
  --output /tmp/l2_bit_pairs.tsv --manifest /tmp/l2_bit_pairs.jsonl \
  pair --anchor 0 \
  --candidate 128 --candidate 256 --candidate 512 --candidate 1024 \
  --candidate 2048 --candidate 4096 --candidate 8192 --candidate 16384

l2_slice_re/run_profile.sh --metric-set concentration -- \
  --buffer-mib 4 --duration-ms 2 --timeout-ms 2000 --repeats 9 \
  --cases-file /tmp/l2_bit_pairs.tsv
```

Ideal 48-domain concentration is approximately 48 for `anchor=anchor` and 24
for equal traffic to two distinct domains.  Actual controls, not those ideal
numbers, set the threshold.  Select a stable low-concentration candidate as the
tentative negative control, rerun it as `--filler`, and require the positive vs
negative block-bootstrap confidence interval to separate before calling any
query `same`:

```bash
python3 l2_slice_re/infer_pairs.py RUN/paired_controls.tsv \
  --output RUN/pair_evidence.tsv
```

Any overlap produces `unknown`; an `unknown` edge is never added to an
equivalence class.

## Phase 4: completed relative-map and bandwidth demonstration

The live runs established stable relative masks `0x200` and `0x7100`, then
exhaustively compared the 64 quotient representatives. Five in-process full
calibrations have produced 32 singleton plus 16 doubleton classes, for 48
relative LTS rollup classes. The maps are allocation-bound: three early maps
used doubleton XOR `0x8800`, while post-refactor run `104317` used `0x8900`.

Allocation cohorts resolved these observations into four affine fold states on
the six-bit quotient: two selector phases each for byte deltas `0x8800` and
`0x8900`. `observed_fold_model.hpp` implements all four. The optional 19 ms
fast selector matched exhaustive maps on 18/18 held-out allocations across
cohorts `112303`, `112356`, and `112507`, including all four states; default
mode remains exhaustive. NCU run `112606.api_fast` independently verified the
selected candidate as uniform and the other three as nonuniform.

`--adaptive-spread` now performs the exhaustive calibration before freeing the
allocation and fails closed unless it finds the exact class structure with no
ambiguous pair. Locked run `102225` selected 48 representatives and measured,
over nine repeats:

- `min/avg = max/avg = 1.0` across 48 LTS rollup instances;
- 47.924 source-read sectors per LTS cycle;
- 3.726 TB/s of 32-byte LTS-sector service bandwidth; and
- 47.83x the same-run one-domain throughput.

This completes a same-allocation `spread_across_observed_classes`
demonstration. It does not provide absolute physical slice numbers.

The callable CUDA wrapper is also complete. `adaptive_placement_cuda.cuh`
validates the allocation base, performs read-only exhaustive calibration, and
requires a 40x timing sanity check without NCU. Qualification run `110028.api`
then independently verified its returned spread with NCU:
`min/avg=0.999983`, `max/avg=1.000542` in all three one-pass repeats, while the
example confirmed user allocation contents were unchanged.

The wrapper now accepts a 64 KiB-aligned `window_offset` and returns offsets
relative to the original allocation base. Three scans (`113230`, `113326`,
`113602`) covered every aligned window in fresh 4 MiB allocations: 192/192 fast
decisions passed, all four observed states appeared, and six edge/middle
checkpoints matched full exhaustive calibration exactly. The delta family had
an exact three-window period in each allocation, but its residue shifted across
allocations and the complete four-state sequence was not periodic.

The aggregate write-ingress path is also complete at the relative-rollup
level. Race-free unique-line run `105043` measured 46.614 write
sectors/LTS-cycle (3.626 TB/s sector service), 97.3% of the adaptive read rate,
while remaining uniform to about 0.5% over the 48 rollups. It does not yet
provide a DRAM writeback rate.

Concentrated-write run `114835.class_write` supplies a clean measured
single-class ingress rate for one tested subset. Sixteen warps used 16 private
lines in one calibrated class and measured one sector/store, `max/avg=48`, and
0.999782 write sector/LTS-cycle. A 16-class control measured
`max/avg=48/16=3`, consistent with 16 distinct, near-equally loaded write
rollups. This supports read/write relative-domain equivalence for the tested
address subsets and a single-domain write rate symmetric with the approximately
one-sector/cycle read result; it is not a saturation sweep or dirty-DRAM
writeback measurement.

## Phase 5 onward

1. Qualify the 19 ms observed-fold fast selector across contexts, boots, and
   driver revisions while retaining exhaustive mode as the default fallback.
2. Extend the completed 4 MiB multi-window test to larger regions, page
   migration, contexts, boots, and held-out driver revisions.
3. Fit and cross-validate the affine-plus-fold model instead of training-set
   encodings.
4. Add atomic and dirty-writeback paths, then investigate bank/set/way and
   associativity using the calibrated class pools.
5. Seek an indexed independent observation before correlating LTS rollups with
   FBP, FBPA, DRAM, MC, or the 96 official `l2s` units.

The public rollups cannot assign absolute hardware instance numbers.  A
physical `place_on_slice(..., absolute_id)` remains blocked unless an indexed
observation or separately verified topology becomes available.
