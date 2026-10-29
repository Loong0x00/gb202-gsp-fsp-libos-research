# Block0 preblock producer recovery (source-only)

## Scope and result

The authorized source is the 264-byte-aggregate PTX entry
`cc_tinlayout_fused_pre_block_swin_1h_32_1_ds_fp8`.  It is a learned block0 producer with two distinct output-pointer operands: **+216** is the high-resolution packed C32 candidate (the post70 skip candidate); **+248** is its learned, half-reduced/downsampled packed C32 output.  This is operand proof, not an assertion that either is graph port 0 or port 1.

No execution, numerical-equivalence assertion, current-catalogue/module comparison, texture sampling, or host-resource aliasing was performed.

## PTX facts

### ABI, fill, and first learned projection

* `PRE_SOURCE.txt:1-11` declares one aligned `b8 ...param_0[264]` aggregate and the static `shared_storage[2048]`; static storage is not dynamic shared memory.
* `PRE_SOURCE.txt:12-193` computes the bounded fill index `p=32*tid.y+tid.x`, increments it by `32*ntid.y`, and writes two 16-byte stores per in-range pixel.  The source feature address is exactly
  `shared + 1024*(c//8) + 16*p + 2*(c%8)`, for `p∈[0,63], c∈[0,15]`.
  Thus all 64 source neurons are sixteen half inputs, not an implicit 32-channel input.
* The feature order is source-derived: noise[0:3], constant one, current RGB, guide RGB, +180 conditioning half, control halves, and terminal zero.  The input texture callbacks and their sampling/filter/address semantics are **not** established by PTX.
* `PRE_SOURCE.txt:~203` has the first `bar.sync 0`; the later source has another synchronization after the first F16 MMA group.  They cannot be erased.  The padding path contains its own conditional barrier (`PRE_SOURCE.txt:14979-15012` region).
* At `PRE_SOURCE.txt:~587-985`, the only ingress embedding is sixteen `mma.sync.aligned.m16n8k16.row.col.f16.f16.f16.f16` operations.  Its A operand is the 16-half feature vector and its B operand is F16—not FP8.  For input feature `k∈[0,15]` and output neuron `n∈[0,31]`, the exact source-slab byte is

  ```text
  lane = 4*(n mod 8) + floor((k mod 8)/2)
  W16[k,n] = slab[8208 + 512*floor(n/16) + 16*lane
                     + 8*floor((n mod 16)/8) + 4*floor(k/8) + 2*(k mod 2)]
  ```

  This is the source-neuron/weight map; it is not row-major by assumption.  The explicit source loads are the lane vectors at `+8208+16*lane` and `+8720+16*lane`.
* In contrast, post70 has **two later F16 K16 head steps** (per `POST_RESULTS.md`), while this source has the single *input* F16 K16 embedding before its FP8 body.  Do not collapse the source K16 into post70's two K16 head contractions.

### Slab types and forks

The source operands establish a mixed 21696-byte slab, not a homogeneous tensor:

* `[0,8192)` is consumed by the subsequent E4M3 K32 learned projection/FFN operand streams; `[8208,9232)` is the F16 16×32 embedding above; the immediately following half scale operands begin at `9232`; later learned operand streams are loaded from the source ranges beginning `9312`, through the final intervals `[20592,21680)`.  The actual accessed union is `[0,8192)`, `[8208,9296)`, `[9312,20580)`, `[20592,21680)`.  Gaps/padding are not weights.
* The first embedding D half registers fork.  The half scale loads at `PRE_SOURCE.txt:~1095-1689` multiply the unquantized D values for the carried/seeded branch.  Separately, the E4M3 conversions beginning at `~1716` convert the **unscaled D** registers for the EXP FP8 path.  Therefore the FFN seed is not recoverable by quantizing first and decoding, and the FP8 path is not licensed to replace the unquantized seed.
* The source then performs 32→128 expansion, cubic half activation, re-quantization, and four carried, interleaved hidden-K32 contractions (`K=0..31,32..63,64..95,96..127`).  Each contraction has the preceding carried half result as its MMA C operand; it is not one 128-wide reduction with a final residual add.
* Source regions around `PRE_SOURCE.txt:9000-12000` show the successive E4M3 packing, K32 MMAs, half pair arithmetic, butterfly reductions, `rsqrt.approx.ftz`, transpose and re-packing.  The later sequence retains normalization, Q/K/V construction, ordered score/reduction/reciprocal normalization, attention/PV, final learned projection and final C32 E4M3 packing.  These are source operations, not a conventional-softmax substitution.  Approximate `rsqrt`/reciprocal and native MMA accumulation remain policy-dependent/non-native.

### High skip (+216): geometry and C32 basis

For positive output-view `H=args.s32[240]`, `W=args.s32[244]`, the source computes `Ht=floor(H/4)`, `Wt=floor(W/4)` (`PRE_SOURCE.txt:~11970`), tests the four positions `(2*ctaid.y+qy, 2*ctaid.x+qx)`, `qy,qx∈{0,1}`, and stores four 512-byte packed tiles through the pointer loaded from `args+216` (`PRE_SOURCE.txt:~12577,~12599,~14395,~14416`; visible store pattern at `PRE_SOURCE.txt:12000-14000`).  The per-valid-tile byte address is

```text
+216 + 512*(y*Wt + x) + 16*lane,  lane=0..31.
```

Each 512-byte tile is 16 high pixels × 32 E4M3 channels.  With high-pixel `(Y,X)`, define the actual tile-major source neuron index

