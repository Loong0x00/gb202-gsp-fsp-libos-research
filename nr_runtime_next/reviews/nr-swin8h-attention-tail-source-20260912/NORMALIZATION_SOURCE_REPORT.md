# Swin8h Q/K normalization → seeded QK MMA (source-only)

## Main notification

The Q and K paths are two distinct 32-register projected slices, both reduced and normalized in half-pair arithmetic.  Q alone receives a subsequent per-`tid.y` scalar half scale.  Their FP8 packs are the A/B operands of the 32 seeded MMAs at original 10685–10905.  V is the remaining projected slice and is transposed then FP8-packed, rather than entering those QK MMAs.

No axis/tensor-layout claim is made: the statements below are direct register/dataflow facts.

## Projected-register partition established by later operands

For each of four source groups `t=0..3`, define these ordered eight-register (16 half-component) lists:

| t | Q list `Q[t]` | K list `K[t]` | V list `V[t]` |
|---|---|---|---|
| 0 | 6030,6029,6028,6027,6026,6025,6024,6023 | 6022,6021,6020,6019,6018,6017,6016,6015 | 6014,6013,6012,6011,6010,6009,6008,6007 |
| 1 | 6006,6005,6004,6003,6002,6001,6000,5999 | 5998,5997,5996,5995,5994,5993,5992,5991 | 5990,5989,5988,5987,5986,5985,5984,5983 |
| 2 | 5982,5981,5980,5979,5978,5977,5976,5975 | 5974,5973,5972,5971,5970,5969,5968,5967 | 5966,5965,5964,5963,5962,5961,5960,5959 |
| 3 | 5958,5957,5956,5955,5954,5953,5952,5951 | 5950,5949,5948,5947,5946,5945,5944,5943 | 5942,5941,5940,5939,5938,5937,5936,5935 |

Each listed register is 32 bits holding **two f16 components**, so each list is 16 f16 components per lane.  The projection MMAs write the encompassing registers at 07320–07652.  Q’s lists alone feed its square/reduce path (07670–09006); K’s lists alone feed the second such path (09124–10327); V’s lists alone feed `movmatrix.sync.trans` (10329–10422).  Thus Q/K/V identification comes from actual subsequent operands, not from an assumed output axis.

## Exact per-list half reduction and reciprocal square root

For either `P=Q[t]` or `P=K[t]`, write `p_i=P[i]` for `i=0..7`; every expression below is an `f16x2` operation, hence applies independently to the low and high 16-bit lanes until the final swap.

```
a_i = mul.f16x2(p_i, p_i)                                  # i=0..7
u   = add.f16x2(add.f16x2(a_2,a_6), add.f16x2(a_0,a_4))
v   = add.f16x2(add.f16x2(a_3,a_7), add.f16x2(a_1,a_5))
U_l = add.f16x2(u_l, shfl.bfly(u, 2)_l)
E_l = add.f16x2(U_l, shfl.bfly(U, 1)_l)
D_even,l = add.f16x2(E_l, swap16(E_l))
D_odd,l  = same tree starting from v
```

`shfl` has clamp/segment operand 31 and active-mask operand -1; the two butterfly distances are 2 then 1 (08011–08039).  This is a four-lane butterfly subgroup reduction, not a whole-warp reduction.  `swap16` is the explicit `mov.b32 {rs_hi,rs_lo}`; the final add therefore sums **both f16 lanes** and packs that result back into both f16 lanes of the resulting 32-bit pair.  The same tree is repeated for each `t`: Q result pairs are `r3417/r3420`, `r3428/r3430`, `r3438/r3440`, `r3448/r3450` (07894–08216); K result pairs are `r3780/r3782`, `r3790/r3792`, `r3800/r3802`, `r3810/r3812` (09348–09661).

Before RSQRT, each component is floored with `max.f16x2(D, F)`.  `F` is built once by interpreting raw decimal immediate `948045311` as the source f32 input to `cvt.rn.f16.f32`, then duplicating that resulting half into both 16-bit lanes (08219–08233).  This report deliberately retains that decimal raw immediate and calls it a max floor only; it does not assign it an unverified named-operator meaning.

For every resulting pair, source forms the two scalar f32 inputs separately:

```
fl = cvt.f32.f16(low(max(D,F)))
fu = cvt.f32.f16(high(max(D,F)))
fl = rsqrt.approx.ftz.f32(fl)
fu = rsqrt.approx.ftz.f32(fu)
N  = pack(cvt.rn.f16.f32(fl), cvt.rn.f16.f32(fu))
```

