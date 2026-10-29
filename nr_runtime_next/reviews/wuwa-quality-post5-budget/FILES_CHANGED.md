# Files created

All paths are relative to the project working directory; no files outside this review were edited.

- `reviews/wuwa-quality-post5-budget/ARTIFACTS_SHA256SUMS` — Review delivery SHA256 inventory (excludes itself).
- `reviews/wuwa-quality-post5-budget/AUDIT_INPUTS.json` — Pinned frozen source/binary and run-findings hashes.
- `reviews/wuwa-quality-post5-budget/CALIBRATION_PLAN.md` — Proposed owned Quality-versus-Ultra POST5 GPU measurement plan; not executed.
- `reviews/wuwa-quality-post5-budget/FILES_CHANGED.md` — Exact inventory of all created review files.
- `reviews/wuwa-quality-post5-budget/REPORT.md` — Frozen-source audit, evidence limits, diagnostic schema and handoff.
- `reviews/wuwa-quality-post5-budget/build/adapter_commit_policy_test` — Linux CPU test executable; executed without GPU APIs.
- `reviews/wuwa-quality-post5-budget/build/bridge.o` — Cross-compilation intermediate; not executed.
- `reviews/wuwa-quality-post5-budget/build/budget_diagnostics_fixture.exe` — MinGW CPU policy fixture; NOT EXECUTED.
- `reviews/wuwa-quality-post5-budget/build/budget_diagnostics_sanitized` — Linux CPU test executable; executed without GPU APIs.
- `reviews/wuwa-quality-post5-budget/build/budget_diagnostics_test` — Linux CPU test executable; executed without GPU APIs.
- `reviews/wuwa-quality-post5-budget/build/dlss5-native-host-diagnostics-review.dll` — Fully cross-linked review host DLL; NOT EXECUTED/INSTALLED.
- `reviews/wuwa-quality-post5-budget/build/export-comparison.json` — Eight unchanged native-host export names.
- `reviews/wuwa-quality-post5-budget/build/factory_hooks_test` — Linux CPU test executable; executed without GPU APIs.
- `reviews/wuwa-quality-post5-budget/build/fixtures-sanitized.jsonl` — Identical receipts from ASan/UBSan CPU run.
- `reviews/wuwa-quality-post5-budget/build/fixtures.jsonl` — Synthetic CPU fixture receipts, not live GPU telemetry.
- `reviews/wuwa-quality-post5-budget/build/format_plan.o` — Cross-compilation intermediate; not executed.
- `reviews/wuwa-quality-post5-budget/build/loader_hardening_test` — Linux CPU test executable; executed without GPU APIs.
- `reviews/wuwa-quality-post5-budget/build/policy_test` — Linux CPU test executable; executed without GPU APIs.
- `reviews/wuwa-quality-post5-budget/build/test_format_plan` — Linux CPU test executable; executed without GPU APIs.
- `reviews/wuwa-quality-post5-budget/build/verification.log` — Final successful CPU-only verification log.
- `reviews/wuwa-quality-post5-budget/build/wuwa_ingress.o` — Cross-compilation intermediate; not executed.
- `reviews/wuwa-quality-post5-budget/candidate/native/Makefile` — Candidate header dependency only.
- `reviews/wuwa-quality-post5-budget/candidate/native/host/wuwa_budget_diagnostics.h` — Private bounded receipt recorder and serializer.
- `reviews/wuwa-quality-post5-budget/candidate/native/host/wuwa_ingress.cpp` — Instrumented copy of frozen ingress; no admission-policy change.
- `reviews/wuwa-quality-post5-budget/diagnostics.patch` — Apply-to-frozen-source diagnostics-only patch; not applied to main/frozen tree.
- `reviews/wuwa-quality-post5-budget/prepare_candidate.py` — Regenerates review candidate and unified patch from frozen source.
- `reviews/wuwa-quality-post5-budget/tests/budget_diagnostics_test.cpp` — Synthetic resize/hotrebuild/refusal/format/bounds policy fixtures.
- `reviews/wuwa-quality-post5-budget/tests/check_receipts.py` — Receipt equations, source assumptions and export-name checks.
- `reviews/wuwa-quality-post5-budget/verify.sh` — Review-scoped CPU verification and Windows cross-compilation commands.
