# Main preliminary Project bootstrap review — 2026-09-10 14:48

The finished isolated implementation is `hsr-project-bootstrap-implementation/`; it has NOT been merged/deployed or accepted as HSR NR support. Canonical final patch has 24 files, including late host pipeline/telemetry identity propagation. Preserve concurrent Main NVX/FLOAT34 changes during any later semantic rebase.

Positive: distinct pointer-free typed identity, private Core argument order, numeric CP/WuWa path unchanged by design, exact Core/NR file/RVA pins, same-owned-device/fresh-call/Core+NR success proof, no invented numeric application ID, no automatic gate opening or unproven direct-init fallback.

## Blocking review findings

1. `native/runtime/interop.cpp::initialize_project_core` currently installs the Core GetProcAddress hook before publishing `g_core_get_proc_previous`. A concurrent Core resolver call can enter the replacement in this window and receive nullptr rather than the original result. This is not acceptable pass-through behavior.
2. Shared import patch/restore code uses plain slot stores and unchecked protection restoration. Restoration can overwrite a newer hook. Needs RO-safe atomic loads, checked writable transition, compare/exchange ownership, predecessor-before-publication, and checked protection restoration.
3. Core can cache the returned NR initializer wrapper after the temporary resolver scope ends. Original-function and module/self lifetime must remain valid for these later pass-through calls, including failed bootstrap/unhook paths.

An isolated CPU-only hardening worker is handling these findings in `hsr-project-bootstrap-hardening/`. Its captured source may precede the final host pipeline/telemetry additions; integrate hardening against the canonical final 24-file patch, not by copying its whole tree.

Even after hardening, real Core binding of exact e16 NR within its 0..17 internal loop remains unproven. Missing/cached resolution must remain incompatible. CPU/fake success cannot establish native NR bootstrap, actual guide usage, or delivered game output.

No Main native source/binary change was made by this review. WuWa physical testing continues on its separately frozen existing package.

## 15:05 Main integration update

Canonical final implementation + nine-file hardening were semantically rebased
against Main NVX/FLOAT34. 27 paths merged, with only the router Makefile dependency
union requiring manual resolution. Both observer paths and FLOAT34 contract were
retained; HSR source manifests use the union of both branches. Backup pointer:
`HSR_PROJECT_MAIN_BACKUP`; rebase receipts: `HSR_PROJECT_MAIN_REBASE`.

Main `native cpu-check all`, HSR `all test check` pass, including 100 forced IAT
publication races, existing factory/loader/commit policies, CS302 and NVX52
checks. Candidate router SHA256:
`e34c04a66d0c65255fcf0cde54ad01cc58244b1fbb5dac4daa6fbc88258acf62`.
This resolves the above source-review blockers, not the unproven Core-to-NR GPU
binding. No game/Wine/GPU deployment of this merged version has occurred.

`native/package` was deliberately not regenerated; development-source preflight
now blocks it. Fixed CP release and the independently frozen GPU-tested WuWa
POST2 bundle remain unchanged. See `NATIVE_DEVELOPMENT_UNVERIFIED.md`.
