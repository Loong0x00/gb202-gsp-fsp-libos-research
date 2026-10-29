# Original plain Swin8H256 DS / historical block22 — CPU/static reference

## Bounded result

**All eight warps execute the untouched original DS body through its original `ret` at PC6155**, with the real block22 slab. One synthetic 8×8 CTA executes **10,752 MMAs**, releases **10 original 256-thread barriers**, writes **16,384 ordinary E4M3 bytes** and **8,192 downstream E4M3 bytes (4×4×512)**. Independent dense checks cover retained-half 2×2 pooling, every projection C element and every output byte. No original instruction, loop or barrier was removed.

This is **conditional plain-entry CPU arithmetic under explicit non-native numerical policies**, not proof of native variant selection, activation parity, launch arguments or readiness. Historical block22 is shifted; the plain entry is not claimed to be its captured native selection.

```sh
python -B reviews/nr-swin8h-ds-reference-20260911/verify.py
# Explicit synthetic fixture only:
python -B reviews/nr-swin8h-ds-reference-20260911/fixture.py --synthetic --reference-policies
```

All writes are confined to this review. No GPU, Wine, CUDA compiler, installed-file modification, sibling write, PTX downgrade or approval request. Main-working community-tone A/B and future authorized native validation remain separate, untouched tracks.

## Independent source, raw/checkpoint, and graph evidence

`collect_evidence.py` freshly decompresses the DLL's exact module03 and module04 PTX records and compares complete module bytes. Original **PTX 9.4 / sm_120** headers are retained separately. Entry slices start at `.entry` (the module's preceding `.visible ` is outside the slice).

| Entry | Module byte slice | Bytes | SHA256 |
|---|---|---:|---|
| `cc_tinlayout_fused_swin_8h_256_8_ds_fp8` | [2692393,2940094) | 247701 | `80a37a10095d4dfadf7b5cae4c430326987c1912ccc9d265ee4560bda3f4f528` |
| `cc_split_swin_16h_ffwd_inpview_512_fp8` | [212090,307346) | 95256 | `3865a7907f63390135ae37992aa73228076478ae2b440ece5265c7fdc239d4d6` |

Module03 SHA256: `fc7b019606d6f00a3dad501b39ec7a38fe0d904b9f187b0254b92935d40565b5`.
Module04 SHA256: `6eaaebeca9c051660f7a9df9ac18c6c13e3a7e267b5392c98c73a0f6f2e21fe6`.

PE resource = raw container = checkpoint payload comparisons are rerun independently of the architecture classification. **`block22.layer0.layer` is 820288 bytes**, SHA256 **`cfb0343287054e38933dbf35c7dbb124fef50cfaf4234f7161575f00896cc02d`**. Raw offset **5907537**, checkpoint offset **5920400**, lexically sorted/aligned upload offset **5912576**. Its nominal F16 serialization `[410144]` is **not** a dense F16 kernel matrix layout.

The architecture JSON and independent historical `graph-factory.log` agree on each layer's type, class and full operator sequence. Graph tensor names, byte counts, shapes and source offsets are joined separately to freshly parsed raw records. The Main scan is confirmed:

| Blocks | Actual historical family |
|---|---|
| 15 | `8h_inpview_256` |
| 16–18 | standard `8h_shifted_256` |
| 19 | standard unshifted `8h_256` |
| 20–21 | standard `8h_shifted_256` |
| **22** | **`8h_ds_shifted_256`**, 35 operators |
| 23 | **four-layer `cc_split_swin_16h_block`**, starting `16h_ffwd_inpview_512`, not fused8 |

Thus **16–21 are standard, not DS**. Blocks16–22 have explicit preceding input edges in both historical records. **Block23 has no recorded input edge**: sequential naming and compatible addresses do not attest an actual native dependency. `EVIDENCE.json` pins the source DLL/raw/checkpoint/graph/log and block15–23 layer0 slabs, with all block23 graph layers retained.

## Own ABI and CTA, not a smaller-DS substitution

The seven original parameter instructions and full pointer def/use scan prove:

