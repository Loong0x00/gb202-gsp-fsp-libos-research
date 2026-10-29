# Preblock0: bounded first-counter NN and actual two-output producer

**Accepted CPU/reference component for the tested first-counter-zero, absent T1–T4, normal-output family. Not a complete/native preblock, live image pipeline, fullNR or standalone distribution.** No DLL/PE/Wine/GPU/network execution, deployment or gate changes occurred. Sampler and noise approximation policies remain explicit.

## Own source and typed model

- Canonical entry `cc_tinlayout_fused_pre_block_swin_1h_32_1_ds_fp8`,6459 instructions,264-byte ABI,32x1 warp. Source SHA `7ef1fb2650817e1b45b44104e06fac39d9d26c3a2afcd042f915681167a2bba8`; current module slice740209..994675. Older source matches only after `.visible ` / edge-whitespace normalization.
- Named21696-byte block0 slab SHA `5fe2ab86289f7b21253d00368ce7a95f005ec3c8476abd7db22550b918962a5c`. Nine typed fields,21636 accessed bytes,60 unread gap/tail bytes. F16 safetensors metadata is not the execution dtype of every byte.
- Original64-pixel fill loop,2048 static shared bytes and barriers at canonical PCs471/838 remain in the CPU oracle. Source has14 backward branches including11 in the padding suffix. Padding barrier6028 is not executed in the admitted normal family; it was not deleted.
- Independent high-level preprocessing constructs16 logical half features from explicit raw-F32 sampler responses, exact uint32 noise hashes, source-rounded F32/F16 operations and explicitly NONNATIVE approximate policies. It is not a Replay/Thread/interpreter forward. The internal feature-only candidate uses[x,y,16]; NN explicitly transposes and maps it to canonical4x4-tile rows.
- Own F16 embedding16→32 uses **one K16** per output tile,16 MMAs total. Constant input features are retained. Unquantized embedding feeds gamma9232/FFN seed; its FP8 fork feeds expansion.
- Four interleaved hidden32 expand/cubic/contract steps implement32→128→32 with perK32 RN-half carry. Raw QKV, ordered Q/K half normalization/RSQRT/Q-gain, rawV transpose, seeded QK, packed map, denominator/RCP, normalized probabilityFP8, twoK32 PV and final residual-seeded projection follow source operations.

| Field | Byte interval |
|---|---:|
|FFN expand / contract|0..4096 /4096..8192|
|F16 embedding16→32|8208..9232|
|FFN embedding-residual gamma|9232..9296|
|QKV32→96|9312..12384|
|QK C/bias64×64|12384..20576|
|Q-normalization gain F32|20576..20580|
|Final projection / gamma|20592..21616 /21616..21680|

Public weights are exposed with canonical input/output neuron axes; internal FP8 K-fragment permutations are separately represented, not guessed by dense reshape.

## Two outputs and source precision fork

