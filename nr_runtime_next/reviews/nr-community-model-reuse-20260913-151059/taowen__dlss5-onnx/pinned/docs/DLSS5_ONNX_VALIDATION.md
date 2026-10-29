# Real-weight static ONNX model

`models/dlss5_real_static_256.onnx` is the current runnable artifact. It uses
145,755,691 parameters from the recovered 71-block graph and the actual
`WEIGHTS_HT.bin` (147,695,410 bytes, 153 records). It is not the small fitted
`DLSS5PortableModel`.

Four real images pass CPU PyTorch / ONNX Runtime comparison with **zero maximum
absolute error**. Outputs preserve recognizable image structure and color and
remain finite in [0,1]. Some flat/dark regions have visible added grain. This
establishes runnable static inference and numerical consistency; it does not
establish superior image quality or equality to the complete NVIDIA DLL.

## Run an image

```bash
python -m pip install -e '.[onnx]'
python tools/run_dlss5_onnx.py \
  examples/assets/normalized/blue_marble.png output.png
```

For a differently sized image, add `--resize`; the result is 256×256. The CLI
handles sRGB decoding and encoding. It runs with ONNX Runtime's CPU provider
and does not need CUDA, the DLL, cubin files, or an external weight file.

The ONNX contract is:

| Name | Shape / type | Meaning |
| --- | --- | --- |
| `rgb` | float32 `[1,3,256,256]` | Linear-light RGB in [0,1] |
| `output` | float32 `[1,3,256,256]` | Linear-light RGB in [0,1] |

Do not feed sRGB byte values directly to the ONNX input. The model is fixed
size and batch 1. Its operators are standard ONNX opset 17; there are no custom
DLL or CUDA operators. GEMM and normalization reductions use FP64 internally
to make half/FP8 rounding stable between the tested runtimes. This is a slower
reference implementation, not a real-time implementation.

Direct PyTorch use:

```python
import torch
from dlss5 import DLSS5Graph, DLSS5StaticImage

graph, _ = DLSS5Graph.with_weight_map("../DLSS5-extracted", load_known=True)
model = DLSS5StaticImage(graph).eval()
with torch.inference_mode():
    output = model(linear_rgb)  # float32 [1,3,256,256]
```

The serialized ONNX embeds its frame-zero noise buffer. When comparing a fresh
PyTorch reconstruction across different PyTorch versions, reuse the saved
`examples/cases/onnx_static/noise.npy` buffer: transcendental implementations can
otherwise change a few half-rounded noise samples. The verification scripts
preserve this buffer when using `--skip-export`.

## Export and reproduce validation

```bash
python tools/export_dlss5_static_onnx.py --weights ../DLSS5-extracted
python tools/export_dlss5_static_onnx.py --skip-export
PYTHONPATH=src python -m unittest discover -s tests -v
```

The exporter checks the ONNX graph, evaluates all four images, saves the input
and output tensors, and exits nonzero if numerical parity fails. A pass applies
to these test cases, not to every possible backend or input.

Artifacts:

- Model: `models/dlss5_real_static_256.onnx`, 1,167,220,673 bytes (about 1.09 GiB).
- Metrics: `examples/cases/onnx_static/validation.json`.
- RTX 5090 PyTorch comparison: `examples/cases/onnx_static/cuda_validation.json`.
- Weight-loading audit: `examples/cases/onnx_static/weight_report.json`.
- Visual comparison: `examples/cases/onnx_static/comparison.jpg` (input / PyTorch / ONNX).
- Individual results: `examples/cases/onnx_static/*_onnx.png` and `*_onnx.npy`.
- CLI smoke test: `examples/cases/onnx_static/cli_blue_marble.png`.
- Weight SHA-256: `836f445d06ecd2e59bb9f17b84b91c143396fd76ccda1c9dc7fe81d5edd548f4`.
- ONNX SHA-256: `4f48985cd8398085910422745ed297d76dcd61bf6d77464ad8c4a06f7dc42c23`.

## Real-image results

Measured with PyTorch 2.12.0+cpu and ONNX Runtime 1.27.0, four CPU threads.
Image sources are documented in `examples/assets/SOURCES.md`.

| Image | Maximum ONNX / PyTorch error | Output / input MAE, linear RGB | ONNX inference |
| --- | ---: | ---: | ---: |
| scenic_landscape | 0 | 0.00728 | 3.72 s |
| stone_texture | 0 | 0.01059 | 3.80 s |
| blue_marble | 0 | 0.00847 | 3.38 s |
| portrait_cc0 | 0 | 0.00599 | 3.58 s |

All output tensors are finite. The first three span [0,1]; portrait spans
[0,0.91709]. Input difference measures the amount of change, not improvement.

PyTorch 2.7.0+cu128 on the RTX 5090 also matches all four saved CPU ONNX outputs
exactly when using the same input arrays and serialized noise buffer. This is
a CUDA PyTorch check; ONNX Runtime's CUDA provider was not tested.

The report also records the **unclamped** enhanced image and raw residual.
Unclamped out-of-range fractions are approximately 8.1%, 13.0%, 29.3%, and 5.0%
respectively. The final saturation is the recovered native RGB post branch,
not a substitute for checking the raw network output. Dark regions in the
Earth image account for many of its negative residual pixels.

## Recovered static contract and remaining scope

The explicit static settings are frame=0 PCG noise, color scale=.125, current
color copied to the history fallback, and zero scalar/auxiliary features.
Post processing adds `8 * neural` to the reference linear RGB, saturates that
result, and blends with the input using the real stored source weight
`0.73974609375`.

The [reconstruction fixes and RTX 5090 kernel probes](DLSS5_PYTORCH_FIXES.md)
cover weight packing, offsets, residuals, attention, and spatial aliases.
The native sm_120 kernels were run directly on the 5090. Complete temporal
resource binding, host dynamic parameters, native half accumulation order,
and the Windows host's larger internal canvas are not reproduced bitwise.

The original `models/dlss5_reference_fp32_256.onnx` and results in
`examples/cases/onnx_reference` are historical failed diagnostics with an
explicit front-feature input. They are not the current static model. The
53 KB portable ONNX is also a different, small fitted network.
