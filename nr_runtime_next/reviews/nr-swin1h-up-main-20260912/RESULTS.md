# Own1h upsample66 and bounded NN48–66

Accepted bounded component and19-block NN chain; **not fullNR/native/standalone**. CPU/static only, five upper inputs non-live. No game/deployment/network/GPU changes.

## Own source, ABI and fields

Exact `cc_tinlayout_fused_swin_1h_32_1_upsample_fp8`:5875ops/96ABI/maxnreg168; sourceSHA1a32ed9b190ac70166c326610ce97a1c3e1cf58424a7c8b4a0a9097a7901c62a. **No shared declaration, no bar.sync**, one32-lane warp. All260static tensor instructions are `f16.e4m3.e4m3.f16`;264execute because the four prefix sites repeat forK0/32. No dummy shared allocation, invented epochs or identity MMA.

Named22784B slabSHAc4083d8e31bb2820eb1392f6d8b6b7148909ffa129cac7c61780ad1f9c03b916. Actual all-CTA operands and scalar loads establish:

| range | role |
|---|---|
|0..4096|FFN expansion32→128|
|4096..8192|FFN contraction128→32|
|8192..10240|prefix64→32, twoK32|
|10256..10320|FFN early gamma32half|
|10336..10400|highskip gamma32half|
|10400..13472|rawQKV32→96|
|13472..21664|single-head64x64 half bias, two4096B query halves|
|21664..21668|oneF32 learned Q scale|
|21680..22704|final32→32|
|22704..22768|final early gamma32half|

Exactly22724slab bytes are read. The60gap/tail bytes are not tensors. Worker ledger/synchronization/ceil/QK-PV claims were rejected before NN prediction; original report and MAIN_REVIEW_AND_REJECTED_LEDGER.md retained.

ABI0lowA,8outputC,16slab,24highH/W,32X/Y,80highskipC,88highskipH/W override. P24 is NOT skip pointer. Source signbit-add/shift implements signed truncation toward zero. Kernel keeps real low projection/shuffle→unquantized nearest2x→per-highpixel rounded skip multiply/add.

## Essential unquantized branches

LetP be unquantized learned-upsample-plus-skip half. Expansion input is FP8(P), but FFN early seed is RNhalf(P*gamma), NOT decodedFP8(P)*gamma. FFN streams four hidden32 expansion/cubic/FP8/contraction chunks, carrying the seeded contraction result across each K32; no separate group/mix matrices.

LetF be unquantized final FFN half. RawQKV uses FP8(F), but final projection seed is RNhalf(F*gamma), NOT decodedFP8(F)*gamma. All64-CTA scalar/neuron proofs and negative tests validate both branches.

Q/K half normalization, measured-half-domain RSQRT, Q scale order, actual m8n8 V movmatrix transpose, packed score map, ordered half denominator, measured-half-domain RCP, probability FP8 beforePV, PV's two K32 groups, register-private PV→FP8→final projection and physical C32 stores are retained and independently observed. Query halves are M0..31/M32..63, not Q-versus-K banks.

## Frozen prediction and complete original evidence

First ownNN was frozen before original execution. Real predecessor bytes are original65 channel16-planar A64, consumed directly: no C/pi reinterpretation or physical repack. Highskip is a deterministic non-live C32 fixture, not attested block4 activation.

High64x64/low32x32/origin0,0:64originalCTAs/16896MMA/64warpRet/131072outputbytes match **`ea49f2b17bc2440f3eb1bea53e9e24d43504a3a0fa80738f8d793667fb596021`**. There are zero shared snapshots because the source has no shared storage. First NN code/output remain unchanged.

ALL64CTAs everyMMA A/B/C/D, actual weight/bias/low byte origins and K32 C producers:512prefix+4096expand+4096contract+3072raw+2048QK+2048PV+1024final=16896. Actual low union65536, highskip union131072, slabunion22724. Every64CTA additionally proves:

-131072 nearest-shuffle halves, real skip ingress/decode/multiply/add and unquantizedP seed halves each;
-524288 hidden activations, each six scalar half operations with actual clamp/FMA constants, actual FP8 conversions and carried contraction neuron identities;
-65536 RSQRT argument/F32/half triples,131072 V-transpose halves, normalized Q/K/V prequant/code neurons;
-8192 RCP calls,262144 probability normalization halves, actual privatePV/final operands,131072 final-seed and final-store source-neuron checks.

`ALL_MMA_PROOFS.json`, `ALL_PREFIX_FFN_PROOFS.json`, `ALL_NORM_TAIL_PROOFS.json` split independent observer scope; overlapping MMA observations are not summed as unique.

## Host field distinction preserved

82current-byte witnesses: factory66→63400upwrapper→629d0builder→generic descriptor copy; descriptor70/74=-1/-1→runtime78/7c→staticXY0/0. Vtableb8108 forward+8=637b0 (not destructor621b0). Kernel initializer selects own FP8 entry and32x1x1 block.

Actual up aggregate base isrbp-20. P24 is rounded highH/W, P88 is **unrounded positive** highskipH/W. First diagnostic used P88=0/0, selecting64/64 by fallback. That original artifact was NOT rewritten as a host capture. `run_host_fields.py` separately runs all64CTAs/16896MMA with actual current-static P88=64/64, observes positive selection and matches the same frozen prediction. `HOST_SELECTOR_CLOSURE.json` proves raw override/predicate registers have no uses after selector PC488; with identical selected64/64 the data path is the same. This applies to this bounded case, not arbitrary override interchangeability/live mutable state/aux visibility.

## API, heldout and tests

`model.Block66Reference`: logicalA uint8[32,32,64] low + canonicalC uint8[64,64,32] highskip→C output;10immutable logical weights. Hooks expose unquantized P/F query matrices[64,32], using documented tile query order, plus normalized/attention/output tensors. Forward is pureNN, not PTX/DLL wrapping.

`chain.Decoder48to66`:all19NN boundaries match original evidence; first chain forward after construction denies file/process/dlopen/socket I/O. Prior original48–65 was reused, NOT newly run. Five upper fixtures and local helper imports remain standalone/fullmodel gaps.

Heldout independent non-live low/skip pair: complete firstNN freeze, then64originalCTAs with current-static positiveP88 and **every16896MMA** A/B/C/D/source/carry checks, full output match **`38c0f2670ebb1c89dd205fa65f1c2203b9aefcce00b9ad1b0d92395d7ae60e39`**. This is a second all-MMA campaign, not a second full scalar campaign or live activation claim.

Ten tests PASS. First MMA observer dtype error (attempted float64 pack through a finite-half-only helper) and first Capstone SKIPDATA collector error are archived. Only observer/collector code changed; no NN or first prediction repairs.

FullNR/native/standalone, full encoder and skip producers, pre/post/history/workspace/counter/ViT-new32–38 and original4h226/8192 native gap remain open. Continuing immediately to own ordinary1h67/68, then own OUTVIEW69/post70; no new approval needed for this CPU/static review work.