Current-byte host proof establishes **O[0]→+248→port0→block1 inpview**, **O[1]→+216→port1→historical block70 skip ABI+8**. Port assignment is not inferred from store order. Main independently rechecked399 distinct instruction addresses (worker's400 witness occurrences),32 windows and127 bounded slices against pinned current DLL bytes. No live handle, allocation extent, alias ownership or native publication is implied.

- High +216 is canonical C32 for high pixel H/W. H/4,W/4 are tile counts, not image dimensions. With128x128 it is524288 bytes.
- Normal +248 is channel16-planar A at64x64x32,131072 bytes. Physical channelk corresponds to finalC `pi(k)`.
- The low branch consumes **original unquantized final F16**, not the stored/dequantized FP8 high skip. Its source order is pair+pair→sum→multiply half0.25, each separately rounded, followed by FP8 conversion. The lane-dependent within-pair/row-pair order is retained.
- Normal low extents use trunc(H/2),trunc(W/2). Padding comparisons separately use trunc((H+1)/2), with signed wrap caveats. They are not interchangeable for arbitrary positive odd dimensions.

## First frozen prediction and full original grid

First NN code (ten numerical files) and predictions were frozen before the original CPU program ran. Its first full forward denied file/process/dlopen/socket I/O after policy construction.

| Case | Source/output geometry | CTA / MMA | Skip C32 SHA | Primary planarA SHA |
|---|---|---:|---|---|
|Default, mode1|source128x128, high128x128, low64x64|256 /69632|`a33828b9bece00eaec23f6b401b446dc31bc41dac55c99f04768cc5fcbc8a101`|`56ee903cb43a4dd89ae177ea7b9a783ff30f7e06bfb95080e0c4af56eb2c2c4a`|
|Independent image/controls, mode0|source125x126, high128x128, low64x64; upper mirror exercised|256 /69632|`b82b7be04fe5b30e55cdbea7cecc74403bcf2a68ff9a8990b174106945e90692`|`9f438d762eb201ce5cf313d5128ee631af80823a810cd1633ef68521c8c2d588`|

Each grid runs4096 F16 embedding MMAs plus65536 FP8 MMAs. Default has1536 shared/tensor boundary checks: shared fill, embedding, FFN, rawQKV, both final query halves. Every output byte matches, with genuine sparse original captures assembled under exact coverage/duplicate checks. No original buffer is manufactured from the prediction. Heldout is a second full-output grid, not a second all-scalar campaign.

### ALL256 detailed proof scopes

`ALL_PROOFS.json` joins512 per-CTA reports; repeated oracle runs are not added to the unique69632 MMA count.

1. Every F16/FP8 A/B/C/D, actual embedding shared origins, all coefficient/bias byte origins, K32 carries and unquantized embedding/FFN seed lineage.
2. Every reached ingress integer/control/plain-F32/half/approximate result, param/slab/shared load, raw sampler response and shared fill store. Independent rational RN checks validate the selected CPU policy; native approximation is not inferred.32768 fill stores and16384 source samples produce all524288 feature/shared bytes.
3. Every FFN cubic/clamp/FP8/carry neuron and unquantized embedding seed.
4. Every QKV normalization scalar tree,262144 RSQRT calls, V transpose and packing; attention affine/packed map/reduction,32768 reciprocal calls, prequantization normalization and PV/final seed.
5. Every relevant final-writer move/select/shuffle, FP8 conversion, balanced downsample half operation, source-neuron identity and actual address.131072 low half neurons;655360 FP8 scalar conversions over the high/low output forks.

All ten first numerical NN files are unchanged. Oracle trace callbacks were added only after the first complete grid matched; before-tracing copies are preserved. Original PTX and arithmetic policies were not changed.

## API and integration

`model.Preblock0FirstReference`:9 immutable canonical weight tensors, explicit raw-F32 sampler and nonnative ingress approximation policy, immutable logical probes, primaryA/skipC arrays and packed buffers. Normal-output geometry is conservative: positive multiples8 up to128, exact half low extents, first64-bit counter0 and absent T1–T4. It never clears a supplied genuine temporal/control resource to make it fit.

15 unchanged worker feature-only tests were rerun by Main;10 additional Main tests pass, including first public no-I/O forward, weights/probe immutability, full64 counter, resource/padding rejection, unquantized residuals, Q-scale/probability order, and rejection of downsampling the quantized high skip.

`../nr-pre0-post70-bridge-main-20260912/` separately replaces post70's former skip fixture with the **actual recovered pre0 producer**. First coupled NN/no-I/O then all289 original post70 CTAs match. Its main input remains reused original69; this is a two-branch connection, **not** an assertion that blocks1–47 or the complete image-to-NR path are closed.

## Padding and safety boundary

The worker's independently traced suffix writes **four planar16 planes** using AH/AW, unlike the normal low output's two planes using h/w. Its20 geometry cases and ten suffix-only thread configurations show holes/overlaps and writes outside a *hypothetical* C32 allocation for various padded/cropped/odd/undergridded cases. Actual capacity/lifetime is not proven, so this is not labelled a native OOB bug. No source loop, barrier or stride is repaired, clipped or replaced with a convenient zero fill. The admitted normal family exits before this suffix.

Native sampler/view formats/swizzles/NVX handles, input/noise approximate bits, TC accumulation/subnormal behavior, genuine temporal recurrence/counter epochs, workspace aliasing and visibility remain open. Historical Vulkan sampler modes have static evidence, but the procedural source callback is not a native image/sampler emulator. First-counter gating uses64 bits; the noise seed consumes low32, not a frame-completion counter.

## Parallel-worker review record

Four explicit `openai-codex/gpt-6-astra` /`xhigh` workers used independent read-only DLL copies. Their outputs were not accepted merely by assertion: Main rechecked all9 maps,272 register lists,1024 embedding shared equations, current host bytes and copied DLL identities; independently derived output layouts; reran15 feature tests; then ran the frozen NN versus the full original CPU program and detailed observers.

The earlier worker's factor-four dimension error and wrong barrier line are retained/corrected in `nr-pre1h0-source-20260912/MAIN_RECEIPT_AND_REJECTED_GEOMETRY.md`. Parallel worker1's first failed extractor file was **reconstructed by reversing its correction**, not a contemporaneous byte snapshot; its original failure log remains. Worker2's missing-backedge test-coverage failure and worker4's clipped disassembly-boundary correction also remain. No new Main numerical mismatch was hidden or tolerance adjusted.

Current next stage: independently review completed encoder1h INPVIEW/DS/host reports and restore block1 onward. Block1 worker explicitly left tilesync/slab verification incomplete; block4 padding has its own conditional plane/stride problem; block5 has88-byte ABI, not96. No fullNR/native/standalone claim or fresh GPU authorization follows.
