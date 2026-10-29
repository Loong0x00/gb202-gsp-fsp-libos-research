# D3D12 format bridge for WuWa and HSR

This directory is a standalone C++ static-library component intended to be
linked into NativeRuntime/Host later. It records real D3D12 compute conversion
work; it is not another adapter/plugin framework and does not load, inject,
deploy, sign, configure, or call NGX.

## Main hardware results

See [GPU_RESULTS_20260910.md](GPU_RESULTS_20260910.md): seven actual RTX 5090
conversion data tests pass after explicit half rounding of MV. Vulkan core and
synchronization validation are clean in the isolated offscreen test. D3D12 debug
layer remains unavailable; the harness retains overall exit 1 / `pass:false`
for that limitation. No real-game seam/HSR interop or Feature18 is attested.

## Implemented GPU path

`FormatBridge::normalize()` validates the current resources and records these
format-aware shader operations on the caller's **direct** command list:

| input | owned origin-zero output |
|---|---|
| signed post Output `R11G11B10_FLOAT`, or attested pre Color | `R16G16B16A16_FLOAT` Color |
| WuWa `R16G16_FLOAT`, HSR `R16G16_TYPELESS` viewed as `R16G16_SNORM` | `R16G16B16A16_FLOAT` MV (`xy`, `z=w=0`) |
| WuWa `R32_FLOAT`, HSR `R32G8X24_TYPELESS` viewed as `R32_FLOAT_X8X24_TYPELESS` | `R32_TYPELESS` resource with `R32_FLOAT` UAV/SRV interpretation |

Only active subrects are converted; normalized bases are all zero. The returned
`D5nRawFrameV1` keeps frame/game/reconstruction identity, reset, feature flags,
HDR/depth flags, jitter, MV scales, pre-exposure, and extents from the caller's
current frame. The bridge changes only the command/resource pointers, states,
and bases needed by the strict native ingress.

For POST, the current game/shared output is sampled into an owned HDR texture and
then restored to its exact declared state. NativeRuntime therefore reads and
writes only the owned `R16G16B16A16_FLOAT` texture. The game target is not changed
by prepare, `CREATE_PENDING`, bypass, or NR failure. After and only after an exact
`D5N_FRAME_EVALUATED_V1` result with the expected number of NR calls,
`commit()` records one typed-UAV `R16G16B16A16_FLOAT -> R11G11B10_FLOAT`
conversion to that frame's current output and restores its original state.
Double commit, wrong frame/result ABI, partial call count, and non-EVALUATED
statuses are rejected.

For PRE, RR is rejected: noisy RR Color is never sent to NR. Ordinary SR gets an
owned float input. A source already in `R16G16B16A16_FLOAT` keeps the game's
observed WuWa SR format. A source in R11 is accepted only with
`explicit_rgba16_float_srv`, meaning the caller has separately captured and
validated that exact ordinary-SR shader/NGX seam with a float16 replacement.
HSR currently has no such captured pre-Color contract, so this attestation must
remain unset in production. On successful native evaluation, `commit()` returns
the native-owned float16 `replacement_color` for the same original SR Evaluate;
it never replaces Color on failure.

No `CopyTextureRegion`/`CopyResource` is used for unlike formats. The HLSL has
four separately compiled typed declarations, including `RWTexture2D<float3>` for
R11. Their D3DCompiler 47 DXBC is prebuilt in `shaders/normalize_dxbc.inc`, so
production creation performs no source/file compilation. The test recompiles,
reflects, and byte-compares all variants. Device creation checks `SHADER_LOAD`,
typed-UAV-view, and `UAV_TYPED_STORE` support before recording.

## Lifetime, budget, and state contract

- Every in-flight slot owns its Color/MV/depth textures and its own immutable
  eight-descriptor shader-visible heap. A descriptor is rewritten only after the
  prior caller fence completes.
- `GetResourceAllocationInfo()` for each committed texture is charged against
  `BridgeConfig::max_owned_bytes`; arithmetic overflow, slot exhaustion, and
  allocation failure are fail-closed. `estimate_owned_pixel_bytes()` is only a
  CPU planning floor; the device allocation values enforce the real cap. Main
  must also include `resident_owned_bytes()`/the intended in-flight slot count in
  its guarded total VRAM preflight rather than treating this as free memory.
- Current game/shared resources and the exact command list are AddRef'd only
  until `submitted(token, queue, fence, value)` is retired. `retire_completed()`
  only polls `GetCompletedValue()`; it never waits. `abandon_unsubmitted()` is
  legal only after the caller proves the list was discarded/reset without
  submission. `trim()` releases completed pooled textures.
