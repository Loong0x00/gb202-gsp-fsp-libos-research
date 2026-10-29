# Original finalpost early prefix — CPU/static continuation

## Result

Implemented the complete **early prefix through both existing prehead handoffs**, not just a boundary report:

- Original raw **I0 main / I1 enc0skip** loads, their branches, signed address arithmetic, zero-padding and singleton broadcast.
- FP8 widening, original lane shuffles, three typed half coefficient tables, weighted merge and pre-FFN residual setup.
- **176 original FP8 MMAs**: 128 in the FFN producer/accumulation chains and 48 producing raw Q/K/V. Original A/B/C operand order and every slab address are replayed.
- Q/K squared-half reductions, clamping, explicit-policy reciprocal square root, learned query scale, and the 32 original V `movmatrix` transposes.
- Minimal numeric register dictionaries connect to **both** existing `ptx_slice.qkv_through_head` paths. A real-slab/synthetic-activation CPU integration reaches both learned half-output heads.

**19 tests pass.** No NumPy, guessed tensor reshape, NaN sanitization, GPU, Wine, assembly, modified module, PTX directive change, or write outside this new review directory. Existing kernel, packed weights and sibling reviews remained read-only.

This completes the source/operand-level connection, **not native numerical parity or real-image restoration**. In particular, native half-operation contraction, MMA arithmetic and approximate `rsqrt` remain explicit policy issues below. No observed main/skip activation bytes were present in the supplied observer run; all numeric integration fixtures are clearly synthetic.

## Reproduce / use

From the project directory:

```sh
python -B reviews/nr-ptx-prefix-20260911/collect_evidence.py
python -B reviews/nr-ptx-prefix-20260911/test_prefix.py
python -B reviews/nr-ptx-prefix-20260911/demo.py \
  --synthetic --stage prehead --rsqrt-rn --head
```

For real caller-supplied raw buffers, replace `--synthetic` with `--main FILE --skip FILE`, optionally `--args FILE --cta X Y`. Buffers must begin at the original aggregate's +0/+8 pointers. They are **not** accepted as NCHW tensors. The CLI will not silently invent them.

Python:

```python
import prefix_reference as prefix
from layout_reference import prehead_inputs

regs, loads = prefix.run_prefix(args184, main_bytes, skip_bytes, slab_bytes,
    cta=(1, 1), stage='prehead', rsqrt=prefix.rsqrt_rn_policy)
# Explicit opt-in above is NOT a native rsqrt claim.
# Default stage='qkv' needs no rsqrt policy and stops before normalization.

# With the existing prehead directory on sys.path:
import ptx_slice
rgb_logit_halves = ptx_slice.qkv_through_head(
    prehead_inputs(regs, store=0), slab_bytes, store=0)
```

`mma=` accepts an independent callback with 32-lane A/B/C raw fragments of widths 4/2/2 u32, returning 32 lanes × 2 u32. Tests inject the sibling prehead's independently implemented inverse-map MMA at **all 176 sites**. This is a CPU mathematical comparison, not a device oracle.

## Exact boundaries and required sets

All register lists are **original numeric PTX names**, with **32 raw u32 lanes per register**. Packed halves are low half first. `BOUNDARIES.json` enumerates all sets.

| Stage | Original PTX lines, inclusive | Outputs |
|---|---|---|
| `merge` | 11–2894 | merged `r944,r947,…,r1037` (32 words); actual pre-FFN scaled registers also retained |
| `qkv` | 11–8493 | raw residual `r2368..r2399`; Q `r2537,r2539,…,r2599`; K `r2938,r2940,…,r3000`; V `r3265..r3296` |
| `prehead` | above + 9095–10436, 10542–11636, 11751–11844 | scaled normalized Q `r2905..r2936`, normalized K `r3233..r3264`, transposed V `r3297..r3328`, raw residual retained |

The skipped interval 8496–9093 is **prehead-owned residual scaling**, not a missing residual producer. Q/K FP8 conversions are likewise left to existing prehead functions. This prefix deliberately stops before the unrelated output-coordinate loads at 11958.

Minimal inputs for `prehead_inputs(regs, store)` → `ptx_slice.qkv_through_head`:

- Store 0: Q **r2905..r2920**, K **r3233..r3264**, V **r3297..r3328**, residual **r2368..r2383**.
- Store 1: Q **r2921..r2936**, same K/V, residual **r2384..r2399**.
- Exactly **96 warp registers / 12,288 bytes per store**, not placeholder matrices. No score, learned residual, key/value or zero-C inputs are guessed.

