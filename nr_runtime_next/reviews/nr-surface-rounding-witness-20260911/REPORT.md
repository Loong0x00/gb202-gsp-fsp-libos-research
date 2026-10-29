# Independent own formatted-SUST witness — prepared for Main review

## Result and strict scope

**CPU verified and crossbuilt; GPU execution remains unapproved/unperformed.** Eight CPU tests pass. Delivered own CUDA13.3 SM120 CUBIN and compile-time-blocked host. No Driver loading/discovery/API calls, GPU CLI invocation, Wine, installation, or writes outside this directory occurred. External inputs were hash-checked unchanged across verification.

Context supplied by Main: original no-texture finalpost succeeded at `nr-original-finalpost-main-20260911/run-20260911-164343`; CPU RNE diagnostic differs 80/256 (all one ULP), RTZ differs 1/256 at (2,3) R. Those are **Main's observations**, not results measured by this worker. This witness deliberately consumes **none** of the original inputs/outputs or neural tensors. Main's original-kernel RGBA32F experiment remains the independent way to expose pre-half neural math. We neither substitute for it nor claim neural parity.

## 1. Exact operation, bit transport and whole surface ABI

`witness.cu` contains one entry, `own_formatted_sust`, with a 32-byte align-8 aggregate:

| Offset | Field | Contract |
|---|---|---|
| +0 | `const uint4* bits` | One owned allocation, exactly 16 bytes/vector |
| +8 | reserved | Zero |
| +16 | `cudaSurfaceObject_t surface` | Full unchanged `cuSurfObjectCreate` return; no masking, arithmetic, reconstruction or descriptor dereference |
| +24 | width | 128 for positive, 32 for extended; enforced by host |
| +28 | count | 1..65536, pinned actual count |

Every active thread performs a `uint4` global load and exact inline **`sust.p.2d.v4.b32.zero`** using four **integer** register constraints. There is no C++ float conversion, half intrinsic, floating arithmetic, texture operation, or neural computation. This also avoids compiler quieting/canonicalizing input NaNs. X is a **sample index**, not X*8 or X*16; Y is a row index. Integer mask/shift coordinates put pixels at `(1+i%width,1+i/width)` inside a one-pixel border. The count guard precedes the input load. No out-of-bounds store is deliberately attempted.

Compiled with `/opt/cuda/bin/nvcc` **13.3.73**, `-arch=sm_120 -std=c++17 --cubin`. Retained own generated PTX is version **9.3**; no original PTX (9.4) was compiled or downgraded. Own CUDA API metadata is 0x85, original 0x86; compiler compatibility is not inferred solely from metadata.

Fresh cuobjdump instruction encodings are byte-checked against complete ELF text, including padding: **40 own instructions**, **120 prior ABI witness instructions**, **3,336 original instructions**. `evidence/static-proof.json` records exact words, register masks and selected-text SHA; retained nvdisasm liveness is supplemental.

Own SASS dataflow:

```text
0080 LDC.64 R2, c[0][0x380]                  // owned input pointer
00a0 IMAD.WIDE.U32 R2, R5, 0x10, R2         // pointer + i*16
00b0 LDG.E.128 R8, desc[UR4][R2.64]          // bit-exact R8..R11
00d0 LDCU UR6, c[0][0x390]                  // surface low word, p+16
0160 SUST.P.2D.STRONG.SM.IGN [R4], R8, UR6   // RGBA bits directly
```

Between the data load and store, **none of R8..R11 occurs in any instruction**. UR6 is not used/redefined between its load and the store. The full surface handle is supplied to the compiler; the compiler chooses its low-word machine operand. Hidden `c0[0x358]` descriptor is used for ordinary global input loading, not dereferencing the surface object.

Own store words: `60ff060804007f9b 0041e4000810af00`. Compare against the prior ABI formatted witness and both original stores at 0xaa90 / 0xcfd0: all low-word bits agree after masking only coordinate/data/surface register-index bytes (bits 24..47); lower 32 bits of high-word payload agree exactly, **0x0810af00**. Scheduling bits are retained/reported, **not** claimed equal. This is opcode **and** dataflow evidence, not a name-only match.

The prior `nr-original-kernel-object-abi-20260911` report, source, CUBIN, verifier, official documentation excerpts and Main host are pinned in `evidence/external-pins.json`. Its documented `surf2Dwrite` and formatted witness receive the same whole surface object at +16 and compile to the same direct low-word uniform input convention. The documented raw `surf2Dwrite` store itself is **not** a formatted-conversion substitute.

