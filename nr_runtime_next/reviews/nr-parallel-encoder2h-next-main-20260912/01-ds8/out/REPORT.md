# Block8 actual 2H downsample reconstruction

## Result

**STATIC RECOVERY WITH EXPLICIT CONTRACT HAZARDS — no native/full-NN/numerical acceptance.** Exact supplied entry: `cc_tinlayout_fused_swin_2h_64_2_ds_fp8`, **5823 instructions**, **88-byte ABI**, own **69936-byte block8 slab**. Block9 is the next197184-byte family and was not substituted. Ordinary source has4845 instructions. Model request metadata is `openai-codex/gpt-6-astra`, `xhigh`; runtime model selection is not independently attested here.

The actual learned64→128 down field starts at **61744**, not61760. It consumes the former ordinary trailing16-byte gap and continues to69936. There are exactly **40 unaccessed slab bytes**, not56. Important unresolved source fact: learned output is eight16-byte channel planes using trunc-half H/W, whereas padding is **sixteen** such planes using ABI80/84. Finite executed source-address traces demonstrate overlap for stated mismatched geometries. Do not assume native safety or transplant DS4 padding formulas.

## Own bytes and source proof

- DS SHA256 `a33527193274eba31ec28f38c5a46a38f4f326e2988b658f4a31b9a174420d81`;235717 bytes,13972 lines.
- Ordinary SHA256 `056455261062601c5c690fe16089c37def7ad3da9e1b4a35cdbc0afcd4e49170`;202549 bytes,12737 lines.
- Slab SHA256 `687d906bc5d6748b57ee3e519c114f9382d93db560b7f779461c1ab90f5237ae`.
- Initial parser errors are preserved, not hidden. A second independent source-preserving DS parser matched **all5823 statements, line spans and labels** after correction. Ordinary did not receive a second fresh raw parser within budget.
- DLL was **never opened, hashed, scanned or executed**. Supplied host/inpview reports remain historical context, not current block8 host proof.

## Every field, type and gap

|Field|Slab bytes, end exclusive|Actual payload dtype|Canonical table shape|
|---|---|---|---|
|ff_expansion|[0,16384)|E4M3|[256, 64]|
|ff_contraction|[16384,24576)|E4M3|[2, 32, 128]|
|ff_mixing|[24576,28672)|E4M3|[64, 64]|
|input_residual_gain|[28688,28816)|F16|[64]|
|qkv|[28832,41120)|E4M3|[2, 3, 32, 64]|
|score_bias|[41120,57504)|F16|[2, 64, 64]|
|q_scale|[57504,57512)|F32|[2]|
|attention_output|[57520,61616)|E4M3|[64, 64]|
|attention_residual_gain|[61616,61744)|F16|[64]|
|down_projection|[61744,69936)|E4M3|[128, 64]|

Only gaps: `[28672,28688)`, `[28816,28832)`, `[57512,57520)`. No trailing gap. Transport `ld.b32`/`v4.u32` and F16 container metadata are not payload types: E4M3 fields feed E4M3 MMA B, gain pairs feed half multiplication, score bias feeds half C, scale feeds F32 arithmetic. Own scale values are **[0.9432693719863892, 6.546261787414551]**; this is parameter decoding only.

`FIELD_MAP.json` gives every scalar's explicit byte formula and own-output canonical byte/offset-table paths. Ten field tables are byte-bijective, disjoint, and together cover69896 bytes. All133 slab-load sites are traced over64 lanes and actual two-trip loops; whole accesses stay within own slab. **188416 MMA B scalar mappings and8192 score-bias C half mappings** independently agree with PTX lane fragments. Common matrices intentionally use explicit **MMA-native K / tiled token axes**, rather than asserting all of them are ordinary row-major neuron tensors. The down field additionally has proven pooled-neuron channel axes.

## Full MMA count, not a static count mistaken for execution

All312 static sites use `mma.sync.aligned.m16n8k32.row.col.f16.e4m3.e4m3.f16`.

|Phase|Static sites|Visits/site|Dynamic collectives/warp|
|---|---:|---:|---:|
|FF expansion/contraction/mixing body|112 =64+32+16|2|224|
|QKV, QK, PV, attention output|192 =96+32+32+32|1|192|
|Down projection|8|2|16|
|Total|312|mixed|**432**|

Conditional compatible two-warp CTA: **864 collectives**, not per-lane records counted as independent MMAs. Ordinary dynamic count is416/warp. FF induction is0 then1; copied predicate is initially true, set false at the tail, so exactly two visits. Down induction is0 then64 with the same copied-predicate two-visit idiom. New loop is **output-channel tiling**; its two K32 carries are separate static MMA groups inside each visit. Padding adds geometry-dependent scalar clearing loops but no MMA. Complete source CFG retains out-of-line, remainder and four-way-unrolled loop bodies.

