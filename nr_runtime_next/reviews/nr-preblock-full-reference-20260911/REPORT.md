# Full first-invocation PREBLOCK264 reference — CPU/static

## Result

**Executable through the original `ret`, not just ingress or embedding.**
`full_reference.py` runs one CTA `(0,0)`, block `(32,1,1)`, of the untouched
`cc_tinlayout_fused_pre_block_swin_1h_32_1_ds_fp8` instruction body:

1. Caller-supplied f32-bit sampler → original deterministic noise, image/guide/control half features.
2. Original 64-pixel fill loop → all 2048 shared bytes → converged CTA barrier → shared fragment loads.
3. **All 16 F16×F16 K16 embedding MMAs** (64 pixels × 32 half outputs), then the second original barrier.
4. **All 256 remaining E4M3×E4M3 K32 MMAs**, with the actual intervening learned projections, half activation/residual arithmetic, normalization, query/key/value/score processing, shuffles, transpose, and FP8 conversions. No conventional softmax, dense layout, query values or block1 offsets are substituted for these instructions.
5. All four packed skip stores through **args+216**, followed by the original shuffle/add/add/mul-half downsampling and all four packed stores through **args+248**.
6. The original padding predicate selects the original terminal at source line **15334**.

The launch's dynamic `sharedMemBytes=0` does not remove the original **2048-byte static shared array**.

The test/demo uses **synthetic sampled image values and derived synthetic guides**, the **actual first 264-byte aggregate**, and the **real block0 slab**. It is not a native activation capture, native numerical oracle, full-frame forward, or whole-network execution.

| Result for this CTA | Bytes | Lane stores | Sparse byte offsets (inclusive extrema) |
|---|---:|---:|---|
| Skip +216 | 2048 | 128 × 16 bytes | 0 … 99327 |
| Downstream +248 | 512 | 128 × 4 bytes | 0 … 1394751 |

`output-patches.json` records each original store as
`[opcode, lane, aggregate_pointer_field, byte_offset, payload_hex]`.
Holes are absent, **not zero-filled**. `Memory.packed()` rejects unproduced bytes.
`demo-summary.json` includes payload hashes and operation counts.

## Actual binding and source

Readonly capture:
`nr-swin1h-binding-main-20260911/runs/20260911-145411-observer_on/nr-kernel-args-01.bin`

- Aggregate SHA256: `e2f4491eb54383dd1466d08ca340fa38027041b825f8713c77392bcf374417f5`.
- Observer log binds submission 1 to this exact entry, `grid=96,56,1`, `block=32,1,1`, `expectedParamBytes=264`, and complete saved extra-buffer arguments. **Before-original submission evidence, not GPU completion.** The observed cubin identity and source PTX identity are separate; no machine-code numeric equivalence is inferred from their names.
- T0 = `73014450503`; T1/T2/T3/T4 = null; full u64 invocation counter at +200 = 0.
- +208/+212 = H432/W768; +240/+244 = H448/W768; +256/+260 = H224/W384.
- Reuses `nr-preblock-binding-20260911` actual264 fieldproof and ABI gate. The test replays its first-counter host patch and verifies the aggregate is unchanged despite nonnull prospective temporal inputs. No T3←Depth substitution.
- `ingress.block0_slab()` uses the pinned upload contract: `block0.layer0.layer`, raw source 63, pool offset 0, payload **21696**, reservation 22016. SHA256 `5fe2ab86289f7b21253d00368ce7a95f005ec3c8476abd7db22550b918962a5c`.
- Original module stays **`.version 9.4`, `.target sm_120`, `.address_size 64`**. The entry is checked against the original module by the reused ingress source reader. No PTX/header modification, compilation, GPU, Wine, installed-file change or sibling write.

All weights/constants/queries come from **original preblock instructions and original block0-addressed loads**. Only generic instruction semantics and numerical primitives are reused from the strict Swin1H helpers. No standard/inpview instruction stream or slab is used by this forward.

Actual accessed slab-byte unions (half-open): `[0,8192)`, `[8208,9296)`, `[9312,20580)`, `[20592,21680)`. These are mixed typed fields, **not a dense FP8/half tensor**. In particular embedding W occupies `[8208,9232)` as half operands; the FP8 conversion happens afterward. `EVIDENCE.json` retains exact load spans and all original MMA source sites.

## Numerical and shared-memory policy

