# Finalpost tile/address mapping — CPU/static continuation

## Result

Recovered more than a 512-byte slab constraint:

1. **All four aggregate `+08` load addresses**, neighbor order, signed `/4` arithmetic, zero substitution and singleton-axis broadcasting.
2. **Exact skip-byte → main-register-byte operand pairing** through the initial lane SHFL/SEL network and packed-half arithmetic. This is a **4:1 pairing relation**, not an invertible main/skip tensor reshape.
3. **Exact lane → two output coordinates**, plus the selected accumulator register/lane/half for each of four learned components. Coordinate packing is an invertible **8×8 tile**; component inversion is restricted to the actually selected register domain.

`tile_reference.py` provides raw-byte packing/gathering and these forward/inverse maps. It does **not** evaluate FP8, QMMA/HMMA, normalization or the finalpost network. No approximate matrix decode, NaN sanitization, torch, GPU, Wine, native launch or signed-DLL/native-CUBIN modification.

## Scope and identity

Read the required prior layout findings, SASS and manifest, and `../nr-static-binding-20260911/REPORT.md`. Native target remains:

- `cc_tinlayout_fused_post_block_swin_1h_32_fp8`, exact SM120.
- Native CUBIN SHA256 `feb368ff5279a7408b1e55554db6e468d7f114a24b18b2af8d7e6989a410c612`.
- Physical DLL SHA256 `e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e` (rechecked read-only).
- Function starts at CUBIN `0x187280`; carve starts at DLL file `0x1f9220`. Thus **CUBIN offset = PC + 0x187280**, **DLL file offset = PC + 0x3804a0**. PCs below are function-relative, not VAs.
- All 3,336 original function instruction encodings were checked against the retained CUBIN. Only **535 bounded selected instructions** are retained here; their bytes were also compared directly with the physical DLL. No all-kernel dump.

**Host identity, not layout intuition:** prior host proof has `+00 = I[0]` and `+08 = I[1]`, described by the launcher validation as “main + enc0 skip”. Accordingly `+08` is the **second / enc0-skip input**, not the late main input. The graph descriptor's block70 pairs `(69,0),(0,1)` are consistent with this, but graph-to-runtime-vector routing and producer packing remain untraced. **Do not reverse main/skip based on these layout results or declare a proved block69 upload path.**

## 1. Four skip loads: usable byte-address rule

Let the operation-derived fields be:

```
H = aggregate.u32(+20)        W = aggregate.u32(+24)
X = 8*CTA.X + aggregate.s32(+28)
Y = 8*CTA.Y + aggregate.s32(+2c)
h = trunc_signed(H/4)        w = trunc_signed(W/4)
ty = trunc_signed(Y/4)       tx = trunc_signed(X/4)
B = aggregate.pointer(+08)
```

For positive H/W, `h=H//4`, `w=W//4`. **Not ceil-divided.** Native `SHF sign → LEA.HI → SHF right2` at `0x0990/0x09d0/0x0a10` and `0x0a30..0x0b10` performs truncation toward zero, not Python floor division for negative X/Y. The earlier `LEA.HI RZ,lane,...` instructions do not shift the lane left: they preserve it as an addend. This distinction also matters for output coordinates.

For each `(dy,dx)` below:

```
valid_y = (h == 1) or (Y >= -3-4*dy and ty+dy < h)
valid_x = (w == 1) or (X >= -3-4*dx and tx+dx < w)
row = 0 if h == 1 else ty+dy
col = 0 if w == 1 else tx+dx
T = row*w + col
```

If both predicates are true, lane `l` loads a 16-byte bundle. Word `j` and byte `b` of that bundle come from:

```
address = B + 512*T + 16*l + 4*j + b
l in 0..31; j in 0..3; b in 0..3
```

Otherwise that entire bundle is **zero substituted; no memory access**. The invalid paths convert zero then duplicate the low half with `PRMT 0x5410`; this is zero padding, not a data-dependent NaN cleanup.

| Load order | `(dy,dx)` | Predicate at load | PC | Destination words |
|---|---|---|---|---|
| 0 | (0,0) | P0 | `0x0e70` | R24,R25,R26,R27 |
| 1 | (0,1) | P1 | `0x0e90` | R28,R29,R30,R31 |
| 2 | (1,0) | P2 | `0x11b0` | R20,R21,R22,R23 |
| 3 | (1,1) | P0 | `0x1270` | R4,R5,R6,R7 |

