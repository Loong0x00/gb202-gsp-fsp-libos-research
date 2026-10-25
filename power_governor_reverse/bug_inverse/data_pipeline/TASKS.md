# Data pipeline task board

Scope: read-only observations for the bug-aware inverse governor.  This board
does not authorize any SET, offset, lock, benchmark, or workload launch.

| ID | Parent gap | Status | Evidence / completion rule |
|---|---|---|---|
| DATA-01 | O-01/O-02 | DONE | Schema-v1 collector records direct GPC/XBAR/SYS clocks, PMUMON, policy model/regimes/dynamics, PERF limits and NVML fields with per-call timestamps. |
| DATA-02 | O-05 | PARTIAL | Core is `GPC-pre -> policy model/thermal -> GPC-post`, with every source bracket plus whole span and GPC drift. Final idle medians were about 21.5 ms without voltage and 24.1 ms with cached in-process voltage. One sample caught a 2.24 GHz P-state transition, so it is explicitly non-atomic. |
| DATA-03 | O-03 | PARTIAL | `policy0_model_thermal` supplies sensed/observed NVVDD/MSVDD fields. It does not expose the ten request clients or guaranteed rail target voltage. |
| DATA-04 | A4 | OPEN, OBSERVED | `pmgr_a613_channels` remains in every sample and records RM `0x3b` as a failed source at idle rather than aborting the sample. Need a controlled idle/load matrix later. |
| DATA-05 | dataset contract | DONE | Raw stdout/stderr plus typed parse live in JSONL; flat CSV export excludes raw blobs by default. Schema is pinned at version 1. |
| DATA-06 | parser replay | DONE | Standard-library tests and frozen real-output fixtures cover typed parsing, source failure, missing executable and CSV flattening. |
| DATA-07 | O-05 closure | OPEN | Replace sequential process launches with one long-lived ioctl process or a common library; target source skew <= one approximately 20 ms arbitration period. |
| DATA-08 | O-06 | OPEN | Add bounded kernel/Xid and PCI-presence event capture with a cursor, avoiding full journal scans per sample. |
| DATA-09 | provenance | DONE | Sibling run manifest validates exact GPU identity and records collector/probe/library/config hashes, driver/VBIOS, profile, phases and commands. |
| DATA-10 | core voltage latency | DONE | The audited module/GPU/wrapper are cached once per run. The sampled voltage source took about 1.5 ms (about 1.4 ms inside the wrapper); core+voltage median fell from 41.6 ms subprocess mode to 24.1 ms. |

## Immediate next data experiment

Fuse the remaining policy/clock RM GETs into one process so the full bracket is
comfortably below one arbitration period. Until then, reject or separately
label samples whose GPC pre/post drift indicates a transition; do not silently
fit them as steady-state rows.
