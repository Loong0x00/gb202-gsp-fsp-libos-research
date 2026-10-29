# Main accepted decoder-input NN tensor lift

The first frozen tensor prediction matches every131072 original-CPU output byte, SHA400f1915123127068305daf6d82cba968cd949b4d267fb7334e53259a3882002. No prediction/layout/value correction after comparison. More importantly, a separate observer now checks the ENTIRE bounded original grid, not merely final FP8 output agreement.

Recovered neural operation for8×8×1024 plus16×16×512 skip:
1. Low-resolution1024→512 FP8 matrix, four K256 partitions with zero initial C, RN-half after each K32.
2. Original ordered half merge of the four partitions.
3. Exact2× nearest replication of the unquantized half projection.
4. Separate half multiply of full-resolution skip by its512 learned half coefficients, followed by half add to the upsampled projection.
5. Source FP8 conversion and independently checked physical stores.

**Unlike ViT FFN/attention projection, this decoder's learned skip is late, not the initial MMA C.** It must not inherit an earlier residual-placement rule merely because both are called projections. Nearest expansion is not bilinear and must not quantize the low-res projection before replication/addition.

## Whole-case provenance and intermediate proof

All8 spatial/channel groups ×4z retain original loops, elections, async publication, barriers, polling, RED and real arithmetic. Shadow origins/labels do not replace arithmetic. ALL_OPERANDS.json aggregates:

-8192 actual MMA A/B byte-origin, raw operand and C-half checks, plus8192 D-half checks; each source-derived K/N rectangle appears once in its proper CTA/warp shard.
-32768 temp-half initialization labels and65536 RED-before half checks.
-131072 coefficient-half checks tied to actual suffix loads and full skip channel labels.
-131072 nearest-source/late-skip half checks: logical low-res labels propagate through original MMA/temp/shuffle operations, full skip labels come from original memory bytes; the source add must connect low(y//2,x//2,c) to full(y,x,c).
-131072 prequantization-half comparisons and131072 actual output-byte lineage/store-position checks.

This independently proves the nearest relation and residual placement for the bounded case, rather than fitting them to the final output or accepting a bijection alone. Five tests PASS, including real wrong-nearest lineage rejected at an original add, complete first-prediction preservation, whole-grid receipts, immutable hooks and domain refusal.

`tensor_reference.forward(source_bytes,skip_bytes,slab,hooks=...)` exposes ordinary logical matrix/partial tensors, low half projection, upsampled half, scaled skip, prequantization and output. Tile-major spatial axes and producer/consumer channel basis are explicit in the maps. No DLL/VM forward; local source/helper dependencies remain.

Scope remains CPU source-policy and8×8→16×16, real block39 slab, predicted upstream ViT and declared pool fixture. Native SASS fusion/rounding, optional alias route, complete encoder/decoder/history and whole-model equivalence are not claimed. NoGPU/PE/Wine/installed/game/network changes.
