# Complete CPU/static expand tensor reference

`expand_tensor_reference.py` is a NumPy CPU implementation of the complete
learned `cc_vit_1d_ffn_expand_fp8` operator: packed logical `A[128,1024]`, the literal 4,194,320-byte raw B slab
(containing packed logical `B[1024,4096]` plus its unused 16-byte tail), and
packed logical/physical `Y[128,4096]`.
It deliberately performs 32 `float64` `128x32 @ 32x4096` GEMMs and rounds to
binary16 **after every K=32 block**. It is not a once-rounded full GEMM.

The source proof for CTA x is explicit: with launch parameters `(128,1)`,
`r58=1`, `r2=ctaid.x`, and `r3=0`; the B selector is
`r6=(128*ctaid.x)|(64*odd_warp)`, whose bits are disjoint. Therefore logical
B/output n shifts by `128*ctaid.x`; the source store base shifts by
`2048*ctaid.x`. `cta_slots` expands the literal fragment/tail/store schedule.
Across all 32 CTAs it proves exactly 524,288 distinct output bytes, `0..524287`.

Finite E4M3FN operands only are admitted. E4M3 NaN bytes (`7f`/`ff`) are
explicitly rejected. Every K32 carry and tail instruction is checked finite;
this reference does not silently turn NaN into byte `7e`. The cubic constants
are the source-validated half bits `ab28`, `3728`, `3b28`.

`forward` returns inspectable `logical_input`, `logical_weight`,
`preactivation`, `output`, and `output_physical` tensors. Optional hooks are
read-only detached snapshots, so they cannot modify activation computation.
No autograd, native MMA, GPU, or whole-model equivalence is promised.
