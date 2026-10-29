# Main acceptance: source-proved Q/K HFMA2 policy

Main read the full instruction/operand proof and ablations, reran9 CPU tests, verified65 external pins and worker artifact checksums. See `nr-finalpost-numeric-gap-20260911/REPORT.md`.

Original SASS proves32 Q/K paired-square contractions:
`RNhalf(x*x + RNhalf(y*y))`, not `RNhalf(RNhalf(x*x)+RNhalf(y*y))`.
The first square is fused; swapping the choice is not equivalent. Correcting exactly these proved CPU expression boundaries removes all14/256 F32 differences in the original no-texture one-CTA fixture, with both existing approximation policies. No output fitting, input/weight change, device-source patch or surface-based arithmetic inference was used.

The known merge skip-product contraction does not affect this power-of-two input fixture. General F16-head MMA/signed-zero discrepancies remain in the prior primitive tests; they are not erased by this result. Output equality for one fixture does not establish every internal value or all inputs.

A separate held-out preparation task at `nr-finalpost-heldout-prep-20260911` is freezing non-power-of-two input fixtures and predictions BEFORE any new GPU result, to test the source-derived policy rather than optimize against the calibration fixture. No held-out native result exists yet.

This CPU-reference correction is **not a fix for installed-game image quality**: those games already execute the original NR DLL and its original fused instructions. Community input/output codec and pass-profile differences are being investigated separately.
