# DS4 suffix: transparent tensor helper, independent source proof

## Result / bounded scope

Implemented `downsample_candidate.py`: supplied **unquantized final C64x32 half → exactly ordered balanced2x2 pool → FP8 → learned32→64, one K32 per N8 → half D → FP8/four-plane low payload**. High-skip quantization is a separate function and never feeds pooling. The helper has mandatory, named half/quantization/MMA policies; no legacy VM import, fitting, identity-MMA fallback, hidden matrix multiply, file loading, or full-network entry point.

**Important new source detail:** the balanced pool does **not** always visit TL,TR,BL,BR in that order. Horizontal children reverse at local pooled x=2,3; first/second rows reverse at odd local pooled y. All512 scalar expression trees now match the actual selects/shuffles/half operations, including ordered children. A deliberately uniform-order first assertion failed and was corrected from source, not waived as commutativity.

Status: **PASS static/source-suffix/synthetic tests only. No original numerical run or complete model prediction; Main retains first numerical freeze.**

Requested model is exactly packet `openai-codex/gpt-6-astra`, thinking `xhigh`; this worker cannot independently attest/change runtime model identity. No outside discovery, recursive scan, PE parsing/loading, DLL execution, GPU, Wine, network, deployment, gate modification, or nested agent was used. Writes are exclusively in this task's `out/`.

## Identity and actual source counts

|Own authorized input|Bytes|SHA256|
|---|---:|---|
|`in/original.ptx`|234725|`8eb9c92ff8a4ffff1c7906589d789188dc2ee6ee05b685adc8dc2650406327e5`|
|`in/block4-slab.bin`|22720|`f0d05533694577fa313f2655b00ada84f231f87ebc66ebbb7e8f0f7ea1ac88d2`|
|`in/nvngx_dlssnr.dll`|165840496|`e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e`|

All match the packet. Own files stat as mode0400, nlink1; DLL inode52847712, PTX52847713, slab52847714. No other copy was opened to compare inodes. DLL access was streaming SHA256 only, not a PE scan. `IDENTITY.json` preserves observations.

Actual entry: `cc_tinlayout_fused_swin_1h_32_1_ds_fp8`, parameter96B. Corrected semicolon-aware instruction parser, retaining vector braces, finds **5982 executable operations and264 MMA** across14904 source lines. All264 are `mma.sync.aligned.m16n8k32.row.col.f16.e4m3.e4m3.f16`. Final8 are down projection. Original source is retained byte-for-byte as `source_snapshot.ptx`; index/labels are `SOURCE_INDEX.json`. This is not whole-kernel semantic/numerical verification.

**Read budget:** 14/24 primary units: packet1, three prior-context files3, actual PTX eight windows (seven2000-line windows +904 lines), slab1 binary acquisition, DLL1 hash-only stream. Subsequent reads only self-generated output artifacts/code. `READ_LEDGER.json` records exact absolute inputs/windows. No additional primary reads are needed.

## Final C input: explicit row and channel conventions

Candidate input is64 raster rows of32 policy-owned half scalars: `F[8*y+x][c]`, local y,x0..7, c0..31. Here **c is the final MMA N-neuron**, not a serialized byte rank. No implicit FP8 decode or extra input rounding occurs.

Actual final destinations are top `%r2998..%r3013` (MMAs11596..11645), bottom `%r4117..%r4132` (13407..13456). For local pixel y,x and neuron c:

- `m=4*(y%4)+x%4`, `lane=4*(m%8)+(c%8)//2`, half element `c%2`.
- Register number is `(2998 if y<4 else 4117)+8*(x//4)+4*(c//16)+(c//8)%2+2*(m//8)`.
- `unpack_final_c_fragments()` accepts32 lane dictionaries of actual packed uint32 registers and an explicitly supplied half-bit decoder.
- If Main's64 rows are TL,TR,BL,BR four4x4 tiles, `tile_rows_to_raster()` makes the row convention explicit.

`FINAL_C_FRAGMENT_MAP.json` derives all2048 half locations from actual16 final MMA D tuples using the standard m16n8 C-fragment rule. Tests compare the helper's closed-form mapping to these independently seeded tuples. Native fragment execution/full-warp obligations remain open.

## Ordered pool and every half boundary

For pooled local y,x0..3, set `rho=y%2`, `sigma=x//2`. The exact source children are:

```
a = F[2y+rho,   2x+sigma,   c]
b = F[2y+rho,   2x+1-sigma, c]
d = F[2y+1-rho, 2x+sigma,   c]
e = F[2y+1-rho, 2x+1-sigma, c]
t0 = hAddRN(a,b)
t1 = hAddRN(d,e)
t2 = hAddRN(t0,t1)
P[y,x,c] = hMulRN(t2, half_bits(0x3400))
```

