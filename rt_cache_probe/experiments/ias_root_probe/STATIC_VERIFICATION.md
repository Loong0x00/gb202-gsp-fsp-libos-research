# Static verification report

Date: 2026-07-11 (Asia/Singapore)

No probe executable was run and no GPU workload was launched during this
implementation pass. Verification was limited to source review, OptiX header
cross-checking, OptiX-IR compilation, host compilation, linking, and static
analysis.

## Requirement matrix

| Requirement | Static evidence |
|---|---|
| Standalone implementation | All files live under `experiments/ias_root_probe`; no source in `agent_optix/minimal` was edited. |
| G | `gas_handles[i]` is placed directly in the unique root ring. |
| IS | `is_handles[i]` is built as an independent one-instance IAS whose child is always `gas_handles[0]`. |
| IU | `iu_handles[i]` is built as an independent one-instance IAS whose child is `gas_handles[i]`. |
| Forced outside-root | Ray origin is `(0,0,0)` and direction is `-Z`; all identity-transformed geometry is at `z=1`. |
| Guaranteed hit | Direction is `+Z` through the interior of the single triangle at `z=1`. |
| Same-handle control | The same K-entry/next-index table is retained while every handle is replaced by root handle 0. |
| Sattolo | Deterministic Sattolo generation plus host validation that the mapping visits every entry once and returns to zero after K steps. |
| Dependent timing | One raygen thread, dependent `next` walk, synchronous `optixTrace`, and `clock64` around each sample. |
| Payload validation | Miss writes 0, closest-hit writes 1, and the host rejects every sample not equal to `0` or `K*rounds` as appropriate. |
| Correct graph contract | Pipeline flags combine `ALLOW_SINGLE_GAS` and `ALLOW_SINGLE_LEVEL_INSTANCING`; link and stack graph depths are 2; trace depth is 1. |
| Output | Raw samples, median/min/max summaries, scenario/handle-set/mode labels, root handles, child mappings, AS sizes, topology, device properties, and safety values are emitted as CSV or JSON. |
| Safety | K/round/sample/warmup limits, 2,000,000 trace-call cap, 10 s watchdog, 64 MiB and 1%-free-VRAM accounting caps, one launch thread, and no GPU reset on timeout. |

## Build result

The following completed successfully with CUDA 13.3 and NVIDIA OptiX headers
9.1.0:

```text
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --clean-first -j2

[ 33%] Compiling IAS/GAS root probe device programs to OptiX IR
[ 66%] Building CXX object CMakeFiles/optix_ias_root_probe.dir/ias_root_probe.cpp.o
[100%] Linking CXX executable optix_ias_root_probe
[100%] Built target optix_ias_root_probe
```

`clang-tidy` with `clang-analyzer-*` and `bugprone-*` found no analyzer defect in
project code. Its remaining diagnostics are API/header style warnings and the
usual aggregate-zero-initialization warning for OptiX structs whose enum fields
are assigned immediately afterward.

## Runtime gate

Compilation proves API/type consistency, not that the driver accepts every
graph at launch or that hit/miss payload validation passes on the target GPU.
The first future runtime should therefore use the smallest gated case, for
example K=1, one sample, one round, and one scenario, before any K sweep.

