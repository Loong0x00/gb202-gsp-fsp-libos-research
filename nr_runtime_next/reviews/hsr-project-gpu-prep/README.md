# Owned-GPU Project-ID fixture — CPU-prepared, NOT GPU-validated

**No launch approval, HSR game acceptance, or gate approval.** Authoring/verification ran only local CPU compilation, static inspection, hashing and tests. No Wine/GPU/guardian/game/protection execution, network requests, service operations, account-prefix access, input or screenshots occurred. Main production source/build/package were not changed. No signed DLL has been copied into this review directory.

## Build / CPU check

From the repository root:

```sh
make -C reviews/hsr-project-gpu-prep check
python3 reviews/hsr-project-gpu-prep/run.py --plan
```

Artifacts: `build/project_gpu_probe.exe` (x86-64 MinGW, warnings-as-errors, static C++ runtime), `build/policy_test`, `VERIFICATION.log`, `PE_IMPORTS.txt`, `INPUT_PLAN.json`, `PLAN.log`. The PE is **compile-tested only**, not run. It links D3D12/DXGI, not runtime implementation or private NGX exports. Windows system/UCRT imports are provided by the fresh Wine prefix.

`--plan` is the default: streams hashes, creates the inventory only. It does **not** stage the 165,840,496-byte NR DLL or any other DLL. Exact resolved sources, sizes, hashes and prefix-relative destinations are in `INPUT_PLAN.json`. Native runtime is **`native/build/dlss5-native-runtime.dll`**, not frozen `native/package` or a review/private rebuilt runtime. Main must retain its build-to-source provenance; PE exports and hashes alone are not reproducible-build proof.

## What the executable exercises

1. Requires explicit runner authorization and mode. Creates no window/swapchain; uses existing physical display environment only if Wine needs it. An internal 18-second watchdog terminates a hung process.
2. Loads staged `_nvngx.dll` by absolute path and production runtime by absolute path. Calls `Initialize`, optional `SetProjectIdentity` (mandatory for this fixture), `Execute`, `Query`, and, for inference, `Submitted`/`Reset`/`Retire`. Missing typed API fails closed, never uses numeric fallback.
3. Uses the actually captured **string** Project ID `"231313132"`, Unity engine `2`, version `"2019.4.34f1"`, SDK `20`. Capture provenance: `../hsr-project-runtime-identity/EVIDENCE.md`, citing the actual D3D11 Project-ID return. The controlled **`C:\fixture\data` is NOT a captured HSR path**. Optional FeatureCommonInfo is null; no captured pointers or parameter maps are borrowed. `ngx_application_id` remains zero only as the typed-path discriminator, never passed as a fabricated numeric app ID.
4. Owns a hardware D3D12 device (exact NVIDIA `10de:2b85`), DIRECT queue, allocator, list, fence and initialized 256×256 resources: RGBA16F HDR checker (4/.25, .5, 1), RGBA16F motion (.5, −.25, 0, 0), and R32_TYPELESS depth .375. Production `initialize_backend` obtains its real Vulkan handles through the **existing vkd3d interop**, not a second/mock Vulkan device. Uploads are really submitted and fence-completed.
5. Disabled `Execute` invokes production `initialize_project_core` with its existing exact-file/RVA pins and **bounded owned Core GetProcAddress / exact NR Init observer**. No private runtime internals are exported/copied/called by the harness. No extra hook, signed disk/code patch, renamed NR-as-SR, feature-enumeration rewrite or cached-resolve workaround is added. Existing production in-memory IAT observers remain unchanged.
6. Default `--bootstrap` stops after this compatibility probe, with no Feature18 create/evaluate. It requires disabled status, one bootstrap, compatible=1 and all production/interop/signed-NR/Project flags. Core success alone is insufficient.
7. Optional `--fixture-inference` proceeds only after that proof, allows one production Feature18 create and one evaluate, submits exact tracked cookies on the owned queue, and requires an actual completed fence plus Query completion sample. Failed/partial recordings are discarded via Reset, not submitted/retried. All resource/module lifetimes remain process-owned; no unsafe runtime unload.

The raw-frame `game` is UNKNOWN; `reconstruction=SR` is only the required **synthetic POST input shape**, not evidence of a signed SR call/binding. The nonzero owner is a fixture bookkeeping key, not an invented signed feature handle. No GATE_OPEN flag, adapter attach/gate API, game phase marker, or game routing is used. Motion data represent the normalized FLOAT34 contract; this does **not** re-test live NVX capture/HSR same-resource view attestation. Existing transport/NVX tests cover a different boundary.

If actual NR completes, call it **fixture inference**, never HSR game acceptance. No image-quality/readback or SR/game binding claim follows from completion.

## Exact inputs / staging

| Role | SHA-256 |
|---|---|
| Core `_nvngx.dll` | `bdad96fdca36050a94a221bb89eab4fc5db6e53ef799494a68957a2e2b28e283` |
| signed NR `nvngx_dlssnr.dll` | `e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e` |
| signed SR `nvngx_dlss.dll` | `ba685453f689201997db726fb0d904e969bdd148ea9a58a56ba5c1ead86eeaf9` |

Core is sourced from the retained **test-only** `tests/format_gpu/runs/20260910-072903-proton/compat/pfx/...` file. The four graphics DLLs (DXGI, D3D12, D3D12Core, NVAPI64) come from the retained **test-only** `tests/hsr_transport_gpu/runs/20260910-141329/prefix/...` files, not the account prefix. NR/SR are read-only exact originals at the paths inventoried; no game executable/plugin/router/host/protection files are staged. SR is available under its genuine name in case Core's ordinary feature enumeration needs it; **loading SR does not prove NR binding**. No SR/NR function is pre-resolved by the harness.

