# Where Winds Meet community package — DLSSNR weight audit

Source used by the public RenoDX/ReShade-style tutorials:

`https://github.com/yumlevi/renodx-dlss-installer/releases/download/latest/streamline.zip`

Audited as data only; no unknown DLL was executed.

## Package/runtime

- Package SHA-256: `5389d164ef99a0e4aba5128da2e87d26de5833aeaf89bfeb0232cfdc8f7229a2`
- Bundled `nvngx_dlssnr.dll`: 165,840,496 bytes
- Bundled DLL SHA-256: `ceb6432f6fbdf44d886014bcd47241932bf8b67439feef9bbdd0961436662650`
- `sbverify`: signature verification failed because the Authenticode image hash does not match.
- Signed local NVIDIA baseline SHA-256: `e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e`; `sbverify` reports `Signature verification OK`.

## Decisive model comparison

Both DLLs contain one `RCDATA/WEIGHTS_HT` resource of 147,695,410 bytes.

- Community/WWM package weight SHA-256: `836f445d06ecd2e59bb9f17b84b91c143396fd76ccda1c9dc7fe81d5edd548f4`
- Signed 310.8 baseline weight SHA-256: `836f445d06ecd2e59bb9f17b84b91c143396fd76ccda1c9dc7fe81d5edd548f4`
- `cmp`: byte-identical.
- The entire `.rsrc` section is also byte-identical.

The package modifies `.text` and `.data` (12,318,347 differing bytes, offsets confined before the resource section) while retaining the old certificate table, hence the failed signature. It does **not** contain Where Winds Meet-specific model weights.

The common baseline weight map contains 153 FP16 tensors with 147,683,778 tensor-payload bytes. The reconstructed graph has 71 blocks and 152 layers. Thus the widely posted Where Winds Meet footage is evidence of community code/integration around the same 310.8 model, not evidence that NetEase shipped or fine-tuned a new checkpoint.

## Interpretation

Current evidence supports a shared conditioned model plus per-game/per-scene integration controls (input contract, model selection, tone/structure controls, semantic/engine masks). It does not support mandatory gradient-based retraining of weights per game. A real per-game weight claim requires comparing untouched NVIDIA-signed DLLs from two official game depots.
