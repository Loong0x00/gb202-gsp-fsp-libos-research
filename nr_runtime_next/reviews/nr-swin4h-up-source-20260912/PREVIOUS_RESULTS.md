# Decoder8hStack — NN blocks48..55 with original chained-grid verification

`stack.Decoder8hStack.from_checkpoint(path).forward_packed(low,skip)` uses original named slabs48..55 and explicit pinned finite-half-domain LUTs. It returns per-block packed outputs and final `output_planar_A_basis`. Input is the proved block48 channel16-planar4x4x512 plus canonical-C skip8x8x256, NOT RGB or a recovered live encoder output.

-48: complete upsample/core NN.
-49..54: complete ordinary8h NN, with CURRENT-STATIC expected origins(-4,-4),(-4,0),(0,-4),(0,0),(-4,-4),(-4,0).
-55: OUTVIEW NN with origin(0,-4), output channel16-planar **A basis**, not canonical-C identity.

These origins come from the current factory table plus source-retyped historical ordering; no live mutable-instance/auxiliary synchronization route is asserted. Whole checkpoint and named ranges verified during construction. First full NN forward after construction passed a guard rejecting file/process/dlopen/socket I/O. Local helper imports remain: not a standalone distribution.

## Independent original chain

The first eight NN predictions were frozen before the new original-grid comparison and remain unchanged. Original block48 output is the separately sealed prior original CPU result. The NEW original49..55 runs consume each preceding ORIGINAL output, not independent replacement predictions:

-17completeCTAs,136warp returns,174080independent-MMA calls;
-49..55 all original ingress/group/FFN/PV shared boundaries and all final output bytes matched the frozen NN predictions;
-all new49..55grids compared=True (not merely repeating NumPy);
-block48's prior10752MMA evidence is identified separately, not called a new run.

Final16384B OUTVIEW A-planar SHA **da7a1b96ed224ee61484ab7de892b162f9affb1c2b01a0dc7f85977e81fc1665**.

`RESULTS.json`, `FIRST_STACK_PREDICTION.json`, `ORIGINAL_CHAIN_PROGRESS.json`, per-block original/prediction files and4passing tests provide evidence. Existing component observers supply exhaustive boundedMMA/scalar/layout proofs; this new chain adds all-grid/boundary comparisons for new weights/activations, not a fresh all-MMA intermediate observer on every new block.

## Limits

This is a complete bounded decoder8h subsection, NOT complete NR or native equivalence. Upper inputs remain explicit fixtures, original4h226/8192native mismatch and full encoder/ViT-all-block/original/pre-post/history/visibility/standalone gaps persist. Next consumer is block56 4h upsample; its source/format connection must still be independently restored. Game deployments unchanged; no GPU/PE/Wine execution or network changes.
