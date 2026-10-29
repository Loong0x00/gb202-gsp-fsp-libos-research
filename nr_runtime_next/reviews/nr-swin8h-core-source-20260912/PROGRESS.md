`upsample-numbered-nonblank.txt` lines 03374-03410 barrier, reset `%rd386` to `%rd11`, and zero `%r5867..%r5898` before the first remaining core MMA loop.

# Remaining-core source recovery (bounded, source-only)

This handoff records source/control-flow facts only. It does not assert a tensor reconstruction, FP16 serialization, numerical equivalence, rounding equivalence, or an interpretation of slab bytes not demonstrated by the cited loads.

## Fixed stage order after the independently proved prefix

1. **First remaining MMA bank**: lines 03411-05886. Shared FP8 is read at four 4096-byte planes; MMA results are held in `%r1933..%r2607` and then are passed through the literal cubic-SiLU-like scalar sequence at lines 04741-05636. The activated values are FP8-quantized at 05659-05769.
2. **Gate/product MMA bank**: lines 05771-05886. It reads the quantized activation registers `%r2649..%r2670`, learned bytes `%r2647..%r2658`, and accumulates in `%r5867..%r5898`. This is the most defensible boundary for the first remaining FFN/MLP result: do not collapse the preceding activation and this bank into a guessed conventional MLP formula.
3. **Post-FFN projection/repack**: lines 05888-07129. The source converts the bank to FP8, writes shared, then runs the `%r5902..%r5933` accumulation loop at 06810-06980 and re-quantizes/re-writes it at 06983-07127.
4. **QKV-sized projection bank**: lines 07130-07660. It initializes `%r5935..%r6030`, runs the `%r6030..%r5935` MMA loop, and then uses its register groups in reductions/normalization and attention preparation. The three-way label is a size/control-flow observation, not a decoded matrix-axis claim.
5. **Normalization / attention**: scalar reduction and RSQRT sections begin 07665; QK-style MMA starts 10685; the exp-like affine/clamp/table sequence begins 10911; tree reductions and reciprocal start 12028-12371; reciprocal-selected weighting is multiplied at 13318 onward. The weighted-value MMA/repack bank is 13987-15134.
6. **Final projection and output serialization**: the last MMA loop is 15137-15311; FP8 conversion and the four guarded global-store quadrants are 15313-15495.

## Exact source address equations and loop extents

Let `t=%tid.y` (0..7), `l=%laneid` (0..31). “`+16*l` then a v4.u32 load” means a 16-byte load beginning at that address. These are byte addresses relative to slab pointer `%rd11`; the listed ranges are source-load envelopes, not proof of a logical matrix shape.

### A. First remaining bank (the first FFN-side bank)

- Setup: `%rd6=32768*t` (03376), `%rd386=%rd11` (03378), counter `%r5899=0` (03377).
- Loop has `q=0,1,2,3`: `%r5899 +=32`, continue while old `%r5899<96` (05882-05886). `%rd386 +=1024` per trip (05883).
- In each trip, `%rd125=%rd386+32768*t` (03451-03453). The four shared A fragments are `shared +16*l + {0,4096,8192,12288}` (03413-03446); later groups use those same four plane bases plus `{512,4608,8704,12800}`, …, `{3584,7680,11776,15872}` (03579-04737). These are the eight source tile coordinates in shared byte space: `a=0..7`, base `512*a + 4096*b`, `b=0..3`.
- Learned B load starts are `(%rd11 +32768*t +1024*q) +16*l + 512*j`, `j=0..63` (visible as 03455/03462, then the repeated 4096-byte A-plane groups through 04624). Therefore the exact contiguous envelope is **[0,262144)**: minimum `t=q=l=j=0`; maximum load starts at `229376+3072+496+29184`, and the 16-byte vector ends at 262143.
- MMA tile shape is literally `m16n8k32`, row/col FP8-to-F16. First-tile witnesses: 03467-03491 (`A={%r1893..%r1896}`, B pairs `%r1897/%r1898` … `%r1903/%r1904`, zero C `%r4834`). The next source tile base is shared +512 at 03579-03612. Do not substitute a guessed row/channel axis for these byte coordinates.
- Scoped execution corroboration only: `MMA_INDEX.json` PCs 2720-2735 list this bank’s first 16 MMA instructions and 32 full-8x8 calls each. Those counts agree with source loop structure but do not identify tensor axes.

### B. Literal activation and learned gate

