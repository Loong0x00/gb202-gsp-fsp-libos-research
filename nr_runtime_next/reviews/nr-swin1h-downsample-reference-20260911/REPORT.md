# Plain Swin1H DS — conditional CPU arithmetic reference

## Result

Executable original `cc_tinlayout_fused_swin_1h_32_1_ds_fp8`: **raw packed input → all 256 core FP8 MMAs → ordinary FP8 output → independently recovered pooling/shuffle → eight learned FP8 projection MMAs → downstream FP8 output**, through original `ret`, in the bounded domain below. All **5,982 static instructions** remain in the source; no replacement convolution, borrowed preblock averaging, default input bytes, or erased wait instructions.

This is **plain DS, not a native-selected kernel**. The actual DS wait launch was outside the current capture filter. Numerical results are conditional on explicitly supplied MMA/approximation policies. No GPU, Wine, compiler/header downgrade, installed/original file change, or sibling edit was used.

```sh
python -B reviews/nr-swin1h-downsample-reference-20260911/verify.py
```

Individual commands: `collect_evidence.py`; `fixture.py --synthetic --reference-policies`; `test_ds.py`. Each writes only here. `ds_reference.run(...)` accepts caller-provided 96-byte aggregate, sparse raw input, encoded slab, separate bounded output sizes and explicit numerical policies.

## Original bytes and historical slab

Both module00/plain DS and module01/2h inpview slices were compared with **fresh read-only decompression of the original DLL**, not just copied from another review. Original headers remain `.version 9.4`, `.target sm_120`. Exact entry bytes/hashes and DLL/resource/checkpoint identities are in `EVIDENCE.json`.

* Plain DS: module00 `[6663829,6898554)`, 234,725 bytes, SHA256 `8eb9c92ff8a4ffff1c7906589d789188dc2ee6ee05b685adc8dc2650406327e5`.
* Historical `block4.layer0.layer`: raw container offset **124246655**, **22720 bytes**, sorted 512-aligned upload offset **124261888**, SHA256 `f0d05533694577fa313f2655b00ada84f231f87ebc66ebbb7e8f0f7ea1ac88d2`.
* Historical block3 slab: 20,672 bytes, raw offset 20507372, upload offset 20513792, SHA256 `8f26be9b75d09960141bbf561a70e9628c269cc901934efdce362426ebbe1589`.

The container/checkpoint's nominal F16 shape **does not make these dense F16 weights**. `TYPED_OPERANDS.json` checks all 111 slab-load sites, lane addresses and loaded bits, records direct MMA B/E4M3 and C/FP16 uses, 64 direct packed-half coefficient uses, and the FP32 scalar at **19552** (`0x3f00dec6`, approximately 0.503399253). Slab unread ranges are `[8192,8208)`, `[8272,8288)`, `[19556,19568)`, `[22704,22720)`; unread storage is not invented data.

The historical factory log explicitly records block4 input layer 3, `cc_tinlayout_fused_swin_1h_ds_shifted_32`, and block5 `cc_tinlayout_fused_swin_2h_inpview_64`. It does **not** establish block4's current launch origin, grid, pointers, variant or execution epoch.

## Exact bounded ABI/layout

Plain DS aggregate reads: input `+0`, ordinary output `+8`, slab `+16`, H/W `+24/+28`, X/Y `+32/+36`, downstream output `+64`, padding dimensions `+72/+76`. Flags/predecessor metadata at other offsets are **not read by this plain entry**.

Certified domain: one `(32,1,1)` CTA warp; H,W in `[8,4096]`, divisible by four; origins divisible by four; effective CTA origins in `[-4096,4096]`; positive disjoint explicitly sized input/slab/output spans; `+72/+76` either `(0,0)` or `(H/2,W/2)`. Input holes, aliased outputs, absent policies, wrong slab size and uncertified geometry fail closed. An out-of-range spatial read becomes zero only where the **original PTX explicitly computes that zero**, never because memory is missing.

