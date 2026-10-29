# Main review / source-only report errata

Worker report retained. Main implemented and independently validated the tensor tail in ../nr-swin8h-attention-tensor-main-20260912/; it is not an adoption of all report equations.

Corrections from actual instructions:
- First local denominator sum at12028 is r4404=add.f16x2(r4503,r4509), not r4403. r4403 is the laneid loaded just before it. Subsequent sum is r4406=add(r4404,r4405), not an addition of laneid. The intended tree association was otherwise useful.
- Gamma address simplification must include lane modulo4. At14361–14374, r5546=lane-(lane&~3)=lane%4 on the admitted nonnegative lane domain. Word loads are820256+64*warp+4*(lane%4)+{0,16,32,48}, not +4*lane. Their exact region is820256..820768,256half coefficients, within slab820784.
- Loop bound tests original old counter before assigning the increment. Keep this order; final K32 loop has eight trips0..224.

Main now proves the seed shared source is FFN output at epoch6, and PV overwrites those per-warp regions before barrier→epoch7. Final projection takes INITIAL C=half(FFN*gamma), not a late add. Proof includes actual shared version/byte origins and every1024finalMMA C/D. QK seeds are actual half matrix[8,64,64] at689152..754688 with a source-backed packed map, not just an envelope.

The first unchanged tensor prediction matched PV shared and full output; all256QK+256PV+1024final MMAs, packed map, denominator and reciprocal, probabilities/quantization, seed and stores were checked. Full original entry continued through all10752MMAs and8ret warps. This is bounded CPU NN/reference evidence, not native/whole-model equivalence.
