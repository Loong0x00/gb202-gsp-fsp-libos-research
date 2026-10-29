# Original-PTX finalpost: recovered actual learned 32→4 head

## Result

**Recovered the final learned RGB/logit projection, before the previously reconstructed color decode.** It is a head-local **32 FP16 features → 4 FP16 components**, implemented by two K16 MMA stages per pixel tile. The same **128 learned half coefficients** are used for both output-store paths. This is not another unimplemented tensor-layout interface: the reference reads the actual pinned block70 bytes and evaluates this projection from its exact packed-register entry boundary.

- **Exact static results:** original PTX operands; slab byte addresses; finite half decoding; A/B/D fragment maps; output SEL/SHFL composition; all 128 coefficient bit patterns and their feature/component indices; absence of a separate bias in this final projection.
- **Executable arithmetic:** exact-integer unrounded dot products, and an explicitly chosen two-stage RN-even-half approximation. No host float arithmetic is needed for either computation.
- **Not proved:** native MMA accumulation/rounding parity, upstream feature values, full finalpost/image forward, live argument/resource contents, or numerical equivalence to another backend. No geometry, darkening, or training conclusion is drawn.

All writes are inside `reviews/nr-ptx-finalpost-20260911/`. Read the prior main/binding/routing/upload/tile reports. No GPU, Wine, native launch, old approximate model, patch, or dynamic-argument analysis.

## 1. Source and typed slice

Original extracted function:
`../nr-static-followup-main-20260911/finalpost-original.ptx`

- 16,266 lines, 265,352 bytes.
- SHA256 `b2471a490b1c5a8817689d14358d648283823ced2165f84b0fef3e13ee928bc8`.
- Its entire byte string occurs **exactly once** in `observed-module-ptx.txt`, SHA256 `cf566aa4d4cdf2e50a9b1756bf931bf4e6f89e1d3b3deacbefe30e6d0a9553ad`.
- Parent `FATBIN_PROVENANCE.json` ties the whole container to the original DLL and the same byte-identical SM120 CUBIN used by the earlier SASS reviews. This pass consumes that provenance, rather than making a new dynamic/backend assertion.

PTX line **1478** loads `%rd6` from aggregate **+24 = +0x18**. There is no subsequent destination write to `%rd6`. Prior upload/binding proof supplies this pointer from `block70.layer0.layer`, unchanged packed bytes. Lines **2895–2900** build `%r5420` from FP32 zero → half zero → duplicated packed half. This is the final head's initial C operand, not an unidentified bias.

| Store path | Typed weight address/load lines | Eight FP16 MMA lines | Output selector lines |
|---|---|---|---|
| First, local y=0..3 | **13715–13729** | **13732–13784** | **13788–13835** |
| Second, local y=4..7 | **15851–15865** | **15868–15920** | **15924–15971** |

Each path loads exactly:

```
B0_lane = load.v4.u32(rd6 + 20784 + 16*lane)
B1_lane = load.v4.u32(rd6 + 21296 + 16*lane)
```

The consumers are explicitly:

```
mma.sync.aligned.m16n8k16.row.col.f16.f16.f16.f16
```

**Only these bytes are interpreted as FP16 weights.** The preceding learned block uses `e4m3` MMA and `cvt.rn.satfinite.e4m3x2.f16x2`. Its output accumulator registers become these FP16 A operands. No dense-half reshape of the 21,808-byte slab or its FP8 region is performed.

`ptx-head-excerpts.txt` retains numbered, hashed original slices, including the FP8 producer boundary and subsequent RGB/logit consumers. `HEAD_PROOF.json` records every actual MMA operand tuple for both paths.

## 2. Exact learned-weight byte permutation

NVIDIA's `mma.m16n8k16` floating-point fragment documentation was fetched over HTTPS; the two relevant text sections and source URLs/hashes are retained. For B, with lane `l`, half index `i=0..3` in its two packed words:

```
B row = 2*(l%4) + (i%2) + 8*(i//2)
B col = l//4
```

The first two words of each `v4.u32` load supply B columns 0..7. The second two words supply the separate B columns 8..15. This follows the **original MMA operand lists**, not the serialized F16 container label.

Define head-local reduction index **k=0..31**, full computed column **c=0..15**:

```
chunk = k//16
base  = (20784,21296)[chunk]
lane  = 4*(c%8) + (k%8)//2
byte_offset(k,c) = base + 16*lane + 8*(c//8)
                       + 4*((k%16)//8) + 2*(k%2)
W[k,c] = little_endian_binary16(slab[byte_offset:byte_offset+2])
```

This is a bijection over the **512 half slots** in slab bytes **[20784,21808) = [0x5130,0x5530)**. The last address is within the copied payload, not its reserved padding.

