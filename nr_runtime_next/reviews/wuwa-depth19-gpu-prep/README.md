# Owned WUWA depth19 GPU preparation — NOT EXECUTED ON GPU

Scope: this NEW directory only. No edits to `reviews/wuwa-sr-depth19-fix`,
production sources, existing tests, root configuration, accounts, or game installs.
No Wine, GPU, game, NR, SR, network, or deployment was run by this worker.

## What is prepared

`probe.cpp` links **actual FormatBridge**, not a replacement normalization shader.
It sets WUWA + ordinary SR + PRE, `source_rgba16_float`, same-frame synthetic
attestation, RGBA16F color, and typed RG16_FLOAT motion (34/34).

Cases, in order:

1. Legacy R32_FLOAT depth resource/view 41/41; crop origin (0,0).
2. R32G8X24_TYPELESS resource19 / R32_FLOAT_X8X24_TYPELESS SRV21; origin (0,0).
3. Same 19/21 pair; nonzero crop origin (1,1), reaching both resource edges.

Every input is **32x20**, active extent **31x19**. Case 2 has right/bottom
padding; case 3 has left/top padding. This represents the padding/crop class of
the reported real 4100x2308 depth resource / 4099-wide active extent, **not** its
allocation size, performance, game capture, or a real 6K workload.

The historical `tests/format_gpu/format_gpu_harness.cpp` D3D12 upload/readback,
DSV fixture, owned queue/fence, and failure handling are reused/adapted locally.
No transport helper or NGX DLL is required.

### Future GPU assertions (not yet verified)

- DSV clears depth **.375 / stencil9** in the active region, **.875 / stencil77**
  in padding. Normalized readback must be bit-exact R32 float .375, not stencil.
- MV readback must be RGBA16F **(.5,-.25,0,0)**, not SNORM interpretation or padding
  sentinel (8,-8). Coordinate-coded RGBA16F verifies crop position exactly.
- Output resources are exactly 31x19. Full source color/MV readbacks, including
  padding, remain unchanged. Depth source state is observed, but raw depth/stencil
  source planes are not separately read back.
- Test-only forwarding `DeviceObserver` captures the **actual production
  CreateShaderResourceView call** and then invokes the real D3D12 device unchanged.
  It requires one depth SRV, format21, texture2D, plane0, one mip; three SRVs total.
  D3D12's SRV creation API returns void: descriptor observation + debug validation
  when available + actual sampled pixels jointly establish the result, not an HRESULT.
- `ListObserver` forwards real calls and checks exactly three dispatches and actual
  before→NON_PIXEL_SHADER_RESOURCE→before barriers for each source, ALL_SUBRESOURCES
  (both depth/stencil planes). No vtable patching or production instrumentation.
- Invalid19/view41 and one-pixel overflow are rejected with **zero forwarded
  command-recording calls, zero SRVs, zero token, no slot allocation** in the rejection
  scope. GPU setup writes exist separately; this does not claim an entire GPU process
  has no writes. The separate CPU test performs no D3D calls at all.
- Fake identity NR producer returns owned normalized color; actual PRE commit must
  return that replacement and record **no game-output writes**. Fake result fields
  (`evaluated`, `actual_nr_calls=1`) are explicitly synthetic, never NR evidence.
- Uses its own direct queue + D3D12 fence. Setup and test submissions both wait for
  **actual GetCompletedValue >= signaled value**, reject UINT64_MAX, then read back
  and retire. Signal alone never authorizes reuse/release. Unknown completion,
  timeout, or signal failure exits via ExitProcess without C++ destructor release.
- Requests D3D12 debug layer + GPU-based validation if available. If unavailable,
  reports that limitation explicitly: pixel/crop/barrier observations are **not a
  comprehensive no-OOB/debug-clean proof**. Partial dispatch groups intentionally
  exercise the production shader's extent guard. Strict no-OOB acceptance requires
  GPU validation and a clean info queue, not just DATA_PASS.

