# Plain Swin4H128 DS — bounded complete CPU/static reference

## Result

The **untouched original module02 `cc_tinlayout_fused_swin_4h_128_4_ds_fp8`** executes through its **original `ret` (PC5686) in all four warps** with the real **block14 slab**. One 8×8 CTA executes **2,944 MMAs, 12 original 128-thread barriers**, emits **8192 ordinary bytes** and **4096 downsampled bytes**. No instruction, loop, or barrier was removed. This is a conditional pure-DS CPU restoration, **not native activation/parity/readiness evidence**.

```sh
python -B reviews/nr-swin4h-ds-reference-20260911/verify.py
# Explicit synthetic fixture only:
python -B reviews/nr-swin4h-ds-reference-20260911/fixture.py --synthetic --reference-policies
```

Only this review is written. No GPU, Wine, compiler, header downgrade, installed-file change, main-working change, or sibling-review edit.

## Independent architecture and source/weight pins

Fresh architecture JSON **and independent graph-factory log** checks establish:

| Block | Historical identity |
|---|---|
| 9 | `4h_inpview_128` |
| 10–12 | ordinary `4h_shifted_128` |
| 13 | ordinary `4h_128` (unshifted) |
| **14** | **`4h_ds_shifted_128`**, 229936 bytes |
| 15 | `8h_inpview_256` |

Thus **10–13 are standard, not DS**. Blocks10–14 have explicit preceding `input_layers` links in both records. **Block15's input edge is absent** in these records: its name/order and byte-layout compatibility do not attest a native dependency. The historical shifted layer is paired with the plain arithmetic entry conditionally; negative origins are tested, but its actual native argument values/variant were not captured.

* DS exact `.entry` slice **[2364356,2597136)**, **232780 bytes**, SHA256 `b2d34eba53517c2fb377aff6cbd4e9f63c03425fd620346011346f25c8a47191`.
* **block14** exact slab SHA256 `6c7a05c82b823e09b0b843f5dd399af7a006410f3587191f62a43205a872724d`; raw offset **831622**, sorted/aligned upload offset **833536**, checkpoint offset **845168**.
* Next8 `.entry` slice **[2170553,2401971)**, 231418 bytes, SHA256 `c9b46ae9a85747274f784f805301134bc01b41b5a2935a5422420119185a5961`.

`collect_evidence.py` freshly decompresses the DLL's exact PTX records and compares the complete module bytes, preserves **PTX 9.4 / sm_120** headers verbatim, verifies PE resource = raw container = checkpoint bytes, and extracts block14 without relabeling. `EVIDENCE.json` contains all source identities, block9–15 slab pins, and historical records. Nominal F16 serialization is **not** treated as a dense F16 matrix layout.

## Own ABI — not inherited from another DS

The DS declaration and all seven parameter instructions independently prove an **88-byte aggregate**. Source pointer def/use propagation reaches every global access:

| Offset | Original DS role |
|---|---|
| +0 | packed input `%rd1` |
| +8 | ordinary output `%rd10`; four b128 store sites |
| +16 | block14 slab `%rd11` → `%rd2`, other learned pointers |
| +32,+36 | signed H,W |
| +40,+44 | signed X,Y; effective origin `(X+8*CTA.x,Y+8*CTA.y)` |
| +72 | downstream `%rd12` → global `%rd9`; v2.b16 projection stores and excluded padding stores |
| +80,+84 | downstream padding dimensions, **not input-view overrides** |

**[24,32) and [48,72) are unread**, independently poisoned in tests. Contract: H,W multiples of eight in **[8,256]**; X,Y and effective origins multiples of four in **[-256,256]**; explicit grid x/y in [1,64], z=1; exactly `(32,4,1)` threads. Input/ordinary spans are each `H*W*128`; downstream is `H*W*64`; exact block14 slab. All four spans must be nonzero, disjoint, nonwrapped, and every reached input byte must exist. Original OOB branches alone produce zeros; a wholly OOB CTA can legitimately read no input bytes and still complete.

**Only +80/+84 = (H/2,W/2) is certified.** Other padding pairs, broadcast/small dimensions, non-multiple-of-eight shapes, aliases/null pointers and missing policies reject before arithmetic. PC5340 takes the original return in this domain. The padding-only tail **PC5341–5685 and PC5687–5825** is retained and parsed, but intentionally not certified/executed. This is the precise excluded boundary, not silently simulated padding or missing-byte zero-fill.

## Original loops, operands and shared exchange

