# Source-connected, inspectable block32 CPU reference

**One non-repack ViT block, not the complete model or native-equivalent delivery.** Public canonical E4M3 code tensors `[128,1024]`→hidden`[128,4096]`→`[128,1024]`;32 attention heads×32 channels. Source-backed host primary graph is reviewed in `../nr-vit-block-executor-main-20260912/RESULTS.md`.

```python
from block import Block32Reference
model = Block32Reference.from_checkpoint('/path/to/dlssnr-310.8-weights.safetensors')
result = model.forward(features, hooks={
    'qkv.Q': lambda q: print(q.shape),
    'attention.scores': lambda s: print(s.shape),
    'projection.prequantization': lambda h: print(h.shape),
})
y = result['output_fp8']
stages = result['stages']  # logical weights, activation views, partials, norms
```

`features` is uint8 **E4M3 codes**, not RGB or uint8 linear intensity. Input N64, float16 arrays, NaN codes, short slabs and unsupported arithmetic domains fail closed. No implicit unknown-token padding. Named observations receive detached immutable arrays; forward accepts observation hooks, not arbitrary in-place activation edits. Broader intervention API follows equivalence work rather than changing the baseline semantics now.

The five named checkpoint ranges are separately pinned, including the2-byte attention descriptor retained as provenance but not read by this plain attention program. FFN residual is seeded before z0 MMA; projection residual is retained FFN output P. Neither is a final high-precision shortcut. QKV preserves source half normalization trees; attention is the source affine/clamp/bit-exp and half tree, not ordinary softmax. All K32 and split-half rounding remains explicit.

Forward is lifted NumPy tensor arithmetic, not a call to the literal interpreter. The wrapper has explicit pure-NumPy byte-layout adapters at component boundaries; stage tensors retain their documented consumer-coordinate bases. It does not pretend those permutations never existed. After construction, the verified forward performs no file, process, dynamic-library or DLL I/O (runtime audit test); source call-graph inspection additionally shows no PTX VM call. That I/O test alone is not claimed to prove absence of in-memory interpretation.

Five tests PASS. Fresh whole-block output and all primary intermediates match the sealed original-instruction CPU chain; output131072B SHA `07b7b4ca88e84c5a073ebfb7ecd631edaeb131387b03daa90561e0b4682cc163`. `run.py` records the fresh forward and separate public-logical vs physical output hashes; test fixtures do not invoke the DLL.

## Still open

- N128 finite reference-policy scope; QKV sqrt32 RNf32, measured half-domain RCP/RSQRT and original source half arithmetic do not establish native kernel equivalence.
- Source/evidence helpers in sibling review directories are still needed at import. This is independent *compute*, not yet a self-contained distribution package.
- Block31 input-repack, block38 output-repack, N64 pool/head connection, full encoder/decoder/history assembly, live allocation/counter epochs and visibility are not provided here.
- Stable original4h226/8192 mismatch and general SASS/approx/accumulation differences remain open.

NoGPU/PE/Wine execution or game/install/network changes. Existing game deployment continues using the original signed GPU DLL.
