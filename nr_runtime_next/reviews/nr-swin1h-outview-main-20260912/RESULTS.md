# Own1h OUTVIEW69 and bounded NN48–69

Accepted bounded component/22-block NN chain, not fullNR/native/standalone. CPU/static only. Five upper feature inputs remain non-live; no game/deployment/GPU/network changes.

## Own source and extents

Exact5351op96ABI `cc_tinlayout_fused_swin_1h_32_1_outview_fp8`, sourceSHA4b0addbf11c906197dc2cdca88bf35724a7f3bb5362cdc714f9e04dff5da511f.256F16e4m3MMA, no shared/barriers/backedge. Named20672B slabSHA315d9c45eb6aff39d14922ee37cfae2ceba0fc477c0c6639a0838e4136e421a7; own ordinary1h two-layer FFN and all scalar/matrix fields are verified through actual operands, not serializedF16 axes.

OUTVIEW69 uses **+72/+76**, not2h+80/+84, for signed positive output-extent overrides; otherwise falls back to24/28 H/W. FirstNN retains full source windows and every input zero/decoder/rawFP8 direct-EXP fork, early FFN seed, unquantized FFN final seed, scalar tree, probability quantization and private PV/final arithmetic.

## Address-y is not logical-y

The actual final-MMA neuron→FP8→each4B store proves physical channelk=canonicalC pi(k), offset

`16*((k//16*OH+logical_y)*OW+logical_x)+k%16`.

The channel-plane OH increment is AFTER the logical guard. Example:PC4199 compares logicalr23 withOH;4205 may skip;only4209 computesr23+OH for the address;4214 storesrs5/rs6. It does NOT require y+OH<OH. Second query half startsY+4 (PC5081), separately proved by actualneuron tags and stores. Worker report's address/guard shorthand conflated these coordinate meanings; original report and MAIN_PLANE_GUARD_CAUTION.md retained.

2048static C-slot/FP8 equations and ALL72defaultCTA actual final operands/code/address checks establish the map.4653common core instructions match exact operands/registers/predicates/constants/CFG; ingress and writer are separately observed. Two initial scope attempts were preserved: one conflated slab-versus-output cvta, the other included writer ctaid-versus-laneid and tile+1-versus-logicalY+4 setup. Those genuinely different statements were excluded from common-core scope, not modified in PTX/NN. FIRST_ALPHA_SCOPE.py.txt/SECOND_ALPHA_SCOPE.py.txt and failure logs remain. First complete NN predictions were made afterward and never changed.

## Four frozen NN predictions and complete original grids

All first predictions precede original execution, consuming actual original68 C32 bytes.

| case | origin/output | CTA/MMA | output SHA |
|---|---|---|---|
|default|(0,-4),64x64|72/18432|fb533f01ca87cad96ed258872033b957f023c2e0b6c24de528794d9636e8c871|
|zero|(0,0),64x64|64/16384|c4d32dc212e3338cf44da0b1e81cffbd81bd5b8f7bd01ed42b06fbac1cc5eca4|
|crop|(0,-4),61x59|72/18432|a7d20e333527b312ad133b958cdbf61f359c2aaade1d9ca3796154cfd6df01c4|
|expanded|(0,-4),68x64|72/18432|55b2a996c03a68c18da5c7da2241316f9cc578921a11eadcde016cf3ba7417f8|

All280CTA/71680MMA/280warpRet/full output bytes match. No fake shared snapshots. Expanded rows64..67 contain8192bytes, **7731nonzero magnitudes**; crop-and-zero-pad is not equivalent. Requested69x64 is refused as unproduced.

Every default72CTA/every18432MMA has independent A/B/C/D/sourceweight/bias/Kcarry, actualP0 copied/sourcezero/decodedseed/directFP8EXP, FFN scalar/neuron/FP8, normalization/transpose/RSQRT, attention packed/reduction/RCP/probability/privatePV/earlyseed/final-store proofs. Additional crop/expanded last-row16CTA tail probes check1280MMA. Overlapping checker replays are not counted as new uniqueMMA.

## Host, API, heldout

17new current-byte host witnesses+124prior rechecked. Conditional_outview/_fp8 selector and factory69 static(0,-4) confirmed. Normal nonDS aggregatebase rbp-90 initializes72/76 at rbp-48 tozero; DS overwrite is skipped. None of this is a live mutable-instance/auxvisibility/fullargumentcapture claim.

A separate original CTA(0,8) executes72/76=(-1,INT32_MIN), with deliberately different UNUSED80/84=(1,1); actual selected64x64 and default output subset match. This is one negative-selector CTA, not a full negative grid.

`model.Outview1hReference`:8immutable logical weights, canonicalC uint8[64,64,32] input, selected logicalA/16channel-planar output and immutable probes. `chain.Decoder48to69`:all22NN boundaries match original evidence; first forward after construction denies file/process/dlopen/socket I/O. Prior original48–68 was reused, NOT freshly run; five non-live upper inputs/local helper imports remain.

Heldout independent non-live input: firstNN then72originalCTA/18432MMA/full output matches **4dd70a4c39d5de52dc7c0b37296247ba24582c80d62352b0f144d70739d2c3ae**. Grid/output evidence, not a second all-MMA/scalar campaign. Nine tests PASS.

FullNR/native/standalone, upstream encoder/skip producers, pre/post/history/workspace/counters/ViT-new32–38 and original4h226/8192 mismatch remain open. Continuing with exact6805op184ABI post70; its F16 head, optional TEX/history/surface and live-resource/native numerical boundaries must remain explicit.
