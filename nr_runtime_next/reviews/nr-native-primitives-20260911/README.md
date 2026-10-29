# Main native primitive oracle — 2026-09-11

Owned CUDA kernels, NOT the original model, no DLL load/patch, no game. Original-style SM120 conversion/HMMA instructions are independently compiled with installed CUDA13.3; no original PTX9.4 header is downgraded. SASS is retained. Serial benchmark lock, no-game checks, Guardian/global31000MiB protection, CUDA free-memory reserve and bounded 20s experiment watchdog. Run `runs/20260911-131354` exited0 with Guardian0 and explicit device synchronization/readback/context cleanup.

## FP8 conversion

Compared to `../nr-ptx-quantization-20260911/ptx_fp8.py`:
- Packing enumerates all65536 half encodings as `(h, h XOR signbit)` pairs. All **63490 supported pairs** (all63488 finite encodings plus both infinities) match bit-for-bit.
- Unpacking enumerates all65536 two-byte combinations. All **64516 non-NaN pairs** match bit-for-bit.
- Unsupported NaN pairs retain native raw observations separately. This does not infer a portable NaN sign/payload rule or authorize silent sanitization.
- Packing did not enumerate all2^32 half pairs; ISA lane independence plus this exhaustive scalar-domain paired test is the scope.

## Final-head FP16 MMA

Two PTX-visible K16 stages use the original128 learned head coefficients and112 synthetic16x32 input matrices. Native packed fragments and each stage's outputs are saved. No real neural activations were captured.

Live four-component counts per stage:
- All2048 one-hot/basis outputs and448 zero/constant outputs are bit-identical to the declared exact-inner-dot/RN-half reference.
- In4096 dense-random outputs, **one differs by1 half ULP in each stage** (max absolute error5.96e-8 and3.81e-6).
- Small-half fixture bit differences102/75 are **signed-zero only**, no nonzero numerical errors.
- Unused four columns are zero but are not counted as live-output agreement.

Therefore the general native accumulator is **not** proved bit-identical to an exact inner sum rounded once. The discrepancies are retained, not fitted away or normalized into a false all-pass. This validates fragment/weight reasoning on the tested domain, not full-model equivalence. `NATIVE_RESULTS.json` includes individual differences and a second-stage comparison conditioned on actual native first-stage values.

Reproduce CPU fixture generation/analysis with `make_fixtures.py` / `analyze.py`. GPU execution additionally requires exact `APPROVAL.json` pins and `run.py --execute`. Do not re-run alongside games or other GPU experiments.