All **5826 static instructions** parse. Learned loop recurrences are checked against **this DS's** original initializers, updates, tests and backedges:

| PCs | Induction | MMAs per warp |
|---|---|---:|
| 252…754 | `%r4725 = 0,32,64,96` | 320 |
| 1302…1351 | `%r4727 = 0,32,64,96` | 64 |
| 1522…1623 | `%r4857 = 0,32,64,96` | 192 |
| 5109…5334 | `%r4858 = 0,128` (original two-pass predicate loop) | 32 |
| straight-line | original attention/output arithmetic | 128 |
| **total** | **736 × four warps** | **2944** |

For `t=0..3`, own slab recurrences are:

```
rd471 = slab + 1024*t
rd472 = slab + 82432 + 1024*warp + 4096*t
rd473 = slab + 101152 + 3072*warp + 12288*t
```

These constants are proved from original DS instructions, not borrowed from 1h/2h. Independent backward expressions check **all 123 static slab sites /740 dynamic warp loads**, actual addresses and loaded register bits, and direct E4M3x4 A/B, FP16x2 C/coefficient and FP32 uses. All slab sites reach a checked typed use. **229904 distinct slab bytes** are read; only `[98304,98320)` and `[98576,98592)` are unread. There is **no guessed or discarded projection tail**: the 32768 bytes `[197168,229936)` form the complete learned projection.

Own block14 FP32 query scalars at `180512+4*warp`:

| Warp | Raw bytes | Value |
|---|---|---:|
| 0 | `ef145941` | 13.567610740661621 |
| 1 | `becbff40` | 7.993620872497559 |
| 2 | `5a971a41` | 9.661951065063477 |
| 3 | `66778540` | 4.170825004577637 |

Barrier PCs: **212,1228,1296,1352,1420,2592,3540,3716,4642,5057,5058,5075**. Even the adjacent **5057/5058 barriers remain separate**. All releases require four actual converged warp arrivals, 128 participants. Independent addresses and last-producing byte/warp/epoch checks cover **69 shared sites /18560 events**, including **184320 cross-warp read-byte events**. Retained bytes persist; shared is not implicitly zeroed or reset between epochs. Reverse and interleaved scheduling give identical registers and outputs.

`TYPED_OPERANDS.json`, `SHARED_PROOF.json`, `STATIC_PROOF.json` and `COVERAGE.json` retain detailed evidence. Interior-plus-edge coverage is reported honestly; **not every static instruction in excluded padding/broadcast paths is claimed executed**.

### Numerical policy and scoped generic reuse

The freshly completed `nr-swin4h-reference-20260911` supplies **only generic strict warp arithmetic, byte-epoch shared semantics, four-warp scheduler, numerical policies and independent MMA operand oracle**. **No 4h inpview ABI/layout/learned offsets/fixture, nor any 1h/2h DS offsets, pooling or projection routines are used.** Its transitive dependency files remain pinned/read-only; their generic arithmetic imports do not make their DS ABI/constants this entry's contract.

* Every **individual k32 MMA** uses exact finite E4M3 dot plus half C, then **RN-half**. All 2944 are independently checked with a **forward** ISA lane/element map, rather than the VM's inverse placement. This is not one RN after k128, and not a tensor-core accumulation oracle. Exact zero follows the explicit +0 MMA policy.
* Original half2 operations and conversions remain in source order. Pool additions each round to half.
* RSQRT uses a reference RN-even FP32 `1/sqrt(x)` for positive normal inputs; zero/negative/subnormal/nonfinite inputs reject. Reciprocal uses reference RN-even FP32 `1/x`, FTZ output handling, and rejects zero/FTZ-zero denominators. Neither substitutes evidence for native `approx.ftz` bit equality.
* Missing operands/bytes/policies, unsupported opcodes, parser gaps, shared holes/races and mismatched barriers fail closed.

## Own pooling and 128→256 physical layout

Input and ordinary output are **packed 4×4×128 microtiles**, not an inpview reshape. For logical row `y`, column `x`, channel `c`:

```
m = 4*(y%4) + x%4
lane = 4*(m%8) + (c%8)//2
j = 4*((c%32)//16) + 2*(m//8) + (c%16)//8
packed_offset = 2048*((y//4)*(W//4)+x//4)
                + 512*(c//32) + 16*lane + 2*j + c%2
```

The original ordinary C fragments **`r2659..2674`, `r3710..3725` remain half-valued after the ordinary E4M3 stores**. Pooling shuffles read these retained registers, **never reload or quantize the ordinary output first**. Independently decoding the logical 8×8×128 tensor verifies:

