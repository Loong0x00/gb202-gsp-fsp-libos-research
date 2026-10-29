# Minecraft native-Java → CUDA IPC → Feature18: real6K chain passed

The final test used the production Java FrameCodec/LiveNr/NativeIpc classes,
real native GL/CUDA resource interop, real cross-process CUDA IPC imports in
Wine, and a real persistent Feature18 backend. No CPU image transfer exists in
the normal frame path; only this isolated test uploads/retrieves an oracle.

## Final6K evidence

- Active6144x3382; padded CUDA/GL allocations and evaluation6144x3392.
- COPY: one same-frame completion, zero mismatched RGBA8 bytes, zero NR calls.
- NR: one successful Create18/Evaluate/sync/same-frame commit, no timeout at the
  intended100ms completion deadline.55,196,315 RGBA8 bytes differ; alpha unchanged.
- All83,116,032 active raw neural floats checked before the commit shader's
  fallback: finite, minimum0, maximum1.
- Same control ID was deliberately reused while switching COPY→NR: the Java
  session restarted safely rather than retaining the previous configuration.
- Helper processes exited before native/GL resources were released.
- gpu_ms=-1 intentionally. The test/build's8-second wall time is NOT inference
  latency/FPS or a GPU timestamp.

## Provenance / limitations

The test input is a GPU nearest-resample of the previously captured1920x1080
Minecraft scene (20260909-030440-c8602c84). It is NOT a newly captured native6K
world frame. This validates real6K allocation, transport and inference, not
in-game motion stability or a quality improvement. The actual game still uses
0.1.1, NR0; the new0.2.0 candidate must be installed after game exit.

The1920x1080 real-scene run also passed under
../mc-java-cuda-ipc-nr-20260909-0436. An actual post-publication1ms timeout,
completed-but-discarded NR result, unchanged GL output and subsequent COPY
recovery were independently verified under
../mc-java-cuda-ipc-timeout-20260909-0445.

Remaining experimental limitations: camera-only MV (no entity/particle/hand
velocity), unverified jitter/cut flags, empirical LDR color contract, CPU
same-frame completion waiting and potentially blocking CUDA driver API calls.
No SR/RR/FG is enabled. Windows DLL file stays SHA-pinned/unchanged; existing
in-memory native-CUDA compatibility shims are still required.

## Staged candidate

Path: `/home/user/rt_5090_project/minecraft_nr_bridge/staging/20260909-050154-nr-0.2.0`

Jar SHA256: `3618a4dd0ac1b24aa6e1eba12ee1efb01aa3216898bece9cf8a8ed5dfafacfef`

JNI SHA256: `e91ee9fed408211a92c05730580a284209dab09ff8b46ffdc5be0e14f4539cd4`

Backend SHA256: `37151dcb36c087235c42b34607dc8ee6f2e60dbfa3b751db8adc1566b9edea8e`
