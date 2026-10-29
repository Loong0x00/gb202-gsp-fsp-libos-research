# CPU-only loader hardening and startup attribution review

## Verdict and non-claim

This is an independent hardening candidate based on the exact CURRENT
`native/` pc3b source snapshot. It preserves the prior 13-target submission/
completion-proof work, including the current `verified_effective_passes` helper
that makes a pending/unproved request publish effective count zero.

The retained REDEngine dump proves that the observed stall followed the game's
crash-report suspension path, but it does not contain the initiating fault. This
patch **does not claim to fix, explain, or attribute that crash**. It removes a
separate genuine unsafe surface: unlocked whole-process module enumeration,
unbounded PE traversal, unload-prone raw module handles, and one global
predecessor shared across unrelated IAT slots.

## Loader design

- `K32EnumProcessModules` and the repeated whole-process scan are removed.
- Outside `DllMain`, the worker uses reference-taking `GetModuleHandleExW` plus
  basename/handle revalidation for exact targets only.
- The current CP executable alone targets its statically observed
  `sl.interposer.dll!D3D12CreateDevice` IAT. The actual `_nvngx.dll` alone
  targets `KERNEL32.dll!GetProcAddress`.
- A private loaded-image PE32+ helper bounds DOS/NT/optional headers, import
  directory, descriptors, lookup/IAT thunks, and names against `SizeOfImage`.
  `OriginalFirstThunk == 0` on the matching descriptor fails closed; resolved
  IAT pointers are never interpreted as import-name RVAs.
- CP device and NGX core each own a `PatchState`, predecessor, and wrapper. No
  arbitrary module can inherit a global-first predecessor.
- `InterlockedCompareExchangePointer` publishes the predecessor before the slot
  CAS can expose the wrapper. The IAT CAS accepts only the exact observed value.
  Already installed is a no-write result; CAS mismatch, a competitor already in
  the slot, or any slot changed after this host installed its wrapper is a
  logged conflict and is not overwritten.
- PE parsing occurs while a normal module reference is held. Temporary refs are
  released. One normal (not `PIN`) reference to the successfully patched NGX
  core generation is intentionally retained, preventing unload/reload ABA of
  its recorded slot and predecessor. No arbitrary module is pinned.
- `VirtualProtect`/CAS/restore is under a small private SRW lock. It performs no
  allocation, file I/O, module-name lookup, COM, or `OutputDebugString`; result
  logging occurs after lock release and only on outcome transitions.
- The six owned DXGI exports still forward only to the actual system32 DXGI.
  After each of the three real factory exports succeeds, the proxy invokes one
  additive owned-host observer outside `DllMain`; observer failure cannot alter
  the original HRESULT, arguments, returned interface, or output identity.
  Signed SR/RR routing and the one-chain pipeline are unchanged.

The polling interval remains 2 ms until the exact core hook is installed and
250 ms afterward, but timing is not presented as a crash fix. Polling now only
acquires named exact targets and does bounded work; it never walks the PEB/module
list directly or through PSAPI.

## Exact-target evidence and WuWa/HSR boundary

`IMPORT_EVIDENCE.md` records exact local paths, hashes, and matching import
records without retaining large dumps:

- Current CP main EXE has `sl.interposer.dll!D3D12CreateDevice` at IAT RVA
  `0x2a8e570`, with nonzero `OriginalFirstThunk`.
- The configured WuWa executable is actually `Client-Win64-Shipping.exe`; the
  requested `WuwaClient-Win64-Shipping.exe` name is absent. The configured EXE
  has no regular or delay `D3D12CreateDevice` import. Its adjacent Base DLL also
  has no such import. Main-EXE factory coverage is therefore not proven.
- The actual `_nvngx.dll` mapped in retained CP runs imports
  `KERNEL32.dll!GetProcAddress` at IAT RVA `0x114340`, with nonzero
  `OriginalFirstThunk`.

