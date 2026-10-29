# Main canonical-channel FFN module (bounded CPU reference)

`ffn.py` provides `Block32FFN.from_checkpoint(path)` and `forward(input_fp8, hooks=...)`.
The public input/output are canonical-C-channel uint8 E4M3 tensors of shape[128,1024]. Hidden features are[128,4096]. No pointer ABI, counter address, PTX instruction interpreter or DLL call occurs in `forward`; pinned source-derived numeric/layout helpers remain local Python dependencies, so this is not a self-contained whole-model distribution.

Both learned matrices expose ordinary, immutable logical arrays. The consumer MMA-A channel permutation is absorbed into their K axes through inverse pi. Pi stays within each K32 block, preserving the exact finite-sum/per-K32-half reference semantics. Named hooks expose input, expand preactivation/output, contract initial C, each z partial, prequantization and output as detached immutable observations. They are not intervention/autograd support or a native-equivalence certificate.

Crucially, learned skip is the initial C of the first projection partition, not a residual added after the full projection. On the frozen input, that tempting alternative changed **94798/131072 prequantization half values**. The negative result is retained in `LATE_RESIDUAL_NEGATIVE.json`.

Six Main tests PASS:
- named safetensors ranges/identities (no raw-offset-delta assumption and no dense-F16 container interpretation);
- canonical matrix-axis relation for both real weight matrices;
- complete131072-byte output equality against the sealed original CPU contract grid;
- all524288 expand preactivation half values and524288 expanded FP8 values match prior reference artifacts;
- late-residual negative, immutable observations/weights and input-domain refusal.

Use `OPENBLAS_NUM_THREADS=1 python3 -B test_ffn.py` in this directory.

This is an inspectable **bounded FFN component**, not the entire ViT block/model, general image input, all numeric domains, live counter-epoch/visibility proof or native GPU equality. Existing4h native discrepancies remain unresolved. NoGPU/PE/Wine/installed/network changes.
