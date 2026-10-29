# WuWa native D3D12 integration handoff

## Candidate and merge order

This directory is an isolated, cross-compiled candidate. `native/` is rebased
on the current pc3b main source (including `verified_effective_passes`); `protocol/`
is the unchanged frozen D5RP32 copy. Apply `integration.patch` only after
verifying every hash in `SOURCE_PRECONDITIONS.md`. The eventual main-tree build
links the existing
`adapters/format_bridge/build/libnr_format_bridge.a` and compiles the existing
WuWa/common adapter sources with MinGW. It adds no plugin framework or fourth
DLL: output remains `dxgi.dll`, `dlss5-native-host.dll`, and
`dlss5-native-runtime.dll`.

The candidate has no ReShade/RenoDX registration, discovery, event, or private
unwrap API. Deployment is deliberately absent. Main must snapshot and **remove**
the old ReShade proxy/add-ons after review and rollback preparation; renaming an
add-on is not removal. This worker did not touch the installed game, old daemon,
launch configuration, login DB, accounts, signed NVIDIA files, or protection
components.

## Actual frame route

WuWa is selected only for the exact process basename
`Client-Win64-Shipping.exe` reached through the native DXGI bootstrap. Detection
creates a closed provisional record, not an attached/ready capability. On a real
NGX list the host creates `FormatBridge` against that list's device and sends a
disabled runtime compatibility request. Actual Attach is built through the
existing `wuthering_waves::contract()`, `capabilities_for()`, and
`build_native_attach()` only after all of these are true:

- production runtime query, signed-NR/vkd3d compatibility and bootstrap count 1;
- real D3D12 device, direct-queue hook, and signed NGX hook observed;
- device-bound FormatBridge creation and format-support checks succeeded.

Only then may telemetry emit capabilities. This is readiness evidence, not a
GPU/game-quality attestation.

Each real Feature 1/13 Evaluate snapshot is normalized through the existing
WuWa evidence normalizer, common policy, and native-contract builder. The
reconstruction comes only from the successfully created handle's real signed
module/feature tuple (`dlss/1` or `dlssd/13`); the phase publisher does not pick
SR or RR.

- POST calls the original signed SR/RR once first. Its current rotating Output is
  both source and game target in format 26. MV format 34 and depth format 41 are
  converted on that same list to owned origin-zero formats 10/10/39. The strict
  native runtime sees only the normalized frame. The only format-10 to current
  format-26 write is recorded by `FormatBridge::commit()` after native returned
  `EVALUATED`, the frame identity matched, and `actual_nr_calls` matched the
  requested 1..10. Host commit proof is withheld until that conversion records.
- PRE is admitted only for the actual ordinary Feature 1 handle. Color must
  already be coherent format 10; guides still normalize from 34/41. On a fully
  evaluated result, the exact same original SR call temporarily receives the
  native-owned format-10 Color with X/Y origin zero, verifies it, calls signed SR
  once, then restores and rereads original Color/X/Y. Any failure calls original
  SR with its original values. Feature 13 + PRE returns unsupported before the
  normalizer and preserves RR; there is no hidden POST branch.

No external Output pointer is cached. FormatBridge AddRefs current resources,
its immutable per-flight descriptor heap, and exact list only through retirement.
Before every normalization, a pure production budget policy consumes a fresh
DXGI local `Budget`/`CurrentUsage` sample, actual `GetResourceAllocationInfo`
size for one slot, global `FormatBridge::resident_owned_bytes()`, and the same
unweakened max(10%, 1 GiB) reserve. Compatibility probes charge zero NR chain
bytes but all remaining planned format slots plus reserve. Initial owner/shape/
order/pass admission charges the complete prospective NR chain; only an actual
accepted NativeRuntime `CREATE_PENDING` or `EVALUATED` result records that
private allocation. Later matching frames charge zero new chain allocation
because `CurrentUsage` already contains it, while still charging fresh reserve
and remaining global format slots. Failed/unknown/partial create, reset,
submission failure, owner retirement, and signature mismatch cannot establish
or retain that receipt. Output-resource rotation at the same dimensions is not
an allocation signature change. The bridge's separate 3 GiB hard cap remains;
it is not treated as available VRAM. NativeRuntime's own admission check remains
the final guard before its allocation.

The host artifact is relinked against FormatBridge static library SHA-256
`25def10412aa841324e6e66d500d1c0c8f2762c5c57b5d1e802e3f9c0c11179e`.
Its retained offscreen RTX 5090 harness passed seven data cases after explicitly
rounding MV with `f16tof32(f32tof16(motion))`. Vulkan Core + Synchronization
validation was clean there, but D3D12GetDebugInterface returned `0x887a002d`;
the overall harness therefore remains `pass:false`, and it is not game proof.

