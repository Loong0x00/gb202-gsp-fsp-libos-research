# MAIN-only D3D12 format-bridge GPU harness

This directory is a standalone validation harness for a later, explicit MAIN
run. It was prepared and cross-compiled only; its presence is **not observed GPU
output** and is not a game, format-seam, feature, or compatibility claim.

The executable creates no window or swap chain. It owns an offscreen D3D12
direct queue, allocator, command list, fence, descriptor heaps, and 32x24
active extents (padded subrect fixtures are 64x48). It does not load NGX, a
game, host capability/UI code, or production
configuration. The `D5nRawFrameResultV1` values used to open the bridge commit
gate are always emitted in JSON as `"nr_result":"SIMULATED"`.

## What a MAIN invocation checks

Startup fails unless DXGI enumerates the exact discrete adapter
`vendor=0x10de, device=0x2b85` (RTX 5090). Tests execute serially on one owned
direct queue:

- compile-time ABI checks for `D5nRawFrameV1 == 200` and
  `D5nRawFrameResultV1 == 216`;
- compile-time SDK checks for formats 10/19/21/26/33/34/37/39/41;
- WuWa POST resources `R11G11B10_FLOAT` / `R16G16_FLOAT` / `R32_FLOAT`;
- HSR POST resources `R11G11B10_FLOAT`, `R16G16_TYPELESS` viewed as
  `R16G16_SNORM`, and `R32G8X24_TYPELESS` viewed as
  `R32_FLOAT_X8X24_TYPELESS`;
- actual `FormatBridge::normalize()` shader dispatches and POST
  `FormatBridge::commit()` dispatches;
- a finite, unsigned HDR R11 grid (including input 60000, explicitly quantized
  to the packed finite R/G value 59904); negative R11 fixtures are rejected by
  the fixture builder;
- one unchanged simulated result per profile, requiring packed
  R11 -> half -> R11 identity; one simulated modified result using a UAV clear
  of the bridge-owned normalized color before commit;
- two rotating game outputs, double-commit rejection, and a simulated
  `CREATE_PENDING` case that clears only the owned texture and requires the
  current and peer game outputs to remain unchanged;
- WuWa padded Color/MV/depth active-subrect conversion to owned origin-zero
  resources (the Color subrect uses the bridge's test-only explicit PRE
  contract), plus WuWa POST padded MV/depth subrects;
- HSR SNORM endpoint codes -32768 and -32767, finite output, zero `zw`, and a
  maximum `SNORM16 -> half` error bound of 0.000244140625. No source-byte
  identity is claimed for this conversion;
- HSR depth initialized only through `ClearDepthStencilView(0.375, stencil=9)`;
  normalized R32 readback must contain only depth 0.375, never stencil;
- exact preservation of flags, reset, jitter, MV scales, pre-exposure, extents,
  identity metadata, and canonical zero normalized origins;
- one queue signal and a bounded wait of at most 5000 ms before every readback
  map, followed by `submitted()`, `retire_completed()`, and a required
  `in_flight_frames()==0` before normal destruction.

On a timeout or indeterminate fence wait the process emits a fatal JSON line and
calls `ExitProcess(124)` without running C++ destructors. This deliberately
leaves every potentially GPU-referenced object at process lifetime instead of
releasing it unsafely.

Output is JSON Lines: one object per case followed by a summary. It includes
readback hashes, finite checks, bit-exact fields, numeric error bounds, commit
status, and D3D12 debug-message counts. Shader/pipeline creation, device removal,
submission, readback, or comparison failures return nonzero. If the D3D12 debug
layer/info queue is unavailable, the summary says `validation:"not_validated"`;
that condition is not reported as debug validation success and the harness
returns nonzero.

The HSR handoff flag and the WuWa explicit PRE color contract in this harness
refer only to coherent synthetic D3D12 resources owned by the test. They do not
attest the real D3D11 handoff or a live game seam.

## CPU and cross-build only

From the repository root:

```bash
# Builds the host CPU reference executable and the MinGW GPU executable.
# It runs neither Wine nor a GPU workload.
make -C tests/format_gpu all

# Runs only format-reference CPU checks (R11 packing and exhaustive SNORM16).
make -C tests/format_gpu check
```

Artifacts:

- `tests/format_gpu/build/format_gpu_harness.exe`
- `tests/format_gpu/build/test_format_reference`

The MinGW rule names `format_gpu_harness.cpp` explicitly, links the current
`adapters/format_bridge/build/libnr_format_bridge.a`, and supplies its Windows
D3D12/DXGI/compiler/COM/UUID libraries. Rebuild after any bridge header/library
API change; integration with Main should follow the final API rather than
copying assumptions from this harness.

## Later MAIN launch (do not run as a background/parallel test)

Use a prefix owned by this test and keep all output under this directory:

```bash
cd /home/user/rt_5090_project/nr_runtime_next
mkdir -p tests/format_gpu/build/main-wine-prefix
WINEPREFIX="$PWD/tests/format_gpu/build/main-wine-prefix" \
WINEDEBUG=-all \
wine "$PWD/tests/format_gpu/build/format_gpu_harness.exe" \
  >"$PWD/tests/format_gpu/build/main-results.jsonl" \
  2>"$PWD/tests/format_gpu/build/main-wine.stderr"
status=$?
printf '%s\n' "$status" >"$PWD/tests/format_gpu/build/main-exit-status.txt"
exit "$status"
```

Run exactly one harness process at a time. Do not use a global Wine prefix, do
not kill any global/personal wineserver, and do not place logs or artifacts on
the user desktop.
