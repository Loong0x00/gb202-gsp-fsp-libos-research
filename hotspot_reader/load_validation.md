# Controlled load validation, 2026-07-14

Hardware: RTX 5090 `0000:01:00.0`, driver 610.43.03.  All workloads changed
no fan, clock, voltage, power-limit, firmware, or MMIO setting.

## Final aggregate-candidate runs

The operational value was recomputed from raw words as:

```text
candidate = max(decode(0xad0aa0), decode(0xad0ae0))
```

The exact status of the numerical invariant is **VERIFIED**; calling the
result NVIDIA's private junction/hotspot remains **INFERRED**.

| quantity | 14.6 s pre-load + 10.4 s load overlap (12 s load continued after trace) / 250 samples | 6.4 s pre-load + 25.0 s FP32 + 8.8 s cooldown / 400 samples |
|---|---:|---:|
| candidate range | 41.812--77.969 C | 42.594--81.375 C |
| PTHERM edge range | 39--64 C | 39--68 C |
| maximum instantaneous candidate-edge | 19.281 C | 20.781 C |
| maximum board power | 473.24 W | 475.79 W |
| aggregate equals its four-source MAX | 500/500 bank-samples | 800/800 bank-samples |
| aggregate mirror equality | 500/500 bank-samples | mirrors not captured by older reader |

In both banks, source 0 and source 3 each became the winner during the trace;
the aggregate was not merely a fixed fifth source that happened to remain
hottest.  All 650 time samples had bit 30 set and low bits 2:0 clear in every
captured bank word.  The older run includes cooldown to candidate 46.938 C /
edge 44 C.  Cooling was continuous overall, not strictly monotonic each sample.

Recompute from the address/raw columns, deliberately ignoring the provisional
derived-column names written by the discovery-stage reader:

```sh
python validation/audit_trace.py \
  validation/gb202_hwmax_trace_20260714.csv \
  validation/gb202_hotspot_trace_20260714.csv
```

The default cooling policy did not approach 107 C and no NVIDIA Xid or thermal
throttle was observed.  The user's reported 30--40 C delta and 107 C event
therefore remain **UNKNOWN** for this candidate; no unsafe attempt was made to
force them.

## Candidates rejected during the initial BF16 scan

An earlier 25-second, approximately 50% duty-cycle BF16 run reached edge 53 C
and 260--278 W.  It was useful for rejecting false positives:

- `0xad0f40` stayed raw `0x001f08cd` (70.406 C under an LS10-layout
  hypothesis) at idle and load;
- `0xad0fa8` likewise stayed fixed;
- `0xad0460/464` tracked edge-like zones rather than the later aggregate.

Those fixed words must not be reported as a live hotspot.  The details and
their evidence labels are retained in `THERM_REGISTER_AND_NVAPI_EVIDENCE.md`.
