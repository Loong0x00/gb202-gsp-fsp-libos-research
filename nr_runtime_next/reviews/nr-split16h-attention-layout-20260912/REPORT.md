# Split16H layer-2 physical layout and host-grid closure

## Certified bounded result

This new, self-contained review is CPU/static only.  It pins copied original PTX, the real layer-2 917,568-byte slab, the prior 32,768-byte `P` witness (`247fa40f…`), layer-1/layer-3 original FP8 PTX, and three raw byte slices from the original DLL (`e16bcf15…`).  No copied host byte is loaded or executed.

For the canonical finite 8x8, 32,768-byte boundary, it establishes two **physical-byte** maps:

* `P output byte i -> QKV input byte i`, for every `0 <= i < 32768`;
* QKV output byte `i -> layer-3 ABI src@0 byte i`, for every `0 <= i < 32768`.

These are explicit byte-boundary maps, not a claimed tensor reshape.  The independent literal loops test tagged byte transports, permutation/bijection/completeness, and the actual P digest; it does not use VM final registers or a VM-generated output as an expected value.  It therefore closes the former missing bridge layout *within this bounded physical ABI composition*, while making no claim about a live allocation/descriptor submission.

The QKV source independently anchors input base at aggregate `+0`, output base at `+8`, and the layer-3 source ABI at `+0`.  Its original four bulk forms cover all 64 aligned 512-byte input chunks for this boundary.  The QKV stores remain original `st.global.L1::no_allocate.b128` forms; layer-3 retains an independent 72-byte ABI whose `src` is `rd1`, not the QKV ABI or an inferred dense reshape.

## Slab and MMA operand roles

The exact slab is exhaustively partitioned into physical serialized roles:

| bytes | typed role | scope of claim |
|---|---|---|
| `[0,262144)` | E4M3 MMA-operand region 0 | physical operand storage only |
| `[262144,524288)` | E4M3 MMA-operand region 1 | physical operand storage only |
| `[524288,786432)` | E4M3 MMA-operand region 2 | physical operand storage only |
| `[786432,917504)` | FP16 MMA-C backing region | real serialized region; checked nonzero, never substituted with C=0 |
| `[917504,917568)` | scalar FP32 backing region | original `4*cta.z + tid.y` source addressing, twice |

The three first regions are deliberately not labelled Q/K/V tensor axes: that would be an unsupported reshape/order assertion.  PTX has 256 FP8 MMA forms, 32 `rsqrt.approx.ftz.f32`, and four `rcp.approx.ftz.f32`; this review supplies no arithmetic policy, identity callback, softmax, GELU, zero C, or numerical output model.

## Exact host lineage

The old `4*cta.z + warp` PTX scalar expression is **not** used as host-grid proof.  The raw original DLL bytes instead establish this chain:

1. QKV method-table capture at VA `0x1800ba260` has slot `+0x40` = `0x18006d260`.
2. Raw QKV forward bytes at `0x18006d260` read the input range from `rdx`, output range from `r8`, select their starts, and dispatch through the launch vtable slot `+0x28`.
3. That same forward slice contains `c7 44 24 20 04 00 00 00`: the launch stack grid-z argument is exactly **4**.
4. The separately captured QKV initializer at `0x18006e230` contains the FP8 name LEA and original `(CTA.x, CTA.y)=(32,4)` immediates.

Thus the bounded four conditional z slices now have a raw-host QKV vtable/forward/grid-z lineage, rather than only source-level evidence.  This does not prove base versus tilesync selection/readiness, live descriptor identity, submission success, or native ordering/interleaving.

## Erratum / scope

`nr-split16h-attention-execution-20260912` structural tests intentionally injected an MMA callback returning C and RCP/RSQRT identity callbacks.  They remain structural execution/synchronization witnesses only and are **not** numerical restoration evidence.  The separately reported Main `q.policies()` run used RN-half exact-FP8-dot-plus-C and reference RCP/RSQRT through all four slices; its `6de6b9a0…` output remains `UNVALIDATED` for layout and is not consumed by layer 3 here.  This review neither relabels that file nor feeds it to layer 3.

Native precision, selected base-vs-tilesync route, readiness, real host submission, actual buffer bindings, cross-kernel synchronization, GPU parity, and deployment remain unproved and unsupported.  Missing pins, aliases, wrong sizes, or out-of-range bytes are outside this certificate and must fail closed.

## Verification

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -B \
  reviews/nr-split16h-attention-layout-20260912/test_layout.py
```

The five local tests hash every owned source/capture, use literal byte loops for both maps, verify all slab regions and key source forms, and decode only copied raw host bytes.  They do not execute the DLL, a GPU, Wine, a native host, or a deployment path.