```
pool = RNhalf( RNhalf(RNhalf(v00+v01) + RNhalf(v10+v11)) * 0.25 )
then E4M3(pool), then learned projection
```

For the real-slab synthetic fixture, incorrectly quantizing ordinary values first changes **520 /2048 pooled elements**. Tagged C-fragment tests independently exercise every ordinary output byte, retained-half pool, pooled shared byte, projection C element and downstream byte.

The projection uses **four separately rounded k32 dot products**, no assumed bias, and **two original output passes**. It has real channel permutations — omitting them is not a reshape:

```
old_channel(k) = 16*(k//16) + 2*((k%16)//4) + 8*((k%4)//2) + k%2
out_channel(n) = 16*(n//16) + 4*((n%8)//2) + 2*((n%16)//8) + n%2
```

For input group `q=0..3`, output warp `w=0..3`, pass `t=0..1`, local `k,n=0..31`, source-derived E4M3 weight location is:

```
lane = 4*(n%8) + (k%16)//4
ng = n//8
weight_offset = 197168 + 8192*q + 1024*w + 4096*t
                + 512*(ng//2) + 16*lane + 8*(ng%2) + 4*(k//16) + k%4
input channel  = 32*q + old_channel(k)
output channel = 128*t + 32*w + out_channel(n)
```

An independent dense projection (not replaying MMA addresses) checks **all 4096 projected half C elements** per CTA, then independently quantizes and checks all downstream bytes. Its weight offsets bijectively cover the entire 32768-byte learned tail. Channel labels here are defined by the original tensor/ISA/view placements, not inferred checkpoint axes.

Downstream is E4M3 **`[16,H/2,W/2,16]`**, 256 channels:

```
view_offset(y,x,c) = 16*(((c//16)*(H/2)+y)*(W/2)+x) + c%16
```

Synthetic 8×8 input SHA256 `03c7d40278e02130a5f14f5475e6f036da61f2157146c82624dce91f4299c5ed` gives ordinary SHA256 `6a722449d15db94598cb0dbc450667a78d89592b9e2eef703861971d9c4b0ee5`, downstream **4×4×256** SHA256 `dada843ebdbf7fdbe72ea168cbb0facba47f46b25ae82ae4157f385cd4fa769e`. These are reproducibility checks, **not native golden activations**.

## Static next8 compatibility — separate bounded boundary

Four original DS CTAs with synthetic H=W=16 produce a complete **8×8×256 /16384-byte** buffer, SHA256 `c04f7fe13777e13f44a32d78bcf057139eebd08b7cbf4c286451603045e181dc`.

The **original module03 next8 inpview body** consumes those exact bytes **without repacking**. Eight original generators reach their real first barrier **PC792**, 256 participants: **4096 scalar loads, every one of 16384 input bytes read exactly once, all 16384 staged shared bytes checked independently**. Tagged-byte and missing-byte tests also pass.

`next_machine.py` is the fresh generic machine with exactly one parser-declaration extension: accept the original **16384-byte shared allocation**, in addition to 8192. A test checks that exact textual diff. Headers/instructions/barriers are unchanged. The eight generators are deliberately held/closed at their actual first barrier; **no inserted return, barrier erasure, next8 learned forward, native activation or readiness is claimed**.

## Verification and separate main/native tracks

**16 CPU tests** cover source/slab/ABI identities, all independent MMAs, source load provenance, loops, retained shared epochs/barriers, dense pooling/projection, byte bijections, tagged ingress/C/stores, schedule reversal/interleaving, shifted rectangular sparse edges, nonzero CTA, wholly OOB input, and missing/alias/wrap/alignment/padding/policy failures. `verify.py` regenerates evidence, fixtures and proofs, runs tests, rehashes pinned read-only helpers/sources before/after, and verifies deliverable SHA256 sums.

**Main-working community-tone A/B remains a separate visual acceptance task.** No main renderer or installed asset was changed, and this synthetic arithmetic result says nothing about image preference or that A/B's outcome.

**Small native validation is also separate and was not run.** A future authorized minimal check should first attest actual selected plain/wait/tilesync and PTX/cubin identity, capture the exact launch/88-byte arguments/slab plus real input readiness, then capture both output buffers for one interior CTA and one shifted edge. Only after that can native MMA/approx differences and next8 dependency order be assessed. This review supplies a CPU/static comparison target, not permission to skip those checks.
