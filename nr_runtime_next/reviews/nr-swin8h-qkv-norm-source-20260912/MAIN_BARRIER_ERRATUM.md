# Main correction: barrier at original10536 / parsed PC5213

The final paragraph of MAIN_RECEIPT.md incorrectly asserted there was no bar.sync in7130..10910. Main's immediate explicit-file assertion failed before sealing or packet construction; the tool failure is retained in the ledger. Direct bounded inspection shows original line10536 is `bar.sync 0`, immediately after the final V FP8 pack and before seed-address calculation at10537. It is the already-preserved PC5213 barrier (shared epoch6), whose byte contents equal FFN epoch5 in the full original capture.

Thus the worker's “after the barrier” was correct; Main's contrary inference from reading separated snippets was not. No source, VM, scheduling, arithmetic or NN implementation changed. Existing original execution already included this barrier. This is a factual Main-note erratum only, not a numerical repair. MAIN_RECEIPT.md is retained unchanged apart from an appended pointer to this correction.
