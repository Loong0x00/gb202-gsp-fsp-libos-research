# Ordinary4h blocks57–60 and bounded NN48–60 chain

**Accepted bounded components, not full NR/native/standalone.** All work is CPU/static under reviews; game deployments unchanged. Inputs ultimately come from three explicitly non-live upper feature fixtures. Block61 OUTVIEW is excluded.

## Identity and actual source fields

Exact `cc_tinlayout_fused_swin_4h_128_4_fp8`:4804ops,88ABI,8192shared bytes,32x4threads. Source SHA `68be8cd13a8d2fe2bfdeb23ded458db59f9b2c40b0c4ddf9c01d3af1d7bc7d4e`. Four named block57–60 slabs are197184bytes each, extracted by checkpoint names/ranges and whole-checkpoint-pinned constructors.

| byte range | source-proved NN role |
|---|---|
|0..65536|128→512 expansion|
|65536..81920|four128→32 groups, each4K32 steps, nonidentity pi basis|
|81920..98304|128→128 FFN mix|
|98320..98576|128 half early-residual gamma values|
|98592..147744|128→384 raw QKV|
|147744..180512|four64x64 half QK seed matrices|
|180512..180528|four F32 Q scales|
|180528..196912|128→128 final mix|
|196912..197168|128 half final early-seed gamma values|

The16-byte gaps before/after FFN gamma and16-byte tail are not invented as weights. The source worker's upsample ledger was NOT used as ordinary evidence; see ERRATA.md. Source arithmetic is retained: half/K32 checkpoints, cubic scalar sequence, exact norm tree, Q-only scale placement, packed32 score map, half normalization→FP8 before PV, and early FFN/final residual seeds.

## Static host, conditional—not live

61 current-byte witnesses prove the factory/table→builder→descriptor-copy→runtime→actual ordinary ABI chain. Blocks57–60 expected origins are **(0,-4),(0,0),(-4,-4),(-4,0)**. Positive input H/W are rounded to8 in this host branch; the admitted16x16 case is unchanged. Actual aggregate+40 is X from runtime+7c, +44 is Y from+78. Plain FP8 selector and32x4 initialization are witnessed separately.

This does not assert a fresh live instance or plain-vs-wait/tilesync auxiliary route. Primary default inputs remain distinct from aux collector fields. Shifted graph labels do not exclude this parameterized ordinary entry. Block61 is independently OUTVIEW and remains pending.

## Frozen predictions and original chained execution

First four NN predictions/code were frozen before the new original runs. Original57 consumes the actual previously-proved original56 canonical-C128 output; each later original block consumes its preceding ORIGINAL output, not a replacement NN prediction.

| block | grid CTAs | MMA | output SHA |
|---|---:|---:|---|
|57|6|16896|e3bd59cb8c21be663608a36777e8dac009651e607ab892251a21f91658a1a1f5|
|58|4|11264|2f9ab02a9bfd3c64d6a69e0382c896ea467200b74e9b3d29da09d589067a1217|
|59|9|25344|203eb856e690d365b6f96615db17b5ca93df16b2efba01bbbab7cf08247eac78|
|60|6|16896|e4f0e5fa39f40bea1d90d3c3547504db10dfad0a61fdee7e0e88a2948c0b8c23|

**25CTAs,70400MMA,100warp returns,250original barriers/shared snapshots**, all boundaries and all32768final bytes per block match. Every whole64-token window executes, including source-zero corners. Caller input allocations were not padded.

## All25CTAs: every original operand, scalar and store

Each CTA has source-zero ingress, FFN, raw QKV, normalization and both-phase tail proof—not only representative windows:

-204800ingress bytes total:131072actual input bytes+73728original zero bytes, tracked through original F32zero→half→FP8→shared stores. Unknown provenance is not treated as zero.
-38400FFN MMA,5,120,000scalar-result halves and all group/FFN source-neuron/FP8/store provenance.
-19200raw MMA and614400raw projected halves.
-102400RSQRT argument/result/half triples; Q/K/V each204800prequant halves; V204800transpose halves; real deferred-Q and retained-K/V operand identities.
-3200QK+3200PV+6400final MMA, all packed/reduction/probability checks,12800actual RCP calls, and every original early seed/unrolled K32 carry/store.

Two-phase scratch ownership remains unchanged: first PV half uses shared0..4095, then second PV half reuses it; FFN4096..8191 persists for second-phase residual. All original barriers remain; CPU ret/submission order does not prove native happens-before/counter visibility.

The first observer batch hit Main's480-second tool budget after105 complete stage reports; no numerical failure occurred. A separate hash-checked resume ran only the20missing reports. First script/log/progress retained, ALL_PROOFS.json closes all125stage reports. The failed opcode-alignment diagnostic is preserved and never used as equivalence evidence. First NN code remains unchanged.

## Public NN, composition, heldout

`model.Standard4hReference.from_checkpoint(path,block=57)` exposes canonical uint8E4M3[16,16,128],9immutable logical weight views, explicit/default-static origins and immutable window/output hooks. `Standard4hStack` composes57–60. `chain.Decoder48to60` connects the prior NN48–56 output without a physical-layout substitution.

All13NN block outputs match their original CPU evidence, and first chain forward after construction rejects file/process/dlopen/socket I/O. Prior original48–56 evidence was reused, NOT newly executed in that check. Local helper imports still prevent a standalone-distribution claim.

A separate block59 double-shift heldout input was frozen before9complete originalCTAs/25344MMA/all90boundaries/full-output comparison. Heldout SHA **`61c77ca3f249f0e62f1fef15176194a26a9d0a9b66c789c478c2cfa081175000`**. It is non-live and not a block58-produced activation; this adds grid/boundary evidence, not another all-MMA observer.

Eight tests PASS. Full NR, native equivalence, standalone packaging, complete encoder/history/counter/workspace/ViT-newblock evidence and original4h226/8192native mismatch remain open. Next: own4h OUTVIEW61 and its62upsample consumer; do not apply ordinary output handling to61.
