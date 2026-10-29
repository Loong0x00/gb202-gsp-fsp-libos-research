# Ordinary4h block 57..60 source-only handoff

## Scope boundary

`PACKET.json` identifies this source as `cc_tinlayout_fused_swin_4h_128_4_fp8`, 4,804 instructions.  The only established incoming tensor is block 56's canonical 16x16x128 result (the packet's stated hash is `742aaa8c…193ec4e`).  The packet graph lists primary edges 56→57→58→59→60; its `aux_input_blocks` collector fields are not a substitute for those primary defaults and do not establish a live extra input.  Block 61 is explicitly the outview layer, not an ordinary output application.

The earlier full shifted-upsample block-56 result (six CTAs, 17,664 MMAs, scalar/origin/two-phase checkpoints) is retained as predecessor evidence only.  Nothing here accepts, executes, or claims a native/full-model result for blocks 57–60.

## Ordinary P0 ingress and source-zero behavior

* The ordinary entry loads pointer P0 from parameter +0 into `%rd1`, output from +8 into `%rd10`, and the slab pointer from +16 into `%rd11` (`STANDARD_SOURCE.txt:12-17`).  Thus P0 is an actual independent ingress in this entry, rather than an inferred view of a slab range.
* The P0 tile origin is formed as `8*ctaid.y + param(+44)` and `8*ctaid.x + param(+40)` (`18-23`).  Its two coordinate quotients, and the two extent quotients, use sign correction before an arithmetic shift (`24-39`).  In particular the computation is `trunc_toward_zero(x/4)`, not `floor(x/4)` or `ceil(x/4)`: for a negative non-multiple it adds 3 before the signed right shift.  This is the required signed bias-and-shift rule.
* On the first of the four gathers, the valid P0 byte address is constructed from `(%r3 * %r6 + %r4)`, a 512-unit tile stride, a `%tid.y` 128-unit term, a `*4`, and a lane `*16` term (`66-76`).  The next three gathers use the corresponding +1 row/column forms (`120-132`, `171-183`, `222-234`).  Treat these as register/address facts only; they do not prove semantic H/W/C axes.
* Invalid samples are materialized as zero converted to finite E4M3 (`81-94`, with the analogous branches `135-148`, `186-199`, `237-250`), then placed in shared memory (`253-289`).  The validity predicates and the special extent cases are source-visible at `41-63`, `96-118`, `150-169`, and `201-220`.

There is no source proof here of a *live* shifted offset for blocks 57, 59, or 60.  The only possible signed offsets visible to this ordinary ingress are the supplied +40/+44 parameters above.  Therefore a shifted source-zero path may be described only conditionally: if those supplied signed origins place a gather out of bounds, the cited E4M3 zero branches are taken.  Layer names, serialized F16, address ranges, a layout bijection, and the packet's table context do not prove a shifted axis or its live value.  In particular, the table's `(0,1),(-1,-1),…` pairs must not be used as live configuration.

## Own slab ledger — preserve bases, strides, and non-uniform gaps

The authorized equation candidates give the following **candidate logical slab ledger** (byte offsets) for this ordinary implementation.  It is useful to preserve the source equations, but is not an axis/consumer proof or acceptance result:

| range / item | candidate source-equation location | loop / role |
|---|---:|---|
| expand weights | 0..65535 | four K32 accumulations |
| grouped weights | 65536..81919 | four groups, each K32 |
| mix weights | 81920..98303 | four seeded K32 accumulations |
| early residual gamma | 131072..131327 | 128 F16 values |
| raw QKV weights | 131584..180735 | 128×384 candidate matrix |
| relative-bias region | 180736..213503 | four-head score seeds |
| Q scale | 213504..213519 | four F32 values, converted to half |
| final projection weights | 213520..229903 | four final K32 accumulations |
| final residual gamma | 229904..230159 | 128 F16 values |
| tail | 230160..230175 | keep distinct; no inferred use |

Do **not** collapse this into an inferred ratio or uniform delta from upsample.  The actual ordinary address generators already have different terms: the first matrix stream seeds `%rd325` from `%rd11`, uses `%tid.y*16384`, and advances the slab cursor by 1024 on a four-iteration `K32` loop (`299-301`, `2141-2145`); the grouped stream is separately based with `%tid.y*4096` and `+65536` (`299`, `1901-1915`).  A later raw stream uses `%tid.y*3072` and `+101152` (`3397-3401`), while another uses `%tid.y<<11` before accesses around `+147744` (`6797-6807`).  Even the interval not named by the candidate FFN map is not safely disposable: a real ordinary load uses `+98320` (`2303-2307`).

The gamma locations above must remain explicit.  They are early-residual gamma at 131072 and final-residual gamma at 229904; neither may be replaced by a guessed slab displacement.  These offsets and the candidate loop boundaries come from `FFN_NN.py.txt`, `QKV_NN.py.txt`, `NORM_NN.py.txt`, and `ATTENTION_NN.py.txt`; their matrix labels are hypotheses until independently consumed/validated.

## Numerical and scalar witnesses

* The first fused nonlinear sequence is half-domain clamp/abs/FMA/multiply logic, with register constants introduced at `1002-1034` and used by the min/max/FMA chain at `1038-1058`.  It is not evidence for a generic host activation rewrite.
* The norm floor constant is introduced from literal `948045311` (`4487-4491`); the reduction floor is followed by half→F32 approximate rsqrt→half conversion (`4626-4651`).
* The score remap has four literal witnesses `1027077105`, `1067877303`, `1065615360`, and `1070129152` (`6987-7012`), then `fma.rn.f16x2`, max, min, packed left shift, and add `2146992128` (`7016-7030`).  The reciprocal side is likewise explicitly approximate F32 then rounded to half (`7743-7752`).
* Quantization boundaries are explicit `cvt.rn.satfinite.e4m3x2.f16x2` instructions (for example `1918-2028` and `9253-9298`).  Do not merge adjacent half accumulations across these conversion points.

## Two-phase tail and required delayed operands

The ordinary tail is genuinely split.  Its first output stores occur at `9300-9343`.  Immediately afterward it repacks and retains `%rs153..%rs168` as `%r2991..%r2994` and `%r3011..%r3014` (`9345-9352`), then launches the following MMA family (`9427-9535`).  Those retained packed operands are required delayed Q/V-side state in the source trace; they must not be recomputed, dropped, or assigned semantic axes merely from their register names.  The final ordinary stores are separately guarded and issued at `11812-11852`.

The upsample source has the same broad two-store/retain shape but not the same tail addresses or registers: its initial stores are `UP_SOURCE.txt:12368-12410`, its delayed packs are `%rs505..%rs520` into `%r4773..%r4776` and `%r4793..%r4796` (`12413-12420`), and its following weight accesses start at `+184832` through `+188416` (`12427-12492`).  Ordinary instead begins its corresponding later access sequence at `+151840` through `+155424` (`STANDARD_SOURCE.txt:9353-9424`).  This demonstrates why a single upsample-to-ordinary offset or ratio is invalid; compare each source-generated base/stride/loop independently.

## Block handoff

* **57:** primary default is block 56; graph label says shifted, but live shift and any auxiliary consumption remain unproven.
* **58:** primary default is block 57 and is the only block in this handoff matching the ordinary entry under review.
* **59 / 60:** primary defaults are 58 / 59 respectively; their shifted labels do not license applying an ordinary output transform or a table-derived shift.
* **61:** outview only; do not apply ordinary4h output handling there.
