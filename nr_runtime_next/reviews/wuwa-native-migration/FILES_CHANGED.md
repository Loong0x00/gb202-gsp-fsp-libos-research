# Exact changed files

All paths are project-relative; no files outside this review were written.

- `reviews/wuwa-native-migration/CPU_TEST_RESULTS-before-summary-refresh.txt` — Retained fail-closed test result when Main changed the summary hash.
- `reviews/wuwa-native-migration/CPU_TEST_RESULTS.txt` — Final 27 passing CPU tests, including per-step failure/crash loops.
- `reviews/wuwa-native-migration/FILES_CHANGED.md` — Exact review-only file inventory (this file).
- `reviews/wuwa-native-migration/REVIEW.md` — Decision, exact scope, launch/publisher audit, transaction and UI integration contract, blockers.
- `reviews/wuwa-native-migration/SHA256SUMS` — SHA256 inventory of review artifacts (excluding itself).
- `reviews/wuwa-native-migration/audit/legacy-desktop-launch.sh` — Read-only snapshot of original legacy desktop wrapper; do not execute.
- `reviews/wuwa-native-migration/audit/legacy-phase-gate.service` — Read-only snapshot of legacy user service; not installed.
- `reviews/wuwa-native-migration/audit/observed-steam-route.txt` — Single historical WuWa process-log launch command, no account config.
- `reviews/wuwa-native-migration/audit/steam-graphics-wrapper.sh` — Read-only snapshot of original Steam graphics wrapper; do not execute.
- `reviews/wuwa-native-migration/candidate-release.json` — Unaccepted candidate publisher/dependency hashes and non-executable service template.
- `reviews/wuwa-native-migration/evidence-drift-review.json` — Explicit review of Main adding its no-visual-observation caveat.
- `reviews/wuwa-native-migration/evidence-report.json` — Verified static observations and honest verificationScope.
- `reviews/wuwa-native-migration/input-lock.json` — Pinned frozen inputs and audited external source hashes.
- `reviews/wuwa-native-migration/legacy-wrapper-refusal.patch` — Unmerged early legacy-wrapper refusal guards; not a native launch route.
- `reviews/wuwa-native-migration/production-plan.json` — Read-only production preview: valid evidence, migration blocked.
- `reviews/wuwa-native-migration/proposal/evidence.py` — Read-only hash/semantic verifier; never imports live publisher/core.
- `reviews/wuwa-native-migration/proposal/guarded-legacy-desktop-launch.sh` — Candidate refusal guard, syntax-tested only; do not execute.
- `reviews/wuwa-native-migration/proposal/guarded-steam-graphics-wrapper.sh` — Candidate refusal guard, syntax-tested only; do not execute.
- `reviews/wuwa-native-migration/proposal/publisher_candidate.py` — New-hash, unaccepted verified-byte reader loader candidate; never run as main.
- `reviews/wuwa-native-migration/proposal/ui_contract.py` — Data-driven target/ack API and generation-bound preview/rollback flow.
- `reviews/wuwa-native-migration/proposal/wuwa.py` — Production-blocked API plus sandbox-only transactional implementation.
- `reviews/wuwa-native-migration/publisher-dependency.patch` — Unmerged immutable-reader loading candidate, based on publisher freeze.
- `reviews/wuwa-native-migration/tests/test_review.py` — CPU evidence/transaction/crash/dependency/UI fixture tests; no real services/DB.
- `reviews/wuwa-native-migration/verification.log` — AST, shell syntax, isolated patch dry-runs and original hash-preservation checks.
