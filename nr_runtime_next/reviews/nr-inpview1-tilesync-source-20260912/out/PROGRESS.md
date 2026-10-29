# Progress / handoff

## Final status

**Completed the bounded source-only INPVIEW_TILESYNC gap.** Final static checker PASS. Base5505 / tilesync5531, both96-byte ABI, both actual source hashes match PACKET. All5505 base instructions match through a5810-symbol bijection; the5495-instruction contiguous common region has5523 exact boundary-labelled CFG edges. The complete26-instruction delta and its side effects are retained, not elided.

Tilesync is **signal-only, not producer-waiting**: ABI56 pointer; logical-W/X-derived per-CTA slot; all-path `bar.sync 0`; full-thread-ID leader selection; `st.release.gpu.global.L1::no_allocate.s32` of zero. ABI40 and48/52 are not read. Source proof does not establish full base equivalence, counter lifecycle, live dispatch, actual native visibility, or numerical/model acceptance. Main may continue its independent base INPVIEW NN work; this worker did not execute it or revisit accepted pre0/slab evidence.

## Work sequence and preserved failures

1. Read mandatory PACKET first, with `functions.read(offset=1,limit=2000)`.
2. Read the two allowed reports, in one parallel call, each `offset=1,limit=2000`, complete and untruncated. Their prior claims were context, not authorization to access referenced outside paths.
3. Wrote and ran `out/ingest.py` once. It ingested only the five whitelisted primary files, in at most2000-line chunks, wrote exact generated caches, and retained byte-range/chunk-hash ledger records. It refuses to overwrite an existing ingestion ledger on rerun. Actual SHA256/size results matched every packet entry.
4. First cache-only exploratory Python command read `cache_base.ptx`, `cache_tilesync.ptx`, and `cache_BASE_CORE_ALPHA.json`; printed bounded nonempty source prefixes/tails and JSON schema summary.
5. Second cache-only exploratory Python command read the same three caches and wrote `parsed.json`. Its provisional line parser counted5531/5557, incorrectly counting local declarations and bundling inline operations. **`parsed.json` remains unchanged and INVALID.** It was not used by the strict checker.
6. Strict-checker run1 failed on actual `.reg.b16 hl, hu;` at base source line8329. Exact traceback was automatically appended to `CHECKER_FAILURES.log`. Only two source caches were read; no new primary reads. Parser now recognizes `.reg` declarations followed by whitespace or a dot; this is lexical parsing, not assembler validation.
7. Strict-checker run2 passed initial statement parsing and full textual alpha checks: actual5505/5531, all5505 pairs,5810-symbol bijection, all26 additions. Again, only two source caches were read.
8. Expanded checker with local-scope validation, boundary-labelled CFG proof, exact delta checks, ABI/side-effect checks, prior-alpha composition, integer-address/leader tests, and negative mutations. Run3 failed a lexical-gap assertion: it incorrectly sent the common closing scope at base5504 to the mapped `ret`5530, rather than the pre-barrier frontier5516. Traceback retained. This is a real distinction between an instruction match and its incoming control/scope frontier, not a reason to erase synchronization.
9. Corrected that explicit scope-gap boundary; run4 passed all expanded checks. Read only six generated inputs: the five caches plus `INPUT_READS.json`. Its log was appended after the preserved failed run.
10. Added explicit common memory-site/raw-register mappings and alias/lifecycle caveats, wrote REPORT/EXPLORATORY_FAILURE, and ran checker5. **Final PASS**, exit0; same six generated inputs, no additional primary reads. Final output:

```
PASS: 5505 exact mapped instructions; 26 additions; 5810-symbol bijection; 5523 boundary-labelled CFG edges
PASS: integer address cases 12645 positive grids 1032 leader cases 129 primary read units 22
```

`DERIVED_READS.jsonl` automatically records cache/ledger inputs and their hashes for each of the five strict-checker invocations. The two exploratory cache-read sets are recorded above. Shell `tail` read only generated `CHECKER_RUN.log`:6 lines after run3,9 after run4,2 after run5. These generated cache/log checks are separate from the primary-input ledger. Local script files were read by the Python interpreter. All absolute primary and generated task-data read paths are listed in REPORT; no other project/source files were accessed.

## Exact primary-input budget

**22 /24 units consumed, two unused; each≤2000 source lines.** No input/output truncation required an unrecorded reread. Full byte/chunk evidence is in `INPUT_READS.json`.

