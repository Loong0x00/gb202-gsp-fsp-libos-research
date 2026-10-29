# Original image ingress preblock (CPU/static)

## Result / limits

Recovered and executable on CPU: the **264-byte parameter ABI**, all texture/control branches, literal image/noise-to-**64×16 half-feature** shared fill, and original shared/global loads through immediately before the first MMA. Also supplied a named, **nonnative** first-embedding arithmetic policy and exact FP8 register packing, plus the first global output's byte-address formula (not its Swin-produced values).

**Important correction:** the first MMA is **`m16n8k16 ... f16.f16.f16.f16`**, not FP8. FP8 conversion starts only at entry line 1716; the first FP8 MMA is line 1828. The constant-one feature provides an affine/bias input; there is no separate added bias before this first MMA (`C=0`).

The observer log at `nr-static-followup-main-20260911/runs/20260911-123323-observer_on/finalpost-trace-v1.log:5` records **function lookup/creation**, handle `00005555877358a0`, for this preblock in captured module SHA `c11e2e…`. It does **not** record its submission. The two recorded `submission=` events are **postblock**, not preblock, and are before-original-call observations, not GPU completion. Thus **no observed preblock arguments, launch dimensions, or actual texture identities are claimed**. The captured module contains native code and PTX; driver selection of PTX is not established.

Everything here is CPU/static. No GPU, Wine, changed DLL, PTX-version edit or prior-review modification was used.

## Provenance and reproduction

- Exact module: `../nr-ptx-bundle-20260911/modules/module-00-dll-000df0e0.ptx`.
- Entry: `cc_tinlayout_fused_pre_block_swin_1h_32_1_ds_fp8`; extracted unchanged byte slice `[740200,994677)`, starts module line **45630**.
- All line references below are to `preblock-original.ptx` (module line = entry line + 45629).
- `SOURCE_PINS.json` pins original module, observer, upload/byte contracts, prefix half helpers, FP8 primitives/fragment layouts and local PTX ISA.
- Actual `upload_contract.pinned_upload()` gives `block0.layer0.layer`: raw offset **63**, **21696** bytes, upload offset **0**, reserved **22016**. Padding is not read. Payload SHA `5fe2ab86289f7b21253d00368ce7a95f005ec3c8476abd7db22550b918962a5c`.

From this directory:

```sh
PYTHONDONTWRITEBYTECODE=1 python test_ingress.py
PYTHONDONTWRITEBYTECODE=1 python collect_evidence.py
```

`Replay(args264, textures, block0_slab(), approx=explicit_policy).run()` returns raw shared bytes, deinterleaved half bits, before-first-MMA registers, texture call trace and byte read/write trace. Texture callbacks receive **raw f32 coordinate bits** and must return four raw f32 bit patterns. No sampler state is invented. `embedding_exact_rn_policy(replay)` additionally returns first-embedding half matrix, original D register words and FP8 A register words.

## ABI: typed loads, not guessed host C++ names

One `.param .align 8 .b8 ...[264]`. All fields little-endian. `T0..T4` below denote parameter texture-object handles. Semantic descriptions are **operation-derived hypotheses**, not traced Vulkan image bindings. In particular, “sourceColor” and “history/guideColor” have not been matched to actual host resources.

