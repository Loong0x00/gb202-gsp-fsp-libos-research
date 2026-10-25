# RTX 5090 VRAM locked-clock controlled test (2026-07-28)

## Result

The latest LACT upstream `master` reproduced the regression. With the same
127-point GPU V/F curve and `+2000` memory offset, adding only
`min_memory_clock: 15000` and `max_memory_clock: 15000` reduced Cyberpunk 2077
Path Tracing average FPS by 16.43%, GPU clock by 118.1 MHz, and one-second
average board power by 142.1 W.

Tested LACT commit:

```text
b3efeb273f7e0ed9b83bc37b24938f6b51fb555f
lact-git r1198.b3efeb27-1
```

The commit was the upstream `master` HEAD when tested and was also cloned and
built independently with `cargo build -p lact --frozen --release`.

## Latest-master controlled comparison

All runs used Cyberpunk 2077 2.31 at 6144x3456 with Path Tracing enabled, the
same game settings, 600 W requested/enforced power limit, and the same fan
curve. States B and C were identical except for the two memory locked-clock
fields.

| State/run | Clock configuration | Avg/min/max FPS | GPU MHz min/avg/max | 1 s board W min/avg/max |
|---|---|---:|---:|---:|
| A — `cp2077_6k_20260728_054158` | stock clock controls | 11.5038 / 10.0939 / 13.3273 | 2722 / 2743.9 / 2767 | 517.5 / 571.3 / 599.9 |
| B — `cp2077_6k_20260728_054455` | 127-point V/F, +2000, no memory lock | 11.8993 / 10.3161 / 13.9809 | 2827 / 2888.1 / 2932 | 505.8 / 556.7 / 590.8 |
| C — `cp2077_6k_20260728_054744` | same V/F and +2000, memory min=max 15000 | 9.9443 / 8.9323 / 11.3875 | 2715 / 2770.0 / 2827 | 396.7 / 414.6 / 438.3 |

State C versus State B:

- average FPS: -16.43%;
- minimum FPS: -13.41%;
- maximum FPS: -18.55%;
- average GPU clock: -118.1 MHz (-4.09%);
- average board power: -142.1 W (-25.53%).

There were no Xids, thermal slowdowns, hardware slowdowns, power-brake
slowdowns, or private active PERF limits in any run.

## Power-policy evidence

The read-only `WORKLOAD_COMBINED_2X` dynamic status changed substantially when
only the memory lock was added:

| Field | A: stock | B: unlocked | C: locked |
|---|---:|---:|---:|
| `CurrLimit` | 396.90 W | 400.87 W | 456.07 W |
| `CurrValue` | 360.70 W | 354.47 W | 264.37 W |
| DG0 candidate | 2997.27 MHz | 2944.12 MHz | 2787.91 MHz |
| Branch-1 workload | 258.30 | 250.83 | 374.18 |
| Branch-1 estimate | 165.70 W | 188.25 W | 276.76 W |

The lock raised the model's second branch estimate by about 88.5 W while real
board power fell by about 142 W. This is model/arbiter state, not evidence that
the physical memory rail consumed 276.76 W.

## Maximum-side isolation and feedback closure

Follow-up tests submitted the two memory clients independently through the
R610 inline-array control `0x2080e0af`:

- `0x75`: strict DRAM maximum;
- `0x78`: strict DRAM minimum.

The decisive comparison held the same actual memory clock at approximately
15001 MHz:

| Request | Avg FPS | GPU MHz | 1 s board W | XBAR MHz | SYS MHz | Observed branch-1 voltage | Branch-1 workload | Branch-1 estimate |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| MIN-only 15000 | 11.7864 | 2893.7 | 560.6 | 2356.0 | 2332.4 | 967.2 mV | 257.3 | 188.2 W |
| MAX-only 15000 | 9.9580 | 2774.7 | 414.2 | 1493.6 | 1501.0 | 870.0 mV | 369.2 | 275.1 W |

A MAX-only value of 16000 reproduced the bad state even though it was
non-binding and actual memory still ran at approximately 15001 MHz. A
MAX-only value of 14000 also left reported memory at approximately 15001 MHz,
but reduced XBAR further to 1440 MHz and SYS to 1239 MHz. Therefore the
trigger is the presence of a finite maximum-range client, with an additional
value-dependent propagation effect; it is not the achieved memory clock.

The active clock topology remains ID 7 and contains bidirectional type-5
shared-rail relations `MCLK <-> XBAR` and `MCLK <-> SYS` on voltage rail 1.
The observable feedback loop is:

```text
finite MCLK maximum
  -> delivered branch-1 state falls to about 870 mV / 1.44-1.49 GHz
  -> normalized branch-1 workload rises
  -> the model still evaluates that workload near 1.1 V / 2.56 GHz
  -> branch-1 estimated power is inflated
  -> WORKLOAD_COMBINED_2X lowers the GPC target
  -> large board-power headroom remains unused
```

A direct sufficiency test subsequently applied `XBAR MAX = 1493 MHz` under the
same FurMark Vulkan load.  `MCLK MAX = 16000 MHz` and the direct XBAR limit
produced the same downstream state to measurement precision:

| Input | Observed branch-1 MHz / mV | Branch-1 workload | Branch-1 estimate | DG0 target |
|---|---:|---:|---:|---:|
| MCLK MAX 16000 | 1498.2 / 870.0 | 526.2 | 234.1 W | 3018.9 MHz |
| XBAR MAX 1493 | 1492.3 / 870.0 | 522.4 | 233.8 W | 3021.8 MHz |

Together with topology ID 7's bidirectional type-5 `MCLK <-> XBAR` relation,
this closes the operational cause: a finite MCLK maximum is propagated as a
cross-domain XBAR/shared-rail ceiling even when the maximum is above actual
MCLK.  The resulting low actual branch state changes workload normalization;
the candidate evaluator then evaluates that workload at a different, higher
candidate frequency/voltage state.  The exact private R610 range field and
function remain unidentified, but the causal input/output chain no longer
depends on that symbol recovery.

The full evidence-labelled closure is recorded in
`power_governor_reverse/MEMORY_MAX_FEEDBACK_CLOSURE_20260728.md`.

## Earlier reproduction

Older LACT commit `ab83c4c28189d5fbf55e995029162a453d02f733` showed the
same behavior: one locked run averaged 9.8940 FPS and two unlocked runs
averaged 11.7416 and 11.8023 FPS. Those values are not mixed into the latest
table above.

## Current persistent state

The machine was restored to the custom 127-point V/F curve and `+2000` memory
offset without `min_memory_clock` or `max_memory_clock`.

```text
/etc/lact/config.yaml SHA-256:
e9207cb62786c742e7c59369e6276e447d06698022c4872c34fc15012bbca13c

Locked-state source backup:
/etc/lact/config.yaml.bak-20260728_050915-before-remove-min-memory-clock
```
