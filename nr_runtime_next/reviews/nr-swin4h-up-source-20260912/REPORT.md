# block56 source-only handoff — OWN7235 `cc_tinlayout_fused_swin_4h_128_4_upsample_fp8`

## Binding and byte-format facts

* Parameter bindings are source-visible: `+0 -> %rd1` (P0), `+8 -> %rd13` (output stores), `+16 -> %rd14` (slab), and `+24 -> %rd3` (P24).  `+0` and `+24` are not interchangeable.
* P0 is consumed directly as the A operand of `mma.sync...f16.e4m3.e4m3.f16`: source loads 32-bit words from `%rd1` (FOUR_H_SOURCE 125–136) without an intervening conversion/repack. Thus the consumer requires raw E4M3 bytes at those addressed locations. Its first MMA loop is eight K32 iterations: counter 0,32,...,224; `%rd404` advances 4096 each iteration (72–100, 251–282).
* For lane `l`, the first P0 word address is exactly `4*%r102`, where `%r102=(%r5+%r13)*%r10 + 4*(%r6+%r92)+%r98`; `%r13=l>>4`, `%r92=(l>>2)&3`, `%r98=l&3`, and `%r10` is the source-built `%r80 & -16` (67–136). The following K blocks retain all source arithmetic: `%r5809 += %r12` and `%rd404 += 4096`. This is the actual operand addressing, not a ratio-derived reshape.
* P24 is independently loaded from `%rd3`. In the first valid neighborhood its byte base is `4*(512*(%r3*%r19+%r22)+128*%r9)+16*l` (565–577); neighboring/padded cases have their own signed/OOB predicate paths. Those words are converted by `cvt.rn.f16x2.e4m3x2` (595 onward), so P24 too is raw E4M3 at the source operand addresses.
* Consequently block55's 16384-byte output can be handed to P0 only as its existing physical byte stream: the consumer performs no canonical-C reinterpretation. Previous block55 proof supplies its `channel16-planar A-basis; physicalk=priorCpi(k)` provenance. Source proves E4M3 direct-consumption and K32 grouping, but does **not** by itself prove a named-axis equality/bijection between its `%r102` map and that prior mapping; do not replace the byte stream or infer axes from equal size/name/adjacency.

## Prefix / learned-skip facts

* First prefix weight loads use slab base `98816-512 = 98304` for the first K block; base expression is `%rd14 + 1024*%tid.y + 98816 + 16*l - 512` (70–100). It is not the 8h base. The learned multiplier is loaded at slab `131328` (877 onward), not inferred from a serialized range.
* Projection accumulators are f16 MMA accumulators initialized from source zero. After the projection's lane/shuffle arrangement, P24 is E4M3-decoded, multiplied in f16 by the `+131328` operand, and added in f16 to the projected value; only then are values `cvt.rn.satfinite.e4m3x2` encoded and placed in shared memory (1272–3374). This establishes late learned-skip placement. Preserve this order, per-K32 f16 accumulation, and FP8 checkpoint.
* Signed coordinate division is truncation toward zero, not floor: e.g. `%r5=(%r1+(%r1<0))>>1` and analogous `%r3/%r4` construction (26–39). All OOB predicates and the signed-byte narrowing path (1719 onward) remain required.

## 4h-specific slab, K-loop, shared/warp witnesses

These are raw source witnesses, not converted dimensions:

* CTA shared storage is 8192 bytes (line 11). A producing warp writes 16 bytes/lane to `%r31 + 16*lane + {0,2048,4096,6144}`, then `bar.sync 0` (3339–3374). Later consumers read the same four slabs (3413 onward). This is CTA/warp ownership evidence; it does not license a guessed tensor axis order.
* Post-prefix MMA family 1 uses `%rd14 + 16384*%tid.y`, then advances its weight pointer by 1024 on counter 0,32,64,96 (3375–34011 and 5218–5222).
* The next source family begins `%rd15+82432`, reads K32 operand pairs around `-512/0`, advances `%rd406` by 4096, and advances the shared address by 512 over counter 0,32,64,96 (6143–6316).
* The following family begins `%rd14 + 3072*%tid.y + 134144`; its six B fragments start at offsets `-2560,-2048,-1536,-1024,-512,0`, then `%rd407 += 12288` over counter 0,32,64,96 (6466–6996). Preserve those bases/strides literally rather than scaling 8h maps.
* Q/K/V/norm source later uses the slab address family `%rd14 + 8192*%tid.y` with fragment offsets 180736 through 184320; its scale load is `%rd14 + 4*%tid.y + 213504` (9865–10049 and 6997–7001). Attention/final-projection operand loads use `+229904` with `%r40=%tid.y<<5` (11560 onward). These identify the 4h operand ranges/order, but no serialized-F16 range was used as proof of axes.
* The two output-store groups are source writes through `%rd13`: first at 12379/12404 and second at 14889/14914, each `b128` per lane with the second half `+2048`. They are FP8 codes made with `cvt.rn.satfinite.e4m3x2`; full output-domain coverage still depends on launch parameters and is not claimed.

## Numerical order and 8h comparison boundary

* Every displayed MMA is `f16.e4m3.e4m3.f16`; source repeatedly applies f16x2 operations and explicit `cvt.rn.satfinite.e4m3x2` checkpoints. Normalization is source `rsqrt.approx.ftz.f32` followed by `cvt.rn.f16.f32` (7694–7870); attention normalizing uses `rcp.approx.ftz.f32` followed by the same f16 conversion (10811–10820). No host/native-equivalence or replacement LUT policy follows from this source-only result.
* Preserve source raw decimal witnesses: activation path uses `-1065353216`, `1082130432`, `1063583744`, `1055195136`, `-1117454336` (4079–4111); norm floor witness is `948045311` (7555–7559); attention affine/clamp witnesses are `1027077105`, `1067877303`, `1065615360`, `1070129152` (10055–10080); packed-map addition witness is `2146992128` (10095–10098). No mental float/half-bit substitution was made.
* The proved 8h source has materially different prefix witnesses: shared 16384 bytes; first prefix base `360960-512=360448`; K counter 0..480 (16 K32 iterations) with `%rd385 +=8192`; and multiplier base `492032` (EIGHT_H_SOURCE 11, 70–100, 278–282, 877–891). Therefore its equations cannot be resized by a guessed factor. The only carried-over claims are those independently visible in the 4h source above (E4M3 MMA, f16 ordering, explicit checkpoints); all 4h offsets/shapes/ranges must remain source-derived.

## Limits / Main action

This is an OWN7235 source handoff only. It establishes argument roles, operand byte formats, actual prefix P0/P24 addressing witnesses, late skip order, K-loop/shared ownership witnesses, and concrete 4h slab bases. It does not establish a host launch, all-grid output bijection, native approximation equivalence, or a complete 4h named-axis model. Main should retain block55's physical bytes verbatim for P0 and only assert byte compatibility at the source operand addresses above.