## Common core alpha/CFG closure and exceptions

One ordered injective token map pairs **4843 ordinary prefix instructions** with DS; final ordinary barrier/ret are not paired to the DS suffix. DS has exactly two extra ABI loads12–13 and one extra `cvta.to.global` at12086 in that comparison.

Strict alpha is **rejected**:22 token conflicts at19 instructions. Source23/25 (ingress) and10367 (core) commute `add.s32` sources, exact modulo2^32. Sixteen pointer additions at12088–12274 use a fresh `%rd327=cvta(%rd9)` instead of mapped `%rd232=cvta(%rd9)` from5181; the source pointer is unchanged. Both exact conversion definitions and all sixteen replacements are checked separately. This is an alias/recomputation proof, not a many-to-one "injective" renaming. After these explicit exceptions, every paired instruction agrees; all21 paired branches preserve targets and order. New DS CFG is retained separately, **not** declared ordinary-alpha-equivalent.

## Ordered half boundaries and three distinct forks

Let `Hmul/Hadd/Hfma` denote the **actual half operations**, `Q8` the source `cvt.rn.satfinite.e4m3x2.f16x2`, `D8` the source decode, and `MMA32(A,B,C)` the opaque native-policy f16-D MMA. No identity or numerical stand-in for MMA is used.

1. Ingress FP8 is decoded to half. **Input residual** is `Hmul(D8(input),gain_input)` (750–956), initializing mixing C registers before the FF loop. The expansion path re-encodes decoded input, uses two K32 carries; its cubic activation retains half min/max/abs, two half FMAs and half multiplication, then Q8. Contraction accumulates four K32 contributions per loop; its Q8 result feeds mixing. Mixing's two loop visits carry the existing half residual C rather than appending a separate final float residual add.
2. The FF result is Q8 at4176–4284 and written to shared4096 bytes. QKV uses this **quantized FF state**. The attention residual at9667–10054 /12000–12385 loads that FP8 state from shared, **decodes it again**, and Hmul-scales it by gain_attention. It is not the earlier unquantized FF accumulator.
3. Attention retains source Q/K normalization, F32 scale, half learned score-bias C, score/exponent/normalizer policies and PV carries. PV half outputs are Q8 before the learned attention output projection (10058–10112 /12389–12443). The output projection initializes C with the separately rounded half attention residual, then preserves **two ordered K32 carries**. The result `Z_half` is `%r2952..2967` (top) and `%r3942..3957` (bottom).
4. **Skip fork:** Q8(`Z_half`) at10318–10363 /12647–12692, stored to ABI+8. **Pooling fork:** source12738–13100 consumes the original `Z_half` registers, not their quantized skip bytes and not a skip reload. For each actual shuffled four-tuple `(a,b,c,d)`, it performs `s0=Hadd(a,b); s1=Hadd(c,d); s2=Hadd(s0,s1); pool_half=Hmul(s2,half(0.25))`. These are four distinct half boundaries. No float32 sum, average-before-add or post-quantized pool substitution is justified.
5. The1024 source-derived neuron trees each cover an exact2×2 spatial neighborhood and one channel. **The operand ordering is not uniformly TL,TR,BL,BR**: lane-dependent shuffle/select routing can reverse pairs/rows. `POOLING_OPERAND_TREES.json` preserves every ordered tree. For example warp0/lane0/register4370 uses `(0,0),(0,1),(1,0),(1,1)`; lane16 uses `(3,0),(3,1),(2,0),(2,1)`. Keep the actual tree even where ordinary finite addition happens to commute.
6. Pool_half is Q8 at13106–13130, packed and written to shared `[0,1024)` at13139. After barrier13141, the down learned projection consumes those pooled FP8 bytes. Its C starts from the precomputed **half zero** `%r2767`, first K32 then second K32 using the **first D as C**. Final half D is Q8 at13287–13308 and stored to ABI+72. **No learned down bias, gain, skip addition or residual exists after this projection.**

These statements preserve rounding/codec/approximation policies; they do not numerically characterize exceptional values, internal f16 MMA accumulation or hardware approximations. `SOURCE_CHECKS.json` inventories the exact math opcodes. No optional pure-tensor implementation is supplied because silently choosing those missing numerical policies would overstate closure.

## Actual learned64→128 mapping and carries

For native B indices `(n,k)`, define:

```
Binner(n,k)=16*(4*(n%8)+(k%16)//4)
            +8*((n%16)//8)+4*((k%32)//16)+k%4
B128(n,k)=4096*(k//32)+1024*(n//32)
          +512*((n%32)//16)+Binner(n,k)
pi(c)=16*(c//16)+4*((c%8)//2)+2*((c//8)%2)+c%2
Wdown[n,c] byte = 61744 + B128(n,pi(c))
```