```text
m = 16*(floor(Y/4)*floor(Wt/4) + floor(X/4))
    + 4*(Y mod 4) + (X mod 4),       c = 0..31.
```

The source fragment/store permutation defines the physical byte as `c_offset(m,c,32)`, rather than the alleged “first store is port 0” rule.  `POST_PREFIX_REFERENCE.py.txt` uses the same explicit `m` equation (`gm`) and the same `ffn.axes.c_offset(gm,c,32)` when it reads its C32 high input.  Hence, **conditionally**, a post70 `skip[h,w,32]` may consume block0 +216 unchanged exactly when

```text
h = Ht,  w = Wt,
post70_skip_byte(Y,X,c) = block0_plus216_byte(c_offset(m,c,32)).
```

This proves basis compatibility by `m,c` equations, not by shape/stride intuition and not by an inferred resample.  It does **not** prove that the current host binds +216 to post70's second neural input; that required alias/binding remains separate.

### Downsample (+248): exact source reduction, geometry, and padding

`PRE_SOURCE.txt:14000-14978` loads `args+248`, selects four source fragment values by lane/shuffle, then performs the source half tree

```text
s01 = RNhalf(s0+s1)
s23 = RNhalf(s2+s3)
avg  = RNhalf( RNhalf(s01+s23) * RNhalf(0.25) )
```

for every packed half pair, before E4M3 conversion.  The witnesses are `shfl.sync.idx` → `add.f16x2 r5086/r5087/r5089` → `mul.f16x2 r5147` and the analogous groups; `1048576000` is the source f32 constant converted to half for 0.25.  This fixes both the 2×2 source-neuron selection and the **half reduction order**.  It is neither a float mean nor a zero/identity downsample.

For positive H,W let `H2=ceil(H/2)`, `W2=ceil(W/2)`.  The four normal stores at `PRE_SOURCE.txt:~14580-14970` form a physical two-plane C32 basis:

```text
D[plane, y, x, c16], plane∈{0,1}, c16∈[0,15]
byte = 16*(plane*H2*W2 + y*W2 + x) + c16.
```

The source lane equations are explicit: `y=4*ctaid.y+floor(lane/16)` (or `+2` in the lower pair), `x=4*ctaid.x+(floor(lane/4) mod 4)`, `c16=4*(lane mod 4)+byte-in-v2.b16`; plane 1 is addressed by `y+H2`.  Thus +248 is a 32-channel learned downsampled producer with its own plane/interleave basis, not a raw first half of the +216 stores.

The source does not erase edges.  It first permits normal stores only under the per-coordinate bounds predicates.  It then loads allocation/padding extents `args+256/+260`; the branch at `PRE_SOURCE.txt:14979-15012` returns only when `+248==0` or both extents are within `(ceil(H/2),ceil(W/2))`.  Otherwise the original `nctaid`/thread-indexed loops and conditional barrier write zero padding only outside the valid downsample rectangle (`PRE_SOURCE.txt:15013-15334`).  Their complete geometry depends on launch builtins (`nctaid`, `ntid`, `tid`); do not replace those loops or barriers with a guessed padding fill.

## Binding boundary (not inferred from stores)

PTX proves parameter **field** +216 is the high packed output and +248 is the downsampled packed output.  It does not name graph ports or prove resource aliasing to post70.  `OLD_BINDING_REPORT.md` separately gives a historical host launch/routing proof for the preblock aggregate, while `POST_RESULTS.md` separately gives post70's input-vector ABI.  Neither first/second store order nor pointer offset alone establishes a current composition.  Required separate host proof is: current preblock +216 allocation/view aliases the post70 C32 input view, has the conditional `(Ht,Wt)` dimensions above, preserves `c_offset(m,c,32)`, and has correct lifetime/synchronization.  +248 instead requires the block1 consumer's independently matched two-plane basis.

## Remaining boundaries

* The source identity is the authorized `PRE_SOURCE.txt`; `PACKET.json` says it is an old exact-entry slice.  I was not authorized to read a current module/catalogue, so current-module equality remains unverified.
* Texture identities, formats, filtering, addressing, normalized-coordinate interpretation, and image/resource contents remain host/sampler boundaries.  Missing texture inputs are not replaced with zero resources.
* The first-call host gate is explicitly **full 64-bit** counter at aggregate +200: it nulls temporal T1/T2/T3 when zero.  The PTX noise hash uses only the low 32 bits loaded from +200; at `2^32` the noise seed wraps without re-enabling the first-call gate.  This distinction remains required.
* The source noise `div/rcp/lg2/sqrt/sin/cos` and learned `rsqrt/rcp` approximate instructions require an explicit nonnative policy; no host-libm/native-bit claim is made.  Native F16/FP8 MMA accumulation order, intermediate precision, FTZ/subnormal and signed-zero behavior are likewise unproved.

## Exact authorized paths read

1. `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-pre1h0-source-20260912/PACKET.json`
2. `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-pre1h0-source-20260912/PRE_SOURCE.txt`
3. `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-pre1h0-source-20260912/OLD_INGRESS_REFERENCE.py.txt`
4. `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-pre1h0-source-20260912/OLD_INGRESS_REPORT.md`
5. `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-pre1h0-source-20260912/OLD_FULL_REPORT.md`
6. `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-pre1h0-source-20260912/OLD_BINDING_REPORT.md`
7. `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-pre1h0-source-20260912/POST_PREFIX_REFERENCE.py.txt`
8. `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-pre1h0-source-20260912/POST_FFN_REFERENCE.py.txt`
9. `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-pre1h0-source-20260912/POST_RESULTS.md`
