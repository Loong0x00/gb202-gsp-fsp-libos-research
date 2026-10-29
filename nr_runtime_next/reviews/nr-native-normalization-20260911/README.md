# Main native normalization primitives

Owned CUDA/SM120 primitives, not original model execution or intermediate activation capture. Run `runs/20260911-134003` passed explicit device completion/readback/cleanup, exit0/Guardian0, with serial no-game/global31000MiB/reserve protection. The original PTX9.4 was not downgraded or recompiled; this new primitive program uses supported instructions with installed CUDA13.3.

- For all63488 finite half encodings paired with the opposite-sign encoding, original-constant HFMA2 affine stage, half clamp, and the whole-word shift/add transform **each match CPU reference bits exactly**. This validates the pointwise part of the special normalization, not the entire reduction tree or standard softmax.
- For all31743 positive finite half values expanded to F32, native `MUFU.RSQ` differs from correctly rounded F32 in7090 cases. After the actual following half conversion, **all results match**. Original query/key normalization has this half→F32→RSQRT→half structure. No arbitrary-F32 or architecture-independent parity is inferred.
- NaN/negative-root raw outputs are retained but outside the supported numerical comparison. No NaN is sanitized into a fictitious finite activation.

`analyze.py` reproduces comparison with integer references; raw outputs and source hashes are retained. Full model, live activation values, and general native MMA equivalence remain unproved.
