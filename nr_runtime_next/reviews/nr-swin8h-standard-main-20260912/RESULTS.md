# Ordinary Swin8h NN recovery and bounded block48→49 connection

## What is accepted

Exact `cc_tinlayout_fused_swin_8h_256_8_fp8`,5300 instructions/88ABI/16384shared,8warps. No original PTX/VM arithmetic changes. NN first variants reuse only the already proved tensor math with source-derived field-specific bases:
- expand0..262144; grouped262144..294912; mix294912..360448;
- FFN gamma360464..360976 (16-byte gaps before and after);
- raw QKV360992..557600; QK seed557600..623136;
- Q scale623136..623168; final projection623168..688704; final gamma688704..689216.
The shifted/ordinary slabs are689232bytes; header gaps and final16bytes are not invented scalar tensors. A single uniform up→standard offset translation is invalid. Original block16/49 named slabs are separately extracted/pinned; serializedF16 does not define the logical matrices.

## Ingress, shifted windows and outputs

Source P0 reads canonical-C4x4 tiles into the four4096B shared planes. Under admitted H/W multiples8>=8 and origins0/-4, invalid tiles are synthesized by ORIGINAL zero→half→FP8 instructions. NN ingress implements those internal windows, not extra caller features. Source output predicates scatter only valid4x4 tiles.

All four first NN predictions were frozen before original runs, and tensor implementations stayed unchanged:

| Slab / origin(x=y) | Full original grid | MMA | Full16384B outputSHA |
|---|---:|---:|---|
|block49 /0|1CTA|10240|548f7c568584f5cff64ad8eea45e11816950c5127357bfd1896605a5278f7f29|
|block49 /-4|4CTA|40960|0f2c6527954bb6b3d8b740ed86b49ba1500b7bb55f02eb3118072074c5acc512|
|block16 /0|1CTA|10240|24654f469e078c39ff395e4c4731ecbf0c2750937709336a181b76924f3d4e5d|
|block16 /-4|4CTA|40960|2159caff11fc4893c8e61ba9b9fc24f2978f66fc02ab339c8bf9934402ba644b|

All10CTAs/80warps return,102400originalMMA total; all ingress,group,FFN,PV shared boundaries and final valid output bytes matched. This uses block48's proved output whose upper inputs remain non-live fixtures.

## Full operand/intermediate proof

Block49 zero-origin CTA and shifted first/last CTAs(0,0)/(1,1) each received ALL core stage observers:
-4096expand+512group+1024FFN-mix MMA origins/raw/C/D;
-3072raw projection MMA origins/raw/C/D and49152raw register halves;
-entire half norm tree,8192RSQRT triples,Q-only scale,Vtranspose,allQK/PV operand-neuron formulas;
-256QK+256PV+1024finalMMA,actualseed bytes/initialC,packed32 map,allhalfdenominator/RCP/probability order,shared versions and stores.

For each shifted observed CTA,16384 shared ingress bytes have original provenance:4096copied bytes+12288original zero bytes. All64-token arithmetic still executes; only4096global output bytes are valid perCTA. No identity MMA, fabricated caller padding or omitted padding arithmetic.

Observers were ported using archived source instruction/operand anchors, not by altering executed code. `CORE_ALIGNMENT_DIAGNOSTIC.json` shows candidate opcode correspondence and additional standard zero/address setup; this alignment is NOT itself tensor proof. Every accepted event reads original standard registers,addresses,values. `OBSERVER_PORT.json` records actual PC/register anchors; ambiguous raw loop-counter mapping was resolved by its actual old-counter/exit instructions. Four tensor files remain at first hashes in NN_VARIANT_DERIVATION.json. Initial observer report keys said “full output” even when future calls would be sparse; before shifted checks these metadata keys were corrected to CTA-written scope, with first files preserved. No numerical correction was needed.

## Host shift / primary connection

`../nr-swin8h-shift-host-static-20260912/HOST_SHIFT_PROOF.json`:45current-byte witnesses plus the complete7pair PE table and explicitly historical source-retyped ordering. Builder desc+70/+74 copy to runtime+78/+7c; actual aggregate+40X derives runtime+7c and+44Y derives+78. Table first/second are X/Y amounts. Expected block49 first(1,1)→(-4,-4); H=W=8→2x2CTA. Worker reversed X/Y on asymmetric pairs and had address typos; separate Main erratum retained.

Graph49 primary input is48export0, and actual packed-source/store provenance closes its format connection. `check_chain.py` runs only NN block48→49, using the CURRENT-STATIC expected block49 shift, and matches full original CPU40960-MMA block49 output. First NN chain forward passes an audit rejecting file/process/dlopen/socket I/O after construction;9immutable named standard weight views and canonical[H,W,256] interface are provided by `model.Standard8hReference`. Block16 requires explicit origin; its live/static individual shift was not proved here.

## Tests and limits

7testsPASS: first unchanged models,allfourfrozenpredictions,shiftedactualtail/ingress,identitybasisnegativeevenzero-rows,late-residualnegative,missingrequiredbyte/bounds,publicdefault/hooks/weights. Scalar/MMA/normalization semantics are not replaced by a named softmax or FP32 reduction.

NOT complete NR, native equivalence, live shift capture, general geometry or standalone packaging. H4 special ingress replication, other variants(outview/wait/DS),remainingblocks/livehistory/epochs and4h226/8192native mismatch remain separate. No GPU/PE/Wine execution or installed/game/network changes. Tiny CPU component timings are not game/4K/native performance claims.
