# Block56 4h upsample NN: zero-origin baseline accepted; actual shift still pending

**Do not read this as current-static block56 or complete NR acceptance.** Current-byte host proof establishes block56 origin **X=-4,Y=0**, not zero. This directory restores and checks the exact4h arithmetic on an explicit zero-origin diagnostic grid. The shifted boundary must be independently admitted and checked next. No game/deployment/GPU/PE execution/network changes.

## Identity and interface

- Exact `cc_tinlayout_fused_swin_4h_128_4_upsample_fp8`,7235 PTX operations,88-byte aggregate,8192 shared bytes,32x4 CTA threads.
- Source SHA `cab6214137cc9a94503177ddbeb7ad16a7834b67d048297ed78aab7e5fde6cb9`.
- Whole checkpoint SHA `890a53f05473dd6fd0980d1ca8501cfd84c1f6d7330b9531ca0981b6a6778d0e`; named block56 slab230176 bytes SHA `f73035bd13f1ce40ec2768b49eee02564e1ef5f7a4860375e7b1901c8e41ae83`.
- `nn.forward` performs tensor math only, using the existing independently measured finite-half LUT domain. Forward rejects file/process/dlopen/socket I/O under audit. Helpers remain local dependencies, not a standalone package.
- P0 is the actual prior original chained block55 channel16-planar A-basis8x8x256 byte stream (SHA `da7a1b96ed224ee61484ab7de892b162f9affb1c2b01a0dc7f85977e81fc1665`). No extra canonical-C reinterpretation or pi shuffle was added.
- P24 is a clearly labelled deterministic16x16x128 skip fixture, NOT restored encoder block14 output. Upper inputs to the earlier decoder chain are also non-live fixtures.

## Own source-derived NN weights/order

All bases, axes and loops are checked against actual MMA/byte operands, not ratios or serialized-F16 shapes:

| range | role |
|---|---|
|0..65536|128→512 expansion|
|65536..81920|four128→32 grouped contractions, nonidentity pi basis, not a multiplicative gate|
|81920..98304|128→128 FFN mix|
|98304..131072|256→128 low-resolution projection,8 K32 RN-half steps|
|131072..131328|FFN early residual gamma|
|131328..131584|late upsample skip gamma|
|131584..180736|128→384 raw QKV,4 K32 steps|
|180736..213504|four64x64 half QK seed matrices|
|213504..213520|four F32 Q scales, converted to half at the original point|
|213520..229904|128→128 final mix,4 K32 steps|
|229904..230160|final early residual gamma|

Trailing16 bytes are not invented as another weight tensor. Prefix is half projection→unquantized nearest2x→half skip multiply→half add→FP8. FFN/final residuals seed initial C, not late adds. Normalization retains the original half tree, floor, measured half-domain RSQRT, then Q-only scale. Attention retains packed32 shift/add, original reductions, half normalization→FP8 BEFORE PV, and per-K32 half accumulation.

## Two-query-half tail is preserved and verified

Original4h processes queries0..31, emits their result, then processes32..63. Normalized K/V and deferred packed16-bit Q survive the first phase. Every original instruction, barrier and zero path remains in the CPU oracle; the NN batches independent logical query rows only.

- Epochs1/2:prefix;3/4:group;5/6:FFN.
- Epochs7/8:first4096 bytes = first query-half PV; last4096 = FFN rows32..63.
- Epochs9/10:first4096 = second query-half PV; last4096 still FFN rows32..63.
- Source residual reads occur before each scratch overwrite. Final C seed and all four unrolled K32 carry producers are checked in BOTH phases. Normalization observer follows deferred Q packs and retained V through their real later uses; it does not manufacture them from snapshots.

## Evidence

First NN code and predictions remain byte-identical. All four original zero-origin CTAs execute2944 MMA each,10 barriers and4 warp returns each: **11776 MMA,16 warp returns**, all32KiB output bytes and all40 shared snapshots match.

Whole output SHA: **`7e2dfe373964e475dbedb08cf1a24a553444c5aeb9a256d350ff663c507fabf1`**.

- All four CTAs received prefix origin/raw/C/D, nearest/late-skip/prequant checks:512 unique prefix MMA. Actual block55 source-byte addresses cover its entire16KiB stream.
- CTA(0,0) has every one of its2944 original MMA proved across independent observers:128 prefix;1024 expansion+256 group+256 FFN mix;768 raw QKV;128 QK+128 PV+256 final. This is not claimed as a fresh all-MMA core observer for the other three CTAs; those have full original grids, all boundaries and prefix proofs.
- FFN:204800 scalar-result halves, activation/group/mix prequant and16384 store-provenance bytes.
- Raw:24576 projected halves. Norm:4096 RSQRT argument/result/half triples, Q/K/V each8192 prequant halves,8192 V transpose halves; both-phase QK/PV source-neuron formulas.
- Tail:all packed words, reductions,512 actual RCP calls for256 unique query/head denominators,16384 probability halves,8192 final seed/PV/final halves and original stores.
- Six tests PASS, including first-code identity, all-grid output, actual static shift kept distinct, required-source-byte refusal, wrong group basis and missing normalization negatives.
- `ERRATA.md` preserves normalization-observer shape failure and Main vtable/zero-origin/report-label corrections. No model arithmetic was patched to match.

## Host/configuration boundary

`HOST_PROOF.json`:55 current-byte witnesses. P0=I0,P24=I1,P8=O0,P16=slab; positive runtime+180/+184 override caller H/W. Builder desc+70=0,+74=1 copy to runtime+78=0,+7c=1. Forward emits Y=-4max(runtime+78,0), X=-4max(runtime+7c,0), hence static block56(-4,0), grid3x2 for16x16. This is current PE plus source-retyped historical factory ordering, not a live mutable-instance guarantee or sync-route acceptance.

Next: source-prove shifted P0/P24/OOB and late prefix masks, freeze a separate shifted NN prediction, then execute its complete6-CTA original grid. Original4h native226/8192 mismatch, full encoder/history/counter visibility, N64 all-new-block comparisons and standalone packaging remain open.
