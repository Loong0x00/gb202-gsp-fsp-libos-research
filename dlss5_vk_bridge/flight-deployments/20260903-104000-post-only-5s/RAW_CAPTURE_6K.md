# Wuthering Waves bounded dynamic 6K raw capture

This diagnostic service is idle at game startup. It records only after a
runtime trigger is created while the game is already running, the login/settle
phase gate is open, and post-SR output is exactly 6144×3456.

Global controls:

- `Super+Alt+W`: launch the configured 6K game profile.
- `Super+Alt+C`: two-stage deferred Flight control. First press preallocates;
  after the ready sound, press R first and then immediately press the hotkey
  again to start 150 post-NR frames (approximately five seconds).

Current five-second Flight payload per captured frame:

1. `post-nr.raw`: final 6144×3456 R11G11B10 output after
   codec/Feature18/decode.

The earlier short-window build captured pre-NR, post-NR, Color, motion and
depth. Five seconds of all five would require roughly 34–43 GB, so the current
first-attribution pass intentionally retains only the decisive post-NR output.

Files are little-endian with tightly packed rows. `manifest.jsonl` records
formats, physical and active dimensions, subrect bases, GPU/file row pitch,
Reset, jitter, MV scale, flags, mode/result, UTC, QPC and bridge frame.

## Hard bounds

- Current Flight window: 150 post-NR frames (about five seconds at 30 fps).
- Exact 150-frame payload/allocation: 12,740,198,400 bytes (11.87 GiB).
- Readback allocation cap remains 12 GiB (12,884,901,888 bytes).
- Host helper requires at least 15 GiB free.
- Ring: 150 non-dropped post-NR slots. Saturation stops instead of creating a
  gap.

No raw frame is written from process startup. Service registration and normal
launch clear stale trigger/stop/active markers. The host helper refuses to arm
unless the game PID exists, `enable-dlss5` confirms stable gameplay, and latest
Router telemetry reports exactly 6144×3456.

In the current deferred Flight build, the first `Super+Alt+C` press allocates
all 150 post-NR slots before the target event. Audible states are deliberately
distinct: one ding means READY, two camera-shutter clicks mean RECORDING
STARTED, and three dings mean SAVE COMPLETE. After the one-ding READY cue, press R first, then
immediately press the hotkey again to begin recording. No
per-frame fence signal, Map, worker write or disk I/O occurs during those 150
frames. At their end, one Present-boundary signal covers the whole window and
only then does the worker map/write it. Do not exit until the completion
notification. Pressing the hotkey while active requests an early drain.

## GPU completion contract

The post-NR copy is appended after successful `EndVkCommandBufferInterop` and
after the GPU timing endpoint. The output is transitioned temporarily to
`COPY_SOURCE` and restored. The render thread never maps or waits. ReShade API-18 submission
identifies the native queue; same-thread Present emits a serialized D3D12 fence
signal. The worker maps only after `GetCompletedValue` proves completion.

## Commands

```bash
# Current two-stage hotkey flow
./tools/wuwa_raw_capture.sh flight   # first call: preallocate
# after ready: press R first, then immediately run/press this
./tools/wuwa_raw_capture.sh flight

# Explicit normal capture remains available
./tools/wuwa_raw_capture.sh arm 4

./tools/wuwa_raw_capture.sh status
./tools/wuwa_raw_capture.sh stop
./tools/wuwa_raw_capture.sh latest
```

Output directory:

`Client/Binaries/Win64/dlss5-raw-captures/`

Current five-second post-only Flight build target:

```bash
make build/post-service-post-only-flight/01-dlss5-post-service.addon64
```
