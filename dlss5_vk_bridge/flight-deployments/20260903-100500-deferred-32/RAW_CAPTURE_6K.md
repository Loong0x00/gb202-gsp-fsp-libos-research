# Wuthering Waves bounded dynamic 6K raw capture

This diagnostic service is idle at game startup. It records only after a
runtime trigger is created while the game is already running, the login/settle
phase gate is open, and post-SR output is exactly 6144×3456.

Global controls:

- `Super+Alt+W`: launch the configured 6K game profile.
- `Super+Alt+C`: two-stage deferred Flight control. First press preallocates;
  after the ready notification, the second press starts 32 frames.

Per captured frame:

1. `pre-nr.raw`: completed signed RR output before codec/Feature18.
2. `post-nr.raw`: final output after codec/Feature18/decode.
3. `color.raw`: original game Color input consumed by signed RR.
4. `motion.raw`: original engine motion vectors, not inferred optical flow.
5. `depth.raw`: original engine depth.

Files are little-endian with tightly packed rows. `manifest.jsonl` records
formats, physical and active dimensions, subrect bases, GPU/file row pitch,
Reset, jitter, MV scale, flags, mode/result, UTC, QPC and bridge frame.

## Hard bounds

- Current Flight hotkey window: 32 frames (about 1.1 seconds at 30 fps).
- Normal `arm`/`toggle` helper default: 24 frames.
- Native fallback for an empty/malformed trigger remains 4 frames.
- Native hard maximum: 32 frames.
- Expected five-surface payload: about 0.28–0.31 GiB/frame.
- Validated 4-frame payload: 1,137,151,872 bytes (about 1.06 GiB).
- Default 24-frame estimate: about 6.4 GiB; worst 32-frame estimate about 8.5 GiB.
- Readback allocation cap: 12 GiB.
- Host helper requires at least 15 GiB free.
- Ring: 32 non-dropped slots. Saturation stops instead of creating a gap.

No raw frame is written from process startup. Service registration and normal
launch clear stale trigger/stop/active markers. The host helper refuses to arm
unless the game PID exists, `enable-dlss5` confirms stable gameplay, and latest
Router telemetry reports exactly 6144×3456.

In the current deferred Flight build, the first `Super+Alt+C` press allocates
all 32 complete five-surface slots before the target event. Wait for the ready
notification. The second press begins recording; press R immediately. No
per-frame fence signal, Map, worker write or disk I/O occurs during those 32
frames. At their end, one Present-boundary signal covers the whole window and
only then does the worker map/write it. Do not exit until the completion
notification. Pressing the hotkey while active requests an early drain.

## GPU completion contract

Copies are appended after successful `EndVkCommandBufferInterop` and after the
GPU timing endpoint. Sources are transitioned temporarily to `COPY_SOURCE` and
restored. The render thread never maps or waits. ReShade API-18 submission
identifies the native queue; same-thread Present emits a serialized D3D12 fence
signal. The worker maps only after `GetCompletedValue` proves completion.

## Commands

```bash
# Current two-stage hotkey flow
./tools/wuwa_raw_capture.sh flight   # first call: preallocate
./tools/wuwa_raw_capture.sh flight   # after ready: start 32, then press R

# Explicit normal capture remains available
./tools/wuwa_raw_capture.sh arm 4

./tools/wuwa_raw_capture.sh status
./tools/wuwa_raw_capture.sh stop
./tools/wuwa_raw_capture.sh latest
```

Output directory:

`Client/Binaries/Win64/dlss5-raw-captures/`

Current deferred Flight build target:

```bash
make build/post-service-deferred-flight/01-dlss5-post-service.addon64
```
