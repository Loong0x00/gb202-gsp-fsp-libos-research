# Ordinary Swin8h source handoff

## Pointer ingress (do not assume a logical input layout)

`param_0` is the only feature ingress: `P_in` is loaded at source line 13; `P_out` is `param_0+8` (line 12); the learned-slab base `P_w` is `param_0+16` (lines 16--17).  The first four valid ingress vector addresses, each a 16-byte `v4.u32` load, are:

```
P_in + 4096*(r3*r6 + r10) + 512*tid.y + 16*lane
P_in + 4096*(r3*r6 + r12) + 512*tid.y + 16*lane
P_in + 4096*((r3+1)*r6 + r13) + 512*tid.y + 16*lane
P_in + 4096*((r3+1)*r6 + r14) + 512*tid.y + 16*lane
```

These are literal address consequences of lines 66--78, 120--132, 171--183, and 222--234; `r10/r12/r13/r14` are predicate-selected coordinates, not an inferred tensor layout. Invalid cases synthesize FP8 zero (lines 81--94 and analogous blocks). `r3/r4/r5/r6` are signed floor-divided coordinate/bound values (lines 24--39). Final stores instead use `P_out` (lines 12345--12363).

## Ordinary `P_w` operands/ranges and order

|stage|ordinary byte range / physical B-tile equation|source evidence|
|---|---|---|
|FFN expand|`[0,262144)`|`tid.y*32768` setup at 298--300; old-counter loop increments its B base by `1024` and tests old `r4101 < 96` at 2804--2808 (four trips).|
|grouped FFN|`[262144,294912)`|first B loads are `P_w + tid.y*4096 + 262144 + 16*lane` / `+262656` (2564--2578).|
|FFN mix|`[294912,360448)`; per B tile `294912 + 8192*t + 1024*tid.y + 512*j + 16*lane`, `t=0..7`, `j=0,1`|the first expression is represented as `295424 + 1024*tid.y - 512 + 16*lane` (3734--3755); the loop adds `8192`, increments 32, and tests the *old* counter `<224` (3904--3909).|
|FFN residual gamma|all accessed words are in `[360464,360976)`: `P_w + 360464 + 4*(16*tid.y + 4*q + (lane % 4))`, `tid.y=0..7`, `q=0..3` for the four word groups (the unrolled repetitions supply the remaining packed placements)|the first lane-mod-4 construction is 2956--2970; the `q=4,8,12` base construction is 2991--3048, and the same pattern continues through 3360. This is a 256-half / 128-word accessed set.|
|raw QKV projection bank|`[360992,557600)`; `P_w + 360992 + 24576*t + 3072*tid.y + 512*j + 16*lane`, `t=0..7`, `j=0..5`|represented initially as `363552 + 3072*tid.y -2560,-2048,-1536,-1024,-512,0 +16*lane` (4059--4248); B base adds `24576` and old counter test is `<224` (4585--4590).|
|QK seed/bias bank|`[557600,623136)`|the 16 contiguous `512`-byte B tiles start at `557600 + 2048*tid.y + 16*lane` (7467--7612).|
|Q scale|`[623136,623168)`, eight `f32`: `P_w + 623136 + 4*tid.y`|4591--4595.|
|final projection|`[623168,688704)`; `P_w + 623168 + 8192*t + 1024*tid.y + 512*j + 16*lane`, `t=0..7`, `j=0,1`|represented as `623680 +1024*tid.y -512/+0 +16*lane` (12067--12087); old-counter test `<224` after `+8192` is 12236--12241.|
|final residual gamma|`[688704,689216)`; packed-word addressing is `P_w +688704 +4*(16*tid.y +4*q +(lane %4))`|the `lane %4` construction and first load are 11291--11304; following `or` bases retain that modulo rather than use `lane` (11320--11694).|

The 16 bytes `[360448,360464)` are **not** an ordinary source operand in the inspected code. In particular, the first FFN-gamma load is `+360464`, not `+360448` (line 2970). Thus a claimed 32-byte learned scalar field at `360448` is not source-supported here; it must not be treated as the gamma or shifted with later fields.

## Comparison with the supplied restored-up equations

The supplied equations directly fix:

```
expand       [0,262144)       grouped [262144,294912)
mix          [294912,360448)  FFN gamma +491520 (256 f16)
QK bias      +689152          Q scale +754688 (8 f32)
final matrix +754720          final gamma +820256 (256 f16)
```

Therefore the ordinary and restored-up FFN matrices through `360448` agree in placement, but ordinary FFN gamma is `+360464`, whereas restored-up gamma is `+491520`: delta `131056`. Later directly specified fields have a different delta `131552`:

```
ordinary +557600 bias       -> up +689152
ordinary +623136 Q scale    -> up +754688
ordinary +623168 final B    -> up +754720
ordinary +688704 final gamma-> up +820256
```

This disproves a single constant shift. The restored-up prefix accounts for `131072` bytes from `360448` to `491520`; the remaining 496-byte difference at the FFN-gamma boundary and the 512-byte pre-QKV gap implied by the later anchors require field-specific mapping. The three supplied equation files do not expose a direct restored-up raw-QKV source equation, so this handoff does **not** label that intervening 512-byte area or map it by name. If its 196608-byte raw-QKV bank is required, derive/verify it from its own source operand equation rather than sliding the ordinary `[360992,557600)` bank.

## Scalar/arithmetic reuse hazards

* Both residual gammas seed accumulators before their matrix K loops; gamma is not a post-matrix scale. Ordinary FFN seeding is visible before the mix loop (3365--3583 then 3793--3909), and final seeding precedes the final loop (11699 onward, then 12125 onward).
* The Q scale is `f32` source data, converted to half and applied only to normalized Q; it is not a 256-half gamma (4591--4595). The up equation likewise specifies `count=8, offset=754688`.
* Ordinary normalization uses the half reduction tree, immediate `948045311`, `rsqrt.approx.ftz.f32`, and later reciprocal `rcp.approx.ftz.f32` (5149--5160, 5288--5297, 9292--9301). Attention additionally uses immediate operands `1027077105`, `1067877303`, `1065615360`, `1070129152` (7841--7866). These are operations/order constraints, not slab fields, and blind matrix reuse omits them.
* The modulo is real: scalar-gamma addresses use `(lane % 4)`, while MMA B loads use `16*lane`; warp strides are `1024`, `3072`, or `2048` depending on stage. The loops test their old counters (`<96` or `<224`) before the next iteration, as cited above.

No execution, numerical claim, or non-packet file access was performed.