- Mips, arrays, MSAA, non-2D/non-unknown-layout textures, invalid/overflowing
  subrects, unsupported formats/views, invalid state combinations, wrong-device
  objects, and conflicting source aliases are rejected. POST Color/Output alias
  is the one intentional exception and must have the same identity and state.
- Every external source and commit target transitions from its exact declared
  state to shader use and back. Owned normalized final states are the native
  contract's `UNORDERED_ACCESS` Color/Output for POST and
  `NON_PIXEL_SHADER_RESOURCE` Color/MV/depth for PRE (guides are NPSR in both).
- D3D12 cannot query or restore the caller's compute root signature, PSO, or
  descriptor heaps. Integration must place this at a seam that rebinds its own
  compute state afterward. Resource states are restored; command-list bindings
  are intentionally clobbered.
- No CPU readback, render-thread wait, file/network I/O, queue submission, or
  fence signal occurs in the library.

Destroy the bridge only when `in_flight_frames()==0`. Because waiting is
forbidden, accidental destruction with unretired GPU work deliberately leaks the
process-lifetime implementation rather than releasing objects still referenced
by the GPU. Correct integration always retires or explicitly abandons every
token.

## Native integration order (not yet wired)

The current `native/runtime/pipeline.cpp::valid_frame()` rejects the game formats
before conversion. Main must insert this wrapper **before** calling
`DLSS5_NativeRuntimeExecuteV1`; do not pass the unnormalized resources through
that validator.

1. Build the current raw frame from the same Evaluate and pass its current
   resource pointers/states/views to `normalize()`. For POST, Color and
   `game_output` are the current rotating signed Output, not a retained pointer.
2. On success, copy `NormalizedFrame::frame` into `D5rExecuteV1::frame` and call
   NativeRuntime. Its strict format/state checks now see only owned
   `RGBA16_FLOAT`, `RGBA16_FLOAT`, and `R32_TYPELESS` resources at origin zero.
3. Call `commit(token, list, result)` only when the native call itself succeeded
   and result status is `EVALUATED`. For POST this records the sole game-output
   conversion. For PRE, replace Color for the original ordinary-SR Evaluate only
   with `CommitOutput::pre_sr_color`; otherwise use the untouched original Color.
4. Preserve the game's exact original SR/RR result and parameter restoration.
   Set any host `output_committed` acknowledgement only from successful POST
   `CommitOutput::output_committed`, never merely from native status.
5. Execute the command list, queue the externally owned fence signal after it,
   and call `submitted()`. Poll `retire_completed()` off the critical path.
6. If a recorded list is reset/discarded and cannot execute, call
   `abandon_unsubmitted()` only after that fact is certain. If it executes—even
   after an NR error—it still requires fence retirement.

HSR additionally requires the existing late/Guardian gates and a coherent
D3D11-to-shared-D3D12 copy plus GPU wait before step 1. After POST commit and the
D3D12 fence, the transport may GPU-wait on D3D11 and copy the R11 shared target
back to the **current frame's** D3D11 Output. This library does not implement or
attest that D3D11 seam, does not retain a game Output after its frame fence, and
does not make HSR pre-SR ready.

See [`INTEGRATION.md`](INTEGRATION.md) for a concrete call-order sketch and
[`FORMAT_EVIDENCE.md`](FORMAT_EVIDENCE.md) for the audited DXGI number/view split
and measured SNORM quantization.

This is integration source, not a new host ABI or a compatibility claim. No
capability should set `format_conversion_ready` until Main completes real device,
fence, finite-value, R11 round-trip, state-debug-layer, and live-game tests.

## Build and non-GPU tests

```bash
make -C adapters/format_bridge test
```

Outputs:

- `build/libnr_format_bridge.a` — MinGW x64 static library;
- `build/test_format_plan` — host CPU plan/layout/format/state/budget/commit tests;
- `build/shader_compile.exe` — software `D3DCompile`/reflection/committed-DXBC
  comparison for all four `cs_5_1` variants (it creates no D3D device or GPU
  work).

A consumer of the static library links `d3d12` and the normal DXGI/COM UUID
libraries; production does not depend on `d3dcompiler_47`. `make test`
cross-compiles and link-checks the full bridge, runs source checks, runs only the
compiler executable under Wine, and runs CPU tests. `make regen-shaders` is the
explicit local-tool regeneration path. Neither command launches a game or GPU
conversion harness.
