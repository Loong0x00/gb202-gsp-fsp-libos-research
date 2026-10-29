# CLK client V/F STATUS read-only load discriminator

Date: 2026-08-17  
Contract: RTX 5090 / R610.57.04 / VBIOS 98.02.2E.80.50  
Safety boundary: read-only RM controls plus the previously validated L2 correctness workload. No clock, voltage, propagation, power or fan setter was called.

## Result

`CLK_CLIENT_VF_POINTS_GET_STATUS` (`0x2080902b`) is dynamic, but the observed 127-point GPC portion is a decomposed view of the same effective V/F curve, not evidence of a separate phase-local winner table.

For the paired current captures:

```text
point87 client_effective=3082000 client_baseline=2797000 control_offset=285000
        main_effective=3082000 main_source=2752000
points=127 normal_effective_equal=125 factory_plus45_equal=127
effective_voltage_equal=127 source_voltage_equal=127
```

The two non-matching effective points are main V/F flat points 0 and 1, whose main `effective_freq` field is an unavailable/sentinel value. For all 125 normal points, client STATUS `freq0` equals the main `0x20809022` effective frequency. For all 127 points, client STATUS `freq1` equals the main source-base frequency plus exactly `45 MHz`, independently reproducing the current VBIOS FactoryOC layer. Both voltage fields match 127/127.

The client CONTROL frequency offset is not itself the final frequency delta: `freq0 - freq1 - control_offset` exposes a grid/constraint remainder on some points. Therefore the observed chain is:

```text
main source base
  + 45 MHz current VBIOS/firmware layer
  = client baseline (STATUS freq1)
  + client CONTROL offset
  + grid/constraint remainder
  = client STATUS freq0 = main effective curve
```

This is useful curve-composition state. It does not enumerate multiple active candidates, identify a binding client, or report the final physical grant.

## Load discriminator

Workload:

```text
ptx_xbar_stress --mode l2 --seconds 4 --l2-mib 32 --vram-mib 1024
RESULT pass=1 rounds=621 errors=0 sm_covered=170/170 elapsed_s=4.003258
```

Before versus load changes 48 upper GPC points (79..126) in both STATUS frequency fields while CONTROL offsets remain unchanged. MCLK point 128 voltage changes from 715 to 710 mV. The early and steady load captures are byte-for-byte identical at the decoded summary level; the immediately post-load state remains thermally shifted from the pre-load capture. This is consistent with a dynamic VFE/tuple/effective-curve view and is not by itself proof of workload request arbitration.

## Files

- `before.txt`, `load-early.txt`, `load-steady.txt`, `after.txt`: decoded client INFO/STATUS/CONTROL summaries.
- `before-vs-load-early.diff`, `load-early-vs-steady.diff`, `before-vs-after.diff`: exact decoded diffs.
- `client-current.txt`, `main-vf-current.txt`: paired client and main V/F captures used for the equality counts above.
- `vf-relations-current.txt`, `gpu-current.txt`: current tuple/relation and GPU context.
- `workload.log`: correctness result.
- `SHA256SUMS`: artifact hashes.

