# Next Main implementation plan (NOT validated normalized NN)

Raw projection proof now in ../nr-swin8h-qkv-tensor-main-20260912/:3072MMA,49152register halves, first code/prediction unchanged,4tests. Real post-K256 register boundary is PC4237 after backedge4236;4235 is inside the loop. The source raw bank view is[64,8,3,32]. Worker Q/K/V lists correspond to banks0/1/2 by raw projection MMA coordinates; verify each consumer before publishing normalized identities.

Candidate canonical per32-vector reduction derived from worker source register tree plus raw C fragment slots:
- square each element with RN-half;
- local8 = RN(RN(square[8:16]+square[24:32]) + RN(square[0:8]+square[16:24])); reshape last8 to four warp-subgroup lanes x two halves;
- RN(local + local[xor2]), then RN(result + result[xor1]);
- add low/high half with RN (source explicitly swaps halves then adds); inspect all duplicate lane results, not only one chosen lane;
- max with RN16 of source f32-bit immediate948045311, then exact half→f32, pinned measured-half-domain RSQRT policy, RN-half conversion;
- Q: half multiply raw Q by factor, THEN half multiply by RN16 of F32 slab[754688+4*warp]. K: factor multiply only. These operations must not commute across rounding.

This is a candidate formula, still requires actual source/midpoint checks. No float32/float64 sum shortcut or ordinary rsqrt fitted to output. Expose finite/overflow/LUT refusal.

For provenance, seed raw element tags from original C slots at each raw projection MMA: m=16*(j//12), n=96*warp+8*(j%12), j0..47. Propagate through actual norm/scale operations and conversions. Validate all Q/K prequant halves; derive physical Q-A/K-B packing from actual downstream MMA source slots, not from bank adjacency. V uses actual movmatrix transpose BEFORE FP8; carry element tags through its original transpose and validate subsequent PV B origins. A logical V tensor alone does not prove physical layout.

Byte-addressed C tags use byte2*element, NOT element directly (earlier FFN observer error). Preserve all original loops and the actual barrier at original10536/PC5213 (epoch6), already executed by the literal oracle. See MAIN_BARRIER_ERRATUM.md for Main's corrected contradictory note.

A new actual source-only worker is running in ../nr-swin8h-attention-tail-source-20260912/ on probability mapping, denominator/RCP, PV, final residual/projection. Its completion should trigger Main to continue the normalized QKV and attention NN lift, not to promote reports to numerical proof.
