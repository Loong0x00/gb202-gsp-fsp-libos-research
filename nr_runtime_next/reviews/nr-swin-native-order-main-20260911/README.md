# Main acceptance: native ordering audit

Main reran eight CPU/static tests and all artifact checksums from `nr-swin-sync-native-order-20260911` successfully.

Accepted evidence:
- Seven original SM120 functions were byte-checked against the DLL and decoded by both tools. They cover standard FP8/non-FP8 wait/chained/tilesync and module06 clear. **This bounded SASS audit did not decode the selected inpview_tilesync producer**; do not relabel the standard producer disassembly as that exact entry.
- Inspected release epilogues contain `MEMBAR.ALL.GPU` and zero stores. Consumer flag polling uses `LDG.E.NA.STRONG.GPU`; the name STRONG.GPU is not proof of acquire semantics. No decoded post-poll MEMBAR/CCTL/acquire-labelled instruction closes that proof.
- Host wrapper normally records an ALL_COMMANDS→ALL_COMMANDS, SHADER_WRITE→SHADER_READ|SHADER_WRITE barrier before launch, but **bypasses it when incoming-completion is present on the Vulkan backend**. A base-handle fallback can retain the same skip flag.
- Reset's and no-incoming producer's prebarriers are conditional ordering candidates. The pre-clear barrier does not order subsequent clear writes; the pre-producer barrier is the relevant candidate. No actual consumer/reset/barrier execution or NVX memory-class contract has been captured/proven.

No runtime bug, stale-zero occurrence, stronger native acquire, safe readback, or full-kernel equivalence follows. The driver may choose ELF or PTX; original ELF disassembly is not a capture of relocated executing code. These limits remain explicit.

No GPU/Wine execution or installed/source modification was performed in this Main acceptance step. Tests/logs only are retained here.
