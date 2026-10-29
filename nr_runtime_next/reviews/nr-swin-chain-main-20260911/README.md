# Main verification: block1 → shifted plain block2 CPU chain

Main reran the worker's nine chain tests and artifact checksums successfully. Four block1 inpview tiles with real block1 weights supply the shifted plain-standard block2's complete input readset, using real block2 weights. Output is a complete 2048-byte tile under explicit reference arithmetic. Input image/features, H=W=16 and shift(-4,-4) remain synthetic.

Additional Main check (`verify_numeric_policies.py`):
- Replaced only reciprocal/rsqrt RN-f32 policies with the pinned, previously measured SM120 half-input LUT callbacks. No GPU call occurs during lookup.
- The complete fixture output remains byte-identical: `b8f5488f5784b14adc1004cd4a74214a39750dbb2ef15f25b94cabd2488ddb97`.
- Re-ran block2 with its synthetic input address explicitly equal to the producer's output address, and supplied only the 2048 actually required bytes. Output patches still match; removing one input byte rejects.
- 6144 rsqrt and 768 reciprocal LUT calls were checked across the fixture and additional consumer. These finite half-domain observations do not establish general native math, Tensor Core parity, sampler behavior or synchronization.

`NUMERIC_POLICY_VERIFICATION.json` retains results. No activation was captured, no native consumer selection established, no barrier/polling semantics erased. Standard wait/chained common-body certification is a separate ongoing review at `nr-swin-standard-variants-20260911`. Actual descriptor numeric shifts are still unobserved; the word “shifted” does not prove their values.

No original source/PTX, signed DLL, installation or GPU state was changed. All Main outputs are confined to this directory.