There is no f32 reduction/sum in this sequence—only f16x2 square/add/max, followed by two lane-wise f16→f32 conversions and scalar `rsqrt.approx.ftz.f32`.  Q factors are `3498,3500`, `3508,3510`, `3518,3520`, `3528,3530` (08358–08533); K factors are `3860,3862`, `3870,3872`, `3880,3882`, `3890,3892` (09796–09971).  Within each list, even register indices `p_0,p_2,p_4,p_6` multiply the first factor and odd `p_1,p_3,p_5,p_7` multiply the second (08558–08775, 09996–10213).

## Q scale, then FP8 packing

Q first computes `qnorm_i=mul.f16x2(Q[t][i], N_even_or_odd[t])`.  It then multiplies **all** Q normalized pairs by `S=pack(s,s)`, where `s=cvt.rn.f16.f32(r3537)` and `r3537` was loaded as f32 from `rd11 + 4*tid.y + 754688` (07661–07665, 08779–09005).  Hence the observed order is raw Q → half RSQRT multiply → half scalar-scale multiply → `cvt.rn.satfinite.e4m3x2.f16x2`; it is not safe to commute the conversions/scale.

Each `e4m3x2` conversion produces 16 bits (two FP8 elements); the following `mov.b32` combines two such 16-bit results, so every named pack below is one 32-bit / four-FP8-element fragment:

```
Q-A packs:
3981={3603,3604}  3982={3605,3606}  3983={3607,3608}  3984={3609,3610}
4003={3611,3612}  4004={3613,3614}  4005={3615,3616}  4006={3617,3618}
4037={3619,3620}  4038={3621,3622}  4039={3623,3624}  4040={3625,3626}
4057={3627,3628}  4058={3629,3630}  4059={3631,3632}  4060={3633,3634}
```

Here `{x,y}` means `pack(cvt_e4m3x2(x),cvt_e4m3x2(y))`, not two elements.  Citations: 09009–09119.

## K FP8 packing and QK operand use

K performs raw K → half RSQRT multiply → `cvt.rn.satfinite.e4m3x2.f16x2`, with no `r3540`-style scalar-scale multiply in its source path.  Its 32-bit/four-FP8-element packs are:

```
K-B packs:
3999={3899,3900}  4000={3901,3902}  4007={3903,3904}  4008={3905,3906}
4011={3907,3908}  4012={3909,3910}  4015={3911,3912}  4016={3913,3914}
4019={3915,3916}  4020={3917,3918}  4023={3919,3920}  4024={3921,3922}
4027={3923,3924}  4028={3925,3926}  4031={3927,3928}  4032={3929,3930}
```

Citations: K multiplies 09996–10213; conversions/packs 10217–10327.  The 32 QK MMAs prove the roles: A operand cycles by Q group through `{3981..3984}`, `{4003..4006}`, `{4037..4040}`, `{4057..4060}`, while B operand always runs `{3999,4000}`, `{4007,4008}`, `{4011,4012}`, `{4015,4016}`, `{4019,4020}`, `{4023,4024}`, `{4027,4028}`, `{4031,4032}` (10685–10905).  These are physical MMA fragments; no component-to-logical-axis mapping is asserted.

## V transpose and seeded-QK entry

V receives neither of the shown reduction/RSQRT/scale paths.  Its f16 pair registers are transposed by the 32 `movmatrix.sync.trans.aligned.m8n8.b16` instructions (10329–10422), producing `3931..3962` in the explicit source permutation.  Each result is then converted by `cvt.rn.satfinite.e4m3x2.f16x2` and paired into 32-bit FP8 fragments `4774,4775,4780,4781,...,4802,4803` (10425–10535).  This is the exact transpose-before-FP8 order; its later consumer is outside this bounded view.

After the barrier, `r35=tid.y`; source forms `rd269=rd11+4*(r35<<11)=rd11+8192*tid.y`.  For vector block `j=0..15` and lane `l`, the QK seed-load address is:

```
rd11 + 8192*tid.y + 689152 + 512*j + 16*l
```

and each `ld.global.v4.u32` loads 16 bytes (10537–10682).  Thus one `tid.y` instance spans `[689152+8192*tid.y, 697344+8192*tid.y)` bytes; the correction’s aggregate sixteen-block/warp envelope is not treated as a logical tensor.  These loaded registers occur as the C operands, e.g. first `{3979,3980}`, then `{3985,3986}`, etc., while the normalized packs above are A/B (10685–10905).  Therefore this is entry into **seeded** QK MMA, not zero-C QK MMA.

## Scope / uncertainty

Only the four authorized copied files were read.  No execution, numerical equivalence, tensor axes, softmax, LayerNorm, RMSNorm, or native-kernel behavior is claimed.
