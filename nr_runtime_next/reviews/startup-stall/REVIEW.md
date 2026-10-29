# CP native startup stall review

## Verdict

The **suspension mechanism is identified, but the initiating fault is not**.

This was not a normal idle, shader-compiler teardown, GPU wait, or NR execution stall. Cyberpunk entered its REDEngine crash-report path at about 06:27:12. That path suspends the game's Windows threads; the out-of-process `REDEngineErrorReporter.exe` then suspends them again while taking a minidump. The native NVIDIA/CUDA helper pthreads are not Wine Windows threads, so their remaining alive is expected.

The retained dump has no `ExceptionStream` and captures the reporting thread after it had reached an IPC wait. It therefore does **not** identify the original exception/assertion or its instruction pointer. In particular, it cannot prove that the native host, Streamline, Steam, NGX, Wine, or the game caused the crash.

No production behavior change is justified from this one event. There is, however, a real independent race surface in `native/host/loader.cpp` that should be instrumented and, if implicated, removed rather than merely slowed down.

## Decisive additional artifact

A crash dump matching this run remained in the prefix:

- Original: `/home/user/.local/share/Steam/steamapps/compatdata/1091500/pfx/drive_c/users/steamuser/AppData/Local/REDEngine/ReportQueue/Cyberpunk2077-20260910-062712-320-480/Cyberpunk2077.dmp`
- Retained copy: `reviews/startup-stall/evidence/Cyberpunk2077-20260910-062712-320-480.dmp`
- SHA-256: `82ad3ce61509e98938a4135c1fbb8e7189a736e6feb0e237ea0c9fcf18bed22f`
- Header time: `2026-09-10 06:27:14 +08:00`
- Size: 100,612 bytes

The directory's Windows PID `320` matches `runtime-status.jsonl`. The last three native heartbeats were 06:27:10.746, 06:27:11.754, and 06:27:12.764. Thus the report directory timestamp, heartbeat loss, and dump timestamp form one event.

The dump contains 57 Windows threads. Its `MINIDUMP_THREAD.SuspendCount` values are:

- 56 threads: previous suspend count 2
- Windows TID 480: previous suspend count 1

Wine's exact GE-Proton base source stores the value returned by `SuspendThread` *before* its temporary minidump suspension, obtains the context, and calls `ResumeThread` (`ValveSoftware/wine` commit `1729f00e17e879f98f9df1f2bca86bc5d21a65df`, `dlls/dbghelp/minidump.c::fetch_thread_info`). This is therefore a real nested-suspension fingerprint, not a count inferred from GDB.

The dump's main Windows thread is TID 324, named `GameThread`, with previous suspend count 2 and RIP at `bcrypt!sha256_compress.isra+0x87`. This is the same interrupted work visible below the later GDB SIGUSR1 frame. `BCryptHashData` is consequently an arbitrary suspended victim, not evidence that hashing itself stalled.

The GDB sample contains exactly 57 `usr1_handler -> wait_suspend` Wine threads plus nine native NVIDIA/CUDA threads. That exactly matches the dump's 57 Windows threads and explains why the driver helpers did not share the suspension.

Full parsed facts are in `dump-facts.json`.

## Static attribution of the suspension

### Cyberpunk crash path

The installed 2.31 `Cyberpunk2077.exe` imports `CreateToolhelp32Snapshot`, `Thread32First/Next`, `OpenThread`, `SuspendThread`, and `ResumeThread`. Static disassembly shows:

- RVA `0x29cfa08`: callback that skips its current thread (and one optional stored TID), opens the target thread with `THREAD_SUSPEND_RESUME`, and calls `SuspendThread` at RVA `0x29cfa42`.
- RVA `0x29d0024`: enumerates the current process's threads and invokes that callback.
- RVA `0x29d0498`: serializes entry into the crash path, enumerates/suspends threads, then enters crash reporting.
- Nearby strings include `!!!CRASHED!!!`, `Failed to create thread snapshot.`, and failures involving the `out of process error reporter`.

