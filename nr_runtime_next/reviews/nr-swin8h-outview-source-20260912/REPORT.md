# block55 ordinary8h OUTVIEW source audit

## Scope and result
Compared the supplied 5759-op `cc_tinlayout_fused_swin_8h_256_8_outview_fp8` source with the supplied 5300-op `cc_tinlayout_fused_swin_8h_256_8_fp8` source, plus the supplied host extracts/strings. This is static source evidence only; it does **not** establish a live configuration, numerical/native parity, or a tensor layout inferred from a name, size, bijection, or adjacency.

The difference is not safely describable as “stores only.” OUTVIEW has the outview config specialization (`...ELb1...`, versus standard `...ELb0...`), reads an additional parameter pair at `+80`, and replaces the standard final four guarded 128-bit stores with a 16-site, coordinate-remapped final store sequence. Its generated resource declarations are correspondingly larger: predicates 269 vs 169, b32 4589 vs 4268, b64 329 vs 310. The comparison found no changed MMA opcode form, FP8 conversion opcode, activation constants, reduction/shuffle form, or weight-load offset in the common computation; those common portions differ in SSA numbering and scheduling/register allocation. That is a source-structural result, not a parity claim.

## Confirmed non-store/scalar differences

* OUTVIEW lines 12–17 load `param+80` into signed `%r64,%r65`, along with the normal parameter material. Standard does not load `+80`.
* In OUTVIEW’s final phase, effective extent values are selected exactly as
  `A = (param80 > 0) ? param80 : param32` and
  `B = (param84 > 0) ? param84 : param36`;
  see OUTVIEW 12340–12343. These are signed `setp.gt.s32` selects, not an unconditional dimensional equivalence.
* OUTVIEW final conversion is `cvt.rn.satfinite.e4m3x2.f16x2` for 32 packed pairs (`%rs1`…`%rs32`) before its stores. Preserve this RN/saturating FP8 conversion; it is not interchangeable with an unconstrained half/FP8 rounding simplification.
* The standard final phase instead converts its 32 pairs to `%rs882`…`%rs913`, computes the original tile predicates (`%p1/%p2` etc.), and makes four 128-bit stores. Thus even final guards and output packing/store granularity differ.
* The common core retains its explicit FP16x2 operation order, `rsqrt.approx.ftz` / `rcp.approx.ftz` paths, and shuffle trees. In particular, its loop counters are actual old-counter tests: `counter += 32; test old_counter < 96` and `counter += 32; test old_counter < 224` (e.g. OUTVIEW 2805–2809, 3905–3910, 4586–4591, 12237–12242). They must not be silently rewritten as simplified iteration counts.

## Final OUTVIEW byte addressing

Let `l=laneid` (0..31), `t=tid.y`, `bx=ctaid.x`, `by=ctaid.y`. Let `X0=param+40`, `Y0=param+44`; let `A,B` be the exact signed selects above; and let `out` be parameter pointer `param+8` (converted to global at OUTVIEW 12243).

The emitted signed/truncating lane work must be retained as written:

```
d = trunc_s32(l / 4)
g = d - 4*floor(d/4)       // implementation: d - (d & -4)
h = trunc_s32(l / 16)
p = l - (l & -4)
```

For actual nonnegative lane IDs this gives `g=(l>>2)&3`, `h=l>>4`, `p=l&3`; those identities do not erase the source’s signed correction/truncation sequence (`shr.s32`, sign-derived adjustment, then masks) used in OUTVIEW 12348–12360 and each repeated store block.

For every output packet selected by `a∈{0,1,2,3}`, `b∈{0,1}`, and `e∈{0,1}`, its logical coordinates and word/byte addresses are:

```
y = Y0 + 8*by + h + 2*a
x = X0 + 8*bx + g + 4*b
c = 2*t + e
valid = (0 <= y < A) && (0 <= x < B)
word = ((c*A + y) * (4*B)) + 4*x + p
byte_address = out + 4*word
```

When `valid`, OUTVIEW executes `st.global.v2.b16` of one converted FP8-pair pair (four FP8 bytes) at that byte address. The 16 guarded sites enumerate all `a,b,e` combinations; the source order is grouped as the two y values for each 2-row band and both `e` values, then the `b=1` counterpart. Do not infer an external tensor-layout label solely from this address coverage.

This derives the geometry directly: each CTA covers an 8-by-8 `(y,x)` tile, with `t` selecting the two `c` planes. The local lane arrangement is `h=floor(l/16)`, `g=floor(l/4) mod 4`, and `p=l mod 4`; the expanded `a,b` offsets complete y=0..7 and x=0..7. The bounds are per final-store coordinate, not a single tile-wide predicate.

For contrast, standard’s ending uses the pre-existing source tile coordinate/predicates and four 128-bit `st.global.L1::no_allocate.b128` stores (STANDARD 12338–12424); this is the material output-path change in addition to the extra extent operands.

## Host/selector evidence and block55 origin

`HOST_SELECTOR.txt` recognizes `_outview` and its FP8 selector branch resolves to `0x1800b9ba0`; `HOST_STRINGS.json` names that target exactly `cc_tinlayout_fused_swin_8h_256_8_outview_fp8` (non-FP8 counterpart at `0x1800b9bd0`). This verifies selector naming/FP8 selection from supplied strings.

In `HOST_BUILDER.txt`, the supplied boolean (`r15b`) controls the special last-iteration (`rbx==12`) path: when true it materializes that iteration’s string into field `rdi+0x58` (lines around 0x180069830–0x18006985b). This is the supplied host evidence for the requested seventh-argument-true → outview name/field path; it is static code only.

For current static block55, retain the supplied decoder convention exactly: origin is `(0,-4)`, with runtime `+0x7c → param+40 (X)` and runtime `+0x78 → param+44 (Y)`. Therefore it is **not swapped**. The final OUTVIEW equations above consume `param+40` as X and `param+44` as Y, consistent with that convention.

## Limitations
Only the six authorized inputs were read. No commands, execution, network access, tests, or live inspection occurred.
