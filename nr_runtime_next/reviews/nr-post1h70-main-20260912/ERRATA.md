# Source, oracle, observer and interruption record

Nothing here changes the nine frozen first numerical NN files or first prediction bytes.

## Worker source review

- Worker `nr-post1h70-source-20260912/REPORT.md` says QK C/bias starts11360. Current source and all actual C-operand byte origins prove **11472**. QKV starts8400; ordinary1h offsets cannot be inherited.
- Its P1 table says a128-byte record while showing `4*(128*tile)+16*lane`: that is **512 bytes per 4x4 C32 tile**, not128 bytes or128 semantic channels. Main source expressions independently establish C32 high-resolution input and A32 half-resolution input, not a stride-based guess.
- Exact current entry lacks `_rgb`; the graph label is not an entry name. Current source and older `finalpost-original.ptx` match only after removing the older `.visible ` prefix and edge whitespace; raw hashes remain different (`SOURCE_COMPARISON.json`).
- Copied candidate NN docstrings mentioning256/768 channels, grouped FFN, etc. are stale prose, not the typed contracts. Actual shapes are64x32 features,32→128→32 FFN,64x96 rawQKV, one attention head. These frozen file bytes were not rewritten to repair prose.

## CPU oracle support failures (not NN repairs or mere observer fixes)

1. `FIRST_RUN.log`, `FIRST_EXECUTION_FAILURE.json`, `FIRST_VM.py.txt`, `FIRST_LITERAL.py.txt`, `FIRST_RUN_SCRIPT.py.txt`: first NN completed/froze before original CPU execution. Original reached PC6579 DIV.APPROX after256FP8+16F16 MMAs, then deliberately refused an unimplemented instruction policy. Null texture handles do **not** eliminate the coordinate divisions.
2. Added an explicit, separately named `(pixel+.5)/128` exact-dyadic **CPU reference** in `coordinate_policy.py`; other denominators/inputs fail. This is not a native DIV.APPROX claim. All32768 default divisions execute; the actual trace finds zero active reads of their results in this null-TEX branch. No executed division was deleted or replaced with zero.
3. `ORIGINAL_RESUMED.log`, `FIRST_NONFINITE_GUARD_FAILURE.json`, `SECOND_VM.py.txt`, `FIRST_COORDINATE_RESUME.py.txt`: finite-only arithmetic policy refused the source's literal **+Inf** operand in `setp.equ.ftz.f32` atPC6630. Added the actual unordered-or-equal predicate in `ieee_compare.py`, not `nan_to_num`, not a replacement of neural values. Arithmetic nonfinite domains remain refused. Frozen NN `f32_ops.py` is unchanged.

## Timeouts and interruption

- `ORIGINAL_RESUMED2.log` and `FIRST_TIMEOUT_PROGRESS.json`:300s tool timeout after285/289 passing CTAs. No output mismatch. Process termination was checked; the in-memory full output was not relabelled/reconstructed from the prediction.
- Four first chunk launches were interrupted before producing results; their empty original logs are retained. No lingering process remained.
- Four `.RETRY.log` runs completed all289 CTAs with genuine per-chunk original pixel captures. `assemble_grid.py` constructs ORIGINAL solely from those captured pixels, with duplicate/coverage/equality checks.
- Initial assembler incorrectly expected16384 divisions. Actual captures prove32768 (two per stored pixel, across both query halves). `FIRST_ASSEMBLER.py.txt` and `ASSEMBLE_GRID.log` are retained; only the accounting assertion changed.

## Observer/test corrections

- `FIRST_HEAD_STORE_OBSERVER.py.txt/.log`: unknown scalar constant metadata defaulted to four bytes in a16-bit `selp`, causing a shape/broadcast error. Fixed metadata width only; then all289 head/store observers passed.
- `FIRST_ATTENTION_OBSERVER.py.txt/.log`: excluding head/epilogue throughPC5814 also erased provenance of second-query bias loads at5779..5814. The exclusion now ends at5766; actual head/epilogue remains independently checked. Original and NN unchanged.
- `FIRST_TESTS.py.txt/.log`: the test probe incorrectly expected `(name,array)`; existing immutable callback contract supplies only `array`. Fixed test closures, not model hooks or numerical code. First API attempt failed at the test hook after numerical computation; subsequent no-I/O API tests passed. The earlier first direct NN and first23-block chain forwards independently passed their no-I/O gates.

`ALL_NORMALIZATION.json` and `ALL_ATTENTION.json` are initial **one-CTA** reports, despite their inherited names. The1156 per-CTA records and `ALL_PROOFS.json` establish four distinct full289-CTA proof scopes. `FIRST_INSTRUCTION_INVENTORY.json` is the original parser inventory; parser whitelist admission is not general execution/native support. TEX and EX2 remain runtime-refused here.