P0/P1 names are reused after earlier loads; they are not persistent semantic flags. `0x0d10` multiplies T by 128, `0x0d40` multiplies by 4 into a wide pointer, and `0x0e30` adds lane×16. The other bundles use the same construction.

**Broadcast is explicit:** `(H & ~3)==4` or `(W & ~3)==4` means the corresponding `/4` extent equals one. That axis collapses to index zero and bypasses its origin bounds. For positive fields this includes **4,5,6,7**, not only 4. Multiple load sites can read the same slab. This is not evidence that any particular logical NCHW dimension is broadcast.

Predicate simplifications are tested against the instruction transcription: `PLOP3 0x28` with third input PT is XOR; `0xe0` is `a & (b | c)`. These explain the special-dimension handling and address SELs at `0x0bd0..0x0d00`, not ordinary clamping.

Examples:

- H=W=128, CTA=(1,2), origin=(0,0): X=8,Y=16; tile indices **130,131,162,163**. Lane31's final byte of load0 is B+**67071**.
- H=W=64, X=Y=-4: only load3 is valid, reading tile0. X=Y=-3: tiles **0,1,16,17** all load. This deliberately preserves native truncation; it is not a proposed image-padding convention.
- H=4,W=7: all four loads read tile0, even with negative origins.

API guardrails: positive signed extents, nonwrapping signed X/Y, and `0 <= T < 2^24`. The native SHL intermediate is 32-bit and the subsequent `IMAD.WIDE` is signed; the simplified API **rejects** huge tile indices rather than silently pretending the formula is an unbounded integer address. The instruction transcription models native wrapping separately. Raw bytes are preserved unchanged by pack/unpack, including all 256 byte patterns.

## 2. Lane/component transformations before first QMMA

### SHFL and PRMT are not interchangeable tensor reshapes

At `0x1280..0x1330`, with `l=SR_LANEID`:

```
p = (l & 0x13) | ((l & 4)<<1) | ((l & 8)>>1)
R51 = p; R55 = p^16; R53 = p^8; R57 = p^24
```

`p` swaps lane bits2/3. Each of these four SHFL source maps is a permutation of all 32 lanes; p is its own inverse. `SHFL.IDX ... 0x1f` at `0x1370..0x1480` and `0x1640..0x1760` fetches the indicated source lane's packed half pair. The following SELs use **P3 = lane bit4** (`0x1180`) and **P0 = lane bit2** (`0x1340`). Those choices cancel two lane bits in the final main-operand pairing; do not stop at the SHFL permutation alone.

Default PRMT byte rules, writing least-significant byte first:

| Selector | Output bytes from inputs A,B | Relevant role |
|---|---|---|
| `0x7610` | A0,A1,B2,B3 | early lower-16-bit boundary flags, later masked by `0xffff`; not a tensor channel permutation |
| `0x5410` | A0,A1,B0,B1 | packed-half concatenation; A=B duplicates the low half, including zero-fill paths |
| `0x5432`, A=B | A2,A3,A0,A1 | swaps halfwords; used in later reductions |

`F2FP.F16.E4M3.UNPACK_B Rdst,Rsrc` takes byte0/1 into half0/1; `.H1` takes byte2/3. NVIDIA PTX documentation and an independently compiled, **never launched** SM120 probe cross-check that order (`isa-notes.txt`, `isa-probe*`). The CPU reference tracks tags only, not numerical conversions.

For the specifically requested first two bundles:

| Entry word | Bytes0/1 → destination @ PC | Bytes2/3 → destination @ PC |
|---|---|---|
| R24 | R85 @1940 | R68 @1b20 |
| R25 | R84 @1a10 | R69 @1a30 |
| R26 | R78 @1b40 | R82 @1b60 |
| R27 | R79 @1a50 | R83 @1a70 |
| R28 | R80 @1bd0 | R70 @1970 |
| R29 | R81 @1ac0 | R71 @1bb0 |
| R30 | R93 @1990 | R94 @1bf0 |
| R31 | R92 @1c10 | R95 @1c30 |

These are register lifetimes at their conversion PCs; later reuse of the same R number does not retain the original bytes.

### Concrete skip-byte/main-byte pairing, including its inverse relation