| Byte offset | Own DS8 role |
|---|---|
| +0 | packed input `%rd1`; four original vector-load sites |
| +8 | ordinary output `%rd9`; four b128-store sites |
| +16 | block22 slab `%rd10` → `%rd2` and learned pointers |
| +32,+36 | signed H,W |
| +40,+44 | signed X,Y; effective origin `(X+8*CTA.x,Y+8*CTA.y)` |
| +72 | downstream pointer `%rd11` → `%rd8`; projection/padding stores |
| +80,+84 | downstream padding dimensions, **not inpview overrides** |

The aggregate is **88 bytes**; `[24,32)` and `[48,72)` are unread and independently poisoned in tests. The API requires an explicit own-DS ABI acknowledgement.

Own source PC30 reads `tid.y`; PC191 shifts it by9, while PC200 advances a tile by4096. With 32 lanes ×16 bytes per warp, **4096/512 = eight warps** fill each tile, and four tiles fill the declared **16384-byte shared allocation**. Tagged ingress verifies disjoint complete ownership. The symbol's `4HLayer` spelling is not used as a launch proof. The conditional launch is **(32,8,1)**; there is no native launch capture or `.reqntid` assertion.

Bounds: H,W multiples of8 in **[8,256]**; X,Y and effective origins multiples of4 in **[-256,256]**; grid x/y each in **[1,64]**, z=1. Exact input and ordinary spans are `H*W*256`; downstream is `H*W*128`; slab must be the complete pinned block22 payload. All four spans must be nonnull, disjoint, nonwrapped and aligned at reached accesses. Sparse input is accepted only when every reached byte exists. Only original OOB branches supply zeros.

**Only +80/+84 = (H/2,W/2) is supported.** Any other padding pair rejects before arithmetic. In this domain PC5809 takes the original return at6155. Padding-only PC ranges **[5810,6155), [6156,6295)** remain in the source/parser but are not certified or executed. This includes the original eleventh static barrier at PC5849. The 10 bounded-path barriers are not a claim to have executed that excluded padding barrier.

## Own learned recurrences and typed roles

All **6295 static instructions parse**. Interior plus shifted/rectangular/OOB cases execute **5806 distinct instructions**. `COVERAGE.json` explicitly lists unexecuted broadcast/pointer-null/padding paths; full static coverage is not claimed.

| Original loop PCs | Own induction | MMAs per warp |
|---|---|---:|
| 251…937 | `%r4691 = 0,32,64,96` | 576 |
| 1484…1533 | `%r4693 = 0,32,…,224` | 128 |
| 1704…1805 | `%r4823 = 0,32,…,224` | 384 |
| 5144…5199 | `%r4824 = 0,32,…,224` | 128 |
| 5608…5803 outer / 5623…5664 inner | `%r4857 = 0,256`; each has `%r4867 = 0,64,128,192` | 64 |
| straight-line attention | original instructions | 64 |
| **Total** | **1344 ×8 warps** | **10752** |

Checked source initializers, updates, comparisons and backedges give slab-relative recurrences (`w=0…7`):

```
rd435 = 1024*t                              t=0…3
rd436 = 295424 + 1024*w + 8192*t             t=0…7
rd437 = 363552 + 3072*w + 24576*t            t=0…7
fourth-loop weight base = 623168 + 1024*w + 8192*t
rd438 = 706112 + 1024*w + 8192*outer + 32768*inner
                                               outer=0,1; inner=0…3
```

Shared induction pointers `%r4692/%r4726 = 512*t`; the fourth loop computes its shared offsets from `%r4824`; nested projection `%r4858 = 1024*inner`. **The fourth-loop base is 623168, not the fresh non-DS8 entry's 623680. The projection has a nested k64 loop, not the smaller DS's unrolled k128 loop.**

Independent backward expressions verify all **113 static slab sites /2120 dynamic warp loads**, every lane's source address, exact loaded bits and direct typed uses: E4M3x4 MMA A/B, FP16x2 C/coefficient arithmetic and FP32 query scalars. All slab sites reach checked typed uses. **820256 distinct slab bytes** are read; only `[360448,360464)` and `[360976,360992)` are unread and retained.

FP32 query scalars are at `623136+4*w`; block22 raw bytes / values:

```
0 60c68d3f  1.1076164245605469     4 f3d16b41 14.738757133483887
1 ac263d41 11.821941375732422      5 58ea5e41 13.932212829589844
2 f0472241 10.142562866210938      6 dc405641 13.39083480834961
3 50784b41 12.716873168945312      7 1ca52841 10.54030990600586
```

