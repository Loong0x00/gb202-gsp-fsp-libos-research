# Swin1H plain inpview — complete bounded middle-block CPU reference

## Result

Implemented **raw packed input + actual encoded block1 slab → packed output**, for one bounded 32-lane tile of the original **`cc_tinlayout_fused_swin_1h_32_1_inpview_fp8`**. This is the requested **96-byte-argument plain inpview** entry, not the wait/chained variant or another finalpost tail.

The entire **5,505-instruction entry** is covered, including **256 original FP8 MMAs**, FFN polynomial activation/residual accumulation, learned Q/K/V, actual Q/K normalization/query scale, value transpose, both additive-score paths, both actual normalization/attention reductions, final learned projections with **nonzero computed C**, FP8 conversion and all four predicated **b128 stores**. No missing operand or instruction boundary remains inside the declared tile/policy domain.

**14 tests pass.** A real-slab, nonuniform synthetic 8×8 fixture stores exactly **2,048 packed bytes**, SHA256:

`f55d59ee28f700ac3a8d16ae65c6f0a4a218c04f9982959477c5bb3dece7a3a2`

**Not native parity or runtime selection attestation.** Historical block1 family and payload identity are established; there is **no attestation that an actual runtime selected this entry, passed these arguments/slab, or used this launch geometry**. All activation and argument demonstration bytes are explicitly synthetic. Existing GPU primitive validation does not establish general native accumulation parity or whole-block parity.

All writes are confined to `reviews/nr-ptx-swin1h-20260911`. Exact DLL, serialized weights, 15-module bundle and sibling reviews were read only. No GPU, Wine, compiler/assembler, signed-file modification or PTX-header downgrade.

## Reproduce / caller API

From the project directory:

```sh
python -B reviews/nr-ptx-swin1h-20260911/collect_evidence.py
python -B reviews/nr-ptx-swin1h-20260911/test_swin1h.py
python -B reviews/nr-ptx-swin1h-20260911/demo.py --synthetic --reference-policies
```

Outputs are `packed-output.bin`, `demo-output.json` and the evidence artifacts in this directory. For caller-provided raw bytes:

```sh
python -B reviews/nr-ptx-swin1h-20260911/demo.py \
  --input RAW --args ARGS96 --output-size N \
  --cta X Y --output-span OFFSET SIZE --reference-policies
```

Without `--output-span`, the JSON contains only actual sparse store patches. The CLI never invents unstored output bytes. All CLI outputs remain in this review directory.

Python, with this directory on `sys.path`:

```python
import swin1h_reference as s
regs, memory = s.run(args96, raw_input, s.pinned_slab(), output_size,
    cta=(0, 0), rsqrt=s.prefix.rsqrt_rn_policy,
    reciprocal=s.prehead.reciprocal_policy)
packed = memory.packed(offset, size)  # rejects any byte not actually stored
```

Both approximation callbacks are mandatory. `mma=` accepts a 32-lane × 4/2/2 raw-u32 A/B/C callback, allowing a future validated native-policy oracle. Default MMA is explicitly exact-dot/RN-half, not native Tensor Core accumulation. Inputs must begin at the aggregate's pointer bases; no tensor reshape is inferred.

## Actual source and block1 bytes

`PROVENANCE.json` verifies:

- Exact signed DLL SHA256 `e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e`.
- DLL `WEIGHTS_HT` resource equals the raw serialized container, whose SHA256 is `836f445d06ecd2e59bb9f17b84b91c143396fd76ccda1c9dc7fe81d5edd548f4`; every serialized payload matches the safetensors checkpoint byte-for-byte. F16 container metadata is **not** used as a dense weight interpretation.
- Historical block1 is `cc_tinlayout_fused_swin_1h_inpview_32`. Its `block1.layer0.layer` payload is **20,672 bytes**, raw offset **21,834**, upload offset **22,016**, SHA256 `0270fb8f406d3d0a916953ddaf6ec5d29328fe95b9d6cb408ca0c25c91108e3a`.
- All **15** fatbins equal their exact DLL slices; their PTX artifacts equal fresh read-only zstd decompression of their original DLL frames and the pinned bundle hashes.
- Target is module00 `entries.tsv` byte interval **[5724445,5940870)**, **216,425 bytes**, SHA256 `e36a534b79b5361f853f1e8baf4cd63f80d85bd73259e46de36a31321568ce13`.

`swin1h-original.ptx` is that exact entry slice, not an assembled standalone module. The original module directives **`.version 9.4`, `.target sm_120`, `.address_size 64`** are preserved separately in `original-module-header.txt`; the source bundle is untouched.

