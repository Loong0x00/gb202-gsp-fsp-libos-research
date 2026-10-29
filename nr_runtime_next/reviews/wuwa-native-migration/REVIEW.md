# WuWa permanent native migration — isolated CPU proposal

## Decision / scope

**Not deployable yet. Production `plan().ready` is false and `apply()` cannot write.**
This review supplies a working read-only evidence/API path, sandbox transaction model,
shared UI contract, and two unmerged hardening patches. It does not edit Main,
start/stop/query real services, launch Wine/Proton/game/GPU, access the account DB,
change Steam settings, or rebuild/copy any DLL into a game installation.
All writes and fixture temporary directories stay inside `reviews/wuwa-native-migration/`.
The fixed CP release, installer and UI remain unchanged. No HSR development code is a
WuWa payload source. No extra agents were used.

Read these first:
- `evidence-report.json`: recomputed, hash-bound historical observations.
- `production-plan.json`: truthful default API response, with deployment blockers.
- `proposal/wuwa.py`: `inspect/plan/apply/rollback/rollback_candidates`; production is
  read-only, mutations exist **only** in `FixtureInstaller` under this review's sandbox.
- `proposal/ui_contract.py`: backend registry, per-target notices/acks, immutable
  profile/path/generation tokens, preview/apply and rollback dispatch.
- `CPU_TEST_RESULTS.txt`: CPU tests, not GPU or real-system acceptance.

## Exact evidence and trust closure

`input-lock.json` pins 113 inspected artifacts. `proposal/evidence.py` embeds its
SHA256 and verifies all frozen package/source files and selected run files. This is
an explicit local review trust root, **not a signature or independent GPU rerun**.
A future signed release must sign/pin the same complete closure, not regenerate a
manifest from whichever development outputs happen to exist at apply time.
The two inspected CP installer files are audit pins only, never WuWa payloads.

During verification Main added only `visual_review` to its POST2 summary. The
hash gate correctly rejected that change (failure log retained). Explicit byte-level
review proved removing that new caveat reproduced the old exact hash and all other
112 pins remained unchanged. `evidence-drift-review.json` records old/new summary
and trust-root hashes. Only this narrowed no-user-visual-observation clarification
was repinned; no binaries/sources/publisher were refreshed or acceptance widened.

Installable binary candidate must remain:
`reviews/wuwa-main-physical-20260910-142015/package/bin/`

| File | SHA256 |
| --- | --- |
| dxgi.dll | f266b6d89e4df02bf6cc763fa09cb05d4e216a1b3764457fb484a27771015061 |
| dlss5-native-host.dll | 3ccbb32a75096f6c3fc0436049b91a62bd92ec46bdd9c0525129c2eb315b9146 |
| dlss5-native-runtime.dll | b73c492ec88b45055132c96e0a7fcd9d24158e37933ee4b3408d070afea15593 |

`SOURCE_SHA256SUMS` is checked against **that freeze's** `source/native` and sibling
`source/adapters`/`source/protocol`, including its `../` manifest paths resolved inside
the frozen source tree. Never fall back to `native/package`, live `native`, live
adapters, or a new Main/HSR build. Package README/TEST_RESULTS text predates physical
acceptance and is not sufficient GPU evidence by itself.

Publisher closure is the exact `reviews/wuwa-publisher-main-20260910-144721` freeze:
publisher `443abd90…d543f9`, legacy reader `3c8198e8…26b938`, runner Python/shell,
source checks and frontend core. Its `INPUT_SHA256.json` is identical to the POST2
run's `publisher-input-sha256.json`; each original absolute path is mapped to the
**frozen copy**, not re-imported from live development. Runner/core are provenance
inputs, not proposed long-running service dependencies.

### Honest verificationScope

Run: `wuwa-runs/20260910-144823-native-post-2-initial-off-physical-user-operated/`

- Physical user-operated **RR POST2**: 100 active receipts; handles `[1,2]`, creation
  counts `[1,1]`; 1,891 successful evaluates per layer (3,782 sum).
- 632 observed completed samples lower bound across OFF/ON epochs. This is the sum
  of positive observed counter deltas after resets, **not 632 frames per layer**, and
  is not inferred from API request acknowledgement alone.
