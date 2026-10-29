# Swin8h attention tail: exact source-order report (bounded, source-only)

## Main notification

This report is ready for Main review. It records only observed register/dataflow order from `ATTENTION_TAIL_SOURCE.txt`; it makes no tensor-axis, softmax, numerical, or native-kernel claim.

## 1. Half affine/clamp, then packed-word map

For every shown input pair, the order is **not commutable**:

1. `fma.rn.f16x2 out, in, r4081, r4082`;
2. `max.f16x2 tmp, out, r4084`;
3. `min.f16x2 clamped, tmp, r4087`;
4. raw 32-bit `shl.b32 packed, clamped, 5`;
5. raw signed 32-bit `add.s32 mapped, packed, 2146992128`.

The first literal instance is `r4083=fma.rn.f16x2(r4080,r4081,r4082)`, `r4086=max(r4083,r4084)`, `r4085=min(r4086,r4087)`, `r5049=shl.b32(r4085,5)`, `r4503=add.s32(r5049,2146992128)` (original 10940–10952).  The next instances use `r4089→r4091→r4506`, `r4094→r4096→r4509`, `r4099→r4101→r4512`, etc. (10957–12023); each has the same five-stage order.

The exact raw decimal constant construction is:

* `r4076=1027077105`; `r4081=pack(low,low)` after `cvt.rn.f16.f32 low,r4076` (10911–10915).
* `r4077=1067877303`; `r4082=pack(low,low)` (10918–10922).
* `r4078=1065615360`; `r4084=pack(low,low)` (10925–10929).
* `r4079=1070129152`; `r4087=pack(low,low)` (10932–10936).

Thus the floor is the `max` operand `r4084` and the ceiling is the `min` operand `r4087`; they are half values produced by the listed f32-to-half conversions and duplicated into both half lanes.  `shl`/`add` operate on the complete packed 32-bit word after the half operations—not independently specified half arithmetic.  I do not assign that map a softmax/exponential meaning.

## 2. Denominator reduction, reordering, floor, and reciprocal

The mapped words `r4503,r4506,...,r4692` are first added with `add.f16x2`; the visible add tree deliberately retains half-pair rounding.  For example, the first local branches are

```
r4403 = add.f16x2(r4503,r4509); r4405 = add.f16x2(r4515,r4521)
r4406 = add.f16x2(r4403,r4405); r4407 = add.f16x2(r4527,r4533)
r4409 = add.f16x2(r4406,r4407); r4410 = add.f16x2(r4539,r4545)
r4408 = add.f16x2(r4409,r4410)
```

(12028–12053); the companion branch ends in `r4415` (12056–12081), and the next two groups end in `r4429` and `r4467` (12084–12137 and 12195–12304).  It then uses the lane-id bits in the exact selection/shuffle sequence:

* `p281=(u16(r4403)&1)!=0`; selects `{r4415,r4408,r4429,r4422}` into `r5114..r5117` (12139–12145).
* `p282=(u16(r4403)&2)==0`; makes `r5118..r5121` (12146–12151).
* shuffle index is `r5125=(shl(r4403,2)&28)+(r4403>>3)`; companion indices are `r5125 xor {1,2,3}`; `shfl.sync.idx` applies to `r5118,r5120,r5119,r5121` (12152–12162).
* bit 3 (`p287`) and bit 4 (`p288`) select to `r4432,r4435,r4433,r4438`; three ordered `add.f16x2`s produce `r4436`, then its two 16-bit halves are duplicated and added as `r4439` (12163–12192).

The analogous second half starts at 12306, forms `r4474`, duplicates its halves, and produces `r4477` (12306–12342).  `prmt.b32 r4481,r4439,r4477,0x5410U` is the observed cross-result packing/reordering (12345); no logical matrix interpretation is inferred.

The reciprocal denominator path is precisely:

```
r4482 = pack(s,s), where s = cvt.rn.f16.f32(r3415)
r4485 = max.f16x2(r4481,r4482)
for each 16-bit half h of r4485:
    f = cvt.f32.f16(h)
    f = rcp.approx.ftz.f32(f)
    h' = cvt.rn.f16.f32(f)
r4484 = pack(h'_low,h'_high)
```

