# Block 31/32 1-D ViT FFN: bounded CPU reference

## Delivered entry

`ffn_expand_post_mma.py` is a CPU-only reference for the **post-MMA tail** of
`cc_vit_1d_ffn_expand_fp8`.  Its input is one actual PTX packed `f16x2` MMA
result word, not a float callback or an invented matrix.  It performs, lane by
lane, the visible sequence:

```
u = max(min(x, +4), -4)
p = fma.rn.f16(-0.05625, abs(u), +0.3)
p = fma.rn.f16(u, p, +0.9)
y = mul.rn.f16(x, p)
out = cvt.rn.satfinite.e4m3(y)
```

All f16 arithmetic is exact-rational followed by explicit binary16 RN-even;
FP8 packing is low-half -> low-byte and high-half -> high-byte.  Signed zero,
infinity saturation, gradual E4M3 subnormals, and NaN refusal are explicit.
The constants are first rounded by the same visible `cvt.rn.f16.f32` steps:
`-4=0xc400`, `+4=0x4400`, `-0.05625=0xab33`, `+0.3=0x34cd`, and
`+0.9=0x3b33`.  This is **cubic SiLU**, not GELU/SiLU guessed from a name.

PTX evidence is lines 179527--183783 of the pinned module: the demangled
configuration names `MpCubicSiluActivation`; the first concrete lane sequence
is at 181740--181760; its E4M3 conversion begins at 183465.  The source also
contains real `mma.sync.aligned.m16n8k32.row.col.f16.e4m3.e4m3.f16`, rather
than an identity or approximate callback.

## Static facts established

| item | source-established fact |
|---|---|
| block 31 layer 0 | `CCVit1DFfnExpand`, type `cc_vit_1d_ffn_expand_repack_input`, 4,194,320 bytes |
| block 32 layer 0 | `CCVit1DFfnExpand`, type `cc_vit_1d_ffn_expand`, 4,194,320 bytes |
| both layer 1 | `CCVit1DFfnContract`, type `cc_vit_1d_ffn_contract`, 4,196,352 bytes |
| expand kernel | shared input 24,576 B; three 8-B copy barriers; `CCFfnExpandConfigF16...MpCubicSiluActivation` |
| contract kernel | shared input 16,384 B; two 8-B copy barriers; `CCFfnContractConfigFP8...NoActivation` |
| MMA form | `m16n8k32.row.col.f16.e4m3.e4m3.f16` in both entries |

The PTX parameter record is 72 bytes.  Expand actually dereferences positional
slots `+0`, `+16`, and `+24`, and loads the two 32-bit geometry values at
`+64/+68`; the other slots are not named by this static evidence.  Contract
loads pointer-width values at `+0,+8,+16,+24,+32,+40` and the same geometry
pair at `+64/+68`.  These are intentionally positional ABI facts, not guessed
semantic argument names.

Both entries compute `N = param64 * param68`; their CTA-x decomposition uses
`ceil(N/128)`, and the bounds quantity is exactly `2 * ceil(N/32)`.  Both use
`ctaid.x`, `ctaid.z`, `tid.x`, `tid.y`, `tid.z`, and initialize the copy
barrier with `ntid.x * ntid.y`.  Neither entry declares `.reqntid`/`.maxntid`,
so an exact host CTA dimension or full grid is **not** recoverable from the
PTX alone.  Contract additionally has an observed `ctaid.z < 3` reduction path
using `red.global.v4.f16x2.add.noftz`, a counter/wait path, and a final
load/add/FP8-write path.  The `add.f16x2` there proves staging reduction; it
does not identify a model-level retained residual.

The architecture marks only block 31 layer 0 as `repack_input`.  The supplied
PTX contains generic/publish/chained expand symbols, but no source-proven
host call site or separate `repack_input` entry.  Therefore no repack subcall
or DAG edge is invented here.

## Raw checkpoint slabs (not copied)

`SLAB_MANIFEST.json`, made by `collect_slabs.py`, records direct SHA-256 values
over the requested ranges in the existing checkpoint.  It preserves all bytes
in place and never zero-fills/copies a missing slab:

| slab | checkpoint file range [start,end) | SHA-256 |
|---|---:|---|
| block31.layer0 | [23031200, 27225520) | `837dddf52feeff1f6143b4aa0efc3ec3df4889dc3614bf1db3dc2f79089777a4` |
| block31.layer1 | [27225520, 31421872) | `143e90b9d5e8359ad8e20bb4f780765014136a838efbadb91c95329b525942f0` |
| block32.layer0 | [35618354, 39812674) | `f94a41873dc7a32ec125461adc3609b162ea59439e81ec946265878009e9f916` |
| block32.layer1 | [39812674, 44009026) | `5c0a940e75c7df37d50098a53796a5014019844d347dabe8c34d73dff4ca6696` |

The manifest retains the architecture offsets, direct checkpoint offsets,
byte counts, and serialization metadata for audit only.  No tensor shape,
weight permutation, or graph edge has been inferred from that container.

## Deliberate boundary / next evidence needed

A full block would require evidence not present in the two static sources:

1. host class construction/launch records resolving all positional pointers,
   CTA dimensions, grid dimensions, and the block-31 repack path;
2. a source-derived mapping from each checkpoint byte to the MMA B operand
   (including all packed/async/shared permutations); and
3. a source-derived mapping from producer output to expand input and contract
   output to the next layer, sufficient to prove or disprove a residual edge.

Until those exist, this review does **not** execute a fake dense matrix, infer
512/4096-like dimensions from the FP16 container, guess a DAG, use GELU or
softmax, expose an identity MMA, or call a partial-contract staging add a
residual.  The delivered entry is usable once real MMA f16x2 output fragments
are available, while these missing boundaries remain hard errors rather than
plausible numeric output.