**Only c=0,1,2,3 reaches the color/logit consumer.** In the actual pinned bytes:

- 128 live coefficient slots, all finite and nonzero.
- 384 unused slots are exactly `0000`, not unknown allocator padding.
- The second eight-column MMA outputs are dead after their own unused shuffles; columns 4..7 of the first group are not selected either. Tests replace all unused coefficients with nonzero finite values and confirm the original operand/shuffle replay still produces exactly the same four outputs. Thus the live-column conclusion does **not** rely on the zero observation.

Precise provenance:

| Item | Value |
|---|---|
| Full slab WEIGHTS_HT payload offset | **147406312** |
| Full slab pool offset | **147429888 = 0x8c99a00** |
| Full slab bytes / SHA256 | **21808**, `197024afb1f78602dc08cfd5ae87c413385237c5f537dd5dcfeae742be85eca8` |
| Head WEIGHTS_HT range | **[147427096,147428120)** |
| Head pool range | **[147450672,147451696) = [0x8c9eb30,0x8c9ef30)** |
| Head 1024-byte SHA256 | `70a0c881022b20035cad47856f13329d3a982a7ed5fa5fe58cbae31950a14d1c` |

`head-tail.bin` is this exact 1,024-byte range obtained through the existing strict `upload_contract.pinned_upload().read(...)`. `head-weights.csv` lists all **128 live coefficients**, slab/pool/resource byte offsets, original little-endian bytes, and values. No inferred allocator-padding contents are read.

Concrete example: **W[28,3]** is at slab byte **21524**, bytes **`c537`**, value **0.485595703125**. Its role is a coefficient of the learned fourth/logit projection, **not** the named `blend_scale` scalar or the host RGB multiplier.

## 3. Exact entry register boundary, math, and pixel selection

Entry A fragments, in original operand order. Each listed register is a packed `.f16x2` word in **each of 32 lanes**:

| Path | Pixel tile t | k=0..15 words | k=16..31 words |
|---|---|---|---|
| First | 0 | r3805,r3806,r3807,r3808 | r3815,r3816,r3817,r3818 |
| First | 1 | r3829,r3830,r3831,r3832 | r3835,r3836,r3837,r3838 |
| Second | 0 | r5392,r5393,r5394,r5395 | r5402,r5403,r5404,r5405 |
| Second | 1 | r5416,r5417,r5418,r5419 | r5423,r5424,r5425,r5426 |

These are already produced by upstream FP8 MMA **with FP16 D**, not arbitrary guessed NCHW tensors. Their actual values remain an explicit unresolved upstream boundary. `feature-register-map.csv` enumerates **all 2,048 feature slots**, 64 output pixels × 32 features, down to PTX register, source lane, and half.

For head-local row `m=0..15`, feature k:

```
chunk      = k//16
source_lane= 4*(m%8) + (k%8)//2
word       = m//8 + 2*((k%16)//8)
half       = k%2
X[t,m,k]   = half(entry[t][chunk][source_lane][word], half)
```

This is the inverse of the documented **A** fragment mapping, separately verified by exhaustive forward enumeration. It does not imply that prior-layer channels/spatial axes have these same names.

Ignoring unspecified MMA internal rounding, the learned computation is:

```
T[t,m,c] = sum(k=0..15,  X[t,m,k] * W[k,c])
Y[t,m,c] = T[t,m,c] + sum(k=16..31, X[t,m,k] * W[k,c])
```

The actual PTX writes T into **FP16 D**, then passes that packed value as the second MMA's **FP16 C**. There is **no final-projection bias**, activation, or blend_scale in this slice. Upstream feature generation may already contain biases/nonlinearities; they are not being deleted or declared absent.

Original first-path live chains:

```
r3821,r3822 = MMA(A[t0,k0], B0[first2], zero)
r3813,r3814 = MMA(A[t0,k1], B1[first2], {r3821,r3822})
r3839,r3840 = MMA(A[t1,k0], B0[first2], zero)
r3833,r3834 = MMA(A[t1,k1], B1[first2], {r3839,r3840})
```

Other four MMA operations compute columns 8..15 that do not reach this output. Second path is the same chain with its own entry feature registers and the same weights.

Replaying the **actual PTX SEL/SHFL instructions** with unique half tags gives, for output lane l and c=0..3:

```
learned[l,c] = Y[t=l//16, m=l%16, c]
local_x     = (l&3) + 4*(l>>4)
local_y     = ((l>>2)&3) + 4*store_path
```

This agrees with the earlier SASS-derived 8×8 coordinate map; both paths' selections were checked independently, not inferred from matching register counts. The output pairs are **r39/r40** for the first path and **r47/r48** for the second. Their four halves are converted to FP32 at lines **13879–13894 / 16007–16022**. The first three feed the prior RGB multiplier/color decode; the fourth feeds the sigmoid-logit path at **14110 / 16245**. It is not surface alpha.