| Offset | Type/use | Operation-derived meaning |
|---:|---|---|
| 0 | u64 T0 | mandatory current/source-color-like texture; XYZ used |
| 8 | u64 T1 | optional previous/guide-color-like texture; XYZ used |
| 16 | u64 T2 | optional displacement/motion-like texture; XY used |
| 24 | u64 T3 | optional depth/selector-like texture; X used |
| 32 | u64 T4 | optional control-mask-like texture; **Y,Z** used; X,W ignored |
| 40,48,56 | f32x2 each | T1 transform: offset, extent, post-scale |
| 64,72,80 | f32x2 each | T2 transform: offset, extent, post-scale |
| 88,96,104 | f32x2 each | T3 transform: offset, extent, post-scale |
| 112,120,128 | f32x2 each | T4 transform: offset, extent, post-scale |
| 136,144,152 | f32x2 each | T0 transform: offset, extent, post-scale |
| 160 | f32x2 | displacement-to-normalized-coordinate multipliers |
| 168 | u32 | T3 selector direction: zero=min, nonzero=max |
| 172 | f32 | base control feature 11 |
| 176 | f32 | base control feature 12 / override fallback |
| 180 | f32 | feature 10, converted once to half |
| 184,188 | f32 each | special-mode override values for features 13,14 |
| 192 | u32 | special control mode flag |
| 196 | f32 | color gain; **added to itself in f32, then converted to half** |
| 200 | u32 bits | noise seed multiplier input |
| 204 | no typed load | unused/unresolved; do not infer a semantic field |
| 208,212 | s32 each | ingress H,W (converted to f32 for coordinates) |
| 216 | u64 pointer | first packed global output |
| 224 | u64 pointer | encoded block0 weight slab |
| 232..239 | no typed load | unused/unresolved |
| 240,244 | s32 each | output-view H,W; used /4 for first output and /2 for second |
| 248 | u64 pointer | second/downsampled packed output; later padding logic also uses it |
| 256,260 | s32 each | second-output allocation/padding extents; not used before first MMA |

The exact typed loads and all texture sites are machine-readable in `EVIDENCE.json`. +168 and +192 are loaded as b64 then split into **integer low word / floating high word**; interpreting either as a pair of floats would be wrong.

For any texture transform with offset `o`, extent `e`, post-scale `s`, PTX computes each axis as `mul.f32(fma.rn.f32(u,e,o),s)`. Whether this denotes normalized sampling, texel coordinates, a subrect, or a specific filtering/address mode remains a host texture-object binding question.

## Image/control preprocessing before MMA

### Pixels, boundaries and noise (lines 12–286)

For block `(bx,by)` and fill index `p=32*tid.y+tid.x`, loop increment `32*ntid.y` while `p<64`:

```
x = 8*bx + (tid.x & 7)
y = 8*by + (p >> 3)
xr = x if x<W else 2*W-x-2
yr = y if y<H else 2*H-y-2
u = div.approx.f32(float(xr)+0.5, float(W))
v = div.approx.f32(float(yr)+0.5, float(H))
```

This is **one upper-side mirror**, not a generic clamp or arbitrary repeated reflection. The reference rejects tiles that would require another reflection. Synthetic tests use block `(32,1,1)` and compare shared-fill equivalence with `(32,2,1)`; neither is a captured preblock launch, nor is the second geometry claimed valid for the complete kernel.

Noise hashes **unmirrored** `(x,y)` and seed `S`, all integer operations modulo 2^32:

```
z = x*(-1918454973) XOR y*(-669632447) XOR S*(-1640531527) XOR 608135816
r = ((z >> ((z>>28)+4)) XOR z) * 277803737
state = r XOR (r>>22)
```

Four rounds start with `t=state*a+b`, `(a,b)` respectively:
`(747796405,-1403630843)`, `(-93469191,1192405134)`,
`(-895109107,568162667)`, `(-2094846927,878960812)`.
For each: `q=((t >> ((t>>28)+4)) XOR t)*277803737`,
`U=float(((q>>30) XOR (q>>8))+1)*2^-24` with original f32 RN boundaries.
The three noise features are Box–Muller-like:
`sqrt(-2*ln(2)*lg2(U0))*cos(2*pi*U1)`, the same radius times `sin(2*pi*U1)`,
and `sqrt(-2*ln(2)*lg2(U2))*cos(2*pi*U3)`, each converted to half.
Constants are literal PTX f32 encodings `3f317218` and `40c90fdb`, and the lg2/sqrt/sin/cos ops are **approx.ftz**, not guaranteed host-libm bits.

### Color and optional reprojected guide (lines 287–544)

T0 is sampled at its transformed `(u,v)`. For each RGB component the exact instruction sequence is:

```
scale_half = H(add.ftz.f32(args.f32[196], args.f32[196]))
color_half = Hmul(Hsub(H(texture_f32), H(0.5)), scale_half)
```

`H` is RN-even half conversion, `Hsub/Hmul` separately rounded half arithmetic. **Do not replace with RGB*2-1, or even an algebraically flattened gain expression.** Example source=0.2, gain=0.75 gives **half 0xb734 = -0.4501953125**, distinct from half-RN of `0.2*1.5-0.75`. Alpha is not consumed.