- Raw decimal immediates must remain raw: `-1065353216`, `1082130432`, `1063583744`, `1055195136`, `-1117454336` at 04743-04775. For each input register the instruction order is `min(x, %r2386)` → `max(..., %r2388)` → `abs` → `fma(%r2390,abs,%r2392)` → `fma(clamped,...,%r2394)` → `mul(x,...)` (04779-04800; repeated through 05636). This documents the order without decoding or swapping positive addends.
- The gated learned vectors are read after `%rd157=%rd386+4096*t` (05643) at offsets `+262144` and `+262656`, each with `+16*l` (05642-05656). Since `%rd386` has advanced by 4096 on loop exit, their aggregate load envelope is **[262144,295424)**. The source does not justify assigning a named gamma/beta or a conventional matrix shape.
- The activated values are quantized before this bank (05659-05769), then lines 05771-05879 perform 16 MMA instructions with A fragments `%r2649..%r2670`, B `%r2647..%r2658`, and persistent C/D `%r5867..%r5898`. PC 3356 onward in `MMA_INDEX.json` records the same A/B/C register roles, each with 32 full-8x8 calls.

### C. Post-FFN projection/repack

- Shared source A is read from `shared +16*l + {0,4096,8192,12288}` at 05888-05920; it is decoded to F16 at 05922-06032.
- `%rd387=%rd11+4096*t+295424` (06807) and loop counter `%r5901` runs `q=0..7` (`+=32`, old `<224`, 06975-06980). `%rd387 +=8192` and the shared A base `%r5900 +=512` each trip (06976-06977).
- B loads in a trip are `(295424 +4096*t +8192*q) +16*l + d`, with `d∈{-512,0}` (06814-06826). The actual envelope is **[294912,360448)**. The overlap of this envelope with the prior load envelope is a source fact; it forbids treating simple contiguity as a tensor proof.
- The 16 MMAs are 06864-06972. `MMA_INDEX.json` PCs 3944 onward gives the A/B/C register witnesses and 64 full-8x8 calls each. It is scoped execution evidence only.

### D. QKV-sized projection bank

- After the shared write/barrier at 07100-07129, `%rd388=%rd11+3072*t+495104` (07130-07132). `%r6031` runs `q=0..7` (`+=32`, old `<224`, 07655-07660); `%rd388 +=24576`, shared base `%r5934 +=512` each trip (07656-07657).
- Six B vectors are loaded at `(495104+3072*t+24576*q)+16*l+d`, `d∈{-2560,-2048,-1536,-1024,-512,0}` (07267-07317). The exact aggregate load envelope is **[492544,689152)**.
- A fragments are shared offsets `{0,4096,8192,12288}` (07232-07264). The literal MMA bank starts 07320 and continues through 07652; it has the 48 accumulator registers `%r6030..%r5935` initialized at 07135-07229. `MMA_INDEX.json` PC 4183 onward exposes the accumulator/A/B role ordering and has 64 calls per shown PC.
- The source-backed byte-size observation `689152-492544=196608=3*65536` supports calling this a three-part/QKV-sized slab. It does **not** prove Q, K, V axis order, head order, or a tensor reshape.

## Scalar order after the QKV-sized bank

- Lines 07665-08061 square selected `%r6030..%r5951` values and reduce pairs with `add.f16x2`, then shuffle-add with masks 2 and 1. Lines 08219-08533 clamp each reduced sum with a scalar made from raw decimal immediate `948045311`, then perform F32 `rsqrt.approx.ftz` and F16 RN conversion. Lines 08558 onward multiply the original values by the resulting RSQRT values; lines 08779-09006 multiply those results by the scalar loaded at 07661-07665 from `%rd11 + 4*t +754688`; lines 09009 onward FP8-quantize. This is the demonstrated arithmetic order. It is not safe to rename it LayerNorm/RMSNorm or reorder reductions.
- A second parallel square/reduce/RSQRT/multiply sequence begins 09124 and continues through the `movmatrix` transpose at 10329-10422. The transpose and its following FP8 converts (10425-10535) are part of the source ordering; do not replace them with a reshape assumption.

## Attention-side facts, deliberately narrow