|Local pooled coordinate class|First pair|Second pair|
|---|---|---|
|even y, x<2|TL,TR|BL,BR|
|even y, x>=2|TR,TL|BR,BL|
|odd y, x<2|BL,BR|TL,TR|
|odd y, x>=2|BR,BL|TR,TL|

Example m=2 is `(F[0,5]+F[0,4])+(F[1,5]+F[1,4])`, not uniformly left-first. Example m=6 begins `(F[3,5]+F[3,4])`, then row2.

The quarter is source F32 bits`0x3e800000` (`1048576000`), `cvt.rn.f16.f32` → half`0x3400` (+0.25). Each source `add.f16x2`/`mul.f16x2` supplies its own half boundary (RN semantics, not a reassociated float32 sum). There are1536 scalar half adds and512 scalar half multiplies. Source final halves feed the select/shuffle chains13555..13918 directly, independently of high FP8 stores. Pooled half destinations `%r4431..%r4438` quantize13965..13989 into `%rs487..%rs494`, packed to `%r4441..%r4444`.

`POOL_SOURCE_TREES.json` retains512 complete ordered expression trees traced through actual source instructions. `POOL_ORDER_AND_OPS.json` records16 ordered spatial quadruples and every pooling half/quantization instruction. The new `source_suffix_proof.py` interpreter is transparent and restricted to symbolic half operations/integer suffix addressing; unsupported operations fail. The tensor candidate never imports it. No numeric source MMA is evaluated there.

## Permutations: prior pi is inverseMainPI, not MainPI

Unambiguous directions, independently confirmed by the pooled A-fragment tags and low writer:

```
inverseMainPI(c) = 16*(c//16)+4*((c%8)//2)+2*((c//8)%2)+c%2
MainPI(k)        = 16*(k//16)+8*((k//2)%2)+2*((k//4)%4)+k%2
```

First16 `MainPI` = `[0,1,8,9,2,3,10,11,4,5,12,13,6,7,14,15]`.
First16 `inverseMainPI` = `[0,1,4,5,8,9,12,13,2,3,6,7,10,11,14,15]`.
Repeat with16-channel block offsets. Both permutations/inverses are tested for32 and64.

**Input axis:** physical MMA K `k` receives canonical final N-neuron `c=MainPI(k)`. Thus `A[m,k]=Q8(P[m,MainPI(k)])`; canonical c is sent to k=`inverseMainPI(c)`. This is the direction that must not be reversed.

**Output axis:** down MMA N-neuron n is this report's canonical output-neuron convention. Its serialized low channel rank is `r=inverseMainPI(n)`; conversely physical serialized rank r represents neuron `MainPI(r)`. There is no hidden N-axis permutation in `logical_D_mmaN_half`; `logical_D_serializedRank_half[m,r]` explicitly returns `D[m,MainPI(r)]`.

Main should choose the named view matching its canonical tensor convention rather than infer an axis from `PI`. `BASIS_MAPS.json` supplies every direction/table.

## Own learned slab and both weight axes

Down weights start **20656**, not20672, and occupy `[20656,22704)`,2048 FP8 bytes. SHA256 of these exact bytes: `a12ad8174c6a1e4a9571aaab09284440d0c85037d15893c1578cbd8fc18f11b0`. Container F16 metadata does not turn this into an F16 matrix.

Actual v4.u32 loads:

|Line|Address|Registers|
|---:|---|---|
|13935|20656+16*lane|4439,4440,4445,4446|
|13944|21168+16*lane|4447,4448,4449,4450|
|13953|21680+16*lane|4451,4452,4453,4454|
|13962|22192+16*lane|4455,4456,4457,4458|

For physical MMA axes `W_N_K[n,k]`, n0..63,k0..31:

```
B(n,k) = 512*(n//16) + 16*(4*(n%8)+(k%16)//4)
         + 8*((n//8)%2) + 4*(k//16) + k%4
W_N_K[n,k] = slab[20656+B(n,k)]
W_N_C[n,c] = slab[20656+B(n,inverseMainPI(c))]
W_R_C[r,c] = slab[20656+B(MainPI(r),inverseMainPI(c))]
W_R_K[r,k] = slab[20656+B(MainPI(r),k)]
```

These are explicit **both-axis** transformations, not a guessed row-major slab reshape. `weight_views()` returns all four. The source checker follows all four loads across32 lanes, then every B-register byte under the m16n8k32 B-fragment rule: n=`8*g+lane//4`, k=`4*(lane%4)+16*Breg_index+byte`. All2048 `(n,k)` and slab offsets are bijective. `WEIGHT_BYTE_MAP.json` contains actual byte values and canonical-input/serialized-output mappings for each operand.

