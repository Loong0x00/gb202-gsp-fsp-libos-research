# Block1 INPVIEW — independent CPU/static source recovery

**Partial task completion; no model acceptance or native equivalence claim.** Base source, ingress, arithmetic alpha correspondence, and CFG are proved below. Tilesync bytes, actual slab values, and fresh PE host selection are explicitly unverified because preserved parser failures exhausted the source-read budget.

## 1. Exact identity and PC convention

- `cc_tinlayout_fused_swin_1h_32_1_inpview_fp8`: **5505 instructions**, one aligned-8 **96-byte ABI**, `.maxnreg 168`. Independently checked SHA256 `e36a534b79b5361f853f1e8baf4cd63f80d85bd73259e46de36a31321568ce13`.
- Ordinary `cc_tinlayout_fused_swin_1h_32_1_fp8`: **4902 instructions**, SHA256 `15ddfc388ff77a4a1ce1bd4bbad79d44df220dda70f731a379eefa1694e0a8cd` independently checked.
- All PCs here are **zero-based PTX instruction ordinals, not native byte PCs**. Ranges are half-open. Instruction JSON also retains original source line numbers.
- Distinct tilesync entry's **5531** count is packet/user information only; its source was not read. It is NOT folded into this proof.

## 2. ABI and exact ingress source

`FIELD_MAP.json` gives individual load PCs and field ranges:

| ABI byte | Meaning | Base PC |
|---:|---|---:|
| 0 | input A pointer | 5 |
| 8 | packed-C output pointer | 1 |
| 16 | own block1 slab pointer | 0 |
| 24,28 | logical H,W | 2 |
| 32,36 | X,Y origin | 4 |
| 72,76 | positive source H,W overrides; otherwise logical H,W | 3 |

Base does not read `[40,72)` or `[80,96)`. Ordinary does not read the source overrides.

Let `hs=(Hsrc>0?Hsrc:H)`, `ws=(Wsrc>0?Wsrc:W)`, `ox=X+8*ctaid.x`, `oy=Y+8*ctaid.y`. For lane `l=0..31`, 4x4 tile `t=0..3` ordered TL/TR/BL/BR, A-register slot `a=0..3`, little-endian byte `b=0..3`:

```
x = ox + 4*(t%2) + (l//4)%4
y = oy + 4*(t//2) + 2*(a%2) + l//16
valid = (hs==1 or 0<=y<hs) and (ws==1 or 0<=x<ws)
sx = 0 if ws==1 else x
sy = 0 if hs==1 else y
k = 16*(a//2) + 4*(l%4) + b
byte_offset = 16*((k//16)*hs*ws + sy*ws + sx) + k%16
```

If invalid, the corresponding raw 32-bit register is **literal integer zero**, and the load is skipped. Each dimension of size1 broadcasts independently even for negative/out-of-range coordinates. Nonpositive overrides fall back independently; they do not mean an absent source. Simplified formulas admit positive effective dimensions and no signed32 overflow; the original PTX integer expressions remain authoritative outside that domain.

This is **two 16-channel spatial planes**, not ordinary packed C and not a claim of scalar-channel-major planar storage. Physical `k` carries predecessor **finalC `PI(k)`**, where:

```
PI = [0,1,8,9,2,3,10,11,4,5,12,13,6,7,14,15,
      16,17,24,25,18,19,26,27,20,21,28,29,22,23,30,31]
```

The permutation is taken from the actually read pre0 basis evidence and composed with this independently recovered consumer map. No new pre0 numerical run was performed.

The ISA A-fragment coordinates are `m=l//4+8*(a%2)`, `K=k`; the 4x4 source pixel is `(m//4,m%4)`. **Expansion K is physical A k, not predecessor canonical C k.** Thus a dense model in predecessor canonical-C coordinates must explicitly account for `PI`; it cannot use an identity layout or identity MMA.

`INGRESS_FIELD_MAP.json` enumerates all 2048 bytes of one 8x8x32 window, including lane/register/byte, source address, ISA coordinates, predecessor neuron, load PC and raw uses. `inpview_source.py` is the executable scalar address/guard recovery, not a numerical NN.

All 64 CTAs of a 64x64 address-only grid cover exactly **131072 distinct bytes**, once each. Boundary tests evaluate individual source cells, never replace a full window with padding. Invalid-source zero may subsequently produce nonzero internal attention values through bias/other arithmetic; ingress zero is not a later mask.

## 3. Raw expansion versus both residual forks

Raw words are:

```
r4631,r4633,r4634,r4635 | r4637,r4639,r4640,r4641 |
r4643,r4645,r4646,r4647 | r4649,r4651,r4652,r4653
```