### This slab is not the finalpost slab

| Slab byte range | Consuming type and source role |
|---|---|
| [0,8192) | E4M3 learned FFN B operands |
| [8208,8272) | FP16 channel scales for the raw-input FFN residual |
| [8288,11360) | E4M3 learned Q/K/V B operands |
| [11360,15456) | FP16 additive score C, first path |
| [15456,19552) | FP16 additive score C, second path |
| [19552,19556) | FP32 query scale, converted RN-half before half multiplication |
| [19568,20592) | E4M3 final learned context projection B, both paths |
| [20592,20656) | FP16 scales for final projection's actual earlier FFN residual C |

Gaps [8192,8208), [8272,8288), [19556,19568), [20656,20672) are **unread and untyped**, not assumed zero padding. All other bytes are proven loaded by the original entry.

Actual query scale is **0.408796101808548**, f32 bits `0x3ed14db9`, RN-half bits **`0x368a`** — not finalpost's 9.938… scalar or offset. Initial residual scales include two negatives; final residual scales include one negative. No postblock offsets/weights are transplanted.

`OPERAND_PROOF.json` retains all 256 D/A/B/C tuples, original line numbers and immediate producer/def-use references. `TYPED_LOAD_PROOF.json` records every slab-load site's 32-lane offsets and each learned-B/additive-C register's actual slab origin, verified against its raw operand bits. Dynamic K/V operands remain marked as computed features, not weights.

Example first final projection, original lines 12197–12200:

```
D={r3254,r3256}
A={r3226,r3227,r3228,r3229}       # original quantized context
B={r3222,r3223}                 # slab+19568+16*lane, u32 slots 0/1
C={r3224,r3225}
r3224 = RNhalf(r1819 * load_half2(slab+20592+4*(lane%4)))
r3225 = RNhalf(r1821 * load_half2(slab+20592+4*(lane%4)))
```

`r1819..r1850` are actual FFN producers, not caller placeholders. The second path uses its own original operands and the same learned tables.

## Exact input and output layout

Aggregate fields read by original PTX:

- +0/+8/+16: u64 input/output/slab bases.
- +24/+28: signed H/W. +32/+36: signed X/Y origins, then add `8*CTA.x/y`.
- +72/+76: input H/W overrides, used only when positive. Output extents still use original H/W.
- Bytes [40,72), [80,96) are never read; changing these from synthetic `0xA5` to zero does not change output.

Let `ih,iw` be effective input dimensions; `X,Y` include CTA offsets. For input site `s=0..15`, let `tile,local=divmod(s,4)`, `dy,dx=divmod(tile,2)`. Lane `l` loads a u32 at:

```
row = Y + 4*dy + 2*(local%2) + l//16
col = X + 4*dx + (l//4)%4
valid = (ih==1 or 0<=row<ih) and (iw==1 or 0<=col<iw)
row = 0 if ih==1 else row
col = 0 if iw==1 else col
offset = 4 * (4*((row + (local//2)*ih)*iw + col) + l%4)
```

Invalid lanes do **not read memory**; the original explicit zero-register initializations supply padding. Singleton axes broadcast even for out-of-range origins. Independent tests compare every raw load bit/address over interior, edge, negative-origin, singleton and dimension-override cases, plus nonzero CTA coordinates.

Output uses original signed truncation: `tw=trunc(W/4)`, `th=trunc(H/4)`, `bx=trunc(X/4)`, `by=trunc(Y/4)`. For tile `(dy,dx)` in `(0,0),(0,1),(1,0),(1,1)`:

```
valid = Y > -4-4*dy and by+dy < th and X > -4-4*dx and bx+dx < tw
offset(lane) = 512*((by+dy)*tw + bx+dx) + 16*lane
```

Each valid lane stores 16 bytes, assembled from eight original E4M3x2 b16 registers. The four lists are **rs338..345**, **rs346..353**, **rs440..447**, **rs448..455**, in low-first order. All 2,048 output bytes in the 8×8 fixture are independently checked against this packing/address equation. Negative/edge cases produce sparse patches only.

This proves packed output byte layout, **not permission to feed it directly back into an inpview entry**. The next kernel's expected input layout remains an external composition boundary.

## Reuse only where original PTX matches

