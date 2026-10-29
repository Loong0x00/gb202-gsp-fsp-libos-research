# WuWa publisher recovery — isolated, undeployed CPU proposal

## Outcome / confidence

**Reproduced a real baseline-loss mechanism in the current publisher. The cause of physical run 142653 is NOT proven.** All changes/artifacts are confined to `reviews/wuwa-publisher-recovery/`. No Main edits, watcher startup, deployment, game/Wine/GPU execution, process instrumentation, network, protection changes, DB access/writes, or real challenge/lease access occurred. Tests encode lease bytes in memory and mock publication/removal; synthetic `/proc` text fixtures live only under this review directory.

### Supplied live evidence (not independently acquired in this review)

- Second physical run 142653: two `phase.disable.game-started` records for PID **799576**, start ticks **22206176**, and no login scheduling observed.
- LatestLoginTime **1789021679.577476**, reported as 14:27:59; exact process started 14:26:54.
- Challenge-file mtime **1789021629.1857624**, reported as 14:27:09, unchanged at 14:30:25.
- NR gate closed, **0 creates / 0 evaluations**.

Those facts are consistent with baseline loss, but do not identify the failed observation. An unchanged mtime is not proof of identical challenge bytes or uninterrupted successful reads. Same PID/start on the two logged successful polls does not exclude a missing/ambiguous identity in between. Missing/invalid challenge reads, DB unavailable/nonfinite results, exceptions, or a watcher restart also matter. No account keys were inspected or logged.

## Source review and CPU reproduction

Current `PublisherState.close()` calls legacy `PhaseGateState.observe(False, ...)`, clearing the active session baseline/pending deadline/enabled bit, then clears publisher process/challenge binding. The next valid observation invokes `reset_session()`, which uses the *current* LoginTime as `last_idle_login`. Legacy `observe(True, ...)` consequently emits `disable:game-started` again and requires a value strictly greater than that new baseline (`+0.001`, also satisfying its session-wall predicate). An unchanged legitimate login that happened during the read gap is now consumed as baseline, not as a transition. It remains closed until another qualifying update.

`test_baseline_reproduces_duplicate_game_started_and_lost_login` uses the supplied PID/start and login epoch, but an explicitly **synthetic prelogin value and hypothetical failed read**. It reproduces the duplicate disable, no schedule, and continued closure 120 seconds later. This proves the code path, not that run 142653 took it. The production action name for scheduling is `phase.schedule.login-updated`.

The existing publisher tests cover initial login/settle, relog, PID reuse, image selection and wire bytes, but not close/read-failure/recovery. The legacy gate itself permits a `None` read while active without revoking; the publisher must continue overriding that behavior rather than simply passing a failed read through as an active observation.

## Proposed rules

The patch changes only the publisher and one publisher-source-check assertion. The imported legacy implementation and read-only DB query remain untouched.

1. **Every invalid observation closes publication.** DB `None`, nonfinite or nonpositive login results clear enabled/pending state and cause lease removal. Unexpected exceptions hard-reset all proof and attempt removal. Removal failure is reported and exits rather than silently continuing; a failed unlink cannot guarantee instantaneous native revocation, so the existing <=2-second expiry remains the backstop.
2. **Recover DB-only failures, not identity uncertainty.** Retain in-memory evidence only when a previously valid observation established a baseline and every failed-read poll still validates the exact nonmissing Linux `(pid,start_ticks)` and full `ChallengeV1` value. Identity/challenge are re-read around the DB read. Missing/ambiguous/replaced identity, any challenge-field change or invalid/missing challenge discards evidence. An unreadable process candidate now makes selection ambiguous rather than being skipped alongside one readable game image.
3. **Retain evidence, never an enabled lease.** Retained data are the same binding, previously observed pre-transition baseline (or initial sample awaiting a transition), original observed session-wall anchor, last valid login high-water value and bounded monotonic timing. The most recent transition's predecessor is updated on a genuine same-process relog. Enabled/pending state is cleared; no lease bytes are retained or read back.
4. **Fixed 30-second recovery budget**, anchored at the last valid observation before the first failed read. Subsequent failures, resumed polls and relogs cannot extend it. Expiry discards proof and baselines the next valid value; it cannot inherit that already-visible login. This budget includes settling, not just the blackout.
5. **Fresh observations and full >=15-second settling.** On recovery, compare a freshly read valid login with the retained predecessor using the unchanged legacy predicate and original session-wall anchor. A qualifying transition schedules a new full settle from recovery, including when recovering from pending/open state. Every subsequent observation during recovery must remain valid with gaps <=2 seconds; failures or longer gaps clear the pending deadline and require another full settle within the original budget. No immediate reopen or old deadline reuse. Unchanged prelogin baseline does not schedule anything.
6. **Unknown/start/restart cannot inherit.** No disk persistence of recovery evidence, no deriving a prelogin baseline from process start time, challenge mtime, a newly read LoginTime, or an old lease. A new watcher or changed binding baselines its first valid value and waits for another qualifying change. Login/monotonic regression also discards inherited proof.
7. **Policy unchanged.** Publication still requires the explicit owner policy flag. Lease layout, exact bindings, maximum TTL and policy bit remain unchanged. New publication uses a new generation/sequence and freshly encoded bytes. Finite CLI validation additionally rejects NaN/infinity; recovery-compatible poll interval is `(0,2]` seconds.

