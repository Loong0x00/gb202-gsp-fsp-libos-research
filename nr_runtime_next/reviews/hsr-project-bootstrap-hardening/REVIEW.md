# CPU-only Main review: owned Project/Core observer

## Disposition

The reported Core resolver publication, ownership, restore-result, and callback-lifetime defects are addressed in this **review copy only**. Source patch: `patches/owned-project-core-observer.patch`, relative to `reviews/hsr-project-bootstrap-implementation/project/` (`patch -p1`). A disposable apply test byte-matched the candidate source tree. The implementation's existing 136-entry source manifest still verifies.

**Not GPU/game approval. Core binding to NR remains unproven.** No Wine, game, GPU harness, deployment, prefix, host protection-policy, or network operation was performed. Native tests only change permissions on their own anonymous test page. Windows protection calls below are source code, cross-compiled but not executed here.

## Blocking defects addressed

| Finding | Hardening |
|---|---|
| Core IAT visible before `g_core_get_proc_previous` publication | Shared `owned_iat::Observer` claims a one-shot state, samples the exact chain head with a non-writing acquire load, retains callback modules, publishes the predecessor with release ordering, then performs one expected-value install CAS. No retry over a different predecessor. |
| Plain removal can overwrite a newer hook | Removal CAS expects only our replacement. Ownership collision rejects bootstrap proof and does not replace the newer pointer. Exact predecessor is never cleared or rebound. |
| Protection restore failure ignored | Every protection restore is checked, including install collision and rollback paths. A failed initial restore triggers one bounded rollback; that failure remains sticky even if rollback succeeds. Unhook failure makes proof false. Original protection is retained across failed-install rollback; a normal unhook restores the protection it itself observed. |
| Core/newer hook can cache resolver or returned NR wrapper | Self, exact Core, exact NR, and exact predecessor's module are checked/pinned before hook visibility. Immutable atomic NR dispatch survives scope destruction. Temporary references cover module validation/export lookup. Pins intentionally last until process exit; draining current callers or restoring one IAT cannot establish that cached pointers are gone. |
| Project path also used unsafe NR `GetModuleFileNameW` patch before exact validation | Project path now uses a second owned observer after exact validation, with its own resident predecessor. Its cleanup must also succeed for proof. Numeric path retains the original patch implementation. Unrelated/invalid-argument filename calls forward to the sampled predecessor. |
| Typed HSR Project initializer pointer was rewritten/read nonatomically | Atomic, compare-exchange-once target; each call takes one acquire snapshot and forwards exactly once. A different target or module-retention failure blocks Project capture while returning the original resolver result. Self/original modules retained before returning the typed wrapper. |
| Failed identity/backend could hit `b.compatible` fast path first | Poisoned state rejected before compatibility reuse. Normal numeric Init arguments/logic are unchanged; reuse of an already-failed backend is deliberately rejected. |
| Query read bootstrap fields under the wrong mutex and could advertise poisoned Project proof | Backend fields now read under `b.lock`; failed backend/identity suppresses compatible/Project flags. Query already holds `g_lock`; initialization releases `b.lock` before Execute acquires `g_lock`, and registration does not acquire `g_lock`. |
| Observer path directly dereferenced incoming path/PE metadata | Fault-safe bounded path reads; exact-module PE reads checked against allocation ownership, with bounded descriptors/thunks/names, unique aligned KERNEL32 import, no FirstThunk name fallback. Inaccessible/malformed/ambiguous imports fail closed. |

## Ownership/lifetime contract

- Only exact retained Core `KERNEL32!GetProcAddress` and exact retained NR `KERNEL32!GetModuleFileNameW` are targeted. No process-wide hook or module scan. PE work is bounded to a 128 MiB declared image, 512 descriptors, 65,536 total matching-module thunks, 256-byte names.
- Windows slot load is `__atomic_load_n(..., __ATOMIC_ACQUIRE)` on aligned x64 pointers, with a lock-free static assertion. CAS is `InterlockedCompareExchangePointer`, only after successful write-enable. No CMPXCHG-as-read on RO memory and no instruction modification requiring an instruction-cache flush.
- An existing HSR Core GetProc hook remains the exact predecessor, not replaced by a guessed kernel export. A callback racing installation, arriving on another thread, or arriving after unhook still calls that predecessor. The direct OS fallback is defensive; no legitimately exposed observer can reach it with a missing predecessor.
- NR wrapper targets are set before hook exposure, not lazily rewritten by the resolver. Returned wrappers call the exact signed-NR initializer even after observation ends. Stack evidence/backend device matching is accessed only through the owning thread's live RAII scope.
- One owned installation attempt per resident state. There is no reinstall, retry-under-new-owner, or clearing of cached callback state. Temporary references are released; pins may remain even on partial setup failure. This bounded retention is intentional, not an unload/drain claim.
- Failed removal can leave our resolver in the IAT (or chained behind a newer hook). It remains forwarding-only after scope exit. Failed protection restore can leave the page writable. Neither outcome is called successful cleanup or accepted bootstrap evidence; no direct NR fallback is attempted.
- CAS protects the observed pointer transaction, not arbitrary noncooperative writes or an external ABA that restores the identical pointer. A later hook owns its own code lifetime. No attempt is made to repair another hook's implementation or force its removal.

## Typed identity review coverage

Reviewed `native/include/native_adapter.h`, `native/include/native_runtime.h`, `native/common/project_identity.h`, `adapters/common/native_contract_bridge.{h,cpp}`, HSR staging/publication/attach in `router.cpp`, host attach in `host_state.cpp`, runtime registration/query in `pipeline.cpp`, bootstrap/NR observation in `interop.cpp`, and `project_bootstrap_policy.h` with existing identity tests.

Retained: discriminated optional Project APIs, inline canonical deep copies, bounded ASCII/UTF-16 validation, synchronized fail-sticky stores, no decimal Project-to-appId/CMS conversion, publication only after successful exactly-once original Project Init, mutually exclusive numeric/Project identity, null optional FeatureCommonInfo (no borrowed nested pointers), exact SHA/RVA checks, fresh synchronous resolver evidence, exact owned Vulkan handles/path/SDK, exactly one observed successful NR original call, and no guessed-CMS/direct-init fallback. Public identity and frame/control/protocol headers are byte-identical to the implementation tree.

No further blocking defect was found in that reviewed typed flow under its documented synchronous/trusted in-process API contract. This is not a claim that all pre-existing router/native hooks are hardened: the old numeric NR filename patch and legacy HSR/router patch primitive remain outside this change, as do unrelated numeric/SR callback globals. The observer rejects ownership loss rather than assuming those external hooks cooperate. Unknown import variants, inaccessible metadata, asynchronous-only Core bootstrap, cached-only resolver paths, or unexpected exports are rejected, not guessed.

## Executable verification

See `VERIFICATION.md`. The Linux fake Core resolves and calls fake NR through an actual RO-page IAT using the **same production Observer/ThreadScope/parser** templates. Fake ABI callbacks exercise forwarding/retention and proof behavior; they are not merely boolean-policy inputs. Windows API operations/module pinning are modeled by checked injectable operations and cross-compiled in the real runtime, not executed on Windows here. ASan/UBSan and TSan runs passed.

Remaining uncertainty: actual private Core behavior, real loaded import layout, cached-pointer use by the signed binaries, Windows VirtualProtect/GetModuleHandleEx failure behavior, and any NR/GPU/game outcome require separate authorized evidence. File hashes/RVAs are existing version gates, not a new loaded-image integrity attestation. No bootstrap, binding, evaluation, or completed-frame production success is claimed.
