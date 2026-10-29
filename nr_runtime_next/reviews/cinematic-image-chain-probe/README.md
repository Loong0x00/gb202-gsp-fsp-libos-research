# Cinematic image-chain probe — CPU-built baseline, Main-only GPU execution

**Delivered first-stage alternative:** working/cross-compiled harness for the **unchanged frozen cinematic D5R DLL**. No instrumented DLL or per-layer images yet. `INSTRUMENTATION_PLAN.md` describes the next isolated clone. No Wine, GPU, probe EXE, or game was run by this worker.

## Main: staging and exact flags

Use a **new owned lab staging directory**, not a game/Main directory. Keep it current working directory during both invocations. Stage:

- `build/image_chain_probe.exe` from this review.
- **Only** `dlss5-native-runtime.dll` from `../quality-post5-cinematic-20260910-173726/package/bin/`; SHA256 **`5b4f8afd1b545cad6d4f3ccbfd089c02b2cf0ff79d7bbfdb9277e74d98e508ba`** is enforced by the EXE.
- Exact approved genuine `_nvngx.dll` and `nvngx_dlssnr.dll` plus their existing approved lab dependencies. Main must retain/revalidate existing signed-binary provenance/signature preflight and staging hashes; the harness logs dependency SHA256, not Authenticode validation. It preloads **Core only**; D5R performs its existing signed NR bootstrap itself. It checks actual loaded Core/runtime/NR paths. No new signature/identity/bootstrap patch, alternate init, or admission fallback is added by the harness.
- The existing validated **vkd3d-proton/Wine Vulkan interop** environment from the owned memory fixture, including its proper D3D12/DXGI loader and `winevulkan.dll` support. Requires actual NVIDIA **10de:2b85** (5090), never WARP. Native Windows D3D12 without the custom Vulkan interop IID is not supported by this frozen runtime.
- **Do not stage the frozen package's `dxgi.dll` proxy or `dlss5-native-host.dll`.** This direct D5R ABI fixture does not use host/game interception. Do not preload NR Init or call any other legacy NR runtime.
- `input.rgba16f`: exactly `width * height * 8` bytes, row-major tightly packed **little-endian binary16 RGBA, linear HDR**, no header/row padding, finite components. No implicit resizing, normalization, transfer-function conversion, or alpha repair. Main prepares the actual image; no fabricated input was staged here.

The following are **instructions for Main, not commands executed by this worker**. `$LAB_WINE64` means Main's existing validated lab Wine entrypoint/environment, not a new guessed Wine installation. Retain its GPU ownership/authorization/preflight setup and run sequentially. Use a fresh output directory name each time; the EXE refuses existing output directories/files.

```bash
# In the isolated staging directory, with Main's approved GPU/Wine environment:
export D5_CINEMATIC_IMAGE_FIXTURE_AUTHORIZED=1
"$LAB_WINE64" ./image_chain_probe.exe --layers 1 --frames 4 \
  --width 768 --height 768 --input input.rgba16f --output-dir post1 >post1.log 2>&1
# Require exit 0 AND post1/SUCCESS.txt before continuing.
"$LAB_WINE64" ./image_chain_probe.exe --layers 5 --frames 4 \
  --width 768 --height 768 --input input.rgba16f --output-dir post5 >post5.log 2>&1
# Require exit 0 AND post5/SUCCESS.txt.
```

These are **two processes**, each with fresh feature handles/history; never change layer count within a process. Defaults: work 768x768, guides=work, 4 evaluated frames (plus one create submission). `--frames 1..8` accepted. Internal **120-second lab watchdog per process** includes all work and disk I/O; not the game's time-limit. No implicit retry. An outer Main supervisor should allow the internal 120s deadline and collect failures rather than retry or weaken gates.

Second, separate **Quality-shaped condition** (not real signed SR execution): same commands/input/work size, new result directories, add `--guide-width 512 --guide-height 512` to **both** layer cases. Arbitrary positive paired guide dimensions <= work are accepted; no guessed size conversion. This intentionally reinstates frozen Create/Evaluate shape mismatch, so do not mix its comparison with guides=work baseline. Work extent <=4096 each and input <=128MiB.

Optional real guide files: add `--motion motion.rgba16f --depth depth.r32f` to both cases. Motion is tightly packed little-endian RGBA16F at **guide extent**, normalized FLOAT34 convention expected by the base fixture, scale=(1,1); depth is little-endian R32 float at guide extent, non-inverted convention. No guide resampling/space conversion. Caller must supply correctly aligned same-frame guides for this static image; jitter is (0,0), source flags=1, no pre-exposure-valid flag. File hashes go in `case.json`. If omitted: **SYNTHETIC ZERO motion in all four components; SYNTHETIC CONSTANT depth=0.375**. Such guides are not game-quality/history validity evidence.

## Fixed exact controls / ABI

Frozen cinematic ABI headers copied byte-for-byte into `abi/`. Only dynamically resolved D5R Initialize/Execute/Query/Submitted/Reset/Retire exports are called. No runtime implementation or NGX SDK is linked into the harness.

