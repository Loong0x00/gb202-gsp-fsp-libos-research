# Progress — STOP, bounded source task completed

## Outcome

- Actual PTX counts independently parsed: base4902, wait4979, chained5005.
- Full common instruction/operand maps:4902 base→wait and4979 wait→chained; three explicitly proved integer-add source commutations in the former, no operand permutations in the latter. Independent coordinate-division reorder and parameter-load hoist checked.
- Full CFGs and conditional common-frontier maps retained, including all polling backedges, CTA barriers, cache qualifiers, sleep and outgoing release-zero.
- Important source finding: consumer polls **relaxed.gpu**, not acquire; ready means **signed nonnegative**, so pending must be **signed negative**, not just nonzero.
- Chained adds release-zero after a CTA barrier; wait has no outgoing signal. Supplied INPVIEW producer claim is conditionally slot/payload compatible, **not a GPU visibility/epoch/progress proof**.
- Supplied main base1/base2/base3 acceptance boundaries remain unchanged. No NN/native/GPU execution or deployment acceptance attempted.

## Chronology / preserved failures

1. Read exactly the absolute PACKET path first, then the two exact supplied report paths. No files outside the packet input set were discovered.
2. Wrote and executed `out/ingest.py` once. It charged a packet identity reread, seven≤2000-line chunks for each PTX, and one identity reread for each report. All packet hashes/sizes matched. The DLL was deliberately not opened or hashed.
3. Initial strict parser correctly produced4902/4979/5005 and56 declarations each. A shape-only alignment was exploratory, never accepted as an operand proof: it could not disambiguate identical-looking division groups or adjacent `bra.uni` sites. The final map uses exact operand constraints and CFG checks.
4. Generated-cache projections inspected the three prefixes/tails, initial base instructions, memory/sync census, output guards/addresses and register witnesses. No further primary input read occurred.
5. Three actual static-checker failures are preserved, unedited, in `CHECKER_FAILURES.log`:
   - an `add.s32` token-length precondition incorrectly expected8 rather than7 tokens;
   - exact operand checking discovered the third source-order exchange atbase4112→wait4189, not just the two prefix adds;
   - added-destination nonclobber checking initially supported only scalar destinations and rejected ABI48's vector destination.
   Corrections respectively fixed the token count, explicitly added the third integer commutation, and used balanced operand splitting for scalar/vector destinations. No predicate/opcode exception was broadened to conceal a mismatch.
6. Full alpha/CFG static pass succeeded. Added bounded integer/control/finite-observation tests, exact delta fingerprints and12 negative mutations. The complete checker then passed.
7. Wrote REPORT and this progress record. Evidence review corrected a draft scope-event count to the actual **2996** per comparison;52 is the local-declaration count, not the number of lexical scopes. No additional primary reads were used.
8. Final rerun and artifact checks are recorded in `CHECKER_RUN.log` and `ARTIFACT_CHECKS.json`. STOP with9 unused primary units; no native follow-up is authorized or implied.

## Primary read ledger: 27 / 36 units

`INPUT_READS.json` is the exact machine ledger: absolute paths, line offsets/counts, byte offsets/counts, SHA256 per bounded chunk, full non-DLL identities and initial-read identity attribution.

| Units | Input | Extent |
|---|---|---|
|1|absolute `PACKET.json`|initial `functions.read`, limit2000, complete|
|2|absolute `in/HOST_REPORT.md`|initial `functions.read`, limit2000, complete146 lines|
|3|absolute `in/INPVIEW_SIGNAL_REPORT.md`|initial `functions.read`, limit2000, complete209 lines|
|4|absolute `PACKET.json`|complete identity/allowlist reread|
|5–11|absolute `in/base.ptx`|lines1–13552; six2000-line chunks and1552 lines|
|12–18|absolute `in/wait.ptx`|lines1–13641; six2000-line chunks and1641 lines|
|19–25|absolute `in/chained.ptx`|lines1–13671; six2000-line chunks and1671 lines|
|26|absolute `in/HOST_REPORT.md`|complete146-line hash/size ingestion|
|27|absolute `in/INPVIEW_SIGNAL_REPORT.md`|complete209-line hash/size ingestion|

