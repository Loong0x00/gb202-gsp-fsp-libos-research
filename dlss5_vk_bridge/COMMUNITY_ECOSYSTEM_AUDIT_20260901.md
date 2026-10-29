# DLSS 5 community ecosystem audit — 2026-09-01

## Scope

Static/source review only. No downloaded community binary was executed. Public repositories were cloned at:

- `NIGos/dlss5-bridge` commit `38c3e2c24784fc344f1c3cc2bc1631f4b0cc07ca`
- `jlrouzies-fr/DLSS5-Feeder` commit `5347efcab9e603393a2ba32b36eea5cb0433d0a5`
- `NoelGamer/dlss5-opengl-bridge` commit `dfab14a7ca08e8510b1912672b402a017dc3e64e`
- `Kizzuwatnaa/DLSS5-Autopilot` commit `da9d64dd506ec71af7fe9622e42f2ad39172e6f4`

## GPU generations

### Stock runtime

The locally deployed stock `nvngx_dlssnr.dll` is 165,840,496 bytes, SHA-256
`e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e`, and its CUDA fatbin records contain only SM 120 (RTX 50 / Blackwell): 30 records.

### Community SF-v2 runtime

GitHub release:

- `RankFTW/rhi-repo`, tag `dlssnr-310.8.SF-v2`
- ZIP SHA-256 (matches GitHub release digest): `1da35941894994eb087e017577829e492454e9bae3a6a9397027069ceb74955c`
- Extracted DLL SHA-256: `6eb209e764f39872625debd6abaf45e2bb6322f6f270f781f70c059ae30b3927`
- File version string: `310.8.SF.0`, original CL `38718415`
- Fatbin architecture/count: SM75×15, SM86×15, SM89×15, SM120×23

This proves that this modified binary contains architecture-specific images for RTX 20 (Turing), RTX 30 (Ampere), RTX 40 (Ada), and RTX 50 (Blackwell). It does not by itself prove successful execution or correct output on every card.

The SF-v2 file is exactly 10,352 bytes shorter than the stock file—the size of the stock Authenticode certificate. Its PE security directory still points to that now-EOF offset and its PE checksum is stale. It is modified/unsigned community code, not a valid NVIDIA-signed DLL.

Public execution evidence:

- RTX 40: Tom's Hardware reports independent execution verification on RTX 4080; settings/performance provenance is incomplete.
- RTX 30: numerous community screenshots/reports exist across 3070/3080/3080 Ti/3090, generally with severe cost; most are uncontrolled.
- RTX 20: one detailed self-report on RTX 2070 Mobile Max-Q under Linux/Proton reports execution and Turing CUBIN/SASS analysis, but publishes no raw run bundle, hash, exact FPS, or GPU timestamp trace. The proposed ~15 ms target is speculation, not a measurement.
- GTX 16: shares SM75 with RTX 20, so the installer's fatbin check accepts the architecture, but GTX 16 lacks Tensor Cores and no credible successful run was found. Architecture presence is insufficient.
- GTX 10/Pascal: the public SF-v2 file contains no SM61 image. This is worse than merely “not yet tested”; the current public binary has no Pascal-targeted code path.

## Graphics API support

This is an ecosystem of routes, not one runtime natively supporting every API.

| Front-end API | Evidence/status | Actual route |
|---|---|---|
| D3D12 x64 | Strong | Native NGX calls or same-device synthetic contract |
| D3D11 x64 | Strong | New `renodx-dlss` private D3D12 endpoint, NIGos bridge, or Feeder |
| D3D9 x64 | Binary/static claim, public closed build | `renodx-dlss` On Present path; private D3D12 endpoint, often dummy temporal inputs |
| D3D9 x86 | Verified Feeder game row | dgVoodoo2 D3D9→D3D11, then x86 feeder + x64 helper |
| D3D10 | **Not supported by current Feeder source** | Would require translation to D3D11/12; Autopilot calls it a “long shot” and says nothing hooks D3D10 |
| Vulkan x64 | Beta but real | ReShade Vulkan layer + shared Vulkan/D3D12 memory/fences; tested in BG3/RDR2/DOOM 2016 depending project |
| Vulkan x86 | Implemented, not game-verified | x86 feeder + x64 host; only transport spike is documented |
| OpenGL x86 | Verified Feeder game row | GL↔D3D12 shared resources + x64 helper (Worms Ultimate Mayhem) |
| OpenGL x64 | Implemented | In-process Feeder or separate OpenGL bridge; standalone transport proven, but Feeder README has no x64 game row |

