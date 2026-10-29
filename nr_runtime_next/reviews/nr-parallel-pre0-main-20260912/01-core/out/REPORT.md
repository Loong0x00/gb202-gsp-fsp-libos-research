# Task A — independent pre0 learned-core reconstruction

## Result

Recovered a source-derived neuron/operand/weight map, **not a numerical VM-forward wrapper**. `FIELD_MAP.json` contains explicit logical weight-byte maps, all 272 MMA A/B/C/D register lists, logical D coordinates, versioned C definitions, source instruction ranges, typed slab fields, gaps, ABI consumption, nonlinear equations, and arithmetic caveats. No NN prediction or original/native execution was performed. Acceptance/freeze remains with Main.

Pinned source: 6459 indexed instructions, 264-byte ABI, 21696-byte slab. PTX, index, and slab hashes verified. All 6459 indexed instructions matched the raw PTX in order after removing the index-only `ret __terminal__` annotation.

## Exact typed slab fields

Intervals are **byte offsets, half-open**, relative to ABI+224's pointer. Matrix axes below are logical input→output, except the query/key seed.

| Bytes | Type | Logical shape / use | Main evidence PCs |
|---|---|---|---|
| 0–4096 | E4M3 | FFN expansion 32→128 | 1215–1287, 1601–1626, 1925–1950, 2249–2274 |
| 4096–8192 | E4M3 | FFN contraction 128→32 | 1527–1600, 1851–1924, 2175–2248, 2499–2572 |
| 8192–8208 | untyped | unread gap, 16 B | no load |
| 8208–9232 | F16 LE | embedding 16→32 | 812–837 |
| 9232–9296 | F16 LE | 32-channel initial residual gain | 839–1214 |
| 9296–9312 | untyped | unread gap, 16 B | no load |
| 9312–12384 | E4M3 | 32→96 Q/K/V projection | 2573–2698 |
| 12384–20576 | F16 LE | additive QK C seed, 64 queries ×64 keys | 4048–4103, 4827–4883 |
| 20576–20580 | **F32 LE** | scalar Q-normalization gain | 3075; cast 3445; multiply 3448–3510 |
| 20580–20592 | untyped | unread gap, 12 B | no load |
| 20592–21616 | E4M3 | final 32→32 projection | 4718–4759, 5484–5525 |
| 21616–21680 | F16 LE | 32-channel final residual gain | 2699–3074 |
| 21680–21696 | untyped | unread gap, 16 B | no load |

The scalar at 20576 decodes to F32 **0.5997287631034851**, rounded to half before use. Slab metadata `F16[10848]` is **not** its execution-time uniform dtype. All **109** slab load sites (44 vector +65 scalar-word loads) resolve; their byte union equals exactly **21636 typed bytes**. All **60 unread bytes** remain untyped, with exact raw hex recorded. No padding/metadata semantics are inferred from their contents.

## Embedding: own ONE-K16 map

Let lane `l=4*g+t`, `g∈[0,8)`, `t∈[0,4)`. Half index `h∈{0,1}`. In `m16n8k16.row.col`:

- A register `a`: `(m,k)=(g+8*(a%2), 2*t+h+8*(a//2))`.
- B register `b`: `(k,n)=(2*t+h+8*b,g)`.
- C/D register `d`: `(m,n)=(g+8*d,2*t+h)`.

Four A tiles use `[r487..r490]`, `[r499..r502]`, `[r503..r506]`, `[r507..r510]`. B N8 tiles use `[r491,r492]`, `[r493,r494]`, `[r495,r496]`, `[r497,r498]`. PCs **822–837 are 16 independent K16 MMAs**, with C=`r4782` (+0), not two K16 carries or a 32-input embedding. First D pair is `[r544,r547]`; every other D pair is explicit in the JSON.

For global computational row `r=16*tile+m`, the source ingress pixel index is:

```
pixel(r) = r%4 + 8*((r//4)%2) + 16*((r//8)%2)
           + 4*((r//16)%2) + 32*(r//32)
shared_byte(r,c) = 16*pixel(r) + 1024*(c//8) + 2*(c%8)
```

Thus the four computational row tiles correspond to 4×4 subtiles of the 8×8 ingress tile, **not** an unchecked row-major reshape. The JSON contains all 64×16 shared byte offsets. Every A half was checked against the source shared-load address.

Embedding logical weight byte address:

```
W16(c,n) = 8208 + 512*(n//16) + 64*(n%8)
           + 16*((c%8)//2) + 8*((n//8)%2)
           + 4*(c//8) + 2*(c%2)
```

Shared-store feature order at PCs126/140 is:
`rs15,rs16,rs17,1,rs2,rs3,rs4,rs495,rs494,rs496,rs14,rs499,rs498,rs497,rs500,0`.
These are 16 half features; conditional texture/host semantics remain ingress work. Constant features are not discarded from the learned operand map.

## FP8 maps, FFN equations, and exact carries

