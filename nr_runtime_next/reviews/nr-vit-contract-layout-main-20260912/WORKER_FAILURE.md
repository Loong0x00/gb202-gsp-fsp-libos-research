# Preserved worker failure notice

Worker `nr-vit-contract-tensor-reference-20260912` reported a NumPy prototype mismatched the sealed a949… output and that it found consumer MMA-A indexing different from producer OUTPUT_MAP. Worker then removed its prototype rather than delivering it. Main confirmed the directory had no regular files after completion; earlier inspection had seen contract_tensor_reference.py10375bytes and README.md1311bytes. No exact failing-output digest or failed source snapshot was delivered, so those cannot be independently reproduced from that notice. This falls short of the requested historical-failure retention; do not silently call the worker prototype verified or restore invented content.

Main proceeds in a new directory with explicit source equations, preserved predictions/results and independent per-operand checks. The existing full original-instruction CPU contract and sealed expand outputs remain unchanged.
