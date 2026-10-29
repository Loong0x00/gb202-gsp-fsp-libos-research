# Internal finalpost numeric gap: source-proved Q/K contraction closes this fixture

## Result

**Verified fixture-specific CPU-policy correction:** the original SASS contracts **32 Q/K normalization squared-pair additions**, folding the **first** square into HFMA2 while rounding the second square with HMUL2. Replacing only those separate-RN CPU expressions with the actual fused expressions changes the native-F32 comparison from **14/256 mismatches, maxabs 2.4318695068359375e-5**, to **0/256, maxabs 0**. This succeeds with both archived approximation policies, without changing FP8 MMA, F16 head MMA, color decode, inputs, or any original reference file.

This attribution rests on **original instruction/operand proof plus connected reproduction and ablations**, not surface rounding. The secondary CPU-RTZ/native-half diagnostic changes from 1/256 to 0/256; it is **not** used to establish internal bit equivalence. CPU-RNE/native-half remains 79/256 after the arithmetic correction (previously 80), a separate surface issue.

All work was CPU/static and all writes are here. No GPU, CUDA Driver loading, Wine, installed-file edit, sibling-reference edit, PTX compilation/downgrade, module patch, NaN sanitization, or fitted output offset.

## Identical native experiment and CPU inputs

Read-only native files:

- `../nr-original-finalpost-main-20260911/run-20260911-164343/output.rgba16f`
- `../nr-original-finalpost-f32-main-20260911/run-20260911-165905/output.rgba32f`
- Actual input fixtures: `../nr-original-finalpost-main-20260911/fixtures`.

The replay verifies both native runs' `owned-args184.bin` against the fixture template after clearing only the five owned pointer/object slots. It verifies all four `after-*` readbacks against the same main1472/skip3072/slab21808/blend2 fixtures. A=B=C=0; 16x16, origin(0,0), one CTA, 32 lanes, decode1, multiplier1/32. Both archived CPU JSONs are reproduced exactly before introducing the alternative policy. Comparisons cover the 64 actual written pixels × RGBA, **not poison outside the tile**.

65 read-only external inputs, sources, native readbacks and approximation tables are frozen in `INPUT_PINS.json`; pre/post verification passes. The original 3,336 SASS encodings are all checked against the untouched ELF selected text. Original ELF SHA256 remains `feb368ff5279a7408b1e55554db6e468d7f114a24b18b2af8d7e6989a410c612`; PTX SHA256 remains `b2471a490b1c5a8817689d14358d648283823ced2165f84b0fef3e13ee928bc8`.

## Concrete original operands: not just an HFMA opcode count

For each paired reduction, the existing CPU policy evaluates:

```
RNhalf(RNhalf(x*x) + RNhalf(y*y))
```

The SASS evaluates:

```
y2 = RNhalf(y*y)          // HMUL2
sum = RNhalf(x*x + y2)    // HFMA2, no intermediate rounding of x*x
```

The first PTX square is always the folded one. This is not commutative with respect to which product receives the intermediate RN boundary.

### Q witness

```
0d60 LDC.64 R10, c[0x0][0x398]                   // slab parameter +24
11c0 IMAD.WIDE R10, R164, 0x10, R10              // slab + 16*lane
4eb0 LDG.E.128.STRONG.SM R48, desc[UR4][R10.64+0x20d0]
4e80 LDG.E.128.STRONG.SM R52, desc[UR4][R10.64+0x22d0]
5ee0 QMMA.16832.F16.E4M3.E4M3 R130, R4, R48, RZ
5e80 QMMA.16832.F16.E4M3.E4M3 R138, R4, R52, RZ
6010 HMUL2 R76, R138, R138
6030 HFMA2 R76, R130, R130, R76
```

The two raw-Q values share the **same four A register versions**; their typed B bases are **8400 and 8912**. Original PTX lines **8160/8174** are the corresponding B-base pair in the first logical A tile, producing `%r2537/%r2545`. Lines **9100/9128** square these; **9324** adds `%r2601,%r2602` into `%r2649`. All four tiles use the same direction, so the proof does not guess a physical-A to logical-tile permutation to establish the contraction policy.

### K witness