Use `F8` for source RN-satfinite E4M3 conversion. Use `M16/M32(A,B,C)` for a **single** source MMA with identified matrix operands and half C/D, leaving native internal arithmetic unspecified. These are matrix-neuron equations, not instruction-stream execution.

Canonical channels are half-MMA output `n`. FP8 pack conversion induces:

```
pi(k) = 16*(k//16) + 2*((k%16)//4) + 8*((k%4)//2) + k%2
```

Under the architectural E4M3 fragment map, A register `a`, byte `h∈[0,4)` has physical K `4*t+h+16*(a//2)` and row `g+8*(a%2)`; B register `b` has physical K `4*t+h+16*b`, column `g`. Logical source channel is `pi(K)`. The JSON's logical weight maps already pull back this permutation; no layout is guessed by reshaping.

```
W8(c,n,base) = base + 512*(n//16) + 64*(n%8)
              + 16*((c%8)//2) + 8*((n//8)%2)
              + 4*(c//16) + 2*((c//8)%2) + c%2
```

Expansion chunk `j` uses base `1024*j`; contraction K32 chunk `j` uses `4096+1024*j`. Thus [0,8192) is two complete 4096-byte matrices, but their **instruction schedule is interleaved EXP0→CON0→EXP1→CON1→EXP2→CON2→EXP3→CON3**.

```
E = M16(X,Wemb,0)
R0 = half_mul(E,g_ffn)              # unquantized embedding residual
Hj = phi(M32(F8(E),Wexp[:,32j:32j+32],0))
R(j+1) = M32(F8(Hj),Wdown[32j:32j+32,:],Rj), j=0..3
```

**The EXP fork converts E itself, not `E*g_ffn`.** PCs1224–1271 reference the original embedding D registers, while PCs1152–1214 create the half residual seed separately. All 64 contraction C tiles were checked: first C is that seed; each later K32 C is its predecessor's D. An FP64 whole-K128 dot with one final rounding, or separately adding the skip afterward, is not a source-faithful arithmetic claim.

Recovered activation, at all 128 packed-half output sites:

```
z = half_max(half_min(x,4),-4)
a = half_fma(-0.055908203125,abs(z),0.447265625)
b = half_fma(z,a,0.89453125)
phi(x) = half_mul(x,b)
```

The last multiply uses **unclipped x**. This clipped cubic SiLU-like gate is present; it is neither omitted nor replaced with conventional SiLU/GELU.

## QKV, normalization, attention, final projection

- QKV PCs2651–2698: `M32(F8(R4),Wqkv,0)`, logical **64×96**, split Q/K/V into 32 channels each; one head. Weight bases are **9312,10336,11360**.
- Q and K normalize independently over **32 channels** using half squares/add trees, an epsilon **floor**, F32 approximate rsqrt, then half conversion/multiply. No mean subtraction, mean-square division, or epsilon addition occurs. Epsilon is `half(f32bits(948045311))` (source F32 approximately `6.2e-5`). Only Q gets the separately rounded F32-slab gain. V is not normalized.
- QK score: **64×64**, computed as 32-query halves at **4088–4103 /4868–4883**. The FP8 K permutations on Q and K agree; byte-label proofs check every lane/operand. C is the explicit half seed, not zero and not a claimed conventional relative-bias representation.
- Seed logical address:

```
12384 + 512*(4*(q//16)+k//16)
      + 16*(4*(q%8)+(k%8)//2)
      + 8*((k%16)//8) + 4*((q%16)//8) + 2*(k%2)
```

- Attention score mapping is **not conventional softmax**. Each half score gets a half affine FMA using half-rounded F32 bit constants `1027077105`, `1067877303`, clamped to `[1.03125,1.5693359375]`. For each adjacent half pair, it performs the **whole-word** transform `((packed_bits << 5)+2146992128) mod 2^32`, then reinterprets its two halves. Cross-half carry must remain intact. There is no row-max subtraction or ordinary exponential instruction here.
- Mapped values are reduced over 64 keys with the exact half-add tree recorded in `FIELD_MAP.json`; approximate reciprocal is taken after an epsilon floor, converted to half, redistributed, multiplied **before** F8 probability conversion. `verify_reduction.py` proves the entire tree and row routing symbolically for **4096 probability scalar uses**, not just the unordered sum.
- PV PCs4702–4717 /5468–5483: **64×64 times64×32**, with two ordered **K32** carries, beginning at zero. V's half `movmatrix` transpose occurs before F8 conversion. Every V operand byte's row/channel identity was checked. There is no post-PV division.
- Final PCs4752–4759 /5518–5525: **32→32**, `M32(F8(PV),Wfinal,C=half_mul(R4,g_final))`. All 32 final C registers were checked against early, unquantized R4 and the **21616** gain field. This is not a QKV residual or quantized skip. Final Y has an F8 output fork and a selected-half side-output routing fork; this work does not assert a fully recovered side-output image ABI.

