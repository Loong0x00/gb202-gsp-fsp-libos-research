# Consumer/reset metadata observer candidate — CPU/crossbuild only

**NO GPU approval. No GPU, Wine, install, or harness execution was performed.**
This prepares future submission-metadata attestation, not actual native consumer/reset execution evidence, synchronization correctness, GPU completion, or activation contents. Main must review fresh pins and its isolated OFF/ON plan before any execution. Prior Main approvals are not inherited.

## Source and candidate pins

- Cloned Main `../nr-swin1h-binding-main-20260911/source`, all 96 files pinned before/after copying; rechecked unchanged after verification (`MAIN_SOURCE_PINS.json`).
- Ancestor runtime: `69caf30f906acfad284b759218cd6f15c727468db168171b6641bfdb331f7298`. NORMALRESERVE and the prior identity-IAT compatibility implementation remain byte-identical; no new IAT patches.
- **Candidate:** `build/dlss5-native-runtime.dll`, SHA256 `0efd06383925b2e41a9c84d38746317de89ef8907ebb93c03be6858ee58c2690`.
- `source/native/build/` is the unchanged cloned **ancestor**, NOT the candidate. PE outputs under `build/` are non-executable on this host and were not run.

## Original ABI proof before enabling reads

`verify_abi.py` independently rechecks exact original signed DLL SHA256 `e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e`, full fatbinary/DLL slice equality, pinned PTX versus a fresh pinned-cuobjdump decompression, and original ELF `.nv.info` records. Every new entry has exactly one parameter, ordinal/index/offset zero, with matching ELF `KPARAM_INFO` and `CBANK_PARAM_SIZE`, and PTX `.param .align 8 .b8 ..._param_0[N]`.

| Exact name | N | Exact permitted module SHA256 |
|---|---:|---|
| `cc_tinlayout_fused_swin_1h_32_1_wait_fp8` | 96 | `c11e2eb6f6eeabadffe340dba74ec8c3f474f4ac4a8ed601d59e04d1d49bda3d` |
| `cc_tinlayout_fused_swin_1h_32_1_chained_fp8` | 96 | same c11 module00 fatbinary |
| `cc_cb_clear` | 16 | `661970ae2e3970b2d1541255c96ffabe241b4d3c5c2a59a895be1fde5db0dbe8` (module06 fatbinary) |

Module00's original ELF equals existing `nr-static-layout-20260911/finalpost-sm120.cubin` (`feb368…`). Module06's ELF is derived locally from the original pinned fatbinary, SHA256 `e67c8db5c29348f1650c532735b0d4740f6a003b7f932ae5c505a41ced082e7a`. No files in the concurrently-written sync review were used. Neither new ABI accepts the standalone ELF hash; the new name gates require the exact fatbinary requested above. `abi/` contains original ELF copies and ABI excerpts; originals remain unchanged.

## Minimal runtime diff and preserved gates

`SOURCE_DIFF.patch` / `SOURCE_DIFF.json`: four source files differ from Main:

1. `source/native/runtime/finalpost_observer.cpp`: add three exact names and their sizes; **name↔module coupling**, not global trusted-hash widening; derive limit diagnostic from `kLaunches`.
2. `source/native/runtime/finalpost_observer.h`: total attempt/snapshot cap 8 → **32**.
3. `source/native/runtime/finalpost_observer_win.cpp`: permit validated 16-byte snapshots in the existing saver (96 was already supported).
4. `source/native/tests/finalpost_observer_test.cpp`: new contract/matrix/lifetime/limit negatives; update shared saver and old limit regression.

Module06 cannot inherit ANY prior post/pre/inpview ABI; clear cannot inherit module00/ELF/unknown module trust. Wait/chained cannot inherit module06 or standalone-ELF trust. Previous names, aliases, module gates and all other code remain unchanged.

Preserved verbatim: owned Init resolver scope, separate instance/device forwarding, proc-change fallback, successful handle-reuse retirement, unknown metadata handling, original `pInfo` pointer passed exactly once outside the recorder lock, exact opt-in `D5R_FINALPOST_TRACE=OWNED_STATIC_OFFSCREEN`, literal non-opt-in inert return, buffer attribution, and all Vulkan memory flags/copies/barriers. No NVX destroy interception was added; observed handle association still is not complete native lifetime proof.

## Read scope, artifacts, and finite limits

- Host metadata only. Single `pParams` aggregate or the existing proved five-word extras `[1, host_buffer, 2, &size_t_bytes, 0]`, with `paramCount=0, extraCount=1`. Extras size must match the exact name ABI; `pNext` must be null. Tag `1` is an integer, NEVER a pointer. Unknown contracts fail closed.
- At most 312 host aggregate bytes per snapshot; 16/96 are copied only after exact name/module and argument-contract validation. Embedded device addresses are opaque and never followed. No GPU dereference/copy/readback or synchronization changes.
- **32 total selected-family attempts**, including rejected selected submissions, across all families and repeated calls, with one terminal limit event. At most 32 files / 9,984 aggregate bytes. No claim that 32 covers every possible run; saturation is an explicit coverage loss, not proof of absence.
- Existing limits unchanged: modules 64, functions 512, name 255 chars, module hash 16 MiB × at most 128 attempts, buffers 4096, buffer metadata log 256, trace lines 4096. Existing one-time 3,944,768-byte module00 host snapshot is unchanged and separate from argument snapshot budget.
- Filenames remain **`nr-kernel-args-%02u.bin`**. **`finalpost-trace-v1.log` is authoritative** for index, exact name/module, grid/block/counts, expected bytes, complete save, and any drop/skip/coverage gap. CREATE_NEW/private ACL/trace-availability/flush/partial-file safeguards are unchanged.
- A future trace records `before_original_not_gpu_completion`: submission observation, NOT device execution completion or successful reset. New 16/96-byte records receive no activation attribution. Existing post184 `activation=...` labels are retained opaque address/buffer attribution only, never activation contents.

## Verification

- `bash build_verify.sh > BUILD_VERIFY.log 2>&1`: fresh static ABI checks; **17 observer + 35 buffer scenarios each under native CPU and Clang ASan/UBSan (104 passes)**; strict-warning MinGW DLL and two mock-suite PE crossbuilds. PE code was not executed.
- New tests cover pParams/extras success, wrong module both directions (including every old exact ABI under module06), unknown module, exact-name near misses, wrong sizes, unknown/lone extra tag1, bad tags/counts/pNext/spans, failed saves/IO exceptions, module/function reuse, 32 mixed-family successes and 32 failed-attempt budget consumption. Each mock launch checks the same original pointer and bytes, forwarded exactly once; successful copy read counts exclude embedded-pointer traversal.
- All 35 inherited buffer scenarios pass, including instance/device aliases, retirement/reuse, overflow, ambiguous attribution, capacity, exception, resolver and inflight/generation fail-closed cases.
- `python3 verify_candidate.py > SOURCE_CHECK.log 2>&1`: unchanged Main inputs, exact four-file diff, identical forwarding/lifetime/host-copy bodies and opt-out saver gates, preserved reserve/interop/IAT sources, same six PE exports and import DLL list. See `VERIFICATION.json`.
- The inherited Makefile omits observer runtime objects/libraries. `build_verify.sh` uses an explicit review-local crossbuild including those objects; it never invokes `check`, `package`, Wine, or any harness.

Remaining uncertainty: only fresh Main-controlled native OFF/ON observations can establish whether/when these consumer and clear names are launched, bind their opaque arguments, and assess observer perturbation. This candidate grants no execution or GPU approval.