- 240 disabled, 2 gate-closed receipts; OFF/ON requests acknowledged by runtime
  D5LC readback, **not a user-noticed visual toggle**. Main clarified during this
  review that the user did not watch the image or notice the NR toggle; there is
  no user-confirmed absence of artifacts. Main cold restoration and unchanged
  signed files are attested. No new cold-process observation is claimed here.
- Runtime status has no dimensions. Physical condition.json retains unused default
  width/height 1920/1080: **do not label this physical run 1080p or 6K from those fields**.
- Historical RR POST1 was owner-verified. The inspected 09:06:52 POST1 run has
  different host (`884757f9…dbe8c8`) and runtime (`0e355207…312d7`) hashes. It is separate
  historical coverage, **not current-frozen-bundle POST1 acceptance**.
- PRE, POST3–10, quality, performance, other settings/resolutions, permanent migration,
  and persistent-service startup/restart/relogin are not verified. The attempted
  POST10 directory is not treated as acceptance.

The runtime's structural capability JSON advertises `post/pre_sr`, max 10 and
restart semantics. Those are protocol capabilities, not a physical acceptance
matrix. Do not transplant its status or relabel it as full PRE/1–10 approval.
Use a separate static `verificationScope`/installation manifest. Never copy old
live-status, pipeline-status, challenge or lease as fresh execution proof.

## Launch wrapper audit — material production blocker

Read-only snapshots and hashes are in `audit/` and `input-lock.json.external_audit`.
The observed route is a single WuWa command line extracted from the existing Steam
process log, not a Steam/account configuration read or write.

1. `/home/user/.local/bin/wuwa-dlss5-6k-launch`:
   - lines 23–94 enforce GameUserSettings and update display keys in LocalStorage;
     its `--check` branch occurs **after** these effects, not a dry run;
   - lines 104–107 remove graphics markers and `enable --now` the legacy watcher;
   - lines 109–110 require the old router/service DLL hashes to be readable;
   - final handoff is `/usr/bin/steam -applaunch 3513350`.
2. `/home/user/hw_configs/wuwa-path-probe/launch-wrapper.sh`:
   - line 7 calls the above `--check` before probe guards;
   - can impose virtual resolution / DLAA, enables old submit-timeline tracing,
     and finally wraps or forwards the incoming Steam/Proton command with `exec "$@"`.
3. Frozen `core.py` lines 1634–1640 already **refuse native evidence with the legacy
   wrapper**. Preserve that refusal until a new exact route is accepted. Do not
   weaken `_has_native_backend_evidence` or call generic configured Wine as a fallback.

**No direct legacy DLL overwrite/deployment command was found in these two exact
current wrapper snapshots.** The desktop wrapper hashes DLLs rather than copies
DLLs. Nevertheless the settings/DB writes, mandatory old DLL reads and watcher
re-enablement make this chain incompatible. This is not a claim that arbitrary
future wrappers or unknown Steam hooks are overwrite-free. Re-audit and hash-bind
both wrappers and the complete actual launch route at preview and apply; changed
or unclassified copy/install/restore hooks block migration.

`legacy-wrapper-refusal.patch` is a proposed **early refusal guard only**, before
any legacy settings/DB/service effects. It detects native host/runtime (including
broken symlinks) or pending/installed migration markers. It neither enables native
launch nor replaces the missing transactional dispatcher. It is unmerged and only
syntax-/fixture-tested. It is not a robust standalone ownership/security boundary:
production needs the exact inventory/transaction manifest and launch lock below.

### Required preserved launch route

"Root launcher" means the normal game-root `Wuthering Waves.exe`, **not sudo/root**.

Historical Steam chain (see `audit/observed-steam-route.txt`):
`steam-launch-wrapper -> reaper SteamLaunch AppId=3513350 -> SteamLinuxRuntime_4
_v2-entry-point -> dwproton-11.0-4/proton waitforexitandrun -> Wuthering Waves.exe`.
The physical runner used the same actual dwproton executable and root launcher
with compatdata `3513350`, rather than directly invoking `Client-Win64-Shipping.exe`.
These are distinct observed handoffs; do not claim the full Steam-container route
was the route executed by the POST2 runner.

