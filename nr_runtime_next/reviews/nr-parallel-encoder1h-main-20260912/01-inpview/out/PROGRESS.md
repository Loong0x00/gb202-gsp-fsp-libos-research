# Progress / limitations

## Completed
- First read was this task's `PACKET.json`; requested model metadata is `openai-codex/gpt-6-astra`, thinking `xhigh`. No model-switch/introspection API was used and no nested worker was spawned.
- Independently hashed/read base INPVIEW and ordinary PTX; corrected parser verifies exactly 5505 / 4902 instructions, respectively, both 96-byte ABI.
- Recovered per-byte INPVIEW source addressing, singleton broadcast, source-zero guards, predecessor channel permutation, and raw-expansion/decoded-residual forks.
- Exact 4721-instruction, 5087-symbol core alpha map; all 256 MMA operands mapped; projected core CFG equality proved. Recovered 12288 weight-byte operand coordinates and 4096 attention-bias half coordinates from addressing/ISA semantics, not from identity layouts.
- Static address/provenance tests PASS. No numerical NN, original numerical campaign, native execution, or acceptance claim.

## Preserved failures / read budget consequence
1. `FAILURE_01_label_parser.log`: label was incorrectly treated as an instruction. This attempt read the whole INPVIEW source in eight <=2000-line chunks before failing.
2. `FAILURE_02_inline_scope_parser.log`: inline `;}` rejected. This also consumed eight source chunks.
3. `FAILURE_03_declaration_count.log`: permissive parser counted inline declarations as instructions (5539/4936). These counts and associated candidate alignments were not accepted.
4. `FAILURE_04_inline_declaration_store.log`: subsequent cache-only parser omitted inline stores; count assertion failed (5497/4894, diagnosed from cache). Final lexer retains all eight inline store/pack instructions and discards declarations, giving exact expected counts.

Five initial bounded reads + 16 failed-attempt source chunks + 15 successful source chunks = **36 bounded source-input reads**. Source files were not opened again. Subsequent work only inspected/replayed this task's generated `out/` artifacts. The final parser defaults to generated caches; re-running it does not consume new source reads.

**Deliberate incomplete scope:** `inpview_tilesync.ptx`, `block1-slab.bin`, DLL, host proof JSON, and remaining optional inputs were NOT read after this budget was reached. Therefore tilesync's 5531 count/delta, block1 slab bytes/hash, and fresh current-byte host selection are not independently verified here. Packet/source-report statements about them are labelled as such. Do not interpret this as full task closure.

## Next bounded follow-up (requires new authorization/read budget)
- Independently parse/hash 5531-op tilesync and produce its full exact base-vs-tilesync PC/operand/CFG exceptions, including synchronization.
- Read/hash the own 20672-byte block1 slab; materialize immutable learned values according to the recovered field/neuron map.
- If needed, recheck selected bounded PE host-selection witnesses under packet PE limits. No live allocation/dispatch/native precision claim follows from these static tests.
