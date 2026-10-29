# `cc_vit_1d_ffn_expand_fp8`: bounded CPU MMA → activation → store reference

## Delivered, and deliberately not overclaimed

`ffn_expand_fp8_reference.py` implements three literal, CPU-only stages from
`module-05-dll-00dd4bc0.ptx`:

1. `mma_m16n8k32_row_col_f16_e4m3_e4m3(A, B, C)` is the real
   `mma.sync.aligned.m16n8k32.row.col.f16.e4m3.e4m3.f16` numerical operation:
   16×32 E4M3 A times 32×8 E4M3 B, added to binary16 C and RN-binary16
   accumulated.  It never returns C as a numeric shortcut.
2. `cubic_silu_half` / `activate_pack_f16x2` execute the literal f16 tail and
   the E4M3 RN/satfinite store conversion.  The source F32 literals are
   r563/r562/r561 = `bd650000`/`3ee50000`/`3f650000`, which convert to
   `ab28`/`3728`/`3b28`: cubic coefficients
   **(-0.055908203125, 0.447265625, 0.89453125)**.  The old
   -0.05625/0.3/0.9 values are not used.
3. `tail_registers_to_stores` takes the real final PTX accumulator-register
   names, applies that tail, and emits all eight 16-byte, lane-relative stores
   at literal offsets `0,512,65536,66048,131072,131584,196608,197120` plus
   `lane*16`.  Thus it does not invent a dense output layout.

Finite `-4` produces binary16 `-0` and E4M3 byte `0x80`; this is tested.
All binary16 infinity/NaN and E4M3FN NaN operand paths reject.  There is no
nonfinite “fix”, zero fill, or unproven NaN payload.

This is a **full nonmock MMA + activation + store fragment reference**, not a
claim that the checkpoint alone is a standalone neural-model forward.

## Literal source facts retained

The entry is a 72-byte parameter record.  It dereferences only positional
`+0` (source for `cp.async`), `+16` (global destination stores), and `+24`
(global MMA-B loads); `+64/+68` are the two `N` geometry factors.  Other
record slots are not semantically named here.  The static code computes
`N = param64 * param68`, `ceil(N/128)` for CTA-x decomposition, and the
header/layer bounds quantity `2*ceil(N/32)`.  `host_contract.StaticGeometry`
exposes these formulae but intentionally calls the factors `N0/N1`, not H/W:
the PTX does not name them.

The entry has 24,576 B shared input storage, three 8-byte mbarriers, one
`bar.sync`, 24 static `cp.async.bulk...mbarrier` instructions, 64 static MMA
instructions, and a visible `r1138` loop stepping 64 through 960.  Its
barrier/async pipeline is retained as a source schedule and tested as such;
a sequential CPU calculation does not pretend to simulate CTA timing.

## Raw weight boundary, reverified in place

`SLAB_MANIFEST.json` records block32/layer0 only: the original `F16`
`block32.layer0.layer` raw range `[35618354,39812674)`, exactly 4,194,320 B,
SHA-256 `f94a41873dc7a32ec125461adc3609b162ea59439e81ec946265878009e9f916`.
`collect_slabs.py` directly hashes the existing safetensors bytes and does not
copy or reshape them.  The test rehashes that range and compares it against
the preserved old `nr-vit-ffn-reference-20260912/SLAB_MANIFEST.json` entry.
No checkpoint F16-to-prepared-E4M3 conversion/permutation is asserted.

## Hard remaining boundary

PTX alone does **not** establish (a) host parameter ownership and names,
(b) CTA dimensions/grid, (c) whether/where block31's repack launch occurs,
or (d) the mapping between async/shared/global bytes, warp MMA fragments, and
logical model matrix coordinates.  Those missing mappings mean that connecting
the numerical MMA tiles into a model-wide full forward would be a dense-layout
guess.  `run_full_forward` and `require_host_contract` therefore raise
`HostContractRequired`; this is intentional conditional ownership until a host
launch record is delivered.  In particular, this review makes no final-model
equality or residual/contract claim.
