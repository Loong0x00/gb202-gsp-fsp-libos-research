# Block5: actual 2h C64 inpview versus ordinary source

## Result and boundary

**Static source/layout closure; no numerical/native acceptance.** Verified own packet-listed PTX and 61,760-byte slab hashes. Exact entry: `cc_tinlayout_fused_swin_2h_64_2_inpview_fp8`.

| | inpview | ordinary |
|---|---:|---:|
| Source lines | 13,351 | 12,737 |
| Executable instructions | **5,459** | **4,845** |
| Static MMA sites | **304** | **304** |
| ABI bytes | **88** | **88** |
| Shared bytes / static barriers | **4,096 / 6** | **4,096 / 6** |
| Natural math loops | **1, exactly 2 iterations** | **1, exactly 2 iterations** |

The reported 5459/4845 counts are **instruction counts, not source-line counts**. Both entries use `.maxnreg 168`; neither declares `.reqntid`.

`python out/verify.py`: **59 aggregate checks passed**, including **557,056 field-operand checks** and **538,197 layout/guard/bit/transport checks**. These are address/label and source checks, not floating neural computation. MMA results are fresh opaque labels, **never identity MMAs**.

Read budget: **18/32 primary units**, each text unit at most 2,000 original lines; 14 remain unused. **One initial diagnostic emitted 2,041 lines and was display-truncated.** Its spill was not read; this violation is preserved in `FAILURES.json`. Later diagnostics were bounded. DLL deliberately unopened; no PE scan, discovery, network, GPU/native/Wine, deployment/gates, or nested agents.

## 1. Own 88-byte ABI — not 1h96

All offsets below are decimal and come from this entry's actual parameter loads, source lines12–37.

| Offset | Type | Register / role |
|---:|---|---|
| 0 | pointer | `%rd8 → %rd1`: planar16 FP8 input |
| 8 | pointer | `%rd9`: ordinary tiled C64 FP8 output |
| 16 | pointer | `%rd10 → %rd2/%rd3`: source-typed slab |
| 32,36 | s32 | `%r52,%r53`: H,W; fallback ingress and output geometry |
| 40,44 | s32 | `%r54,%r55`: X,Y origins |
| **80,84** | s32 | `%r56,%r57`: independent positive ingress H,W overrides |

**Unread:** `[24,32)`, `[48,80)`. Ordinary also leaves80–87 unread. **+72/+76 are not this entry's effective dimensions.** No 1h field offsets were transplanted.

`EH = ABI80 > 0 ? ABI80 : H`; `EW = ABI84 > 0 ? ABI84 : W`. Output dimensions always remain H,W. Supplied host report establishes an88-byte2h aggregate and a rounding path, but does **not** supply live +80/+84 values or a live exact FP8 dispatch.

## 2. Ingress: four explicit planes and canonical neuron basis

Define

```
piC(c) = 16*(c//16) + 4*((c%8)//2) + 2*((c//8)%2) + c%2.
input_byte(y,x,c) = 16*((c//16*EH+y)*EW+x) + pi64(c)%16.
```

This is **four physical 16-byte planes**, each with EH×EW pixels; not raw neuron-index channel order, and not ordinary tiled C64.

Actual source loads16 u32 sites per lane. Site order is horizontal tile `h=0,1`, plane `p=0..3`, row half `d=0,1`:

```
y = Y+8*ctaid.y + 4*tid.y + lane//16 + 2*d
x = X+8*ctaid.x + (lane//4)%4 + 4*h
byte = 16*((p*EH+y)*EW+x) + 4*(lane%4)     # four actual bytes
```

If EH==1, the source broadcasts y=0 and omits its usual coordinate guard; EW==1 does the same for x. Otherwise each dimension requires `0<=coordinate<effective_extent`. A failed site supplies u32 zero bits, not an unguarded load. Simplified equations assume no signed-address overflow; the index retains the exact signed32 operations.

Channels are proved by **four distinct plane terms plus two learned K32 passes covering K64**, not by stride alone. A compatible64-thread CTA consumes4,096 ingress bytes for8×8×64. `FIELD_OPERAND_PROOF.json` checks first-projection K axes against actual loaded byte tags; `LAYOUT_PROOF.json` independently compares131,072 first-MMA A byte tags with ordinary source's ingress basis.

Each u32 splits into two E4M3x2 pairs, then `cvt.rn.f16x2.e4m3x2` decodes four half elements. Both branches below use these decoded halves. Later encodings explicitly use `cvt.rn.satfinite.e4m3x2.f16x2`; finite round-trip intuition must not substitute for NaN/native codec guarantees.

### Conditional DS4 handoff — not a live allocation

The supplied DS4 contract's primary learned writer uses

`16*((plane*HD+y)*WD+x)+pi64(neuron)%16`, **HD,WD=floor(high H,W /2)** in its positive domain.

