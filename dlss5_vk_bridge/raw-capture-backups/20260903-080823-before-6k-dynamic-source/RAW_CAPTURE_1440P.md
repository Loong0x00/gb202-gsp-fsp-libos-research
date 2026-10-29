# Wuthering Waves bounded 1440p raw capture

This diagnostic service is idle at game startup. It records only after a
runtime one-shot trigger is created while the game is already running, the
login/settle phase gate is open, and post-SR output is exactly 2560×1440.
`Super+Alt+C` toggles dynamic start/early-stop.

Per captured frame:

1. `pre-nr.raw`: completed signed RR output before the owned codec/Feature18
   pass.
2. `post-nr.raw`: final game output after codec/Feature18/decode.
3. `color.raw`: original low-resolution game Color input consumed by signed RR.
4. `motion.raw`: original engine motion-vector resource (not inferred optical
   flow and not the optional clamped proxy).
5. `depth.raw`: original engine depth resource.

All files are little-endian, tightly packed rows. `manifest.jsonl` records DXGI
format, physical resource dimensions, active guide subrect bases, render/output
dimensions, GPU row pitch, tight file row pitch, bytes, Reset, jitter, MV scale,
flags, mode/result, UTC nanoseconds, QPC and bridge frame.

At expected 1440p Quality dimensions, 32-bit output/MV/depth formats and an
RGBA16F game Color input, the five surfaces are roughly 54–57 MiB/frame. The
hotkey default of 120 frames is roughly 6.5–7 GiB; the native hard maximum of
240 frames is roughly 13–14 GiB. Actual sizes come from D3D12
`GetCopyableFootprints` and are recorded in the manifest.

## Safety and synchronization

- No startup capture: registration and normal launch clear stale trigger,
  stop, and active markers; the helper refuses to arm unless the game process
  exists and `enable-dlss5` proves the gameplay phase gate is open.
- The trigger is bounded (default 120, maximum 240), requires at least 15 GiB
  free space, and is consumed once.
- Pressing `Super+Alt+C` again creates a stop marker; the service stops accepting
  frames and drains only already submitted GPU copies.
- Copies are appended only after `EndVkCommandBufferInterop` succeeds and after
  the existing GPU timing end marker.
- The readback set is signed-RR pre-NR, final post-NR, original game Color,
  engine MV and engine Depth.
- Every source is temporarily transitioned to `COPY_SOURCE` and restored to its
  documented state.
- The render thread never maps or waits.
- ReShade API-18 `execute_command_list` identifies the actual native queue. A
  later same-thread Present serially signals a native D3D12 fence. The worker
  maps only after `GetCompletedValue` proves completion.
- Command-list reset/destruction before submission aborts that recorded slot.
- Readback is a 32-slot ring with a 3 GiB hard allocation cap. Ring saturation
  stops the sequence instead of silently dropping an interior frame.
- Successful/free readback heaps are released at session finalization;
  completion-unproven allocations are intentionally quarantined until process
  exit.
- Capture failures never alter the signed RR or post-service return value.
- Typeless, depth-stencil, planar, block-compressed, array, MSAA, multi-mip and
  clamped-guide inputs are rejected.

The completion boundary relies on Wuthering Waves using a same-thread Present
after queue submission. This is valid for the observed path but still requires
a short live validation before relying on a long diagnostic run.

## Builds

Raw capture only (marker-off avoids GPU timing overhead):

```bash
make build/post-service-capture/01-dlss5-post-service.addon64
```

Raw capture plus the existing GPU timestamp stream:

```bash
make build/post-service-capture-timing/01-dlss5-post-service.addon64
```

Neither target is part of `make all`.

## Trigger helper

Deploy only while the game is fully exited. The helper hashes and backs up the
active service, installs atomically, leaves capture disarmed, and creates a
per-deployment rollback script:

```bash
./tools/deploy_wuwa_raw_capture.sh timing
```

After the game has reached a stable scene and the 15-second phase gate has
opened, use the global toggle:

```text
Super+Alt+C   start up to 120 frames / press again to stop early
```

Equivalent commands:

```bash
./tools/wuwa_raw_capture.sh toggle 120
./tools/wuwa_raw_capture.sh status
./tools/wuwa_raw_capture.sh stop
./tools/wuwa_raw_capture.sh latest
```

For the first fence/state validation, use `arm 4` from a terminal instead of
the 120-frame hotkey. The service consumes the trigger only on an eligible
2560×1440, unclamped frame.
Output is written below `Client/Binaries/Win64/dlss5-raw-captures/`.
