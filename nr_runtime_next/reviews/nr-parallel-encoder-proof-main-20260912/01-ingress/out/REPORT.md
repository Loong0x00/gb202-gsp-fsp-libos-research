# Independent base INPVIEW ingress recovery

## Result and boundary

**PASS in the tested CPU domain:** transparent ingress equations match an independently written literal integer/load prefix on **593 cases, 18,976 lanes, 303,616 raw words, and 1,214,464 bytes**. Every word's actual load address or skipped-load guard, its four byte values, and its singleton-X predicate were compared. This is **not native, full-NN, learned-core, or universal numerical equivalence**.

- Entry: `cc_tinlayout_fused_swin_1h_32_1_inpview_fp8`.
- Independently counted source: **216,425 bytes, 14,159 lines, 5,505 instructions**. Independent second count: **5,561 semicolons − 56 register declarations = 5,505 instructions**. Multiline instructions and inline scope declarations are handled.
- PCs are zero-based instruction ordinals. Executable prefix is exactly **`[0,769)`**: 27 distinct opcodes, 16 global 32-bit load sites, 24 conditional branches, and six parameter-load sites. All raw words are final after PC754. PCs755–768 recompute wrapped origins and their signed /4 coordinates.
- Last executed instruction: PC768, line835, `shr.s32 %r33, %r3279, 2;`. First **unexecuted** instruction: PC769, line836, `cvta.to.global.u64 %rd71, %rd6;`.
- Only prefix integer/predicate/parameter/global-byte-load semantics exist in `prefix_checker.py`. Its executable instruction tuple excludes the suffix. No learned bytes are supplied. Merely loading the slab pointer from ABI16 is not dereferencing it.
- Requested/packet model metadata: `openai-codex/gpt-6-astra`, `xhigh`. Provider/model routing is not independently attestable from these files.

## Exact ABI and high-level equations

The aligned-8 parameter block is 96 bytes. Pointers are raw uint64; dimensions/origins/overrides are uint32 bit patterns interpreted as signed32 where shown.

| Offset | Field |
|---:|---|
| 0 | Source input pointer A |
| 8 | Output pointer (not dereferenced here) |
| 16 | Slab pointer (not dereferenced here) |
| 24,28 | Logical H,W |
| 32,36 | X,Y origin |
| 72,76 | Independently positive signed source H,W overrides |

Those six parameter loads cover `[0,40)` and `[72,80)`; no other ABI bytes are read by this source. Poisoning `[40,72)` and `[80,96)` leaves all 32 literal lane states unchanged.

Define `u32(v)=v mod 2^32`, `s32(v)` as interpretation of those bits in `[-2^31,2^31-1]`, and `u64` similarly. For local pixel `(ly,lx)` in `[0,8)^2`:

```text
hs = s32(Hoverride) if s32(Hoverride)>0 else s32(H)
ws = s32(Woverride) if s32(Woverride)>0 else s32(W)
ox = s32(u32(X) + u32(u32(ctaid.x)<<3))
oy = s32(u32(Y) + u32(u32(ctaid.y)<<3))
x = s32(ox + lx)
y = s32(oy + ly)
y_ok = (hs==1) or (0<=y<hs)
x_ok = (ws==1) or (0<=x<ws)
valid = y_ok and x_ok
sy = 0 if hs==1 else y
sx = 0 if ws==1 else x
```

For physical channel `k=0..31`, let `plane=k//16`, `quartet=(k%16)//4`, `b=k%4`. **Only when valid:**

```text
row = u32(sy + plane*hs)
words_per_row = u32(ws<<2)
word_index = u32(row*words_per_row + u32(sx<<2) + quartet)
load_address = u64(A + 4*s32(word_index))
byte_address = u64(load_address+b)
raw_byte = explicit_source_byte(byte_address)
```

