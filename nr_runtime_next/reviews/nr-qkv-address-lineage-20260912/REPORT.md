# QKV address lineage — rejected bridge claim / bounded static erratum

## Verdict

**REJECTED: the logical layer1-P → QKV → layer3 bridge remains open.**  This review does not turn ABI pointer equality, a 32,768-byte range, a byte bijection, or an invented `(offset, offset)` table into tensor/logical-address provenance.  In particular, `nr-split16h-attention-layout-20260912`'s `p_to_qkv_byte_map`, `qkv_to_layer3_byte_map`, and `512*i` chunk construction are not used as evidence here; Main's prior review and its erratum are retained unchanged.

What is newly established is narrower: pinned original PTX contains the instruction-boundary SSA described below.  It gives four real QKV bulk-copy sites, their source/shared-address SSA, a first exact shared-to-MMA-A family, the actual C load-to-MMA-C path, QKV output packing/stores, and the independent layer3 reader equation.  It does **not** supply the missing launch descriptors, valid predicate/CTA domain, logical index interpretation, or inter-kernel binding needed to compose those equations.

No GPU, Wine, host/DLL, installed file, PTX execution, PTX modification, live capture, or sibling write was performed.

## Explicit provenance (before candidate use)

`PROVENANCE.json` pins every read-only external artifact and `test_01` verifies it before inspecting a source form:

| artifact | SHA-256 | role used here |
|---|---|---|
| layer1 source PTX | `56d1a218…85fe9f945` | producer store facts only |
| QKV source PTX | `fb1585fc…eebb18f7` | primary address/SSA facts |
| layer3 source PTX | `6e8bd549…9788b4cd7` | reader facts only |
| Main P | `247fa40f…ea163a44`, 32768 B | provenance only; no inferred logical map |
| Main candidate | `6de6b9a0…78193fc9`, 32768 B | provenance only; **not** passed to layer3 |

The candidate's upstream status is `REAL_REFERENCE_POLICIES_EXECUTED_NOT_LAYOUT_OR_NATIVE_ACCEPTANCE`: Main reports 13,312 MMAs and real RCP/RSQRT policy checks, but also reports both logical layouts false.  It remains named `qkv-real-policy-UNVALIDATED-layout.bin`; this review neither relabels it nor treats it as a layer3 input.

## Source-derived QKV ingress SSA

All four static `cp.async.bulk.shared::cta.global...` instructions are present, each with an original 512-byte literal.  `S2`/`S3` are in the original loop; `r2882` starts at zero, increases by 64, and the source predicate compares the pre-increment value with 384.  Thus there are seven lexical loop iterations **if its original predicates admit the transfer**.  This is not a launch-wide coverage count.

| site / PTX line | source byte offset from QKV `rd5` | shared destination | static bytes |
|---|---|---|---:|
| S0 / 270 | `4 * (((r2782 + r2783) << 11) | r9)` | `shared_base + 4*(r8+r9)` | 512 |
| S1 / 356 | `4 * (((r2784 + r2785) << 11) | r9)` | `shared_base + 4*(r14+r9)` | 512 |
| S2 / 551 | `4 * ((r135 << 11) + (r139 << 7))` | `shared_base + (tid.y<<9) + r17` | 512 |
| S3 / 653 | `4 * ((r179 << 11) + (r183 << 7))` | `shared_base + (((tid.y<<9)&1024) | (((tid.y<<9)+2048)&1046528) | ((tid.y<<9)&512)) + r17` | 512 |

These are literal SSA transcriptions from the predecessor instructions ending in `%rd49`, `%rd53`, `%rd57`, and `%rd60`, respectively.  They are materially different from `512*i`.  They still depend on CTA/thread inputs and bounds/predicates.  The PTX merely shows QKV `rd5` at parameter +0; it does not show that it was bound to layer1's output allocation or that the producer's logical byte equation equals any S0–S3 equation.

For comparison, layer1's final eight actual 16-byte stores are at PTX lines 4811–4919.  Their bases are `rd6 + 4*((r3*r8+r6)<<11 + (r10<<2)) + 16*lane`, plus the source's 512/8192/8704 offsets and a second `rd4` family.  The exact producer source has no QKV `%rd5` register.  An inter-kernel buffer binding and a solved common logical index are therefore required, not assumed.

## Shared swizzle → MMA A, and retained C

At lines 701/710 the first loop-body shared loads make the following two A-fragment families explicit:

