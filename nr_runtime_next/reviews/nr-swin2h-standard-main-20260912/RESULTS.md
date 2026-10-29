# Ordinary2h blocks63–64: register-private FFN and bounded NN48–64

**Accepted bounded components, not complete NR/native/standalone.** CPU/static only. All upstream feature inputs remain explicitly non-live; current PE/factory configuration is not a live-instance guarantee. No game/deployment/network/GPU changes.

## Identity and ordinary source ranges

Exact `cc_tinlayout_fused_swin_2h_64_2_fp8`:4845ops/88ABI/fixed4096shared/32x2threads. Source SHA `056455261062601c5c690fe16089c37def7ad3da9e1b4a35cdbc0afcd4e49170`. Original named61760-byte slabs:

-63: `20b7f76bc07dc19e91b78ff3d27a465ab26ae5c86f634382827d27c067b9e4d0`;
-64: `f49359a7472893b847912c5f81a08c36f82d5a37aa3a77fcf792349dc6f1f321`.

Whole checkpoint is pinned by public construction. Actual operands prove expansion0..16384, groups16384..24576, mix24576..28672, early gamma28688..28816, rawQKV28832..41120, bias41120..57504, Qscale57504..57512, final57520..61616, finalgamma61616..61744. The16/16/8-byte gaps and16-byte tail are not invented as tensors. MMA is exactly `f16.e4m3.e4m3.f16`.

## The FFN is not UP scheduling with removed prefix

Ordinary ingress stays in registers. Warp0/1 owns32 query rows each. P0 raw bytes/sourcezero are decoded to half for retained features and early gamma seeds, then actually reencoded to FP8 for expansion operands. Every finite E4M3 code roundtrips exactly, including signed zero; actual per-neuron conversion/source lineage is also checked. NaN codes are outside admitted NN input domain.

The original `r4268=0,1` loop selects two128-hidden/32-group-output channel groups. Each pass interleaves four32-hidden expansion/activation chunks and four grouped K32 contributions, then quantizes the group and immediately adds that group's K32 mix contribution to the carried early-seeded output. It is NOT the UP prefix K loop, and the FFN warp axis is not the UP hidden-column axis.

First shared checkpoint is complete FFN output. The exact six barriers are PCs1579,2745,3691,3811,4735,4843:

-epochs1/2: complete FFN;
-epochs3/4: first2048bytes PVqueries0..31, last2048 retained FFN32..63;
-epochs5/6: first2048 reused for PV32..63, last2048 still FFN32..63.

All original loop predicates, zero branches, input conversions, half/K32 rounding, packed attention map, probability-before-PV quantization, early seeds and final unrolled carries remain in the CPU oracle. NN full logical tensors do not claim the hardware materializes those tensors simultaneously.

## Frozen predictions, actual chained original grids

First NN code and predictions were frozen before new original execution and remain unchanged. Original63 consumes actual original62 C64 output; original64 consumes original63 output.

| block | static expected origin | CTAs / MMA | output SHA |
|---|---|---|---|
|63|(-4,-4)|25 /20800|1709e752360abf5472eb57d0d35e5e8f9bf17d849de540ba83e148c3f3ce3fc4|
|64|(-4,0)|20 /16640|4a536716d90afc6c353237f698cf4ad7556991b210bb3f585373ded881c2a39c|

All45originalCTAs/37440MMA/90warp returns/270shared snapshots and all65536output bytes per block match. Every warp's actual FFN pass sequence is[0,1].

Every original operand/scalar/neuron/store is independently checked on ALL45CTAs:

-131072real ingress bytes+53248sourcezero bytes; zero labels derive from original zero→half→FP8 instructions, not unknown provenance;
-368640actual input half→FP8 roundtrip codes and4,608,000scalar-result halves;
-20160FFN+8640raw+2880QK+2880PV+2880final MMA=37440;
-552960raw halves,92160RSQRT argument/result/half triples, real deferredQ/retainedK/V,11520RCP calls;
-every grouped pi-basis contribution, pass0→pass1 mix C producer, normalization/scalar/packed/reduction checkpoint, both query-half residual/scratch lifetimes and final stores.

The first FFN observer dropped zero-neuron labels at input reencoding, and the first raw-observer import was malformed. Scripts/logs and observer-only corrections are preserved in ERRATA.md. No prediction/model repair occurred. Both block batches completed with disjoint outputs; no timeout/rewrite of sibling artifacts.

## Host, public NN and composition

38new current-byte checks plus62prior host checks revalidated. Current factory table b2308 and builder/descriptor/runtime field flow give63(-4,-4),64(-4,0),65(0,-4). Block65 is OUTVIEW and excluded. The actual ordinary aggregate uses primary I0 at0, ordinary O0 at8, slab16, positive H/W rounded to8 at32/36, X fromruntime7c at40 and Y from78 at44. Native auxiliary wait/tilesync/counter visibility remains unproved; primary defaults are not aux collector aliases.

`model.Standard2hReference` exposes canonical uint8E4M3[32,32,64],9immutable logical weight views and immutable window/output hooks. `Standard2hStack` joins63→64. `chain.Decoder48to64` joins all17NN blocks; every boundary matches original CPU evidence and first chain forward after construction rejects file/process/dlopen/socket I/O. Prior original48–62 evidence was reused, NOT freshly executed there. Four upper inputs remain non-live. Local helper imports remain a standalone-packaging gap.

A separate block63 double-shift heldout input was frozen before25complete originalCTAs/20800MMA/all150boundaries/full-output comparison. SHA **`c1c51a0cca925e8e500afdc7a8993b6cb55c929cf1a3cb5ba97d6da0ab016062`**. It is not an actual block62 activation; this adds grid/boundary evidence, not another all-MMA observer.

Eight tests PASS. FullNR/native/standalone, complete encoder/pre-post/history/workspace/counter/ViT-newblock proofs and original4h226/8192native mismatch remain open. Next: own OUTVIEW65, then1h upsample66; do not apply ordinary output handling to65.