For effective origin `(X+8*cta.x,Y+8*cta.y)`, the four valid 4×4 input/ordinary microtiles have byte address

```
512 * ((Yeff/4 + tile//2)*(W/4) + Xeff/4 + tile%2) + 16*lane
```

Each lane reads/writes 16 bytes; full interior CTA reads 2048 and writes **2048 ordinary bytes**. Ordinary input/output is the same packed 32-channel format, not an NCHW reshape. An exact logical coordinate description is:

```
m = 4*(row%4) + col%4; t = (channel%8)//2
lane = 4*(m%8) + t
j = 4*(channel//16) + 2*(m//8) + (channel%16)//8
byte = 512*((row//4)*(W//4)+col//4) + 16*lane + 2*j + channel%2
```

These logical channels are defined by the source C-fragment/packing map, not an asserted checkpoint axis order.

### Recovered DS computation, not a preblock assumption

Ordinary stores quantize four half-result microtiles. DS **does not reload or average those quantized ordinary bytes**: it uses the retained **unquantized FP16 results** (`r2998..3013`, `r4117..4132`). Source shuffles gather each 2×2 neighborhood, with the tree

```
RNhalf( RNhalf(RNhalf(top-left+top-right) +
               RNhalf(bottom-left+bottom-right)) * 0.25 )
```

Then it quantizes to E4M3, performs a learned **32→64** projection, and quantizes that result to E4M3. This exact tree and spatial/channel permutation are tested against an independently reconstructed 8×8×32 tensor with nonuniform operands.

The projection's four 512-byte load blocks begin **20656, 21168, 21680, 22192** in the actual block4 slab. All eight MMAs use the source's explicit zero C accumulator. Do not substitute preblock offsets or `slab[-2048:]`: the final 16 bytes are unread.

For MMA reduction coordinate `k`, ordinary logical channel is

```
c(k) = 2*((k%16)//4) + 8*((k%4)//2) + k%2 + 16*(k//16)
```

For projection MMA `q=0..7`, column `n=0..7`, weight byte is

```
20656 + 512*(q//2) + 16*(4*n+(k%16)//4)
      + 8*(q%2) + 4*(k//16) + k%4
```

Its physical output channel is `16*(q//2)+4*(n//2)+2*(q%2)+n%2`. `projected_bytes()` independently pools, decodes these slab operands, computes the projection, quantizes and packs the result without consulting pooled/MMA/store registers.

### Output transition / next view

Downstream H'=H/2, W'=W/2, **64 E4M3 bytes per spatial element**. A CTA emits a clipped 4×4 tile, 1024 bytes when interior. Physical storage is **`[4,H',W',16]` bytes**, with

```
offset(row,col,c) = 16*(((c//16)*H'+row)*W'+col) + c%16
```

It is neither the ordinary packed-microtile layout nor ordinary output with new dimensions. In source store order `s=0..7`, lane `l`, rows are `Yeff/2 + 2*(s%2) + l//16`, columns `Xeff/2+(l//4)%4`, channel group `s//2`, and each store writes four bytes at inner offset `4*(l%4)`.

Original `cc_tinlayout_fused_swin_2h_64_2_inpview_fp8` has an **88-byte**, different ABI: input `+0`, slab `+8`, output `+16`, H/W `+32/+36`, X/Y `+40/+44`, input-view override H/W `+80/+84`. Its global ingress loads precisely the downstream `[4,H',W',16]` representation above, splitting raw words into E4M3 pairs before learned work. `next_boundary()` executes only the untouched prefix from its first parameter load through its last raw global input load, then stops **before conversion/learned/shared operations**. Enumerating `tid.y=0,1` proves a full 8×8 footprint of 4096 bytes; it does not attest a selected next launch or implement a two-warp 2h layer.

## Composition and tests

