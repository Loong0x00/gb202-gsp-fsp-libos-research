# 480p ultra-performance + 4x frame-generation probe — 2026-08-01

## Black Myth: Wukong Benchmark Tool

- Output resolution: 854x480
- Full ray tracing: level 3
- Quality preset: cinematic
- Requested super-resolution scale: 33% linear (approximately 285x160 input)
- Requested frame-generation mode: `InsertFrame=3`
- Benchmark JSON accepted: `ScreenResolution=854x480`, `ImageQuality=14`, `Rtx=3`, `Dlss=2`, `InsertFrame=3`
- Reported FPS: average 257, 95% 227, minimum 118, maximum 337
- Mean of 18,077 frame records: 257.473 FPS
- Mean CPU/GPU frame time: 4.956 / 6.491 ms
- Telemetry: 173.7 W mean, 201.0 W maximum, 3032 MHz mean, 6382 MiB mean VRAM
- No new Xid occurred during this run.

For reference, the earlier native 854x480 run with frame generation disabled reported 109 FPS average, 94 FPS at 95%, 35 minimum, 150 maximum, and approximately 279.7 W mean board power. Because both internal resolution and frame generation changed, the 2.36x reported-FPS increase is not an isolated frame-generation multiplier.

### Exact frame-generation control — 2026-08-02

The benchmark was repeated with the same 854x480 output, `ImageQuality=14`, full RT level 3, DLSS mode 2, and cinematic quality. The only result-field difference was `InsertFrame=0` instead of `InsertFrame=3`.

- Frame generation off: average 145, 95% 128, minimum 97, maximum 179 FPS
- Mean of 20,421 frame records: 145.130 FPS
- Mean CPU/GPU frame time: 4.282 / 6.013 ms
- Telemetry: 196.49 W mean, 212.27 W maximum, 3015 MHz mean, 8123 MiB mean VRAM
- 4x MFG / off multiplier: 257.473 / 145.130 = **1.774x**
- A zero-overhead 4x multiplier would have been 580.520 FPS; the observed output was 44.35% of that ideal.

If `InsertFrame=3` is interpreted as one traditionally rendered frame plus three generated frames, its inferred traditional-render cadence was 257.473 / 4 = 64.368 FPS. Thus MFG produced four output frames per input-frame group while reducing the underlying render cadence from 145.130 to approximately 64.368 FPS in this low-resolution Proton/gamescope test. This is an aggregate observation; it does not isolate neural inference, scheduling, frame pacing, game integration, or translation-layer overhead.

Artifact: `wukong_480p-up-nofg_20260802.json`; SHA-256 `70dae4f10326c73a65d63e6f0409e43ee7413ee4fd34418d95458200f547b437`.

Artifacts:

- `wukong_480p-up-mfg4_20260801.json`
- `wukong_480p-up-mfg4_telemetry_20260801_part2.csv`

## Cyberpunk 2077 2.31

The exact requested combination did not reach the benchmark. At 854x480 with DLSS Ultra Performance and 4x MFG requested, the initial scene stalled and the kernel logged:

`Xid 109, GameThread, CTX SWITCH TIMEOUT, Info 0xec019`

A discriminating control with the same 854x480 DLSS Ultra Performance request but frame generation completely disabled reproduced the same Xid 109. Therefore the failure is already triggered by the ultra-low DLSS input-resolution path at 480p; it is not evidence that 4x MFG alone caused the fault.

Both game configuration files were restored byte-for-byte after testing:

- Cyberpunk 2077 SHA-256: `0049e36cb1e76fc5c3bc6ec19582ab4fdd387cd77c477d48cd7fda2196cb34eb`
- Black Myth benchmark SHA-256: `927753da17bcb2217f16a2b58f6398288f777b147f36d870a26290e51ed328e9`
