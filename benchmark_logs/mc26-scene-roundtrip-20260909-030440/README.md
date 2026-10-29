# Actual Minecraft Java world: one-frame GL roundtrip passed

Target: /home/user/minecraft/26.1 (actual26.1.2, Fabric0.19.2, Sodium0.8.12-beta.3,
Iris installed but shaders OFF). Loaded probe0.1.0 SHA256
688cc996f5c32fd630c27a4e1b07142c2685dff36b15fed3b196a796f605943d.

Only one on-demand roundtrip request was sent. Raw payload is retained at:
/home/user/minecraft/26.1/nrbridge/captures/20260909-030440-c8602c84/frame-01.bin

- 1920x1080; 74,649,600 bytes: RGBA32F before, R32F depth, RGBA32F after.
- Metadata's SHA256 was independently verified against the payload.
- Before/after color bit-identical, both Java and Python checks.
- Fence completed before Map/readback; no automatic continuous capture.
- All color/depth floats finite. Raw depth min0.9864106774/max1;
  exactly1 pixels27.0706%, exactly0 pixels0%.
- Current/previous projection determinant about-0.1147292; view determinant~1.
- Actual pre-hand/pre-HUD scene image shows redstone machinery. Depth-contrast
  preview shows matching world geometry; it is a viewing-only normalization,
  not the raw data or a changed depth input.

This validates the actual world capture seam and local GL copy-back, NOT
cross-process shared memory, motion vectors, or NR. Feature18 evaluations=0.
No game settings, world blocks, or loaded jar were changed in this session.

A stale loading/transition status had mentioned an Infinity JSON error; it did
not affect this successful capture. Source-only staged0.1.1 rejects nonfinite
camera fields before GPU work/serialization. Six CPU tests passed; deployment
is deferred until the user exits the game.
