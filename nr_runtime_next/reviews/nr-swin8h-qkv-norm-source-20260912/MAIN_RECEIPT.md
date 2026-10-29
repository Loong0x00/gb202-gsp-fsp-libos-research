# Main receipt, not normalization acceptance

Worker completed. Main read the full report. Raw projected bank64x8x3x32 has separately passed all3072originalMMA A/B origins/raw/C/D and49152raw-half boundary comparisons in ../nr-swin8h-qkv-tensor-main-20260912/. The report's proposed Q/K partitions, half reduction tree, RSQRT/scale sequence, Q/K packs and V transpose remain to be independently validated against actual source operands and intermediate values. Do not upgrade normalized_QKV_proved=False based on this source-only report.

The original byte range7130..10910 contains no new bar.sync; the prior FFN shared-ready barrier precedes it. Do not add a synchronization step merely from report wording “after the barrier”. Original loops/instructions remain intact.

CORRECTION: the preceding no-barrier paragraph is false. See MAIN_BARRIER_ERRATUM.md; original10536 / PC5213 is an existing barrier, already executed and preserved.

Later bounded numerical acceptance: ../nr-swin8h-qkv-normalized-main-20260912/RESULTS_AND_ERRATUM.md now validates all source reductions/RSQRT/scale/transpose/packing and physical QK/PV operands. Earlier receipt describes its historical unaccepted state, not current status.