This agrees with the **actual block5 consumer basis** iff producer HD,WD equal consumer effective EH,EW, the handle/visibility/buffer conditions hold, and any producer padding hazards are resolved. Supplied routing says DS4 O0→block5 I0; it remains supplied conditional static evidence here, not a re-scanned/live producer.

**PH/PW metadata or channel-stride names do not prove that equality.** Counterexample to a broad clean-size assumption: producer H=72 gives dense HD=36 and PH=36, while the reported2h default ceil8 path gives40 unless +80 provides36. Producer multiples8 alone therefore do not close this handoff. Producer64→DS32→consumer effective32 is a compatible *conditional example*, not invented activation/allocation data.

DS4's different padding strides/eight-plane zero suffix and odd-size hazards remain producer obligations. Actual block3→4 source/activations were not supplied and are not invented. Main retains the first numerical freeze.

## 3. Own slab: nine typed canonical field maps

Slab SHA256: `1b905577285978107b21b5730aac2b0105d45f757b5e78334291d9b4ab5646bb`.

Packet container metadata is F16[30880], with DLL data offsets `[141517952,141579712)`; **actual source payload is mixed typed**, not uniformly F16.

| Byte range, end exclusive | Actual payload | Canonical shape / role |
|---|---|---|
| 0–16384 | E4M3 | [256,64] FF expansion |
| 16384–24576 | E4M3 | [2,32,128] branch-local FF contraction |
| 24576–28672 | E4M3 | [64,64] FF mixing into residual |
| **28688–28816** | F16 | [64] input residual gain |
| 28832–41120 | E4M3 | [2,3,32,64] head,Q/K/V,neuron,input |
| 41120–57504 | F16 | [2,64,64] score-bias C fragments |
| **57504–57512** | **F32** | [2] Q scaling parameters |
| 57520–61616 | E4M3 | [64,64] attention output projection |
| **61616–61744** | F16 | [64] attention residual gain |

**Exactly56 unread bytes:** `[28672,28688)`, `[28816,28832)`, `[57512,57520)`, `[61744,61760)`. Their raw hex is retained; no guessed field/dtype is assigned. Source-address tracing of both valid tid.y values covers61,704 bytes at129 distinct slab load sites.

`FIELD_MAP.json` gives every shape, axis, dtype, indexing equation, hash and exact paths to **row-major u32 byte-offset tables plus canonical raw payloads** under `fields/`. Each table bijectively covers its field, and canonical payloads reconstruct directly from own slab bytes.

The FP8 packing primitive is

```
P(n,k,N) = (k//32)*N*32 + (n//16)*512
         + 16*(4*(n%8)+(k%16)//4)
         + 8*((n//8)%2) + 4*((k//16)%2) + k%4.
```

Canonical K uses `piC(k)` in P; this permutation is checked against actual A packing, not guessed from a matrix identity. Head-local QKV indexing, both branch strides and bias C packing are explicit in the JSON.

Both F32 Q-scale values were decoded from own slab: **2.3823421001434326, 9.916067123413086**. Source converts each to half before multiplication. Gains and score bias are finite in this slab; no numerical activation result is claimed.

## 4. Actual computational forks and all MMA operands

All304 tuples for each source are in `inpview.MMA.json` / `ordinary.MMA.json`, including original lines, instruction indices, opcode, and full **D,A,B,C register lists**. `MMA_OPERAND_DEFINITIONS.json` adds predecessor definitions, stage/head/loop indices and explicit loop-carried C dependencies. `MMA_BYTE_TAGS.json` contains dynamic address/element tags, not numeric values.

Every MMA is exactly `m16n8k32.row.col.f16.e4m3.e4m3.f16` with register tuple lengths2/4/2/2. Per warp:112 FF sites execute twice, then96 QKV +32 QK +32 PV +32 output = **416 collective operations**, or832 for a compatible two-warp CTA.

### First residual fork

* `X = decode8(input)`.
* Initial FF-mix C is **half-multiply X by the gain at28688**, retained unquantized.
* Learned expansion independently quantizes **X, not gain×X**. Each branch expands64→128 using two ordered K32 steps.
* Actual cubic activation: `t=max(min(z,4),-4)`; output is `hMul(z,hFma(t,hFma(-0.055908203125,hAbs(t),0.447265625),0.89453125))`. These constants/operations are source-derived, not an assumed SiLU implementation.
* Quantized activated128 feeds a32-output contraction through four ordered K32 steps. Its half output is quantized before FF mixing.
* Mixing branch0 and branch1 each adds its K32 contribution through actual C chains. Branch1 starts with branch0's **unquantized** mixed D. No invented expansion/contraction bias or intermediate identity projection.
* Only after both branches is resulting Z quantized into shared memory.

### Attention / second residual fork

