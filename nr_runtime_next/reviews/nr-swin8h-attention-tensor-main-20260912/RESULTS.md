# Main Swin8h attention/PV/final projection tensor acceptance

`attention.forward(Q,K,V,skip,slab,reciprocal=...,hooks=...)` is a bounded NN-facing tensor implementation, not a VM forward. Logical Q/K/V are uint8E4M3[64,8,32], skip is FFN canonical-C packed64x256. Original slab820784 and explicit pinned half-domain reciprocal measurement. Local helper imports remain.

## Exact recovered order

1. Seeded QK: each head64x32 @32x64, component pi retained on both operands. One K32 RN-half operation with original learned half C seed. Seed logical shape[8,64,64], source offset689152..754688; `BIAS_MAP` is independently checked against all actual seed operand bytes.
2. Half FMA with coefficients RN16 of raw f32-bit immediates1027077105/1067877303, then max/min with RN16 of1065615360/1070129152.
3. The complete packed32-bit word shifts left5, then adds2146992128 modulo2^32. The tensor preserves both half components and cross-half bits; no replacement by a scalar exponential or softmax.
4. For keys2*lane+half+8*j,j0..7: first form four half pairs(j0+j1),(j2+j3),(j4+j5),(j6+j7); then ordered left-fold across these four pairs. Actual shuffles/selections transpose the partials into query order. Sum subgroup lanes0,1,2,3 by ordered left-fold, then add low/high halves. Original prmt packs two query denominators; max floor→half-to-f32→measured RCP→RN-half.
5. Multiply mapped probabilities by their row's reciprocal in HALF, THEN quantize FP8 BEFORE PV. This differs from deferring normalization until after PV.
6. PV: two ordered K32 MMAs, first zero C then first D as second C; source key pi retained. FP8 after final half result, packed into shared.
7. Final256→256 projection matrix754720..820256: INITIAL C is half(FFN skip*256half gamma at820256). Eight K32 RN-half steps. Quantize/store final output. Seed is not a late add.

## Proof

First `attention.py` SHA0a667665cda4a52a67f9c44eca874a5ed89474090a46a3c06797be8aa170b08f unchanged. First PV16384B SHA8467a2d1009455533efada5ba5924d0e54b51f345e60e9c979e769babbe635b3 and output16384B SHA3da96cddc0606a05fdc173bc333d6adeda7f928f66094aa75cb82418ed18d753 matched original boundaries.

All256QK+256PV+1024final MMAs checked: actual inputs, QK seed global byte origins/C/D, probability producer stage/key/query origins, V values in independently proved physical relation, PV carry provenance/C/D, final A shared epoch7 origins/PV labels, actual weight origins/C/D and initial seed lineage. All32768seed halves covered.

Also32768affine/65536clamp half results;16384packed32 shift/add words each; all ordered half denominator tree results and query ownership, original selection/shuffle/prmt ancestry,512RCP input/result/conversion triples;32768probability normalization/prequant halves;16384final seed halves with actual FFN epoch6/gamma byte sources;16384PV and16384final prequant halves;16384PV shared-store and16384final global-store byte lineage.

The entire original10752MMA entry still ran;8warps ret, original loops/barriers intact. The first attention checker passed without a numeric/map fix. Source worker errors (r4404 vs laneid r4403; coefficient lane%4 rather than lane) corrected in its separate MAIN_REVIEW.md before acceptance.

5testsPASS: first unchanged prediction, full actual operands/scalars, wrong post-PV normalization negative, wrong final late seed negative, finite/reciprocal-domain/hook contracts. No native/general-F32 approximation/synchronization or full NR-model promotion.
