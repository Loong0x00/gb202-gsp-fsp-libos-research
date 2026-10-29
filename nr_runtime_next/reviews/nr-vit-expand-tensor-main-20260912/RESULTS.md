# Main acceptance: complete bounded expand tensor reference

Main reran all five tests of `nr-vit-expand-tensor-reference-20260912`: PASS. The CPU NumPy operator exposes logical input[128,1024], real weight[1024,4096], preactivation[128,4096], logical FP8 output and full524288-byte physical output, plus immutable detached observation hooks. No DLL execution is involved.

It performs32 exact-in-float64 finite E4M3 K32 dots, rounding to half **after every K32**; not a once-rounded dense GEMM. Full CTA-x addresses are source-derived. Independent selected-coordinate arithmetic checks pass. All16384 output bytes of both actual original-instruction CPU CTAs0 and31 match. Other CTAs are lifted computations and address-proved, not separately literal-executed here. This is not native GPU parity.

Main also independently compared the vector tail with the earlier Fraction/source oracle across all63488 finite-half inputs: **62585 admitted results and FP8 packs match bit-for-bit;903 cases explicitly refuse half-overflow**, as required by this tensor implementation's narrower finite-tail domain. NaNs are refused, not converted to saturated output. The previous failed-WebSocket CTA0-only candidate's NaN-saturation bug is not accepted or reused. Source constants are ab28/3728/3b28.

`FORWARD.json` and four binary artifacts retain a complete bounded synthetic-input result. Physical output524288bytes:
`b0435e97871e72c2cf17263355c42bdc35d4399509ef5193635828aca67ce87e`.

That full output, together with the retained input, was consumed by the Main original contract full-grid CPU reference in `nr-vit-contract-main-20260912`. This is meaningful NN-facing forward progress, **not a complete standalone equivalent network, all-domain activation support, or the entire ViT block**. Observation hooks are not an equivalence certificate or validated causal intervention interface.

No GPU/Wine/installed/network changes. Reproduction: worker tensor test suite (`python -B .../test_expand_tensor_reference.py`, `OPENBLAS_NUM_THREADS=1`) and Main `check_tail.py`.
