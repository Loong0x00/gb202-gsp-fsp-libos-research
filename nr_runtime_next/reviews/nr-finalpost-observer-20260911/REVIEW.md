# Minimal owned Vulkan FINALPOST observer — CPU/crossbuild review

## Result / scope

Ready for **Main's review**, not GPU acceptance. Only this review directory was written. The isolated DLL was cross-built, never loaded or executed; no GPU, Wine, live-package build, harness modification, or signed-file modification occurred. This observes the **actual signed NR Vulkan API through the frozen vkd3d interop backend**, not an NVAPI_D3D12 proxy.

Artifact: `source/native/build/dlss5-native-runtime.dll` (2,754,064 bytes)

**New exact SHA256:** `29bc4bcf853771cd59b4ef96bf3b3777d10aa8fe26cf63fd1d76811a43cddf5d`

Approved frozen runtime SHA256: `5b4f8afd1b545cad6d4f3ccbfd089c02b2cf0ff79d7bbfdb9277e74d98e508ba`.

Signed NR read-only pin: `e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e` (165,840,496 bytes). Its local file was read to verify its pin and bounded string table; it was not copied into this clone.

`FROZEN_INPUTS.json` records every copied runtime/include/common/protocol input. Among copied files, **only `runtime/interop.cpp` differs**: an observer include and a local choice of the two Init proc-address arguments. The existing `patch_import`, `identity_get_module_filename`, signed NR loading, bootstrap, codec, pipeline, and protocol are byte-for-byte unchanged. No CUDA architecture/code-patch probe was reused. The frozen identity IAT hook still exists exactly as before; “no new signed modifications” does not mean that pre-existing route was removed.

## Entrypoint and proxy ABI

`initialize_backend` still resolves signed `NVSDK_NGX_VULKAN_Init_Ext2` and invokes its frozen `__cdecl` ABI:

```
NgxResult(app_id, L".", VkInstance, VkPhysicalDevice, VkDevice,
          PFN_vkGetInstanceProcAddr, PFN_vkGetDeviceProcAddr, api, nullptr)
```

Only those **two function pointers handed to Init** may change. `Backend::gipa/gdpa`, `load_vk_dispatch`, and all other Init arguments remain unchanged. No loader export, vtable, signed import, or Vulkan device/instance dispatch table is newly patched.

The exact, case-sensitive gate is `D5R_FINALPOST_TRACE=OWNED_STATIC_OFFSCREEN`. Unset, empty, different, or oversized values return the original two pointers **without recorder setup, interception, or file creation**. Explicit-on setup failure diagnoses the failure and returns the original pointers; absence of artifacts is not proof.

The wrappers call each original resolver once with the original handle/name. A real NULL remains NULL; unknown names remain untouched, including `vkGetDeviceProcAddr` queried through GIPA. Intercepted names only:

| Name | Header PFN / return |
|---|---|
| `vkCreateCuModuleNVX` | `PFN_vkCreateCuModuleNVX` / exact `VkResult` |
| `vkCreateCuFunctionNVX` | `PFN_vkCreateCuFunctionNVX` / exact `VkResult` |
| `vkCmdCuLaunchKernelNVX` | `PFN_vkCmdCuLaunchKernelNVX` / `void` |

Definitions use Vulkan `VKAPI_ATTR` / `VKAPI_CALL`; compile-time PFN type checks pass on Linux CPU and MinGW x64. Callbacks, opaque handles, pNext, structures, pointers, and output pointers reach the original call unchanged, exactly once. Every real Vulkan call is outside recorder locks. Recorder exceptions are contained; observation failure does not synthesize a Vulkan return value.

Instance-query and device-query targets have **separate atomic function-pointer slots and separate proxies**. Only the owned instance/device queries are wrapped. A changed real target is returned untouched, with an explicit diagnostic, rather than redirecting an already-issued proxy. This is one bootstrap / one owned-device scope, not a general multi-device layer. Command buffers have no device argument: their ownership is a harness precondition, not inferred from their opaque handles. Calls obtained through some other resolver path are deliberately not intercepted.