* QKV consumes stored **Q8(Z)**, split into two32-feature heads over64 tokens. Q/K normalized-half and scale operations precede their FP8 encoding; V is separately encoded/transposed.
* Own shuffle/transpose tags prove Q/K/V roles and token order `16*(2*(y//4)+x//4)+4*(y%4)+x%4` within8×8.
* QK bias is the actual **F16 C operand**, not an imagined later bias addition. No standard `exp`/softmax substitution: source uses half FMA/clamps, a packed shift/add exponent approximation, half reductions and approximate reciprocal.
* The packed exponent operation's component basis is checked for **304,704 finite clamped halfword pairs**. Numerical accuracy/exceptional-value behavior is not accepted by that layout lemma.
* PV's K64 reduction uses **pi64(token)** order. Its actual MMA schedule interleaves two N8 groups with K0/K1; a naïve ordering failed and is preserved in `FAILED_INITIAL_PV_GROUPING.json`.
* Attention residual C is **decode8(Q8(Z)) × gain61616**, not the original unquantized Z. PV half D is quantized to shared; final learned64→64 projection consumes both heads through two ordered K32 contributions and starts from that residual. Final D is FP8-encoded on output.

Exact operation trees/order are retained in the indexed source; basis tags intentionally do not evaluate floating values or denominator dependencies.

## 5. Thread roles, shared reuse, barriers and output

A source-compatible minimal shape is **(32,2,1)**: two full warps with tid.y=0,1. **Actual launch shape remains unobserved.** Before the first barrier, tid.y selects top/bottom4 image rows. Afterward it selects attention head and final32-output-channel partition. Cross-head final projection reads both heads; these are not independent final projections.

Additional warps with the same tid.y duplicate payload/shared addresses; extra tid.y extends beyond supported head/shared fields. Merely launching64 total threads with another shape is not equivalent.

| Epoch ending at inpview barrier | Shared reads | Shared writes |
|---|---|---|
| 4920 | none | initial Z,0–4096 |
| 8641 | Z,0–4096 | none |
| 10732 | top Z,0–2048 | top PV scratch,0–2048 |
| 11030 | top PV,0–2048 | none |
| 13072 | **bottom Z,2048–4096** | **bottom PV scratch,0–2048** |
| 13348 | bottom PV,0–2048 | none |

The bottom PV phase **reuses the first half**, not the second half, of shared memory. All six CTA barriers are retained. Finite ownership checks show no duplicate writers or same-epoch other-thread read/write conflicts for the compatible shape. No grid barrier, producer-consumer publication/fence or live alias/lifetime guarantee follows.

Output is ordinary tiled C64 E4M3, **not planar16**. Four128-bit writer sites:10998,11019,13328,13345; all4,096 interior output neuron bytes are tagged and checked. For each4×4 tile, row0 guard is `oy>-4 && trunc0(oy/4)<trunc0(H/4)`; row1 uses `oy>-8` and tile row+1; columns analogous. These always use H,W, not EH,EW. Full equation and four boundary guard tests are in `ABI_AND_INGRESS.json` / `LAYOUT_PROOF.json`.

**No output null guard, zero-padding suffix, or guarantee that skipped tiles/fringes are written.** Signed divisions truncate toward zero, not Python floor on negatives.

## 6. Common core: alpha + CFG, with explicit exceptions

Starting ordinary line358 / inpview954:

* **4,615 instructions** are exact under **one injective register/label/shared-symbol renaming**, including all304 MMA tuples, barriers and math-loop body.
* One further instruction is exact only by **commuting the add.s32 operands** (ordinary10365 / inpview10969), not literal alpha equivalence.
* Inpview has18 extra core instructions: H/W division8643–8650, first-column guard10973–10978, second-column guard11001–11004. Independent definition DAGs prove their values equal ordinary boundary H/W-divisions and column predicates.
* All five common branch label targets and fallthroughs are preserved; one target has the proven four-instruction guard prelude. Both CFGs have one self-loop, with induction0→1 and predicate true→false, proving exactly two visits.

**Ingress CFG is intentionally excluded.** Inpview has per-pixel guards and singleton1 broadcast; ordinary has whole4×4-tile guards and broadcast when `(dimension & -4)==4` (dimensions4–7). Their load instructions/cache/weak qualifiers also differ. Value equivalence requires a stable compatible input byte view and matching decoded boundary values; it is not universal at arbitrary extents/overrides or a native memory-semantics claim.

## Deliverables and remaining obligations

Core: `FIELD_MAP.json`, `ABI_AND_INGRESS.json`, `COMMON_CORE_ALPHA_CFG.json`, `FIELD_OPERAND_PROOF.json`, `LAYOUT_PROOF.json`, full indexed sources/MMA tuples, canonical typed fields, `verify.py`, `READ_LEDGER.json`, `FAILURES.json`, `STATIC_TEST_RESULTS.json`. `FILES_CHANGED.json` lists exact output paths.

Open for Main: actual3→4 source/activations, actual EH/EW and H/W, precise host operand binding beyond supplied evidence, producer padding safety, live buffers/alias/lifetime/completion/visibility, live slab binding, exact launch/dispatch and native FP8/MMA precision. **No original numeric run or full-NN prediction was performed.**