Accordingly, this patch contains no fabricated WuWa IAT target and no global
fallback. It now adds a separate route rooted only in factories actually
returned by the three exports of the owned DXGI proxy. The host QIs known
factory revisions, patches the SDK-verified base and Factory2 `CreateSwapChain*`
slots, and best-effort observes a supplied D3D12 command queue and its real
device through the existing hooks before exactly-once original forwarding.
D3D11 queue QI failure is a no-op. For WuWa the required scope statement is:
**queue-at-swapchain route implemented but UNVALIDATED**. Main must cold-test the
actual caller route and first-SR timing; code shape is not proof that WuWa uses
this proxy path. HSR needs no main-EXE factory hook because its adapter owns
D3D12 dynamic device creation and delayed queue setup after native submit/device
tracking.

## Owned factory observation

The proxy resolves `DLSS5_NativeHostObserveFactoryV1` only from the adjacent
owned host loaded by its existing outside-`DllMain` initializer. It calls the
observer only after a successful real `CreateDXGIFactory`,
`CreateDXGIFactory1`, or `CreateDXGIFactory2` return with a non-null output.
The output remains opaque; the host invokes its always-valid COM
`QueryInterface` entrypoint for `IDXGIFactory2`, `IDXGIFactory1`, and
`IDXGIFactory`, allowing a newer requested interface (including Factory7)
without assuming its concrete C++ type and retaining base fallback when
Factory2 is unavailable.

MinGW-w64 SDK C-vtable `offsetof` and function-type assertions verify:

- `IDXGIFactory::CreateSwapChain`: slot 10;
- `IDXGIFactory2::CreateSwapChainForHwnd`: slot 15;
- `IDXGIFactory2::CreateSwapChainForCoreWindow`: slot 16;
- `IDXGIFactory2::CreateSwapChainForComposition`: slot 24.

Each known interface vtable has independent original pointers and exact slot
CAS. Predecessors are published before wrappers, duplicate observations are
idempotent, and a concurrent actor is never overwritten. One reference from the
successful factory QI is retained per patched vtable for record/vtable lifetime;
no object is released or otherwise called while the private factory patch lock
is held. Swapchain wrappers QI `pDevice` for `ID3D12CommandQueue`, call
`GetDevice`, then reuse `hook_device` and `hook_command_queue` before forwarding
the original method exactly once. Observation is advisory: every failure still
forwards and cannot force a factory or game failure. No fourth DLL, ReShade,
private unwrap, protected-executable hook, dynamic game `GetProcAddress` guess,
or whole-process scan is introduced.

## Minimal startup instrumentation

The three Windows workers call `SetThreadDescription` with stable names:

- `d5h-loader`
- `d5h-telemetry`
- `d5r-retire`

`CreateThread` output TIDs are retained atomically, and each worker also records
its own TID at entry. Existing bounded status output gains optional
`worker_tids`, `worker_loops`, `loader_phase`, `loader_last_result`, and
`telemetry_phase` fields. Runtime query reserved words 0/1 carry retire TID and
loop count without changing `D5rQueryV1` size or public signatures.

Loader phases are: 1 exact main acquisition, 2 CP parse/CAS, 3 core acquisition,
4 core parse/CAS, 5 pass complete, 6 wait, 7 stopped. Telemetry phases are:
1 control, 2 completion query, 3 status/capability output, 4 wait, 5 stopped.
`loader_last_result` packs target ID (1 CP, 2 core) in the high 16 bits and a
bounded import/patch result in the low bits. These fields and thread names make a
future dump attributable; they do not infer the initiating crash.

No render/queue callback gains file I/O, heap work, debug output, waits, or new
telemetry locks. No multi-megabyte startup journal is introduced. Main separately
owns ReportQueue retention.

## Queue-hooks scope decision

Factory QI/GetDevice/Release calls are all outside the new private factory patch
lock. The existing broader COM-under-`g_lock` risk in `queue_hooks.cpp` remains
real and is not expanded or claimed fixed here; moving its fence creation/signal
path safely requires separate lifetime/rollback design. This unchanged risk is
not evidence for the REDEngine initiating fault.

## Patch contents and prior 13-target superset

`loader-hardening.patch` applies additively to CURRENT pc3b. The buildable
isolated result is under `tree/`. It changes 11 existing files and adds 6
private/additive files:

```text
native/Makefile
native/README.md
native/boot/dxgi_proxy.cpp
native/docs/ARCHITECTURE.md
native/docs/HANDOFF.md
native/host/factory_hook_core.h                (new)
native/host/factory_hooks.cpp                  (new)
native/host/host_internal.h
native/host/host_state.cpp
native/host/loader.cpp
native/host/loader_hardening.h                 (new)
native/host/telemetry.cpp
native/runtime/pipeline.cpp
native/tests/dxgi_vtable_layout_test.cpp       (new)
native/tests/factory_hooks_test.cpp            (new)
native/tests/loader_hardening_test.cpp         (new)
native/tests/source_checks.py
```

The isolated tree retains the complete current pc3b source, so this is a source
superset of the previous 13-target patch rather than a reversion to pc3. In
particular, `native/common/control.h`, public adapter layouts, D5LC/D5RP,
signed SR/RR chain, package signature files, adapters, and game files are
unchanged. The owned DXGI proxy changes only to perform post-success owned-host
factory notification; its six-export surface and real-system forwarding remain.

## Apply preconditions

Apply only from the project root and only if all existing-target hashes match
`source-snapshot.sha256`, all six new paths are absent, and dry-run succeeds:

```bash
sha256sum -c reviews/loader-hardening/source-snapshot.sha256
for p in native/host/loader_hardening.h \
         native/host/factory_hook_core.h native/host/factory_hooks.cpp \
         native/tests/loader_hardening_test.cpp \
         native/tests/factory_hooks_test.cpp \
         native/tests/dxgi_vtable_layout_test.cpp; do test ! -e "$p"; done
patch --dry-run -p1 < reviews/loader-hardening/loader-hardening.patch
patch -p1 < reviews/loader-hardening/loader-hardening.patch
```

`full-source-snapshot.sha256` additionally records every source input copied
from the pristine pc3b baseline, including the pending/effective-zero control
helper; `tree-source.sha256` records the final isolated result. During this
follow-up, local `native/` acquired separate WuWa/transitive-build changes from
another workstream. Per scope, none was copied into this tree or edited here;
verification reconstructed the hash-matched pc3b baseline from its pre-WuWa
backup and confirmed that this patch has no WuWa-deletion hunks. Therefore the
now-diverged main tree must be rebased manually. If any target hash differs, do
not force hunks or apply twice.

## Verification and limitations

CPU-only verification is in `verification.log`:

- clean MinGW x86-64 build of DXGI proxy, host, and runtime;
- native policy test;
- native test of the actual shared PE/CAS/reference helper: valid bounded import,
  bad import directory, bad/unterminated names, bad thunk, oversized image,
  absent `OriginalFirstThunk`, predecessor-before-hook ordering, per-target prior
  preservation, already-installed skip, post-install conflict, forced CAS
  mismatch, and reference release/retention;
- CPU fake-COM/shared-core tests for all swapchain forwards and arguments,
  unchanged output identity/HRESULT, D3D11 queue-QI passthrough, safe successful
  queue/device observation, Factory2-unsupported base fallback, duplicate
  observation, and CAS-conflict preservation;
- MinGW SDK compile-time assertions for all four vtable slots and signatures;
- source invariants and PE export checks, including the additive host observer.

No Wine, GPU, game launch, attach, process signal, or hardware test was run.
Main owns CPU/Wine/GPU integration and cold-game acceptance.

Residual limitations:

1. Page protection is still page-granular. Private serialization plus exact CAS
   prevents this host's own interleaving and stale overwrite, but cannot make an
   unrelated external patcher's `VirtualProtect` transaction cooperative.
2. Exact polling cannot patch a core before code executed under that core's own
   loader initialization. No loader-notification callback patches or loads a DLL.
   Cold integration must confirm required NGX export capture is not missed.
3. A protection-restore failure leaves an already callable hook in place because
   rollback could race a caller; it is logged, retained safely, and NGX readiness
   remains fail-closed for that degraded generation.
4. CP/WuWa/HSR binaries can update. The recorded hashes/imports are apply/test
   evidence, not perpetual signatures; changed binaries require fresh bounded
   import evidence.
5. Factory-vtable storage is intentionally bounded at 16 distinct vtables. A
   full table fails observation without changing the original factory API.
6. The queue-at-swapchain route is not proof of the actual WuWa caller route,
   first-SR timing, or game compatibility. It remains UNVALIDATED until main
   performs cold tests.
7. The original REDEngine initiating fault remains unknown.