| Units | Absolute primary path | Exact span |
|---|---|---|
|1|`/home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/PACKET.json`|first tool read, offset1,limit2000,complete|
|2|`/home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/BASE_REPORT.md`|tool read, offset1,limit2000; actual156 lines|
|3|`/home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/HOST_REPORT.md`|tool read, offset1,limit2000; actual146 lines|
|4..11|`/home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/base.ptx`|1..2000,2001..4000,4001..6000,6001..8000,8001..10000,10001..12000,12001..14000,14001..14159|
|12..19|`/home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/tilesync.ptx`|1..2000,2001..4000,4001..6000,6001..8000,8001..10000,10001..12000,12001..14000,14001..14189|
|20|`/home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/BASE_REPORT.md`|1..156, complete identity ingestion|
|21|`/home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/HOST_REPORT.md`|1..146, complete identity ingestion|
|22|`/home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/BASE_CORE_ALPHA.json`|1..1,614339 bytes, complete bounded CPU ingestion|

The two report tool calls were parallel; units2/3 identify calls, not an asserted physical completion order. Cached retries never read the original primary files. No destructive action or input mutation occurred.

## Verification / reproducibility

Final reusable command, reads generated caches only:

```
PYTHONDONTWRITEBYTECODE=1 python /home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/out/static_checker.py
```

Checks include exact source identity against ingestion; semicolon-aware instruction counting; all-token bijective alpha; local declaration/scope matching; exact added opcodes, operands, predicates and labels; full CFG retention and explicit common-frontier graph equality; absence of waits/acquires/atomics/backedges; exact ABI load ranges; original arithmetic/warp-op and path counts; supplied prior alpha's base-side operands and composed records;12645 wrapping/signed signal-address cases;1032 positive-grid bijections;129 leader-predicate cases; seven rejected source mutations.

No barrier/signal/wait/ret is executed or modeled as a CPU substitute. Address tests evaluate only integer expressions. No first/full NN prediction, original numerical run, CUDA compilation, PTX/native execution, DLL/PE/Wine/GPU/network access, outside discovery/recursive scan, nested agent, deployment, or gate change was performed.

Remaining uncertainty is intentional: model identity cannot be runtime-attested here; the supplied ordinary-source proof antecedent and host report are not freshly revalidated from outside source/DLL files; actual signal allocation/initialization/reuse/aliasing, live launch shape/arguments/dispatch, consumer acquire/publication, GPU visibility, and numerical/native acceptance stay open.

## Files changed / artifact catalog (all absolute paths)

All were created or updated only under the authorized out directory. No other project path changed.

- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/out/REPORT.md` — source-proof report, full delta interpretation, acceptance boundary, all actually read paths.
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/out/PROGRESS.md` — this handoff, exact budget, failures, artifact catalog.
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/out/DELTA.json` — measured identities, complete26-instruction delta, ABI/signal semantics, CFG/core proof summary and conditions.
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/out/static_checker.py` — reproducible CPU lexical/alpha/CFG/address checker, no kernel or synchronization execution.
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/out/ingest.py` — one-shot bounded whitelisted ingestion; refuses ledger replacement.
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/out/INPUT_READS.json` — exact22-unit primary read ledger, byte intervals and hashes.
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/out/DERIVED_READS.jsonl` — append-only generated-data read records for strict-checker invocations.
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/out/PARSED_PTX.json` — authoritative executable instructions, original source lines, labels, declarations, lexical scopes.
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/out/ALPHA_PROOF.json` — every base↔tilesync instruction/operand position and bijective symbol witness.
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/out/CHECKER_INTERMEDIATE.json` — complete actual CFGs and added instructions; barriers/signals retained.
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/out/PRIOR_ALPHA_COMPOSITION.json` — prior proof's verified base-side/internal consistency and ordinary→tilesync composition, explicitly conditional on unread ordinary antecedent.
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/out/STATIC_TESTS.json` — static path bounds, address witnesses, positive grids, leader and mutation test results.
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/out/CHECKER_FAILURES.log` — both strict-checker failure tracebacks, preserved append-only.
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/out/CHECKER_RUN.log` — scope-check failure and later successful checker outputs, preserved.
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/out/EXPLORATORY_FAILURE.md` — explanation and rejection of provisional parser result, plus corrected strict-checker failures.
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/out/parsed.json` — deliberately preserved INVALID provisional parse; not used as proof.
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/out/cache_base.ptx` — exact generated byte copy, hash-checked, used for retries only.
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/out/cache_tilesync.ptx` — exact generated byte copy, hash-checked.
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/out/cache_BASE_REPORT.md` — exact generated report cache, hash-checked.
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/out/cache_HOST_REPORT.md` — exact generated report cache, hash-checked.
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/out/cache_BASE_CORE_ALPHA.json` — exact generated prior-proof cache, hash-checked.
