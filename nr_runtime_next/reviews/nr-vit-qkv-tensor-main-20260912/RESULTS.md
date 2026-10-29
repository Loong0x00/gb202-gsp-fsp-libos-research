# Main QKV neural-tensor lift

`nn_reference.py` exposes a1024→3072 matrix, two K512 partitions with RN-half per K32,128×32×32 Q/K/V views, explicit source half-square trees, epsilon0x0410, measured half-input RSQRT lookup, Q half sqrt32=0x45a8 and32 learned F32 scales. Full Q/K/V outputs each131072 bytes match the original-instruction CPU grid:

- Q cc1acb0e930fc316680702a71800e235c9885edcdab7a08e9ab414d0658fd504
- K46581f1fbded6f184e77e00ea0332c21b455895514a04b6d2e7d26c50d6f1c66
- V0c4af456939ba79562b0047928fd73bc274ea4a2c8ff03e7af1fb91b1f5f2f8e

## Preserve initial failed prediction
First source-equation prediction matched Q/V but not K. Incorrect assumption: K uses Q's packing. First code, raw predicted bytes and comparison metadata are preserved in `first_prediction/`. K's own original stores derive a different, independently checked `K_MAP`; no values or tolerances were fitted. Current negative test deliberately reuses Q packing and fails at real K store placement.

## Intermediate evidence
Groups0 and15: per group6144 actual MMA input-origin/C and D-half checks,24576 merge-temp/prequant/store checks,4096 normalization squared-sum half checks,128 learned-scale origins. Shadow origins propagate at actual async publication; arithmetic and original synchronization remain intact. Norm is not replaced by a once-rounded sum: that shortcut changes Q1249 and K1403 out of4096 norm values on this fixture. Seven tests PASS, including scalar-tree reference and immutable hooks.

## Scope
N128, original block32 weights and sealed input. Finite/overflow refusal and measured LUT domain remain explicit. The one sqrt32 operation is RNf32 reference with resulting half0x45a8, NOT a proof of native sqrt.approx F32 bits. No full-kernel native equivalence/whole-network claim. Forward is NumPy tensor computation; local source/evidence imports are not yet a self-contained distribution. NoGPU/PE/Wine/installed/network changes.
