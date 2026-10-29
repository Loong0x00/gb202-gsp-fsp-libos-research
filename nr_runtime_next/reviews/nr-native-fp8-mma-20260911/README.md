# Main native FP8-QMMA and reciprocal boundary oracle

Owned SM120 primitive program, not original model execution or activation capture. Original final-prehead FP8 coefficients and residual channel scales are used with synthetic input features/residuals. 81 input matrices ×4 column groups =324 warp cases. GPU run `runs/20260911-132533`: exit0/Guardian0, synchronization and readbacks completed, owned CUDA context cleaned up. Serial lock/no-games/global31000MiB/reserve protections as in `run.py`. No signed DLL, game settings or original PTX revision was changed.

**QMMA:** all41472 results match the declared exact K32 dot + supplied half C, then RN-half reference bit-for-bit. This is native verification of this tested primitive/data domain, not proof for every possible accumulator, earlier residual multiplication, or full prehead/model.

**RCP:** all31743 positive finite half denominators were expanded to F32, passed through native `MUFU.RCP`, and converted back to half. Native F32 reciprocal differs from correctly RN F32 in4026 cases (max1ULP), but **all final half results match**. The normalizer's allowed half-sum domain `[0x0410,0x7bff]` includes30704 values; all its half results match too, despite3897 intermediate F32 differences.

Thus the native approximate reciprocal itself is not correctly rounded F32. Its *observable following half boundary* matches the mathematical reference for the exhaustively tested positive-half domain on this device/run. Do not generalize to arbitrary F32 inputs or unrelated kernels.

`NATIVE_RESULTS.json` and raw outputs retain the distinction. `analyze.py` checks the literal instruction-domain matrices and reference reciprocal with integer arithmetic. Device identity was recorded after the run in `DEVICE_AFTER_RUN.txt`. No claim of original-model or architecture-independent numerical equivalence.