`TYPED_OPERANDS.json` and `STATIC_PROOF.json` retain the source expressions, typed load provenance and recurrences.

## Shared memory, strict arithmetic and numerical boundaries

Bounded barrier PCs: **212,1410,1478,1534,1602,2782,5141,5555,5556,5573**. The adjacent **5555/5556** barriers remain separate. Own scheduler release requires the same PC/id and all 32 active lanes in all eight warps, with no early retirement.

Independent byte producer/epoch checks cover **71 static shared sites /67840 events**, including **860160 cross-warp read-byte events**. Shared contents persist across epochs, never reset or implicitly zeroed. Missing producers, bounds/alignment violations, RAW/WAR/WAW and mismatched barriers fail closed. Reverse and interleaved schedules give identical final registers and both output buffers.

The fresh8 review supplies only pinned generic strict warp arithmetic, shared byte semantics and numerical/MMA helpers. Local ABI, CTA release, learned recurrences, DS layout and projection are own-source derivations. The local machine's sole difference from the fresh8 generic machine is enabling **17 already-implemented instruction forms** actually present here (including `mov.pred`, `bra.uni`, cg vector loads and v2.b16 stores). `machine-changes.diff` and a test prove no execution-handler changes. No smaller-DS ABI/offset/projection helper is imported; reused proof/memory scaffolding is checked against this source.

`NUMERICAL_POLICIES.json` explicitly states:

* Each original k32 MMA uses exact finite E4M3 products plus half C, then **RN-even half after that instruction**. All 10752 fixture MMAs match a separate forward ISA fragment-placement oracle. This is **not native tensor-core accumulation parity** and not one rounding after k256.
* Source half2 add/mul/fma and conversions preserve their separate rounding boundaries and signed-zero rules; half overflow/nonfinite arithmetic and E4M3 NaNs reject. The dense checker independently uses exact dyadic products and RN-half at each original k32 boundary.
* `rsqrt.approx.ftz.f32` uses the explicit reference RN-even FP32 `1/sqrt(x)` policy on positive normal inputs; `rcp.approx.ftz.f32` uses reference RN-even FP32 `1/x` with FTZ output handling and FTZ-zero-denominator rejection. **Neither is a native approx oracle.**
* Unknown opcode/forms, operands or reached memory bytes reject, rather than being skipped or filled.

## Retained-half pooling, learned 256→512 projection and exact layouts

Input and ordinary output are E4M3 **256-channel 4×4 microtiles**. For row `y`, column `x`, channel `c`:

```
m = 4*(y%4) + x%4
lane = 4*(m%8) + (c%8)//2
j = 4*((c%32)//16) + 2*(m//8) + (c%16)//8
packed_offset = 4096*((y//4)*(W//4)+x//4)
                + 512*(c//32) + 16*lane + 2*j + c%2
```

Own ordinary C registers **r4825…4856** are forward ISA fragments: within each tile's eight registers, `m=lane//4+8*(j%2)` and channel pair `32*warp+2*(lane%4)+8*(j//2)`. The original ordinary stores (PC5255,5268,5290,5303) permute the register order **0,2,1,3,4,6,5,7**. All bytes are checked independently; this is not a DS4 register placement assumption.

Those C registers stay **half-valued after the ordinary E4M3 stores**. The original shuffle/add/mul chain pools them directly, without reloading or quantizing the ordinary output first:

```
E4M3( RNhalf( RNhalf(RNhalf(v00+v01) + RNhalf(v10+v11)) * 0.25 ) )
```

All **4096 pooled elements** match independent logical pooling and original shared staging at PC5572. Quantizing ordinary values first changes **948** pooled bytes in the supplied fixture. Tagged C-fragment tests separately validate the original ordinary stores, pooling and full projection.

The complete learned tail **[689216,820288)** is **131072 E4M3 bytes =256×512**. There is no guessed/discarded tail and no assumed projection bias. Eight separately rounded k32 dots contribute to each projected output element; the original nested loop computes two successive k32 groups per k64 iteration, in order.

Source/ISA-derived channel permutations:

```
old_channel(k) = 16*(k//16) + 2*((k%16)//4) + 8*((k%4)//2) + k%2
out_channel(n) = 16*(n//16) + 4*((n%8)//2) + 2*((n%16)//8) + n%2
```

For `q=0…7`, output warp `w=0…7`, outer pass `t=0,1`, local `k,n=0…31`:

```
lane = 4*(n%8) + (k%16)//4; ng = n//8
weight_offset = 689216 + 16384*q + 1024*w + 8192*t
                + 512*(ng//2) + 16*lane + 8*(ng%2) + 4*(k//16) + k%4
input channel  = 32*q + old_channel(k)
output channel = 256*t + 32*w + out_channel(n)
```

These offsets bijectively cover all 131072 tail bytes. The dense checker validates **8192 half C elements** against own reversed C registers `4866-2*(n//8)-(m>=8)`, then independently quantizes and verifies every downstream byte. Channel labels are defined by source/ISA/view placements, not guessed checkpoint axes.

Downstream is E4M3 **`[32,H/2,W/2,16]`**, 512 channels:

```
view_offset(y,x,c) = 16*(((c//16)*(H/2)+y)*(W/2)+x) + c%16
```

Fixture hashes (synthetic reproducibility, **not native golden activations**):

* ordinary 8×8×256: `61e0170f41267a97a0c6c04700d6863135751f5432673a4d35d27ddfd674e3cf`
* downstream 4×4×512: `4af7395f679492c13ac7a39d9b8fd5fca372183a1f48800d9af79a4a9a60902f`
* four DS CTAs at H=W=16 produce complete downstream 8×8×512: `808983e0442179682cedd5a1610f94970ffc2f342b19d7f22749cc8c4085e45a`

The four-CTA assembly independently checks pooling/projection per CTA and rejects overlapping/unproduced output bytes.

## Separate next-stage compatibility and truthful unsupported boundary

The actual next entry is **split16 ffwd inpview**, with its own **56-byte** aggregate, input at+0 and H,W at+24/+28. It declares **8192-byte, 512-aligned shared input storage plus two mbarriers (16 bytes)**. It is **not** another fused8 ingress and cannot use the fused8 scheduler/ABI as a substitute.

`next_static.py` preserves and lexes its full source but **does not execute it**. Independent backward source expressions check all **16 `cp.async` source sites**, the original channel-loop initializer/increment/comparison/backedge, and **8192 four-byte addresses /32768 bytes** for conditional (32,4,1), H=W=8, CTA=(0,0,0). Initial64-channel prefetch plus seven increments of64 have exactly the DS `[32,H,W,16]` physical addresses. Tagged bytes and the actual assembled DS bytes pass; missing supplied bytes reject. **No repacking is required at this address-contract level.** `NEXT_STATIC.json` retains expressions and the exact input SHA.

**Unsupported:** executing `mbarrier.init/arrive/try_wait`, `cp.async/commit_group/wait_group`, shared-copy publication/readiness, next16 forward arithmetic, native inter-kernel ordering and actual block23 dependency. The DS VM rejects this entry, rather than replacing async operations with synchronous copies or removing barriers. Address compatibility is deliberately **not** described as an executed original next-stage ingress.

## Verification and remaining scope

**16 CPU tests** cover source/raw/graph pins, own ABI, every original MMA, all typed slab/shared sites, recurrences/retirement, retained-half pooling and dense projection, bijective byte layouts, tagged ingress/C, reverse/interleaved scheduling, shifted rectangular sparse edges, nonzero CTA, wholly OOB CTA, unread ABI poisoning, and fail-closed missing/alias/null/wrap/alignment/padding/policy/opcode/shared/barrier cases. Separate next16 tests cover static source addresses, real/tagged supplied bytes and missing-byte rejection — not async execution.

`verify.py` reruns provenance, fixtures, proofs and tests, compares protected read-only source/helper hashes before/after, and regenerates/verifies deliverable `SHA256SUMS`. See `VERIFICATION.json`, `tests.txt`, `BOUNDARIES.json` and `COVERAGE.json`.

This restores the bounded **plain DS family arithmetic with historical block22 weights**, not historical native launch identity. A future authorized native check would still need actual selected plain/wait/tilesync/PTX/cubin identity, exact arguments/input/slab readiness, both output captures and independent async consumer ordering. None was requested or performed here.
