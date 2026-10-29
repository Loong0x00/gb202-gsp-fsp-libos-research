# Eight ViT blocks as an inspectable N64 source-policy NN component

`ViTStack64.from_checkpoint(path)` loads original pinned block31–38 weights (40 named descriptors, including the plain attention programs' unused2-byte descriptors). `forward(features,hooks=...)` accepts canonical uint8 E4M3 `[64,1024]`; `forward_head_2d(head_bytes)` additionally performs exact block31 input repack. Result exposes canonical output,1D physical bytes and block38's exact2D repack for the decoder. There are explicit source-layout adapters, no pointer ABI, PTX VM, DLL or GPU forward call.

Example probe: `hooks={'block38.qkv.Q': lambda x: print(x.shape)}`. Individual core stages preserve immutable logical hooks. `keep_stages=True` retains logical matrices, norms, split partials and activations for each block; default avoids retaining all decoded weights. This is inference/observation, not a claimed differentiable or intervention-equivalent training reconstruction.

Current-source outer binding audit establishes the31→38 primary sequence and distinguishes auxiliary flags from feature outputs. Block31 repack and block38 repack are performed only at their respective boundaries. N64 only; unsupported shape/NaN domain fails closed. No unknown token padding. Original perK32 half rounding, learned residual seeding, nonstandard attention and measured LUT policies remain explicit.

The complete eight-block NN forward ran on the pool/head conditional fixture.56 primary buffers and40 weight ranges are frozen in FIRST_STACK_PREDICTION.json before later oracle comparisons. Final1D SHA6e8cb2e6bcd28fc11767fc2199ad0f7cba7932c7ce0e6858f8b63f8b7254d3dc; final2D SHA9e98785bb64de3fe3ecb34d0d7c74b9a50998fc4816ab415da3c8ab561ce9bab. Four tests PASS: fresh repeat with immutable named probe, all saved buffers/weights, canonical axes through both source codecs, domain refusal.

## Evidence boundary — important

Block31's seven primary buffers match its complete original CPU grid; core operators additionally have source/per-operand checks for N64 block31 and N128 block32. **New N64 numeric predictions for blocks32–38 have not all been compared with their own complete original-instruction grids.** No native GPU/whole-stack equivalence is claimed from repeated NumPy execution alone. This is a source-policy stack component, not completion of the full NR model.

Upstream pool inputs remain explicitly synthetic/non-live; full encoder/decoder/history, broad geometry/allocator/epoch/visibility and original4h numeric mismatch remain open. Local source/evidence dependencies also remain, so not yet an isolated distribution. NoGPU/PE/Wine/game/install/network changes.
