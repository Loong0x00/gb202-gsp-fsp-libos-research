# Actual Minecraft world6K NR enabled and running

Target instance /home/user/minecraft/26.1, actual26.1.2/Fabric0.19.2,
nr_scene_probe0.2.0. Iris shaders OFF. Original6144x3382 resolution unchanged;
GPU working textures/evaluation pad to6144x3392.

## Real game evidence (not resized/offline test inputs)

- Initial request20260909-064028-cc3df7fb:120 successful Feature18 evaluations
  and120 same-frame commits; Java submitted_frames=applied_frames=120.
- Helper confirms real Feature18 Create, seq1/frame15127 Reset1; subsequent
  samples Reset0, seq120/frame15246 result1/evaluations120, then clean STOPPED.
- Continuous request20260909-064208-f68a9bce: after20-second observation,
 503 further evaluations and503 commits, no timeout, no late discard, no error.
  Total for this game process at that sample:623 actual Feature18 evaluations.
- Continuous mode remains ON (max_frames0). No captures requested, no raw output,
  no resolution/other-mod/options/Iris/world changes.
- No new NVRM Xid found in the06:40:20 onward kernel-log query during validation.

This proves actual in-world inference and same-frame application, including
persistent history use. It is not a visual-quality acceptance, dedicated FPS/
latency benchmark, or proof of indefinite temporal stability. GPU inference
timing remains unmeasured (gpu_ms=-1). Motion vectors are camera-only; entity/
particle/hand velocities and authoritative jitter are not supplied.

Disable if needed:
python3 /home/user/rt_5090_project/minecraft_nr_bridge/tools/nr_ctl.py off
