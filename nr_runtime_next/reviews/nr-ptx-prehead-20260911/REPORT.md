# Original-PTX prehead: executable producer boundary, both store paths

## Result

Recovered **the actual last FP8 projection feeding every head ENTRY_REG**, then extended the connected CPU reference upstream through **score production, the actual normalization, and the two-stage attention/value reduction**, for **both** store paths. This is executable numerical/fragment logic, not a tensor-layout placeholder.

The important correction to a simple dense-head model is:

```
normalized query halves * typed query scale -> E4M3 Q
normalized key halves -> E4M3 K
score = FP16_D_MMA_K32(Q, K, typed FP16 additive score slab)
probability-like fragment = actual half/bit-transform/normalization(score)
context = FP16_D_MMA_K32_then_K32(E4M3(probability-like), E4M3(value))
feature = FP16_D_MMA_K32(E4M3(context), typed E4M3 learned projection,
                       RN_half(raw earlier feature * typed half channel scale))
feature registers -> existing head_reference -> learned RGB/logit halves
```

“Query/key/value/score” describe the operand roles in this bounded pipeline, **not a recovered image tensor layout**. In particular, the normalized score fragment is **not replaced by standard exp/softmax**, the last projection C is **not zero or a guessed bias**, and the two K32 stages are **not collapsed into a single dense sum**.

**Verified:** 16 new CPU/static tests pass; all 13 existing head tests still pass. Both paths connect to the existing head reference. **Not verified:** native parity, real image features, earlier Q/K normalization or earlier value/residual producers, complete finalpost/full model.

All writes are in this review directory. Original PTX, upload implementation, signed files and other source files were read only. No GPU, Wine, compiler, native launch or old approximate model was used.

## 1. Original operands and typed bytes

Source: `../nr-static-followup-main-20260911/finalpost-original.ptx`, SHA256
`b2471a490b1c5a8817689d14358d648283823ced2165f84b0fef3e13ee928bc8`.
`rd6` is loaded from aggregate +24; `rd136` is its `cvta.to.global` alias (1478–1479).

Slab: `head_reference.pinned_slab()` uses the existing strict
`upload_contract.pinned_upload()`, span `block70.layer0.layer`:

- 21,808 encoded bytes; SHA256 `197024afb1f78602dc08cfd5ae87c413385237c5f537dd5dcfeae742be85eca8`.
- Resource source offset 147406312; upload/pool offset 147429888.
- No dense F16 interpretation of the serialized slab is made.

| Slab range | Actual consuming type/role | Original source |
|---|---|---|
| [11472,15568) | FP16 C additive score fragments, first store | loads/MMA 11969–12149 |
| [15568,19664) | FP16 C additive score fragments, second store | loads/MMA 14129–14318 |
| [19664,19668) | FP32 query scale, converted RN to half, then half multiplication | load 9095; arithmetic 10209–10436 |
| [19680,20704) | **E4M3 B** of final FP8 projection | 13584–13710 / 15720–15846 |
| [20704,20768) | FP16 channel scales for raw residual C | address/load/multiply slice 8496–9093 |
| [20784,21808) | Existing final head FP16 B | prior head reconstruction |

The nearby [19668,19680) and [20768,20784) gaps are deliberately **not assigned a type or role** here. Earlier slab bytes remain outside this work.

The first eight-MMA projection loads exactly:

```
{r3771,r3772,r3779,r3780} = v4.u32(rd6 + 19680 + 16*lane)
{r3783,r3784,r3787,r3788} = v4.u32(rd6 + 20192 + 16*lane)
```

Consumers are `mma.sync.aligned.m16n8k32.row.col.f16.e4m3.e4m3.f16`.
The second path uses identical byte addresses and its own operand names. All eight outputs per path feed the final head, unlike the head's own dead output columns.

For projection-local k,c in 0..31:

```
lane = 4*(c%8) + (k%16)//4
W_offset(k,c) = (19680,20192)[c//16] + 16*lane
              + 8*((c%16)//8) + 4*(k//16) + k%4
```

This is a checked bijection over **all 1,024 E4M3 coefficient bytes**. Real bytes contain no E4M3 NaN. `last-projection-weights.csv` lists every coefficient and exact resource/pool/slab address.

Residual channel c uses half bits at `20704+2*c`. These are **not all positive**: c15=-0.71484375 and c28=-0.408935546875. The query scalar is bytes `b9021f41`, FP32 **9.938164710998535**, explicitly converted to half **9.9375** before multiplication/FP8 conversion. Additive score halves are all finite, ranging from -14.9296875 to 0. No spatial/positional interpretation of those numbers is asserted.

## 2. Last complete producer and exact head connection

Each named register below is **32 lanes of packed f16x2 u32**, not one scalar.