Define main-entry words **M38,M39,M37,M36** as R38,R39,R37,R36 after the predicated aggregate `+00` loads at `0x0850,0x0980,0x0a80,0x0b60`, respectively. Invalid entries are already zero. This report does **not** assign NCHW dimensions to these words or finish their full upstream pointer-layout proof.

For skip load `t=2*dy+dx`, destination lane l, and byte `k=0..15` within its loaded bundle, the main byte paired with it by the initial HMUL2/HFMA2 path is exactly:

```
main_lane = (l & 3) | ((l & 8)>>1) | (dx<<3) | ((k & 4)<<2)
main_reg  = ((38,37), (39,36))[dy][k>>3]
main_byte = k & 3
```

At the arithmetic boundary, skip conversion is multiplied by its packed weight, and added to a separately weighted shuffled main half. Example **`0x1af0 HFMA2 R85,R85,R103,R50`** pairs skip load0 byte0/1 with M38 byte0/1 from the above lane; R50 came from the main-side HMUL2 at `0x1950`. The map stops before numerical arithmetic/QMMA interpretation.

`input-pair-map.csv` enumerates **all 2,048 skip-byte slots** with exact HFMA PC, destination register/half, and corresponding main-entry tag. All **512 main-entry byte tags occur four times**: skip lane bits2 and4 vary freely. `inverse_main_pair()` returns those four preimages. This is deliberately **not a bijective permutation**, and does not authorize generating skip values from main values. The input pointers still refer to separate host operands.

## 3. Output coordinate and learned-component map

### Exact coordinates, two stores

For the observed 32-lane CTA, native integer instructions `0x9690..0x98c0` simplify to:

```
x = 8*CTA.X + origin_x + (l & 3) + 4*(l>>4)
y = 8*CTA.Y + origin_y + ((l>>2) & 3) + 4*s
s = 0 for store @0xaa90; 1 for store @0xcfd0
```

The second path adds exactly **R53 += 4** at `0xc110`; R52 is unchanged. Initial register coordinates are R52=x,R53=y. Useful local view:

```
lanes  0.. 3: x=0..3, y=0     lanes 16..19: x=4..7, y=0
lanes  4.. 7: x=0..3, y=1     lanes 20..23: x=4..7, y=1
lanes  8..11: x=0..3, y=2     lanes 24..27: x=4..7, y=2
lanes 12..15: x=0..3, y=3     lanes 28..31: x=4..7, y=3
second store: same x, y+4
```

Inverse for local x,y in 0..7:

```
l = (x&3) | ((y&3)<<2) | ((x>>2)<<4)
s = y>>2
```

First store is skipped by `0x98e0/0x9910/0x9970` → branch `0x9d00` if x<0, y<0, x>=W or y>=H. Second adds y+4 and checks the same bounds at `0xc140/0xc180` → EXIT `0xc240`. H is reloaded at `0xab60`. P0 retains/restores the x-upper-bound result across the optional first epilogue (`0xa0b0 P2R`, `0xa160 ISETP`). Thus a first invalid y need not prohibit a second valid y.

These are **surface coordinate registers**, not a recovered linear framebuffer address. The surface handle is aggregate `+10`; actual surface descriptor/format/row pitch remain unknown.

### Learned component source, independent of HMMA matrix interpretation

Immediately after `0x9510` has completed, name the first output snapshot registers `(R20,R21,R16,R17)`. For the second snapshot, after `0xc130`, use `(R48,R49,R12,R13)`. For learned component c=0..3 of output lane l:

```
source_lane = 4*(l & 7) + (c>>1)
source_reg  = snapshot_regs[l>>3]
source_half = c & 1
```

This is derived by replaying actual SEL/SHFL instructions, not a guessed QMMA fragment layout. Upstream `0x8090..0x8190` constructs `s=((l<<2)&28)+(l>>3)` and XOR1/2/3 variants; P4=lane bit0, P5=bit1, P6=bit3, P3=bit4 govern selection. Native first-path selectors/shuffles are `0x95d0..0x98f0` plus `0x9b50/0x9b70`; second-path equivalents are `0xc160..0xc230` plus `0xc390..0xc3c0`.

Before the color epilogue, components 0,1 come from first selected packed word, component2 from the second word's low half. **Component3 is the learned sigmoid logit, not surface alpha** (`0xa100`, `0xc640`). Actual surface alpha is prepared separately by the existing decode branch. `output-component-map.csv` lists both 128-component selections.