This accounts for one suspend count on all non-reporting game threads, including the native telemetry worker.

### REDEngineErrorReporter

The installed `REDEngineErrorReporter.exe` imports the same thread enumeration/suspend APIs plus `MiniDumpWriteDump`. Its disassembly shows:

- RVA `0x3d1b` onward: enumerate target-process threads.
- RVA `0x3e00` onward: call `SuspendThread` on the collected thread handles.
- RVA `0x3ee1`: load minidump flags `0x2211c1`.
- RVA `0x3f05`: call `MiniDumpWriteDump`.
- RVA `0x2ba0`: cleanup loop calling `ResumeThread`; it is invoked again on normal function exit at RVA `0x4043`.

The retained dump's header flags are exactly `0x2211c1`, strongly fingerprinting this reporter call. A late process-list sample that did not contain `REDEngineErrorReporter.exe` or the UI `CrashReporter.exe` does not exclude this short-lived helper; the dump proves that its report path ran before the late sample.

The 56-at-2 / one-at-1 distribution is consistent with the game crash path suspending all but its reporting thread and the external reporter then suspending all target threads before calling Wine DbgHelp. It does **not** show whether the reporter's later resume cleanup completed. Static code has a balanced cleanup path, while the later all-thread `wait_suspend` state indicates that at least one effective suspend remained. Without a Wine-server suspend/resume trace, assigning that imbalance to a specific caller would be speculation.

### Why this is not just a loader lock or ordinary wait

In this GE-Proton Wine base, `usr1_handler` is explicitly the SIGUSR1 handler “used to signal a thread that it got suspended”; it calls `wait_suspend`. The Wine server sends SIGUSR1 from `stop_thread` when a thread or process suspend becomes effective. Wine debugger events can also call `suspend_process`.

A loader critical-section wait by itself would not put every unrelated Windows thread under `usr1_handler -> wait_suspend`. A hook framework, debugger, crash reporter, `SuspendThread`, or `NtSuspendProcess` can do so. Here the contemporaneous REDEngine dump and the game's/reporter's static suspend paths are the direct evidence.

Microsoft Detours is capable of the same *shape* if a transaction is abandoned: official `DetourUpdateThread` calls `SuspendThread` for each enlisted non-current thread, while both commit and abort call `ResumeThread`. A dead/blocked transaction owner could therefore retain suspends, but it would normally leave its owner running. No retained call trace identifies such a transaction here, and the REDEngine dump is stronger event-specific evidence.

## Candidate assessment

| Candidate | Static/evidence result |
|---|---|
| REDEngine crash path | **Confirmed mechanism.** Matching report directory/dump, nested suspend counts, and exact thread-enumeration code. |
| Native host/runtime | No `SuspendThread`, `NtSuspendThread`, debugger, Toolhelp thread-enumeration, MinHook, or Detours imports/uses. It cannot directly create this all-Windows-thread pattern. It can still have triggered the preceding crash through an unrelated race or invalid patch. |
| Active `dxgi.dll` | Hash `328ae2...` matches the owned 106,208-byte boot proxy and retained `after-run-dxgi`; it has no suspend/thread-snapshot imports. The restored 5.6 MB ReShade DLL currently at the game path was not the active run binary. Old ReShade teardown cases are not this event. |
| Streamline | `sl.interposer.dll` and plugins were mapped. `sl.interposer.dll` has no static suspend import; `sl.common.dll` imports Toolhelp snapshot but not `SuspendThread`. Dynamic lookup or a bug in its hooking remains possible, but there is no evidence that it held all threads here. |
| Steam overlay | Mapped and statically imports `SuspendThread`/`ResumeThread`. Its visible code balances suspension around overlay/child-injection handling of individual thread handles. It remains an external hook actor, but the retained evidence does not attribute this crash or all-thread hold to it. |
| NGX | `_nvngx.dll`, SR, RR, and FG DLLs were mapped. `nvngx_dlssnr.dll` was not yet loaded. No sampled native NR evaluation occurred. Nothing retained attributes suspension to NGX. |
| Wine debugger | Wine debug events can suspend a process, but no winedbg was observed and the report path already explains the pattern. A transient debugger cannot be excluded because no pre-GDB Wine-server trace or `TracerPid` timeline was retained. The late GDB attach cannot explain the earlier heartbeat loss and dump. |
| GPU/driver | Nine native driver threads remained in normal poll/condition waits and no NR frame ran. This is not evidence of a GPU hang. |