Every policy is explicit at `run()`; omitting any fails:

- Ingress uses the prior opt-in libm approximate policy for div/rcp/lg2/sqrt/sin/cos, retaining actual hash/noise instructions and half conversion/subtraction/multiplication boundaries. This is not native approximate-instruction bit parity.
- **Necessary actual-args fix:** +96/+100 are zero even with T3 null. Original PTX unconditionally computes reciprocal then negation before skipping temporal work. The prior finite ingress rejected this. `ingress_first.py` reuses its thread implementation verbatim except `neg.ftz.f32` sign-bit handling; `first_libm_policy` supplies documented `rcp(±FTZ-zero) = ±infinity`. These computed infinities are not consumed by the selected temporal-null branch. No transform is patched in the fixture and no operand is invented. Local pinned ISA text, lines 11765–11855, documents reciprocal special values/FTZ. All other finite arithmetic restrictions remain.
- FP16 MMA: generic ISA m16n8k16 fragment mapping, exact finite K16 dot plus actual C, **one RN-even half result per original MMA**. Uses finalpost/head finite-unit and rounding primitives, never its offsets or weights. Gradual subnormals; exact cancellation chooses +0; nonfinites/overflow reject.
- FP8 MMA: reused explicit exact-K32-dot-plus-C / RN-half policy. Half2 arithmetic and E4M3 RN/satfinite conversions use the pinned typed primitives. No automatic reinterpretation of first-MMA half words as FP8.
- rsqrt and reciprocal in learned math use existing explicit RN-f32 reference policies, not invented native approximate bits.
- **General native MMA accumulation order, intermediate precision, subnormal and bitwise parity remain unproved**, regardless of any narrow primitive results elsewhere.

Shared backing is initialized only by original fill stores; every shared load checks written-byte coverage. The first barrier checks 32 participating lanes at one original instruction; the suffix checks full-warp convergence at its barrier and every MMA/shuffle/transpose. The third original barrier (line15012) belongs to an unselected padding path. No barriers are erased. Original loops remain parsed/executable with strict instruction budgets; only `.pragma "nounroll"` scheduling hints are discarded. Missing registers stay absent/None and fail on read.

## Exact remaining boundary

This restores the **complete selected first-invocation preblock path** for the bounded CTA, not every branch/launch geometry:

- Nonzero full counter or any nonnull T1/T2/T3/T4 fails the API gate; temporal reconstruction and mask-bearing variants are outside this task.
- Only one warp per CTA is supported. No multiwarp/cross-CTA timing or visibility model.
- Here downstream dimensions equal ceil(preblock output dimensions/2). The original predicate at **14979–14982** branches to `ret` without the padding-zero loops. Padding geometry needing unspecified `%nctaid` builtins fails rather than inventing grid values. Generic integer loop execution is unit-tested, but a native padding-layout contract is **not** claimed.
- Sampler filtering, addressing, view creation, resource contents, consumer selection/metadata and device publication/synchronization remain external. Captured addresses identify explicit CPU memory regions only; they are never dereferenced as host pointers.
- The demo's output bounds are explicit CPU fixture spans sufficient for the actual selected stores, not independent evidence of native allocation ownership.

## Verification

From project root, all outputs remain in this review:

```sh
python -B reviews/nr-preblock-full-reference-20260911/test_full_reference.py
python -B reviews/nr-preblock-full-reference-20260911/full_reference.py --synthetic --reference-policies
python -B reviews/nr-preblock-full-reference-20260911/collect_evidence.py
```

**14 CPU/static tests pass.** Tests cover actual ABI/host firstcounter binding, real slab hash, complete fill/noise/guide behavior, signed-zero reciprocal handling, scoped ingress-copy identity, all embedding outputs against the prior independent dense map, **every one of the 256 FP8 MMA calls against the independent forward fragment map**, all 272 original MMA sites reached, independent skip/downstream address and packing equations, synthetic-image sensitivity of both learned outputs, real backedge execution/budget, missing operands, unsupported operations, output holes/bounds/overlap, and divergent collective/barrier failure. No native-activation assertion is made by these tests.

Readonly reruns of the reused numerical suites also pass: **19 prefix tests + 13 finalpost/head tests**, retained in `reused-primitive-tests.txt` (46 tests total with this review's 14). These strengthen the reference-policy checks, not a native-parity claim.