- The exact raw words feed **64 expansion MMA instructions**, beginning at **PC1206**. There is **no input half→FP8 conversion before the first expansion**. No raw-to-half-to-FP8 roundtrip is asserted, even for nonfinite codes.
- Independently, **PC770..817** splits/decode these words using 32 `cvt.rn.f16x2.e4m3x2` instructions. **PC1131..1193** multiplies decoded half pairs by the F16 gamma at slab **8208..8272**.
- Those half results seed the first contraction MMA group **1519..1534**, not expansion. `ARITHMETIC_FORKS.json` traces all 32 half-pair seeds back to the exact raw halfword, decoder, gamma load, and source neuron. It verifies **2048 scalar neuron relationships**: the decoded residual's `PI(k)` equals contraction C channel `8*(n8group)+2*(lane%4)+half`. Raw expansion K and residual C are therefore deliberately different coordinate systems.
- Four hidden32 expansion/contraction chunks are interleaved. Each contraction's half C is carried directly to the next K32 contraction: **48 exact carried C pairs** proved. There is no reset/reencoding of carried residuals.
- Final FFN half results **2491..2506** fork again. **2537..2584** quantizes them for raw QKV. Separately **2946..3008** multiplies the original **unquantized FFN half** by final gamma **20592..20656**; these seed final projection **4685..4692 / 5446..5453**. All 32 half-pair final residual forks are proved; none is reconstructed by decoding quantized QKV input.

## 4. What is and is not ordinary1h reuse

`ordinary__inpview.alpha.json` is the initial **candidate** shape alignment, retaining all exceptions; do not treat its global candidate as proof. `CORE_ALPHA_PROOF.json` is the corrected proof: **4721 exact instructions**, a bijective **5087-symbol alpha map**, explicit operand-position maps, and equality of **4724 projected CFG edges**. All **256 MMA instructions and every A/B/C/D register position** are included.

Exact ordinary→base core ranges:

| Ordinary PCs | Base PCs / rule |
|---|---|
| `[178,3382)` | `p+591` |
| `[3382,4110)` | `p+599` |
| `[4113,4116)` | `p+596` (Y guard reordered) |
| `[4116,4132)` | `p+599` |
| `[4132,4902)` | `p+603` |

All exceptions are explicit:

1. Ordinary `[0,178)` versus base `[0,769)` is replaced ingress/address setup. Ordinary uses four weak `.cg` vector loads of 16B/lane with 4x4 tile guards; base uses sixteen 4B/lane loads with per-pixel source guards, overrides and singleton broadcast. Ordinary's four zero-construction F32→half→FP8 sequences are absent in base, which uses integer zero.
2. Logical `H/4,W/4` truncation moves from ordinary `[19,27)` to base `[3973,3981)`; source dimensions must not replace output dimensions.
3. Ordinary `[4110,4113)` recomputes Y origin; base already computed it in `[762,765)`. The final add swaps its two sources; integer addition is commutative modulo2^32.
4. X guard0 moves from ordinary `[41,44)` to base `[4712,4715)`.
5. X guard1 moves from ordinary PCs `68,80,81,82` to base `[4731,4735)`.
6. Y guard0 is scheduled before these newly computed X guards in base.

The mapped arithmetic, F16 operations and constants, clipping/cubic activation, quantization placement, norm half reduction trees, F32 approximate RSQRT/RCP, Q scale order, V transpose, attention bias, score/probability/PV, private query halves and final projection are **instruction-identical modulo the proved alpha map**. This is stronger than counting opcodes; it is not an independent hardware rounding validation.

Both base and ordinary have **zero shared-memory operations, zero CTA barriers, zero backedges**. Base has 28 conditional branches/57 CFG blocks; ordinary has 12 conditional +8 unconditional branches/33 blocks. All paths have exactly **256 MMA** instructions; no arithmetic loop is hidden by static counting. Warp synchronization remains: 256 `mma.sync`, 104 `shfl.sync`, and 32 `movmatrix.sync` instructions in each source. Zero shared/CTA barriers does **not** mean synchronization-free native behavior.

**Permitted reuse conclusion:** reuse only the proved register-level ordinary arithmetic core with this exact ingress/coordinate adapter, the own block1 slab, and unchanged source precision/warp semantics. This does not authorize blindly feeding A into an ordinary packed-C loader, reusing another block's learned values, or treating an existing high-level ordinary NN as accepted block1.

## 5. Slab and output field recovery

Own block1 slab size **20672B** and SHA `0270fb8f406d3d0a916953ddaf6ec5d29328fe95b9d6cb408ca0c25c91108e3a` are **packet metadata only**; the slab bytes were not read. Address roles are independently derived from PTX:

| Bytes | Meaning |
|---|---|
| 0..4096 | raw FP8 expansion 128x32 operand matrix |
| 4096..8192 | raw FP8 contraction 32x128 operand matrix |
| 8208..8272 | F16 FFN gamma32 |
| 8288..11360 | raw FP8 Q/K/V operand matrices |
| 11360..15456,15456..19552 | two F16 query32 x key64 bias halves |
| 19552..19556 | F32 Q scale |
| 19568..20592 | raw FP8 final projection32x32 |
| 20592..20656 | F16 final gamma32 |

