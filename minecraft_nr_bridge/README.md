# Minecraft Java 26.1.2 — native Linux NR bridge

## Current state

**0.2.0 was installed after confirmed game exit on2026-09-09 at05:51.**
`mods/nr-scene-probe-0.2.0.jar` is the only active probe jar; the previous0.1.1
was archived. The49 unrelated mod/config hashes were verified unchanged.
The immutable runtime and rollback are in
`deployments/20260909-055105-nr-0.2.0`; `CURRENT_DEPLOYMENT` points there.
`nrbridge/backend-install.json` selects this runtime. On2026-09-09 at06:40,
actual-world6144x3382 validation completed120 successful Feature18 evaluations
and120 same-frame commits. Continuous mode was then explicitly enabled; the
following20-second observation recorded503 additional commits with zero timeout,
late discard or error. NR was subsequently turned OFF after user feedback of no visible benefit and32FPS; no raw captures were requested.
See`benchmark_logs/mc-live-nr-6k-20260909-064045` for in-game evidence.
Visual quality and long-term temporal stability still require acceptance.
Never hot-replace the jar/native libraries. `CURRENT_CANDIDATE.json` retains the
independently verified package provenance.

The new path is actual **OpenGL → native JNI/CUDA → CUDA IPC → Wine Feature18 →
CUDA IPC → OpenGL**, not a CPU screenshot relay. Minecraft itself remains native
Linux Java. Only the separate NVIDIA Windows runtime process uses Wine.

### Evidence already obtained

- Actual OpenGL3.3 codec test: top-left orientation, padding, alpha-preserving
  RGBA8 copy commit, analytic camera motion(+2,-3.25pixels), and restored GL state.
- Actual Java/JNI/Wine shared-memory COPY: original Minecraft scene remains
  byte-identical. COPY performs zero Feature18 evaluations.
- Actual Java/JNI/Wine NR at1920x1080(active)/1920x1088(padded): one successful
  Create18/Evaluate, same-frame commit, all8,294,400 output floats finite[0,1].
- Actual same pipeline at **6144x3382(active)/6144x3392(padded)**: COPY byte-identical;
  NR Create/Evaluate/sync/commit successful, all83,116,032 active output floats
  finite[0,1],55,196,315 RGBA8 bytes changed, alpha unchanged. The final run passed
  with the intended100ms completion timeout and had zero timeouts.
- The6K test input is explicitly a GPU nearest-resample of the previously
  captured1080p scene. This proves6K resource/inference/transport execution, **not
  a new native6K game capture or temporal/visual-quality acceptance**.
- A genuine lazy Feature18 request deliberately missed1ms **after publication**;
  the runtime really evaluated it, the late output never reached GL, and COPY
  recovery retained the pending NR history reset.
- Eleven ordinary CPU/GL tests passed; real NR/IPC tests are opt-in and were
  executed separately. Same-ID config mode changes restart the session safely;
  deleting/restoring identical config no longer leaves it permanently disabled.

Evidence directories under`/home/user/rt_5090_project/benchmark_logs/`:

- `mc-java-cuda-ipc-copy-20260909-0434`
- `mc-java-cuda-ipc-nr-20260909-0436`
- `mc-java-cuda-ipc-6k-final-20260909-0451`
- `mc-java-cuda-ipc-timeout-20260909-0445`

The old actual-world scene-seam validation remains documented in
[docs/STAGE1_0.1.1.md](docs/STAGE1_0.1.1.md).

## Target and preservation

Target`/home/user/minecraft/26.1`: actual26.1.2/Fabric0.19.2/Java25,
Sodium0.8.12-beta.3/Iris1.10.9. No account/launcher data, other mods, original
options, Iris settings, world files, or`realtime_aixi` bridge are modified.
Iris shaders must already be OFF; unknown/on/fallback/shadow/post-effect paths
are rejected rather than automatically changing the user's configuration.

The verified hook remains`GameRenderer.renderLevel` after
`LevelRenderer.renderLevel`, before the hand depth clear, hand and HUD. Actual
world-draw camera/model-view/projection locals include bob/hurt/portal effects.
Camera position is double precision and coordinates are camera-relative.

## Inputs and limitations

- Stock RGBA8 LDR scene only. GPU shaders normalize to float values and prepare
  owned RGBA32F/R32F/RG32F textures; output is RGBA32F and alpha is preserved on
  RGBA8 commit. Color is an empirical render-target RGB/255 contract, **not
  asserted HDR-ready or physically color-managed**.
- GL window depth[0,1], non-inverted; unprojection uses NDC`d*2-1`.
- Backward camera-only pixel motion uses current/previous actual matrices and
  double-position delta. **No entity/particle/hand motion vectors**.
