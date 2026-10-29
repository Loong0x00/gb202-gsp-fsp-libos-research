# Own block9 slab: 197,184 bytes, mixed types

Packet container F16[98592] is not the payload type. SHA256 `934cebc771cfa1ed086f47f018426090e14ca4326dcb22843cbc17dff9851c32`. All offsets are slab-relative, end-exclusive. No DLL offset translation or live binding was attempted.

|Bytes|Type / native fragment shape|Source role|
|---|---|---|
|0–65536|E4M3 [4,128,128]|Expand: 512 outputs total, K128|
|65536–81920|E4M3 [4,32,128]|Grouped contraction: N32,K128 per head|
|81920–98304|E4M3 [128,128]|Dense mix, seeded by residual1|
|98304–98320|unread16|No payload type inferred|
|98320–98576|F16 [128]|Residual1 gain: ld.b32 -> mul.f16x2|
|98576–98592|unread16|No payload type inferred|
|98592–147744|E4M3 [4,3,32,128]|QKV projection, native group coordinates|
|147744–180512|F16 [4,64,64]|Attention additive C fragments, not FP8|
|180512–180528|F32 [4]|Head scale: ld.b32 -> cvt.rn.f16.f32|
|180528–196912|E4M3 [128,128]|Dense output projection, residual2 seed|
|196912–197168|F16 [128]|Residual2 gain, two spatial uses|
|197168–197184|unread16|No payload type inferred|

Totals: **163840 E4M3 bytes;16640 F16 elements;4 F32 elements;48 unread bytes**. Actual load union197136 bytes. Field hashes, source load lines, nonfinite counts and raw gap bytes are in FIELD_MAP.json. SLAB_READ_MAP.json contains every slab load's lane/head/trip addresses and exact byte coverage, not just extrema.

## Complete coordinate maps

FIELD_ELEMENTS.json exhaustively maps every typed element's native-fragment coordinate to slab byte. These are PTX fragment coordinates, **not asserted original framework axes or an unstated channel permutation**. Hardware B/D lane conventions are explicitly represented and tested against actual source operands; native numerical semantics remain unvalidated.

Define a native N32,K32 B tile:

```
B(n,k)=512*(n//16)+16*(4*(n%8)+(k%16)//4)
      +8*((n%16)//8)+4*(k//16)+k%4
```

Relative-to-field offsets:
- Expand(h,n,k): `16384*h+4096*(k//32)+1024*(n//32)+B(n%32,k%32)`.
- GroupContract(h,n,k): `4096*h+1024*(k//32)+B(n,k%32)`.
- Mix / OutputMix(n,k): `4096*(k//32)+1024*(n//32)+B(n%32,k%32)`.
- QKV(h,g,n,k): `12288*(k//32)+3072*h+1024*g+B(n,k%32)`; g0..2 is an explicit native group index.
- Bias(h,m,n): `8192*h+2048*(m//16)+512*(n//16)+16*(4*(m%8)+(n%8)//2)+8*((n%16)//8)+4*((m%16)//8)+2*(n%2)`.
- Gains(c): `2*c`; scale(h): `4*h`.

The checker validates full field bijections and **655360 E4M3 B-operand byte tags plus32768 half C-operand byte tags** over actual four-head source accesses. Transport `.u32` does not determine payload type; consumers do. There are no borrowed 2H field/count assumptions.

## Raw / decode / reencode

`block9-slab-raw-copy.bin` is the own supplied slab, not the DLL. TYPED_SLAB.json gives each element's original little-endian bits plus exact finite decoded value; nonfinite entries retain raw bits with null numeric annotation. All fields and all unread gaps are reencoded from authoritative raw bits into `block9-slab-reencoded.bin`; SHA256 matches the supplied slab exactly.

fields.py separately implements finite E4M3 decode and RN-even satfinite encode: all254 finite encodings, signed zero, finite midpoint ties and saturation endpoints pass. NaN sign/payload canonicalization is deliberately **not** claimed; raw bits preserve it instead. This is codec/layout verification, not activation evaluation, full NN, original numeric execution or native acceptance. F16/F32 raw-bit preservation does not erase NaN payloads or treat packet gaps as weights.
