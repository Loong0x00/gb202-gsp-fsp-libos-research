# Main normalized Swin8h Q/K/V NN acceptance

This adds the normalization/packing proof that the prior RAW-projection directory explicitly did not claim. CPU/static, original block48 slab, bounded64positions/8heads/32components, finite and pinned-LUT domains only; NOT full NR or native equivalence.

## Exact tensor semantics

Raw projected banks0/1/2 are identified as Q/K/V by actual later operands, not register adjacency alone. Each Q/K vector has32half components. Source order:

- RN-half square;
- per-eight component: RN(square[8:16]+square[24:32]) and RN(square[0:8]+square[16:24]), then RN(first+second);
- four-subgroup-lane butterfly distance2 then1, each RN-half;
- explicit low/high swap/add, summing both half lanes;
- max with RN16 of source f32-bit immediate948045311;
- exact half→f32, pinned measured-half-domain RSQRT, RN-half;
- half multiply raw Q/K by factor;
- Q ONLY: subsequent half multiply by RN16 of8F32 scalars at slab754688; then FP8 RN/satfinite;
- K has no Q-scale multiply. V follows original row-major8x8 movmatrix transpose BEFORE original FP8 conversion.

The NN presents logical V values; the separate original transpose/FP8/PV consumer proof establishes its physical relation. It does not remove the transpose from the original oracle.

All QK operands use component pi(k), not identity. A rows16*(j//8)+m; B key rows8*(j%8)+n. All PV V operands use key rowsK0+pi(k), channelsN0+n. Equations checked on all256QK and256PV MMAs.

## Evidence

First `normalized.py` SHAe458dcb55f3033c053e6ff3f75a1920d55dbf06cceecb9f7e1fb60d7a8d90275 unchanged. Logical FP8 Q/K/V16384B each:
- Q390b0ac2ac2bf00614c26821e04e5765d828e729e841f286fc9c2b2ddb9bc30c
- Kc036a002fe5f743e5cfe29a28950be3f1555198b35ee4adc913b8b498d540bb1
- V2ff03969dc2c7ff2aeb6157d0b230b836ad2bf4badc521d86a1478aed18032b5

Original half-tree union/owner/component/order tags and every intermediate result verified:32768squares;16384first-pair adds;8192each of local/butterfly2/butterfly1/half-lane sums and floor;8192half→f32/RSQRT/f32→half triples;32768factor multiplies;16384Q-scale multiplies;16384each Q/K/V prequant halves;16384V transpose halves.256actual QK A/B and256actual PV V operands checked by original source neuron identities and exact bytes. Full10752MMA original program still executes and returns all8warps; final output remains3da96cddc0606a05fdc173bc333d6adeda7f928f66094aa75cb82418ed18d753.

5testsPASS: full original intermediate/physical proof,unchangedfirstprediction,wrong-scale-order negative,policy/domain refusal,immutable hooks. Wrong scale-before-normalization changes5731/16384Qhalves and42FP8bytes, rejected by the original intermediate observer.

## Preserved observer issue

First checker wrongly parsed shfl clamp/mask operands as literal integers; this source supplies registers carrying31/all-ones. FIRST_CHECK.log and CHECKER_BEFORE_SHUFFLE_OPERAND_FIX.py.txt retained. Corrected observer evaluates actual source operand registers and checks their values; no instruction/arithmetic/tensor changes. Full run passed. Additional physical equations derived from actual provenance were asserted over the full grid in a further complete run; pre-formula checker snapshot retained.

The original barrier at10536/PC5213 is retained. Earlier Main's contrary note was corrected separately in the source review; it was never removed from execution.