The deterministic H=W=16 fixture starts with 8192 explicitly synthetic, nonconstant packed bytes. Six plain-standard block3 CPU CTAs use the **real block3 slab**, origin **(-4,0)** and grid `(3,2)`, matching the *shape of the captured shift* but not captured activations/dimensions. They completely produce 8192 packed bytes.

Six DS CTAs then use the **real block4 slab**, explicitly synthetic origin **(0,-4)** and grid `(2,3)`. Interior DS CTAs read across **four block3 producers**, 512 bytes each. They completely produce 8192 ordinary and 4096 downstream bytes without holes/overlap. Both next-view ingress warp coordinates read all 4096 downstream bytes. `demo-summary.json` has ownership, sizes, policy labels and hashes; downstream SHA256 is `07520ef881b33707e82d9adcfcf4d21324e365eca1c6159db53a4e010a369f14`.

Thirteen tests pass: all 264 actual FP8 MMAs against independent forward fragment maps and finite binary64-exact dot/RN-half; all slab addresses/bits; independent tensor pooling/projection/output; tagged rectangular/shifted/edge packing; next-view tagged operands and OOB; missing-byte/alias/policy rejection; namespace isolation; source pins; and complete fixture hashes. The ordinary result also equals plain standard run with the **same block4 slab prefix on one fixture**—a bounded numerical cross-check, **not** a whole-source variant-equivalence certificate.

Strict replay is reused from the pinned preblock-full helper only for its loop-capable PTX instruction semantics, with an isolated injected copy of the pinned Swin primitive module. **No preblock ingress, weights, offset map, shared-memory model or F16 MMA is used**: all plain DS MMAs are FP8, and it declares no shared memory. Both score-normalizer regions (PC `[3440,4038)`, `[4211,4795)`) are independently alpha-equal to the previously checked standard regions. No generic import namespace is left overwritten.

Numerical policy: one exact finite dot+C followed by RN-even half **per MMA**, gradual half subnormals; caller-supplied RN-f32 reference rsqrt/reciprocal instead of native `approx.ftz`; literal half instruction rounding and E4M3 satfinite conversion. Nonfinite/overflow rejects. Native tensor-core accumulation, approximation error/FTZ, compiler contraction of unadorned half operations and SASS/PTX selection remain unproved.

## Current capture and exact gaps

`CAPTURE_BOUNDARY.json` independently parses submissions 5 and 13 of actual `20260911-155526-observer_on`: block3 chained, H224/W384, origin **(-4,0)**, grid49×28, input `0x255bdc00`, **output pointer** `0x2585dc00`, incoming flag pointer `0x245e1600`, outgoing flag pointer `0x245e2e00`, predecessor origin(-4,-4). These are **metadata, not activation/flag values**. The DS wait and its arguments are not captured. Historical block4 association therefore remains conditional, and **plain DS is not called native-selected**.

Remaining gaps:

1. **Execution contract:** DS wait/chained choice, its common-body equivalence to plain DS, incoming polling/flags, resets/epochs, publication/release, cache visibility, barriers/API order, and native next-layer binding. No execution effects are dropped by turning a selected wait kernel into plain arithmetic.
2. **Geometry:** singleton broadcast, non-four-aligned/odd dimensions/origins, multiwarp DS, and large/wrapped coordinates are not certified. The wrapper rejects them.
3. **Oversized downstream padding:** original code after BB27_44 contains grid-dependent loops and `bar.sync 0`, with override-based strides and eight 16-byte zero groups versus the main stores' fixed H/2,W/2 four-group FP8 layout. No matching allocation/host contract was recovered here. The full source and loop interpreter are retained, but the public wrapper rejects oversized overrides rather than claiming their layout, fabricating padding, or removing the barrier. In the certified domain the original predicates bypass that suffix. Null downstream destinations are also rejected rather than treated as a safe optional output.
4. **2h:** only the raw ingress boundary, not its learned arithmetic, shared memory, collectives, outgoing layout or execution contract.
5. No native numerical parity, full-model/dense-frame forward, captured input activations, or GPU result is claimed.