## Format-tail submission ownership

`normalize()` records work even when native later reports CREATE_PENDING,
BUDGET_EXCEEDED, or ERROR. `queue_hooks.cpp` therefore has a separate private
format-tail table:

1. reserve an observer before calling `normalize()`;
2. arm it with every returned format token;
3. forward the real `ExecuteCommandLists` first;
4. issue one Signal on that exact queue and pass its fence/value to
   `FormatBridge::submitted()`;
5. let only the telemetry worker poll `retire_completed()`.

This works for format-only lists with no runtime Create/Evaluate cookie. Format
tails never call `runtime_submission_status` and never count as NR evaluation
proof. A successful real `Reset` before submission invokes
`abandon_unsubmitted()`. A release without a confirmed Reset is not treated as
discard proof (the bridge's safety AddRef can keep the list alive), so it retains
rather than prematurely frees. A queue-device mismatch or Signal failure is
also rejected/retained because the list did execute.

## Startup/login heartbeat lease

`wuwa_lease_publisher.py` imports `PhaseGateState`, broad `find_game_pids`, and
the read-only `latest_login_time()` query from the existing
`/home/user/rt_5090_project/dlss5_vk_bridge/wuwa_phase_gate.py`. It does not use
the old one-shot marker.

The native host writes a 48-byte per-process challenge containing Windows host
PID, process creation FILETIME, random session nonce, and issue time. Because
the legacy broad finder can return both a parent `Steam.exe` stub and the game
when each argv contains the game token, the publisher filters candidates by the
complete basename of Wine's argv[0]. It reads `/proc/<pid>/stat` before and after
cmdline, requires a stable start tick, and requires exactly one passing image;
zero or multiple candidates remain closed. Its 104-byte atomic
lease binds the challenge, exact game PID/start tuple, publisher PID/start tuple,
fresh login phase generation, explicit external anti-cheat policy permission,
and a strictly increasing heartbeat sequence. Native accepts only phase=open,
matching challenge, complete nonzero identities, and an issue/expiry interval
at most two seconds. Missing, malformed, stale, watcher-failed, publisher-dead,
game-exited, PID-reused, DB-unreadable, or same-process-relogin state closes the
gate. Native file reads occur only on the telemetry worker.

Without `--anti-cheat-policy-permitted`, anti-cheat permission remains unknown/
closed and no open lease is written. That option is only an explicit Main-owner
policy input; this candidate neither infers nor validates permission. The native
side separately calls WinVerifyTrust (cache-only, no setting changes) on the
current executable before allowing open, but its target-game behavior and the
captured `0x0876232c` application ID remain Main review items rather than claims
manufactured by CPU fixtures. No protection bypass,
early patched protected module, account write, or database write exists.

This is specifically the evidenced **startup/login transition plus 15-second
settle**. It does not detect or claim later world/loading-screen state. If Main
requires a continuing world-load gate, that needs a separate real source and a
new reviewed fail-closed input.

## Required Main-only cold checks

No Wine, GPU, or game was launched here. Before declaring WuWa compatible, Main
must cold-test at least RR+POST/1 and, only if the game exposes ordinary SR,
SR+PRE/1. In addition to the pc3 completion-proof acceptance checks, verify:

- actual game resources and states are exactly Output/MV/depth 26/34/41 and the
  declared UAV/NPSR states at this seam;
- current Output rotates safely and is never retained after its frame fence;
- all prepare-only CREATE_PENDING/budget/error/reset paths retire correctly;
- POST R11 round trip and sole final commit are correct under the debug layer;
- after POST's final format shader, the actual game seam rebinds any later
  compute state; after PRE format/native shaders, the signed SR Evaluate binds
  its own root signature/PSO/heaps before recording;
- Color/base restoration survives success and every failure; original signed
  Feature 1/13 result and handle remain unchanged and are called once;
- queue-device mismatch stays failed/retained, and format-only work never raises
  `actual_nr_call_count` or completion proof;
- lease expiry is observed in <=2 seconds and relog requires a fresh 15-second
  settle; verify the Linux PID/start tuple corresponds to the intended Wine game
  process on the target Proton build;
- WinVerifyTrust behavior and the captured `0x0876232c` NGX application ID are
  valid in the target build.

D3D12 has no `GetState`; this code restores only from the exact state declarations
at the evidenced seam. It makes no claim that authored/cross-compiled code is
live-game validation.
