# Main packet preparation correction

The first extraction command looked for a guessed `_4h_128_8_upsample_fp8` entry and stopped with StopIteration before writing a source packet. The tool failure is retained in the ledger; previously completed OUTVIEW/decoder-stack seals were already verified and unchanged.

A bounded read of the exact entries.tsv resolves the actual FP8 entry to `cc_tinlayout_fused_swin_4h_128_4_upsample_fp8`, module02-dll-006fe100,7235instructions,88ABI. The corrected packet uses that exact entry. No instruction, layout, tensor or launch dimension is inferred from the naming correction.
