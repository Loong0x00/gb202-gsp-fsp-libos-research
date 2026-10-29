# DLSSNR 310.8 model dump

This directory contains a reproducible extraction, an inspectable semantic
PyTorch reconstruction, and a working Linux/PyTorch frontend for the exact
embedded DLSSNR CUDA backend.

Consolidated SR/RR → NR → MFG findings, 4K/6K timing, SM/XBAR/SYS sweeps,
Wuthering Waves ghosting evidence, official NVIDIA benchmark context, and the
proposed lightweight NR→MFG adapter are recorded in
[`DLSSNR_MFG_ADAPTER_RESEARCH_20260902.md`](DLSSNR_MFG_ADAPTER_RESEARCH_20260902.md).
The companion
[`DLSS5_PUBLIC_FRAME_GENERATION_AUDIT_20260902.md`](DLSS5_PUBLIC_FRAME_GENERATION_AUDIT_20260902.md)
classifies public DLSS 5 tests by explicit FG/MFG on, off, or undisclosed status.
The RTX 50 SM/L2 proxy design and completed 33-point 1080p–4K standalone matrix
are recorded in
[`RTX50_DLSSNR_COMPUTE_L2_BANDWIDTH_PROXY_PLAN_20260903.md`](RTX50_DLSSNR_COMPUTE_L2_BANDWIDTH_PROXY_PLAN_20260903.md)
and
[`rtx50-native-l2-matrix-20260903-004556/README.md`](rtx50-native-l2-matrix-20260903-004556/README.md).
Memory bandwidth was deliberately left as an unmodeled error term.

## What is exact

- `WEIGHTS_HT.bin` is the exact `RCDATA/WEIGHTS_HT` resource from the signed
  runtime.
- `dlssnr-310.8-weights.safetensors` contains all 153 serialized tensors with
  byte-preserving payloads.
- `architecture.json` records all 71 blocks, 152 executable layers, graph edges, native
  layer types, and operator traces returned by the DLL's own graph factory.
- FP8 matrix boundaries, FP16 channel scales, Swin attention bias tables, and
  head scales used by the two transformer implementations in
  `dlssnr_pytorch.py` are size-checked when loaded.
- `cuda_feature_probe.exe` now creates real CUDA arrays through the patched
  Wine nvcuda bridge, calls `NVSDK_NGX_CUDA_EvaluateFeature`, synchronizes the
  stream and reads the RGBA32F result back. The packed weights and fused
  Swin/ViT/decoder CUBIN kernels are therefore NVIDIA's exact execution path.
- `dlssnr_native_pytorch.py` is the usable Linux frontend. PyTorch performs
  image decode/resize, parameter sweeps, bridge-equivalent SDR postprocessing,
  metrics and contact-sheet generation.

## What remains approximate

The native runtime executes fused CUBIN kernels. `dlssnr_pytorch.py` currently
implements the 512-channel split-Swin and 1024-channel 1-D ViT block families
with ordinary PyTorch operators. The DLL's custom approximate softmax is
represented by standard softmax, so this is a semantic/ablation model, not a
bit-identical replacement. The fused image encoder/decoder and RGB pre/post
blocks are still represented in `architecture.json` but do not yet have a
PyTorch forward implementation.

Do not use `dlssnr_pytorch.py` or `dlssnr_full_pytorch.py` for visual model
attribution: the raw weight payload uses CUBIN/Tensor-Core-specific packing.
Use `dlssnr_native_pytorch.py`; it keeps PyTorch as the frontend while the DLL
executes the exact packed model.

## Commands

Run the exact model on an image from Linux (the current machine's isolated
Wine/CUDA prefix is already prepared):

```sh
python dlssnr_native_pytorch.py input.png --sizes 512,384,256,192,128 \
  --out native-sweep
```

The useful controls are exposed directly:

```sh
python dlssnr_native_pytorch.py input.png --sizes 384 \
  --intensity 0.5 --tone 1 --structure 0 --skin -1 \
  --no-auto-mask --depths 0.1,0.5,0.9 --control-masks=-1,0,1 \
  --out parameter-sweep
```

`--crop x,y,width,height` selects a region before the sweep. Each run writes
the exact neural output (`*.rgba32f` and `*.neural.png`), the bridge-equivalent
final image (`*.png`), `metrics.csv`, and `contact-sheet.png`. The installed
bridge defaults are represented by intensity/tone/structure `1`, skin `-1`,
automatic mask off, transfer strength `1`, and color strength `0`.

The native executable can also be rebuilt with:

```sh
x86_64-w64-mingw32-g++ -std=c++20 -O2 -static \
  -DWIN32_LEAN_AND_MEAN cuda_feature_probe.cpp -o cuda_feature_probe.exe
```

### Current distant-character result

On the supplied 6K Wuthering Waves screenshot, using the character crop at
`2500,1300,1000,1000` and a 384-pixel model input, the exact model reduced
mean luminance over the pale leg/skin ROI to about `0.736x` while whole-frame
luminance was `0.983x`. Intensity `0` restored the ROI to about `0.9997x`, and
local structure `0` restored it to about `0.927x`. Constant and spatially
varying synthetic depth maps produced bit-identical outputs for this reset,
zero-motion single-frame test. This directly demonstrates a model/post-block
darkening prior, but does not by itself prove that the game's distance trigger
is independent of LOD, temporal history, color-transfer, or integration state.

Re-extract the resource blob into safetensors:

```sh
python extract_weights.py WEIGHTS_HT.bin dlssnr-310.8-weights.safetensors \
  --manifest manifest.json
```

Build the architecture manifest from the DLL graph trace:

```sh
python build_architecture_manifest.py graph-factory.log manifest.json architecture.json
```

Run real CUDA forwards through one split-Swin and one 1-D ViT block:

```sh
python dlssnr_pytorch.py dlssnr-310.8-weights.safetensors \
  --device cuda --all-middle --json pytorch-forward-smoke.json
```

The two Python classes can also be imported directly for activation probes,
weight ablations, layer comparisons, or as the compute side of a Blender
Python add-on.