Only Main execution copies the nine inventoried files into a freshly initialized run prefix. Graphics replace fresh Wine builtin links atomically (never write through them); Core/SR/NR/runtime/EXE reside at `prefix/drive_c/fixture/`. Each staged target is resolved and rehashed into `STAGED_HASHES.json`. No old test/account prefix registry is cloned. Exact hashes retain prior signed-baseline identity; no new signature-chain/revocation validation is claimed.

## Main-only bounded runner proposal (NOT executed here)

Main must review this runner and inventory and separately authorize a no-game GPU window. Then:

```sh
# Re-run CPU checks/plan after ANY input change, inspect the plan, then:
python3 reviews/hsr-project-gpu-prep/run.py --execute --main-authorized \
  --inventory-sha256 <reviewed-INPUT_PLAN.json-SHA256> --mode bootstrap
# A separate authorization may instead select --mode fixture-inference.
```

Do not paste the placeholder, bypass a failed check, reuse an old prefix, run the EXE manually, or launch another game/test concurrently. There is no automatic second run or fallback.

Runner safeguards (based on `tests/hsr_transport_gpu/run.py`, tightened):

- Explicit authorization + approved inventory digest; rehashes current inputs and rejects drift, redirects, wrong pins or package sources.
- Requires a fresh **offline network namespace** (`unshare --user --map-current-user --net`) before any Wine/NGX work. No network availability/gate workarounds. Namespace failure is a blocker, not permission to run outside isolation.
- Holds repository `benchmark.lock`; exact `/proc` game-name/argv and truncated-comm checks before launch and while running. Unreadable process state fails closed. It never kills games.
- Starts unchanged Astral guardian with `--no-launch --dry-seconds 80`, waits for live monitoring, checks liveness throughout boot/probe, and requires final guardian exit 0. **Both `--phase-log` and `--phase-marker` are redirected under this run.** The old transport pattern does not override these defaults; guardian otherwise unlinks the game's marker even in no-launch mode. This proposal does not touch that marker or the account Player.log.
- Fresh Wine prefix and HOME/cache/config, sanitized environment, no inherited Wine/injection/proxy/account settings. No virtual display, input, screenshots, game launcher or protection process. Wine's own prefix initialization is the only proposed service activity, never account/system service manipulation.
- Wineboot ≤45s; probe ≤22s externally /18s internally; fence waits ≤3s; completion sampling ≤1.5s; guardian finite lifetime, arm/completion deadlines. Log/hashing/staging are CPU/disk operations, not evidence of GPU execution.
- Always kills/waits **only that newly owned prefix's** wineserver, including successful runs. Process-group cleanup applies only to its child/guardian. No global `pkill`, account-prefix wineserver, registry transplant or package deployment.

Results live only under `runs/<timestamp>-<pid>/`: plan, staged hashes, probe stdout/stderr (`WINEDEBUG=-all,+debugstr` captures production diagnostics), Wine/graphics/guardian logs, and `RESULT.json`. No CURRENT_RUN/global gate file is written. A fresh Wine prefix is not a full filesystem sandbox; the proposal does not import account registry data.

## Evidence interpretation and blockers

- **Not tested on GPU/Wine.** Current Core result, NR Init call count, CMS and compatible are **unknown**, not zero/success. No run directory exists from this authoring task.
- Likely decisive boundary: pinned Core may enumerate only Features 0..17 and never resolve/call NR. Even Core result `1` with `nr_original=0`, or an Init hidden behind a cached resolver, leaves production incompatible. Preserve diagnostics; do not alter Feature18 binding/enumeration, add direct Init_Ext2 fallback, or approve a gate.
- Existing unproven log exposes Core result, NR-original/success call counts, fresh resolver and mismatch. **It does not expose CMS on failure**; JSON keeps CMS null, not a guessed value.
- On success, existing runtime logs CMS but omits raw Core-result/call-count telemetry. `evidence.py` reports result=1 and exactly one successful NR Init **explicitly as inferred from the hash-inventoried production `proven(Evidence)` policy**, corroborated by success log + Project-compatible Query. This is not an additional raw observer. Missing/duplicate/conflicting diagnostics fail the receipt closed. Main must confirm binary/source correspondence before relying on this inference.
- `actual_nr_calls` / Query's `actual_evaluate_calls` count successful full-pipeline evaluations, **not every attempted signed Evaluate**. Failure-path exact attempted count is not exported; JSON leaves it unknown. Layer create and successful-evaluate counters are printed separately. Init counts are never conflated with inference counts.
- Fresh/offline prefix may lack an NGX registry entitlement/cache, certificate dependency, supported null FeatureCommonInfo behavior, or driver capability. Report the actual failure; do not copy account registry, fetch network state, patch checks or loosen gates.
- User/network namespaces may be unavailable or may remove supplementary group access needed for `/dev/i2c-1`, NVIDIA/graphics devices or the physical display. Guardian/namespace/device failure must stop the launch. Main must resolve an authorized isolation/device-access plan; this worker did not test these facilities.
- Synthetic dimensions/resources may be rejected by the model even if Project bootstrap succeeds. That is a fixture diagnostic, not an HSR failure/acceptance result. Missing delayed dependencies or OutputDebugString capture likewise remain runtime blockers.