This is planar16 source storage `[2][hs][ws][16]`, with conventional nonoverflow byte strides **channel=1, X=16, Y=16·ws, plane=16·hs·ws**. It is not `[hs][ws][32]`, scalar-channel-major storage, or a packed-output layout. The conventional formula `16*((k//16)*hs*ws + sy*ws + sx)+k%16` is not sufficient at overflow: the PTX narrows the **word** index, then **sign-extends it before multiplying by four**. Tests distinguish positive +4GiB offsets, negative −8GiB offsets, zero wrapped row strides, wrapped plane products, signed coordinate overflow, CTA shifts, and uint64 pointer addition.

If invalid, the entire corresponding word is literal integer zero and there is **no source access**. Size1 independently broadcasts even at negative/overflowed/out-of-range coordinates. A singleton on one axis cannot rescue a failed non-singleton guard on the other. Zero or negative overrides fall back; positive overrides may enable loads even when logical dimensions are nonpositive. Logical output geometry must not mask this ingress.

The two PTX guard-construction forms simplify to the same `valid` equation. All 16 Boolean valuations are checked in `guard_truth_table.csv`. `%p1..%p16` are X-singleton selection predicates, **not general validity flags**: each equals `(ws==1 and y_ok)`. They are compared against literal final predicates in every differential case.

The arithmetic reduction is by congruence modulo2^32: `mul.lo.s32`/`mad.lo.s32` preserve low product bits, and grouping row/plane/X/quartet additions is valid in that ring. Sign is restored specifically for signed comparisons and `mul.wide.s32`; it must not be lost at either point. `%r31`/`%r33` contain **truncation toward zero** of the wrapped origins divided by4, not Python negative floor division. Those values and the other exposed origin/dimension/pointer handoffs are checked too.

## Tensor, raw registers, and provenance

`ingress_candidate.py` has no PTX parser/interpreter dependency. It evaluates 64 pixel guards and 512 closed-form quartet addresses.

- `RawWindow.tensor`: 2,048 raw FP8-code bytes, shape **64×32**, row `8*ly+lx`, channel physical `k`.
- `RawWindow.addresses`: byte-level source provenance; `None` means predicate-generated zero. A loaded zero still has an address.
- `RawWindow.guards`: 64 independent full source guards.
- `RawWindow.raw_words()`: 16 raw register vectors, each 32 lanes.
- `RawWindow.tile_major_tensor()`: explicitly alternative 64×32 byte view, four TL/TR/BL/BR 4×4 tiles, row `16*tile+4*(ly%4)+lx%4`. This permutation alone proves no MMA/core semantics.

For slot `s=4*t+a`, lane `l`, and little-endian byte `b`:

```text
lx = 4*(t%2) + (l//4)%4
ly = 4*(t//2) + 2*(a%2) + l//16
k  = 16*(a//2) + 4*(l%4) + b
```

This maps all **16×32×4=2,048** operand bytes bijectively onto the window. Tile-local pixel row is `l//4+8*(a%2)`. Both row-major and tile-major byte views are checked against literal register bytes, without running MMA.

| Tile | Raw registers (a=0,1,2,3) | Load PCs |
|---|---|---|
| TL | r4631,r4633,r4634,r4635 | 62,108,153,199 |
| TR | r4637,r4639,r4640,r4641 | 244,291,337,384 |
| BL | r4643,r4645,r4646,r4647 | 429,475,521,567 |
| BR | r4649,r4651,r4652,r4653 | 613,660,707,754 |

`ingress_contract.json` also verifies each raw word has exactly its zero initialization and guarded load as prefix definitions, and records the source-valid/skip predicates, branch PCs and source lines. `provenance.csv` records all 2,048 bytes for original0 CTA(0,0), including raw register/lane/byte, tensor position, address, value, and load PC/line. Test comparisons cover provenance for every case, not just that illustrative CSV.

Physical K is intentionally **not labeled predecessor canonical neuron C**. The prior report mentions a predecessor permutation, but its underlying evidence is not among the authorized inputs; no such permutation is imported as independently established fact.