The public `renodx-dlss` SF 0.3 binary was inspected but not run:

- Release ZIP SHA-256: `ec457ad16db80e7fa737f78fc771b46285992cf36bc4f879a4368fda1d5b74c8`
- Add-on SHA-256: `8404b19237ab6c3f7b32c6ba0235c25568ee28a2d4be06377ab8c1ea0d3addc7`
- Its strings explicitly say: “On Present supports D3D9, D3D11, and D3D12 presentation.”
- It contains D3D9Ex upgrade/private D3D12 proxy code, D3D11/D3D12 NGX entrypoints, and dummy-temporal presentation paths.
- It does not advertise D3D10, Vulkan, or OpenGL in that supported On Present sentence. Those require other projects/routes.

## 32-bit bridge

Confirmed in public Feeder source, not just a concept:

- x86 ReShade add-on captures color/depth/estimated motion textures.
- A bundled x64 host loads 64-bit NGX and the x64 neural-rendering add-on.
- Shared NT-handle GPU textures and fences carry frames across the process boundary.
- No image pixels need to traverse CPU/system memory.

Verified public game rows include 32-bit D3D11, wrapped D3D9, and 32-bit OpenGL. 32-bit Vulkan is implemented but lacks a game row.

## Synthetic “DLSS contract”

Confirmed by open source. DLSS5-Feeder constructs a real NGX DLAA evaluation from:

- the final/backbuffer color,
- a ReShade-selected depth buffer,
- estimated optical-flow motion vectors,
- an optional trust/bias-current-colour mask.

The neural-rendering add-on then intercepts that genuine NGX evaluate and inserts Feature 18. This is a real NGX call with synthetic inputs—not a native engine integration.

Important limits:

- Feeder is normally DLAA (render size = output), not genuine engine low-resolution DLSS SR.
- No engine jitter; UI is usually processed with the scene.
- Motion is optical flow, not authoritative camera/object velocity.
- Lighting changes, particles, transparency, disocclusion and HUD can create wrong history.
- The new `renodx-dlss` presentation path can use dummy temporal inputs for no-DLSS D3D9/D3D11 presentation.

## Emulators

Public evidence levels must be separated:

- **PCSX2 / PS2:** public visual demonstrations exist. They establish an experimental post-process result, not official/native PCSX2 integration. A misleading PCSX2 commit titled `GS: Add RT/PT and DLSS/DLSS5` (`88da513a...`) changes only one Qt `.ui` file (158 additions/60 deletions) and contains no renderer backend implementation.
- **Dolphin / GameCube-Wii:** public comparison images and an author claim about motion vectors exist, but no source patch, logs, binary hashes, MV debug output, or continuous proof video. The public evidence is consistent with ReShade optical flow over the completed frame.
- **DuckStation / PS1, PPSSPP / PSP, Xenia / Xbox 360:** listed as compatible D3D11/12 profiles by DLSS5-Autopilot, but that list is a routing/capability table. No independent public run logs or reproducible demonstrations were found in this audit.

Therefore the defensible public statement is: PCSX2 has demonstrations, Dolphin has weaker demonstrations, and the other named emulators are plausible/installer-supported targets but not publicly verified to the same standard. Discord may contain additional evidence not available in public repositories.

## Bottom line

The broad community breakthrough is real:

1. modified runtimes now contain SM75/86/89/120 GPU code;
2. open bridges can synthesize a DLSS contract in software without native DLSS;
3. D3D11/D3D12, Vulkan, OpenGL, wrapped D3D9, and cross-bitness host paths exist in code;
4. emulator final-frame processing is technically straightforward once ReShade depth and optical flow are available.

The overclaims are also real:

- D3D10 is not presently a native/supported path in the audited source;
- “all emulators confirmed” exceeds public evidence;
- SM75 presence does not prove GTX 16 works;
- Pascal/GTX 10 is absent from the current public SF-v2 fatbin;
- synthetic final-frame processing is not equivalent to an emulator/game exporting native depth, motion, jitter, exposure, and HUD masks.
