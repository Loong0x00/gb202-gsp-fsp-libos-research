# Algorithm/data smoke report — 2026-08-14

Scope: read-only data normalization, four competing predictive models, and a
domain-scoped discrete inverse query. No GPU control/write method was called by
this code.

## Reproducible commands

Run from this directory:

```bash
PYTHONPATH=. python -m unittest discover -s tests -v

python canonicalize.py \
  ../../../benchmark_logs/cp2077_6k-pt-tail3300-dg0-vf-feedback-short_20260814_001713 \
  --scene-only --output /tmp/cp2077.csv --report /tmp/cp2077-align.json
python compare_models.py /tmp/cp2077.csv --output /tmp/cp2077-models.json
python solve_inverse.py --candidates /tmp/cp2077.csv \
  --target-mhz 3300 --voltage-limit-mv 1080 --power-limit-w 800 \
  --output /tmp/cp2077-query.json

python canonicalize.py \
  ../data_pipeline/artifacts/idle_core_voltage_final_20260814_010050.jsonl \
  --output /tmp/collector-final.csv --report /tmp/collector-final-align.json
python compare_models.py /tmp/collector-final.csv \
  --voltage-field nvvdd_target_mv --max-clock-uncertainty-mhz 15 \
  --output /tmp/collector-final-models.json

python solve_inverse.py --grid tests/fixtures/verified_grid.json \
  --target-mhz 3200 --voltage-limit-mv 1080 --power-limit-w 800 \
  --output /tmp/synthetic-query.json
```

## Test result

- 8 unit tests passed under Python's standard-library `unittest`.
- `py_compile` passed for all three CLIs and all `gpu_inverse` modules.
- The benchmark-log root normalized 182 discovered run directories into
  110,973 canonical rows in 5.6 seconds. Missing source files remained empty
  rather than aborting a run.
- Additional readable-run smoke:
  - `cp2077_6k_20260729_002035`: 79/79 rows have clock, voltage, power, DG0.
  - `furmark_vk_3840x2160_20260729_001810`: 337/337 rows have clock, voltage,
    power, DG0; voltage is recovered from `lact-telemetry.csv`.

## 2026-08-14 CP2077 scene

The scene window yields 360 policy-anchored rows over the recorded 80.955 s
window. These legacy files are not atomic samples. Absolute nearest-neighbor
skew relative to the policy timestamps is:

| Source | Median | p99 | Maximum |
|---|---:|---:|---:|
| telemetry | 18 ms | 46 ms | 57 ms |
| NVML | 12 ms | 32 ms | 34 ms |
| clock-hardware | 49 ms | 68 ms | 70 ms |
| power cap | 14 ms | 30 ms | 33 ms |
| active limits | 13 ms | 30 ms | 32 ms |

`clock-hardware.csv` has XBAR/SYS only. The legacy `final_clock_mhz` response is
the telemetry GPC clock, not a direct `--clk-measure-freq 1` result. Because
some skew spans several approximately 20 ms update periods, these rows can
compare steady predictive association but cannot identify event ordering.

All four models use a train-only 15 MHz-binned weighted-PAVA monotone step map,
then round requests upward to the 5 mV grid. Linear regression is retained only
as a baseline inside the report. The split was chronological: 288 training and
72 held-out rows.

| Hypothesis | Held-out RMSE | MAE | error <=5 mV | delta AICc |
|---|---:|---:|---:|---:|
| final clock | 4.564 mV | 3.472 mV | 93.1% | 70.81 |
| DG0 | 4.564 mV | 3.472 mV | 93.1% | 70.81 |
| pre-DG0 candidate | not identifiable | — | — | — |
| asymmetric first-order/hold | 3.909 mV | 3.056 mV | 100% | 0 |

This is only predictive evidence. The final-clock and DG0 hypotheses remain
observationally confounded here; neither `pre_dg0_candidate_mhz` nor the winning
voltage-request client exists in these logs.

The observed-row 3300 MHz / 1080 mV / 800 W query found no feasible observed
row. Its closest retained scene row was 3195 MHz, 1060 mV, 641.8 W: 90 MHz
outside the allowed 15 MHz clock bin. This conclusion is explicitly
`no_feasible_observed_candidate`, not an infeasibility proof and not a learned
control law.

## Unified collector JSONL

The actual final 10-sample artifact maps successfully through the `sources`
adapter:

- nested rail target records decode as NVVDD 815 mV and MSVDD 875 mV in all
  ten rows; older flat rail fields remain supported;
- policy-sensed rail 0/1, rail target 0/1, and the compatibility `voltage_mv`
  label remain separate fields;
- GPC pre/post direct measurements retain their midpoint, signed drift,
  half-range uncertainty, and bracket duration;
- two unstable brackets are retained in canonical output but excluded by the
  15 MHz model filter: sample 2 drifted -2344.946 MHz and sample 7 drifted
  +3075.099 MHz. The model report records input=10, excluded=2, usable=8.

The remaining NVVDD target is constant at 815 mV. Final-clock, DG0, and dynamic
hypotheses therefore correctly report `not_discriminating_constant_signal`;
the pre-DG0 candidate remains `not_identifiable`. This idle artifact cannot
identify voltage-request selection. Its core profile also lacks board-power
samples, so an 800 W inverse query is `indeterminate_missing_required_observations`.

## Discrete inverse solver check

The synthetic, explicitly verified fixture enumerates four candidates. The
3200 MHz query returns its one feasible candidate; a 3500 MHz query returns
`infeasible_within_verified_discrete_domain`. The latter claim is restricted to
the enumerated synthetic domain and is not a GB202 or physical impossibility
claim. Real solving remains disabled until measured control axes/effects cite a
baseline source and validity domain and are marked `verified`.

## Still unidentifiable / missing

- a directly observed pre-DG0 candidate with independently varying excitation;
- the winning voltage-request client (or client equivalence class);
- synchronized under-load direct GPC brackets plus rail targets and board power;
- verified GB202 control axes, bounds, local effects, and validity domains;
- repeated workload/temperature hold-out runs sufficient to separate state,
  delay, regime, and temperature effects.

