# Main exact 1D -> 2D FP8 byte repack

Exact module05 `cc_vit_1d_repack_1d_to_2d_fp8`,24ABI,120 original instructions. Source integers and loads/stores were lifted independently; this was NOT assumed to be the inverse of the earlier input repack.

For H,W positive multiples4 in the bounded envelope, work=m*256+q; y,x=divmod(m,W). Define
`F(m,q)=128*(q//8)+16*(m%8)+4*(q%4)+2*((q%8)//4)+(m%16)//8`.
Original source word=`4096*(m//16)+F(m,q)`; destination word=`4096*((y//4)*(W//4)+x//4)+F(4*(y%4)+x%4,q)`. Bytes are copied as raw b32 words, including arbitrary NaN encodings; there is no FP8 numerical operation or sanitization.

Current projection host confirms optional `_repack_output` and `_fp8` predicates. FP8 repack CTA256 and gridH*W, **not input-repack's ceil(H*W/32)**. Host computes1024/(2*fp8Flag+2)=256 words/pixel then ceil(256*H*W/256).20 instruction witnesses plus selected kernel-name pointer verify this. Parameter0 is the internal1D projection destination, parameter8 caller O[0]; geometry at16/20. Full init tail beyond its first unwind fragment is preserved.

For8×8, all512 actual original warp returns/16384 loads/16384 stores matched separate source and destination equations and the65536-byte result. Tests additionally execute original4×4,8×12,12×8 cases; wrong identity destination fails at an actual original store, and missing last byte fails at an original load. Five tests PASS. Independent input-repack roundtrips confirm the valid logical extent, including4×4 input-repack padding; arbitrary inactive padding is NOT claimed to survive a roundtrip.

`repack.forward(source,H,W)` is CPU byte computation with no DLL/VM dependency. `check_literal.py` separately invokes the original CPU integer stream for verification. NoGPU/PE/Wine/installed/network changes, no full-model/native-neural equivalence claim.
