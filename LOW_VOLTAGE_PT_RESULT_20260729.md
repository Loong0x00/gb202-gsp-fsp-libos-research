# RTX 5090 low-voltage path-tracing result (2026-07-29)

## Question

Does Cyberpunk 2077 path tracing actually require approximately 973 mV to sustain approximately 2900 MHz, or is the high voltage a consequence of selecting a higher V/F point and then reducing its realized clock through the runtime power controller?

## Baseline

Previously validated curve, 10 consecutive Cyberpunk 2077 benchmark rounds at 6144x3456 with path tracing:

- Average FPS: 11.7911
- Reported graphics clock: 2897.57 MHz average
- Reported GPU voltage: 973.07 mV average
- One-second board power: 555.28 W average
- No Xid or benchmark failure

## Discriminating tests

1. Keeping the baseline curve but applying a max-only 2900 MHz graphics-clock request caused the runtime point to fall to approximately 923 mV and 2851 MHz. This disproves the interpretation that path tracing intrinsically forces approximately 973 mV at all nearby clocks.
2. Raising the 925 mV curve point above a lower max-clock request caused the controller to fall back to a lower V/F candidate instead of simply clipping that point to the requested maximum. Therefore the max-clock request participates in V/F candidate selection; it is not merely a final continuous frequency clamp.
3. An experimental 2970 MHz plateau from the 925 through 970 mV table entries, combined with a max-only 2970 MHz request, produced the target runtime region.

## Completed experimental rounds

Four complete Cyberpunk 2077 path-tracing rounds were retained. A fifth round was manually interrupted after the mechanism/result had converged and is excluded.

- Average FPS: 11.9424 (range 11.9151--11.9571; sample SD 0.0193)
- Reported graphics clock: 2897.13 MHz (per-round means 2895.4--2898.2; sample SD 1.20 MHz)
- Reported GPU voltage: 920.65 mV (per-round means 920.4--921.0; sample SD 0.25 mV)
- One-second board power: 514.73 W (per-round means 514.5--515.0; sample SD 0.21 W)
- No Xid, GPU-lost, reset-required, or completed-round application failure

Relative to the 10-round baseline, the completed experimental rounds showed approximately the same reported graphics clock, 52.4 mV lower reported voltage, 40.6 W lower average board power, and 1.28% higher average FPS. The FPS difference is an observed same-session result, not a formal causal estimate, because the two configurations were not alternated in an interleaved randomized A/B sequence.

## Interpretation boundaries

- The test disproves the claim that this PT workload requires approximately 973 mV merely to deliver baseline-level throughput around the reported 2900 MHz region.
- The driver's `clocks.current.graphics` sampling, bin selection, aggregation, and reporting path has not yet been reverse engineered. It must not be called a direct measurement of effective SM execution frequency.
- The curve-table voltage label and runtime voltage telemetry are not interchangeable. The experimental table started its plateau at the 925 mV entry, while completed rounds reported approximately 920.7 mV average.
- Equivalent or higher benchmark throughput is stronger evidence than the reported graphics-clock number alone, but a dedicated on-GPU effective-clock probe would still be useful for detecting clock stretching directly.
- Four rounds establish a strong short-run result, not unconditional long-game stability.

## Cleanup state

- The experimental max-clock request was reset.
- Memory-clock requests were reset.
- `/etc/lact/config.yaml` was restored to the previously validated curve with SHA-256 `72c89a17b3f2467e474e38173992467f2622fecfa29c94fffe2e86ada9c34b9f`.
- The experimental curve remains only as a saved research artifact and is not the active daily configuration.