The DLL retains exactly the frozen six exports (`DLSS5_NativeRuntime{Execute,Initialize,Query,Reset,Retire,Submitted}V1`), with unchanged frozen `DllMain` behavior. No observer work in DllMain. PE import/export details: `DLL_PE.txt`; extra observer system dependencies are BCrypt and Advapi32 APIs.

## Bounded observations and byte contract

- At most **64 modules**, **512 functions**, and **128 module-hash attempts**. No unbounded metadata container. Full tables and invalid metadata are diagnosed; original calls still proceed.
- Module input is hashed **before** create, only when `0 < dataSize <= 16 MiB`. Windows BCrypt SHA256 receives checked 64 KiB CPU chunks. Only size/hash/handle are retained, not module bytes or a VRAM dump. Only successful creates bind returned handles. A failed hash is explicitly unknown.
- Function create copies at most **255 printable ASCII characters plus NUL**, then records name → function handle / module handle / SHA256. Unreadable, unterminated, or control-character names are skipped. An untracked module hash is explicitly `unknown`, not a match.
- Observed successful handle reuse retires old associations; invalid new metadata cannot retain the old function name. No destroy interception was added. Tables are intentionally non-evicting: saturation reduces coverage rather than guessing identities. Reuse or calls outside the owned observed creation stream cannot be attested.
- Only the **first eight FINALPOST-family submissions** are eligible, process-wide, counting unknown variants and failed capture attempts. Non-FINALPOST functions never trigger a parameter read. Unknown function handles are diagnosed. One terminal launch-limit diagnostic is emitted.
- Parameter sizes use an **exact allowlist**, not substring-based length inference. Base is `cc_tinlayout_fused_post_block_swin_1h_32`, optionally followed by `_fp8`: **184 bytes**. Either precision base plus exactly `_simple_blend`, `_simple_blend_full_rect`, `_control_mask`, or `_control_mask_full_rect`: **312 bytes**. Unknown variants, including `_rgb`, log a skip with no guessed-length read. These ten names were verified in signed NR's bounded string-table window; 184/312 sizes are anchored by `../nr-static-binding-20260911/REPORT.md` and the static layout work.
- Capture requires the header's **`paramCount == 1`**, `extraCount == 0`, and no launch pNext extension. The latter two are conservative plain-contract restrictions. Original calls still receive all extensions/extras unchanged when skipped.
- Read the launch info using **`sizeof(VkCuLaunchInfoNVX)`**, then just the pointer-sized slot at **`pParams[0]`**, then exactly 184/312 bytes from that CPU pointer. Current x64 header size is **88**, `paramCount` offset **56**, `pParams` offset **64**. ABI assertions pass in the Windows crossbuild. No manually invented 96-byte launch-info read.
- Every host read validates nonzero/overflow-safe pointer bounds and committed readable non-guard/non-noaccess regions with `VirtualQuery`, then uses checked `ReadProcessMemory` (including byte-count validation) rather than an unchecked memcpy from caller memory. Raced unmapping fails the read. No pNext chain, pExtras array, embedded texture/surface/device address, or GPU pointer in the aggregate is dereferenced.
- Log includes command buffer, function/module identity/hash/name, grid/block dimensions, shared memory size, counts, and expected byte count. Parameter bytes are captured and saved **before the original launch call**. They attest a pre-call submission snapshot, **not execution, GPU completion, output correctness, or middle activations**. Concurrent caller mutation is not made safe by this observer.

The selected static SM120 finalpost ELF candidate is **2,789,376 bytes**, SHA256 `feb368ff5279a7408b1e55554db6e468d7f114a24b18b2af8d7e6989a410c612` (`../nr-static-layout-20260911/finalpost-sm120.cubin`). This is a comparison candidate, **not an observed runtime module match**. A different uploaded container/hash is not automatically equivalent.

## Artifacts and failure semantics

