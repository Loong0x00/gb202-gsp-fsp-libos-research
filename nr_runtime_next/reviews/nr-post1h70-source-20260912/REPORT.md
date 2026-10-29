# Block 70 finalpost184 ABI — source-only account

## Scope and identity

The supplied candidate is exactly
`cc_tinlayout_fused_post_block_swin_1h_32_fp8`: **6,805 instructions** and one
**184-byte** parameter aggregate (`POST_SOURCE.txt:1–2`; `PACKET.json`).  The
collector graph label `cc_tinlayout_fused_post_block_swin_1h_32_rgb` is **not**
the PTX entry name.  The named layer slab is F16[10904], hence **21,808 bytes**,
with supplied data offsets 147394850 and 147416658.  This identifies a static
candidate, not a host selection proof.

The graph supplies two ordered primary producers: block 69/layer 0/output 0,
then block 0/layer 0/output 1.  It supplies no source-level semantic names for
the two pointers.  Therefore this report calls them ingress P0/P1 below rather
than claiming an unsupported main/skip naming bijection.  If the graph-order
aliases `main=block69` and `skip=block0` are adopted externally, P0/P1 are the
corresponding first/second ABI positions; that alias is not proven by the PTX.

## Actually loaded ABI roles

The parameter loads, with actual source consumers, are:

| ABI byte offset | Static role proved by use |
|---:|---|
| +0 | P0 base (`%rd2`, lines 14, 97–98): global `ld.b32` ingress. Each load is split into two packed 16-bit values and converted `e4m3x2 -> f16x2` (270–292). Its current byte address is `P0 + 4*(%r90)` (first instance: 89–98), where `%r90` is formed from guarded tile coordinates, `%r10`, and lane-derived `%r88`; this is a four-FP8-byte word address, not a declared dense tensor shape. |
| +8 | P1 base (`%rd3`, line 17): guarded `ld.weak.global.cg.v4.u32` ingress. The first visible group is `P1 + 4*(128*(%r5927+%r24)) + 16*lane` (1175–1185). Thus each valid spatial record has a source-visible 128-FP8-byte stride and each lane brings 16 bytes; the immediate group is 32 lanes × 16 bytes. This supports a 128-byte record, not an asserted semantic channel layout. |
| +16 | output surface/object handle, only consumed by `sust.p.2d.v4.b32.zero` (14124–14126 and 16259–16261). |
| +24 | slab base: loaded, converted with `cvta.to.global`, and used for all reported slab loads (12–13; later reloaded at 1478–1479). |
| +32 | two output/extent bounds words, used in the final store guards (13870–13877). |
| +40 | two tile offsets, used in coordinate construction (15–16, 13856–13868). |
| +48 | two scalar words copied to `%r29/%r30` (1365–1367); `%r29` multiplies learned RGB and `%r30` controls the displayed decode branch. Their host meaning/value is not established. |
| +56 | optional A/TEX handle `%rd4` (1368, 13878; 16006). |
| +64,+72,+80 | A texture-coordinate affine operands, loaded only on the source-present A path (13808–13915; 16038–16045). |
| +88 | optional history handle (13963–13964; 16096–16097). |
| +96 | optional motion/history-related handle `%rd5` (1369) and an AND-gate input (13962, 13970–13973; 16095–16106). |
| +104 | optional blend scalar pointer `%rd7`/`%rd8`; if non-null it is dereferenced before the history conjunction (11962–11963; 13943–13958; similarly 16073–16091). |
| +112,+120…+160,+168,+172,+176 | history coordinate/options and output dimensions, consumed only in the guarded history branch or coordinate setup (13974 onward; 11958–11966). |

P0 is guarded by tile/boundary predicates before the global loads; P1 has its
own separately guarded address calculation.  The source establishes these two
bases, their current address formulas, and their byte granularity.  It does
**not** establish live allocations, pointer values, complete logical tensor
shapes, or which graph producer a host binds to each pointer.

