# Main block48 Swin8h upsample: literal whole entry + NN prefix

## Accepted, precisely bounded

- Exact module03 `cc_tinlayout_fused_swin_8h_256_8_upsample_fp8`:7733 parsed instructions,88-byte aggregate,16384 static shared bytes. Original source SHA1d42d3e6fcbe04bed15a1d494c9bb697c5fa4045e05b0d5380dbf24af2f959b6 unchanged.
- Named checkpoint range `block48.layer0.layer`,820784 bytes, SHA7e832b24266b5565b4660a32a4789ce3b15d5835e01df4872e0cee52f82dfcb7. Whole checkpoint identity verified before extraction; F16 serialization is not interpreted as an FP16 matrix.
- Main34 current-byte host witnesses: ctor68630/vtableb99a8, forward69c70, init6a300. Host creates CTA32x8x1. Upsample branch binds PTX0=I0,8=O0,16=slab,24=I1;32/36=effectiveH/W;40/44=zero. Positive this+180/184 override wins, otherwise supplied H/W. Grid ceil(W/8),ceil(H/8),1. Live values/override setter remain unproved.
- Same host DS branch binds PTX8=hostO1 ordinary;PTX72=hostO0 downsampled. Thus restored outer graph block48 inputs[(47,export0),(22,export1)] select the block22 **ordinary**256-channel skip, not its downsampled512-channel result. Producer47 physical output→P0 compatibility is still not promoted merely from this graph edge.

## Original instruction CPU execution

`literal_reference.py` runs the original full entry with original loops, all eight warps, real slab, independent forward-MMA and pinned measured finite-half-domain RCP/RSQRT LUTs. Shared byte production/epochs, full-lane barriers, missing state, bounds, alias and duplicate writes are checked. No identity MMA or added tokens; no GPU/PE/Wine execution.

Explicit deterministic NON-LIVE8x8-effective fixture:
- P0 channel16-planar4x4x512:8192 bytes; P24 tile-packed8x8x256:16384 bytes.
-10752 original MMAs (512 prefix +10240 core);8192RSQRT/512RCP calls;8barriers/256threads;all8warps ret;all16384output bytes produced.
- All8192input/16384skip bytes read;820768 slab bytes read. Last16 slab bytes are present but not read in this execution, not deleted.
- Output SHA3da96cddc0606a05fdc173bc333d6adeda7f928f66094aa75cb82418ed18d753.

New8x16-effective heldout:two full original CTAs,16ret warps,21504MMA,32768 produced output bytes;SHAb79f5fa9490b7565b3129b089e553743cd7ea8cbc2c8d2e30730c141c6a5709b. Both first prefix predictions were frozen before literal execution and matched its shared boundary; no new all-MMA observer claim for this heldout.

## NN-facing prefix restored

`prefix_tensor.forward(source,skip,slab,hooks=...)`, bounded8x8 case, contains tensor operations rather than a VM forward. Source-backed equations:

1. Decode P0 using `16*((k//16*Hp+y)*Wp+x)+k%16`.
2.512→256 projection, matrix at slab360448 with source-backed B(k,n,256) packing; zero C; sixteen ordered K32 steps with RN-half after each. No activation here.
3. Retain this4x4x256 HALF output; nearest2x into8x8x256 without prior FP8 quantization.
4. Decode packed full-resolution P24, half multiply by256 learned half coefficients at492032, then late half add to the projected nearest value.
5. FP8 RN/satfinite, actual packed shared destination. No named-activation substitution or early residual seed.

First tensor implementation and prediction unchanged. Prefix shared16384 SHA b5ab520b15967d2bf6da7e9aeed76cd899834d78e89cb156357fc01f6300f63d.

`check_prefix.py` executes the full original program and independently verifies all512 prefix MMA A/B raw bytes + actual source origins + C/D,16384 skip-multiply halves with original skip/gamma byte origins,16384 nearest/late-add halves with projected-coordinate provenance,16384 prequant halves and the full shared boundary. Nonidentity arithmetic-register→quantize order comes from the actual select chains, not register adjacency. Wrong-nearest is rejected at the original add's provenance, not only by comparing output bytes.

Prematurely quantizing the low projection changes16191/16384prequant halves and3972/16384prefix FP8 bytes on the fixed fixture. `EARLY_QUANTIZATION_NEGATIVE.json`.

## Preserved failures / corrections

- Worker report retained in sibling source directory. Its impossible33000+ line citations, swapped activation positive addends,0xbd660000 typo (actual0xbd650000), reversed clamp order, negative-floor description, and incomplete initial weight-base description are corrected in `MAIN_REVIEW.md`. Its compact activation formula was not implemented.
- Initial VM parse refused `cvt.s16.s8`; `FIRST_PARSE_FAILURE.log`. Private `vm.py` extends only cvt.s16.s8,cvt.s32.s16,shr.s16, with typed operands and proper signed semantics. Original PTX and sibling VM unchanged; baseline copy retained. Exhaustive65536-input tests exercise both conversions and the actual shr.s16 by2; extra shift-count boundaries checked.
- First observer assumed arithmetic register sequence matched quantize sequence; skip origin was4 where it incorrectly expected2. `FIRST_PREFIX_CHECK.log` and `CHECKER_BEFORE_STORE_LINEAGE_FIX.py.txt` retained. Actual three-select chains prove per-four permutation[0,2,1,3]. Only checker metadata changed; first NN tensor, original VM arithmetic and source/weights unchanged. Full grid rechecked.
- Initial hook TEST mistakenly passed one callback; existing API requires a mapping{name:callback}. Failed test/log retained as BEFORE_HOOK_TEST_FIX*. Model API unchanged. Corrected full six-test suite PASS (`TESTS_AFTER_HOOK_FIX.log`).

## Not promoted

This is **a whole-entry CPU executor plus a proved NN prefix**, not a whole Swin NN lift, standalone distribution or complete NR model. Remaining10240-MMA Swin core still uses the literal executor here. Upper source is a labeled fixture, not recovered block47 live activation. Geometry8x8/8x16 evidence does not exhaust all allowed CPU dimensions/OOB branches. Native rounding/fusion/MUFU/synchronization/cross-frame equivalence remain separate; existing4h226/8192 gap unchanged. Local helper imports remain. Game deployments untouched.