Every primary chunk is≤2000 lines. The initial combined prefix/tail projection was also below2000 output lines and was not tool-truncated. Empty EOF probes contain no source lines. Nine units remain unused. The independent readonly DLL's metadata was read **only as text in PACKET**, never checked by opening/scanning its bytes.

## Generated-artifact reads (not additional primary inputs)

All generated dependencies are confined to this `out/`. Earlier exploratory/failed executions are documented here; the automated `DERIVED_READS.json` is the latest checker's dependency list, and `DERIVED_READS.jsonl` records successful complete checker runs, not a claim to automatically log Python's code/library reads.

- `ingest.py` reads its newly written `cache_base.ptx`, `cache_wait.ptx`, `cache_chained.ptx` for bounded projections after the charged ingestion.
- Every checker invocation loads only `cache_PACKET.json` and those three PTX caches. There were an initial parse-only success, three preserved failures, a full-alpha success, and complete protocol-check passes. Hash checks bind cached PTX to packet identities. No retry reopens primary PTX.
- Three ad-hoc Python projections read `PARSED.json` to show initial/base memory witnesses, output witnesses, then ABI/cvta/warp witnesses. The third also read and enriched `INPUT_READS.json` initial-read identity records using already charged identities.
- A short report consistency check read `BASE_WAIT_ALPHA.json`, `WAIT_CHAINED_ALPHA.json`, and `REPORT.md` to verify local-declaration/scope counts.
- CPU Python executed this task's `ingest.py`, `static_checker.py`, and `protocol_checks.py`. `PYTHONDONTWRITEBYTECODE=1` was set; no task bytecode cache was requested. Standard-library imports are tooling, not additional project discovery.
- `CHECKER_RUN.log` was displayed with bounded `tail`. Final artifact checks read only the explicitly named generated reports/JSON/logs/scripts/caches, recorded by name in `ARTIFACT_CHECKS.json`/`FILES_CHANGED.json`; no recursive listing/scan was used.

## Verification scope

Complete final checker command:

```
PYTHONDONTWRITEBYTECODE=1 python /home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-encoder-next-main-20260912/01-wait-chain/out/static_checker.py
```

Checks include:

- actual counts, ABI/header/register bounds and exact source identities;
- all4902/4979 mapped instructions,5230/5298 symbol bijections,52 local declarations and2996 scope events per comparison;
-4894/4988 conditional common-frontier CFG edges, all actual branches and three natural wait loops;
- all77/+26 deltas, nonclobber sets, barrier-cut reachability and literal synchronization/cache qualifiers;
-7608 scalar prefix formula cases,3600 independent tile-overlap cases,3804 outgoing-address cases,60 leader-predicate cases;
-9 finite observation traces and12 rejected mutations.

The protocol helper refuses all common NN/MMA instructions, requires explicit finite synthetic read tapes, and stops at barriers. Outgoing arithmetic is tested separately and stops before its release store. It neither executes synchronization nor substitutes CPU ordering, and an all-negative trace terminates only by a bounded test cutoff.

## Plainly unverified / not performed

- Native GPU execution, lowering, cache visibility, release/acquire publication closure, scheduling fairness and forward progress.
- Actual pending initialization (**must be signed negative for this source predicate**), reset ordering, epoch association, ABA/reuse prevention, all consumer retirement and data/signal allocation lifetime.
- Live signal handles, pointer validity/alignment/extent/ownership/nonaliasing, equal predecessor/current logical dimensions, actual grid/block/warp launch shape and barrier participation.
- Live slab bytes/binding, all original numeric/full-NN runs, actual host dispatch/gate state, PE bytes, DS wait source, source-module provenance beyond packet source-file hashes.
- Fresh producer-source verification: INPVIEW release-zero/no-inputwait semantics are a supplied hash-verified report claim. Its host tail-field mismatch remains unresolved.
- Independent attestation that the runtime model matches requested `openai-codex/gpt-6-astra/xhigh`.

No network/external discovery, recursive scan, nested agent, DLL/native/GPU/Wine execution, input edits, deployment or gate actions occurred. All task-controlled writes are in this own `out/`.
