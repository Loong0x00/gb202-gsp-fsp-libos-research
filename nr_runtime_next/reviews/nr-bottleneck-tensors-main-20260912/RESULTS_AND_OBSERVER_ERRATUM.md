# Main accepted pool/head NN tensor lifts

First source-equation predictions for both components match all original-CPU outputs unchanged: pool full131072B c1315f7b…, pooled32768B80caf86e…, head65536B9b0df1cf…. Both tensor implementation hashes remain those saved BEFORE comparison. Separate full-grid observers subsequently verify original operands and prequantization, not merely FP8 output agreement.

## Neural operations and source-backed coordinate rules

- Pool:512→512 matrix over16×16 positions; learned half skip product is initial MMA C; RN-half each K32. Full output is FP8. Pooled output retains full HALF results, does horizontal pair sums (00+01),(10+11), then sum and half×0.25, then FP8. Original shuffle lane0 indices0,4,16,20 and all observed expression leaves establish the ordered2×2 tree.
- Head:512→1024 matrix over8×8 positions, zero initial C, RN-half each K32, then FP8. Matrix at slab offset0; no use of the final16 serialized bytes is inferred from their mere presence.
- Pool CTA warps own64 output channels each and all four spatial4×4 subtiles. Head warps own64 channels and two horizontal subtiles, with warp-group selecting the vertical half. These are checked against actual A/B byte origins and independently decoded warp fragments, not inferred from parameter count.

## Entire bounded grids checked

Pool8 CTAs:16384 original MMA A/B-origin/raw-value/C and D-half checks;131072 initial learned-skip/coefficient half origins;131072 full prequant halves/stores;196608 ordered-mean add operand halves;32768 quarter-factor/ordered-mean prequant halves/pooled stores. Head4 CTAs:8192 original MMA origin/C/D checks and all65536 prequant halves/store lineages. Arithmetic, loops, elected copy issuers, mbarriers and original stores remain untouched. Source tags are only observers.

Five tests PASS: first predictions; full-grid receipts; wrong ordered mean expression refused; observer active-lane regression; immutable hooks and missing spans. A separate counterfactual moving FP8 quantization BEFORE pooling changes31930/32768 half means and6731/32768 final FP8 bytes. The source retains half registers; this is a rejected shortcut, not a fitted correction.

## Main observer erratum — failures preserved

Initial generic checker guessed the pool warp decomposition from a nearby template. Current pool source r9=(warp<<6)+(channel_group<<8) corrected this BEFORE pool checking; unexecuted candidate is saved. Tensor equations/predictions did not change.

The first actual pool checker failed at original mean PC2092: it applied predicated metadata mov/selp writes to ALL lanes. Lane0 incorrectly acquired logical label12288 instead of keeping its branch-selected source. Original VM arithmetic was already executing active lanes correctly. The fix updates observer arrays only for active lanes. That exposed a second metadata-only issue: `mov.b64 %rd263,0` had assigned four unknown origin bytes instead of the opcode's eight. Typed immediate origins now use declared width; data-bearing width mismatches fail closed. Failed checker snapshots, initial/diagnostic logs and the prior head receipt are retained. After corrections ALL pool/head grids passed. Neither the original VM nor neural tensor arithmetic/weights/predicted values was altered. Tests deliberately reintroduce all-lane metadata writes and require rejection.

These are bounded CPU/source-policy components with local helper/evidence dependencies, not an isolated full-model/native-equivalent distribution. Input pool activations remain the explicitly declared fixture, not recovered whole encoder output. Full temporal/geometry/allocator behavior, native SASS arithmetic and4h226/8192 remain open. NoGPU/PE/Wine/installed/game/network changes.
