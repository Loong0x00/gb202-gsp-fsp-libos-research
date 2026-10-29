# Block56 actual-static shifted NN and bounded decoder48..56 chain

**Accepted bounded component, not full NR/native/standalone.** Main restores the source-proved static block56 configuration X=-4,Y=0, effective16x16, grid3x2, using actual prior original block55 bytes and an explicitly non-live encoder-skip fixture. This does not assert a live mutable-instance/sync-route configuration.

## First predictions and original grids

`nn.py` was written separately from the preserved zero-origin baseline. The five arithmetic modules are byte-identical copies of the already-proved4h equations. It adds actual-coordinate source-zero gathers, the original post-late-add high-coordinate masks and valid-coordinate final stores. It does NOT pad caller allocations, skip invalid-token arithmetic, or execute an interpreter in NN forward.

Original `cc_tinlayout_fused_swin_4h_128_4_upsample_fp8`:7235ops/88ABI/8192shared/32x4threads; source SHA `cab6214137cc9a94503177ddbeb7ad16a7834b67d048297ed78aab7e5fde6cb9`. Named230176-byte block56 slab SHA `f73035bd13f1ce40ec2768b49eee02564e1ef5f7a4860375e7b1901c8e41ae83`; checkpoint pin and55 current-byte host witnesses copied unchanged.

First NN prediction was frozen before original execution. All6originalCTAs execute2944MMA each,4warp returns and10barriers: **17664MMA,24warp returns,60shared snapshots**, all match. Edge CTAs write4096bytes; middle CTAs8192; complete32768-byte output is nonoverlapping and fully covered.

Output SHA: **`742aaa8c515bbe972c3d7a268649f4a3a62a960bda2ab089237b3e596193ec4e`**.

## Every original MMA and scalar stage, on all six CTAs

Unlike the earlier zero baseline's representative core observer, this shifted run checks every CTA:

- Prefix768MMA, full A/B byte origins/raw/C/D, unquantized nearest2x, per-high-pixel skip multiply/add, final prequant and all96late selects/CTA. P0 source-byte union is its entire16KiB original block55 A-planar stream; no extra pi/C reinterpretation.
- Edge low gathers:2048real+2048sourcezero bytes; edge skip gathers:4096real+4096sourcezero bytes. Middle windows are fully sourced. Zero tags originate in actual literal-zero/mov/half/FP8 instructions, not an unknown-origin sentinel treated as zero.
- FFN6144expansion+1536group+1536mixMMA; actual source bases/pi basis/early seeds,1,228,800scalar-result halves and all FP8/store provenance.
- Raw4608MMA and147456raw halves; normalization24576RSQRT argument/result/half triples; eachQ/K/V49152prequant halves,49152V transpose halves. DeferredQ16-bit packs, retainedK/V and both query halves are source-neuron checked.
- Attention768QK+768PV+1536finalMMA. Both-phase packed-word map, exact reduction tree,3072actual RCP calls, probability normalization→FP8 BEFORE PV, residual seeds and every unrolled K32 carry producer are checked.

The original two-phase scratch lifecycle is preserved: epochs7/8 use first4096bytes for PV queries0..31; epochs9/10 reuse those same bytes for PV32..63. Last4096FFN bytes persist for the second residual seed. All60mixed shared snapshots match, with original barriers intact. CPU scheduling does not prove native visibility or counter lifecycle.

The source's late masks are retained even though this baseline fixture has zero numerical half-bit changes from them. Their predicates/selects are independently verified and a mask-elision negative is rejected. See source-worker erratum for ceil/truncation and high-resolution P24 clarification.

## Public NN and composition

`model.Block56Reference.from_checkpoint(path)` provides:

- `forward_packed(P0_A_planar_bytes, P24_C_packed_bytes)`;
- `forward(low_A[8,8,256], skip_C[16,16,128])`, uint8 E4M3, canonical-C output[16,16,128];
-11 immutable logical weight views and immutable named window/output hooks.

The input low channel basis is the learned P0 A basis: physicalk is prior block55's C channelpi(k), as already proved at producer and now verified at every consumer load. It is not an RGB/model-input interface.

`chain.Decoder48to56` joins NN48..55 to this block56 without repacking the block55 physical byte stream. All nine outputs match their original CPU evidence; first whole-chain forward after construction passed file/process/dlopen/socket-I/O rejection. Original48..55 evidence is reused and explicitly NOT claimed freshly executed in this chain check. New original56 grids consume the exact prior original55 bytes.

A separate heldout low/skip pair was frozen before another complete6-CTA original run:17664MMA,all60boundaries/full output agree. Heldout SHA **`37a312aa65b98699a9411e12cb0cdb7f74f9bf347d794e4db272aeaaae8f152c`**. Heldout adds grid/boundary coverage, not another all-MMA intermediate observer, and its low tensor is not claimed as a block55-produced activation.

Eight tests PASS. First shifted code/predictions, first zero-baseline code/predictions and original PTX are unchanged. No unexpected NN/observer failure occurred in this shifted run. Local sibling imports remain; no standalone delivery, game performance or native equivalence claim. Upper fixtures, full encoder/history/counter/workspace/ViT-newblock checks and original4h226/8192native mismatch remain open. Next: ordinary4h blocks57..60, then61outview and62upsample with own source/binding evidence.
