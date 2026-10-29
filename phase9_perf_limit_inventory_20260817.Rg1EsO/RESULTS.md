# Phase-9 complete PERF-limit inventory

Date: 2026-08-17  
Target: NVIDIA GeForce RTX 5090, R610.57.04  
Scope: private RM read-only STATUS, pinned static GSP catalog, and known-safe L2 correctness workload  
GPU setters: none

## Result

The current `PERF_LIMITS_GET_STATUS_V2` ID space is exhausted: all IDs
`0x00..0xff` were queried one at a time in the same RM session. Exactly 20 IDs
were runtime-valid in each of the three inventories. Cross-mapping against the
pinned current GSP container found no `PERF_CF_CONTROLLER_SYS_*` record. The
only static name containing `SYS` is runtime-invalid `0x1b SYSPERF`.

The PERF-CF controller catalog and idle-before runtime state were:

| ID | Static name | Runtime |
|---:|---|---|
| `d0` | `PERF_CF_CONTROLLER_DRAM_MIN` | valid, 15001000 kHz |
| `d1` | `PERF_CF_CONTROLLER_GPC_MIN` | valid, 697000 kHz |
| `d2` | `PERF_CF_CONTROLLER_NVD_MIN` | valid, state-dependent |
| `d5` | `PERF_CF_CONTROLLER_DRAM_MAX` | invalid |
| `d6` | `PERF_CF_CONTROLLER_GPC_MAX` | invalid |
| `d7` | `PERF_CF_CONTROLLER_NVD_MAX` | invalid |
| `db` | `PERF_CF_CONTROLLER_XBAR_MAX` | invalid |

Therefore this interface cannot supply the missing SYS request/winner. It also
does not supply an active NVD upper candidate or winner; `d2` is only a named
controller-min endpoint.

## Runtime inventory

The 20 valid IDs were:

```text
06 11 36 41 42 43 46 48 4d 53 6f 70 71 8e 8f d0 d1 d2 e9 ea
```

The three 256-ID scans are sequential observations over about 2.8 seconds, not
simultaneous phase snapshots. Their controller-min and XBAR values were:

| Scan | d0 | d1 | d2 | e9 | ea |
|---|---:|---:|---:|---:|---:|
| idle-before | 15001000 | 697000 | 2715000 | 3135000 | 2775000 |
| load | 15001000 | 3195000 | 2640000 | 3135000 | 2715000 |
| idle-after | 15001000 | 3240000 | 2662000 | 3135000 | 2737000 |

These rows must not be used as a synchronized forward-model bracket.

## NVD endpoint discriminator

An initial 11-ID synchronized LACT query returned `d2` invalid in all 36 loaded
rows. Direct short-lived single-ID processes returned the first 3 queries
invalid and the following 37 valid at 705000 kHz. This was not an array
capacity limit:

- loaded batch queries with `d2` in different positions were valid for counts
  1, 2, 3 and 9;
- an early short run made counts 10 and 11 both invalid independent of `d2`
  position;
- the controlled repeat in `batch-size-boundary-load.txt` made counts 8, 9 and
  10 transition together: all invalid during the first ramp interval, then all
  valid at 2295000/2662000 kHz.

The earlier apparent tenth-entry boundary was therefore temporal, not a
payload truncation.

LACT now queries the original eight candidates and `d0/d1/d2` as two explicit
semantic groups while preserving one 55-column row. Under a passing 9-second
L2 workload, its 6.5-second persistent-session capture returned 53 complete
rows:

| Signal | Result |
|---|---|
| d0 | valid 53/53, 15001000 kHz |
| d1 | valid 53/53, 3180000/3195000/3240000 kHz |
| d2 | valid 4/53, 637000..697000 kHz, only at elapsed 397..788 ms |
| physical NVD during d2-valid rows | 2234762..2286117 kHz |
| physical GPC | 3171195..3198801 kHz |
| physical XBAR | 2395203..2421699 kHz |
| physical SYS | 2390099..2407322 kHz |

The workload passed 1399 rounds, 170/170 SM coverage and zero correctness
errors. `d2` being far below simultaneous physical NVD, and disappearing while
the workload remains active, disproves interpreting it as a final NVD grant.
Repeated process/session creation is itself a measurement perturbation for
this endpoint.

## Static/runtime method

`audit_perf_limit_catalog.py` pins GSP container SHA-256
`c0156954f3e048d56011524e0c2ae2881bb6db8173b53f9b2f4eb94197f02999`, verifies
the inner ELF at offset `0x19f040`, scans the 0x20-byte catalog records, and
cross-maps all 256 runtime rows. The generated JSON records the complete valid
set, the PERF-CF controller catalog including runtime-invalid MAX endpoints,
and every system-named catalog entry.

## Semantic boundary

The solver retains `d0/d1/d2` under:

```text
perf_cf_controller_min_endpoints_not_binding_upper_winners_or_final_grants
```

Closed here:

- no missed active SYS or NVD-MAX PERF-limit ID exists in `0x00..0xff` on this
  exact build;
- `d2` is not the physical NVD grant;
- the prior 10-entry truncation hypothesis is false.

Still missing:

- phase-local SYS request candidates and binding winner;
- an NVD upper candidate/winner and the complete clock-client selector;
- workload/client duty state mapping V/F upper envelopes to realized clocks;
- the aggregate MSVDD ten-slot request records and winner ID, which the public
  rail STATUS/PMUMON paths do not export.

## Artifacts

- `idle-before.txt`, `load.txt`, `idle-after.txt`: complete runtime inventories
- `*-catalog.json`: pinned static/runtime cross-maps
- `loaded-55-column-sampler-split.log`: final persistent-session capture
- `loaded-55-column-sampler-split-workload.log`: paired correctness workload
- `d2-single-load.txt`, `d2-batch-load.txt`: short-lived probe behavior
- `batch-cap-load.txt`, `batch-size-boundary-load.txt`: order/count controls
- `post-health.txt`, `post-kernel-alerts.txt`: final read-only health check
- `SHA256SUMS`: receipt hashes

## Validation

```text
LACT cargo fmt --check: pass
LACT git diff --check: pass
LACT daemon: 48 pass, 10 ignored
solver compileall: pass
solver unittest discovery: 179/179 pass
solver pytest: 189/189 pass
C probe: -O2 -Wall -Wextra -Werror pass
pinned catalog reproducibility cmp: pass
catalog assertions: 256 rows, 20 valid, no PERF_CF_CONTROLLER_SYS,
                    NVD_MAX runtime-invalid
55-column loaded live sampler: 53/53 complete rows
L2 correctness workload: 1399 rounds, 170/170 SM, 0 errors
```