## Native source review

### `native/host/loader.cpp`: genuine race surfaces

1. **Wine's current-process module enumeration is not a stable snapshot.** In the exact base commit, `K32EnumProcessModules`/`EnumProcessModulesEx` directly walks `PEB->LdrData->InLoadOrderModuleList` for `GetCurrentProcess()` without taking Wine's `loader_section`. The separately exported `LdrQueryProcessModuleInformation` does take that lock, but `K32EnumProcessModules` does not use it.
2. The host then releases any enumeration context, retains only raw `HMODULE` values, and dereferences DOS, NT, import-descriptor, thunk, and import-name pointers with no module pin and no image-bound checks. Concurrent unload can turn this into an access violation. Concurrent load/list mutation can make enumeration itself inconsistent.
3. The worker performs this whole-process scan every 2 ms until `ngx_hook_seen`, then still scans every 250 ms forever. Startup is exactly the period with the highest loader-list churn.
4. IAT publication uses a plain pointer store. Aligned x86-64 stores are physically atomic, but this is not a synchronized C++ publication and it does not coordinate with another hooker's patch transaction.
5. `VirtualProtect` is page-wide. Two unrelated patchers can interleave “old protection / writable / restore”, restoring the wrong final protection or faulting a writer after another actor restored RX.
6. One global `g_real_create_device` is used for every patched IAT. The first relevant IAT in this game is the executable's import of `sl.interposer!D3D12CreateDevice`; another module such as `nvapi64.dll` can have a different previous target. Later external repatching is overwritten while the host retains the first stale predecessor. This is a chaining/conflict risk, not a valid per-slot detour model.

These are plausible ways to produce an early crash, and the intermittent immediate-success retry is compatible with a race. The dump has no original exception IP, however, so none is proven to have happened in this run.

### `native/host/queue_hooks.cpp`

The fixed records and patch operations are serialized by `g_lock`. Newly published wrappers acquire the same lock before reading a record, which covers most own-publication reentrancy. There is no thread suspension.

Remaining risks are narrower:

- Direct shared-vtable stores can race an external vtable patcher.
- Failure rollback ignores a failed restore; a thread that fetched the temporary wrapper can later find no record and return `E_FAIL`/drop execution.
- `hooked_execute` holds the exclusive lock while `queue_state(..., true)` calls COM (`GetDevice`, `CreateFence`, `Release`) and while calling `queue->Signal`. Calling external/driver COM under a non-reentrant global lock is avoidable deadlock exposure.
- A single recorded predecessor per vtable assumes no later third-party replacement.

An SRW-lock problem here could block callers of these hooks, but it does not explain unrelated telemetry, RED workers, and vkd3d Windows workers all entering Wine's suspend handler. Also, this run stopped at frame 0 before any native NR submission.

## Exact next instrumentation

Do these in order; do not alter game protection or any signed NVIDIA/game DLL.