## All8 learned MMA tuples: no K128, bias, residual, or identity

Every row below uses A=`{%r4441,%r4442,%r4443,%r4444}`, C=`{%r4459,%r4459}`, opcode `m16n8k32.row.col.f16.e4m3.e4m3.f16`.

|g|Line|N range|D tuple|B tuple|
|---:|---:|---|---|---|
|0|13993|0..7|4460,4462|4439,4440|
|1|14000|8..15|4461,4463|4445,4446|
|2|14007|16..23|4464,4466|4447,4448|
|3|14014|24..31|4465,4467|4449,4450|
|4|14021|32..39|4468,4470|4451,4452|
|5|14028|40..47|4469,4471|4453,4454|
|6|14035|48..55|4472,4474|4455,4456|
|7|14042|56..63|4473,4475|4457,4458|

`%r4459` has one source definition: F32 +0 at955, RN half conversion959, duplicated half+0 at960. No down bias load, carried K chunk, or post-down residual exists between pooling and these outputs. Candidate invokes its supplied MMA policy **exactly8 times**, each A16x32/B8x32/C16x8(+0) → D16x8. Internal native accumulation is deliberately not equated to a host dot. `SUFFIX_MMA_TUPLES.json` and `SUFFIX_MMA.json` preserve tuples and load evidence.

## Low four-plane writer, origin0/-4, and separate high fork

Source low pointer is ABI+64; high pointer ABI+8. Host graph/export binding was not rederived (PE inspection forbidden); prior host prose is not promoted into new evidence.

Low data uses `HD=trunc0(H/2), WD=trunc0(W/2)` from ABI24/28, not padding fields72/76. In the admitted positive/no-overflow domain, `oy=(Y+8*cy)/2`, `ox=(X+8*cx)/2` for origins multiples4. For source lane,d:

```
m = lane//4 + 8*d
y = oy + m//4; x = ox + m%4
n = 16*plane + 8*u + 2*(lane%4) + e
byte = 16*((plane*HD+y)*WD+x) + 4*(lane%4) + 2*u+e
     = 16*(((n//16)*HD+y)*WD+x) + inverseMainPI(n)%16
```

plane0..3,d/u/e0..1. Each actual `st.global.v2.b16` stores four FP8 bytes: n-pairs for u0 then u1, not F16 payload. Source lines14137,14171,14205,14240,14275,14311,14345,14380 are separately guarded by `0<=y<HD && 0<=x<WD`; there is no preceding low-null or PH/PW guard.

`low_writer_coordinates()` exposes all256 store coordinates/guards per CTA, including invalid stores with no address. `low_global_stores()` returns valid relative byte-address/byte-string records; it does not allocate/write device memory. `low_packed_local_four_planes` is the1024-byte **unguarded local16-pixel tensor view**, not a global allocation or padding buffer.

High is independent `Q8(F)` to four tiled4x4 C32 stores, source11722/11739/13535/13552, with complete-tile guards. `high_skip_stores()` returns only valid high bytes, never zero-fill. Integer/source checks enumerate actual high/low stores and compare all byte identities to closed-form candidates. H=W64, origin0 CTA0: high2048/low1024 bytes; origin(-4,-4) CTA0: high512/low256; origin(-4,-4) CTA(1,1): high2048/low1024. Eight cases also cover unequal/odd extents, one-axis shift,4x4 sizes, and guarded-out CTAs. See `WRITER_COORDINATES.json` and `TEST_RESULTS.json`.

## Padding stays EXACT STATIC, separate eight planes/different strides

Original PTX remains unchanged, including the entire padding CFG, peeled loops, four-way unrolling, and backward branches after the textual return. The new checker directly interprets that original integer CFG; no padding fix or four-plane normalization was substituted.

Original zero addresses are `16*((p*PH+y)*PW+x)+b`, **p0..7**, b0..15, with PH/PW from72/76 and ceil(H/2),ceil(W/2) interior exclusion. Low learned stores remain **four** planes at HD/WD strides. Late null/extent checks begin14382 **after learned stores**. Conditional `bar.sync0` at14436 is CTA-local; CTA0 tail strips can run without it. No grid publication/alias/ordering guarantee is inferred.

`padding_static_addresses()` is a separate address-set helper, not a data packer or scheduler. Its local4x4 boundary rectangles and CTA0 uncovered bottom/right rectangles match exact source-CFG zero sets on10 cases, with32/48/64/128/160-thread integer tests. These thread counts are static loop tests, not approved neural launches.