| Store | Source context halves before final FP8 cvt | Raw residual before channel scale |
|---|---|---|
| 0 | r3755..r3770 | r2368..r2383 |
| 1 | r5342..r5357 | r2384..r2399 |

The eight consecutive context words per tile are quantized pairwise: the lower source half becomes the lower FP8 byte; the second `cvt` result occupies the upper 16 bits of the packed b32 MMA operand. Conversion uses **RN-even, finite saturation to ±448**; NaNs are rejected rather than sanitized.

Example first MMA:

```
r3775 = pack16(cvt_e4m3x2(r3755), cvt_e4m3x2(r3756))
r3776 = pack16(cvt_e4m3x2(r3757), cvt_e4m3x2(r3758))
r3777 = pack16(cvt_e4m3x2(r3759), cvt_e4m3x2(r3760))
r3778 = pack16(cvt_e4m3x2(r3761), cvt_e4m3x2(r3762))
r3773 = mul.f16x2(r2368, load.u32(rd136+20704+4*(lane%4)))
r3774 = mul.f16x2(r2370, same channel-scale word)
{r3805,r3806} = MMA({r3775..r3778},{r3771,r3772},{r3773,r3774})
```

All other operand tuples are retained in `PRODUCER_PROOF.json`; C source permutations and both paths are executed from the original instructions in the independent tests.

`prehead_reference.project(regs, slab, store)` returns exactly the head's
`[2 tiles][2 K16 chunks][32 lanes][4 packed u32]` entry structure.
`to_entry_regs(...)` emits the exact `head_reference.ENTRY_REGS[store]` dictionary.
`through_head(...)` returns the 32 lanes × four learned RGB/logit half bits.
These are **before color decode, sigmoid/blending and output stores**.

## 3. Upstream extension: real normalization, not guessed softmax

Both original normalizer blocks are executable: 12153–13470 and 14322–15606. A separate direct implementation, `normalize_scores`, independently agrees with their full PTX arithmetic, bit and lane-selection order.

Per packed score word, the original performs:

1. `fma.rn.f16x2(score, half(0x29c0), half(0x3d34))`.
2. Clamp each half to `[half(0x3c20), half(0x3e47)]`.
3. **Whole-word** `((word << 5) + 0x7ff88000) mod 2^32`. Carries and half packing are preserved; this is not `exp`.
4. Half-rounded reduction over eight score groups per lane in the actual tree `(((g0+g1)+(g2+g3))+(g4+g5))+(g6+g7)`.
5. Original SEL/SHFL moves collect four lanes in order; half add chain `((lane0+lane1)+lane2)+lane3`, followed by low-half + high-half.
6. Clamp the positive sum to epsilon half `0x0410` (from FP32 bits 948045311).
7. Convert to FP32, `rcp.approx.ftz.f32`, convert back to half, broadcast/shuffle to the original fragment lanes.
8. Half multiply, then E4M3 conversion/packing.

The direct reference retains every half arithmetic boundary. Unique-tag tests prove the four-lane ordering; dense asymmetric score tests cover both halves, all rows and both paths. Zero score inputs yield half **1/64** before FP8 conversion, but nonuniform results use the actual transform/tree, not a textbook softmax implementation.

The value B operands here are **dynamic computed features**, not additional learned slab weights. Their supplied half boundary is r3297..r3328, **after earlier `movmatrix`**, then the exact original E4M3 conversions at 11847–11957. Context is produced by 16 original MMAs per store: four column groups × two query tiles × **two sequential K32 stages**, each with FP16 D. These outputs become the context boundary in §2.

Score production is also implemented: normalized/scaled Q and normalized K halves are quantized, then sixteen original K32 MMAs use the real loaded FP16 score C bytes. `score_bias_offset` exhaustively maps all **4,096 half slots**. This avoids mislabeling the 8,192-byte score region as dense projection weights or FP8 B.

## 4. Arithmetic policy and limitations

**Same core policy as the head reference:** exact integer dot within each visible MMA, then RN-even half D; gradual half subnormals; exact cancellation chooses +0; nonfinite arithmetic and half overflow fail closed. Scalar packed half add/mul/fma each have their own RN-half boundary. Finite overflow during the explicitly `satfinite` E4M3 conversion saturates, not during unrelated half operations.

For the FP8 MMAs, the retained NVIDIA ISA describes multiplication at specified precision and accumulation **at least single precision**, with order, rounding and subnormal-input behavior unspecified. The FP16 final head has its separately documented precision bounds. **A half D does not establish half-only internal FP8 accumulation.** Our exact inner sum is a declared mathematical reference, not recovered Tensor Core internals.

There is one additional explicit approximation boundary: the normalizer's `rcp.approx.ftz.f32` is replaced by **correctly RN-even FP32 reciprocal of the exact input**, then the original RN-half conversion. `reciprocal_policy` implements this via integer rational arithmetic and exposes a callback for a future validated oracle. This is **not** native `rcp.approx` parity. FTZ-zero/zero denominators reject; normalizer inputs are positive half sums converted exactly to FP32, so no FP32 subnormal occurs there.

