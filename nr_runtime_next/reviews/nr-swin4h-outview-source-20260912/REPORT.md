# Block 61 OUTVIEW source-only review (bounded)

## Scope/result

Reviewed only the supplied source/host-provenance packet. Block 61 is the 5,260-instruction `cc_tinlayout_fused_swin_4h_128_4_outview_fp8` (88-byte parameter block), not the 4,804-instruction ordinary entry. This review is source evidence only; it does **not** accept a numerical/native/full-model result or infer an 8h OUTVIEW layout.

## Directly established differences from ordinary

* OUTVIEW alone loads signed words at ABI `+80,+84` into `%r73,%r74` (OUTVIEW lines 12–16). The ordinary source has no such loads.
* Its actual write extents are selected independently, at lines 6799–6802:
  `P = (%r73 > 0) ? %r73 : %r69` and `Q = (%r74 > 0) ? %r74 : %r70`.
  Thus zero and negative extra extents fall back to the ordinary extents; this is a conditional binding, not proof that either extra word is always live or positive. Those selected values feed both store guards and store strides. They do not appear in the shown QK/PV/final-MMA operand chains.
* The core is not merely an ordinary-store relabel. OUTVIEW contains separate staged operand phases with nonuniform bases/gaps: the initial `%rd10 + tid.y*16384` phase with four `+1024` loop advances; the `+82432` phase with operands at `-512,0` and `+4096` loop advances; and the `+101152` phase with operands at `-2560,-2048,-1536,-1024,-512,0` and `+12288` loop advances (lines 299–2146, 3073–3248, 3398–3929). Keep these delayed phases and their operand order; they do not establish a contiguous/reshaped QKV map.
* QK uses slab base `147744 + tid.y*8192`, the fixed f16 affine/clamp scalar bit patterns `1027077105,1067877303,1065615360,1070129152`, packed `<<5 + 2146992128`, and the explicit reduction/permutation chain. The final-weight phase uses `180528` onward. These same scalar constants are visible in ordinary source, but source comparison does not prove a global tensor-axis bijection.
* OUTVIEW’s final writer is materially different: it emits guarded `st.global.v2.b16` fragments (OUTVIEW lines 9310–12341), while ordinary emits guarded `st.global...b128` chunks (STANDARD lines 9300–9343 and 11812–11852). Therefore copying an UPSAMPLE or ordinary writer ledger would be unsound.

## Actual final output byte equations and guards

Let `t=tid.y`, `L=laneid`, `a=floor(L/16)`, `b=floor(L/4) mod 4`, `l=L mod 4`. Let `Y0=%r72+8*ctaid.y`, `X0=%r71+8*ctaid.x`; source uses `%r72` for Y and `%r71` for X. For each final FP8 four-byte fragment, choose `dy∈{0,2,4,6}`, `dx∈{0,4}`, and `q∈{0,1}` as dictated by its actual listed store/register pair. Its coordinates are

```
y = Y0 + a + dy
x = X0 + b + dx
g = 2*t + q
byte address = output(+8) + 4 * ((g*P + y) * (4*Q) + 4*x + l)
```

and the `v2.b16` store writes bytes at that address through `+3` (the four final `cvt.rn.satfinite.e4m3x2.f16x2` codes). Every such fragment is guarded by `0 <= y < P` and `0 <= x < Q`; the source has no guard on `g` because `t` is the fixed four-way thread-Y coordinate. The fragment schedule covers `dy=0/2/4/6`, `dx=0/4`, `q=0/1`, with lane subcoordinates above—i.e. the actual 8-by-8 CTA tile, not a single reshape assertion.

This proves the writer’s physical byte addressing. It does **not** prove that this physical `[g][P][Q][16]`-style ordering is canonical HWC128, serialized F16, a bijection to the predecessor’s C128 layout, or any named layout axis.

## Extents/origin/quotients/selector

* The startup `/4` calculations use signed sign-bias then `shr.s32`: `(v + ((v>>31) unsigned>>30)) >> 2`. That implements signed truncation toward zero, not floor or ceil.
* HOST_PROOF records the static expected block-61 decoder origin `(0,-4)` and ABI `+40=X`, `+44=Y`; the graph packet also identifies block 60’s output as the source-proven canonical-C128 predecessor. This is static provenance, not evidence of a live mutable instance.
* Host selector text recognizes `_outview`; HOST_PROOF ties the current factory/table path to block 61 and supplies the static origin. The source establishes the `+80/+84` conditional writer binding above, but the supplied host material does not prove actual runtime values for those words. No live-origin claim is made.

## Acceptance boundary

The supplied NN candidate is not sufficient to promote this result: it is a candidate source equation with external reciprocal-table requirements, whereas this OUTVIEW PTX visibly uses in-source approximate reciprocal/rsqrt operations in its normalization paths. No numerical acceptance, output hash, axis bijection, or full-model equivalence is established here.
