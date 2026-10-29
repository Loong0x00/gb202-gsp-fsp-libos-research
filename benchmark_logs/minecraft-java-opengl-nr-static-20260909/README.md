# Minecraft Java / Linux OpenGL NR source audit

Source-only inspection; no game, launcher, shader pack, or driver modification.

## Located implementation

https://github.com/NoelGamer/dlss5-opengl-bridge

Pinned commit: dfab14a7ca08e8510b1912672b402a017dc3e64e
(same revision as the project's earlier 2026-09-01 ecosystem audit).

Code evidence:

- `src/gl_interop.inc`: WGL/Win32 loading; `glImportMemoryWin32HandleEXT`
  with `GL_HANDLE_TYPE_D3D12_RESOURCE_EXT`; semaphore imports use shared D3D12
  fences. Formats include RGBA16F color, R32F depth, RG16F motion.
- `src/d3d12_session.inc:47–53`: `SafeCreateFeature` explicitly creates NGX
  Feature 1 (SuperSampling), not Feature18. Its same-size mode supplies DLAA.
- `src/d3d12_session.inc:583–589`: documents that a separately loaded RenoDX
  add-on must detour D3D12 Evaluate and insert NR. Without that interception,
  this bridge's own calls are ordinary DLAA. An entrypoint detour alone is not
  proof that Feature18 successfully evaluated.
- `src/motion.inc`: depth/current+previous camera matrices reconstruct
  camera-only motion. Dynamic object motion is absent. Default unnamed
  uniforms provide no matrices and hence zero motion.
- README: default backbuffer capture includes UI; optional scene FBO capture
  can run before UI. No engine jitter, no exposure texture, one view per frame.

## Linux / Java boundary

This is a Windows OpenGL ReShade/WGL -> D3D12 bridge, **not** a native Linux
Java/LWJGL mod. Its addon64 DLL and Win32 external-memory handles cannot be
used directly in a native Linux JVM. No verified native-Linux Minecraft Java
Feature18 execution was found in the inspected material.

Potential port architecture (unimplemented/unverified): native Fabric/Iris/JNI
capture before HUD, Linux OpenGL/Vulkan external-memory FD and semaphore
transport, then a compatible Feature18 execution service. The existing Wine
Feature18 evaluator proves only the inference endpoint; it does not prove the
new cross-API/cross-process FD transport or Minecraft motion contract.

Engine-informed capture should prioritize camera and entity motion, camera-cut
Reset, jitter consistency, shader-pack color/exposure conventions, and block
placement/removal disocclusion. Do not label camera-only motion or optical flow
as full engine velocities.

Related public sources:

- https://github.com/jlrouzies-fr/DLSS5-Feeder/blob/main/PLAN-OPENGL.md
  (also Windows external-object path).
- https://github.com/IReallyWantToSleep/superresolution
  (separate Minecraft upscaling/interoperability project; search evidence does
  not establish DLSS5/Feature18 support).