## Verification and limits

Ran `extract_static.py`, `build_field_map.py`, and `verify_reduction.py` using CPU/static standard-library analysis only. PASS checks include:

- PTX/index/slab hashes and all 6459 indexed source instruction matches.
- Every parameterized MMA B half/byte address, embedding A source half address, and all 4096 QK C seed elements.
- Every field map bijective onto its exact typed interval; full slab load union and all unread gaps.
- FFN K32 C carries, final early-R4 seeds, both PV K32 carries, all cubic activation patterns.
- QK/PV abstract operand identities and exact attention denominator add-tree/routing equality.
- Final sanity: strict finite JSON parsing, all three script ASTs, nine typed fields, four gaps, 272 MMA nodes and pinned6459/264 metadata PASS (`final_sanity.log`).

**Preserved failure:** `extract_static_failed.py` preserves the original failing script (reconstructed by reversing its sole annotation-normalization correction; not re-executed). `extract_static.log` records the first assertion at PC6335 because the index writes `ret __terminal__`, whereas PTX has `ret;`. The corrected comparison removes only that annotation; `extract_static_retry.log` records PASS. This was a source-comparison failure, not a numerical result. No failures were removed.

Unknowns that prevent native-equality claims:

1. MMA internal accumulation/rounding order; FP8 conversion exceptional values; half FMA/NaN/subnormal details; approximate reciprocal/rsqrt and FTZ arithmetic policy. Fragment interpretations are architectural assumptions corroborated by source label consistency, not native measurements or an allowed local ISA-spec input.
2. Host ABI builder, concrete slab pointer binding, launch/active-warp geometry, duplicate work/write ownership. The filler uses `tid.x+32*tid.y`; its natural interpretation requires blockDim.x=32. Learned operands contain no warp-id offset. No DLL bytes were inspected to establish host launch facts.
3. Texture ingress values/control ABI and final side-output/tail indexing need separate lifting. Source ABI unread gaps include **204–208 and232–240**. Typed consumption for all other ABI intervals is in the JSON, without claiming host field names.
4. No separate expansion/contraction/QKV/final bias addition appears; possible offline folding into constant features/weights is not excluded. Unread slab gaps are not promoted into guessed fields.

Only the post attention hypothesis was consulted, **after** pre offsets were independently resolved. Its 21808-byte slab and offsets (bias11472, final19680, gamma20704) were not adopted; pre source proves **21696 /12384 /20592 /21616**.

## Exact authorized input paths actually read

Required manifest:
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/01-core/PACKET.json`

Allowed input files actually read:
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/01-core/in/pre_inventory.json`
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/01-core/in/pre_identity.json`
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/01-core/in/pre_code_index.txt`
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/01-core/in/pre0.ptx`
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/01-core/in/pre_slab.bin`
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/01-core/in/post_attention_candidate.py.txt`

**No other allowed inputs were read.** In particular: no DLL/PE bytes, old reports, ingress reference, or other post candidates; no paths referenced inside those documents were followed. No network, CUDA/GPU, Wine, chmod, input mutation, or delegated agents.

Input-read accounting: seven bounded tool reads including the manifest, plus two extractor passes of 13 bounded chunks each = **33 input-read units**. Each text chunk is ≤2000 lines; each slab read is explicitly bounded at21696 B. The failed pass is included. Subsequent scripts consume only this worker's generated `out/` artifacts.

## Files changed / delivery

All paths below have the exact prefix:
`/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/01-core/out/`

- `FIELD_MAP.json` — primary machine-readable source-derived result.
- `REPORT.md`, `PROGRESS.md` — findings and bounded-task state.
- `extract_static.py`, `build_field_map.py`, `verify_reduction.py` — self-contained source/layout/symbolic checks; no external review imports.
- `extract_static_failed.py` — preserved original extractor that fails on the index-only terminal annotation; do not use as the passing verifier.
- `nodes.json`, `mma_nodes.json`, `load_addresses.json` — exact register/node/address provenance.
- `code.json`, `slab_hex.json`, `read_ledger.json`, `summary.txt` — worker-local extraction snapshots/audit support. `summary.txt` is the initial forward-address-pass snapshot; the completed **109-load** table is `load_addresses.json`.
- `verification.json`, `reduction_verification.json` — successful static checks.
- `extract_static.log`, `extract_static_retry.log`, `build_field_map.log`, `build_field_map_enriched.log`, `verify_reduction.log`, `verify_reduction_enriched.log`, `final_sanity.log` — retained execution logs, including the source-comparison failure.

Generated artifacts subsequently read by scripts/tools were exactly `code.json`, `slab_hex.json`, `nodes.json`, `mma_nodes.json`, `FIELD_MAP.json`, `summary.txt`, and the seven log files just listed. Script execution also reads the three generated `.py` files. These are worker-created files under the same exact `out/` prefix, not additional original inputs.