T1 and T2 are a pair: if either is null, guide features are a bitwise copy of source features and T3 is not sampled.
Otherwise:

1. If T3 is present, sample center and four diagonal neighbors `(u±1/ex,v±1/ey)` in T3's coordinate transform. Scan center, TL, TR, BL, BR; choose **min X when +168=0, max X otherwise**, retaining the prior sample on ties. This is consistent with a depth-neighborhood selector; actual depth identity/reverse-Z binding is unresolved.
2. Chosen normalized displacement is multiplied by `T3.extent/T2.extent`, then applied to the T2 sampling location. If T3 is null, displacement is zero.
3. T2.XY times +160/+164 is added to original `(u,v)`, and multiplied by `(W,H)` to obtain reprojected pixel-center coordinates.
4. T1 uses a **five-tap cross-shaped cubic reconstruction** with merged central weights, not a single bilinear sample and not a full sixteen-tap bicubic gather. Base `b=floor(coord-.5)+.5`; fraction `f=clamp(coord-b,0,1)`. Axis weights are:
   `w0=f²-.5*(f+f³)`, `w1=1+1.5*f³-2.5*f²`, `w3=.5*(f³-f²)`, `w2=1-w0-w1-w3`, `wm=w1+w2`.
   Axis positions `b-1`, `b+w2/wm`, `b+2` are clamped to `[.5,extent-.5]`, normalized by ingress extent, then transformed for T1. Taps are left-middle, middle-top, middle-middle, middle-bottom, right-middle. Products of corresponding axis weights are summed and **renormalized by their sum**. Source-order f32 operations and approximate reciprocal/division matter.
5. Reconstructed T1 RGB undergoes the same separately rounded half normalization as T0.

Tests cover optional-handle short circuits, min/max depth direction, chosen motion coordinates, cubic tap coordinates/weights, and independent five-tap reconstruction away from edges.

### Controls (lines 130–155 and 546–584)

Let `B=args.f32[172]`, `C=args.f32[176]`, `a=args.f32[184]`, `b=args.f32[188]`, `M=args.u32[192]`.

- Unless `M!=0 && T4==0`: feature11=`H(B*(T4.Y if present else 1))`; feature12=`H(C*(T4.Z if present else 1))`; features13,14=`H(-1 if M else 0)`.
- Special `M!=0 && T4==0`: feature11=`H(B)`; if `max(a,b)>=0`, feature12=`H(1)`, feature13=`H(C if a<0 else a)`, feature14=`H(C if b<0 else b)`; otherwise feature12=`H(C)`, features13,14=`H(-1)`.
- Overrides are not used in the T4-present branch. The source has unordered float comparisons; the simplified formulas above describe finite values.

### Shared packing (lines 157–193)

Logical pixel feature vector, raw half components:

```
[noise0, noise1, noise2, 1,
 sourceR, sourceG, sourceB, guideR,
 guideG, guideB, H(args+180), control11,
 control12, control13, control14, 0]
```

For pixel `p` and channel `c`, byte address within the exact **2048-byte shared allocation** is:

```
1024*(c//8) + 16*p + 2*(c%8)
```

Two 16-byte stores per pixel, planes +0 and +1024. Tests verify all 2048 bytes written exactly once, no shared read before initialization, and identical fill across the two tested synthetic thread geometries.

## First MMA, real weight bytes, and first FP8 packing

At entry lines 587–985, barrier then shared load permutation and two 16-byte-per-lane slab loads. For lane `l`, `g=l//4`, `t=l%4`:

```
a = 4*(32*(l//16) + 4*(g%4) + t)
A = shared.b32[a + {0,256,1024,1280}] = r487..r490
slab vector0 = slab[8208+16*l : 8224+16*l] = r491..r494
slab vector1 = slab[8720+16*l : 8736+16*l] = r495..r498
first B = {r491,r492}; C={0,0}
```

First MMA yields `r544,r547`. PTX ISA m16n8k16 half mapping gives A row `m` the **top-left 4×4 tile pixel** `p=8*(m//4)+(m%4)`, columns the 16 features above. Remaining A groups add shared offsets +64 (right), +512 (bottom), +576 (bottom-right). Sixteen f16 MMAs therefore project all 64 pixels to 32 half channels.

