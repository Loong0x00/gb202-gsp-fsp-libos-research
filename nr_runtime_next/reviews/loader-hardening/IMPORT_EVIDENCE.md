# Exact local import evidence (read-only)

Observed 2026-09-10. No game was launched or attached. The configured paths came
from `/home/user/.config/dlss5-linux/profiles.json` (also recorded in
`adapters/evidence/INVENTORY.md`); only PE metadata and bounded matching import
records were printed.

## Cyberpunk 2077

- Path: `/home/user/.local/share/Steam/steamapps/common/Cyberpunk 2077/bin/x64/Cyberpunk2077.exe`
- Size: 59,945,608 bytes
- SHA-256: `a7de82945c03e041fc7339fcf9066224d98db2f5d80fea50f7947bb350a60991`
- `SizeOfImage`: `0x4efc000`
- Import directory: RVA `0x32dec34`, size `0x2e4`
- Regular import: `sl.interposer.dll!D3D12CreateDevice`
- Descriptor `OriginalFirstThunk=0x32e0450`, `FirstThunk=0x2a8e538`
- Function index 7, IAT RVA `0x2a8e570`, name RVA `0x32e298a`

This proves the current CP main-EXE target used by the candidate. Its wrapper
chains the per-slot observed predecessor, which is intentionally not assumed to
be the system D3D12 export.

## Wuthering Waves

The requested name `WuwaClient-Win64-Shipping.exe` does not exist at the
configured game path. The actual profile and inventory name is:

- Path: `/home/user/.local/share/Steam/steamapps/common/Wuthering Waves/Client/Binaries/Win64/Client-Win64-Shipping.exe`
- Size: 975,548,424 bytes
- SHA-256: `a6cdb83f6f2909b5a13ca19b1d5ff4f0455f743e8fabf40bb07546500968cdfa`
- `SizeOfImage`: `0x3d627000`
- One regular import descriptor and 29 delay-import descriptors
- **No regular or delay import named `D3D12CreateDevice`**
- Its delayed `d3d12.dll` imports contain only four helpers including
  `D3D12SerializeRootSignature` and `D3D12SerializeVersionedRootSignature`.

The adjacent `Client-Win64-ShippingBase.dll` (SHA-256
`9ceb2e6f4a2e8d579003374cef95071b3b1de0a64968166a0b457c5af0cfb63c`)
has one regular `kernel32.dll` descriptor including `LoadLibraryA`, no delay
imports, and no `D3D12CreateDevice` import or literal. The main EXE does contain
`D3D12CreateDevice` literals, consistent with a possible dynamic lookup, but a
literal does not prove an IAT slot or its owning call path.

Therefore this review does **not** invent a WuWa factory/device-IAT target and
does not apply the CP target policy as WuWa coverage. The follow-up instead
observes only factories returned successfully by the three exports of the owned
DXGI proxy, then hooks the known base/Factory2 `CreateSwapChain*` routes to test
`pDevice` for a real D3D12 queue. This avoids protected-executable and dynamic
`GetProcAddress` guessing, but does not prove that WuWa's actual caller uses the
owned proxy or reaches a tracked method in time. Scope remains: **queue-at-
swapchain route implemented but UNVALIDATED** pending main cold tests. There is
no arbitrary-module fallback in this patch.

## Actual NGX core used by retained CP runs

Retained CP process maps identify:

- Path: `/home/user/.local/share/Steam/steamapps/compatdata/1091500/pfx/drive_c/windows/system32/_nvngx.dll`
- Size: 1,992,304 bytes
- SHA-256: `bdad96fdca36050a94a221bb89eab4fc5db6e53ef799494a68957a2e2b28e283`
- Regular import: `KERNEL32.dll!GetProcAddress`
- Descriptor `OriginalFirstThunk=0x1577f8`, `FirstThunk=0x114108`
- Function index 71, IAT RVA `0x114340`, name RVA `0x157ffc`

The candidate targets only this exact core basename and import pair. A normal
`GetModuleHandleExW` reference is retained after successful installation to keep
that patched generation live; no process-wide module set is pinned.

## Method

`pefile.PE(..., fast_load=True)` parsed only import and delay-import directories;
`sha256sum` recorded exact inputs. Separate CPU tests exercise the candidate's
own loaded-image parser with valid, out-of-bounds, unterminated-name, missing
`OriginalFirstThunk`, and bad-thunk cases. No large import/file dump is retained.
