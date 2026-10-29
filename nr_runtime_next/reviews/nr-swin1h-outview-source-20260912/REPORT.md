OUTVIEW69 source fact: final output stores use +8 as O0, output extents selected from +72 when positive (else +24), a 16*OW-byte row stride, and explicit per-store signed bounds guards.

# OUTVIEW69 source-only report

## Identity, scope, and ABI
Packet identifies the entry as `cc_tinlayout_fused_swin_1h_32_1_outview_fp8`, 5,351 instructions, parameter span 96 bytes. The only `ld.param` offsets in its supplied listing are:

| Offset | Directly loaded value/use |
|---:|---|
| 0 | P0 pointer (`rd1`) |
| 8 | O0 pointer (`rd3`, then `rd2`) |
| 16 | slab pointer (`rd4`, then `rd53`) |
| 24, 28 | signed supplied H, W (`r52,r53`) |
| 32, 36 | signed X, Y origin (`r54,r55`) |
| 72, 76 | signed output extent candidates (`r56,r57`) |

Thus this is an OUTVIEW-specific 96-byte ABI finding. It must not be collapsed into the ordinary source ABI (the supplied STANDARD source has only 0/8/16/24/32 loads), nor into a 2h/88-byte ABI. Bytes not proved loaded are not assigned meanings. HOST_PROOF's `40:96 unused` summary cannot override the direct `ld.param.v2.b32 ...+72` instruction.

Let `OH = (arg72 > 0 ? arg72 : arg24)` and `OW = (arg76 > 0 ? arg76 : arg28)`: these are signed `setp.gt.s32`/`selp` selections, not inferred tensor dimensions. The source tile base is `Y=arg36+8*ctaid.y`, `X=arg32+8*ctaid.x`.

The `/4` sequence adds the sign correction before arithmetic shift; it is signed truncation toward zero: `7 -> 1` and `-7 -> -1`, not `/2`.

## P0 guard and FFN/core boundary
The source has four explicit P0 load cases. It retains the exact exceptional tests `H&-4==4`, `W&-4==4`, row tests `Y<-3`/`Y<-7`, and column tests `X>-4`/`X>-8`, plus the individual quotient limits. A rejected case creates zero via FP32->RN-FP16 then RN-satfinite-E4M3; it is not an unguarded OOB interpretation.

P0 raw FP8 registers directly feed the first expansion MMA. Separately, converted half P0 values are multiplied by the gamma at slab +8208 for the FFN residual seed. This is explicitly **not** an input-roundtrip seed. The FFN path is 32->128->32 with cubic FP16 operations, activation RN-satfinite E4M3, and four carried, unrolled K=0/32/64/96 contractions. Preserve every stated RN conversion, FMA/add carry, zero accumulator and lane shuffle; do not replace the unrolled source with reassociated math. Its final `F` is unquantized half at the final-seed boundary. The attention candidate correspondingly uses unquantized `F` as its final residual/seed input, not the FP8 code.

The source later performs bfly and indexed shuffles plus `prmt` before its final MMA; those are data movement, not proof of a `pi` map or a size/name-derived bijection. The supplied source declares no shared storage and contains no shared-memory/barrier instruction, so no shared epoch is asserted.

## Final MMA fragment -> FP8 pair -> O0 address
The final projection has two source-visible accumulator groups.

* First query half: final MMA fragments are `r2976..r2991`; each is converted by `cvt.rn.satfinite.e4m3x2.f16x2` to `rs1..rs16` in that order. The eight four-byte stores take pairs `(rs1,rs2)`, `(rs3,rs4)`, ..., `(rs15,rs16)`.
* Second query half: final MMA fragments are paired in source order as `(r4233,r4234)`, `(r4235,r4236)`, `(r4237,r4238)`, `(r4239,r4240)`, `(r4241,r4242)`, `(r4243,r4244)`, `(r4245,r4246)`, `(r4247,r4248)`; each member is independently RN-satfinite E4M3x2 and the resulting pairs are `(rs17,rs18)` through `(rs31,rs32)`.

Each `rs` is an E4M3x2 pair; each `st.global.v2.b16` writes the two `rs` values, i.e. four output bytes. This records the source fragment-to-pair chain only; it does not invent logical neuron labels beyond the actual accumulator fragments.

For lane `l`, define `g=floor(l/4)`, `x=X+(g mod 4)`, `y0=Y+floor(g/4)`, and `c=l mod 4`. For every store at `(y,x)`, the exact address form is:

`O0 + 4 * (y*(4*OW) + 4*x + c)` bytes.

Hence component stride is 4 bytes, x stride is 16 bytes, and row stride is `16*OW` bytes. The source guard on every one of these stores is exactly `0 <= y < OH && 0 <= x < OW` using signed comparisons.

The eight first-half pairs target `(y,x)` in this order: `(y0,x)`, `(y0+2,x)`, `(y0+OH,x)`, `(y0+OH+2,x)`, then the same four rows with `x+4`. The eight **second-half** pairs target `(Y+4+floor(g/4),x)`, then `+2`, `+OH`, `+OH+2`, followed by those four rows at `x+4`. In particular, the second query half explicitly starts at **`Y+4`**, rather than being assumed identical to the first. Every address retains its own guard; no extent, stride, or plane is assumed from a name or size.

## Host evidence and chain boundary
HOST_SELECTOR source searches underscore-delimited selector terms including `_fp8`, `upsample`, `_ds`, `_inview`, and `_outview`; the `_outview` match has a distinct return path. HOST_FORWARD has conditional (`r11 == -1`) selection of input/output list entries and separate signed origin/extent setup. Together these establish a conditional host selector path, not a claim that all variants share an ABI or a shared execution epoch.

HOST_PROOF's static table gives block 69 expected origin `(0,-4)`. This report states that static expectation only. CURRENT_CHAIN_RESULT reports matching numerical outputs only through blocks 48--68 and explicitly excludes a 69 result. Therefore there is no claim here of a 69 numerical match, native execution, full-NR execution, live result, or fresh instance.
