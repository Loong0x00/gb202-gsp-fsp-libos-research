# Block61 OUTVIEW NN and bounded decoder48–61 composition

**Accepted bounded component; not complete NR/native/standalone.** CPU/static evidence only. The default uses actual prior original block60 bytes; upstream inputs remain three non-live feature fixtures. No game/deployment/GPU/PE-execution/network changes.

## Source, weights, unchanged first model

Exact `cc_tinlayout_fused_swin_4h_128_4_outview_fp8`:5260ops,88ABI,8192shared bytes,32x4threads. Source SHA `97e0a1b279493e407941bfb8a53e41bcdacd0020b355dd4ff0f351632d19e153`. Original named block61 slab197184bytes SHA `845c4b4f0c1b2df91815d65930a53640b431cc7b9b93b47d567dd6bf07c13d6a`; public construction verifies the whole checkpoint pin.

4519 common-core instructions match ordinary4h exactly under unambiguous register/shared-symbol/branch renaming, including target PCs. Ingress and writers are deliberately outside that theorem and separately proved from actual byte/neuron origins. Weight bases/gaps and scalar/K32 order are independently checked, not inferred from opcode counts or a same-size slab.

The first private parser rejected `st.global.v2.b16`; only the already-implemented2-byte-element vector form was admitted in this isolated VM. Original PTX and arithmetic unchanged. First NN code and all four predictions remain unchanged. The failed wider alpha scope/coordinate-register reuse diagnostic is preserved in ERRATA.md, not hidden by changing the model.

## Output is A-basis, not a C reshape

Every actual final-MMA neuron is tracked through FP8 conversion into its4-byte transaction. The physical output is channel16-planar `(8,OH,OW,16)`:

`offset = 16*((k//16*OH + global_y)*OW + global_x) + k%16`.

The value at physical channelk is **canonical-C channelpi(k)**, not channelk. An8192-element static C-slot/code derivation is closed by every actual final-MMA operand/store check. Identity-channel substitution is rejected by neuron provenance even where values could be equal.

Raw signed output words80/84 select positive values, otherwise input32/36 H/W. Both guards and strides use selected extents. Whole64-query windows execute before per-coordinate output masking; expansion cannot be implemented by zero-filling an already-masked ordinary output.

## Frozen cases and complete original grids

| case | origin | selected OHxOW | CTAs / MMA | output SHA |
|---|---|---|---|---|
|default|0,-4|16x16|6 /16896|0528e764aba58d7beecb26765d2b719d244977128abb954f221f069832f0810f|
|zero-origin diagnostic|0,0|16x16|4 /11264|9e4c027e4c85921825f73beb73107bf3333530713ab530b27db8f18ea816b4e3|
|crop|0,-4|13x11|6 /16896|c92108f4419a6c35ce8bea562529401744b95b1a461d343a7e78a3bc6dacfd91|
|expanded|0,-4|20x16|6 /16896|e813fa6c2a7c806ab60c74ab9c9a7e0ac7ef1443f0eb54dacc6955734d3b72d1|

All22originalCTAs/61952MMA/88warp returns/220shared snapshots and all final bytes match. The original expanded rows16..19 contain8192bytes, **6865 nonzero-magnitude bytes**. They are computed ghost outputs, not invented padding. Unproduced21x16 is rejected by the public reference rather than filled silently. Actual negative raw fields(-1,INT32_MIN) were also executed and verified to select16x16 fallback.

## All default six CTAs, every operand/scalar/two-phase lifetime

All16896default MMA are independently source/raw/C/D checked across every CTA:9216FFN+4608raw+768QK+768PV+1536final. Ingress sourcezero, activation, gamma seeds, every norm/RCP/packed/reduction/probability checkpoint and every output-neuron address are checked. Deferred Q16-bit packs and retained K/V survive the first query half; source epoch6/8 residual reads, epoch7/9 PV scratch reuse and all four unrolled final K32 carry producers are preserved.

Both crop and expanded last-row CTAs additionally receive complete tail source/scalar/store checks:2048more tail MMA across four CTA cases. This is separate from the all-case whole-grid/boundary comparisons, not a claim to repeat every core observer on every extra case.

## Host and public NN

20 selector/setup witness checks plus61 prior current-byte checks revalidated (not asserted unique). The normal non-DS aggregate initializes80/84 to zero and skips the DS overwrite. Static block61 origin remains(0,-4). These are conditional current-PE/factory facts, not fresh live mutable-instance or wait/tilesync/counter-visibility acceptance.

`model.Outview4hReference.from_checkpoint(path)` exposes9immutable logical weight views, canonical-C uint8E4M3 input[16,16,128], selected-extent logical A-basis output[OH,OW,128], packed planar output and immutable logical hooks. Forward is pure NN math, not a DLL/interpreter wrapper; local helper imports remain a packaging gap.

`chain.Decoder48to61` connects all14NN blocks; every boundary matches its original CPU evidence and first whole-chain forward after construction passes file/process/dlopen/socket-I/O rejection. Prior original48–60 evidence was reused, NOT newly executed in that chain check. New original61 default grids consumed exact original60 output.

A separate non-live heldout input, not claimed as a block60 activation, was frozen before another6originalCTAs/16896MMA/all60boundaries/full-output check. SHA **`1df32b9a3ac77209d978dc9c83c10709d8446294d8af233c1ff5d2cd2b27e0d2`**. Heldout adds grid/boundary evidence, not another all-MMA intermediate observer.

Nine tests PASS. Full encoder/pre-post/history/counter/workspace/ViT-newblock coverage, standalone packaging and original4h226/8192native mismatch remain open. Next is own2h upsample block62; its consumption of this A-planar output must be established from its actual operands, not adjacency/layout names.
