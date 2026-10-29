# Main accepted N64 block31 valid-row tensor lift

Five NumPy components consume the exact N64 producer and real block31 checkpoint slabs. First source-derived prediction matches every byte of all seven primary buffers (expand,contract,Q,K,V,attention,projection), without changing a predicted value or map after comparison. FIRST_PREDICTION.json pins those first implementation hashes; tests require them unchanged. Final65536B SHA43bc2ff775b2ea222fba26d8790e1814bb785053df50fdc5d6cde3d815b43222.

Changes from accepted N128 source templates are explicit valid-row domain64, original masked output admission for expand, and attention's one64-key block instead of two. Weight strides, half arithmetic, K32 boundaries, coefficient seeding, Q/K/V packing, normalization trees, bit-exp, pre-FP8 denominator vs FP8 numerator and LUT limits are unchanged. This is not ordinary softmax or once-rounded GEMM. Original CPU execution still computes its defined inactive rows; the tensor model omits their discarded results, without inventing external tokens.

## Independent original-stream observers

Full original arithmetic and synchronization still run. Observer labels are only byte provenance, never replacement arithmetic. Origin tags are published on the actual asynchronous shared completion. Numeric/origin checks cover valid rows; padding warps run unmodified without claiming a logical tensor comparison for discarded rows.

Per first/last group:
- Contract groups0/7:8192 valid MMA A/B-origin+C and D checks;8192 seed-half origins and8192 prequant/store checks.
- Projection groups0/7:2048 valid MMA origin/C and D;8192 seed-half origins/prequant/stores.
- QKV groups0/15:3072 valid MMA origin/C and D;12288 merge-temp/prequant/store checks;2048 norm2-half checks;64 scale origins.
- Attention heads0/31:all256 original MMA run; valid warp0 has32 score+32 PV checks and64 D checks,4096 probability halves,64 denominator partial/final halves,2048 output halves/store origins. Other warps are actual original padding computation, not suppressed arithmetic.

Five tests PASS: fresh full tensor chain matches literal outputs; preserved first prediction; first/last observer receipts; wrong QKV consumer basis rejected at actual MMA ingress; immutable hooks and missing/NaN domain refusal. Expand's mapping/tail uses the previously source-derived schedule plus the N64 store predicate and its complete original-grid output comparison; a new exhaustive per-MMA expand observer is not claimed.

`predict.forward(input_bytes, slabs)` returns raw physical outputs plus inspectable logical tensors for all stages; individual component `forward(...,hooks=...)` hooks remain immutable. Source/evidence helper imports still exist, so this is not yet an isolated distribution package or complete model. Only N64 is admitted here, not arbitrary token counts. N128 block32 reference remains unchanged.

Finite source-policy CPU equivalence evidence is not native kernel/whole-model/temporal equivalence. Source pool/head NN lifts, outer topology/allocator/geometry/counter epochs, full encoder/decoder/history and stable4h numeric mismatch remain separate. NoGPU/PE/Wine/installed/game/network changes.
