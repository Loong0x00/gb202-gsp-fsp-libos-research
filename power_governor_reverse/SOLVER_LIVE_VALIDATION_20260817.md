# GB202 solver live validation

Date: 2026-08-17  
Target: RTX 5090 / GB202 / R610.57.04  
Scope: bounded P0 compute validation on the current desktop state

## Result

The corrected digital twin is usable as a predictive upper-envelope solver for
the tested GPC/XBAR/SYS/NVD and NVVDD/MSVDD path. Its final prospective test
predicted all four clocks before load, then matched their live p95 values within
2.140 MHz and both rail maxima exactly.

Frozen control/readback:

- GPC temporary lock: 2700 MHz;
- GPC-to-XBAR ratio: existing raw `0x0000e660` = 0.899902344;
- XBAR tuple offset: existing 0 kHz;
- NVVDD/MSVDD control deltas: existing 0/-50000 uV;
- rail maxima: existing 1200/1000 mV;
- no XBAR, ratio, voltage or fan write in the successful run.

Frozen solver output and live measurement:

| Domain/rail | Prediction before load | Live statistic | Signed error |
|---|---:|---:|---:|
| GPC | 2700 MHz | 2701.947 MHz p95 | +1.947 MHz |
| XBAR | 2430 MHz | 2430.820 MHz p95 | +0.820 MHz |
| SYS | 2422 MHz | 2424.140 MHz p95 | +2.140 MHz |
| NVD | 2310 MHz | 2310.213 MHz p95 | +0.213 MHz |
| NVVDD | 885 mV | 885 mV max | 0 mV |
| MSVDD | 995 mV | 995 mV max | 0 mV |

Workload result:

```text
mode=compute
elapsed_s=3.000240
rounds=9356
gib=49703.750
sm_covered=170/170
errors=0
pass=1
Xid/GSP/AER/reset alerts=0
```

Prospective receipt:

- outer control/prediction/health receipt:
  `/home/user/rt_5090_project/benchmark_logs/solver_live_compute_gpc2700_xbar0_20260817_095751`
- inner workload/direct telemetry receipt:
  `/home/user/rt_5090_project/benchmark_logs/ptx_xbar_solver-0-gpc2700-ratio-stock-live-rails_compute_20260817_095752`

The reusable runner now performs this comparison automatically. It writes
`model-vs-live.json`, uses nearest-rank clock p95 and the highest modal rail
target while retaining the maximum as a transition diagnostic, and makes
15 MHz/5 mV comparison tolerances part of its final pass gate. A one-second
smoke run of that complete automated path passed with
170/170 SMs, 3,215 rounds, 17,079.688 GiB, zero errors and zero kernel alerts:

- `/home/user/rt_5090_project/benchmark_logs/solver_live_compute_gpc2700_xbar0_20260817_100128`
- `/home/user/rt_5090_project/benchmark_logs/ptx_xbar_solver-0-gpc2700-ratio-stock-live-rails_compute_20260817_100128`

The smoke-run p95 errors were +2.719/+2.581/+2.444/+2.486 MHz for
GPC/XBAR/SYS/NVD. NVVDD matched exactly; the shorter rail sample window saw
MSVDD 990 mV versus the 995 mV prediction, a -5 mV difference. The longer
three-second prospective run captured the predicted 995 mV point exactly.

## Voltage decision ordering closed by the live run

The previous model default requested voltage from the pre-propagation clock.
The 2700 MHz point rejects that ordering:

```text
GPC final                         2700 MHz
ratio ceiling floor(2700*0.899902344) 2430 MHz XBAR
XBAR V/F bank at 2430 MHz         995 mV
live MSVDD maximum                995 mV
```

The counterfactual pre-propagation XBAR request starts from 2812 MHz, requests
1240 mV and is capped at 1000 mV. Hardware selected 995 mV, not 1000 mV. At
that voltage the live banks give SYS 2422 MHz and NVD 2310 MHz, also matching
the direct clocks. The default configuration was therefore changed to
`voltage_request_stage = final`. This conclusion is confirmed for the tested
R610 P0 path; private clients and other P-states remain outside the claim.

## Low-voltage/VMin validation and stage-order discriminator

A separate GPC 2137 MHz run exposed and then verified two lower-voltage stages
that were invisible at 2700/3000 MHz:

1. GPC/XBAR clock-grid and divider projection occur before the F-to-V lookup
   used for the request. The ratio result around XBAR 1923 MHz is projected to
   1920 MHz, whose request is 825 mV.
2. MSVDD VMIN raises the physical rail target to 870 mV but does not grant the
   SYS/NVD clocks associated with a logical 870 mV V/F point. Their ceilings
   remain derived from the pre-VMIN 825 mV request.

Prospective result:

| Domain/rail | Predicted | Live p95/mode | Error |
|---|---:|---:|---:|
| GPC | 2130 MHz | 2138.602 MHz p95 | +8.602 MHz |
| XBAR | 1920 MHz | 1924.715 MHz p95 | +4.715 MHz |
| SYS | 1905 MHz | 1908.952 MHz p95 | +3.952 MHz |
| NVD | 1800 MHz | 1805.170 MHz p95 | +5.170 MHz |
| NVVDD | 840 mV | 840 mV mode | 0 mV |
| MSVDD | 870 mV | 870 mV mode | 0 mV |

The three-second PTX run completed 8,515 rounds and 45,235.938 GiB over
170/170 SMs with zero errors and zero kernel alerts. Receipts:

- `/home/user/rt_5090_project/benchmark_logs/solver_live_compute_gpc2137_xbar0_20260817_101901`
- `/home/user/rt_5090_project/benchmark_logs/ptx_xbar_solver-0-gpc2137-ratio-stock-live-rails_compute_20260817_101902`

This lock-based point validates the lookup projection and VMIN separation. It
does not itself identify issue 1268 because the lock commit intentionally asks
the normal V/F path to refresh, and the GPC bank contains duplicate 2137 MHz
points at 840/845 mV.

## Issue 1268 model boundary

The digital twin now represents the reported GPC bug with an optional
`post_voltage_clock_max_mhz` stage. It lowers the final effective clock after
the voltage request and deliberately performs no second lookup. A trace records
both retained voltage and the hypothetical refreshed voltage.

The stale-voltage behavior is supported by the controlled max-only feedback
experiment, but the private client/equation producing the final GPC grant is
still unknown. Consequently this value must come from a captured final grant or
a separately recovered arbiter; it is not fabricated by the solver.

## Repeated runs

An earlier 3000 MHz run supplied an independent non-discriminating validation:
the model predicted GPC/XBAR/SYS/NVD = 3000/2445/2430/2317 MHz, while live p95
was 3001.240/2443.930/2426.960/2319.995 MHz. Both orderings hit the 1000 mV
MSVDD cap at this point, so it validates the clock outputs but cannot identify
the voltage-request stage.

Receipts:

- `/home/user/rt_5090_project/benchmark_logs/solver_live_compute_xbar0_20260817_095058`
- `/home/user/rt_5090_project/benchmark_logs/ptx_xbar_solver-0-gpc3000-ratio-stock-live-rails_compute_20260817_095058`
- post-hoc 2700 MHz discriminator:
  `/home/user/rt_5090_project/benchmark_logs/solver_live_compute_gpc2700_xbar0_20260817_095243`

## Rejected control paths and state preservation

Three exploratory SET attempts were deliberately gated before load:

| Attempt | Result | Load started | Independent restored/current GET |
|---|---|---|---|
| NVVDD/MSVDD temporary holder | `VOLT_RAILS_SET_CONTROL = -137` | no | deltas remained 0/-50000 uV |
| GPC-to-XBAR ratio 1.0 | RM status `0x1b` | no | ratio remained `0x0000e660` |
| XBAR +420 MHz | RM status `0x1b` | no | XBAR offset remained 0 kHz |

Failure receipts:

- `/home/user/rt_5090_project/benchmark_logs/solver_live_compute_xbar420000_20260817_094644`
- `/home/user/rt_5090_project/benchmark_logs/solver_live_compute_xbar420000_20260817_094805`
- `/home/user/rt_5090_project/benchmark_logs/solver_live_compute_xbar420000_20260817_094851`

These rejections describe authorization/state in the current desktop session;
they do not falsify the decoded control ABI. No unsuccessful setter was retried
under load.

They also do not describe the later pinned-LACT exact-contract path. Subsequent
LACT transactions on the same driver/VBIOS successfully performed full-preimage
SET/GET_CONTROL/restore for XBAR/SYS domain offsets, V/F point control,
relation-0 CONTROL and the XBAR/SYS/NVD composite V/F voltage-coordinate
offset. Relation CONTROL adoption is confirmed, while a physical ratio winner
is not. Aggregate rail min/max setters remain a distinct control class.

## Telemetry correction

The old stress harness called RM domain `0x1` SYS. The recovered topology and
simultaneous NVML readings prove it is GPC. The sampler now records the direct
domain IDs:

```text
GPC  0x00000001
XBAR 0x00000002
SYS  0x00000004
NVD  0x00100000
```

New `hardware-clocks.csv` files contain all four domains. Historical harness
columns labelled SYS must be treated as GPC unless independently reanalysed.

## Post-run state

The runner reset the GPC lock and independently read back:

- XBAR offset 0 kHz and XBAR MSVDD offset 0 uV;
- ratio raw `0x0000e660`;
- NVVDD/MSVDD deltas 0/-50000 uV;
- idle temperature 32 C, about 55 W at final inspection;
- no boot-current Xid, GSP error/reset-required, AER error or Surprise Down.

Fan state and fan controls were never read or written by this validation.
