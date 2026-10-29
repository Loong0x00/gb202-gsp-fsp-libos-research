# Own2h OUTVIEW65 and bounded NN48–65

Accepted bounded component, not fullNR/native/standalone. CPU/static only; four upper feature inputs remain non-live. No game, GPU, network or deployment changes.

## Source and weights

Exact5301op/88ABI `cc_tinlayout_fused_swin_2h_64_2_outview_fp8`, sourceSHA e55d074320ab9601d2ff498fc65eea306f2771c69790e22304ffda6171a3ad88. Fixed4096shared,32x2threads; all304static MMA sites `f16.e4m3.e4m3.f16`. Named61760B block65 slabSHA6f842cd03f9ce89da64e4b424bb9a2173488c28214fc542246586145fcb2e613. Source/actual B and scalar origins validate its own expand/group/mix/earlygamma/QKV/bias/Qscale/final/gamma fields at0/16384/24576/28688/28832/41120/57504/57520/61616, with gaps/tail not promoted to tensors.

4559 common instructions match ordinary2h with exact operand/register/predicate/constant substitutions AND mapped CFG targets. Ingress and OUTVIEW output are independently observed, not included by a fuzzy opcode match. A discovery opcode alignment alone was not used as proof. The already implemented exact `st.global.v2.b16` form was enabled in the isolated parser whitelist before parsing; original PTX unchanged.

Own source retains register-private FFN, warp32-row ownership, FP8→half→FP8 ingress, two hidden-group passes (r4586 atPC614), original early seeded and carried mix, and six barriers1581/2747/3700/4045/4969/5299. Shared epochs1/2FFN;3/4first2048PV0..31+last2048FFN32..63;5/6first2048PV32..63+last2048retainedFFN. No UP-style shared ingress/group was invented.

## Final-neuron output proof

4096static final-MMA C-slot→FP8 equations, followed by actual all-default-CTA final operands/neuron labels and byte addresses, establish physical channelk=canonical-C pi(k):

`offset=16*((k//16*OH+y)*OW+x)+k%16`.

This is channel16-planar A basis, NOT identity reshape. First-half terminalr2935..2950→rs1..16 and second-halfr4067..4082→rs17..32 have distinct source address paths. Second half addsY+4 atsource12941/PC5042; actual tagged query coordinates and stores verify that offset. Worker report's first-half equation cannot be directly applied to its second-half register example; original report and MAIN_RECEIPT_AND_PHASE_CAUTION.md retained.

Signed80/84 select positive override, otherwise32/36 H/W fallback. All full windows execute including ghost coordinates; each actual store is individually bounded. A separate original CTA(0,4) executes(-1,INT32_MIN), observes32x32 selected and matches default writes. This is one negative-selector CTA, not a full negative-extent grid. OH37x32 is refused because coordinates are unproduced.

## First predictions and original CPU grids

All four complete NN predictions were frozen before original execution, using actual original64 C64 bytes. First NN code and outputs remain unchanged.

| case | origin / output | CTA / MMA | SHA |
|---|---|---|---|
|default|(0,-4),32x32|20/16640|217b0f575076a144d7d5caf41739b5fdbdf1d54c31a7cd212d0e75d088d24602|
|zero|(0,0),32x32|16/13312|08a3d550d7e3868537bbda9f55fb46c928ec4ce2b57f0423d6d0c50ef6c34508|
|crop|(0,-4),29x27|20/16640|d67c53a6124cc6a5d410728b22efde281a1a3ded4e3514fb4e97c8eddcf67e43|
|expanded|(0,-4),36x32|20/16640|0495d683a0572047553800931e72aadb3e256a146604e11bb4a23558167e8784|

76CTA/63232MMA/152warpRet/456shared snapshots/full output bytes match. Expanded rows32–35 contain8192bytes, **7940nonzero magnitudes**; crop-and-zero-pad is not equivalent.

Every default20CTA/every16640MMA is additionally checked for actual ingress/zero/roundtrip provenance, FFN scalar/carries, rawQKV/normalization/RSQRT, normalized probabilities beforePV, both query-half scratch/residual epochs, final operands and every physical byte store. Extra crop/expanded last-row8CTA tails add1536 observed MMA. ALL_PROOFS.json records actual cy=4. The initial console progress print retained a stale literal2; FIRST_CHECK_ALL.py.txt and FIRST_ALL_OBSERVERS.log preserve it. Only that print was corrected; actual configure calls, report filenames, CTA fields and calculations already used4. No NN or observer arithmetic/metadata needed repair.

## Host, API, chain and heldout

20new current-byte selector/default-extra-field checks +100prior witnesses rechecked (not called unique). Current conditional `_outview`/FP8 selector targets b8b38. NonDS aggregate80/84 are initializedzero and DS override is skipped. Current-static expected65 origin(0,-4), primary input(64,0), not a fresh live mutable instance or aux/native visibility proof.

`model.Outview2hReference`:9immutable logical weights, canonicalC uint8[32,32,64] input, selected logicalA and channel16-planar outputs, immutable probes. `chain.Decoder48to65`:all18NN boundaries match prior original evidence with first forward denying file/process/dlopen/socket I/O. Prior original48–64 NOT freshly rerun. Local helper imports and four non-live upper inputs remain.

Heldout non-live input: firstNN freeze then20originalCTA/16640MMA/all120boundaries/full output match SHA4073f4e28a650823f611aa315f90ae1c959ca19f9fe6c2253f38e58696ef4364. This is not actual64 activation or a second all-MMA observer campaign. Nine tests PASS.

FullNR, native whole-kernel equivalence, independent packaging, upstream encoder/skip producers, pre/post/history/workspace/counters/ViT-new32–38 and original4h226/8192 mismatch remain open. Work continues immediately with own96ABI1h upsample66; its source report must not be accepted as numerical evidence or reuse65 synchronization.
