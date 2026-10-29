# Original Swin8H block15: full bounded CPU/static reference

## Result

**All eight warps reach the original final `bar.sync 0` and `ret`.** This executes the untouched module03 `cc_tinlayout_fused_swin_8h_256_8_inpview_fp8` with the **real historical block15 slab**, all four original learned loops, 10,240 original MMAs, eight 256-thread barriers, and 16,384 output bytes for the supplied synthetic 8×8 fixture. No instruction/barrier was erased, and no unknown byte was replaced with zero.

**Conditional CPU reference only.** Input is deterministic finite **raw synthetic E4M3**, not DS14 output. **DS14 bridge, native variant selection, numerical parity and predecessor readiness remain unvalidated.** No GPU, Wine, CUDA compiler, installation change, PTX downgrade or sibling write is used.

```sh
python -B reviews/nr-swin8h-reference-20260911/verify.py
# Explicit fixture regeneration:
python -B reviews/nr-swin8h-reference-20260911/fixture.py --synthetic --reference-policies
```

## Independent source / graph / slab identification

Fresh CPU DLL-record Zstd decompression equals module03, SHA256 `fc7b019606d6f00a3dad501b39ec7a38fe0d904b9f187b0254b92935d40565b5`. Its original entry slice **[2170553,2401971)** is 231,418 bytes, SHA256 `c9b46ae9a85747274f784f805301134bc01b41b5a2935a5422420119185a5961`. The slice starts at `.entry`, after the preceding `.visible `; `module-header.txt` separately preserves **PTX 9.4 / sm_120 / 64-bit addresses** verbatim.

`architecture.json` block15 is independently joined by tensor name, serialized shape, byte size **and source offset** to the freshly parsed raw record. Its class and complete 32-operator sequence match the original `graph-factory.log`, not merely an entry-name substring. Fresh PE-resource/raw-container/checkpoint byte comparisons agree:

| Historical tensor | Bytes | Raw offset | Checkpoint offset | Aligned upload offset |
|---|---:|---:|---:|---:|
| `block15.layer0.layer` | 689232 | 1061634 | 1075104 | 1063936 |

Slab SHA256: `a3081eaee51296319ade0839add190cfdbe2adbf0f0a5e990df1f2a577ae9507`. Only those exact bytes are accepted. Nominal F16 container shape `[344616]` is **not** a dense F16 kernel layout. The byte-level typed operand proofs below additionally match all 109 original slab-load sites and their true bounded recurrences. Graph/block14 identity is retained in `historical-block14-15.txt`, but **no block14/DS14 byte bridge is claimed**. See `EVIDENCE.json` and `collect_evidence.py`.

## Own ABI and conditional launch, not inherited constants

The original declaration specifies an aligned **88-byte** aggregate. Six own parameter instructions and full global-pointer def/use propagation prove:

| Offset | Own original role |
|---|---|
| +0 | input `%rd7` → global `%rd1`; 16 scalar load sites |
| +8 | output `%rd8`; sole root of all four b128 stores |
| +16 | historical block15 slab `%rd9` → global `%rd2` and derived pointers; 109 load sites |
| +32,+36 | signed H,W: output and default input extents |
| +40,+44 | signed X,Y; actual origins add `8*CTA.x/y` |
| +80,+84 | signed **input-view** H,W overrides; positive values replace default ingress extents |

`[24,32)` and `[48,80)` are unread and deliberately poisoned with `0xA5` in the fixture. In particular **+72 is not a downstream pointer here**. Full pointer uses, parameter instructions and recurrences are in `STATIC_PROOF.json`.

The source declares **16,384 shared bytes**, not the 4h entry's 8192. Its own first exchange obtains `%r6 = %tid.y`, adds `%r6 << 9` to each 16-byte lane store, and places four tiles at offsets **0,4096,8192,12288**. Each warp owns 512 bytes per tile; `4096/512 = 8` warps exactly fill each tile. The API derives this quotient from checked source instructions. Tagged byte tests prove disjoint complete ownership for those eight warps. The shared symbol itself contains a `...4HLayer...` spelling: **the symbol/entry name alone is not the proof**.