Unreferenced gaps/tail total60B: `[8192,8208)`, `[8272,8288)`, `[19556,19568)`, `[20656,20672)`. F16 checkpoint container metadata does not turn raw FP8 weight fields or F32 scale into F16 tensors.

`FIELD_MAP.json`: 107 slab-load sites, every lane's exact offset, **20612 referenced bytes** bounded by20672. `SLAB_NEURON_MAP.json`: **12288 raw weight bytes** bijectively mapped to their field's ISA operand `(n,k)`, plus **4096 F16 bias elements** bijectively mapped to `(query,key)`. Those matrices are not assumed row-major. General B coordinates: `k=4*(lane%4)+16*breg+byte`, `n=lane//4`; C/D coordinates: `m=lane//4+8*register`, `n=2*(lane%4)+half`. `ARITHMETIC_FORKS.json` contains all 256 A/B/C/D tuples and producer PCs. This is source/ISA provenance, not an MMA execution.

Output is ordinary packed C, with actual store PCs **4730,4747,5490,5503**. Let `tx=trunc0(ox/4), ty=trunc0(oy/4), ht=trunc0(H/4), wt=trunc0(W/4)`; output tile `(dx,dy)` uses:

```
valid = ox > (-8 if dx else -4) and tx+dx < wt \
    and oy > (-8 if dy else -4) and ty+dy < ht
address = O + 512*((ty+dy)*wt + tx+dx) + 16*lane
```

Each valid lane store is16B with exact source register packing, not identity neuron order. `/4` is truncation towardzero (e.g. -7→-1), not Python floor division. Nonmultiple-of-four dimensions are not rounded up here. 192 address/store checks include negative origins and nonmultiple sizes and agree with ordinary source predicates.

## 6. Host/native/tilesync limits

The supplied, actually read `pre_post_host_report.md` reports conditional static routing: pre primary O0/+248→block1 input0/ABI0, pre secondary O1/+216→post skip, factory block1 unshifted INPVIEW, and Swin forward `0x1800637b0` choosing normal S+8 versus gated alternate S+38. Its initializer report identifies base and tilesync FP8 candidates. **These are prior report statements, not DLL bytes freshly checked by this worker.** Neither historical name nor static initializer establishes a live FP8/base/tilesync handle.

No PE/DLL bytes were read, loaded or executed (PE scan/window usage0). No fresh launch block dimensions, allocation extents, aliases, producer-consumer device visibility, native precision/NaNs, or live dispatch are established. Lane/fragment checks describe a 32-lane warp; they do not establish a live one-warp-per-CTA launch. Tilesync's extra26 instructions have **not** been recovered here; no equality or synchronization claim is made for that entry.

## 7. Verification and exact source-input reads

Successful commands, all cache-only after initial bounded ingestion:

```
PYTHONDONTWRITEBYTECODE=1 python out/recover_static.py
PYTHONDONTWRITEBYTECODE=1 python out/verify_static.py
PYTHONDONTWRITEBYTECODE=1 python out/verify_forks.py
```

PASS: 5505/4902 instruction counts; exact alpha/projected CFG; 134 geometry/origin/override cases, 4288 lane cases, 68608 source quartets; 131072 unique full-grid address bytes; 74688 boundary-test source-zero bytes; all memory and fork coordinate checks. **These are address/static checks, not activation/output or numerical model comparisons.**

Exact external/source input paths actually read (and no others):

1. `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-encoder1h-main-20260912/01-inpview/PACKET.json` — first read, limit2000.
2. `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-encoder1h-main-20260912/01-inpview/in/inpview.ptx` — initial lines1..1200; three full bounded ingestions, eight chunks each (two failed parses, one retained cache).
3. `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-encoder1h-main-20260912/01-inpview/in/pre0_output_basis.json` — lines1..600 only.
4. `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-encoder1h-main-20260912/01-inpview/in/ordinary_results.md` — bounded limit400.
5. `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-encoder1h-main-20260912/01-inpview/in/pre_post_host_report.md` — bounded limit500.
6. `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-encoder1h-main-20260912/01-inpview/in/ordinary.ptx` — one full ingestion in seven <=2000-line chunks.

Total **36 bounded source-input reads**. Generated-output cache/proof reads are separate and confined to `out/`; their dependencies are declared in the static scripts. `INPUT_READS.json` records the budget including failures; `PROGRESS.md` preserves all failures and follow-up scope. No input mutation, network, DLL loading, compilation, GPU/CUDA/Wine, deployment/gate changes, nested agents, or full numerical prediction occurred. All generated files are under the authorized `out/` directory.