1. **Always retain REDEngine crash artifacts.** Snapshot `ReportQueue` names before launch; watch it at 100 ms or with inotify; immediately copy and hash every new directory into the run. Parse stream types, thread names, previous suspend counts, modules, exception code/address if present, and the report-stop TID.
2. **Capture transient helpers.** During the first 20 seconds, record every 50–100 ms: PID, PPID, `/proc/<pid>/stat` start time, `comm`, executable link, and command line. This will catch `REDEngineErrorReporter.exe`, `CrashReporter.exe`, or winedbg even if it exits before stall triage.
3. **Name and publish owned worker TIDs.** At the first instruction of `loader_worker`, `telemetry_worker`, and runtime `retire_worker`, call `SetThreadDescription` with stable names (`d5h-loader`, `d5h-telemetry`, `d5r-retire`). Capture the `CreateThread` output TIDs into atomics and include them in status. The current dump's stop TID 480 is unnamed, so it is impossible to determine whether the original fatal path ran on an owned worker.
4. **Add a no-allocation startup ring journal.** Use a fixed, file-backed ring with records `{QPC, sequence, tid, phase, module_base, slot, observed_pointer, result, GetLastError}`. Record start/runtime-load, enumeration begin/end and count, each target IAT compare/protect/CAS/restore, device/queue/list lock request/acquire/release, and worker loop counters. Do not use `OutputDebugString`, heap allocation, module-name lookup, or arbitrary file I/O inside a patch critical section.
5. **Get the original exception.** One focused cold reproduction should use `WINEDEBUG=+timestamp,+pid,+tid,+seh,+process,+thread,+debugstr` and bounded log retention. `+seh` is the important channel. Avoid broad `+relay`/`+snoop` against proprietary native DLLs. If necessary, use a test Wine build with one dedicated trace in wineserver `suspend_thread`, `resume_thread`, `suspend_process`, and `resume_process` handlers, logging requester PID/TID, target PID/TID, old/new counts, and debugger-event reason. That is the only exact way to identify an unmatched suspend owner.
6. **Pre-attach static triage.** On heartbeat loss, before any debugger, archive the new report directory and process timeline, then read `/proc/<pid>/status` and task status/wchan files including `TracerPid`. Only attach after these are durable.

A host-caused root should require at least one of: an SEH IP in the owned DLLs, a dump `ExceptionStream` in an owned range, a named owned stop TID plus journal phase at the fault, or a wineserver trace tied to an owned API call. `wait_suspend` alone is not that proof.

## Source references

- Exact GE-Proton10-34 Wine base: `https://github.com/ValveSoftware/wine/tree/1729f00e17e879f98f9df1f2bca86bc5d21a65df`
- Wine suspension implementation: `server/thread.c`, `server/process.c`, `server/debugger.c`, `dlls/ntdll/unix/thread.c`, and `dlls/ntdll/unix/signal_x86_64.c` at that commit.
- Wine module enumeration and dump capture: `dlls/kernelbase/debug.c`, `dlls/ntdll/loader.c`, and `dlls/dbghelp/minidump.c` at that commit.
- Microsoft Detours transaction behavior: `https://github.com/microsoft/Detours/blob/main/src/detours.cpp` (`DetourUpdateThread`, `DetourTransactionCommitEx`, `DetourTransactionAbort`).

## Minimal-diff position

**No functional diff is justified yet because the initiating crash is unresolved.** The minimal safe next diff is instrumentation-only: name the three workers, retain their TIDs, and add phase/counter fields or the fixed ring journal.

If a later trace proves `patch_loaded_modules` is involved, do not treat a 2 ms to 25/250 ms interval change as a fix. The conditional fix should:

- replace repeated unlocked whole-PEB enumeration with loader notifications that only enqueue module bases; never patch inside the loader callback;
- pin/revalidate each module in the worker before parsing and bounds-check every PE directory/thunk against `SizeOfImage`;
- publish IAT values with compare/exchange and skip/log a slot whose predecessor is not the expected canonical or already-recorded chain;
- stop scanning once the required device and NGX hooks are proven installed; and
- move `GetDevice`/`CreateFence`/`Signal` calls outside `g_lock` with explicit fence lifetime ownership.

That is larger than a defensible emergency one-line change, but it addresses the actual lifetime/chaining problems without disabling protection or patching signed DLLs.
