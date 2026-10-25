# Bug-inverse read-only data pipeline

`collector.py` runs only known GET/read paths. It never invokes the existing
probe's SET, offset, clock-lock, hold, or benchmark modes. A source failure is
part of the sample and does not stop later sources.

## Collect

```bash
cd /home/user/rt_5090_project/power_governor_reverse/bug_inverse/data_pipeline
python collector.py collect \
  --output artifacts/idle.jsonl \
  --samples 3 \
  --interval-ms 50
```

The default `core` profile is a phased
`GPC-pre -> policy0-model/thermal -> GPC-post` bracket. It reports whole-window
span, source-midpoint span and GPC pre/post drift. Add the pinned read-only
610.57 rail target reader with `--with-voltage`. It is imported and initialized
once per run, then sampled in-process concurrently with the policy GET; the
per-sample path does not restart Python or NvAPI.

Use `--profile full` for low-rate metadata. `--execution parallel` is retained
only as a measured interference control: the driver serialized the tested RM
GETs and inflated their durations. Parallel launch does not make them atomic.

By default this records:

- PMUMON plus direct GPC, XBAR and SYS frequency GETs;
- policy-0 model/thermal state, dynamic policies and regime state;
- PERF limit summary and active limits;
- PMGR A613 channel status (including its current `0x3b` failure);
- a typed `nvidia-smi` identity/clock/power/temperature/utilization row.

Select a subset with comma-separated names, for example:

```bash
python collector.py collect --output artifacts/clocks.jsonl --samples 10 \
  --profile full --sources clk_pmumon,clk_gpc,clk_xbar,clk_sys
```

The output path is created exclusively by default (`open(..., "x")`) so an
old run cannot be overwritten accidentally. Use `--append` intentionally to
append. Each source contains monotonic-raw and wall-clock start/end timestamps,
return code, status, exact stdout/stderr and parsed fields. `schema_v1.json`
documents the required envelope. A sibling `.manifest.json` pins collector and
probe hashes, `libnvidia-api`, LACT config, GPU identity, driver/VBIOS, profile,
phases and exact commands. The collector refuses a GPU other than the expected
`10DE:2B85-1043:89E3` at `0000:01:00.0`. It never asks LACT for default-GPU
stats, which could otherwise select the iGPU.

## Export flat CSV

```bash
python collector.py export-csv \
  --input artifacts/idle.jsonl \
  --output artifacts/idle.csv
```

Nested lists (such as policies) stay as compact JSON cells. Raw text and command
arrays are omitted from CSV unless `--include-raw` is specified; they always
remain in the authoritative JSONL.

## Test

```bash
python -m unittest discover -s tests -v
```

Tests require no GPU and use frozen real-output fixtures. See `TASKS.md` for the
remaining data gaps. This external phased collector brackets and quantifies
sampling skew; measured span must remain within the experiment's accepted
PMU-cycle bound to close parent gap O-05.

The checked-in final idle artifacts measured a 21.5 ms median core bracket
without voltage and 24.1 ms with in-process voltage. A core+voltage sample
caught a 2.24 GHz GPC pre/post transition, so consumers must use the
drift/window fields and must not treat even a short bracket as atomic.