Authoritative local documentation verified rather than guessing unknown details:

- Prior `DOCS.md`: Driver/runtime whole-object creation/interoperability/device-input chain, including supported object passage. Header widths alone are not the argument.
- Pinned `evidence/docs/ptx.txt`, §9.7.13.2: `.p` formatted RGBA `.b32` source interpreted as FP32 for FLOAT arrays and converted to destination format; X samples; `.zero` drops OOB stores.
- Pinned `driver-array.txt`: `CU_AD_FORMAT_HALF`, four channels, 2D Depth=0 and `CUDA_ARRAY3D_SURFACE_LDST`.
- Pinned `driver-surface.txt`: API-created whole surface object, array resource, zero descriptor flags.

These official excerpts do **not** specify a complete FP32-to-HALF rounding/NaN contract. This experiment measures that remaining conversion boundary; it does not assume the answer.

## 2. Deterministic independent fixtures and bounded coverage

All binary files are little-endian; input layout is tightly packed RGBA `uint32` encodings. `MANIFEST.json` pins every byte, and generated `fixture_pins.hpp` enforces hashes/sizes before Driver loading.

| Domain | Vectors | Interior width × allocated interior rows | Array with guards | Launch | RNE/RTZ discriminating components |
|---|---:|---|---|---|---:|
| positive | **61,441** | 128 × 481 | 130 × 483 RGBA16F (502,320 bytes) | 481 CTAs ×128 | **69,120** |
| extended | **632** | 32 ×20 | 34 ×22 RGBA16F (5,984 bytes) | 5 CTAs ×128 | **264** |

Positive domain:

- All **15,360** adjacent HALF intervals from +0 through 1.
- For each, exactly representable FP32 midpoint and immediately adjacent FP32 encodings below/above it. Three RGB rotations put all three categories in every RGB channel; alpha is exactly 1.
- Then all **15,361** exact HALF values from +0 through 1 as RGB controls, alpha=1. Total 46,080 boundary vectors +15,361 controls.
- RGB stays in [0,1]; no negative, infinity or NaN. Positive HALF subnormal intervals are intentionally included, not silently dropped.
- Last row contains one active vector; count-guard tail has 127 inactive threads. Tests cover both vector mapping and unused-cell guards.

Extended domain, separate file/launch/report:

- **158** distinct exploratory scalar encodings, each placed in every RGBA channel with exact distinct companion channels (0.125,0.25,0.5,1).
- Negative values, ±0, FP32 subnormal endpoints, smallest FP32 normal, HALF underflow/normal transitions, parity-sensitive midpoint neighbors, values around 1 and 2, 65504/65520/65536 overflow boundaries, max finite FP32, ±infinity.
- Eight signed quiet/signaling NaN encodings/payloads, each in all four channels: **32 unscored NaN components**. Input bits stay raw, and future output half bits will be reported literally. There is no NaN normalization or expected payload/quiet-bit assumption.
- Last row has 24 active vectors; eight inactive tail threads and unused cells remain poison.

Array poison is raw half bits **0x7e55** in every component, uploaded by Driver memory copy, not a formatted conversion. Borders and unused last-row cells must remain bit-exact. Interior exceptional values are unrestricted and never conflated with an unwritten-NaN test; analyzer scores known inputs and reports every unknown NaN raw.

## 3. CPU reference hypotheses and tests

`fixture_cpu.py` implements two integer-only hypotheses, **not asserted hardware policies**:

- RNE: nearest, ties-to-even, gradual HALF underflow, signed zero; finite overflow to signed infinity.
- RTZ: magnitude truncation, gradual HALF underflow, signed zero; finite overflow to signed max finite.
- Both preserve infinity as a hypothesis. NaNs return `None`; serialized reference slots have zero placeholders **only with mask=0**, never normalized expectations.

Eight tests verify:

1. Exact roundtrip of every non-NaN HALF encoding (both signs, infinity, signed zero).
2. Every adjacent finite positive HALF midpoint and ±one-F32-ULP neighbors, both signs, including subnormals and tie parity (with overflow checked separately).
3. 20,000 deterministic random FP32 encodings: RNE versus independent Python `struct '<e'`; RTZ versus independent exact-rational bracketing/truncation bounds.
4. Explicit underflow/overflow/infinity/signed-zero cases and unknown NaN policies.
5. Full generated fixture bytes/hashes/masks/reference files; all known fixture RNE values also checked against independent `struct`.
6. Exhaustive positive channel/interval/control coverage and discriminator count.
7. Exploratory coverage in all four channels.
8. Synthetic CPU-generated complete guarded arrays for each policy/domain: exact analyzer mismatch/discriminator counts, range breakdowns, raw unknown NaN reporting, coordinate equivalence, launch-tail coverage, guard-corruption detection, wrong-size refusal.

