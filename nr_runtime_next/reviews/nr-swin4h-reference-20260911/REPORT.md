# Full bounded Swin4H inpview: CPU/static reference

## Result and historical/ABI corrections

Executable **module02 `cc_tinlayout_fused_swin_4h_128_4_inpview_fp8`**, through its **original `ret` in all four warps**. The 8192-byte DS-produced synthetic input is consumed without repacking; the actual block9 slab drives **2816 MMAs**, all three four-pass learned loops, **ten original 128-thread barriers**, and 8192 output bytes. No original instruction or barrier was erased. This is a conditional CPU reference, **not a native activation or parity claim**.

The user's corrected historical identities are confirmed, not silently relabeled:

* **block8 = 2h DS, 69936 bytes**, SHA256 `687d906bc5d6748b57ee3e519c114f9382d93db560b7f779461c1ab90f5237ae`.
* **block9 = 4h inpview, 197184 bytes**, SHA256 `934cebc771cfa1ed086f47f018426090e14ca4326dcb22843cbc17dff9851c32`. **Not block10.** Only this slab is accepted by the 4h API.

The aggregate happens to be **88 bytes**, but is proved from this entry's own declaration and six parameter loads—not inherited from 2h. Source def/use propagation reaches every global address:

| Byte offset | Own original 4h role |
|---|---|
| +0 | input `%rd10` → global `%rd1`; 16 scalar global load sites |
| +8 | output `%rd11`; sole root of all four b128 global stores |
| +16 | block9 slab `%rd12` → `%rd2`/`%rd5`; 115 global load sites |
| +32,+36 | signed H,W; output extents and default input extents |
| +40,+44 | signed X,Y; effective origins add `8*CTA.x/y` |
| +80,+84 | signed **input-view** H,W overrides; positive values replace default input extents |

**`[24,32)` and `[48,80)` are unread. In particular +72 is NOT a downstream pointer here**, unlike DS. +80/+84 are **not DS output-padding dimensions**. Unread fixture bytes are deliberately `0xA5`. `STATIC_PROOF.json` records every parameter instruction and every global pointer use.

```sh
python -B reviews/nr-swin4h-reference-20260911/verify.py
# Explicit fixture only:
python -B reviews/nr-swin4h-reference-20260911/fixture.py --synthetic --reference-policies
```

## Provenance and scoped reuse

Fresh read-only DLL PTX-record decompression matches the untouched module02 entry **[1899483,2114298)**, 214815 bytes, SHA256 `805e92d0dcceee5aaaf6c300ed2483abf0776be7ac1d8ff9fed03ff30f38e24c`. Offsets begin at `.entry`; the preceding `.visible ` is outside the slice. `module2-header.txt` preserves **PTX 9.4 / sm_120** verbatim. Fresh PE-resource/raw-container/checkpoint checks agree on both block8 and block9; nominal F16 storage does **not** establish a dense F16 weight layout.

`synthetic-ds-input-8x8.bin` is byte-identical to the freshly completed DS review's `synthetic-downstream-8x8.bin`, SHA256 `76302b3cfd47283519f4bb67ceb87d35b032440c4a124cea86156f63358cda41`: four synthetic block8 DS CTAs, 16×16×64 → 8×8×128. It is **not** a native middle activation. `EVIDENCE.json` retains source locations and identity checks.

The pinned 2h **warp arithmetic coroutine** is copied locally with exactly three textual changes: dependency import, accepting the original **8192-byte shared declaration** instead of 4096, and its scheduler docstring. A test checks that exact diff. Arithmetic/branch/collective semantics are unchanged. The **2h two-warp scheduler and barrier release are not reused**: new scheduling requires warps `{0,1,2,3}`, `%ntid=(32,4,1)`, matching full-warp arrivals, and all 128 participants before release. Shared byte epochs retain strict RAW/WAR/WAW and uninitialized-byte checks, with 8192-byte bounds. The declared shared base address zero is a bound address, never implicit initialized data.

Only this new review is written. No GPU, Wine, CUDA compiler, header downgrade, installed-file change, or sibling edit is performed. Zstd decompression and PE parsing are CPU/static operations.

## Full arithmetic, original loops and shared exchange

All **5404 static instructions** parse; interior+edge traces cover every instruction, including branch instructions and `ret`. Under the enforced conditional `(32,4,1)` launch, every warp executes:

| Original loop PCs | Induction at loop entry | MMAs per warp |
|---|---|---:|
| 832…1334 | `%r4417 = 0,32,64,96` | 320 |
| 1882…1931 | `%r4419 = 0,32,64,96` | 64 |
| 2102…2203 | `%r4549 = 0,32,64,96` | 192 |
| outside these loops | original straight-line arithmetic | 128 |
| **Total** | **704 per warp ×4** | **2816** |

The original initializers, updates, tests and backedges prove the slab pointer recurrences, with pass `t=0..3` and warp `wy=0..3`:

```
rd342 = slab + 1024*t
rd343 = slab + 82432 + 1024*wy + 4096*t
rd344 = slab + 101152 + 3072*wy + 12288*t
```

Independent backward source expressions evaluate **all 115 slab sites /676 dynamic warp loads**, check actual addresses and loaded register bits, and track direct typed uses: E4M3x4 MMA A/B, FP16x2 C and coefficient arithmetic, FP32 conversion. Every slab site reaches a checked typed use. **197136 distinct slab bytes** are read; unread ranges are `[98304,98320)`, `[98576,98592)`, `[197168,197184)`. Unread bytes are retained, not deleted or decoded speculatively.