## Verification domain and actual input preservation

The exact cached PTX and original0 input hashes match the packet:

```text
original.ptx          e36a534b79b5361f853f1e8baf4cd63f80d85bd73259e46de36a31321568ce13
original0-primary.bin  56ee903cb43a4dd89ae177ea7b9a783ff30f7e06bfb95080e0c4af56eb2c2c4a
```

For original0, the test explicitly chooses **H=W=64, X=Y=0, no overrides**, and all 8×8 CTAs. This is a declared test ABI, not a freshly recovered host launch. The 131,072 source bytes are covered once each, reconstructed in source-address order, and equal the original input exactly. All 64 windows retain nonzero payload. **190 actual 0x00 bytes and 179 actual 0x80 bytes are preserved**; none are replaced by a whole-window padding rule. Four additional original0 boundary cases are checked.

Separate synthetic cases: 128 geometry, 96 negative-origin, 49 override, 11 nonpositive-dimension, 108 singleton, 20 uint32-wrap, 8 uint64-pointer-model, 96 seeded edge, 5 empty-guard, 3 raw-code preservation, and 1 explicit partial-window test. Address-tagged synthetic bytes are stored in an **explicit finite map**: absent bytes are errors, not generated on demand. Dense all-256-code testing preserves every code, including 0x00/0x80/0x7f/0xff, without a numeric conversion or NaN claim.

- **769/769** static prefix PCs covered; **48/48** taken/fallthrough outcomes of 24 branches covered.
- **303,616** load-address-or-source-zero decisions and broadcast predicates compared.
- **718,912** predicate-zero bytes and **3,629** loaded-zero bytes remain separately identifiable across the differential cases.
- Fourteen intentional missing-input scenarios pass: eight distinct sparse holes, first-word lengths0..3, and guarded-in singleton/override loads with no bytes. Both implementations raise with the exact missing byte and 4-byte load address. All-guarded-out empty input performs no loads. ABI length and lane-range rejections are also tested.
- `test_results.json` counters describe the 593 complete differential cases; supplemental primitive, poisoned-ABI, and expected-exception checks are separate.

## Reproduce and scope limits

From the assigned directory, using only own generated caches:

```sh
PYTHONDONTWRITEBYTECODE=1 python out/prefix_checker.py
PYTHONDONTWRITEBYTECODE=1 python out/test_ingress.py
```

Minimal integration:

```python
from ingress_candidate import ABI, SourceBytes, ingress_window
abi = ABI.from_bytes(params96)
window = ingress_window(abi, (cta_x, cta_y), SourceBytes(primary_bytes, base=abi.input_ptr))
raw_row_major_64x32 = window.tensor
raw_tile_major_64x32 = window.tile_major_tensor()  # choose the consumer's explicit layout
```

`SourceBytes` never permits negative Python indexing or silent short loads. Its uint64-wrapping address space is a CPU model; extreme synthetic pointer cases establish neither native pointer validity nor allocation bounds. Input data is treated as immutable during the comparison. Live aliases/concurrent writes, host selection, warp/CTA launch shape, GPU visibility, numerical precision, learned weights, every MMA/core operation, and final outputs remain outside this proof. No tilesync/ordinary-entry equality is claimed.

**Access compliance:** 12 primary read units, each at most2,000 lines, documented in `readledger.json`: packet1, initial PTX view1, prior report1, full PTX ingestion8, binary ingestion1. Later project-data reads use own `out/` caches only. The DLL copy was **not opened/read/hashed/loaded/executed**. No frozen NN files or outputs were read; no full NN/original learned kernel, native/GPU/Wine/network/deployment/gate action, outside discovery, or nested agent was used. All writes are in this worker's `out/`. Do not rerun one-time ingestion; it now refuses when the ledger already exists.

`failures.json` preserves the two corrected exploratory parser issues. The final differential suite has no unresolved failure. Main must review the byte-view and address contract and separately establish all learned-core/MMA claims before integration.
