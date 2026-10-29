# GB202 L2 slice reverse engineering

This directory is the clean implementation area for `L2_SLICE_RE_BRIEF.md`.
It intentionally does not extend the old `tools/latency/slice_probe.cu`, whose
ordinary repeated loads can be captured by L1.

Current stage:

- bounded `ld.global.cg` read-set probe using one active lane per warp and a
  configurable 1--6 verified-resident blocks/SM to make a small address set
  observable;
- equal-duration compute-only background control;
- NCU rollup capture with raw report/CSV preservation;
- optional, explicit clock locks with unconditional `-rgc/-rmc` restoration;
- no display-manager, TTY, display-routing, MIG, MMIO, or firmware actions.

Build and smoke test:

```bash
make -C l2_slice_re
timeout 10s l2_slice_re/build/slice_probe \
  --buffer-mib 4 --duration-ms 1 --repeats 1 --case single=0
```

Initial unlocked counter run (safe signal validation, not a peak-bandwidth
measurement):

```bash
l2_slice_re/run_profile.sh -- \
  --buffer-mib 4 --duration-ms 5 --repeats 7 --case single=0
```

The default `concentration` metric set requests only the four rollups of one
base LTS counter, minimizing replay passes.  Use `--metric-set validation` for
the separate L2 hit/miss and total-read check.  Parsed results must report a
single replay pass before they are used as a synchronous concentration test.
The `topology` set automatically selects the compute-only kernel and collects
same-launch `fbpa/dram/lts cycles_elapsed sum/avg`; it is the first planned live
measurement for counting the three rollup domains alongside the 96-slice device
attribute. Equal cardinalities or integer divisibility do not establish a map
between the domains.

The first live cardinality run produced stable `8 FBPA / 16 DRAM / 48 LTS`
ratios in all three one-pass repeats; see
`raw/20260713T092611+0800.LGScei/topology.summary.tsv`.

Same-allocation adaptive spread is available through `--adaptive-spread`. It
first compares all 2,016 pairs among the 64 representatives of offset bits
8--15 modulo the verified stable masks. It proceeds only if the timed-load
controls separate cleanly and the result is exactly 32 singleton classes plus
16 doubletons, with no ambiguous pair. It then measures one representative per
class without replacing the allocation. Calibration and measurement are both
included in the 30-second requested-kernel-time cap.

```bash
l2_slice_re/run_profile.sh --metric-set bandwidth -- \
  --buffer-mib 4 --duration-ms 10 --calibration-ms 1 \
  --repeats 9 --blocks-per-sm 6 --adaptive-spread
```

The locked reference run `raw/20260713T102225+0800.PqI3IU/` produced 48
representatives with `min/avg=max/avg=1` in all nine repeats and reached 47.924
source-read sectors/LTS-cycle (3.726 TB/s of 32-byte LTS-sector service). This
is a relative 48-rollup-domain result, not absolute physical slice IDs or DRAM
bandwidth.

Post-refactor qualification run `raw/20260713T104317+0800.Luhz4o/` passed the
stronger before/after controls and same-edge rechecks, then reproduced
`min/avg=max/avg=1` in all three final NCU repeats. Its 16 doubletons used XOR
delta `0x8900`, whereas the earlier full maps used `0x8800`; the API therefore
discovers classes exhaustively and intentionally does not hard-code either
delta.

`observed_fold_model.hpp` contains four finite fold states now observed across
exhaustive maps and 4 MiB-spaced allocation cohorts. It converts offset bits
8--15 to the stable-kernel quotient and generates four candidate 48-class maps.
The optional `--fast` demo mode measures all four and requires exactly one to
exceed 40x. Three held-out cohorts (`112303`, `112356`, `112507`) matched fast
and exhaustive maps on all 18 allocations and covered all four states. The
strict CUDA API remains the default because the state set is empirical.

The calibration decision logic is shared with the reusable host-side core in
`adaptive_placement.hpp`. The directly callable CUDA wrapper is
`adaptive_placement_cuda.cuh`; it supplies the timed `ld.global.cg` kernels and
does not require NCU at runtime. The API owns control separation, all 2,016 pair
decisions, end-of-run drift controls, two rechecks for every tentative same
edge, the exact 32-singleton/16-doubleton structure gate, and a final
spread/concentrated throughput check. `placement.hpp` binds the resulting map
to the original allocation address and rejects use with a different base.

```cpp
auto calibration = l2slice::find_relative_class_representatives_cuda(
    buffer, bytes, stream);

auto addresses = l2slice::spread_across_observed_classes(
    buffer, calibration.relative.map);

l2slice::CudaCalibrationOptions fast_options;
fast_options.mode = l2slice::CudaCalibrationMode::observed_fold_fast;
auto fast = l2slice::find_relative_class_representatives_cuda(
    buffer, bytes, stream, fast_options);  // optional empirical fast path

// Calibrate a later 64 KiB window of the same allocation. Returned offsets
// remain relative to buffer, not to the start of the window.
fast_options.window_offset = 2u * 1024u * 1024u;
auto later = l2slice::find_relative_class_representatives_cuda(
    buffer, bytes, stream, fast_options);
```

The wrapper accepts an sm_120 current-device `cudaMalloc` allocation base of at
least 64 KiB, rejects stream capture/interior pointers, changes only cache
residency, and uses a 10-second requested-GPU-time hard cap plus per-kernel
watchdog. It links against `libcuda` for allocation-range validation. The
production name is deliberately `relative_classes`, not `physical_slices`.
`CudaCalibrationOptions::window_offset` defaults to zero, must be 64 KiB
aligned, and must leave a complete 64 KiB window inside the allocation. Every
returned map offset is relative to the original allocation base, so it can be
passed directly to the placement helpers.
On a watchdog timeout the API does not reset the GPU and intentionally leaves
scratch alive; callers must terminate instead of freeing/reusing the possibly
still-referenced allocation (the example exits with status 124).