Own block9 FP32 query scalars at `180512+4*wy` are:

| Warp | Raw bits (byte order) | Value |
|---|---|---:|
| 0 | `fc278d40` | 4.411130905151367 |
| 1 | `80926441` | 14.2857666015625 |
| 2 | `06ddc040` | 6.026980400085449 |
| 3 | `1c725f40` | 3.491339683532715 |

No 1h/2h scalar is borrowed. `TYPED_OPERANDS.json` contains the source expressions, site/load/register/role evidence and loop traces.

Original barrier PCs are **792,1808,1876,1932,2000,3172,4128,4314,5238,5402**. Each release has 128 actual participants. Independent source address expressions and last-producing byte/warp/epoch checks cover **all 64 static shared sites /17408 read-write events**; **172032 read-byte events cross warps**, with all four warps appearing as producers and consumers. The initial exchange writes all 8192 bytes. Later stages correctly retain the upper 4096 bytes across epochs before reading them at epoch 8; shared storage is neither reset nor implicitly zeroed. `SHARED_PROOF.json` records coverage, producer-consumer counts and barriers. Reverse and interleaved warp orders yield identical registers and outputs.

### Explicit numerical policies

* Finite E4M3 dot plus half C; **RN-half after each individual k32 MMA**, not a single-rounded k128 dot. Exact mathematical zero becomes +0 under this policy. Every one of 2816 MMAs is compared against an independent **forward** ISA lane/element placement and dot calculation, rather than reusing the interpreter's inverse operand map.
* Source half2 arithmetic and E4M3 conversions remain in source order.
* RSQRT substitutes correctly RN-even FP32 `1/sqrt(x)` on positive normal inputs; zero/negative/subnormal/nonfinite inputs reject. Reciprocal substitutes RN-even FP32 `1/x`, flushes subnormal outputs, and rejects zero/FTZ-zero denominators. These are **not native `approx.ftz` or tensor-core accumulation oracles**. Unsupported/nonfinite policy inputs fail rather than inventing values.

## Exact ingress and output representation

Ingress is physical **E4M3 `[8,H,W,16]`**, directly compatible with DS:

```
input_offset(row,col,c) = 16*(((c//16)*H+row)*W+col) + c%16
```

Each of four warps reads 512 scalar 4-byte loads; their byte coverage is disjoint and totals 8192 for an interior 8×8 CTA. Independent tagged ingress checks execute the **original full-body generators up to their actual first barrier**, gather all four arrivals, and verify every staged shared byte. No inserted `ret`, erased barrier, or missing-byte zero is used.

Output is **packed 128-channel 4×4 microtiles**, not the ingress view or a reshape thereof. Define logical channels by the original ISA C fragments:

```
m = 4*(row%4) + col%4
lane = 4*(m%8) + (c%8)//2
j = 4*((c%32)//16) + 2*(m//8) + (c%16)//8
offset = 2048*((row//4)*(W//4)+col//4)
         + 512*(c//32) + 16*lane + 2*j + c%2
```

An independent tensor decoder quantizes original unquantized C-fragment outputs `%r2939..2954` and `%r3999..4014`, maps each logical element, and checks all output bytes. Tagged tests independently check all four original store sites. Both layout maps are bijections over an 8×8×128 tile; output SHA256 for the supplied fixture/policies is **`0422ff26b9c9dedc3e4f547330b27b62bc9f037059739324e6c3a1340dacd312`**. This hash is reproducibility evidence, not a native golden result.

## Bounded contract and verification

API: `swin4h_reference.run(a, patches, weights, input_size, output_size, ..., abi=ABI, grid=..., mma=..., rsqrt=..., reciprocal=...)`. H,W are multiples of four in `[8,4096]`; X,Y and effective origins are multiples of four in `[-4096,4096]`. Explicit grid x/y is positive and ≤1024, z=1; CTA z=0. Input/output spans are each exactly `H*W*128` bytes, disjoint/nonwrapped/nonzero and separate from the exact block9 slab. Input may be sparse, but **every reached byte must exist**. Only original OOB branches create zeros; an entirely OOB CTA can legitimately consume no input bytes and still execute all barriers.

Only input-view override `(0,0)` or `(H,W)` is certified. **Broadcast/extended input views, other padding/override pairs and non-multiple-of-four geometry are rejected before execution.** Missing policies/operands/bytes, aliases, unsupported opcodes, unparsed source, shared holes/races, mismatched barriers, early retirement and wrong slab identity fail closed. No uncertified path is claimed as supported merely because the parser accepts its source.

**15 CPU tests pass**: own ABI and identities, exact machine adaptation, all typed loads/scalars, all independent MMAs, three original loops, all shared producers/epochs/barriers, tensor-layout bijections, tagged ingress/stores, reversed/interleaved scheduling, shifted rectangular sparse edges, nonzero CTA origins, full static instruction coverage and negative cases. `verify.py` regenerates evidence/fixture/proofs/tests, rehashes protected read-only sources/helpers before and after, and checks all deliverable SHA256 sums.

Separate and **unproved**:

1. **Native variant selection:** plain versus wait/tilesync and PTX versus cubin; native launch/argument capture.
2. **Native numerical parity:** real tensor-core accumulation and approximate-instruction bit equality.
3. **Native readiness:** predecessor epoch, stream/dependency/inter-CTA order and actual native activation availability.

These limitations do not truncate the bounded CPU forward: its maximal executable boundary is the original final barrier and `ret` for all four warps. See `BOUNDARIES.json`, `COVERAGE.json` and `VERIFICATION.json`.