For contrast, the ordinary 1h source has a 96-byte aggregate (`STANDARD_SOURCE.txt:1–2`): it loads base +0 as its ingress, +8 as its FP8 output destination, and +16 as slab (11–15; 11705–11737).  It has no post entry's second ingress, output surface, optional handles, or F16 final head.  This difference is source ABI evidence only, not a deployment recommendation.

## Learned operands and quantization boundaries

All claims in this section follow consumers, not a serialized-F16 name or an
assumed dense reshape.  The roles are kept separate: **raw** means the P0/P1
loads above; **FFN** means the early expand/activation/projection operands;
**QK** means the score MMA plus its C/bias operands; **PV** means the
probability/value MMA chain; **final** means the later FP8 projection; and
**head** means only the terminal F16 K16 projection documented in the next
section.  A scale or C/bias is never relabelled a matrix weight.

* **FFN / early projection region.** The post source loads slab B operands at
  offsets 0, 512, 1024, 1536, …, 7680 and feeds them to
  `mma.sync.aligned.m16n8k32.row.col.f16.e4m3.e4m3.f16` (for example
  2904–3141 and the repeated 4096/4608, 5120/5632, 6144/6656, 7168/7680
  groups).  It converts its f16 results with explicit
  `cvt.rn.satfinite.e4m3x2.f16x2` at the materialization boundaries
  (2921–3031, 4062 onward).  The cubic stage is source-visible
  `min/max/abs/fma/fma/mul` (3145–3204 and repeats), not an inferred generic
  activation.
* **Scales are not weights.** At 545–911 the code loads slab words at +8272
  into `%r205…%r298` and immediately consumes them as the right operands of
  `mul.f16x2`; at 1482 onward it analogously loads +8336.  These are actual
  pointwise scale operands.  The source does not prove an external parameter
  name, a value, or a dense scale tensor.  It also uses other scalar-like slab
  loads (for example +19664 at 9095) in explicit f16 multiplication; they must
  not be silently folded into matrix weights.
* **QK bias is a C operand, not a weight.** The source loads the +11360 region
  (e.g. 11971–12038) and passes `%r3337/%r3338`, then peers, as the C operands
  of QK `m16n8k32 e4m3×e4m3 -> f16` MMAs (12041–12149).  The Q/K operands are
  separately quantized fragments `%r3339…` and `%r4891…`; calling the C region
  a QK weight would be false.  The following f16 affine/clamp/packed-map path
  is explicit: constants and `fma,max,min,shl,add` at 12155–12349, followed by
  ordered f16 reductions and reciprocal approximation (12728 onward and
  12894–12920).
* **PV and final FP8 projections.** Their source operands are likewise explicit
  e4m3 MMA A/B/C lists, with f16 D and repeated satfinite conversions.  In
  particular, the two K32 attention/PV halves are not a single unrounded dense
  operation: source forms f16 partial D words, later converts named fragment
  words to FP8, and reuses those actual converted words in later MMA lists.
  The supplied `ATTENTION_NN.py.txt` is a candidate equation with separately
  declared reciprocal policy; it is not evidence that its assumed slab length
  20,672 or its unshown host inputs are this entry's full 21,808-byte contract.

Consequently the source has several **unquantized forks**: f16 D/register
values are used by subsequent f16 arithmetic or C operands, while explicitly
selected paths are quantized by `cvt.rn.satfinite.e4m3x2.f16x2` before a later
FP8 MMA.  They cannot be replaced with an all-FP8 or all-F16 dense model.  The
ordinary 1h entry does visibly end in FP8 conversion and global FP8 stores
(11650–11737), whereas this post entry continues into f16 head/output work.
That does not prove equality of the shared prefix or authorize a substitute
activation.

Remaining FFN/attention gaps are deliberate: source alone has not proved a
complete logical weight permutation, every semantic layer name, all tensor
axes, a native reciprocal/rsqrt table, native F16 accumulation order, or a
numerical equivalence claim.  The supplied Python candidates are useful
hypotheses but do not close those gaps.

## Actual MMA types and final neuron-to-output path

The post body uses the following source-visible types:

* learned FP8 stages: `mma.sync.aligned.m16n8k32.row.col.f16.e4m3.e4m3.f16`;
* final learned head: `mma.sync.aligned.m16n8k16.row.col.f16.f16.f16.f16`.

