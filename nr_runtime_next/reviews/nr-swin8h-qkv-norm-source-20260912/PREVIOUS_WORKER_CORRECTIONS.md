# Main review: preserve worker report; correct source envelopes

REPORT.md/PROGRESS.md remain source-only leads, not accepted tensor/axis proof. Main inspected original instructions and ran the full unchanged kernel with actual operand-byte provenance. New proof: ../nr-swin8h-ffn-tensor-main-20260912/.

Corrections:

1. The first bank does NOT read every j=0..63 in the worker formula. Its vector offsets are4096*k+{0,512},k=0..7, i.e.512*j with j in{0,1,8,9,...56,57}. Four loop trips are hidden-output chunks q, not input K. Eight unrolled input K32 steps are inside each trip. Actual global addresses prove EXP(k,h)=32768*(h//128)+B(k,h%128,128), covering[0,262144).
2. The next learned vectors are read INSIDE the same four-trip loop, BEFORE rd386 increments. At each such load rd386=P16+1024*q,q=0..3, not already P16+4096. Actual group matrix range is[262144,294912),32768 unique bytes; no overlap with the next matrix. It is eight independent128→32 linear projections, NOT a multiplicative gate inferred from the word “gate”.
3. Post-group mixing base is rd387=rd12+295424. rd12 was defined in the prefix as P16+1024*t, NOT P16+4096*t. Therefore its load address is295424+1024*t+8192*q+16*l+{-512,0}; actual range[294912,360448). The worker's stated4096*t equation and its claimed end360448 were mutually inconsistent.
4. Seed/gain order: source lines6031–6657 read prefix shared input, half-multiply by256 half coefficients at491520, and retain the results as the INITIAL C registers of the mixing MMAs. This is early residual seeding, not a late add. The grouped result is FP8-quantized before mixing. Actual source read epochs1→3 and all C/D steps checked.
5. Attention seed pointer source10537+: r5048=r35<<11, rd268=4*r5048, and r35=tid.y. Warp stride is8192 bytes, NOT2048. With sixteen512-byte vector blocks per warp its envelope is[689152,754688), not[689152,711680). This scalar address correction does not yet identify attention seed axes.

Main FFN evidence: first unchanged NN predictions match original shared boundaries; all4096expand+512group+1024mix MMA operands/raw/origins/C/D, activation intermediates,16384residual seed halves, group/final prequantization and actual shared-store lineage checked. A checker byte-vs-half label-index bug was preserved and corrected separately; NN source/weights/original arithmetic unchanged. No native/full-model promotion.
