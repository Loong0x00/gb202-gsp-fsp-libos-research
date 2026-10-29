# Format evidence and numeric interpretation

Sources were read only; this component changed none of them.

## DXGI numbers

The local MinGW `dxgiformat.h` defines:

| number | enum |
|---:|---|
| 10 | `DXGI_FORMAT_R16G16B16A16_FLOAT` |
| 19 | `DXGI_FORMAT_R32G8X24_TYPELESS` |
| 21 | `DXGI_FORMAT_R32_FLOAT_X8X24_TYPELESS` |
| 26 | `DXGI_FORMAT_R11G11B10_FLOAT` |
| 33 | `DXGI_FORMAT_R16G16_TYPELESS` |
| 34 | `DXGI_FORMAT_R16G16_FLOAT` |
| 37 | `DXGI_FORMAT_R16G16_SNORM` |
| 39 | `DXGI_FORMAT_R32_TYPELESS` |
| 41 | `DXGI_FORMAT_R32_FLOAT` |

In particular, **33 is not `R16G16_SNORM`**. It is the typeless base resource;
SNORM is typed view 37. Likewise HSR depth base 19 requires a depth-plane SRV
view such as 21 for float shader reads.

`bridge.cpp` repeats all of these as compile-time assertions against the Windows
headers.

## WuWa

`adapters/evidence/INVENTORY.md` records the audited frame as Output/MV/depth
26/34/41. The read-only capture
`benchmark_logs/wuwa-native-replay-75-pre-event-20260903-121233/dlss-ngx-frames.jsonl:1`
also records:

- padded Color `4100x2308`, format 10, for render `4099x2306`;
- Output `6144x3456`, format 26;
- MV at render extent, format 34;
- depth at render extent, format 41;
- jitter, MV scales, pre-exposure, feature flags, and resource pointers from one
  Evaluate.

The bridge consequently accepts WuWa post 26/34/41 and the observed pre-SR Color
10 contract. It does not reinterpret the noisy RR Color as post input.

## HSR

The installed read-only log
`.../StarRail_Data/Plugins/x86_64/hsr-dlss5-router.jsonl:11-15` records Output,
MV, and depth shared-resource base formats 26, 33, and 19. The audited source
`/home/user/rt_5090_project/hsr_dlss5_lab/hsr_nvunity_iat_router.cpp`:

- obtains D3D11 NGX Output/MotionVectors/Depth through parameter slot 8 with
  fallbacks (`get_d3d11`, around lines 124-149);
- copies those D3D11 resources into same-format shared resources;
- opens the resources on D3D12; and
- logs the D3D12 base `GetDesc().Format`.

That source does **not** capture the game's original D3D11 SRV descriptors and
its old transport creates no D3D12 SRVs. Therefore the base formats 33/19 are
observed, while view formats 37/21 are the explicit typed shader contract this
bridge requires; they are legal DXGI family views, but still need Main/live
capture attestation before HSR compatibility is claimed. Passing view 33 or 19
is rejected rather than silently guessing.

The old transport uses shared resources with simultaneous-access flags and a
shared D3D11/D3D12 fence, but it also performs render-thread waits. This bridge
reuses none of that waiting behavior. Its `hsr_shared_copy_attested` means a
future owner supplied a coherent current-frame copy and GPU-side wait; the flag
must not be set from old logs alone.

## Numeric preservation and quantization

- WuWa `R16G16_FLOAT -> R16G16B16A16_FLOAT` preserves the numeric `xy` values
  through matching binary16 typed load/store (NaN payload byte identity is not
  claimed).
- HSR `R16G16_TYPELESS` with an `R16G16_SNORM` SRV first applies DXGI SNORM
  decoding to `[-1,1]`, then the UAV rounds `xy` once to binary16. MV scale and
  jitter metadata are copied unchanged; changing the scale would incorrectly
  apply normalization twice.
- The exhaustive CPU reference over all 65,536 signed 16-bit codes measured
  `SNORM16 -> float16` maximum absolute error **0.000244140625** and RMS error
  **0.0001065016992**. This is numeric preservation within float16
  quantization, not byte-exact conversion.
- Finite R11 values are decoded numerically to float16 for owned work; POST NR
  results are converted once through a typed R11 UAV store. NaN payloads,
  infinities, negative post-NR values, and final R11 rounding are device-format
  behavior and require the planned GPU harness. No byte-exact R11 round-trip is
  claimed.
- Depth is copied numerically through a float view into an owned typeless R32
  allocation. Stencil is intentionally excluded by view 21. NaN payload byte
  preservation is not claimed.

No GPU execution or game validation was performed for this contribution.