### Structured diagnostics

`publisher.reject`, `publisher.reset`, `publisher.baseline`, `publisher.revoke`, `publisher.recovery` records include fixed reasons, generation, PID/start, baseline-known/retained booleans, and appropriate previous-enabled/pending/session or remaining-budget/settle metadata. Main's JSON events gain `unix_ns`. Resets distinguish process/challenge changes, missing/ambiguous observations, expired/stale recovery, regression and unexpected exceptions; read rejection and reason for discarding evidence are separate records. No account keys, raw DB values, challenge nonce or database paths are logged. Existing reader APIs still collapse DB missing/read/schema failures into `None`, and identity missing/unreadable/multiple into `None`; diagnostics **do not pretend to distinguish those subcauses**.

## Verification

Re-run safely from project root (does not invoke any watcher):

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -B reviews/wuwa-publisher-recovery/tests/test_recovery.py
```

**36 unittest tests pass**, including:

- current-code symptom reproduction; unknown baseline; midgame watcher restart;
- prelogin, pending and already-open read-failure recovery; full 15-second settle;
- same-process relog, relog during recovery, repeated failure, interrupted recovery;
- fixed-budget expiry on valid/invalid polls; stale evidence; recovery poll gaps;
- exact PID/start replacement, missing/ambiguous identity, all challenge fields, missing challenge, mismatched binding during failed DB read;
- failed/nonfinite/nonpositive reads revoke mocked leases; policy-denied never writes; removal failure surfaces;
- login/monotonic regression; generation/sequence/wire TTL; diagnostic allowlist;
- original publisher assertions against BOTH baseline and proposal (imports/temp directory routed into isolation);
- three existing legacy **state-only** tests (legacy DB-write/marker-write tests intentionally not run);
- existing publisher-specific source assertions (one renamed variable check updated), AST checks of main's revalidation and exception-removal wiring.

`test.log` records results. `verification.log` records source checksum preservation and isolated patch dry-runs. `SOURCE_SHA256SUMS` pins the original inspected files; `SHA256SUMS` pins review artifacts.

## Caveats / handoff

- **Proposal only; do not deploy or start it from this review.** It intentionally cannot rescue the already-missed live transition without pre-existing in-memory proof. Do not invent LoginTime updates, edit the DB, toggle policy, or manually write a lease to compensate.
- Recovery is intentionally unavailable after unreadable/ambiguous identity or challenge, or beyond its fixed budget. A configured settle >=30 seconds cannot complete recovery inside this budget; normal initial-login settling still works. Default 15-second settling is the tested recovery target.
- The fresh-poll-gap rule applies to recovery, not to ordinary legacy settling. Ordinary gate semantics and later world/loading-screen limitations remain unchanged.
- The legacy aggregate DB reader's SQL casts, wall-clock acceptance and cross-account aggregate semantics are not redesigned here. It provides no detailed failure taxonomy. No live DB health or actual transition provenance was established.
- Main was never executed, even with mocked inputs. Its integration wiring is statically checked; one-poll publication/removal is tested with IO mocks. No real atomic-write/unlink behavior or native lease-expiry enforcement was exercised. Wire-format expiry is tested, not claimed as fresh native acceptance.
- Read-around identity/challenge checks reduce races, but cannot provide an atomic process/DB snapshot. Existing host-side exact-binding, challenge, policy and expiry validation remain required and are not changed.
- The two-file `recovery.patch` targets `adapters/wuwa_native/wuwa_lease_publisher.py` and `adapters/wuwa_native/tests/source_checks.py` for a later separately authorized integration. Check the pinned source hashes first. The regression harness stays isolated in this review rather than being installed into Main tests.

## Artifact paths

All paths below are relative to `reviews/wuwa-publisher-recovery/`:

| Path | Purpose |
|---|---|
| `REVIEW.md` | Findings, bounded rules, verification and limitations |
| `recovery.patch` | Undeployed two-file unified patch |
| `proposal/wuwa_lease_publisher.py` | Complete candidate publisher, never run as main |
| `proposal/source_checks.py` | Candidate source-check adjustment |
| `tests/test_recovery.py` | CPU-only regression harness and IO tripwires |
| `test.log` | Test output |
| `verification.log` | Original hashes and patch dry-run output |
| `SOURCE_SHA256SUMS` | Original source preconditions |
| `SHA256SUMS` | Artifact checksums |
| `baseline/wuwa_lease_publisher.py` | Unmodified publisher snapshot |
| `baseline/wuwa_phase_gate.py` | Unmodified imported legacy snapshot |
| `baseline/test_publisher.py` | Unmodified existing publisher tests |
| `baseline/test_wuwa_phase_gate.py` | Unmodified legacy tests (state-only subset executed) |
| `baseline/source_checks.py` | Unmodified existing source checks |
