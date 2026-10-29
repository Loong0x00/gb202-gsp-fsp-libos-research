# Wuthering Waves deferred 32-frame Flight recorder

## Why

The visible bad frame persists with:

- a D3D12 UAV barrier;
- an output UAV/COPY_SOURCE/UAV transition;
- a real full-output copy;
- the complete five-resource transition/copy set used by raw capture.

Therefore the earlier clean raw window was not caused by those GPU barriers or
copies alone. The remaining capture-time disturbances were per-frame queue
fence signals, concurrent Map/packing/disk writes, lazy slot allocation, or an
ordinary non-occurrence. This recorder removes those activities from the
32-frame target interval.

## Binary

Previous five-copy A/B:

`466e2cac1b9e3c05a3b3f040488490a6d392077bd434546f2c239053e8c15e6c`

Current reviewed Flight v2:

`4a4fb4c063f078b7fcf113fb12ad312d5988f1aec934a73398d0c878bf7c00cc`

## Runtime contract

1. Preparation allocates all 32 complete five-resource slots before the skill.
   Expected charged allocation is about 8.49 GiB, below the fixed 12 GiB cap.
2. Recording uses the same five GPU copies already proven not to suppress the
   defect.
3. During the 32 target frames there is no queue Signal, fence completion
   polling, Map, worker write, row packing, or disk I/O.
4. At the Present after frame 32, one queue fence covers all submitted slots.
5. Only after that fence completes does the worker write approximately 8.5 GiB
   of raw files and finalize the manifest.

## Hotkey procedure

After normal 6K launch and the login gate has opened:

1. Press `Super+Alt+C` once while idle. Do not press R yet.
2. Desktop notification banners are disabled on this GNOME profile, so wait
   for the newly added completion sound instead.
3. Press R first, then immediately press `Super+Alt+C` a second time. The first
   live attempt used the reverse ordering and spent its 32-frame window on an
   already-running enemy attack, ending about 0.23 seconds before the target R
   cinematic began.
4. Wait for the completion sound before exiting the game.

The second-stage window is 32 Feature18 frames, about 1.1 seconds at 30 fps.
A hotkey press while active requests an early drain. No startup-time automatic
raw recording is enabled.

## Safety and rollback

- 6K only, five typed single-plane resources only.
- 32-slot and 12-GiB hard limits remain.
- Host requires at least 15 GiB free disk space.
- Evaluate return semantics are unchanged on capture failure.
- `restore.sh` restores the previous five-copy build, only while the game is
  stopped.

A practical static review confirmed the clean Wuthering Waves single-thread
submission path. Cross-thread execute/Present would be unable to drain all
slots; if the active marker does not disappear, do not exit or trigger another
capture and inspect `dlss5-raw-capture.log` first.
