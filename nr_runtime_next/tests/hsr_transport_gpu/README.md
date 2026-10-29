# Main-owned real GPU transport / NVX fixture

This is **not HSR game or native NR acceptance**. It links the production D3D11 transport and (latest run) NVX observer objects, and loads the production format helper. NR output is simulated; the executable asserts that neither `_nvngx.dll` nor `nvngx_dlssnr.dll` is loaded. No screenshots, game input, account-prefix writes, or game launch.

## Recorded runs

- `runs/20260910-134447`: original synthetic SNORM37 fixture; three transport cases passed. Historical conversion fixture only, **not the actual signed HSR motion contract**.
- `runs/20260910-135832`: corrected FLOAT34 fixture, real GPU guide readback and three transport cases passed.
- `runs/20260910-141329`: additionally executed actual DXVK ExtDevice1 slot6 through the production NVX observer. Two successful calls returned exact same-resource motion33/view34 and depth19/view21; handles6470/6471. Diagnostic only, routing_used=0. All guide/transport cases passed.

Latest data checks:
- Motion typeless33 bytes encode FLOAT16 (.5, -.25), not SNORM; normalized RGBA16F readback is bit-exact `(0x3800,0xb400,0,0)` for all 192 guide pixels.
- Depth typeless19 has FLOAT32 .375 and stencil9; view21 normalization yields .375 without stencil contamination for all 192 pixels.
- Case0: white copyback to target A, actual D3D11 retirement2.
- Case1: rotate to B, prepare-only simulated black producer, no game copyback; B remains white, retirement4.
- Case2: black copyback to current B, previous A remains white, retirement6.
- Signal enqueue alone is insufficient: test flushes/polls actual retirement and reads GPU output. Test-only CPU readback waits are not production render-thread waits.

All runs used NVIDIA10de:2b85, a separate Wine prefix with copied graphics DLLs, exclusive benchmark.lock, bounded process duration, and the unchanged Astral hardware guardian (latest guardian_exit0). RESULT.json, input hashes, stdout, Wine and guardian logs are retained per run. No D3D12 debug-layer or full validation acceptance is claimed.

## Build / run

After rebuilding `adapters/hsr_native`, cross-compile probe.cpp with `build/d3d11_transport.o` and `build/d3d11_nvx_srv_observer.o`, static MinGW C++20, `-ld3d11 -ldxgi -ldxguid`, into this directory's `build/hsr_transport_probe.exe`. Copy the exact `dlss5-hsr-format-bridge.dll` into build, then run `python3 run.py`. Main only; never run concurrently with games or other GPU tests.

## Evidence limits

Exact signed SR static mapping is documented in `../../reviews/hsr-nvapi-path/REPORT.md`: 33 maps to FLOAT34, not37. Runtime NVX use is proven here only for an explicit synthetic fixture. Current game evaluation/cached-view usage still requires its own evidence. The adapter now requires observed FLOAT34/21; the generic format library retains historical synthetic SNORM conversion support without allowing the HSR adapter's old37 contract. Frozen ABI sizes and production signed binaries were not changed.