The conditional launch is `(32,8,1)`, with 256 participants. There is no native launch capture or `.reqntid` proof here. The new scheduler requires all warp IDs 0…7, identical barrier PC/id, all 32 active lanes in each arrival, and no early retirement. Pinned generic strict arithmetic and byte memory machinery are reused read-only; the eight-warp scheduler, ABI, bounds, source recurrences and layouts are own-8h. `machine-changes.diff` records the local generic-machine adaptation.

## Full instruction loops and convergence

All **5900 static instructions** parse. Interior and shifted/rectangular edge traces together execute **every static instruction**, including all original backedges, OOB branches, barriers and final `ret` (`COVERAGE.json`). The original loops differ materially from 4h:

| PCs | Induction register and values at entry | MMAs per warp |
|---|---|---:|
| 831…1517 | `%r4439 = 0,32,64,96` | 576 |
| 2064…2113 | `%r4441 = 0,32,…,224` | 128 |
| 2284…2385 | `%r4571 = 0,32,…,224` | 384 |
| 5726…5775 | `%r4573 = 0,32,…,224` | 128 |
| outside loops | original straight-line arithmetic | 64 |
| **Total** | **1280 ×8 warps** | **10240** |

Own source initializers, increments, tests and backedges prove slab-pointer closed forms (slab-relative, `wy=0…7`, pass `t` in each loop's domain):

```
rd323 = 1024*t
rd324 = 295424 + 1024*wy + 8192*t
rd325 = 363552 + 3072*wy + 24576*t
rd326 = 623680 + 1024*wy + 8192*t
```

Shared induction pointers `%r4440`, `%r4474`, `%r4572` are `512*t`. The first loop is **four** passes, not eight; there is a genuine fourth learned loop absent from 4h. All original updates execute; these closed forms belong only to the independent checker.

Every MMA/transpose/shuffle requires converged full-warp participation. All CTA barriers are preserved at PCs **792,1990,2058,2114,2182,3362,5721,5898**. Forward, reverse and interleaved warp schedules produce identical final registers and output bytes.

## Shared ownership and typed slab proof

Independent backward source expressions evaluate all **68 static shared sites / 63,488 dynamic lane events**. A separate byte-level producer ledger checks each read against its last actual producing `(epoch,warp,lane,PC)` and value. **802,816 read-byte events cross warps**; all eight warps appear as both producers and consumers. Initial staging writes all 16,384 bytes. Storage persists across all epochs; notably epoch6 reads retained epoch4 data before writing its next exchange. It is never cleared at a barrier. Shared holes, bounds/alignment violations, RAW/WAR/WAW without the necessary barrier and incomplete releases reject. See `SHARED_PROOF.json`.

All **109 slab sites / 1864 dynamic warp loads** have independent source-derived offsets, exact loaded-register-bit checks, and direct typed-use coverage: **E4M3x4 MMA A/B**, **FP16x2 C/coefficient arithmetic**, and **FP32 scalar conversion**. The checker covers **689184 distinct slab bytes**. Preserved unread ranges are:

```
[360448,360464), [360976,360992), [689216,689232)
```

Own query scalars are FP32 at `623136 + 4*wy`, not borrowed 1h/2h/4h constants:

| Warp | Raw bytes | Value |
|---:|---|---:|
| 0 | b2a0e240 | 7.08211612701416 |
| 1 | 58213140 | 2.767660140991211 |
| 2 | 6644bc40 | 5.883349418640137 |
| 3 | a0c44d41 | 12.860504150390625 |
| 4 | 7d8a9f40 | 4.985655307769775 |
| 5 | 73347e40 | 3.9719512462615967 |
| 6 | 1ae40c41 | 8.805688858032227 |
| 7 | 5ed2a840 | 5.275679588317871 |

`TYPED_OPERANDS.json` retains every dynamic load, source expression, direct coefficient use and per-site typed-role counts. Its compact MMA records are summarized rather than duplicating 10,240 operand trees; the runnable checker checks them all.

## New actual instruction forms and explicit numerical policies

The eight newly encountered forms are **`cvt.s8.s32`, `cvt.s32.s8`, `cvt.u32.u16`, `shr.u16`, `add.s16`, `sub.s16`, `setp.ne.b16`, `selp.b16`**. Local pinned NVIDIA PTX ISA documentation resolves the critical widening behavior (`new-op-isa-evidence.txt`):

* `cvt.s8.s32 %rs,…` chops to low8 then **sign extends to the actual b16 destination**; it does not merely write an unsigned low byte.
* `cvt.s32.s8` reads only low8 of its actual b32 source, then sign extends to b32.
* u16→u32 zero extends; add/sub.s16 wrap modulo65536; logical `shr.u16` clamps an unsigned shift amount to16; b16 comparison/select preserves bits.

Only the actual operand-width forms are certified; an explicit opcode whitelist rejects unknown forms even on unexecuted/predicated paths. Tests exhaust all 65,536 low16 inputs plus high-bit source patterns and shift boundaries. The original 4015…4922 gather stage is separately tested with a tagged half bank against a closed-form lane/half mapping. This isolated instruction test **does not replace** the full forward or remove any barrier from it.

`NUMERICAL_POLICIES.json` is the explicit contract:

* Finite **exact E4M3 dot + half C, RN-even half after each original k32 MMA**, not a once-rounded multi-pass dot. MMA exact zero is +0; overflow/NaN rejects. **All 10,240 MMAs** are compared against an independent **forward ISA fragment placement** and dot computation, not the machine's inverse mapping.
* Source half2 add/mul/fma retain separate source rounding boundaries, gradual half subnormals and defined signed-zero rules; no speculative native contraction. Half arithmetic overflow/nonfinites reject. FP32/half conversions and E4M3 packing use source order; NaN payloads are unsupported. The satfinite conversion primitive saturates infinity, but the full arithmetic domain is finite-only.
* Explicit RSQRT policy substitutes correctly RN-even FP32 `1/sqrt(x)` on positive normal inputs. RCP substitutes RN-even FP32 `1/x`, rejects FTZ-zero denominators and flushes subnormal results. **Neither is a native `approx.ftz` oracle.**

## Independent input/output representation

Ingress is physical E4M3 **`[16,H,W,16]`**:

```
input_offset(row,col,c) = 16*(((c//16)*H+row)*W+col) + c%16
```

Each warp loads 512 scalar four-byte words. Tagged tests suspend all **original full-body generators at the first actual barrier**, gather all eight arrivals, and compare all staged bytes against an independent ingress/tile map. No inserted `ret` or zero-filled shared memory is used.

Output is packed **256-channel 4×4 microtiles**, not ingress order or dense F16. Logical channels are defined by original ISA C fragments, not checkpoint axes:

```
m = 4*(row%4) + col%4
lane = 4*(m%8) + (c%8)//2
j = 4*((c%32)//16) + 2*(m//8) + (c%16)//8
offset = 4096*((row//4)*(W//4)+col//4)
         + 512*(c//32) + 16*lane + 2*j + c%2
```

The independent decoder forward-places **unquantized `%r4574…4605` C fragments**, independently quantizes each half, and checks every output byte and all four store PCs **5845,5862,5884,5897**. A separate tagged-C test exercises the original conversion/repacking/store chain, including its **0,2,1,3,4,6,5,7** register permutation per tile. Both tensor maps are bijections. Supplied fixture/policy output SHA256 is **`41cffd85120dd8f72be25242047fd56175dc3fa9eef0d1e5726d330b2f87ddac`**, a synthetic reproducibility hash, **not a native golden result**.

## Bounded API and verification

`swin8h_reference.run` requires an explicit own ABI acknowledgement, exact block15 slab, all three numeric policies and grid. H,W are multiples of4 in `[8,64]`; X,Y and effective origins are multiples of4 in `[-64,64]`; grid x/y are in `[1,8]`, z=1. Only input-view override `(0,0)` or `(H,W)` is certified. Input/output spans are each exactly `H*W*256`, disjoint/nonzero/nonwrapped and separate from the slab. Sparse input is allowed **only if every reached byte exists**. An entirely OOB CTA legitimately consumes no input while executing all original loops/barriers.

**14 CPU tests** cover complete independent MMAs, all typed slab/shared sites, original loops and convergence, exhaustive new-op semantics, tagged ingress/output, tensor bijections, schedule permutations, sparse rectangular edges/nonzero CTA origins/full instruction coverage, and fail-closed policies/unknown bytes/aliases/wrong geometry/operand forms/shared races/deadlocks. `verify.py` reruns fresh provenance, fixture/proofs and tests, checks protected read-only sources/helpers before/after, and generates/checks `SHA256SUMS`. See `VERIFICATION.json`, `tests.txt` and `BOUNDARIES.json` for recorded outcomes and remaining native/DS14 limitations.