Each warp/loop visit selects `nbase=32*warp+64*visit`. Its four first-K MMAs13200/13207/13214/13221 cover nbase+0,+8,+16,+24, with half-zero C. The four second-K MMAs13258/13265/13272/13279 take respectively the first D pairs4582/83,4586/87,4590/91,4594/95 as C. Second K slab basis is **65840 =61744+4096**. Loop visits partition output channels, not an extra K carry.

For lane `l`, A register `r=0..3`, byte `b=0..3`, native `m=l//4+8*(r%2)`, `k=32*carry+16*(r//2)+4*(l%4)+b`. All1024 A byte tags prove `(pool_y,pool_x)=(m//4,m%4)` and `k=pi(c)`. Standard f16 D pairs use row `l//4+8*Dreg`, col `nbase+8*Ngroup+2*(l%4)+half`. Both output byte maps are independently checked against their actual store instructions, not borrowed from DS4.

## Outputs, guards, padding, shared epochs

`OUTPUT_CONTRACT.md` and JSON state both complete byte formulas, exact signed guards, logical envelopes, pointer-null caveat, odd-size/trunc-vs-ceil distinction and all padding policies. Data envelopes are source formulas only; **no actual allocation extent is asserted**.

Shared storage is4096 bytes, no `.reqntid`. Nine static barriers occur at4326,8047,10130,10418,12461,13103,13104,13141,13504; first eight are reached by all64 conditional-compatible lanes, ninth is CTA-uniform geometry-conditional padding. Consecutive13103/13104 are retained. Epochs (before first barrier is0):

|Epoch|Reads|Writes|
|---:|---|---|
|0|none|0–4096|
|1|0–4096|none|
|2|0–2048|0–2048|
|3|0–2048|none|
|4|2048–4096|0–2048|
|5|0–2048|none|
|6|none|none|
|7|none|0–1024|
|8|0–1024|none|

Finite byte-level checks retain unique writers and no same-epoch other-thread read/write conflicts. Bottom PV scratch reuses the first half rather than overwriting its residual source in the second half. Both down-loop visits read the same pooled scratch after13141. Barriers do not prove inter-kernel publication, allocation ownership or native completion.

## Verification and stopping boundary

`python -B out/finalize.py` exercises only own source indices, slab snapshot, integer addresses/control and opaque neuron-coordinate tokens: 61570 scalar field bijections;188416 B checks;8192 bias C checks;1024 exact pooling trees;1024 down A bytes;2048 learned and4096 skip neuron bytes; six executed source-address geometry cases. Fresh DS parser proof is separately persisted. Failures and strict rejected alpha evidence remain.

**32/32 primary read units, each text acquisition <=2000 lines; stop here.** All writes are confined to own `out/`. No outside discovery/recursive scan, network, GPU, Wine, DLL/PE operation, deployment/gate action, nested agent, native allocation claim, fabricated activation or original numeric run. Main4's reported first full72-grid pass and family resemblance are not block8 proof.

### Remaining gaps

- No actual block8 host aggregate values, ordered graph ports/consumers, dispatch, launch dimensions, original weight binding, allocation size, alias/lifetime, completion or publication proof. ABI+8 is called skip and ABI+72 learned down output by source function, not independently proven host O[1]/O[0].
- Primary learned writes use eight channel planes and trunc(H/2),trunc(W/2) strides; padding uses sixteen planes and ABI80/84 strides. Supplied-source finite address cases overlap. No host/live geometry supplied to resolve or rule out this hazard.
- No native E4M3 codec, f16 MMA accumulator implementation, rsqrt/rcp/ex2 approximation or exceptional-value numerical equivalence. No neural/activation execution or original numerical freeze; no identity MMA.
- Common E4M3 field tables use explicit MMA-native n/k axes; only the down-projection input K-to-pooled-neuron permutation and both final output neuron bases are independently closed here. Common QKV/score token-to-global-spatial semantic naming is not universally reproved.
- Ordinary hash/count and full operand projection are checked; DS alone received the second independent source-preserving raw parser within budget. Do not claim two independent exact raw parsers for ordinary.
- Finite address tests cover six stated geometry/origin/grid cases under conditional (32,2,1) CTAs, not arbitrary signed overflow, arbitrary launch shape, general grid ownership, or universal safety. Neither source declares reqntid.
- References are supplied historical reports only; block4/1H DS and Main4 full72-grid acceptance do not establish block8. No DLL/host facts were reacquired. Model request metadata is reported, not independent runtime model attestation.
