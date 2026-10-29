---
library_name: onnx
pipeline_tag: image-to-image
tags:
- onnx
- image-to-image
- research
- dlss
- amd
- int8
---

# DLSS5 static-image ONNX reconstruction

A runnable reconstruction of the 71-block image network, using the real weight
package extracted from `nvngx_dlssnr.dll`. Includes the ONNX model, inference
script, source implementation, DLL extraction/export tools, and numerical
validation artifacts.

This is a research reconstruction, not an official NVIDIA release. It does not
reproduce the complete DLL or its temporal/rendering integration. Numerical
agreement does not establish improved image quality; flat and dark regions may
show added grain.

## Download and run

```bash
pip install huggingface_hub
hf download taowen/dlss5-onnx --local-dir dlss5-onnx
cd dlss5-onnx
pip install -r requirements-inference.txt
python tools/run_dlss5_onnx.py input.png output.png --resize
```

Inference needs ONNX Runtime, NumPy and Pillow. It does not need PyTorch, the
DLL, CUDA, or an external weight file. `--resize` resizes the input to 256×256;
without it the script requires a 256×256 image. The script handles conversion
between sRGB image files and linear-light model tensors.

| Model | Purpose |
| --- | --- |
| `models/dlss5_real_static_256.onnx` | Validated portable reference; FP64 reductions and emulated FP8 boundaries |
| `models/dlss5_real_static_256_amd_fp16.onnx` | Radeon GPU variant; FP16 matrices/activations and FP32 reductions; 301 MB |
| `models/dlss5_real_static_256_amd_int8_vit.onnx` | Calibrated mixed INT8/FP16 variant; 16 large ViT feed-forward matrices use INT8; 234 MB |

The reference model prioritizes reproducible arithmetic and is **not a native
FP8 GPU implementation**. The GPU variants deliberately change precision and
do not exactly match the reference. They retain the same linear-RGB tensor
contract. INT8 calibration uses the landscape and stone examples; earth and
portrait are held out from calibration. These four images are not a broad
quality evaluation.

### Radeon 890M on Linux

On the tested Linux machine with system ROCm 6.4.2 already working:

```bash
python tools/setup_amd_runtime.py
bash tools/run_amd.sh tools/run_dlss5_onnx.py input.png output.png --resize \
  --model models/dlss5_real_static_256_amd_fp16.onnx --provider amd --repeat 5
```

Select `models/dlss5_real_static_256_amd_int8_vit.onnx` to run the INT8 variant.
The project-local runtime uses AMD's ONNX Runtime/MIGraphX provider, with explicit
GPU placement and no CPU fallback. First compilation takes minutes; compiled
programs are cached for later processes. Keep a session alive when processing
multiple images. Setup prerequisites, runtime workarounds, export commands and
validation reports are described in [the AMD guide](docs/DLSS5_AMD.md).
The setup is specific to the tested ROCm/Linux stack; it is not a GPU driver
installer. CUDA and DirectML performance has not been measured for these files.

On the Radeon 890M, an alternating-order benchmark without profiling measured
**161.5 ms/image for FP16** and **176.5 ms/image for INT8**, after warmup at
256×256. INT8 is about 22% smaller but did **not** run faster than FP16 on this
machine. FP16 is the recommended speed variant here. Mean absolute errors vs
the reference were approximately 0.0044–0.0060 in linear RGB for both variants;
maximum individual-channel errors reached approximately 0.136. See the AMD guide
for per-image errors, timing variability and compilation/cache costs.

## Tensor contract

| Tensor | Shape | Type | Range / color space |
| --- | --- | --- | --- |
| `rgb` | `[1, 3, 256, 256]` | float32 | `[0,1]`, linear RGB |
| `output` | `[1, 3, 256, 256]` | float32 | `[0,1]`, linear RGB |

The model is fixed to batch 1 and 256×256, uses standard ONNX opset 17, and has
145,755,691 parameters. It embeds frame-zero noise and selects stateless current
color/history fallback, zero scalar/auxiliary features, and the reference RGB
post branch. It is not a general temporal upscaler or a masked inpainting API.

## Export from the DLL

Obtain the DLL separately. The tool checks the extracted package's SHA-256
before loading weights; other DLL weight packages are not silently accepted.

```bash
pip install -r requirements-export.txt
python tools/export_dlss5_from_dll.py /path/to/nvngx_dlssnr.dll \
  --output models/reexported.onnx

# Optional precision conversions from the published reference:
python tools/optimize_dlss5_amd.py
python tools/quantize_dlss5_int8.py
```

This extracts `WEIGHTS_HT`, loads the recovered network, reuses the published
`noise.npy`, exports ONNX, and validates four included images against PyTorch.
All graph source files are in `src/dlss5/`. The source repository contains
additional native-kernel analysis:
[taowen/dlss5-as-inpainting](https://github.com/taowen/dlss5-as-inpainting).

## Validation and provenance

The published reference was tested using PyTorch 2.12.0+cpu and ONNX Runtime
1.27.0 with four CPU threads. All four image outputs matched PyTorch exactly
(maximum absolute error 0). Reference timings were approximately 3.4–3.8 seconds
per image on the original test system; these are not GPU measurements.

PyTorch 2.7.0+cu128 on an RTX 5090 also matched the saved CPU ONNX outputs exactly
when using the same serialized input and noise buffers. This was a PyTorch CUDA
check, not an ONNX Runtime CUDA benchmark.

- ONNX: 1,167,220,673 bytes; SHA-256 `4f48985cd8398085910422745ed297d76dcd61bf6d77464ad8c4a06f7dc42c23`.
- Extracted weights: 147,695,410 bytes, 153 records; SHA-256 `836f445d06ecd2e59bb9f17b84b91c143396fd76ccda1c9dc7fe81d5edd548f4`.
- Reports and comparison images: `examples/cases/onnx_static/`.
- GPU precision reports, comparisons and unclamped CPU diagnostics: `examples/cases/onnx_amd/`.
- Detailed validation: `docs/DLSS5_ONNX_VALIDATION.md`.
- Test-image attribution: `examples/assets/SOURCES.md`.