No NaN is changed into zero/finite data. Nonfinite native propagation, signed-zero edge cases, native subnormal handling and native approximate instruction behavior remain outside the claimed domain. Consequently no native/full-model/image parity, tuning, quality or training conclusion follows from the CPU examples.

## 5. Precisely unresolved inputs / Main connection

There are several usable entry points; none silently supplies missing features:

| Entry point | Caller inputs per store, all 32-lane packed half registers |
|---|---|
| `project` / `through_head` | 16 context words + 16 raw residual words from §2 |
| `scores_through_head` | 32 score words + 32 value words + 16 raw residual words |
| `qkv_through_head` | 16 already-scaled normalized query words + 32 normalized key words + 32 value words + 16 raw residual words |
| **`unscaled_qkv_through_head`** | **96 registers:** 16 normalized query words *before real slab query scale*, the same 32 keys, 32 values and 16 residual words |

Exact largest boundary:

- Store0 Q: `2841,2846,2844,2848,2850,2854,2852,2856,2858,2862,2860,2864,2866,2870,2868,2872`.
- Store1 Q: `2874,2878,2876,2880,2882,2886,2884,2888,2890,2894,2892,2896,2898,2902,2900,2904`.
- Shared normalized K: **r3233..r3264**, before E4M3 cvt. These are products of earlier feature and normalization operands, not raw weights.
- Shared V: **r3297..r3328**, after `movmatrix.sync.trans.aligned.m8n8.b16` of earlier FP16 MMA results r3265..r3296 (with the actual nontrivial register order retained).
- Raw residual: **r2368..r2383** / **r2384..r2399**, earlier FP8 MMA results, not zeros or an additive constant.

`BOUNDARIES.json` gives the **exact original immediate producer instruction and source line for every one** of these roots, plus the smaller score/context boundaries. This is the next bounded reconstruction target; no live arguments, input image encoding, earlier normalization/value/residual arithmetic or feature tensor axis is fabricated here. The two stores share K/V but have distinct Q and residuals; combined largest boundary is 128 packed register arrays.

Minimal use:

```python
import prehead_reference as pre
import ptx_slice
slab = pre.head.pinned_slab()
# regs: {numeric_original_r_name: [packed_u32_for_lane0, ..., lane31]}
learned = ptx_slice.unscaled_qkv_through_head(regs, slab, store=0)
# learned[lane] = four raw half bits accepted by the prior color/logit decode.
```

For explicit head handoff: `scale_queries` -> `produce_scores` -> `normalize_and_attend` -> `project` -> `head.project_staged_rn`. `demo.py` demonstrates and asserts both compositions with real weights and **clearly synthetic** boundary features.

## 6. Evidence and verification

Run from this directory:

```sh
python -B collect_evidence.py > collection.json
python -B demo.py > demo-output.json
python -B test_prehead.py > verification.txt 2>&1
python -B ../nr-ptx-finalpost-20260911/test_head.py > head-regression.txt 2>&1
```

**16 tests pass**, including all 254 finite E4M3 encodings, all 63,488 finite binary16-to-E4M3 conversions, rejection of all nonfinite half encodings, all projection byte/fragment addresses, all score additive half addresses, all 32 source basis channels and all 32 residual channels with real weights, dense original operand replay for both paths, independent normalizer/tree/tag checks, both complete Q/K/V-to-head chains, real query scalar conversion/multiplication, a staged-MMA rounding counterexample, malformed inputs and nonfinite rejection. Every positive finite half reciprocal input is also checked against independent `Fraction`/Python FP32 conversion. **13 head regression tests pass.**

Independent MMA replay uses documented **forward** lane/element mappings and independently decoded/quantized FP8 operands, versus the producer's inverse maps. The chosen half-rounder is intentionally shared with the already-tested head policy; this is not an independent native oracle.

`demo-output.json` retains all 64 learned four-component outputs and both head-entry fragment hashes. Example lane0 outputs with deterministic synthetic inputs and actual slab:

- store0: `[-0.00505828857421875, -0.0027866363525390625, -0.00045943260192871094, 0.005290985107421875]`.
- store1: `[-0.01068115234375, -0.0057373046875, -0.0111846923828125, -0.003582000732421875]`.

These are reproducible CPU calculations, **not native captures or real-image predictions**.

Retained evidence: numbered original excerpts, every MMA operand tuple, typed byte artifacts/hashes, full FP8 weight/score-half/channel-scale CSV maps, original input definitions, NVIDIA fragment/conversion docs and source URLs/hashes. Initial local checks caught slice end lines cutting off one C tuple and an argument-tokenizer whitespace issue; both were corrected before final tests. No native validation was run.
