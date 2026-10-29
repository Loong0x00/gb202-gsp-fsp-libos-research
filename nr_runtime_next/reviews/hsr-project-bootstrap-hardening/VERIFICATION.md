# CPU-only verification

All commands were run against `reviews/hsr-project-bootstrap-hardening/`. Nothing was deployed or launched through Wine.

## Passed

| Check | Evidence |
|---|---|
| Fresh MinGW production/runtime/host build, frozen layout objects, fake private Core ABI DLL/caller cross-compile; native policy/identity/ownership/loader/factory tests | `logs/native-cpu-check.log` (`make -B -C project/native cpu-check`), final incremental pass in `logs/native-cpu-check-final.log` |
| Fresh HSR candidate and helper build; 59 logic checks, vtable policy, 302 binding-observer checks, unchanged 68-export surface and checked manifests | `logs/hsr-check-final.log` (`make -B -C project/adapters/hsr_native check`) |
| Existing exact digest/RVA/private ABI/identity checks plus new observer wiring, byte-identical headers/protocol/identity contract, exact numeric init block, unchanged PE export sets | `logs/identity-pe-check.log` (`python3 verify_cpu.py`) |
| New executable ownership harness under AddressSanitizer + UndefinedBehaviorSanitizer | `logs/observer-sanitizers.log` |
| Same harness under ThreadSanitizer | `logs/observer-tsan.log` |
| Original implementation's 136 source hashes remain unchanged | `logs/base-unchanged.log` |
| Patch dry run, actual apply to disposable source copy, complete byte comparison to candidate | `logs/patch-check.log` |

No compiler warnings/errors were found in final native/HSR build logs. An initial HSR source check correctly rejected the inherited stale router manifest; the two review-copy HSR manifests were refreshed after rebuilding, then the final forced build/check passed. That initial result is retained as `logs/hsr-first-stale-manifest.log`.

## New executed fake Core/NR harness

`project/native/tests/owned_iat_observer_test.cpp` uses production `owned_iat::Observer`, `ThreadScope`, bounded import parser, and bootstrap proof predicate. Its anonymous IAT page really starts read-only (`mmap`/`mprotect`); sampling it does not perform a write. Its injectable platform operations use actual atomic slot load/CAS and real page permission changes, plus deterministic failure injection. Resolver/NR ABI callbacks and module-retention handles are CPU fakes; Win32 module pinning itself is not executed.

Coverage:

- 100 latch-forced races: a separate thread calls the newly visible IAT resolver *inside* the installation CAS operation, before the installer returns. It must forward through the existing HSR chain, never return null, and see published module/NR/predecessor state.
- Fake Core resolves and calls fake NR on the owning thread; another thread calls the cached wrapper while the scope is live without changing owner evidence.
- Cached NR and actual sampled resolver pointers called on a different thread after scope/observer destruction and normal module-reference release. Retained handles remain alive; exact original success/failure results are preserved.
- Fresh successful evidence is accepted only after checked cleanup. Older/nonowned scopes and other threads cannot manufacture evidence.
- Concurrent competing owner rejected before touching the slot; second installation rejected after successful unhook; preexisting identical replacement is not treated as owned.
- Install CAS collision, module preparation failure, write-enable failure, transient/permanent initial restore failure, collision plus restore failure, rollback write-enable failure, unhook write-enable failure, unhook restore failure, and newer-hook removal collision.
- Rollback uses the saved pre-install protection even when the current page was left writable. Repeated `close()`/destruction does not spin/retry or steal ownership. When cleanup fails, proof rejects while the original resolver/NR still forwards.
- Exception unwinding restores TLS scope and owned IAT.
- Synthetic PE success and rejection for absent OriginalFirstThunk, ordinal/nonmatching import, out-of-bounds or unaligned IAT, duplicate match, invalid NT offset, missing descriptor terminator, and inaccessible/truncated names.

## Reproduce (from this directory)

```sh
make -C project/native cpu-check
make -C project/adapters/hsr_native check
python3 verify_cpu.py

g++ -std=c++20 -O1 -g -pthread -fsanitize=address,undefined \
  -fno-omit-frame-pointer project/native/tests/owned_iat_observer_test.cpp \
  -o project/native/build/owned_iat_observer_sanitized
project/native/build/owned_iat_observer_sanitized

g++ -std=c++20 -O1 -g -pthread -fsanitize=thread \
  project/native/tests/owned_iat_observer_test.cpp \
  -o project/native/build/owned_iat_observer_tsan
project/native/build/owned_iat_observer_tsan
```

Do **not** use `native make check/package`: those unrelated targets include a Wine harness. HSR `check` above is CPU-only. Build output hashes are recorded in `logs/BUILD_SHA256SUMS`; source/patch inventory is recorded separately.

## Not established

The executable Linux fake is not execution of signed Core, signed NR, or the Win32 adapter. The private Windows Core ABI harness is cross-compiled only. Actual Core-to-NR binding, Win32 protection/pinning behavior, game initialization, Vulkan work, GPU evaluation, and completed-frame production proof remain unproven. No approval for deployment, GPU, or game use follows from these checks.
