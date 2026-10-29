# Block62 2h upsample NN and bounded decoder48–62 chain

**Accepted bounded component, not complete NR/native/standalone.** CPU/static only; game deployments unchanged. P0 is the actual prior original block61 A-planar byte stream. P24 is an explicitly non-live block8-skip fixture, not a recovered encoder activation. Four upper feature inputs remain non-live in the composed decoder.

## Own source and types

Exact `cc_tinlayout_fused_swin_2h_64_2_upsample_fp8`,7064ops/88ABI, fixed4096-byte shared declaration,32x2threads. Source SHA `66ba833efed08895583a3506900300f1e5ff7f83fcf462ed358ef20989e7b26d`. Named block62 slab70048bytes SHA `eaaa79ba63a53cbd0c23521593379284af29ab50a718ddf37e06b93b339ccadd`, whole checkpoint verified at construction.

All276 static MMA sites use **F16 accumulators**: `f16.e4m3.e4m3.f16`, not the worker's reported F32 form. Original PTX, loops, barriers, source zeros, shuffles, masks and instruction ordering are unchanged. Source-only worker did not accept the numerical model; Main's independent evidence below does.

| byte range | actual source/operand-proved role |
|---|---|
|0..16384|64→256 expansion|
|16384..24576|two128→32 grouped contractions, each4K32|
|24576..28672|64→64 FFN mix|
|28672..36864|128→64 prefix projection,4K32|
|36864..36992|64 half FFN early-seed gamma values|
|36992..37120|64 half late upsample skip gamma values|
|37120..49408|64→192 raw QKV|
|49408..65792|two64x64 half QK seed matrices|
|65792..65800|two F32 Q scales|
|65808..69904|64→64 final projection|
|69904..70032|64 half final early-seed gamma values|

The8-byte gap65800..65808 and16-byte tail are not invented as tensors. No ratio or uniform4h displacement supplied these axes; actual operands/raw bytes/accumulators verify them.

## First prediction and full original grid

An initial code-generation K-axis replacement error was caught by source preflight **before any NN prediction/original execution**. Its first code and failed assertion are retained. K128 was corrected from the actual4K32 source loop. The first complete NN prediction was then frozen and has remained unchanged through every comparison; see ERRATA.md.

Admitted high32x32/low16x16, static-origin(0,0),4x4grid: all16originalCTAs execute864MMA each,2warp returns and10barriers. **13824MMA,32warp returns,160shared snapshots,65536final bytes** all match the frozen NN.

Output SHA: **`666b09abd260b13420a18ea1cd1955c45a25ccde6ec1db2f1f98acd3b4412287`**.

## All16CTAs, every original MMA and intermediate

-512prefixMMA: actual P0/B byte origins, raw operands, perK32 C/D; complete32768-byte P0 union exactly consumes block61's physical A-basis stream. No extra C/pi reinterpretation.
-Unquantized nearest2x is proved by actual source-neuron/shuffle/add operands before per-high-pixel half skip multiply/add. All65536P24bytes and all late coordinate-select masks are checked. Current admitted origins make the late masks false; they remain in the original program and NN boundary formulation.
-7168FFN MMA,1,638,400scalar-result halves, all actual group/pi/early-gamma/store provenance.
-3072raw MMA and196608raw halves. The mix and raw QKV have TWO UNROLLED K32 groups, not copied4h runtime loops; second-group C producer tags prove the first-group carry.
-32768RSQRT argument/result/half triples; Q/K/V each65536prequant halves, V65536transpose halves, real deferred Q/retained K/V source identities.
-1024QK+1024PV+1024finalMMA, all packed/reduction/probability-before-PV/4096RCP calls/early seeds and two-unrolled-K32 final carries.

Two query-half phases remain: shared first2048bytes hold PV rows0..31, then are reused for PV32..63; last2048FFN bytes persist for the second residual seed. All160mixed shared snapshots and original barriers match. CPU ret/scheduling does not prove native visibility/counter behavior.

## Host, public NN and composition

62 current-byte witnesses establish factory62→2h up-builder→descriptor-copy→runtime→actual aggregate. Factory r9d/fifth argument are both-1, so runtime78/7c select Y/X zero. P0=I0(61,0),P24=I1(8,1),output+8=O0,slab+16; positive runtime180/184 override supplied H/W. Initializer supplies32x2threads. These are conditional current-PE/static-factory facts, not a fresh live instance or auxiliary route guarantee.

`model.Block62Reference.from_checkpoint(path)` exposes11immutable logical weights, logical A-basis low[16,16,128], canonical-C skip/output[32,32,64], uint8E4M3 codes and immutable window/output hooks. Forward is tensor math, not a VM/DLL wrapper. Local sibling/helper imports remain.

`chain.Decoder48to62` connects all15NN blocks without repacking block61's physical stream. Every boundary matches its original CPU evidence; first chain forward after construction passes file/process/dlopen/socket-I/O rejection. Prior original48–61 evidence was reused, NOT freshly executed in that check; block62 original execution used its exact preceding original61 bytes.

A separate non-live low/skip heldout pair was frozen before another16originalCTAs/13824MMA/all160boundaries/full-output comparison. SHA **`ff39185beb3f806686581906b3cbe4179a667392110e9065a5a02943d86b03fd`**. Heldout is not a block61/block8 activation capture and adds grid/boundary, not another all-MMA intermediate observer.

Eight tests PASS. Full encoder/pre-post/history/counter/workspace/ViT-newblock coverage, standalone packaging and original4h226/8192native mismatch remain open. Next: own ordinary2h63–64, then65OUTVIEW and66upsample; none are inferred from this entry's name or dimensions.
