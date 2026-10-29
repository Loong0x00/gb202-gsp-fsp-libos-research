# SYS/NVD workload and frequency-domain target matrix

Date: 2026-08-17  
Target: RTX 5090 / R610.57.04 / VBIOS 98.02.2E.80.50  
Scope: read-only RM STATUS plus correctness-checked workloads  
GPU setters: none

## Result

Two previously missing runtime surfaces are now synchronized in the LACT
sampler:

1. official `0x20801037` clock PMUMON samples, including programmed GPC,
   DRAM, NVD and active-GPC clocks;
2. `0x20809062` frequency-domain group STATUS for GPC/XBAR/SYS/NVD.

The latter uses a 20-byte record. Same-generation MODS contains the exact log
format `clkDomain, actualFreq, targetFreq, clkSource, flags`; current runtime
values independently match direct physical clock measurements. The first
failed calls used the wrong record input offset. With the API domain at record
`+4`, the method is valid and returns all four tested domains.

The final synchronized row has 79 columns. It retains physical measurements,
voltage PMUMON, V/F relation state, PERF candidates/controller-min endpoints,
clock PMUMON, and four-domain actual/target/source/flags in one persistent RM
session.

## Steady loaded means

All frequencies below are MHz. `physical` is direct `CLK_MEASURE_FREQ`;
`actual/target` are the frequency-domain STATUS fields.

| Workload | Domain | Physical | Actual | Target |
|---|---|---:|---:|---:|
| L2 | GPC | 3190.15 | 3187.00 | 3195.00 |
| | XBAR | 2414.48 | 2413.91 | 2426.73 |
| | SYS | 2402.11 | 2398.18 | 2407.00 |
| | NVD | 2276.40 | 2286.05 | 2299.14 |
| compute | GPC | 3178.00 | 3192.22 | 2779.57 |
| | XBAR | 2413.36 | 2417.74 | 2351.39 |
| | SYS | 2400.60 | 2402.74 | 2336.39 |
| | NVD | 2273.34 | 2290.13 | 2224.09 |
| VRAM | GPC | 3204.95 | 3207.68 | 3213.95 |
| | XBAR | 2415.31 | 2415.00 | 2430.00 |
| | SYS | 2399.33 | 2392.00 | 2407.00 |
| | NVD | 2273.33 | 2287.00 | 2302.00 |
| NVDEC | GPC | 2848.47 | 2947.70 | 2842.17 |
| | XBAR | 2367.43 | 2377.43 | 2367.04 |
| | SYS | 2359.65 | 2362.43 | 2352.04 |
| | NVD | 2229.34 | 2250.91 | 2240.04 |
| NVENC | GPC | 2660.64 | 2682.57 | 2580.00 |
| | XBAR | 2337.60 | 2330.78 | 2317.00 |
| | SYS | 2333.10 | 2315.78 | 2302.00 |
| | NVD | 2179.07 | 2205.00 | 2197.00 |
| transcode | GPC | 2698.75 | 2753.36 | 2653.64 |
| | XBAR | 2369.72 | 2381.95 | 2369.36 |
| | SYS | 2365.03 | 2367.59 | 2354.36 |
| | NVD | 2247.90 | 2256.77 | 2246.09 |

The STATUS `actual` field tracks direct physical measurements within sampling
lag/quantization. The `target` field exposes the missing workload-conditioned
post-arbitration target for every domain, including SYS and NVD. Every tested
GPC/XBAR/SYS/NVD `clock_source` and `flags` value was zero; those fields do not
identify a winning client on this boot.

## NVD programmed clock and controller-min endpoint

The official clock PMUMON programmed-NVD field follows the frequency-domain
actual state and direct NVD measurement. Under settled L2 it used
`2280/2287 MHz`; VRAM used `2280 MHz`; the video workloads moved between
roughly `2205..2310 MHz` as their target changed. Idle gating can make the
instantaneous physical clock differ more strongly from the delayed PMUMON
sample.

`PERF_CF_CONTROLLER_NVD_MIN d2` is not the target:

- idle: 0 valid rows;
- L2: 0/22 steady rows;
- VRAM: 19/19 rows, `840..1102 MHz`, while NVD target was `2302 MHz`;
- NVDEC: 21/23 rows, `607..2692 MHz`;
- NVENC: 16/23 rows, `615..1860 MHz`;
- transcode: 22/22 rows, `705..2362 MHz`.

Memory traffic and video paths activate `d2`; pure L2/compute generally do
not. Its value may be below or above the simultaneous final target, so it is a
state-dependent controller-min endpoint rather than final NVD grant.

## What is now closed

- final programmed NVD clock is directly observable from an NVIDIA-documented
  PMUMON interface;
- workload-conditioned actual and target frequencies are directly observable
  for GPC, XBAR, SYS and NVD;
- SYS is no longer missing from the phase-local final-target bracket;
- NVD video/global-memory activation is distinguished from the final NVD
  target;
- the solver loader preserves these values without relabeling target as a
  candidate set or winner.

## Remaining non-equivalent state

- the simultaneous pre-arbitration candidate set and binding clock-client ID;
- the two rails' ten voltage request records, active/deferred masks and live
  winner ID;
- direct current-build slot mapping for SYS/NVD voltage request producers.

These are not required to display or safely transact the four-domain controls,
but they are required before claiming a complete arbitrary-workload GSP
inverse predictor.

## Workloads and correctness

- L2: 778 rounds, 170/170 SM, zero errors;
- compute: 17686 rounds, 170/170 SM, zero errors;
- VRAM: 2286 rounds, 170/170 SM, zero errors;
- NVDEC: 6K60 AV1 CUVID decode, ffmpeg exit 0;
- NVENC: synthetic 6K60 AV1 encode, ffmpeg exit 0;
- transcode: 6K60 AV1 CUVID to HEVC NVENC, ffmpeg exit 0.

`matrix-summary.json` is generated reproducibly by
`bug_inverse/perf_limits_61057/analyze_workload_matrix.py`.

## Validation

```text
LACT cargo fmt --check: pass
LACT git diff --check: pass
LACT daemon: 50 pass, 10 ignored
solver compileall: pass
solver unittest discovery: 185/185 pass
solver pytest: 195/195 pass
C probe: -O2 -Wall -Wextra -Werror pass
matrix analyzer reproducibility cmp: pass
live 0x20809062 GPC/XBAR/SYS/NVD actual/target readback: pass
```