Main must supply a fresh, private, owner-only, non-source CWD within its separately guarded private prefix. CWD is captured once; a final-component reparse directory is rejected. This is not an adversarial directory-tree sandbox: Main must own and guard the parent path as well.

Fixed filenames, all **CREATE_NEW**, no overwrite/append-to-existing/retry/delete:

- `finalpost-trace-v1.log`: at most 4,096 normal events plus one explicit terminal drop event.
- `finalpost-args-01.bin` through `finalpost-args-08.bin`: each successful snapshot is exactly 184 or 312 raw bytes; gaps reflect skipped/failed attempts.

Files request `GENERIC_WRITE` only and a protected, non-inheriting DACL granting the current token user **FR/FW, not execute**. The cross-built DLL and map also have Unix mode 0644. Trace writes and snapshots check full byte counts and flush results. Snapshot close failure is also reported. Existing filenames are not touched; failed partial files remain marked non-proof. No snapshots are saved if the primary trace is unavailable or saturated. Startup/write failures explicitly go to OutputDebugString/stderr when the trace itself cannot be written. These auxiliary sinks may not be collected by every harness: **Main must capture stderr/debug output and require a complete trace**, never treat silence/missing files as success.

Windows `VirtualQuery`/`ReadProcessMemory`/BCrypt/ACL/CREATE_NEW behavior is **cross-built and source-reviewed, not executed here**. In particular, Wine's mapping of the nonexecute owner DACL into Unix file modes is not attested. Main must independently enforce private directory/umask permissions and verify no execute bits on output files before accepting a later run.

## Verification

Executed CPU-only:

```
make -C reviews/nr-finalpost-observer-20260911/source/native cpu-test all
python3 reviews/nr-finalpost-observer-20260911/source/native/tests/source_checks.py
```

Four portable test modes pass: baseline, flow, limits, failures. They exercise the **production proxy core**, with mock host-memory/hash/file backends: exact name allowlist and 255/256 boundary, zero/16MiB/>16MiB/hash-attempt limits, module/function table saturation and reuse, first-eight launch budget, unknown variant no-read, pointer overflow and too-short host span, capture-before-real, immutable structures/aggregate/pointer slot, opaque callback/pNext pass-through, exact-once forwarding, error-return preservation, NULL/unknown/foreign resolver handling, independent GIPA/GDPA targets, changed-target bypass, save failure, and recorder exceptions. A mock real call re-enters the recorder mutex, under a timed test, to detect lock-held forwarding. Off mode passes original pointers even with absent IO callbacks.

All four modes also pass AddressSanitizer + UndefinedBehaviorSanitizer with leak detection. These mock tests do not substitute for exercising the Windows APIs. The build log retains an initial intentionally corrected ABI assertion failure (96 vs actual header 88); final runs pass. No failing test is hidden.

`source_checks.py` verifies frozen originals against input hashes, the exact two-block interop diff, unchanged identity route and exports, and static platform guard presence. `PINS.json` records output, original runtime, signed NR, static candidate ELF, Vulkan headers, and compiler versions. `SHA256SUMS` pins this review's files. Build uses a zero PE timestamp for reproducibility. No host/boot/live-package/Wine/GPU target exists in the clone Makefile.

## Main-only next gate (not performed)

Review this patch and provenance first. Main alone may clone its harness, change that clone's **exact runtime DLL pin** to the new hash above, and run its already-approved offscreen path in a fresh guarded private prefix/CWD. Do not alter the approved harness/package or use the old architecture-patch probe.

Compare an explicit-off baseline (original supplied proc pointers, no artifacts) with explicit-on, require unchanged ordinary runtime/output acceptance, and inspect all drop/failure lines. For the intended evidence require the exact base FP8 function, a known matching original module hash/size, a complete `finalpost-args-XX.bin` of 184 bytes, and matching pre-call submission metadata. A suffix is 312 bytes and not interchangeable with the base. Missing launches, unknown hashes, table saturation, incomplete files, or resolver bypass are coverage failures, not negative model evidence. No GPU-completion or activation-byte claim follows from these files alone.