- At 10537-10682, seed fragments are slab loads at `%rd11 +2048*t +16*l + (689152+512*j)`, `j=0..15`. The literal source envelope is **[689152,711680)**. These registers are C inputs for the MMAs beginning 10685 (e.g. 10685-10688 uses C `%r3979/%r3980`), so they are residual/seed positions in the instruction sense; their semantic role is unresolved.
- Attention MMA tile coordinates are 4 A-groups (`%r3981..%r3984`, `%r4003..%r4006`, `%r4037..%r4040`, `%r4057..%r4060`) crossed with eight B pairs (`%r3999/%r4000` through `%r4031/%r4032`), written to C/D pairs `%r3979/%r3980` through `%r4073/%r4074` (10685-10905). The same source section proves nonzero seeds, not an attention-bias tensor layout.
- For every attention result, the literal scalar sequence is FMA with raw decimal `%r4076=1027077105` and `%r4077=1067877303`, then `max` with `%r4078=1065615360`, then `min` with `%r4079=1070129152`, then `shl 5` and integer add `2146992128` (10911-10953 and repetitions). Keep those raw decimal operands; this is not elevated to a named softmax approximation formula.
- The source sums table-derived values in an explicit tree (12028 onward), permutes/reduces across lanes (12139-12343), clamps the denominator by the earlier raw `948045311` value (12345-12356), then uses `rcp.approx.ftz` followed by F16 RN (12362-12371). The subsequent lane-selection code starts 12375 and per-element multiplication starts 13318. Thus the observable order is: affine/clamp/table mapping → explicit sum/reorder reductions → denominator clamp → reciprocal → lane-select → multiply. No rounding association beyond the instructions is claimed.
- The weighted-value MMA/repack sequence is 13987-15134. Its initial C is zero `%r4834` at 13987-13990, whereas its alternating downstream MMA C values are prior results (14001-14207). That distinguishes these zero seeds from the nonzero attention seeds above.

## Final projection and exact output stores

- Final learned B pointer: `%rd389=%rd11+1024*t+755232` (15137-15139). Loop `%r6033` has `q=0..7` (15306-15311), `%rd389 +=8192`, and shared base `%r6032 +=512` (15307-15308). B vectors are `(755232+1024*t+8192*q)+16*l+d`, `d∈{-512,0}` (15143-15157), giving the exact slab load envelope **[754720,820256)**.
- Final A is shared at base `shared +512*t +16*l + {0,4096,8192,12288}` (14213-14246 before the later final bank; the final loop reads the same four planes at 15160-15192). Final MMA lines are 15195-15303; post-loop FP8 conversions are 15313-15406.
- Store coordinate derivation is explicit. Define `Y=%r3`, `X=%r4`, `Wq=%r19`, `t=%tid.y`, `l=%laneid`. First quadrant’s byte address is
  `O + 4*((Y*Wq + X)*1024 + 128*t) + 16*l`
  (15415-15433). The other guarded stores are, respectively,
  `O + 4*((Y*Wq + X)*1024 + 128*t) +16*l +4096` (15436-15450),
  `O + 4*(((Y+1)*Wq + X)*1024 +128*t)+16*l` (15453-15476), and
  `O + 4*(((Y+1)*Wq +X)*1024+128*t)+16*l+4096` (15479-15493), subject to their source predicates. This is an output byte-layout equation; it deliberately does not assign tensor dimensions to packed words.

## Correspondence with `standard-numbered-nonblank.txt`

The same skeleton exists in the standard kernel, with different register names and slab constants:

- Standard’s post-activation projection loop is 03734-03909 (base `295424`, loop 8, shared base `+=512`, slab `+=8192`), corresponding structurally to upsample 06807-06980.
- Standard’s following three-part bank starts 04059-04590 with slab base `363552`, six B vectors at offsets `-2560..0`, shared base `+=512`, slab `+=24576`, corresponding structurally to upsample 07130-07660 (base `495104`).
- Standard’s next scalar square/reduce/RSQRT sequence starts 04595, matching the upsample sequence beginning 07665. This establishes code-shape correspondence only; it does not establish parameter identity or a tensor bijection.

## Rejected / unresolved

- Rejected: deriving a logical matrix orientation, head count, channel count, or named parameter solely from contiguous slab ranges, FP8 packing, shared adjacency, or register numbering.
- Rejected: treating the first bank’s four loop trips as a proved K axis. The source proves `q=0..3`, `%rd386 +=1024`, and the precise addresses; it does not by itself identify `q` as K versus a packed/output traversal.
- Rejected: treating register adjacency as store order. The source’s explicit convert/pack/store chains control serialization.
- Unresolved: exact tensor-axis maps of all MMA operands; logical shapes of the first/gated bank and post-FFN projection; semantic names of the scalar vectors; attention head/window interpretation; logical output channel layout; native rounding/fusion behavior.