Future normal desktop native dispatch should hand off to Steam; the graphics
wrapper's native branch must validate the exact original incoming argv and forward
it unchanged after native transaction/lease readiness checks. No Steam account or
LaunchOptions edits. Preserve the existing normal root launcher, actual dwproton,
prefix, runtime/reaper chain, updater policy and protection chain. Skip only the
owned legacy graphics/config instrumentation after explicit transaction consent.
Do not guess a new runner, direct shipping EXE, generic Wine, forced display mode or
protection override. The observed updater policy was `PROTON_ENABLE_NGX_UPDATER=1`;
do not silently replace it with CP/generic defaults. Validate any future native
`dxgi=n,b` graphics override independently, without changing game settings.
The bounded test runner is **not** an appropriate permanent launch script: it
performs temporary control/scalar changes and cold restoration.

## Persistent native publisher: explicit reversible ownership transfer

Installing three DLLs alone is insufficient. The lease host needs the persistent
publisher for a fresh challenge/PID/start-time-bound <=2s heartbeat. Replace only
the **graphics** watcher, never a protection/account/background system service.

Frozen publisher imports an absolute live
`/home/user/rt_5090_project/dlss5_vk_bridge/wuwa_phase_gate.py` at module import time.
Pinning just the publisher file or a service unit misses this executable dependency.
Copying that publisher into a content-addressed directory does not fix its import.
`--settle-seconds 15 --poll-seconds 0.2 --anti-cheat-policy-permitted` matches the
physical publisher invocation, but this permission is owner rendering consent,
**not vendor anti-cheat approval** and not permission to alter protection.

Proposed immutable release:
- retain the exact GPU-tested binary freeze; package publisher + legacy reader +
  bootstrap/unit/launch dispatcher as a distinct content-addressed dependency closure;
- verify release trust, no symlink/hardlink/case collisions, ownership/modes, and full
  publisher/dependency/dispatcher/runner hashes at plan, apply and every service start;
- run isolated Python (`-I -B`, no PYTHONPATH) with trusted interpreter/stdlib; execute
  only verified bytes, not `hash(path)` followed by a second unverified import;
- no executable dependency under mutable Main source; immutable-by-release policy
  means drift is refused, not that user-owned chmod alone defeats a same-UID attacker;
- no legacy watcher `main()` execution: reuse only its frozen read-only reader/state
  machine. Never copy, restore or open the actual DB in this worker. Future existing
  reader uses SQLite mode=ro/query_only; installer never accesses DB/WAL/SHM.

`publisher-dependency.patch` / `proposal/publisher_candidate.py` are an **unaccepted
candidate**, based exactly on the frozen publisher. Only its dependency location/
loader changes: same-directory legacy reader, embedded exact reader hash, execute
verified bytes once. CPU tests import it under a non-main name in the sandbox with
SQLite connection forbidden; no publisher loop or game/service command runs.
`candidate-release.json` binds its new publisher hash and retains its tested base
hash. Its `publisherGpuTested` is false. A trusted bootstrap for the publisher itself
and persistent acceptance are still missing; this candidate must never be presented
as the `443abd90…` GPU-tested publisher. The service template is data with unresolved
placeholders, not an executable unit.

No startup baseline fabrication: if the publisher starts/restarts after login and
cannot prove the transition, remain closed until legitimate evidence. Expired or
ambiguous PID/start/challenge, DB read failure and multiple candidates must revoke,
not extend a lease. Preserve the frozen bounded 30s recovery rules and 15s settle;
do not weaken them to improve startup success. This login lease is **not** a detector
for later world/loading/teleport screens. Persistent restart, logout/login, suspend,
crash and stale-lease scenarios require explicit future acceptance.

## Proposed production transaction contract (not executed here)

API matches CP's explicit pattern, but has WuWa-specific notices and ownership:
- `inspect()` / `plan()` are read-only and do not create lock/state files, import a
  publisher, query DB or write service settings. Return checks, exact actions,
  target/release/evidence scope, required acks and a canonical hash `plan_id`.
- `apply(plan_id, acknowledgements=...)` is the **only** install entry. Bind plan ID
  to target/profile/route identities, protected-file inventory, exact source/evidence
  hashes, file preimages/modes, unit/drop-ins/enable/mask state, service process
  identity, launch lock, and requested non-mutating control preconditions. Recheck
  under an exclusive installation lock. Missing consent cannot be inferred from
  NR enable, preview, UI startup, detection or a service being present.
