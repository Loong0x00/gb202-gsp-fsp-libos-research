# Own ordinary1h67/68 and bounded NN48–68

Accepted bounded components and21-block NN chain; not fullNR/native/standalone. CPU/static only; five upper inputs remain non-live. No GPU/network/game/deployment changes.

Exact `cc_tinlayout_fused_swin_1h_32_1_fp8`:4902ops/96ABI/256static-and-dynamic F16e4m3MMA, no backedge, no shared/barrier. SourceSHA15ddfc388ff77a4a1ce1bd4bbad79d44df220dda70f731a379eefa1694e0a8cd. Named20672B slabs67SHA48e91279ad6de711d3c277c35b3cf48225310bf6c713e8298c4f5ffb0f0f0f37 and68SHA11ec13bc10546dae5e6be7960c4c5e903deab7d9035773f018c1819ce66d1e51.

Actual fields: FFNexpand0..4096/contract4096..8192, FFNgamma8208..8272, rawQKV8288..11360, halfbias11360..19552 (two4096B query halves), oneF32Qscale19552..19556, final19568..20592, finalgamma20592..20656. The16/16/12/16 gaps/tail are not learned tensors. Bias halves are not raw/later projection matrices.

## Direct raw ingress, separate decoded residual

Actual P0 rawFP8 quartets r4299..r4317 directly feed expansion. Separately decoded P0 half feeds the8208 gamma/early FFN contraction seed. **There is no real-input half→FP8 reencoding in this source**, unlike ordinary2h and the UP prefix case. Only four OOB-zero construction FP8 conversions occur before first expansion; actual invalid P0 cells derive from integerzero→halfzero→FP8zero, not missing-data substitution.

First FFN observer had inherited an UP reencoded-stage assumption and failed with source producer stage4 versus expected6. FIRST_FFN_OBSERVER.py.txt/log retained. Only observer labels changed: rawFP8 ingress stage stays on the direct MMA fork, decoding creates the half-seed fork. First NN code/predictions remain unchanged. The NN's shared helper decodes then repacks its finite-half input; FINITE_INPUT_IDENTITY.json checks all254finite E4M3 codes including signedzero as an exact identity. This is explicitly NOT a source instruction/roundtrip claim. NaN input remains rejected.

FFN32→128→32 streams four hidden32 expansion/cubic/FP8/contraction chunks with exact early seed and perK32 carried rounding. Final projection's seed remains **unquantized FFN half**, while rawQKV gets FP8(FFN). Actual norm half trees/RSQRT/Q-scale order, V movmatrix transpose, packed score mapping/reduction/RCP/probability FP8 beforePV, private two-query-half PV→final and C32 stores are proved without shared epochs.

The correct `/4` example here is7→1,-7→-1. The worker report instead repeated the `/2` example3→1,-3→-1, which is not valid for this source. Main uses actual shift-by2 instructions and admitted origin multiples4. No NN change resulted.

## Frozen chain and every original CTA

First two NN predictions were frozen before new originals. Original67 consumes actual66 host-field output; original68 consumes original67 output.

-67 static(-4,-4),81CTA/20736MMA,131072B SHA **8ed3f705aa848142f5bbcb2a8db94f9644133c74d2098ceb1b110e2e3d3877bf**.
-68 static(-4,0),72CTA/18432MMA,131072B SHA **5ec492f58a90768a78bbfed1947d8ee37bb8eefa388cf10b595fbb9a364324c4**.

All153CTA/39168MMA/153warpRet/full outputs match. No shared snapshots exist in this source. Every153CTA additionally has everyMMA A/B/C/D, actual B/bias byte origins, K32 C producers; all ingress/zero/decoder/earlyseed/FFN scalar and FP8 neuron provenance; every normalization/transpose/attention scalar/private residual/store proof. Real ingress262144bytes+sourcezero51200bytes,156672RSQRT argument/F32/half triples,19584RCP calls. Independent block-qualified CPU batches completed; no timeout or sibling rewrite. Four checker observations overlap and are not added as unique MMA.

## Host, public API, heldout

42new current-byte witnesses+82prior rechecked. Current tableb2328=(1,1),(1,0),(0,1), builder629d0/descriptorcopy/runtime maps67(-4,-4),68(-4,0),69(0,-4). Seventh parameter selects OUTVIEW69, excluded here. Actual ordinary aggregate uses supplied H/W at24, **not the UP rounded-H/W construction**, X/Y at32 fromruntime7c/78;0I0,8ordinaryO0,16slab. This entry never reads40..95. Diagnostica5 padding is not a claim about the complete live argument record. Static origins and primary defaults are not fresh instance or aux/native visibility proof.

`model.Standard1hReference`:canonicalC uint8[64,64,32],8immutable weights and immutable input/unquantized-FFN/attention/output probes. `Standard1hStack` joins67→68. `chain.Decoder48to68` all21NN outputs match prior original evidence; first forward after construction rejects file/process/dlopen/socket I/O. Prior original48–66 was reused, NOT reexecuted. Five upper fixtures/local helper imports remain.

Heldout non-live block67 input: firstNN then81whole originalCTAs/20736MMA/fulloutput matches SHA **eb979186ea9e06e901b11cb8edf77e42885114cf09cb48d484b7a04e3ec97d21**. This is grid/output coverage, not another all-MMA/scalar observer campaign or actual66 activation. Nine tests PASS.

FullNR/native/standalone/encoder/prepost/history/workspace/counter/ViT-new32–38 and original4h226/8192 native mismatch remain open. Main continues immediately with own96ABI OUTVIEW69; its72/76 extents and channel-plane address offset must not be confused with logical-y bounds or the2h80/84 ABI.