- Jitter is not injected or authoritatively verified. Camera cuts use world/
  texture/size invalidation plus a conservative motion heuristic, not a game
  camera-cut flag.
- Shapes pad to16, clamp border inputs, and crop the same-frame result to active
  size. Max dimension8192 and max33,554,432 padded pixels are working-set limits,
  not a4K capability restriction.6K is explicitly supported by code and tests.
- No SR/RR/FG is added here: Feature18 is NR at the supplied resolution.
- GPU inference timestamps are **not measured**: `gpu_ms=-1`. Build/test wall
  time is not inference performance. The prototype intentionally waits on the
  CPU for same-frame completion, with a1..250ms polling deadline. CUDA driver
  map/unmap/API calls can themselves block; this is not a strict whole-call
  real-time bound or an asynchronous zero-stall renderer.
- Single/reset/static tests do not establish motion stability or fix the older
  unrelated WuWa6K temporal failure. Actual target-instance inference/commit has
  now passed; visual quality and longer motion stability remain separate checks.

## Completion and lifetime rules

Images never enter the JVM heap in the normal frame path. Three owned GL input
textures are copied on GPU to exported CUDA linear allocations; the helper
imports64-byte CUDA IPC handles, uses persistent CUDA arrays/Feature18 history,
then publishes completion only after actual GPU synchronization.

The4096-byte shared file is CPU control only. Release/acquire request/completion
sequences, immutable in-flight inputs, and same-call completion prevent late
results from masquerading as current frames. Busy/timeout/error means the game
color is not committed. A skipped or discarded NR result forces history reset;
COPY cannot consume that reset. There is no unbounded external GL semaphore wait
on a potentially dead peer.

Normal disable/resize stops the exact helper and waits asynchronously for its
exit before releasing imported allocations. At`Minecraft.destroy`HEAD, the final
shutdown/quiescence wait is deliberately allowed to block so the exporter does
not disappear while the importer is alive. The application launcher must **exec
Wine directly**, not return early or hide it behind a timeout wrapper.
`tools/run_nr_backend_direct.sh` is the application launcher; the worker's
`tools/run_nr_backend.sh` is only a separately bounded standalone utility.
No global wineserver/process kill is used.

## Controls (after0.2 deployment)

Default is OFF. The installer must publish an immutable runtime manifest at
`nrbridge/backend-install.json`; explicitly generated`nrbridge/live.json`
requests enable the service:

```sh
python3 tools/nr_ctl.py status
python3 tools/nr_ctl.py on --mode copy --frames 1
python3 tools/nr_ctl.py on --mode nr --frames 120
python3 tools/nr_ctl.py on --mode nr --frames 0   # explicit continuous operation
python3 tools/nr_ctl.py off
```

Default timeout100ms/intensity1. Tone1/structure1/skin-1/style0/AutoMaskOFF use the
proven runtime defaults. Runtime identity/DLL version is SHA-pinned. As with the
existing native CUDA probe, the signed DLL file is unchanged but process-local
identity/device-layout/Blackwell compatibility shims are applied; this is not an
unmodified Windows runtime execution environment.

Diagnostics remain separate (`tools/probe_ctl.py`). In0.2 they allow up to4 frames,
1GiB/request and2GiB total capture directory, with a Java heap-headroom check and
fence-before-map. Controls and raw persistence use separate executors so a large
raw hash/write does not block disable polling. No automatic raw capture.

## Build and explicit real tests

```sh
native/build_native.sh
native/build_backend.sh
JAVA_HOME=/usr/lib/jvm/java-25-openjdk \
 /home/user/.gradle/wrapper/dists/gradle-9.4.1-bin/arn2x92ynaizyzdaamcbpbhtj/gradle-9.4.1/bin/gradle build
```

GL tests require DISPLAY=:0 and the current XAUTHORITY. Ordinary build skips
real-service integration tests unless explicitly enabled:

- `MCNR_RUN_IPC_TESTS=1`, filter`LiveNrIpcTest`; optional
  `MCNR_TEST_WIDTH=6144 MCNR_TEST_HEIGHT=3382`, `MCNR_TEST_TIMEOUT_MS=100`.
- `MCNR_RUN_TIMEOUT_TESTS=1`, filter`NativeTimeoutTest`.
- Set a fresh`MCNR_IPC_EVIDENCE`directory. Use`--rerun-tasks` when changing test
  environment variables. Test-only CPU uploads/readbacks/oracles are not part of
  the game's transport path. Tests never open a user world or control live NR in
  the user's running Minecraft instance.