`observers.h` is generated from the installed MinGW GCC/x64 interfaces. Wrappers
are test-scoped, preserve real COM identity through forwarded QI/AddRef/Release,
and remain alive through submission retirement. This is not a general COM proxy.

## CPU/crosscompile evidence produced here

```
make all       # passed, local base .a + PE32+ x86-64 executable + native CPU test
make controls  # passed: legacy, wrong view, crop overflow, CPU state round trips
make check     # EXPECTED FAIL with base validator: WUWA19/21 rejected at both origins
```

See `build.log`, `cpu-controls.log`, `cpu-updated-expectation.log`, and
`build/inputs.sha256`. The default CPU suite **requires updated acceptance**;
`--controls-only` is diagnostic and must not be promoted to acceptance.
The base executable is only a compile artifact and is expected to stop at 19/21
normalization if run. No GPU DATA_PASS has been obtained.

**Final handoff update:** Main's concurrent `MAIN_FIXED_BUILD.log` was discovered
while finishing base verification. That log was left untouched. Base artifacts
were preserved as `build/wuwa_depth19_probe.base.exe`, `build/test_plan.base`, and
`build/base-inputs.sha256`; then the current fixture was relinked with the actual
archive Main selected, read-only:
`../wuwa-sr-depth19-fix/source/adapters/format_bridge/build/libnr_format_bridge.a`.
The matching fixed `format_plan.cpp` CPU suite **passes all tests**, including
19/21 at both origins. See `fixed-relink.log`. Current `build/wuwa_depth19_probe.exe`,
`build/test_plan`, and `build/inputs.sha256` now describe that **fixed-library**
build; both manifests were verified. GPU execution remains unperformed.
A bare `make all` still deliberately selects base and will overwrite these
current artifacts; retain the explicit overrides below for fixed builds.

## Handoff / staging instructions for Main

First obtain/review the separately assigned fix; this directory does not apply it.
After Main compiles the fixed production library, relink this fixture against it:

```sh
cd /home/user/rt_5090_project/nr_runtime_next/reviews/wuwa-depth19-gpu-prep
make all \
  BRIDGE_LIB=/absolute/path/to/fixed/libnr_format_bridge.a \
  PLAN_CPP=/absolute/path/to/fixed/format_plan.cpp \
  BRIDGE_CPP=/absolute/path/to/matching/bridge.cpp
make check PLAN_CPP=/absolute/path/to/fixed/format_plan.cpp
```

`BRIDGE_LIB` override is **read/link-only**; no recursive make or write occurs in
that directory. `PLAN_CPP` chooses the native CPU validator source. `BRIDGE_CPP`
records matching source provenance (and selects source if building the local
archive). Relinking/CPU compilation are forced, preventing stale override reuse.
All default build outputs remain here. No automatic run/deploy/clean target exists.
The APIs/headers are expected unchanged by the depth-pair validator fix.

Only after separate GPU authorization, Main may copy the rebuilt
`build/wuwa_depth19_probe.exe` and `build/inputs.sha256` to an **owned isolated test
staging directory**, not a game directory. Use the already-authorized Windows or
GPU/Wine fixture environment; this worker did not create/change any environment.
The inherited adapter requirement is NVIDIA RTX5090 `10de:2b85` (not WARP).
Run there with `wuwa_depth19_probe.exe --run-owned-gpu`, capture stdout/stderr and
exit code. Without that explicit flag it refuses execution. Do not run concurrently
with a game. No bridge DLL/NR DLL is needed: FormatBridge is statically linked.

Require all three DATA_PASS lines, final SUITE_DATA_PASS, exit0, correct manifest,
and the debug/GBV caveat review. A successful future run proves **synthetic owned
FormatBridge normalization only**, not NR quality, real SR execution, PRE host seam
integration, actual 4100x2308 game geometry, or game stability.
