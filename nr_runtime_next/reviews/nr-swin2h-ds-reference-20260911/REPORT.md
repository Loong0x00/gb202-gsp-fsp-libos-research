# Plain Swin2H DS: bounded full CPU arithmetic and 4h ingress compatibility

## Result and identity correction

Executable **`cc_tinlayout_fused_swin_2h_64_2_ds_fp8`**, original **88-byte** aggregate, both `(32,2,1)` warps through original `ret`: packed input → **832 learned/core MMAs** → ordinary output → source-order half pooling → shared exchange → **32 projection MMAs** → downstream output. No original loop/barrier instruction was erased. The original two-warp machine is reused unchanged, with its strict shared-memory epochs, barriers, control flow and collective convergence requirements.

**The requested “block9 DS slab” conflicts with verified local evidence.** `graph-factory.log`, the raw DLL resource and byte-identical checkpoint identify:

* **block8**: `cc_tinlayout_fused_swin_2h_ds_shifted_64`, **69936 bytes**, SHA256 `687d906bc5d6748b57ee3e519c114f9382d93db560b7f779461c1ab90f5237ae`. This is the actual DS slab used here.
* **block9**: `cc_tinlayout_fused_swin_4h_inpview_128`, **197184 bytes**, SHA256 `934cebc771cfa1ed086f47f018426090e14ca4326dcb22843cbc17dff9851c32`. Its real bytes are saved separately, **never relabeled or accepted as DS weights**. They are not required by the ingress-only 4h prefix.

Consequently, a literal full DS execution with block9 weights is **not delivered**, rather than silently interpreting an incompatible slab. Historical shifted graph naming does not prove which plain/wait/tilesync kernel was selected, nor its launch origin or epoch.

```sh
python -B reviews/nr-swin2h-ds-reference-20260911/verify.py
```

Explicit fixture: `fixture.py --synthetic --reference-policies`. API: `ds2_reference.run(...)`; see `fixture.run_one` for caller-supplied arguments, bytes, spans, grid and policies. All writes are confined to this review. No GPU, Wine, compiler, header downgrade, installed-file change or prior-worker edit.

## Byte provenance and own ABI