* `%r238..%r241` (the A tuple of MMA 1 and 2, lines 767/774) comes from `shared_base + ((r2882<<6)&4096) + 16*lane`.
* `%r242..%r245` (the A tuple of MMA 3 and 4, lines 781/788) comes from that address plus 512.

The source contains **256** static FP8 MMA instructions.  The four above are precise first-family witnesses, not a false assertion that all 256 A/B/C tuples or every dynamic issue have been logically decoded.  No dynamic coverage is claimed from the static count.

C is retained at an actual original boundary: lines 4527–4529 form `rd106 = rd7 + 4*(r1671<<11) + 16*lane + 786432` and load `%r1186,%r1187,%r1194,%r1195`.  Lines 4598/4605 use `{%r1186,%r1187}` and `{%r1194,%r1195}` as the fourth (C) operand of real MMA instructions.  This disproves a synthetic C=0 replacement for that witness.  It does **not** type every slab read, prove all slab roles, or establish numerical/native parity.

`test_03` creates source tags `T(j)` independently and checks only the boundary-local proposition for a 512-byte bulk: byte `j` at a site has tag `T(F+j)` for that site's SSA source expression `F`.  It deliberately leaves `F` symbolic and does not construct a global source/output address table.  This is a tagged-source test at the original copy boundaries, not a VM trace and not a bridge proof.

## QKV output packing and actual layer3 reader

QKV has four original predicated `st.global.L1::no_allocate.b128` sites (6218, 6239, 8637, 8654): **16 static bytes per lane per site**.  In the first family, conversion results `%rs124..%rs131` are packed into `%r1897..%r1900` and stored at `rd3 + 16*lane`; `%rs132..%rs139` are packed into `%r1903..%r1906` and stored at that base plus 8192.  The `rd3` base is `rd6 + 4*(((r2*r5+r3)<<11) + (r1668<<9) + (r1670<<7))`.  The second family similarly packs `%rs218..%rs231` and uses `rd4 = rd6 + 4*(((r5*r2+r5+r3)<<11) + (ctaid.z<<9) + (tid.y<<7))`.

Layer3 has an independent 72-byte ABI.  Its first source bulk reader derives `rd160 = rd1 + 4*((r20+r708)<<11 + (r17<<2))`, converts that to `%rd32`, then uses the original bulk copy at line 209.  This is a real source reader equation, but `rd1` is layer3 parameter +0—not a QKV register, QKV ABI, or established buffer binding.  Its static source has four 512-byte bulk sites.  No equality of the QKV output equations and this layer3 equation was found or asserted.

## Typed roles and unclosed regions

The only source-supported top-level roles are: QKV `rd5` ingress, QKV `rd6` output, QKV `rd7` opaque slab, and layer3 `rd1` source / `rd2` other input / `rd4` slab.  The one retained-C path above is typed through a real MMA C operand.  A complete typed classification over all slab reads and all MMA A/B/C operands is **not feasible from these files alone** and is not claimed.  Nor is logical Q/K/V naming inferred from serialized regions.

Open requirements for closure:

1. producer-store logical-byte SSA and QKV S0–S3 source SSA must be solved under a documented common CTA/thread/parameter domain;
2. a pinned, static inter-kernel descriptor/allocation binding must establish layer1 output → QKV `rd5` and QKV `rd6` → layer3 `rd1` (pointer identity alone is insufficient);
3. every bulk issue, shared swizzle, MMA operand, output register/lane pack, store, and layer3 read needs independent logical expected maps and coverage counts;
4. all relevant slab reads need typed roles.  Unknowns fail closed.

## Corrected host fact (context only)

Main's corrected host evidence is retained as context, not used as a live-capture claim: vtable `0x1800ba298`, `+0x08 → 0x18006d260` forward, `+0x38 → 0x18006e230` initializer; table LEAs `0x18006aa7e` and `0x18006ad0a`; forward `0x18006d423` reads `[r10+0x28]`, `0x18006d427` writes stack `+0x20 = 4`, and `0x18006d42f` dispatches.  The old `0x1800ba260 + 0x40` cross-table claim is not repeated.  This supports at most static host-grid context, not logical layout or a live submission.

## Verification

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -B reviews/nr-qkv-address-lineage-20260912/test_lineage.py
```

The five CPU/static tests validate hashes, original instruction counts (including four async sites and one QKV `ret`), per-site SSA boundaries, tag protocol, retained-C dataflow witness, store packing anchors, and the separate layer3 reader.  They execute no PTX or host code.
