# Scoped changes

All files are under the new clone `/home/user/rt_5090_project/nr_runtime_next/reviews/cinematic-layer-capture-runtime`; copied baseline files are otherwise unchanged (build/package excluded). Exact edited/added source paths:

- `/home/user/rt_5090_project/nr_runtime_next/reviews/cinematic-layer-capture-runtime/native/Makefile` — capture build dependencies and CPU-only check target.
- `/home/user/rt_5090_project/nr_runtime_next/reviews/cinematic-layer-capture-runtime/native/common/capture_policy.h` — portable bounds/budget/retirement/quarantine/two-attempt policy.
- `/home/user/rt_5090_project/nr_runtime_next/reviews/cinematic-layer-capture-runtime/native/runtime/pipeline.cpp` — capture insertion points, exact submission association, completion-worker drain outside render lock.
- `/home/user/rt_5090_project/nr_runtime_next/reviews/cinematic-layer-capture-runtime/native/runtime/diagnostic_capture.inc` — opt-in cold READBACK allocation, interop boundaries, stage copies, metadata, retired raw writer.
- `/home/user/rt_5090_project/nr_runtime_next/reviews/cinematic-layer-capture-runtime/native/runtime/ngx_parameters.cpp` — observational capture-only core pointer getter (slot 8).
- `/home/user/rt_5090_project/nr_runtime_next/reviews/cinematic-layer-capture-runtime/native/runtime/runtime_internal.h` — private getter declaration; no public ABI change.
- `/home/user/rt_5090_project/nr_runtime_next/reviews/cinematic-layer-capture-runtime/native/tests/capture_policy_test.cpp` — CPU lifecycle/parity/footprint models and mutation check.
- `/home/user/rt_5090_project/nr_runtime_next/reviews/cinematic-layer-capture-runtime/native/tests/capture_source_checks.py` — immutable-baseline and structural checks.

Documentation/evidence at the same clone root: `DIAGNOSTIC_CAPTURE.md`, `FILES_CHANGED.md`, `ARTIFACT_SHA256SUMS`, `CHANGED_SOURCE_SHA256SUMS`, `crossbuild.log`, `capture-tests.log`, `cpu-check.log`, `sanitizers.log`.

Generated artifact: `/home/user/rt_5090_project/nr_runtime_next/reviews/cinematic-layer-capture-runtime/native/build/dlss5-native-runtime.dll`.

`make cpu-check` also generated unchanged host/boot crossbuilds, CPU test executables, maps, and the format-bridge archive under this clone's `native/build` and `adapters/format_bridge/build`. Nothing was copied/deployed outside the clone; no signed DLL was altered or built, no Wine/GPU executable was run.
