# Own post70: learned NN and bounded optional-null-texture branch

**Accepted only for this explicitly bounded CPU branch**, not complete post70, fullNR, native equivalence, live image inference or standalone distribution. No GPU/network/PE execution/game deployment/gate changes. Historical live arguments had A non-null; this work does not authorize zeroing that resource.

## Identity and source-derived network

- Exact entry `cc_tinlayout_fused_post_block_swin_1h_32_fp8`:6805 instructions,184-byte ABI,32x1 warp, no shared/barriers/backedges. Source SHA `8833e1a55197d3e6e2acc1d2032c6ba22c9712c96a58c2a873733c59506fb91c`.
- Named21808-byte slab SHA `197024afb1f78602dc08cfd5ae87c413385237c5f537dd5dcfeae742be85eca8`; named blend scalar bytes`eb39` =0.73974609375, separately loaded by the original even though history is absent.
- P0 is A32[64,64] from **actual original69**; P1 is non-live C32[128,128]. Source expressions establish nearest2x and per-channel main/skip half scales, **no learned prefix MMA**. Physical A channel for canonicalC is inverse-pi; it undoes the proved69 writer basis without inventing a dense layout.
- P=RNhalf(RNhalf(nearest(main)*main_gamma)+RNhalf(skip*skip_gamma)). FP8(P) feeds EXP; unquantizedP feeds the FFN seed. Four interleaved hidden32 chunks implement32→128→32 with per-K32 RN-half contraction.
- UnquantizedFFN feeds final seed; quantizedFFN feeds QKV. Q/K ordered half reductions/RSQRT/scale, V transpose, seeded QK, packed map, ordered denominator/RCP, normalization **before** probabilityFP8, two-K32 PV, final projection are retained.
- Final unquantizedC directly feeds two **F16 K16** head steps, with no extra FP8 conversion or bias.32x16 is computed; only columns0..3 are selected as RGB/logit. Alpha is separately1 in this decode branch, not the logit. Other384 physical half coefficients are not made live merely because they are loaded/computed.

| Field | Byte interval |
|---|---:|
|FFN expand / contract|0..4096 /4096..8192|
|FFN seed gamma|8208..8272|
|main / skip gamma|8272..8336 /8336..8400|
|QKV|8400..11472|
|QK C/bias|11472..19664|
|Q scale F32|19664..19668|
|final projection / gamma|19680..20704 /20704..20768|
|F16 head|20784..21808|

All21764 used slab bytes have actual-source witnesses;44 gap bytes are unused. Layout/roles follow typed operands, not serialized-F16 metadata.

## Frozen predictions, full original grids and detailed evidence

| Input case | Origin | CTAs | FP8 / F16 MMA | Logical RGBA-F32 SHA |
|---|---|---:|---:|---|
|actual69 + non-live skip0|(-4,-4)|289|73984 /4624|`e3578c062275284c85de8795c67eac6fa669ed963a87f42b5df2597203d59f67`|
|independent non-live pair|(0,0)|256|65536 /4096|`1a0ca5b45bd7daa90c1e4d83d53df753dc25079af1ddceda20920fd6d663322b`|

Both first predictions match every actual CPU store,16384 pixels/262144 bytes each.545 distinct input/CTA executions and148240 MMA across the two grids. Checker replays, failed support attempts and timeout work are **not** added to those unique counts. ORIGINAL files come from actual captured stores, not prediction-filled buffers. All nine first numerical NN files remain unchanged.

Default **ALL289 / every78608 MMA** additionally has four separately sealed proof scopes (`ALL_PROOFS.json`):

1. Every FP8/F16 A/B/C/D value, actual B and bias byte origins, K32/K16 carries, unquantized FFN final seed, and finalC→headA neuron identities.
2. Actual nearest/main and skip byte origins or original sourcezero; each main gamma, skip gamma, P add and FFN seed half; every FFN cubic stage/FP8/carry neuron. Each ingress has524288 real neuron uses and67584 original-zero uses. Unique underlying main/skip byte spans are131072/524288, not silently padded substitutes.
3. Every QKV normalization scalar tree, measured-domain RSQRT conversion/result, Q-scale ordering, V transpose and normalized Q/K/V operands; every attention affine/packed-map/reduction/RCP/probability/PV/early-seed scalar and operand.
4. All73984 selected head halves including ghost queries;65536 valid half→F32 promotions;196608 RGB scalar operations; every neuron→pixel coordinate, both query halves, surface-handle identity and four-word payload. Hardware formatted surface conversion is outside scope.

2048 static ingress equations,10240 additional corner/interior expressions,4096 finalC→F16headA slot equations supplement actual observers. Full windows and source bounds remain unchanged.

## Host, public API and composition

`HOST_PROOF.json`:210 current-byte instruction witnesses. Base mode0 selects184 bytes (other modes312 bytes); conditional `_fp8` selector registers32x1x1. Input-vector0/1 map to ABI0/8, output0 to16, slab24. FactoryR8/R9=1→descriptor70/74→runtime78/7c→origin(-4,-4), with XY placement independently followed. H/W32/36 are supplied or positive runtime overrides, not newly rounded by forward. RGB48=1/32; `_rgb` name controls52. Optional A/B/C derive from inputs2/3/4, not from the two neural buffers. Blend pointer104 is separate; sourceW/H172/176 have positive-or-fallback selection.

Two archived184-byte argument files are read without dereferencing/chmod/execution. Both had **A non-null**; B/C were absent then present. Thus the new null-A case remains diagnostic, not a claim about genuine live inputs or resource validity.

`model.NullTexturePost70Reference`:12 immutable named logical weight tensors, mainA uint8[64,64,32], skipC uint8[128,128,32], immutable logical probes, learned RGB/logit half output and logical RGBA-F32. Non-None texture resources explicitly raise rather than disappearing. Pure array arithmetic, not a VM/DLL forward wrapper.

`chain.Decoder48to70NullTexture`:23 NN boundaries match previously verified original results; its first forward after construction passed file/process/dlopen/socket I/O denial. Prior48–69 originals were **not** reexecuted. Six upper feature inputs remain non-live. API no-I/O retry and12 tests pass, including source high-word resource rejection, unquantized forks, probability/normalization ordering, twoK16-vs-collapsedK32, head requantization and second-query coordinate counterfactuals. Heldout is a second full-output grid, not a second all-scalar campaign.

## Explicit numerical and resource limitations

- F16 head policy is exact integer dot plus RN-half after eachK16; native Tensor Core accumulation/FTZ/signed-zero behavior is not established by CPU agreement.
-32768 original coordinate divisions execute per full grid. The explicit dyadic/128 CPU policy admits no arbitrary divisor; actual default traces show no active reads of their results when all textures are absent. No native DIV.APPROX bit claim.
- Source unordered comparison against literal+Inf is implemented as a predicate, not NaN replacement. General nonfinite arithmetic is still refused.
- No texture sampling/history reconstruction, native raw-TEX high-word closure, surface format conversion, counter/workspace visibility, live encoder/skip producers or independent packaging is proved here. The original4h226/8192 discrepancy and unexecuted-per-block N64 ViT32–38 evidence gap remain.

All support failures, observer failures, initial count error, interrupted jobs and timeout logs are retained with precise classifications in `ERRATA.md`. Do not rerun historical `main()` functions that rewrite first artifacts. Read-only regression: `OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 python3 -B -m unittest -v test_post70`.