- `rollback(txid)` is a dry run; `rollback(txid, apply_changes=True)` is explicit cold
  compensation, not a generic ReShade restore. List only this target's transactions.

Required transaction ordering:
1. Prove cold for game shipping EXE, normal root launcher and the exact Wine/Proton
   prefix/process tree, including in-flight Steam launch. Unknown/unreadable proc
   candidates, stale PID identity or active unrelated ownership ambiguity block.
   Production must use pinned directory FDs/openat-style operations and stable
   identity reads, not the fixture's path-only mock. Do not terminate a game to
   manufacture coldness.
2. Coordinate **every** normal launch entry with a shared/exclusive transaction lock
   and durable pending guard. Recheck process coldness before each mutation. An
   uncooperative direct launch remains a blocker, not permission to patch protection.
3. Back up exact owned DLLs/markers, both wrapper bytes and metadata, old/native unit
   files, drop-ins, enable links/masks, active/enabled/failed baseline and service PID
   before effects. Reject unknown target collisions; no wildcard DLL deletion. Unit
   enable links are an explicit service-manager exception, not permission to follow
   arbitrary filesystem symlinks. Mask changes need exact transaction ownership.
4. Fsync backups and a write-ahead journal (plan/release/target/restore hashes and
   modes, service preimage, intended action and allowed postimage) before stopping
   anything. Keep bytes plus metadata, not just hashes. Use same-directory O_EXCL
   staging, fsync data, atomic rename, fsync directory. **Multi-file/service changes
   are not one atomic operation**; the guard and journal provide recoverability.
5. Explicitly stop legacy graphics watcher, verify stopped identity, disable future
   activation and apply a transaction-owned mask. Stage immutable publisher/reader,
   guarded native-aware wrappers and unit; retire only exact owned router/service/
   legacy markers; install host/runtime then dxgi from the frozen package. No mixed
   native+legacy launch is permitted in the transition window.
6. Validate preserved D5LC/D5RP without writes. The physical test temporarily used
   `NREnableUpscaling=0` and initial NR OFF. If existing controls violate the reviewed
   contract, block and require a separate explicit user control operation then
   replan; never silently import the runner's temporary scalar changes. No pipeline
   request normalization into POST2 behind the user's back.
7. After hash/route checks, daemon-reload; enable/start native publisher explicitly;
   verify unit MainPID/start identity and immutable ExecStart/argv. Idle liveness is
   **not** an active lease or GPU proof. Preserve fail-closed gate behavior. Never
   start both publishers. Publish the static installation/verification manifest
   last, then remove pending guard only after final checks/commit.
8. Failure: retain pending launch block. If game has appeared, **stop all further
   file compensation and require cold recovery**, rather than overwriting a loaded
   DLL or claiming rollback success. If cold, stop/wait native first; remove stale
   native lease/challenge safely while publisher stopped; reverse exact file/route
   steps and restore original units/drop-ins/enable/mask states. Restart legacy only
   if its original state was active and files are restored. Do not restore fresh
   lease/status bytes as current evidence. Recheck hashes/modes and journal rollback.
9. Crash recovery must reconcile pre/postimages even for rename/service effect before
   completion-record fsync. Unknown edits, corrupt backup, changed units/route or
   protected drift block before writes; never overwrite another actor's changes.

Owned production game targets are the exact three native DLL names; exact legacy
`00-dlss-ngx-router.addon64`, `01-dlss5-post-service.addon64` and audited graphics
markers; installer-owned state/manifest paths. Native ephemeral challenge/lease/
status require explicit cold invalidation handling. Do not recursively clear
`.dlss5-linux` / `.dlss-ngx-router` or use the test runner's broad inventory as an
installer write list. Preserve signed NVIDIA DLLs, executables/protection files,
account DB/WAL/SHM, saves, GameUserSettings, display selection, ReShade/user configs,
profile store, D5LC scalar bytes and D5RP requests. No account repair or DB restoration.

### What the fixture model does and does not prove