## 4. CPU reference, exact versus approximate

`head_reference.py` accepts **[2 pixel tiles][2 K chunks][32 lanes][4 packed u32 words]** and the exact-size encoded slab. It rejects nonfinite arithmetic inputs, malformed fragments, and short/oversized slabs. It exposes:

- `weight_offset`, `feature_slot`, `output_source`, `output_xy`: exact integer layout rules.
- `weights`: just the 128 live typed coefficients, as raw half bits.
- `project_exact`: unrounded mathematical result as integer numerators in units **2^-48**. Each finite half is an exact integer in units 2^-24, so products/sums require no floating approximation.
- `project_staged_rn`: exact sum within each K16 MMA, **RN-even to half after each stage**, with gradual subnormals. Returns four half bit patterns per output lane. This is a **declared reference rounding policy**, not a recovered native one.

The NVIDIA ISA explicitly says, for f16 C/D: multiplication is at least single precision, accumulation is at least half precision; **accumulation order, rounding, and handling of subnormal inputs are unspecified**. Therefore original PTX alone cannot prove bit-identical general native outputs. The reference retains the visible intermediate-half boundary but does not pretend its exact inner dot is the Tensor Core implementation. Exact cancellation uses +0; nonfinite inputs/overflow fail closed rather than sanitizing them. Native signed-zero/subnormal/nonfinite corner cases are not emulated.

The tests deliberately distinguish two-stage rounding from one dense dot: contributions `1 + 2^-11` in the first K16 and `2^-11` in the second yield **1** under the chosen two-stage policy, versus **1+2^-10** after a single final rounding. The distinction would be lost by a naive dense FP32/FP64 head implementation.

`proof_checks.py` independently applies the **forward** documented A/B/C/D fragment maps to the eight **operand tuples parsed from original PTX**, then replays only the two bounded original 48-line selector blocks. It does not implement upstream PTX or accept unknown operations. This independent check shares the explicitly chosen half-rounder, not the optimized head's inverse byte/feature formulas.

Examples using a one-hot feature equal to 1 at every head row (all other entry halves zero), with actual learned bytes:

| Feature k | learned R | learned G | learned B | logit |
|---|---:|---:|---:|---:|
| 0 | -0.0007395744323730469 | -0.01629638671875 | -0.005519866943359375 | 0.011749267578125 |
| 16 | -0.0007944107055664062 | 0.00396728515625 | -0.004245758056640625 | 0.01180267333984375 |
| 28 | 0.00968170166015625 | 0.0141143798828125 | -0.0037078857421875 | 0.485595703125 |

These are reproducible CPU learned-projection examples, **not native captures or predictions of real-image features**.

## 5. Verification and boundary

From this review directory:

```sh
python -B collect_evidence.py > collection.json
python -B test_head.py > verification.txt 2>&1
```

**13 tests pass**, including:

- Original PTX size/hash and exact containment in the observed module text; pinned upload/slab equality.
- Weight pointer and zero-root instructions; both eight-MMA operand chains and two explicit 16-byte-stride loads.
- Every one of 512 tail-half addresses against the independent forward B map; 128 live coefficients and 384 exact-zero unused slots.
- All 512 feature slots per pixel tile against the independent forward A map.
- Both original selector blocks, all 256 selected output halves, and all 64 local coordinates.
- All **63,488 finite binary16 encodings** against Python's binary16 decode and exact round-trip (signed zero distinguished at the bit boundary); all nonfinite encodings rejected.
- RN ties/subnormal/overflow tests and 3,000 independent binary16-rounding checks.
- Every one of **32 one-hot feature channels at all 32 output lanes**, with actual weights, checked through both original operand/selector paths.
- Four deterministic dense bounded synthetic register inputs, original instruction replay versus direct recovered head; a separate exact `Fraction` dot-product check across 128 outputs with broad finite-half inputs.
- Nonzero mutation of unused columns, strict malformed/nonfinite inputs, and the two-stage rounding counterexample.

The first test run caught two overly broad source-check counts (a regex matched source operands as destinations, and a stride count also counted a lane-bit mask); these were narrowed to the actual destination/multiply instruction forms. Final arithmetic/layout tests pass. No native validation was run.

**Completed boundary:** actual original learned coefficient bytes → typed final projection → the exact four values accepted by the prior color/logit decode. The **complete 21,808-byte weight permutation is still unknown**; only this final 1,024-byte typed region is solved. The upstream FP8 activation/normalization/MMA pipeline, input encodings, and native general numerical parity remain separate work. No dynamic arguments were analyzed or duplicated here.
