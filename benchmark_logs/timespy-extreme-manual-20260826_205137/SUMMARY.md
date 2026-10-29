# Time Spy Extreme stress run — 2026-08-26

## Test identity

- NVIDIA driver: `610.57.04`
- GPU: NVIDIA GeForce RTX 5090
- Enforced/requested/default power limit: `600 W / 600 W / 600 W`
- Workload: `TimeSpyGt1XST`
- Preset and resolution: `X`, `3840x2160`
- Configured loops: `20`
- Raw result status: `SUCCESS`
- Raw result interval: `2026-08-26T12:50:57.494739Z` to `2026-08-26T13:10:28.610844Z`

## Loop result

- Completed loops: `20/20`
- Mean: `149.154405 FPS`
- Minimum: `148.694504 FPS` (loop 19)
- Maximum: `149.505341 FPS` (loop 16)
- Minimum / maximum: `99.4577%`
- First-five mean: `149.184753 FPS`
- Last-five mean: `149.218329 FPS`
- First-five to last-five change: `+0.0225%`
- Linear slope: `+0.003595 FPS/loop` (`+0.0458%` across 19 loop intervals)

No progressive performance loss is present in this run.

## Telemetry

- `nvidia-smi` samples: `23230` at nominal 50 ms interval
- Peak instantaneous GPU power: `459.95 W`
- Peak averaged GPU power: `458.03 W`
- Per-loop average graphics clock: `2931–2934 MHz`
- Maximum observed graphics clock: `3007 MHz`
- Maximum GPU temperature: `61 C`
- Maximum hotspot temperature: `71 C`
- Maximum connector power reading: `461.914 W`
- Maximum single pin current reading: `7.220 A`
- Minimum pin voltage reading: `11.776 V`
- NVIDIA throttling/event flags observed: `0`
- Kernel Xid/GSP/reset events observed: `0`

## Instrumentation note

At `20:51:37`, the first watchdog instance treated a transient `25.799%`
relative pin-current spread at `436.620 W` as a fault and terminated the
3DMark Java/CEF front end. The already-running `3DMarkTimeSpy.exe` workload
was not terminated and continued independently through all 20 configured
loops. A replacement watchdog disabled only the relative-spread rule while
retaining GPU/hotspot temperature, single-pin current, connector voltage,
connector power, and kernel-event monitoring.

Because the front end was gone, it did not package an ordinary
`.3dmark-result` or display its final UI. The independent workload output is
complete, checksum-bearing, and reports `SUCCESS`; its configuration, raw
result, system-info monitoring, and external telemetry are preserved here.
