# Selected tilesync CPU data reference + explicit publication intents

Main reran the sibling variant review: 19 tests and all artifact checksums passed. Its exact-source certificate matches all 5504 common non-return instructions under typed register/label bijection, operand/dataflow and control-flow checks. Tilesync adds 26 instructions, including `bar.sync 0` and a thread-zero GPU-release store of zero. This is **not an atomic RMW** and not a host fence.

`selected_reference.py` connects the certified common arithmetic implementation to the independently verified symbolic publication planner. It checks pinned sources, actual block1 slab, bounded CTA and nonaliasing logical input/output/slab/sync regions. Both the formula and original-extra-instruction planner must agree. Unsupported native/concurrent synchronization is rejected.

The result contains:
- CPU reference data-output patches;
- explicit barrier/release **intents after those data stores**;
- `native_sync_executed=false`, `whole_kernel_native_equivalence=false`.

No release or GPU memory operation is performed. A supplied logical span is a CPU-model boundary, not physical allocation ownership. No missing memory is invented; no complete-model or native activation provenance is asserted.

`python3 -B test_selected_reference.py`: **6 tests pass**. The selected CTA(1,1), using captured 96-byte argument metadata but explicitly synthetic finite FP8 inputs, computes 2048 output bytes. Its planned sync-word address is workspace base +196, within the 5376-byte logical flag range. Common data patches match plain reference computation; this tests integration, not native arithmetic parity. Wrong policies, aliasing, short flag span and out-of-grid CTAs fail.

Consumer acquire, flag initialization/reuse, real allocation lifetime and GPU synchronization remain unresolved. A CPU/static subagent is pursuing those in `../nr-swin-sync-protocol-20260911/`; do not assume all flags start zero or omit the publication epilogue in a native replacement.

Changed only this review directory. No GPU/Wine run, installed configuration, original PTX, signed DLL or previous worker source was modified.