Fresh read-only decompression of original DLL PTX records matches both untouched entry slices. Header copies preserve **PTX 9.4 / sm_120**. Offsets count bytes beginning at `.entry` (the module's preceding `.visible ` is outside the slice):

* module01 DS `[2466108,2701826)`, 235718 bytes, SHA256 `0e7fa63dd4db7d9a3481590765a3e8e2ffe40897464ec5abc84d6b1008eed44b`.
* module02 4h inpview `[1899483,2114298)`, 214815 bytes, SHA256 `805e92d0dcceee5aaaf6c300ed2483abf0776be7ac1d8ff9fed03ff30f38e24c`.

`EVIDENCE.json` records DLL/resource/container/checkpoint identity, both real slab offsets and sorted 512-aligned upload offsets. Nominal F16 checkpoint storage is **not** a dense F16 interpretation.

**DS's own source loads/stores**, not the earlier mistaken 2h pointer labels, prove:

| Bytes | Role from original def/use |
|---|---|
| +0 | input `%rd1`: four global vector read sites |
| +8 | ordinary output `%rd8`: four b128 store sites |
| +16 | slab `%rd9` / global `%rd2`: 133 read sites |
| +32,+36 | H,W signed int32 |
| +40,+44 | X,Y signed int32 |
| +72 | downstream `%rd10` / global `%rd7`: four main stores, 60 padding stores |
| +80,+84 | padding H,W signed int32 |

`[24,32)` and `[48,72)` are **unread by this plain entry**, not invented pointer/flag roles. All seven parameter-load sites and all global-address pointer origins appear in `STATIC_PROOF.json`. Fixture unread fields are deliberately poisoned `0xA5`.

## Bounded execution and numerical policies

H,W in `[8,4096]`, multiples of four; X,Y and effective CTA origins multiples of four within `[-4096,4096]`. Explicit positive grid x/y ≤1024, z=1; CTA z=0. Disjoint, nonnull, nonwrapped input/slab/ordinary/downstream spans of exactly `H*W*64`, `69936`, `H*W*64`, `H*W*32` bytes. Input is an explicit sparse byte map: every reached byte must exist. Only original PTX out-of-bounds branches manufacture zeros.

Padding dimensions must be `(0,0)` or exactly `(H/2,W/2)`. **Extended padding is rejected** before execution; its original code, backedges and ninth static barrier remain present but uncertified. Missing bytes/policies, wrong slab identity, aliases, unsupported geometry/opcodes, shared holes/races and barrier mismatch fail closed.

All 5823 static instructions parse. An interior CTA executes two core loop passes (`%r4856=0,1`) and two projection passes (`%r4889=0,64`): **416 core +16 projection MMAs per warp**, 864 total. Eight original barriers release only after all 64 threads arrive, at PCs `1581,2747,3693,3813,4738,5097,5098,5115`. The consecutive barriers are **both retained**. The 4096-byte shared store has no implicit zero initialization; every one of **2112 shared read/write events** is checked against independent source address expressions and the actual last producing byte/warp/epoch. Reverse warp schedule gives identical registers and outputs.

Explicit policies: finite E4M3 dots plus half C, RN-half **after each k32 MMA**; reference RN RSQRT and reciprocal. They are **not native tensor-core accumulation or approximate-instruction oracles**. In particular the 64-channel projection has two k32 partial accumulations, not one single-rounded k64 dot.

`TYPED_OPERANDS.json` verifies all **133 static slab sites /330 dynamic warp loads**, loaded bits and direct typed uses (E4M3 MMA A/B, half2 C/coefficient arithmetic, FP32 conversion). DS query scalars are recovered from its own block8 slab: offset **57504** `1a7a713f` = 0.9432693719863892 for warp0, **57508** `fa7ad140` = 6.546261787414551 for warp1. No 1h query constants are borrowed. Unread slab ranges: `[28672,28688)`, `[28816,28832)`, `[57512,57520)`.

## Exact 64 →128 representation

Let effective origin be `(X+8*cta.x,Y+8*cta.y)`. Ordinary 64-channel packing, with logical channels defined by source C-fragments rather than presumed checkpoint axes:

```
m = 4*(row%4) + col%4
lane = 4*(m%8) + (c%8)//2
j = 4*((c%32)//16) + 2*(m//8) + (c%16)//8
offset = 1024*((row//4)*(W//4)+col//4)
         + 512*(c//32) + 16*lane + 2*j + c%2
```

The DS **ingress warp index selects spatial rows** (`Yeff+4*warp`), with channel groups 0/32 at its four vector sites. **After shared exchange, the output warp index selects channel groups 0/32**, not spatial rows. This distinction is independently tested. One interior CTA reads and writes 4096 ordinary bytes.

Unquantized ordinary source fragments are `%r2952..2967` and `%r3942..3957`. Independent tensor decoding proves the original shuffle pool equals **horizontal half sums, then vertical half sum, then half multiplication by 0.25**, followed by E4M3 conversion. The factor comes from DS's own FP32 immediate `1048576000`, not a reused 1h pooling routine. Tagged nonuniform fragments additionally exercise the original pool slice.

`layout_proof.projected_bytes` independently computes tensor pooling, channel-to-K permutation and the slab projection at `[61744,69936)`. For local output group `q=0..3`, projection warp `wy`, pass `t=0,1`, second K block `cw=0,1`, and ISA projection column `n=0..7`:

```
K local k = 0..31
ordinary channel = 32*cw + 2*((k%16)//4) + 8*((k%4)//2) + k%2 + 16*(k//16)
weight lane = 4*n + (k%16)//4
weight byte = 61744 + 4096*cw + 1024*wy + 2048*t + 512*(q//2)
              + 16*weight_lane + 8*(q%2) + 4*(k//16) + k%4
physical downstream channel = 32*wy + 64*t + 16*(q//2) + 4*(n//2) + 2*(q%2) + n%2
```

With `Hd=H/2`, `Wd=W/2`, downstream is **E4M3 `[8,Hd,Wd,16]` physical bytes**, not an ordinary packed 128-channel microtile or an NCHW reshape:

```
down_offset(row,col,c) = 16*(((c//16)*Hd+row)*Wd+col) + c%16
```

Each interior CTA produces 4×4×128 = **2048 downstream bytes**. The independent tensor calculation consumes neither the pool/projection result registers nor store addresses. Tagged original stores separately prove both downstream loop-pass layouts.

## Static original 4h ingress compatibility

Four independent synthetic DS CTAs on a 16×16×64 input produce **8192 bytes** (8×8×128). The actual module02 `cc_tinlayout_fused_swin_4h_128_4_inpview_fp8` ingress prefix, **all four warps**, reads exactly those bytes **without repacking**: 512 scalar 4-byte loads per warp, complete disjoint byte coverage. Independent address/register maps and a separate tagged-byte fixture validate all 16 load sites per warp.

This prefix stops **immediately before the first shared exchange**, after original ingress label `$L__BB9_32`. It is not a truncated full 4h numerical claim: no 4h barrier is erased or released, and no learned 4h MMA is executed. The real block9 slab is retained for the next boundary, but full four-warp 4h arithmetic is outside this deliverable.

## Verification and remaining limits

**14 CPU tests pass**: own ABI/global pointer lineage, byte identity and block8/block9 conflict, all typed slab sites/scalars, all 864 independent forward-map MMAs, both loops, complete shared footprints/barriers, independent pooling/projection/layout, tagged pool/stores, reverse schedule, shifted rectangular sparse edges, four-CTA → four-warp 4h ingress, and fail-closed negative cases. `verify.py` regenerates evidence/fixture, runs tests and checks read-only source/helper hashes; `SHA256SUMS` covers deliverables.

Still separate/unproved: native plain vs wait/tilesync/cubin/PTX selection, predecessor readiness, inter-CTA/native dependency semantics, runtime activation/argument capture, extended padding, native approximation/accumulation bit equality, full 4h arithmetic, and any claim that prior block5 output is the model's immediate DS input. The DS fixture is explicitly synthetic, not fabricated native evidence.