The component inverse is valid only for source lanes with `lane%4 in {0,1}` and the four snapshot registers: **128 selected halves per store**, all unique. Source lanes congruent to 2/3 modulo4 are not selected here. Their redundancy or matrix meaning is **not** proved; the inverse API rejects them rather than claiming all accumulator halves form a permutation.

## 4. Source PC / byte anchors

Bytes below are the original 16 instruction bytes in increasing file-address order. `selected-evidence.json` contains every retained instruction with both CUBIN and DLL offsets; `selected-assembly.txt` is the bounded readable counterpart.

| PC | CUBIN file offset | DLL file offset | Original 16 bytes |
|---|---|---|---|
| `0x09d0` | `0x187c50` | `0x380e70` | `11720b0b14000000ff108f0700e20f00` |
| `0x0d10` | `0x187f90` | `0x3811b0` | `2408090880000000ff008e0700e40f00` |
| `0x0d40` | `0x187fc0` | `0x3811e0` | `250802090400000002028e0700e28f00` |
| `0x0e30` | `0x1880b0` | `0x3812d0` | `250802a41000000002028e0700e20f00` |
| `0x0e70` | `0x1880f0` | `0x381310` | `810918020400000000fd1e0c00220f00` |
| `0x0e90` | `0x188110` | `0x381330` | `81191c040400000000fd1e0c00220100` |
| `0x11b0` | `0x188430` | `0x381650` | `812914040400000000fd1e0c00e20000` |
| `0x1270` | `0x1884f0` | `0x381710` | `8109042c0400000000fd1e0c00e20000` |
| `0x1370` | `0x1885f0` | `0x381810` | `89752d2e331f000000000e0000e81f00` |
| `0x1940` | `0x188bc0` | `0x381de0` | `3e7255ff18000000ff06000200e20f00` |
| `0x1af0` | `0x188d70` | `0x381f90` | `31725555670000003200000000e40f00` |
| `0x9890` | `0x190b10` | `0x389d30` | `107234101300000034e8ff0700e20f00` |
| `0x98c0` | `0x190b40` | `0x389d60` | `1172350235000000fff28f0700e20f00` |
| `0xaa90` | `0x191d10` | `0x38af30` | `9b7f00340c08ff6000af100800e22300` |
| `0xc110` | `0x193390` | `0x38c5b0` | `357835350400000000008e0700f60f00` |
| `0xcfd0` | `0x194250` | `0x38d470` | `9b7f00340804ff6000af100800e41100` |

## Verification and remaining gaps

From this directory:

```sh
TMPDIR="$PWD" /opt/cuda/bin/ptxas -arch=sm_120 isa-probe.ptx -o isa-probe.cubin
/opt/cuda/bin/cuobjdump -sass isa-probe.cubin > isa-probe-sass.txt
python -B inspect_mapping.py > collection.txt
python -B test_tile_reference.py > verification.txt 2>&1
```

**13 tests pass**, including:
- CUBIN hash and all original instruction-byte transcriptions; collector separately verifies selected bytes in the hashed DLL.
- **4,016** address/boundary cases versus a separate bounded native integer-instruction transcription, including signed origins, singleton extents and pointer low-word carry.
- Raw 512-byte pack/unpack and lane/word/byte address inverses; zero padding without reads; short buffers rejected.
- All four lane SHFL permutations, PRMT byte rules, and all **2,048** symbolic input pairings with their four-preimage inverse.
- All **64** output coordinates and inverses, origin/boundary cases, plus both **128-half** output component selections versus a separate native SEL/SHFL tag replay.
- CPU-only PTX compiler corroboration of `/4` LEA.HI semantics and the packed conversion opcode. The small **new standalone probe CUBIN** is not the native CUBIN and was never loaded or launched.

These are source/transcription and combinatorial checks, **not GPU parity evidence**. Still missing: producer-to-byte-slot/channel correspondence for enc0 skip; complete +00 pointer packing; graph-to-I-vector routing; complete weight/FP8 matrix layouts and numerical arithmetic; runtime argument values, textures/surface descriptors, upload/repack path and current D3D12 equivalence. The reference accepts/register-addresses already encoded bytes, **not a logical model tensor**. The recovered maps constrain a future implementation but do not make finalpost or block70 numerically executable.

All writes are confined to `reviews/nr-static-tile-20260911/`; existing native and prior-review files were read-only.