(12347–12371).  `r3415` is the direct source operand of the f32→half floor conversion; this bounded tail does not establish its origin or a decimal value.  The denominator floor therefore occurs **before** `rcp.approx.ftz.f32`, and each half converts to f32, receives scalar approximate reciprocal, and rounds back to f16 separately.

`r4484` is then shuffled and half-selected into broadcast half pairs.  The first four are `r4504,r4507,r4510,r4513` (12375–12430), followed by the same signed/index arithmetic pattern for the remaining pairs through `r4693` (12433–13313).  For example the first index path is exactly `r5156=((laneid + ((laneid>>31)>>>30))>>2)` followed by signed correction/masking/subtraction to `r5163`; `shfl.idx r4484,r5163`, then selects either packed half using bit 5 of the corrected index, producing duplicated `r4504` (12377–12401).  The +8 companion produces `r4507` (12402–12423).  The subsequent paths preserve the source offsets (including +16/+24, +32/+40, and +48/+56), rather than a claimed contiguous tensor order.

## 3. Inverse normalization precedes FP8 conversion and PV MMAs

Every shown mapped half pair is multiplied by its selected reciprocal **before** FP8 conversion.  The first products are `r4694=mul.f16x2(r4503,r4504)`, `r4696=mul(r4506,r4507)`, `r4695=mul(r4509,r4510)`, `r4697=mul(r4512,r4513)` (13318–13340); the complete sequence continues to `r4757=mul(r4692,r4693)` (13343–13760).  The nonmonotonic destination order is source order and is retained.

Only afterwards are pairs converted with `cvt.rn.satfinite.e4m3x2.f16x2` and packed.  The first packs are

```
r4758={cvt(r4694),cvt(r4695)}
r4759={cvt(r4696),cvt(r4697)}
r4760={cvt(r4698),cvt(r4699)}
r4761={cvt(r4700),cvt(r4701)}
```

(13763–13789), continuing through `r4831={cvt(r4756),cvt(r4757)}` (13819–13985).  Therefore the reciprocal normalization is before the observed E4M3 conversion and before its first use as an MMA A operand; it is not performed after the PV MMAs.

## 4. PV operand/carry order (physical registers only)

The probability-map E4M3 packs above occur as the A operands of the 32 MMAs at 13987–14207.  The B operands are the pre-existing E4M3 packs `r4774/r4775`, `r4780/r4781`, `r4782/r4783`, `r4790/r4791`, `r4794/r4795`, `r4796/r4797`, `r4798/r4799`, and `r4802/r4803` in the exact schedule below.  These are operand facts, not a statement about axes.

* First A group `r4758..r4761`: B `{4774,4775}` → C `{4834,4834}` → D `{4762,4763}` (13987–13990); B `{4780,4781}` → zero C → D `{4768,4769}` (13994–13997).  A `r4764..r4767` then uses B `{4782,4783}` with C `{4762,4763}` → D `{4991,4993}`, and B `{4790,4791}` with C `{4768,4769}` → D `{4992,4994}` (14001–14011).
* The next two B pairs `{4794,4795}` and `{4796,4797}` again start from `{4834,4834}` into `{4770,4771}` and `{4772,4773}`; A `r4764..r4767` carries them into `{4995,4997}` and `{4996,4998}` with B `{4798,4799}` and `{4802,4803}` (14015–14039).
* The identical two-zero-then-two-carry pattern repeats for A groups `r4776..r4779`/`r4786..r4789` (14043–14095), `r4806..r4809`/`r4812..r4815` (14099–14151), and `r4822..r4825`/`r4828..r4831` (14155–14207).  Each initial pair explicitly uses C `{r4834,r4834}`; each second-stage MMA explicitly receives the immediately prior listed D pair as C.

Thus `r4834` is the observed initial C register pair for these PV partials; this bounded report does not assign it a numeric value.  The named carry registers above are not interchangeable and are not a late reduction.

## 5. Final-projection seed, sources, K-loop, and stores

### Seed source and learned coefficients

After the PV MMA sequence, source loads four shared vectors at

```
shared_storage + 512*tid.y + 16*laneid + {0,4096,8192,12288}
```

into `r4840..r4861` (14211–14246), splits each packed word into E4M3x2 halves, and converts them with `cvt.rn.f16x2.e4m3x2` into `r4896,r4902,...,r4989` (14248–14358).  This is the actual shared-memory content feeding the final-projection seed.  Its prior producer is outside this bounded source excerpt, so it cannot source-only be identified as a particular logical residual tensor.

