# OUTVIEW65 source-only review — static result

## Disposition
**Not accepted as numerical/native/full-NR evidence.** This is a static reconstruction only. PACKET fixes OUTVIEW65's expected origin to **(0,-4)**; that is not evidence of a live instance. The prior NN48..64 / 37,440-MMA result remains upstream context only.

## Own kernel and change boundary
- Own entry: `cc_tinlayout_fused_swin_2h_64_2_outview_fp8`, **5,301 instructions**, 88-byte parameter block; ordinary comparator is `cc_tinlayout_fused_swin_2h_64_2_fp8`, **4,845**.
- The core is a real two-head 64-wide FP8 fused block, not a name/ratio-derived 4h construction. Its source has the same major FFN → normalization/attention → final-projection structure, but OUTVIEW adds an output-view tail and changes the instantiated configuration (`...ELb1ELi4...` versus ordinary `...ELb0ELi4...`).
- The decisive tail difference is concrete: ordinary uses two guarded `st.global...b128` tile stores (e.g. STANDARD 10388/10405 and 12714/12731); OUTVIEW converts final registers to FP8 pairs then uses per-pair `st.global.v2.b16` output-view stores (OUTVIEW 12894–12939 and 12974 onward).

## FFN: weights, loop, and quantization
- Slab reads show the FFN regions directly: residual gamma is loaded from **+28688**; expand panels begin at **+0** and **+8192**; grouped-projection reads include **+16384** (then its 4096-byte group regions); mix reads begin at **+24576**. These are actual `ld.weak.global.ca.v4.u32` source offsets, not inferred serialization.
- The expand loop is exactly two passes: `%r4586` starts at 0, its weight base is `(%r4586 << 11)*4`, then it is set to 1 and branches back once (OUTVIEW 969–980, 4160–4173). This is the **g=0/1 128-hidden-group loop**; it is not an UP-prefix K loop. It retains the MMA accumulators across the appropriate K32 operations and then applies the cubic half path.
- Cubic activation is half-pair arithmetic: `min.f16x2`, `max.f16x2`, `abs.f16x2`, two `fma.rn.f16x2`, and `mul.f16x2`; its clamp constants originate from f32 bit patterns for -4 and +4 (OUTVIEW 1237–1293). The activation is quantized with `cvt.rn.satfinite.e4m3x2.f16x2` before the next FP8 MMA stage.
- Thus FP8→half decoding and half→FP8 re-encoding are architecturally real. The first shared checkpoint follows FFN: FP8 pairs are stored to the four shared 512-byte slices, `bar.sync 0` executes, then consumers reload them (OUTVIEW 4292–4360). Do not remove this checkpoint, the two-pass grouping, barriers, or rounding conversions.

## Attention / normalization preserved in OUTVIEW
- The source squares half accumulators, performs its explicit pair/add/shuffle reduction tree, floors by the half epsilon made from f32 bits `948045311`, and uses `rsqrt.approx.ftz.f32` followed by `cvt.rn.f16.f32` (OUTVIEW 5189–6052). The resulting values are multiplied by gamma loaded at **+57504**, then FP8-quantized.
- QK uses `mma.sync.aligned.m16n8k32.row.col.f16.e4m3.e4m3.f16`, followed by half FMA, max/min clamp, packed-bit transformation (`shl.b32 ... ,5; add ... ,2146992128`), and the explicit reduction/permutation tree. Its probability denominator is floored by the same epsilon and inverted through `rcp.approx.ftz.f32`→rounded-half (OUTVIEW 8818–9010); probability products are immediately `cvt.rn.satfinite.e4m3x2.f16x2`-quantized (9450 onward) before PV MMAs. These are not replaceable with a generic softmax or exact reciprocal.

## Final neuron/register-to-byte equation
For each final fragment element, in source order:

1. Decode the shared FP8 final input after the final barrier; use slab B panels at **+57520, +58032, +59568, +60080** (per `tid.y` panel base).
2. Execute the two K32 MMA accumulation stages. For example, `%r4067` is produced by the terminal `mma.sync...` at OUTVIEW 12838–12841, seeded by its preceding K32 result; the terminal fragment set is `%r4067..%r4082`.
3. Quantize componentwise, with the exact opcode
   `q_i = cvt.rn.satfinite.e4m3x2.f16x2(z_i)`.
   The register mapping is ordered: `r4067..r4082 -> rs17..rs32` (OUTVIEW 12894–12939).
4. Store pairs in order: `{rs17,rs18}`, `{rs19,rs20}`, …, `{rs31,rs32}` via `st.global.v2.b16` (first at 12974; subsequent stores repeat the same form). Hence the byte result is the RN/saturating E4M3 encoding of the terminal half MMA fragments, not F16 serialization and not an assumed bijection/map.

## OUTVIEW extents, guards, and store stride
- OUTVIEW alone loads the signed pair at parameter **+80/+84**: `ld.param.v2.b32 {%r66,%r67}`. It selects
  `Hout = (r66 >s 0) ? r66 : r62` and `Wout = (r67 >s 0) ? r67 : r63`
  through `setp.gt.s32`/`selp.b32` (OUTVIEW 8048–8052). Ordinary source does not make this +80/+84 selection.
- Every output pair has signed two-axis suppression: `y <s 0 || y >=s Hout || x <s 0 || x >=s Wout` branches around its `st.global.v2.b16` (first instance 10394–10410). These are output-view extent guards, not unsigned/clamped addressing.
- For the first pair, with `t=tid.y`, `l=laneid`, `y=Y+8*ctaid.y+floor(l/16)`, `x=X+8*ctaid.x+(floor(l/4) mod 4)`, and `d=l mod 4`, the source index is exactly
  `I = ((2*t)*Hout + y)*(4*Wout) + 4*x + d`,
  followed by byte address `output_base + 4*I` (OUTVIEW 10384–10410). The remaining stores cover the explicit +2/+4 row/column fragments under the same signed guards. This gives the observed register-to-byte layout equation without assuming a high-level layout bijection.

## Host-selection qualification
HOST_SELECTOR has a conditional `_outview` recognition path: it searches underscore-delimited substrings, compares the 8-byte `_outview` literal (`0x7765697674756f5f`), and branches at `0x180064960/0x180064a1a` only when found. It is therefore conditional, not proof that this OUTVIEW path is selected for the reviewed live graph. HOST_PROOF explicitly records 65 as excluded from the ordinary 63/64 set and labels its scope non-live; the graph packet, not a live run, is the basis for `(0,-4)`.

## Limits
No OUTVIEW numerical check, native execution, full-NR acceptance, 4h extrapolation, name/ratio inference, F16 serialization assumption, or logical/physical-map bijection was used.