The synthetic arrays are test-only CPU objects, **not GPU output artifacts**. No `run-*` directory/output was created. Analyzer returns independent mismatch counts, signed/range grouping (so subnormal/overflow behavior cannot hide ordinary-range rounding), and same-input/multiple-output observations. Neither policy is forced to win.

## 4. Host safety and Main gate

`host.cpp` adapts Main-owned CUDA Driver resource/sync/cleanup patterns from the supplied Main host **without modifying it**:

- No linked CUDA/Runtime library (`readelf -d` checked); dynamic Driver loader constructed only after exact CLI, geometry, pin and **compile-time Main approval** gates.
- Delivered `build/blocked-host` prints `main_approved=0` on the CPU-only `--cpu-info` path. Worker did not invoke the GPU CLI, including its blocked form.
- One context/module/input buffer/array/surface per selected-domain invocation. One bounded kernel launch. No texture objects, original module or external GPU resources.
- Exact SM120 device/function checks. Full API-returned surface copied unchanged into align-8 argument +16 and queried back for owned array identity.
- Mandatory successful post-launch context sync before any readback; input re-read must be bit-identical; array guards checked. Raw output is saved, with no half-to-float or NaN canonicalization step.
- Cleanup performs another full drain. Failed drain skips individual destroys/frees and tears down the owned context. Failed surface destroy retains its backing array until context teardown. All CUDA errors and cleanup/logging failures cause failure; first error is preserved.
- New run directory only, constrained name/ordinal/domain, no clobbering old runs. Main approval/rebuild/run procedure is in `README.md`. Default verifier can only produce the blocked host.

A successful host exit would mean launch/resource/guard/input checks passed, **not** either rounding hypothesis or neural parity. Interpretation also requires successful full cleanup status. Approval is not inferred from Main's separate original-kernel authorization.

## 5. Pins and remaining boundaries before any conclusion

Delivered key SHA-256 values:

- Own CUBIN (5,784 bytes): `1d8b18e2f7d312a509061f29b3888032ed86ef5786682eafb18abbaafb94679d`
- Positive FP32 bits: `22a9c1296e013987c804048e52e0d0aa1dc9493edfc436946b978ce9e83e985b`
- Extended FP32 bits: `b8da8b5ec34a137460b4bd7fb7c0180e017a3c7285fd4fa1b07771acc4a2332b`

Exact source/host/header/fixture/build/evidence pins are in `SHA256SUMS`; kernel/host sizes and hashes in `RESULT.json`; tool/header/interpreter hashes in `evidence/toolchain-pins.json`; full commands in `evidence/commands.json`. Main's enabled host will necessarily have a different binary hash and must be pinned separately.

**Still unmeasured/unproven:**

- Actual module load, array/surface creation, hidden-constant population, launch, synchronization and cleanup for this own witness. Prior original success is useful context, not this witness's runtime evidence.
- Actual conversion on the selected GPU/driver: RNE versus RTZ (or neither/mixed), ties, signed zero, gradual HALF underflow/flush, overflow, infinities, NaN signs/payloads/quieting. NaNs remain observations even if a familiar encoding appears.
- No repeated-run stability, other architectures/drivers/formats, concurrency, OOB `.zero` behavior or texture behavior is tested. Tiny FP32-subnormal inputs round to half zero under both hypotheses, so this cannot by itself distinguish an earlier FP32 FTZ from ordinary underflow for those particular values.
- Exhaustive HALF intervals/exact HALF controls are **not every FP32 value**, and not the original kernel's actual pre-half values. Match results characterize tested inputs only; extend fixtures explicitly and re-pin before changing scope.
- Identical formatted SUST payload/whole-object input establishes the narrow static bridge, not all runtime state or a universal ABI guarantee. No manual opaque-handle manipulation is allowed.
- **Nothing here isolates the original (2,3) R residual as neural math or proves neural parity.** Correlate Main's separate original-RGBA32F outputs and final-half outputs only after both experiments are valid. Do not change production rounding based solely on this CPU/crossbuild preparation.
