# Minecraft Java 26.1.2: NR scene probe (stage 1)

**This build does not implement or enable Feature18/NR inference.** It prepares
and validates a coherent native-Linux OpenGL scene seam. No Windows ReShade DLL
is injected into Java, and no external-memory/FD transport has been implemented.

## Exact target / preservation

- Game instance: `/home/user/minecraft/26.1`
- Actual Minecraft: 26.1.2 (the launcher version directory is misleadingly named
  `26.1.1-Fabric`)
- Fabric Loader 0.19.2; Java25; Sodium0.8.12-beta.3; Iris1.10.9
- Existing Iris setting: shaders OFF, BSL selected. This setting was not changed.
- Installed jar: `mods/nr-scene-probe-0.1.1.jar`
- Current jar SHA256: `cbf55abfa06da8e86ea15a69341137c68f0fa731381ec97fc3a4b2714c70737f`
- The successful world roundtrip below used the previous 0.1.0 build (`688cc996...`).
- `CURRENT_DEPLOYMENT` points to the backups and `rollback.sh`.
- Existing game options, Iris config, and every pre-existing top-level mod jar
  were hash-checked after deployment. No saves, servers, launch/account data,
  other mods or the realtime-aixi bridge were altered.

## Hook (verified against actual 26.1.2 bytecode)

`GameRenderer.renderLevel(DeltaTracker)` immediately **after** the call to
`LevelRenderer.renderLevel(...)`. This is after world framegraph rendering and
before the first depth clear, hand rendering, screen effects and HUD.

The Mixin captures actual local cameraState/modelViewMatrix/projectionMatrix.
The latter includes bob/hurt/portal projection transforms, unlike the base
CameraRenderState.projectionMatrix. Deep-copied matrices are column-major;
positions are doubles and vertices are camera-relative. Pixel rows are GL
bottom-left; NDC depth is [-1,1]. First frame, world, texture or size changes
invalidate previous-camera metadata.

An initially considered late GameRenderer.render pre-HUD hook was rejected
because its depth had already been cleared for hands. The corrected world hook
is the deployed version and was separately startup-tested. No capture was made
using the discarded late hook.

## Gating and diagnostics

- Default: metadata only; **no automatic readback, no scene copy, no NR**.
- Iris shaderpack/config enable, shadow pass, unknown Iris API, game post effects,
  non-GL backend, unsupported layout, or >3840x2160 capture: reject diagnostics.
- Uses actual OpenGL3.3 + ARB DSA/copy-image/buffer-storage/get-texture-sub-image
  extensions. Do not require reported OpenGL4.5: the tested Minecraft context
  is 3.3 even though all required entrypoints are exposed by NVIDIA.
- `capture`: enqueue raw RGBA float color and depth float reads into a PBO.
- `roundtrip`: additionally copy color to our same-format owned GL texture and
  back, then capture post-copy color for bitwise comparison. Depth is read but
  not rewritten.
- GPU fence is polled with timeout=0; PBO is mapped only after completion. There
  is no glFinish/blocking wait. A bounded CPU copy occurs on the GL thread after
  completion; file hashing/writing happens on a separate worker.
- At most 4 frames/request, 512MiB payload/request, 1GiB capture-directory budget,
  <=2 combined in-flight PBO/write slots. Request expires after60s; fence timeout10s.
- Raw captures are diagnostics, **not a per-frame CPU transport implementation**.
- No real velocity buffer, entity/hand MV, authoritative jitter/camera-cut flag,
  or verified NR color/exposure conversion exists yet; metadata says so explicitly.

## Usage

Launch the ordinary HMCL profile for this instance, enter a world, leave Iris
shaders OFF. From a terminal:

```sh
python3 /home/user/rt_5090_project/minecraft_nr_bridge/tools/probe_ctl.py status
python3 /home/user/rt_5090_project/minecraft_nr_bridge/tools/probe_ctl.py roundtrip --frames 1
python3 /home/user/rt_5090_project/minecraft_nr_bridge/tools/probe_ctl.py capture --frames 1
python3 /home/user/rt_5090_project/minecraft_nr_bridge/tools/probe_ctl.py stop
```