Without an explicit `rsqrt` callback, `stage='prehead'` rejects **before replay**. The complete raw QKV/FFN stage remains independently usable. There is no remaining unimplemented prefix producer under the declared optional policy.

## Raw address and weighted-merge equations

`layout_reference.input_read_set` is independent of the interpreter. It emits every `(input, load-site, lane, relative-offset-or-None, byte-size)` and validates its simplified nonwrapping domain. `None` means **no memory access**, not reading nonexistent bytes then sanitizing them.

Let `H,W,X0,Y0 = aggregate.s32(+32,+36,+40,+44)`, `X=X0+8*CTA.x`, `Y=Y0+8*CTA.y`. Division below truncates toward zero.

### Main I0, aggregate +0

Let `h=H//2`, `w=W//2`. Main sites 0,1,2,3 are original `r5917,r5920,r5923,r5926`, corresponding to prior SASS snapshots M38,M39,M37,M36.

For `dy=site%2`, `plane=site//2`, lane `l`:

```
row = trunc(Y/2) + l//16 + 2*dy
col = trunc(X/2) + (l//4)%4
valid = (h==1 or 0<=row<h) and (w==1 or 0<=col<w)
row = 0 if h==1 else row
col = 0 if w==1 else col
offset = 4 * (4*((row + plane*h)*w + col) + l%4)
```

Valid lanes load one raw u32; invalid lanes substitute literal zero. The extra `plane*h` term is present in original lines 205–214 / 258–267. It must **not** be replaced by a guessed lane-major slab layout.

### Skip I1, aggregate +8

Use the prior recovered `/4` rule: four `(dy,dx)=(0,0),(0,1),(1,0),(1,1)` loads with 512-byte tiles and 16 bytes per lane. For valid tile index `T`, offset is **`512*T + 16*l`**. Singleton `/4` axes broadcast to index zero. Bounds include negative-origin thresholds `Y>=-3-4*dy`, `X>=-3-4*dx`, as already proved by the prior tile review.

Independent formulas versus literal PTX loads are tested at interior, negative, edge and singleton cases and with **both unchanged observed 184-byte aggregates**. `observed-args-input-readsets.json` retains exact read sets for CTA (0,0), (1,1), (96,56). This is address evidence only.

### Merge operand pairing and coefficients

For merged register `r(944+3*j)`, let `site,j0=divmod(j,8)`, `(dy,dx)=divmod(site,2)`, and byte-pair start:

```
pair = (0,4,2,6,8,12,10,14)[j0]
```

For half `h`, `k=pair+h`, the paired main byte is:

```
main_lane = (l&3) | ((l&8)>>1) | (dx<<3) | ((k&4)<<2)
main_site = dy + 2*(k>>3)
main_byte = k&3
skip_byte = k                  # from skip site, destination lane l
```

This preserves the prior **four-to-one** main/skip pairing; it is not an invertible reshape or permission to synthesize skip from main.

The scalar coefficient word at table base `b` is:

```
b + 4*((l&3) + 4*((j%8)//2))
```

Bases are **8272 main**, **8336 skip**, **8208 pre-FFN residual**, each exactly 64 bytes of packed half values. Literal PTX merge policy is `RNhalf(RNhalf(main*wm) + RNhalf(skip*ws))` per half. The independent merge reference checks **all 1,024 output words**, nonuniform inputs/coefficient bits and boundary cases. A following half product uses the 8208 table exactly where present in PTX.

## FFN/QKV operands and typed weight layout

`mma-weight-layout.json` records all **176** MMA line numbers, D/A/B/C register vectors, original half-pair → CVT → packed A lineage, and B u32 slab-address descriptors. It is generated from the pinned original source and verified against replayed registers for every A word and every one of the **45,056 B byte slots**.

For a recorded MMA with indices `m=0..15, k=0..31, n=0..7`:

```
A: lane=4*(m%8)+(k%16)//4; word=2*(k//16)+m//8; byte=k%4
B: lane=4*n+(k%16)//4;     word=k//16;          byte=k%4
C/D: lane=4*(m%8)+n//2;   word=m//8;           half=n%2
B slab offset = B_u32_address[word].base + 16*lane + byte
```

A's four registers each pack two quantized half-pair sources in the **listed operand order**. B is E4M3; C/D are packed half, including all nonzero residual/accumulation operands. No `reshape` of slab bytes establishes any of these maps.

The typed FP8 B regions read here are **[0,8192)** for the FFN chains and **[8400,11472)** for Q/K/V. Half tables occupy [8208,8400). Learned query scale is **f32 at +19664**, converted RN-half before the half query product. Bytes in gaps are not interpreted as padding zeros or coefficients.