- H=W64,PH=PW32, origins0 and-4: zero padding bytes and no barrier CTAs.
- H=W60,PH=PW32,origin-4,grid8x8:15872 zero-byte addresses, max exclusive131072;7936 lie above a **hypothetical**64*PH*PW envelope and6464 overlap the dense64*30*30 data-address envelope.
- H=W59 preserves floor/2 data versus ceil/2 padding exclusion; no invented odd-size fill.
- H=W62,PH=PW32,origin-4,grid9x9:8064 zero-byte addresses,17 barrier CTAs, same set for32/64 threads.

**Not an actual-allocation OOB finding.** No actual allocation, pointer alias, live launch, or inter-CTA schedule was observed. Static eight-plane zero stores do not imply128 learned channels. No four-plane padding repair is proposed. Exact integer wrap/negative-size behavior outside the helper's conservative admitted domain is not generalized.

## FFN wording ambiguity: bounded check only

Do not turn prior “clamp z, then z*...” prose into clipped outer multiplication. In the inspected first cubic chain, raw z=`%r267`; `min` then `max` produce clipped t=`%r271`; abs(t)→`%r273`; first FMA→`%r275`; second FMA uses t→`%r277`; final `mul.f16x2 %r497,%r267,%r277` multiplies **raw z**, not clipped t. Constants are -4,+4,-0.055908203125,0.447265625,0.89453125, converted to half before use. `FFN_AMBIGUITY_WITNESS.json` preserves exact instructions. No fullFFN implementation or all-stream verification is claimed; FFN is outside this task.

## Verification / Main handoff

Commands run (from this task root):

```
python out/ingest.py
PYTHONDONTWRITEBYTECODE=1 python out/source_suffix_proof.py
PYTHONDONTWRITEBYTECODE=1 python out/test_suffix.py
```

Final run `test_run_04.log`: all five sections PASS. Earlier failures and their fixes are retained in `FAILURES.md` and failed logs.

Tests include5982/264 counts;512 ordered source pool trees;2048 final-C locations;2048 actual slab byte origins; all8 complete MMA tuples; both permutation directions/weight axes; low/high source writer bytes at0/-4; exact padding integer CFG; synthetic32 input-channel basis tests across64 outputs with genuinely nonidentity learned matrices and32-product MMA policies; packed output checks; invalid-policy/input rejection.

Arithmetic tests use **synthetic F and synthetic slabs only**. Their explicit test MMA computes32 products via host `math.fsum`, then one half rounding; it is not native-certified and is not installed as a candidate default. Actual slab is used only for hashing/layout byte checks. Test quantization independently checks all63488 finite half bit patterns against a binary-search nearest-even E4M3FN oracle, plus5 edge cases; this is not GPU acceptance.

Rounding witness with ordered children `[2048,1,1,-2048]`: source balanced pool gives half0.25; sequential gives0; single-round exact sum gives0.5. Separate-fork witness `[1.0625,1.0625,1.0625,1.125]`: correct unquantized pool produces A FP8`0x39`, wrongly pooling decoded high bytes gives`0x38`.

Main must explicitly supply `Policies(half_from_bits, half_add_rn, half_mul_rn, fp8_e4m3_rn_satfinite, mma_m16n8k32, ...names...)`, select raster/channel views, and supply final halves plus the slab. The helper returns pooled halves, physical-K FP8 A, raw-N half D, serialized-rank half D, raw-N FP8 D, and local packed low bytes. Global high/low stores and padding addresses are separate calls.

### Explicitly unverified / not done

1. Actual final C activations; actual learned-slab numerical projection; original/full-block/full-model numerical prediction; first numerical freeze.
2. Native MMA internal precision/order, half NaN/subnormal/FTZ details, native FP8 exceptional behavior and policy equivalence. No GPU/Wine/DLL execution.
3. FullFFN, QKV/attention/PV/final projection numerical derivation or whole-kernel CFG equivalence.
4. Live variant/dispatch/host graph binding, pointer allocations/extents, aliases, visibility, lifetimes, warps/CTA, active mask, legal launch shape, CTA-z duplication, and barrier scheduling.
5. Actual allocation OOB or padding safety; cross-CTA data/zero-store order. Original static discrepancy is retained, not repaired.
6. Inputs outside positive dimensions, aligned origins and conservative no-overflow domains; universal equivalence of the simplified padding address set for all possible integer launches.
7. Main's actual tensor-view convention/integration and supplied numeric policies; no external Main files were read. Runtime model identity beyond the packet request.

Exact generated paths and artifact roles are listed in `ARTIFACTS.json`; all reside under `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-encoder-proof-main-20260912/02-ds-tail/out/`.