Do not queue repeated requests; each is one-shot and expires after60s. Status:
`/home/user/minecraft/26.1/nrbridge/status.json`. Capture payload and metadata:
`nrbridge/captures/<request-id>/frame-01.{bin,json}`.

Inspect a saved frame (CPU only, no inference):

```sh
python3 tools/inspect_capture.py /path/to/frame-01.json
```

## Verification actually performed

- Build and 5 JUnit tests passed with Java25/Loom1.15.5.
- Hidden native OpenGL3.3 context on RTX5090/610.57.04: patterned color roundtrip
  byte-identical, depth0.5 exact, pixel-pack bindings/state restored, readback
  performed only after completed fence.
- Driver advertises GL_EXT_memory_object_fd and GL_EXT_semaphore_fd. This proves
  extension availability only, not cross-process sharing.
- Isolated Minecraft26.1.2 development client with exact Sodium/Iris/Fabric API
  jars started successfully and loaded the corrected Mixin; status reached
  `ready_waiting_for_world`. No user save was opened. Development windows stopped.
- **Target-instance world validation PASSED (2026-09-09 03:04):** one 1920x1080
  scene roundtrip, 74,649,600 raw bytes. Color before/after bit-identical; color
  and depth finite; depth range 0.9864106774..1, 27.07% exactly1. Current/previous
  projection and view matrices finite and invertible. Color/depth previews show
  matching redstone structures without HUD/hand. See captures/20260909-030440-c8602c84
  under the game's nrbridge directory and benchmark_logs/mc26-scene-roundtrip-20260909-030440.
- **Feature18 Create/Evaluate: not implemented, zero calls.**

### 0.1.1 finite-camera fix — deployed after confirmed game exit

A stale status error reported a non-finite camera value during a prior transition.
The successful capture above has no such values. Source now rejects uninitialized
or non-finite camera position/matrices/angles before serialization or GPU work;
it does not make invalid floats acceptable JSON. Seven tests passed (six CPU,
one real OpenGL3.3 roundtrip test).
`build/libs/nr-scene-probe-0.1.1.jar` SHA256:
`cbf55abfa06da8e86ea15a69341137c68f0fa731381ec97fc3a4b2714c70737f`.
Deployed at 2026-09-09 03:43 after the user exited Minecraft and process absence
was checked. Version0.1.0 was archived; only0.1.1 is active. The 49 unrelated
mod/config files were hash-verified unchanged. No captures or NR were enabled.
`CURRENT_DEPLOYMENT` points to the new backup and rollback to0.1.0.

## Build

```sh
JAVA_HOME=/usr/lib/jvm/java-25-openjdk \
 /home/user/.gradle/wrapper/dists/gradle-9.4.1-bin/arn2x92ynaizyzdaamcbpbhtj/gradle-9.4.1/bin/gradle build
```

GPU tests need the logged-in display environment (`DISPLAY=:0` and the current
`/run/user/1000/.mutter-Xwaylandauth.*` XAUTHORITY). They create an invisible test
window. Tests touch neither the game instance nor its worlds.

## Remaining NR integration

1. Verify real world color/depth pairing, matrices, resize and shader-on gating.
2. Exportable Vulkan/CUDA-owned resources -> FD import into owned GL textures;
   native JNI/FFM SCM_RIGHTS IPC and safe synchronization/peer-loss protocol.
   GL external objects support import, not exporting the existing main texture.
3. Match color/exposure/jitter and motion contracts, then connect the existing
   isolated Feature18 evaluator. Never feed stale NR color with current guides.
4. Only after byte-identical passthrough and bounded real-frame checks, enable
   experimental per-frame NR. Unsupported paths must leave the game unchanged.