The final head is not an FP8 reinterpretation.  It first receives FP16 feature
fragments from the upstream FP8 MMA sequence.  For store path 0, source loads
head B fragments at slab byte addresses `slab + 20784 + 16*lane` and
`slab + 21296 + 16*lane` (13714–13729).  It computes two K16 stages:

```
{r3821,r3822} = MMA({r3805,r3806,r3807,r3808}, {r3809,r3810}, zero)
{r3813,r3814} = MMA({r3815,r3816,r3817,r3818}, {r3819,r3820}, {r3821,r3822})
```

(lines 13732–13749).  Store path 1 uses the independent feature fragments
`r5392…r5426`, the same two slab bases, and the analogous chained F16 MMAs
(15850–15920).  The initial C is the source-created packed FP16 zero `%r5420`
(2896–2900), so this head slice has no source-loaded head bias.

The selector/shuffle code selects live path-0 words into `%r39/%r40`
(13803–13823), and path-1 words into `%r47/%r48` (15939–15959).  These are the
two query/output halves: each has a distinct spatial half/store path, not an
interchangeable duplicate.  Unpacking gives path 0 `%r4676,%r4677,%r4678` as
three learned components and `%r4679` as the fourth/logit (13879–13894);
path 1 correspondingly yields `%r5706,%r5707,%r5708` and `%r5709`
(16007–16022).  The source then applies the logit sigmoid approximation to the
fourth component (14110–14114; 16245–16249), while the first three flow through
optional-source/decode blending and ultimately RGB surface components.  They
are not alpha: alpha is separately initialized/controlled in `%r5947` or
`%r5952` before the four-component surface stores.

There are physically 512 binary16 slots in the two 512-byte head B regions
(32 reduction positions × 16 MMA columns).  Source use, rather than zero-bit
inspection, shows that only columns 0–3 are selected into `%r39/%r40` and
`%r47/%r48`, i.e. **128 live coefficients** for 32→4.  The other 384 physical
slots are not part of the selected RGB/logit path.  The supplied old-head
report's observation that they are zero is not the basis of this conclusion,
and neither the report nor this pass treats them as a newly proved dense head.

The exact B-slot formula recorded by the supplied head source is

```
base = (20784, 21296)[k//16]
lane = 4*(c % 8) + (k % 8)//2
offset(k,c) = base + 16*lane + 8*(c//8)
              + 4*((k%16)//8) + 2*(k%2)
```

for `k=0..31`, `c=0..15`; source selection proves only `c=0..3` reach the
output.  This formula is an actual typed-load/MMA-fragment account, not a
claim that the entire slab is serialized F16.

## Optional TEX/history branches

TEX is optional only where source predicates say so.  A uses +56: path 0
branches around TEX when bounds fail **or** A is null (13878–13915), and path 1
executes TEX only when bounds pass **and** A is non-null (16006–16045).  History
requires the conjunction of decode nonzero, +88 non-null, positive clamped
blend, output bounds, and +96 non-null (13960–13973; 16093–16106), before the
+96/+88 texture instructions.  The blend pointer +104 is separately checked
and may be loaded before that conjunction.

`OLD_NO_TEX_REPORT.md` documents a particular optional null-handle path.  It
is **not** authorization to zero genuine inputs, fabricate activations, or
claim native equivalence.  No source-derived result here assumes those handles
are null; if non-null, their TEX operands and image results remain live
requirements.

The native raw-TEX high-word/handle convention, surface-object ABI/conversion,
and native F16 MMA accumulation behavior remain unresolved.  They are not
fixed by static PTX operands or the old optional-path report.

## Boundaries

No numerical block-70 result, full-NR result, native launch/acceptance, GPU
run, host ABI binding, resource allocation, or deployment/gate modification was
performed.  Open items include the actual variant selector and host ABI
binding, real P0/P1/slab/optional-resource contents, complete semantic tensor
layouts, epilogue host semantics, native TEX high words, surface behavior, and
all native approximate/MMA rounding details.