The actual FFN activation is the original clamp/absolute/polynomial instruction sequence, **not a substituted GELU library call**. With half constants `-4,+4,-0.055908203125,0.447265625,0.89453125`, it evaluates `t=clamp(x,-4,+4)`, `u=FMA(-0.055908203125,abs(t),0.447265625)`, `v=FMA(t,u,0.89453125)`, then `RNhalf(x*v)`, honoring every original half boundary.

## Numeric and execution policies — important limitations

1. **FP8 exact conversion:** directly reuse source-pinned `nr-ptx-quantization-20260911/ptx_fp8.py` and `mma_fragments.py`. Import verifies hashes. Finite conversion, RN-even, saturation, packing and fragment maps are not independently guessed. FP8/half NaNs reject. Standalone half→FP8 primitive has the documented infinity saturation behavior; prefix arithmetic rejects nonfinite halves.
2. **Half operations:** integer exact add/mul/FMA with source-order RN-even, gradual subnormals, signed-zero handling, and finite-only result. Overflow rejects instead of producing a hidden replacement. **Native contraction is a real gap:** the retained ISA explicitly permits unadorned `mul/add` contraction; prior SASS shows an HFMA in the merge. This replay does not assert its separate PTX rounding boundaries match that fused native sequence.
3. **MMA:** default `mma_exact_rn` computes exact K32 sum plus typed C, then one RN-half per original instruction, with exact mathematical zero +0. Native accumulation order, precision, zero/subnormal handling are unspecified and **not asserted**. The callback is the strict native-comparison boundary.
4. **Q/K rsqrt:** no implicit fallback. Optional `rsqrt_rn_policy` computes correctly RN-even f32 `1/sqrt(x)` using a finite f32-lattice search and exact integer midpoint comparisons. No host float sqrt is used in production. Positive normal inputs only; zero, negative, subnormal/FTZ and nonfinite inputs reject. These slices widen positive clamped halves, so valid executions meet this domain. Native `rsqrt.approx.ftz.f32` has a documented error bound, **not unique bits**; this substitute is explicitly nonnative.
5. **Execution:** 4,200 selected original instructions, 32 statically forward branches. A single bounded static DAG sweep evaluates lane predicates and reconverges before collectives. Back edges, unsupported instructions, partial-warp collectives, missing operands, unmapped/misaligned loads and ambiguous overlapping byte regions reject. This is not a fake full GPU or an arbitrary iteration-limit fallback. No stores, surfaces or unknown external memory are implemented.
6. **Tail:** the connected demonstration additionally inherits existing prehead's explicit RN reciprocal and staged MMA/head policies. Its final values are learned RGB/logit **halves before output color decode**, not claimed final pixels.

## Verification and provenance

- `verification.txt`: **19 CPU tests**, including exhaustive **63,488 finite half** widening/roundtrip; 3,000 bounded scalar cases against independent binary64-exact arithmetic; 1,005 rsqrt cases with exact midpoint certificates and host comparison; every movmatrix element plus involution; 176-MMA oracle injection; all A/B operand layouts; address/padding/broadcast tests; independent nonuniform weighted merge; strict failure paths; both existing head paths.
- `synthetic-connected-demo.json` and `demo-output.json`: unchanged observed args01, real hash-pinned 21,808-byte slab, explicitly synthetic main byte `0x28` and skip byte `0x18`, CTA (1,1), both store outputs. First learned row is `[39242,39348,37548,45184]` as raw half bits for both constant-input paths. This is a reproducibility fixture, **not native observed evidence**.
- Original PTX SHA256: `b2471a490b1c5a8817689d14358d648283823ced2165f84b0fef3e13ee928bc8`.
- Encoded slab SHA256: `197024afb1f78602dc08cfd5ae87c413385237c5f537dd5dcfeae742be85eca8`. Read-only source span is `WEIGHTS_HT.bin[147406312:147428120]`, matching prior upload offset 147429888 and size 21808.
- `SOURCE_PINS.json` pins the original PTX, both actual aggregates, reused primitive source, inspected prehead boundary files, prior tile reference and locally retained NVIDIA ISA source. Prehead pins are a snapshot: if that sibling work changes its API, the integration check rejects pending reinspection.
- ISA excerpts retained here cover half add/mul/FMA, f32 rsqrt, shuffle semantics and movmatrix; full source is the already-fetched NVIDIA PTX ISA 9.4 text in the quantization review. Local verification was sufficient; no additional network fetch or device operation was needed.