```
5000 LDG.E.128.STRONG.SM R72, desc[UR4][R10.64+0x24d0]
4ec0 LDG.E.128.STRONG.SM R76, desc[UR4][R10.64+0x26d0]
60d0 QMMA.16832.F16.E4M3.E4M3 R76, R68, R72, RZ
5fa0 QMMA.16832.F16.E4M3.E4M3 R80, R68, R76, RZ
62b0 HMUL2 R73, R80, R80
62e0 HFMA2 R73, R76, R76, R73
```

These raw-K values share A versions and use typed B bases **9424 and 9936**. PTX first-tile equivalents: MMAs **8188/8202**, squares **10546/10574**, pair-add **10770**. Register reuse is tracked: the R76 B pair consumed at 5fa0 is **not** the later R76 raw-K output from 60d0.

### Complete coverage and validation

`static_proof.py` propagates typed load lineage, QMMA D-word identity, and versioned A identities; unknown writes invalidate values, including multi-register writers. It proves each addend is the actual earlier HMUL2 of the matching same-A, same-D-word raw value. Across all 32 HFMA2 sites, the folded B base is the first PTX term and the rounded B base is first+512. Q bases are 8400/8408; K bases 9424/9432; two D words × four A versions gives **16 Q + 16 K**. The bounded operand region has no branch. Exact per-site chains and all 32 PTX line/operand entries are in `STATIC_PROOF.json`.

Every one of the 32 fused-source mutations, and four typed B-load mutations, is rejected. `test_transform_only_proven_QK_sites` verifies the CPU-only in-memory expression rewrite changes exactly the 32 certified add lines, nothing else. No transformed device source is written or compiled.

The retained NVIDIA half-ISA text (`../nr-ptx-prefix-20260911/isa-arithmetic-shuffle.txt`, lines 48–52 and 154–158) explicitly permits contraction of unadorned mul/add; explicit `.rn` is treated conservatively. This supports interpreting the recovered instructions; permission alone was not taken as evidence that a particular fold happened.

## Numerical witnesses and ablation results

On the identical main fixture, the first-pair sums change at **126 Q half components and 171 K half components**. Raw Q/K and the weighted merge remain unchanged. After normalization, **209 Q and 187 K** half components change. `PAIR_SUM_WITNESSES.json` retains every changed first-pair component, not just an output-selected example:

- Q PTX9324, lane0 low half: x=`b0ca` (-0.149658203125), y=`271d` (0.0277862548828125); separate sum=`25ef`, fused sum=`25ee`.
- K PTX10770, lane1 low half: x=`3068` (0.1376953125), y=`9cee` (-0.00481414794921875); separate sum=`24dd`, fused sum=`24dc`.

| CPU fragment policy | F32 mismatches /256 | Max absolute F32 error | CPU RTZ-half vs native-half mismatches |
|---|---:|---:|---:|
| Existing separate RN | 14 | 2.4318695068359375e-5 | 1 |
| Merge skip-product fold only | 14 | 2.4318695068359375e-5 | 1 |
| Merge opposite fold (counterfactual) | 14 | 2.4318695068359375e-5 | 1 |
| Q first-square fold only | 5 | 1.9431114196777344e-5 | 1 |
| K first-square fold only | 9 | 2.4318695068359375e-5 | 0 |
| **Q+K first-square folds** | **0** | **0** | **0** |
| Merge skip fold + Q+K first folds | 0 | 0 | 0 |
| Q+K second-square folds (counterfactual) | 33 | 3.337860107421875e-5 | 1 |

Corrected Q+K gives 0/256 for **both** `RN_f32_reference` and `measured_SM120_half_input`. `COMPARISONS.json` and each policy JSON retain exact component values and bit patterns.

### Precise residual coordinates, (x,y)

Original 14 F32 residuals:

- **(3,1): RGB**
- **(4,2): GB**
- **(2,3): RGB**
- **(6,3): RGB**
- **(3,4): RGB**

Q-only leaves (4,2):GB and (2,3):RGB, **5 components**. K-only leaves (3,1):RGB, (6,3):RGB, (3,4):RGB, **9 components**. **Q+K leaves no residual coordinates.** Original sole RTZ-half residual is (2,3):R, CPU `3802`, native `3801`; corrected policy eliminates it without any output adjustment.

## Weighted merge and FFN: real contraction, not this fixture's gap

Original merge witness:

- `0e70 LDG.E.128... R24` loads the skip bundle; `1940 F2FP.F16.E4M3.UNPACK_B R85,R24` widens its first pair.
- `1050 LDG.E R103,[R12.64+0x2090]` loads skip coefficient at slab8336+lane-derived offset.
- `0fd0 LDG.E R9,[R12.64+0x2050]` loads main coefficient at slab8272+the same offset.
- `1950 HMUL2 R50,R50,R9` rounds the paired main product.
- `1af0 HFMA2 R85,R85,R103,R50` fuses the skip product into that rounded main contribution.

PTX first merge: main mul **922** `%r816=%r204*%r205`, skip mul **1852** `%r817=%r720*%r721`, add **2076** `%r944=%r816+%r817`. This establishes a real native-vs-separate-policy distinction. However, **both tested merge fold directions change zero of the 2,048 merged half components on this fixed fixture**, hence do not explain these 14 output differences. No general merge equivalence is inferred from power-of-two synthetic features.

The direct original half mul→add audit finds **64** sites: 32 merge and 32 Q/K pair reductions; **none in FFN**. FFN's polynomial uses explicit `fma.rn.f16x2` already honored by the CPU, and its final multiply remains HMUL2 before FP8 conversion. Concrete original sequence **2210 HFMA2 R53,|R52|,-R2.H0_H0,0.447265625...**, **2230 HFMA2 R109,R52,R53,0.89453125...**, **2460 HMUL2 R109,R57,R109** agrees with that structure. `MUL_ADD_AUDIT.json` is deliberately a direct-def/use inventory, not a proof against every possible compiler reassociation.

## F16 head MMA: tested separately, general limits remain

Original head has eight `HMMA.16816.F16` instructions: path0 **9350/9440** and **93f0/9510**; path1 **c0a0/c100** and **c0c0/c130**. The second member of each pair takes the first F16 accumulator as C. This supports retaining **two K16-visible half boundaries**, not replacing the head by one unrounded K32 dot.

`fragment_policies.py` explicitly compares exact K16 then RN-half, F32 sequential accumulation with C first, F32 pairwise then C, and F32 sequential with C last. On the captured-fixture-derived head entry fragments:

- All four policies give **identical learned half bits, including the unused logit**.
- Thus all four leave the uncorrected 14 F32 differences; all four give corrected **0/256**.
- Counterfactual exact K32 with no first-half boundary produces **78** F32 differences on old fragments and **71** on corrected fragments. It is not a fix.

Read-only re-evaluation of all **112 prior native primitive fixtures, 7,168 live components per stage**, preserves the known general discrepancy:

| Head policy | Stage1 numeric mismatches | Stage2 numeric mismatches |
|---|---:|---:|
| Exact K16/RN-half | 1 | 1 |
| F32 sequential, C first | 2 | 2 |
| F32 pairwise, C last | 2 | 4 |
| F32 sequential, C last | 2 | 3 |

All four additionally have 102/75 signed-zero-only differences at stages1/2. `HEAD_POLICIES.json` lists exact primitive cases/rows/components. **None is promoted to a universal native head model.** NVIDIA's retained MMA ISA text explicitly leaves accumulation order, rounding and subnormal handling unspecified; F16 C/D has at least half accumulation precision. Existing native FP8 MMA 324-case evidence remains unchanged, not enlarged by this work.

## Remaining limits

- The verified fix is a **new-scope CPU fragment policy for this original kernel's recovered Q/K contractions**, with exact output reproduction for this one synthetic internal-feature fixture. Existing references are unchanged and would need an explicitly reviewed opt-in before adopting it.
- No native internal checkpoint values were captured here. Even exact native-F32 output reproduction does **not** prove all hidden intermediates, learned half bits, unused logits, or all other fixtures bit-exact; downstream quantization can conceal differences.
- General F16-head MMA equivalence, signed zero, subnormal behavior, wider FP8/approximation domains, and other input/launch contracts remain unproved.
- Surface conversion is independent. RTZ-half statistics are diagnostics only; this worker makes no new surface-rounding proof.
- This is not actual-image processing, a full-model run, or whole-model parity.

## Reproduce

```
bash reviews/nr-finalpost-numeric-gap-20260911/verify_cpu.sh
```

Passes: 65 external pins before/after; 3,336 original instruction-byte checks; 32 complete Q/K operand chains; 10 connected policies; 10 head-policy/entry combinations; read-only native-head regression; **9 CPU tests**, including 32 fused-operand and four B-load mutations. `verification.log` retains the run; `FILES_CHANGED.txt` lists exact new paths.