POST, layers 1 or 5, upscaling=0, preset=0, **style=2**, **intensity/local-tone/local-structure/skin-structure=2**, **auto-mask=1**, UI correction=0, depth mode=0, motion scales=1, paper white=1, **HDR transfer strength=.6**, color strength=1, fixed reset generation=1. Exact enabled 76-byte ABI snapshot saved as `control.bin`; no live-control/host config file required. Here “HDR .6” means the frozen codec's `transfer_strength`, not `paper_white_scale`.

Uses existing numeric fixture bootstrap ID `0x0876232c`; frame game=UNKNOWN, POST SR-shaped reconstruction only. No fabricated signed-SR handle, adapter gate call, or GATE_OPEN bit. No game gate bypass: this is the expressly owned raw-runtime fixture route, not admission into a game/host pipeline. The runtime's existing DXGI Budget/CurrentUsage/estimate/allocation checks remain intact (including the already-frozen zero-extra-reserve cinematic policy). Failures stop the case; no fallback.

## Capture and submission contract

For every evaluated frame, on the **same owned native command list**:

1. Restore color from immutable original-image GPU reference (`COPY_SOURCE`), return color to UAV.
2. Copy current color into dedicated **before** D3D12 READBACK with UAV→COPY_SOURCE→UAV.
3. Call real frozen **D5R Execute**, which runs all requested layers, codec composition and native output commit itself.
4. Only on successful whole-pipeline status, copy current color into distinct **after** READBACK; restore UAV.
5. Close list, actual `ExecuteCommandLists`, same-queue `Signal`, then D5R **Submitted** with exact tracked list/device/cookie/kind/queue/fence/value.
6. Require exact fence completion (`UINT64_MAX` is failure), then Map and strip D3D12 footprint padding. Assert **every before-image is byte-identical to input**. Save both images with SHA256/nonfinite/zero/changed-component/changed-pixel counts in stdout. Only after CPU copy-out may buffers/list/allocator be reused.

One create submission is also tracked, acknowledged and actually fenced before evaluation. Evaluation frames are contiguous 2..N+1; first-use reset is left to runtime, not forced every frame. Per-layer unique handle/create/evaluate counts, whole-runtime counts, budget receipt and runtime background last-completed-frame evidence are checked. On failed Execute the tracked recording is Reset/discarded, never submitted. Signal/ack/fence failures terminate; no potentially in-flight resources are intentionally recycled.

After the last exact fence and completion query, Retire is requested. Frozen `active_chains` excludes retiring chains and **does not prove async resource destruction**; we do not mislabel it. Runtime DLL is not unloaded; runtime-held references/background cleanup have process lifetime.

**Boundary caveat:** `before-execute` is original HDR immediately **before Execute**, not decoded HDR immediately before the internal native commit. `after-commit` is current owned output after D5R's native commit. Baseline cannot compare internal decoded-before-copy against output-after-copy, nor distinguish raw L1/L5 within POST5. It never tests FormatBridge/game copyback/Present.

## Outputs / CPU comparison

Each case creates `case.json`, `control.bin`, `frame-01-before-execute.rgba16f`, `frame-01-after-commit.rgba16f`, ...; `output.rgba16f` is byte-identical to the last after-commit image. `SUCCESS.txt` is written only after all checks/retirement request succeed. Nonfinite output counts are diagnostic, not silently converted or treated as visual acceptance. Partial files without SUCCESS are invalid completed-case evidence.

Run CPU analysis after Main collects both cases (Python + NumPy):

```bash
python3 /home/user/rt_5090_project/nr_runtime_next/reviews/cinematic-image-chain-probe/analyze.py \
  --input input.rgba16f --case1 post1 --case5 post5 \
  --width 768 --height 768 --frames 4 >comparison.json
```

Checks success/control snapshots, identical input restoration, matched guides/runtime/shape metadata and final image identity. Reports per-frame SHA256, counts, RGBA min/max/mean, input/output and previous/current changes, plus POST1-vs-POST5 exact equality, RGB and alpha MAE/RMSE/max/p95/p99. RGB/alpha separated. This compares **separate-chain final HDR images**, not same-chain raw neural layers.

## CPU build / verification only

```bash
make -C /home/user/rt_5090_project/nr_runtime_next/reviews/cinematic-image-chain-probe all
cd /home/user/rt_5090_project/nr_runtime_next/reviews/cinematic-image-chain-probe
python3 cpu_checks.py
```

Cross-compilation uses MinGW with warnings-as-errors; PE only inspected, not executed. `BUILD_CPU.log`, `CPU_CHECKS.log`, `frozen-inputs.json` retain build/model/ABI/hash evidence. CPU analyzer tests use temporary synthetic arrays marked CPU-only, not the user's GPU image. No run target exists. CPU models cannot verify actual signed image writes, runtime bootstrap success, synchronization validation or image quality; Main's GPU run remains required.