It separately reads the half coefficient pairs `r4897,r4900,...,r4990` from `rd265+820256+4*index` (14361–14764).  For nonnegative lane IDs, the displayed address arithmetic gives the four physical word offsets

```
820256 + 64*tid.y + 4*laneid + {0,16,32,48},
```

reused in the shown pattern; the source retains the signed-correction instructions, so this simplification must not replace them.  The converted shared pairs multiply those coefficient pairs in f16x2, yielding `r6034..r6065`; e.g. `r6034=mul(r4896,r4897)` (14766–14770), through `r6065=mul(r4989,r4990)` (14983–14987).

These products are the **initial C operands** of the later final-projection MMAs: the first is `D {r6034,r6035}, A {r5772..r5775}, B {r5776,r5777}, C {r6034,r6035}` (15195–15198).  All 32 C registers are analogously self-carried (15202–15303).  Therefore this source is an early f16x2 coefficient-multiplied C seed, not an add after the projection.  Calling it a learned residual or assigning its shared content a model role remains unproven here.

### PV-to-final-projection handoff and K-loop

The PV carried outputs `r4991..r5022` convert to E4M3x2 and pack as `r5025..r5046` (14990–15100), then store at

```
shared_storage + 512*tid.y + 16*laneid + {0,4096,8192,12288}
```

(15102–15134).  `bar.sync 0` is immediately preserved at 15136.

Only after that barrier does the final-projection loop begin.  It has `r6033=0`; each trip loads A as four shared `v4.u32` vectors from

```
shared_storage + 512*k + 16*laneid + {0,4096,8192,12288},  k=0..7,
```

because `r6032` starts as `shared_storage` and is incremented by 512 every trip (14214–14215, 15160–15192, 15306–15311).  These post-barrier shared addresses were populated immediately before the barrier by the stated PV-pack stores using the physical `512*tid.y` writer schedule; the reader uses the stated `512*k` schedule.  No logical correspondence beyond that physical readdressing is asserted.

On the same trip, B is loaded from

```
rd11 + 755232 + 1024*tid.y + 8192*k + 16*laneid + {-512,0}
```

into `{r5776..r5779}` and `{r5780..r5783}` (15137–15157, 15308).  The sixteen MMAs at 15195–15303 use A groups `{5772..5775}`, `{5784..5787}`, `{5788..5791}`, `{5792..5795}` against B pairs `{5776,5777}`, `{5778,5779}`, `{5780,5781}`, `{5782,5783}`, always carrying their own `r6034..r6065` C/D registers.  Then `r6033+=32`, `r6032+=512`, and `rd389+=8192`; predicate `r6033<224` branches, yielding exactly the source values `k=0,1,2,3,4,5,6,7` (15306–15311).  No loop placement or address stride has been inferred from names.

### Final conversion and global stores

After the eighth carried trip, `r6034..r6065` convert to E4M3x2 values `rs1234..rs1265` in the listed interleaving (15313–15406).  Predicated `st.global...b128` stores occur as follows:

* `p392`: `{rs1234..rs1241}` packed into `r5809..r5812`, to `rd7 + 16*laneid` (15408–15434).
* `p394`: `{rs1242..rs1249}` packed into `r5814..r5817`, to `rd7 + 4096 + 16*laneid` (15436–15450).
* `p398`: `{rs1250..rs1257}` packed into `r5824..r5827`, to `rd8 + 16*laneid` (15453–15476).
* `p400`: `{rs1258..rs1265}` packed into `r5829..r5832`, to `rd8 + 4096 + 16*laneid` (15479–15493).

`rd7` and `rd8` are separately derived from the guarded index arithmetic at 15408–15420 and 15453–15463.  This report does not assign their stores logical axes.

## Scope / uncertainties

Only the four authorized copied regular files were read; no commands, searches, execution, numerical calculation, or external lookup was performed.  The source establishes physical register order, instruction rounding/conversion, barriers, and the cited address expressions.  It does not establish the producer identity of the pre-PV shared values used in the final C seed, a named normalization/softmax operator, or any logical matrix axes.  Main should treat `NORMALIZATION_SOURCE_REPORT.md` as the separate pending source-only report identified in the packet.