The **1024-byte range `[8208,9232)` is 16×32 f16 weights**, not FP8 and not a flat row-major tensor. Natural MMA-column `n`, input feature `k` map to:

```
lane = 4*(n%8)+(k%8)//2
W[k,n] byte offset = 8208 + 512*(n//16) + 16*lane
                    + 8*((n%16)//8) + 4*(k//8) + 2*(k%2)
```

Tests independently match all original loaded words and cover this byte interval without gaps/overlap. No arbitrary input bytes or pool padding stand in for weights.

First D half coordinates for lane `l` are `(g,2t),(g,2t+1),(g+8,2t),(g+8,2t+1)` in each 16×8 MMA tile. For quadrant `q`, eight-column group `j`, rowword `s`, D register is `r(544+24*q+6*j+3*s)`.

Lines 1095–1689 also form a residual branch by multiplying those D words by half scales from **9232+2*n** (32 per-channel scales). **FP8 conversions at 1716 read unscaled D**, not the residual-scaled registers.

First FP8 A words `r643..r646` pack pairs of quantized D words, e.g. `r643 = E4x2(r544) | (E4x2(r550)<<16)`. This induces a nontrivial channel order when decoded as the subsequent m16n8k32 A matrix:

```
n(K) = 16*(K//16) + 2*((K%16)//4) + K%2 + 8*((K%4)//2)
# 0,1,8,9,2,3,10,11,...,16,17,24,25,...
```

The reference returns the original registers rather than pretending this permutation is contiguous conventional channels. Reused pinned FP8 primitives preserve RN-even/satfinite and little-endian byte order. First FP8 input register groups for quadrants are `643..646`, `653..656`, `657..660`, `661..664`.

## First global output byte layout (values not replayed)

First global writes are at lines **12577,12599,14395,14416**, not immediately after the first embedding. The Swin/attention body between is intentionally outside this task's execution reference.

For positive output-view dimensions `H=args.s32[240], W=args.s32[244]`, define `Ht=H//4,Wt=W//4`. For quadrant `(qy,qx)` of the CTA:

```
y=2*by+qy; x=2*bx+qx
if y<Ht and x<Wt:
  address = args.u64[216] + 512*(y*Wt+x) + 16*lane
  store 16 bytes of packed E4M3
```

Each valid output tile is **512 bytes**, with lane0 bytes0..15 through lane31 bytes496..511. This is an exact opaque packed-tile layout; no unproven host tensor/channel naming is imposed. `first_output_store` implements it in the positive, nonoverflow domain. Tests cover byte coverage and clipping. +248 later receives a different two-plane layout with four-byte-per-lane stores and separate edge/padding handling; those values and padding are not replayed here.

## Verification / remaining blockers

`verification.txt`: CPU tests pass. `EVIDENCE.json` contains source pins/locations, complete typed load and texture site inventory, real slab hash, every first-MMA lane byte address and synthetic demo. `synthetic-shared.bin` is explicitly generated from synthetic callbacks/args and real block0 weights; it is **not a GPU capture**.

Exact/discrete claims: parameter offsets/types, literal source execution/control flow, integer hashes/address math, half conversions/arithmetic under stated finite domain, FP8 conversions/packing and fragment layout. Nonnative policies are opt-in and named: `libm_policy` approximates PTX approximate instructions using host libm; `embedding_exact_rn_policy` uses exact K16 sum followed by one RN-half, not measured native accumulation. Plain half/f32 source operation order is retained; native compiler contraction is not emulated. Native texture filtering/addressing/format conversion, approximate-op bits, half MMA accumulation precision/subnormal treatment, real preblock args, and actual T0–T4 image identities remain unresolved. Missing textures, malformed ABI, unmapped/overlapping shared writes, unknown operands and missing approximate policy fail closed.

**Integration handoff:** this advances the model's image input end; it does not duplicate the restored block70 prefix/tail or claim a full-model port. The next exact host-side target is the **264-byte preblock launch argument construction plus texture-object bindings**, not postblock's 184-byte argument capture. Once available, pass actual sampled f32 texture responses (or verified sampler implementations) to this reference; native approximate/first-f16-MMA policy needs separate validation.