- Arithmetic, FP8 conversions, MMA fragment maps, exact-dot policy and rsqrt reference are imported from hash-pinned `nr-ptx-prefix`; no parent/sibling file is modified.
- `static_replay.py` is a local extension of the prefix's strict forward-DAG interpreter. It adds declared parameter name/size, actual b128 vector packing/stores, terminal `ret`, the actual limited `prmt/and.b16/cvt.u16` forms, and an explicit reciprocal callback. The target contains **only FP8 K32 MMAs**; no FP16 MMA emulation was needed or guessed.
- Both score normalizers are proved **bijectively register-renaming equivalent instruction-for-instruction**, including every opcode, immediate, vector order and local-register reuse, to the existing prehead normalizers:
  - Swin lines **10692–12009**, **598 instructions**, versus prehead 12153–13470.
  - Swin lines **12540–13824**, **584 instructions**, versus prehead 14322–15606.
- The full interpreter still executes **this original entry**. Existing `normalize_scores` is used only as an independent cross-check under the proven maps. No prehead projection, score offsets or query scalar are imported.

The score transform therefore remains the original affine/clamp → **whole-u32 shift/add** → half-rounded reduction tree/lane ordering → clamped reciprocal → half multiply → FP8 conversion. It is **not standard softmax**. Attention is two separately half-rounded K32 MMAs per output fragment, not one collapsed K64 dot.

## Numeric and execution policy boundary

1. FP8 conversion and packed operand maps reuse pinned finite/RN-even/satfinite primitives. NaNs reject. Scalar finite half add/mul/FMA each preserve the original PTX-visible RN boundary, gradual subnormals and signed-zero policy. Overflow rejects; no sanitization.
2. Native unadorned half `mul/add` contraction is **not modeled**. Literal PTX source-order rounding can differ from fused native SASS.
3. Each visible FP8 MMA computes an exact integer dot plus typed C, then RN-even half D. Native internal accumulation order/precision, subnormal behavior and signed-zero details remain unproved. Independent forward-vs-inverse-map agreement is a mathematical operand test, not a device oracle.
4. `rsqrt.approx.ftz.f32` and `rcp.approx.ftz.f32` require explicit callbacks. The provided policies compute RN-even f32 reciprocal square root / reciprocal; they do **not assert native approximate-instruction bits**. Unsupported zero/FTZ/nonfinite domains reject.
5. Exactly one bounded full warp is modeled. All **28 branches are statically forward**; backward branches reject at parse time, with no guessed spin-loop termination or iteration limit. Partial-warp collectives, missing/uninitialized operands, unknown operations, out-of-bounds/misaligned memory, overlapping input/output regions and duplicate output stores reject. Output has no zero-filled backing allocation.
6. No live middle activation/argument capture, observed dispatch/slab binding, multi-CTA scheduling, in-place aliasing or image/full-model reconstruction is claimed.

## Verification

`verification.txt`: **14 passing CPU tests** covering:

- Pinned complete source/shape, all 256 original MMA sites, both alpha-equivalent normalizers.
- All raw input load sites/lanes, padding/broadcast, negative/edge origins, positive overrides and nonzero CTA.
- Independent pre-FFN weighted operand/half-product checks; all 32 final projection residual products from actual FFN halves.
- **All 256 MMAs** injected through an independent documented **forward** fragment-map oracle, with independent E4M3 decoding; all outputs equal the inverse-map reference. Exactly 128 sites have nonzero C on the fixture.
- All **384 original half→FP8 sites**, each 32 lanes, compared with an independent nearest-finite/RN-even quantizer.
- Both actual normalizers compared against the separate direct transform/tree implementation, not just output hashes.
- Every **4,096 score-additive half slot**; all learned final-projection B occurrences; all slab-load address classes and exact covered/unread byte sets.
- All output store addresses and byte packing, sparse outputs, complete 2,048-byte coverage, nonconstant synthetic result and zero-input epsilon behavior.
- Strict rejection of truncated parameters/input/output, missing registers/policies, unsupported operations, backward branches, nonfinite input, misaligned/out-of-range/overlapping stores and unwritten output extraction.

`collection.txt`/`PROVENANCE.json`: successful exact-DLL/resource/checkpoint/upload/15-PTX audit, primary inputs unchanged afterward. `demo-output.json`/`packed-output.bin`: executable full-tile fixture, clearly synthetic and nonnative. `BOUNDARIES.json` enumerates completed stages, typed regions and only the remaining external/numeric boundaries.

During local testing, sibling `layout_reference` module-name shadowing and an overly strict nonzero-C count assertion were caught and corrected; the local independent layout module is now uniquely named. No sibling edits were made.
