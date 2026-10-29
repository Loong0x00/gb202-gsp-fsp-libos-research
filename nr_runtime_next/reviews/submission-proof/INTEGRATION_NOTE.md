# Concurrent integration note

The isolated review tree and unified diff were completed and verified against the pre-patch hashes in `source-snapshot.sha256`.

At the final 2026-09-10 07:09 +08:00 observation, another worker/process had replaced all 13 `native/` patch targets with byte-for-byte copies of the reviewed patched tree. This worker did not write `native/` and did not revert that concurrent integration.

Consequences:

- `sha256sum -c reviews/submission-proof/source-snapshot.sha256` now fails because those are intentionally the **pre-patch** hashes.
- `patch --dry-run -p1 < reviews/submission-proof/submission-proof.patch` now reports a reversed/already-applied patch.
- The integration can be checked without writing anything:

```bash
while read -r path; do
  cmp -s "$path" "reviews/submission-proof/tree/$path" || echo "DIFF $path"
done <<'PATHS'
native/include/native_runtime.h
native/runtime/pipeline.cpp
native/host/host_internal.h
native/host/host_state.cpp
native/host/pipeline.cpp
native/host/queue_hooks.cpp
native/host/telemetry.cpp
native/tests/policy_test.cpp
native/tests/source_checks.py
native/docs/ARCHITECTURE.md
native/docs/ADAPTER_ABI.md
native/docs/HANDOFF.md
native/README.md
PATHS
```

At note creation this check emitted no differences. Main should inspect ownership/timing and must not apply the patch a second time.
