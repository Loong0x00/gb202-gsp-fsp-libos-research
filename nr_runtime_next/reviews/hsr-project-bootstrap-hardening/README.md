# HSR Project bootstrap hardening — CPU-only review copy

Base: finished `../hsr-project-bootstrap-implementation/project/`. That tree and Main were not edited.

- **Patch:** `patches/owned-project-core-observer.patch` (apply with `-p1` at implementation-tree root, only when separately authorized).
- **Candidate:** `project/`; exact source changes in `CHANGED_FILES.txt`.
- **Review:** `REVIEW.md`.
- **Executed tests/results:** `VERIFICATION.md`, `logs/`.
- **Checks:** `verify_cpu.py`, source manifests, `SHA256SUMS`.

Includes one-shot owned Core/NR IAT RAII, RO-safe atomic sampling/CAS, predecessor-before-visibility publication, checked fail-closed cleanup, exact existing-hook chaining, resident cached-callback lifetime, typed identity fixes, and native CPU race/failure tests. Normal numeric CP/WuWa initialization and frozen public ABIs are preserved.

**No GPU/Wine/game execution or deployment. Core binding to NR remains unproven. Not GPU/game approval.**