Build and run the minimal example:

```bash
make -C l2_slice_re build/adaptive_placement_demo
l2_slice_re/build/adaptive_placement_demo
l2_slice_re/build/adaptive_placement_demo --fast
```

Run all offline tests with `make -C l2_slice_re test`. Development-time NCU
qualification is separate from the runtime API:

```bash
l2_slice_re/validate_cuda_api.sh
l2_slice_re/validate_cuda_api.sh --fast
```

Qualification artifact `raw/20260713T110028+0800.api.mfd5M7/` reported
`contents_unchanged=true`, a 43.60x runtime spread/concentrated ratio, and in
three single-pass NCU repeats `min/avg=0.999983`, `max/avg=1.000542` for the
returned 48-address spread.
Fast qualification `raw/20260713T112606+0800.api_fast.on6VyL/` independently
showed the selected candidate at `min/avg=0.999982`, `max/avg=1.000543`, while
the three rejected candidates had `min/avg=0` and `max/avg≈2`.

Larger-region qualification uses the allocation-scoped window option:

```bash
l2_slice_re/run_window_scan.sh
```

Runs `113230.window_scan`, `113326.window_scan`, and `113602.window_scan`
tested all 64 aligned windows of three fresh 4 MiB allocations: 192/192 fast
selections succeeded, all four states appeared, and selected-candidate timing
was 43.122--43.697x versus 18.821--18.917x for rejected candidates. Six
first/middle/last checkpoints matched the exhaustive 2,016-pair map exactly.
The latest probe also rejected both invalid window forms, checked all 3,072
placement-helper pointers, accepted an exact 64 KiB allocation, and verified
that neither allocation's contents changed.

A locked production run must specify the supported ranges explicitly, for
example `--lock-gpu MIN,MAX` and `--lock-mem MIN,MAX`.  The runner installs its
restore trap before applying either lock.  Do not use a lock run if another
custom lock was already active, because the NVIDIA CLI has no reliable
read-only field for reconstructing that previous range.

The summary's `instances_sum_over_avg` is the PerfWorks rollup divisor.
`concentration_max_over_avg` is 48 for an ideal single active counter instance,
24 for two equally loaded distinct instances, and 1 for 48 equally loaded
instances.  With only rollups, subtracting background maxima is not equivalent
to per-instance subtraction; conclusions must use repeated controls and retain
the raw values.
For a uniform-spread claim, also require `raw_min_over_avg` to be 1; checking
only the maximum can miss empty counter domains.

Aggregate LTS write ingress uses a separate race-free mode. Every active warp
owns 32 unique 128-byte lines, and the primary metric is the L1TEX-source LTS
write-sector counter. `write-bandwidth` must remain single-pass:

```bash
l2_slice_re/run_profile.sh --metric-set write-bandwidth -- \
  --buffer-mib 32 --duration-ms 10 --repeats 9 \
  --blocks-per-sm 6 --write-stream
```

Locked reference run `raw/20260713T105043+0800.fnmteh/` measured 46.614
write sectors/LTS-cycle and 3.626 TB/s of 32-byte sector service, with one
sector per store and near-uniform 48-domain traffic. This is not DRAM bandwidth;
the four-byte useful payload rate is one eighth of the sector rate.

The calibrated concentrated-write demo tests whether read-relative classes
remain distinct/equivalent in the write counter for selected subsets. It uses
16 private lines in one class and a 16-class routing control:

```bash
make -C l2_slice_re build/class_write_demo
l2_slice_re/run_profile.sh --program class-write \
  --metric-set write-bandwidth \
  --lock-gpu 2895,2895 --lock-mem 14001,14001 --
```

Locked run `raw/20260713T114835+0800.class_write.hGwBp5/` passed all nine
samples with one sector/store. The one-class case measured `min/avg=0`,
`max/avg=48`, and 0.999782 sector/LTS-cycle (78.140 GB/s sector service). The
16-class control measured `max/avg=3.000006`, consistent with 16 distinct,
near-equally loaded write rollups; its two-block kernel is instruction-issue
limited and is not a 16-domain peak. The separately qualified one-domain and
46.614-sector/cycle near-uniform writer have a 46.6x cross-kernel endpoint
ratio, consistent with wide domain parallelism. Because their grids and
working sets differ, this is not a same-kernel causal scaling measurement and
does not assign physical slice IDs.

`--metric-set write-validation` adds request, hit/miss, total-write, and DRAM
byte counters. It may replay the writing kernel and is descriptive only; run
`105207` used five passes.

Offline case planning and model fitting:

```bash
python3 l2_slice_re/plan_cases.py \
  --output /tmp/pairs.tsv --manifest /tmp/pairs.jsonl \
  pair --anchor 0 --candidate 128 --candidate 256

# Later, after conservative equivalence classification produces offset/class TSV:
python3 l2_slice_re/xor_fit.py classes.tsv --min-bit 7 --max-bit 25
```

`plan_cases.py` preserves weights in JSONL and expands them to repeated offsets
for the probe's 64-slot case format. `xor_fit.py` reports only the identifiable
relative affine-invariant space. Its v2 output is explicitly
`descriptive_training_only`, reports singleton/constraint diagnostics, and does
not call a training-set separator an exact hardware hash.

After a pair plan includes both `positive_same` and a separately established
`negative_distinct` control, `infer_pairs.py` block-bootstraps whole repeat IDs
and emits only `same`, `different`, or `unknown`. It refuses positive merges
when the two control distributions are not separated at the requested
confidence.
