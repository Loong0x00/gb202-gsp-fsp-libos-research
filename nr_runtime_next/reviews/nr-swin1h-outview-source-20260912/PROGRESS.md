OUTVIEW69 fact: the supplied 5,351-instruction source entry declares a 96-byte parameter object and directly loads offsets 0, 8, 16, 24, 32, and 72; +72 is therefore live in this entry.

## Scope
Static, source-only review of `cc_tinlayout_fused_swin_1h_32_1_outview_fp8` (packet block 69). This is not a native, PE, Wine, GPU, live-runtime, full-NR, or fresh-instance result. The supplied chain result is numerical evidence only for prior NN blocks 48--68; it does not establish a numerical result for 69.

## ABI and coordinates
* +0: P0/input pointer; +8: O0/output pointer; +16: slab pointer.
* +24/+28: signed supplied extents `(H,W)`; +32/+36: signed tile origin `(X,Y)`; +72/+76: signed output-extent overrides `(OH,OW)` (the source calls `ld.param.v2.b32` at +72).
* No other parameter offset is loaded by the provided entry source. This is the 1h/96-byte OUTVIEW ABI, not the ordinary 1h source ABI (whose supplied source only loads through +32), and not a 2h/88-byte ABI. The HOST_PROOF summary's broad `40:96 unused` wording conflicts with the direct +72 load; the direct entry listing controls this source-only conclusion.
* Tile bases are `Y=arg32.y+8*ctaid.y` and `X=arg32.x+8*ctaid.x`. Each signed divide-by-four uses sign correction then arithmetic shift, i.e. truncation toward zero: `7 -> 1`, `-7 -> -1` (not division by two).

## Input guard and data path
For the four P0 neighborhoods, the source keeps its four distinct predicates/zero paths rather than a generic bounds rule:
* rows `Y/4` and `(Y/4)+1` use, respectively, `Y<-3 || Y/4>=H/4` and `Y<-7 || Y/4+1>=H/4`;
* columns `X/4` and `X/4+1` use, respectively, `X>-4 && X/4<W/4` and `X>-8 && X/4+1<W/4`;
* `H&-4==4` and `W&-4==4` take the source's exceptional select paths; a failed load manufactures FP8 zero through FP32->FP16 RN then satfinite E4M3 conversion.

The ordinary-source P0 FP8 registers feed the expansion MMA directly. Separately decoded P0 half values form the residual seed with slab gamma; that seed is not an input FP8 round-trip, even if a helper can be finite-identity-compatible.

## Boundaries preserved
FFN is the source's 32->128->32 path: cubic half arithmetic, activation FP8 satfinite conversion, then carried contractions for K chunks 0, 32, 64, 96. The source is unrolled; the candidate's four-chunk notation is sequential, not permission to reassociate. Its seed is the separate decoded-P0 seed and the final FFN value `F` remains unquantized half at the final-seed boundary. The attention/core path has its own FP8 crossings, exact f16 rounding/carries, zero MMA seeds, bfly/index shuffles and `prmt` rearrangements. No `.shared`, shared-memory access, `bar.sync`, or generic shared epoch is present in the supplied entry source.

## Current status
The final output-address proof and host selector/conditional findings are recorded in REPORT.md. Static expected origin for block 69 is `(0,-4)`, not a newly observed instance result.