`FixtureInstaller` uses a fixed target allowlist, synthetic owned DLL bytes, trusted
preimages, canonical preview ID/acks, symlink/case/hardlink/type guards, an exclusive
flock, fsynced backups/atomic files/write-ahead journal, and pure in-memory
`MockServices` commands. It checks cold callbacks repeatedly, exercises stop/disable/
mask versus enable/start order, and recovers all 17 apply crash windows from disk.
Rollback rejects user drift/corrupt backups, restores original bytes/modes and mock
service state, and refuses hot compensation. Preservation sentinels are inert test
files, never real databases/signed files. No subprocess/service adapter is present.

The fixture's `route.json`, `game/legacy-enable`, synthetic publisher/reader and
`installed.json` stand for future production artifacts, not production path mappings.
It accepts only the modeled legacy-active/enabled baseline; production restoration
for originally disabled/inactive/failed/masked services and actual systemd links,
drop-ins, permissions, crash-during-rollback and restart persistence is still needed.
It is **not** a hardened adversarial filesystem implementation or a real systemd
transaction, and must not be made production-ready by toggling a boolean/path.
The candidate loader patch does not make the model's synthetic payload GPU tested.

## Minimal shared UI integration proposal

Current `native_migration_ui.py` hardcodes CP target, cached module, subtitle,
acknowledgement, budget notice and rollback target. Keep CP's existing API/module
loader/fixed release exactly as supplied. Do not alias WuWa through CP's installer
or budget ack; no changes to `installer/__init__.py` exports are necessary now.

Later integration points (no Main patch applied):
1. Supply existing CP module and a separately named WuWa module to
   `ui_contract.catalog()`. Bind exact root/shipping paths, not game title/AppID
   guesses. Unknown games (including HSR) get no migration backend here.
2. Replace `native_target_selected`'s boolean with a captured SelectionToken
   `(profile_id, executable, generation, target_id)`. Capture backend/token before
   starting each worker, check again on idle callback and confirm, including rollback.
   Switching away and back or switching profiles for the same executable invalidates
   stale previews. Keep existing non-daemon worker and close-during-mutation guard.
3. Populate title/notices/required checkboxes from TargetSpec and `verificationScope`.
   Every ack must be explicit; do not reuse CP budget text for WuWa. Keep detailed
   checks/blockers and proposed **service/route** actions visible, not only DLL names.
4. Use `ok && ready && plan_id` before enabling install. Production WuWa currently
   has ready=false: preview only. Rollback is tied to target and transaction, with
   another fresh backend preflight. Never save/rewrite a profile as part of migration.
5. After apply, report only "static files installed / publisher idle verified";
   fresh PID/session/sequence-bound runtime receipts are required for active NR.
   Unsupported acceptance scope stays visible even if protocol controls offer 1–10.
   CP retains its existing accepted-release/budget notices and behavior.

`ui_contract.py` is runnable/tested without Gtk; it is an integration contract, not
an imported Main UI change. Production GTK callback wiring and real-launch receipt
refresh still require Main review.

## Outstanding release gates

- Approve and implement the production filesystem/service/launch exclusion adapters,
  exact inventory/protected guards and reversible two-wrapper transaction.
- Implement and pin the publisher's trusted bootstrap; review candidate dependency
  relocation and closure. Persistent service lifecycle acceptance is **new work**.
- Accept the preserved native-aware actual Steam/dwproton/root-launcher path without
  any account/settings/protection edits or legacy DLL/config redeployment.
- Validate current controls without silently changing them; decide explicit UI policy
  for historical POST1 versus this exact bundle's POST2-only evidence.
- Exercise actual cold apply/recovery/restart/rollback with separate owner authorization;
  do not advertise permanent migration acceptance until then.
- PRE, larger counts and visual quality need their own independently hash-bound GPU
  acceptance. None is inferred from structural max_nr_passes=10 or POST2 success.

## Reproduce (CPU only)

From project root, all generated output remains in this review:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 reviews/wuwa-native-migration/proposal/evidence.py
PYTHONDONTWRITEBYTECODE=1 python3 reviews/wuwa-native-migration/proposal/wuwa.py
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s reviews/wuwa-native-migration/tests -v
```

Do not execute the audit/candidate shell wrappers (even `--check`), publisher main,
service templates, real-game tests or any deployment commands. `bash -n` is syntax
inspection only. Patches are intended for isolated review/dry-run against snapshots,
not direct application to live paths. See `verification.log` for patch/syntax checks.
