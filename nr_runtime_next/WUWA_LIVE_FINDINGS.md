# WuWa native live acceptance — 2026-09-10

## 16:05 update: POST5 works in Ultra Performance, Quality remains blocked

Run `wuwa-runs/20260910-155322-native-post-5-initial-off-physical-user-operated`
has 126 active POST5 receipts, five independent handles/one Create each,
1,235 successful Evaluates per layer recorded (1,233 per layer in active
receipts), 613 completed samples and last completed frame4495. The user later
identified the successful setting as Ultra Performance and said it is too blurry.
This is NOT Quality-mode acceptance or a picture-quality recommendation.

User hot-switched to Quality: state became `budget_exceeded/frame_budget_limit`.
Last10s before NR used10369–10402MiB; active whole-GPU samples23608–24151MiB;
after Quality rejection14527–14569MiB. These are changing-scene samples, not a
controlled allocation-peak calibration. The arithmetic suggests investigation
is worthwhile, but does not prove Quality+POST5 fits safely. Status byte fields
after rejection are stale prior-chain values, not the new Quality preflight.
`QUALITY_SWITCH_FINDINGS.json` and `MAIN_POST5_VERIFICATION.json` preserve scope.

Normal time-limit exit and all owned/signed baseline hashes/no game were
independently verified at16:05. No Main SR/RR/resolution, swap or budget-protection
changes. User wants Quality, not a downgrade to make the test pass. An isolated
CPU audit in `reviews/wuwa-quality-post5-budget/` is reviewing estimates,
resize/residency accounting and missing preflight diagnostics.

## POST2 verified scope (14:55 cold check)

Physical user-operated RR POST2 now passes, in addition to the original POST1 case.
`wuwa-runs/20260910-144823-native-post-2-initial-off-physical-user-operated/MAIN_POST2_VERIFICATION.json`
records 100 active receipts, independent handles `[1,2]`, one Create per layer,
**1,891 successful Evaluates per layer (3,782 total)** and **632 GPU-completion
samples observed across OFF/ON segments**, last completed frame8633. OFF then ON
was acknowledged and recovered active execution with new completion proof.
Native three-DLL route, no ReShade; current-output/deferred-commit source and
package are pinned by the frozen candidate and retained active binaries.

The recovery publisher captured the fresh login at14:49:38 and opened after
15 seconds at14:49:53. This successful run did not exercise a read-failure
recovery branch; actual SQLite-lock tests prove that branch separately, not
that the earlier live failure was caused by a lock. Main also closed the
legacy reader's SQLite connections explicitly without changing its read-only SQL.

The test inherited physical desktop/game settings, with no forced resolution,
automatic input or screenshots. Runtime status lacks dimensions, so this report
does not claim a separately measured pixel resolution. NR was temporarily set
with internal upscaling0; game SR/RR was unchanged. It ended normally at the
360-second limit; fresh14:55 cold check verified no game and every owned/signed
baseline hash, original phase service and controls restored.

**Still unverified:** ordinary SR/PRE, higher layer counts, permanent frontend
migration, long stability and image-quality improvement. No claim of full
1–10-layer/both-order WuWa support is made.

User subsequently clarified they did not observe the image or notice the NR
toggle. POST2 acceptance is therefore execution/completion-path verification
only; there is **no user visual acceptance or confirmed artifact-free result**.

## Original POST1 result

The same owned three-DLL native chain (pc4) reached real WuWa D3D12 Feature 13
RR, normalized current formats, and executed POST NR/1 in a live scene without
ReShade. This is **one tested order/count/resolution**, not all requested modes
or a picture-quality/stability claim.

- Actual runner from the latest retained Steam launch was **dwproton-11.0-4**;
  the manager profile's GE-Proton10-34 path was stale. The test used the existing
  `Wuthering Waves.exe` root launcher, not a protected-startup shortcut.
- Headless Gamescope 1920x1080; existing RR and graphics settings retained.
- Owned DXGI factory observation supplied real queue/device coverage despite
  the main EXE lacking a D3D12CreateDevice import. NGX hooks and production
  NR/vkd3d compatibility probe succeeded; WinVerifyTrust accepted the game EXE.
- Fresh login transition + 15-second publisher settle opened the native lease;
  NR stayed OFF until Main saw the actual world scene.
- In `wuwa-runs/20260910-090652-native-post-1-initial-off-1920x1080`, the last
  retained sample shows **1,781 successful layer Evaluates**, one independent
  handle / one Create, **890 GPU-completed samples**, last completed frame 9845.
- Real final compositor screenshots retained, including `view-335s.jpg/.png`.
  The picture changed substantially; no same-source quality reference or
  temporal flicker analysis was captured, so no improvement claim is made.

## Control discovery

The legacy on-disk D5LC had `NREnableUpscaling=1`. New same-size native layers
require zero; enabling NR initially produced the correct unsupported receipt
and zero NR calls. Main then explicitly set that one temporary NR scalar to 0,
without changing the game's SR/RR. It acknowledged and became active with actual
completion proof. Original D5LC bytes were restored afterward. Future test
fixtures explicitly use internal upscaling 0; the manager tooltip explains it.

The preceding `090040` run validated launcher/queue/NGX/format-probe/lease and
world rendering, but **ran no NR**. Its late `action.json` NR-enable request was
not consumed before the bounded deadline; only the connect click is in its
executed action log. Do not count it as NR success.

## Safety/restoration

Both finished runs report `owned_restored:true`, `signed_unchanged:true`, old
phase service restored active, and display DB still `PcResolutionIndex=0` /
`PcWindowMode=0`. No test code wrote the SQLite database, account/save files,
protected components, or hardware. Normal game login updates were not rolled
back. Only temporary display INI/owned DLL/control/lease files were restored.

Logs retain an unimplemented `ntoskrnl.exe.PsGetProcessExitStatus` exception from
the Wine launch environment. No stub, protection, or driver was patched or
bypassed to continue: the normal game launcher reached its normal connect UI
and accepted the normal connect action. The exception is not silently omitted
or attributed to NR (NR was off at that point).

## Later POST/10 attempt did not reach NR

`wuwa-runs/20260910-092212-native-post-10-initial-off-1920x1080` encountered a
fatal game error after connecting, while NR was still OFF: zero layer Creates,
zero Evaluates and zero completion samples. The retained minidump identifies
an access violation reading address 9 in the game's
`ThirdParty/KrPcSdk_Global/libcrypto-3-x64.dll + 0x363915`. This locates the fault
but does not prove its initiating cause or exclude indirect interference.
It is **not** evidence that ten NR layers executed or caused an OOM. No crypto,
anti-cheat, or kernel component was changed to work around it. The runner
reported launcher/game exit and restored owned/signed baselines and old gate.
Supplemental crash files/hashes are under that run's `crash-evidence/`.

## Still pending

- WuWa multiple layers and actual ordinary Feature-1 PRE.
- Longer/moving-scene visual stability; prior 6K NR anomalies are not resolved by
  this 1080p result.
- Production migration and user choice of compatible live controls/settings.
- HSR transport/Guardian/view/AppID and PRE remain separate, unverified work.

See per-run manifests, maps, control/status JSONL, actions, screenshots, GPU logs,
restore records and hashes. Original WuWa router/service hashes remain the
known production values; no permanent native migration was performed.

## 2026-09-10 physical POST2 follow-up (14:33 cold-verified)

Neither physical attempt extends the existing positive RR POST1 acceptance.

- `wuwa-runs/20260910-142151-native-post-2-initial-off-physical-user-operated`: user entered world; phase publisher opened. Main requested NR ON, but runner attempted to JSON-serialize the frontend `ControlResult` dataclass and raised at14:25:15, triggering cold rollback. This was a test-runner error, not a demonstrated game/NR crash. No two-layer completion evidence was obtained. Fixed action-event serialization with `dataclasses.asdict`, preserving acknowledged/written/failure distinctions. `tests/test_wuwa_action_receipt.py` tests the actual frontend result type.
- `wuwa-runs/20260910-142653-native-post-2-initial-off-physical-user-operated`: live OFF and ON controls both acknowledged and logged correctly (ON seq1789021772613416101). Runtime remained local-policy `gate_closed`, RR POST2 requested, 0 handles/Creates/Evaluates/completions. An acknowledged control request is not active NR.
- The second publisher logged two `phase.disable.game-started` events for the same PID799576/start22206176 and no login-scheduled event. Read-only check14:30:25 observed LoginTime1789021679.577476 (14:27:59), challenge file mtime1789021629.1857624 (14:27:09). Current logs do not identify why its baseline was reset; transient read failure is a hypothesis, not a proven root cause. An isolated CPU review in `reviews/wuwa-publisher-recovery/` is investigating fail-closed recovery without database edits or policy bypass.
- Second run ended normally at its time limit. Fresh14:33:22: inactive/MainPID0/no game; all owned and signed hashes match baseline, original phase service active, temporary NREnableUpscaling restored. `MAIN_COLD_RECHECK.json` exists in both runs.
- Both runs used the physical desktop/user input, existing resolution and SR/RR, with no automatic screenshots/clicks/keys and no account database writes by the runner. No gate was overridden. Candidate/source freeze: `reviews/wuwa-main-physical-20260910-142015/` (receipt-fix source also retained there).


## 20260910 174229 Cinematic raw2 POST5: user sees no useful improvement

Explicit isolated Cinematic package/controller used raw2, all four NR strengths2, HDR transfer0.6, other calibration/mask/preset unchanged, Quality POST5 zero-extra-reserve/no-time-limit. Last active sample shows five independent handles, each3041 Evaluate calls,1028 completed samples. This is execution evidence ONLY; no per-layer pixel proof or improved final image. User: “没看出来啊,更白了” and “5层看起来=一层”. Focus now dataflow/NR convergence/final HDR delivery, not blind setting changes.

At17:49:55 telemetry reached31285MiB, above retained31000MiB global VRAM guard; runner stopped with fault/global VRAM guard exceeded, NOT time limit or proven actual OOM. RESTORED.json and Main independent MAIN_COLD_RECHECK.json verify no game, all owned/signed hashes restored. Do not relax guard silently.


## Offscreen same-chain image verification1828–1830

Userauthorized image-through-owned-chain test. See reviews/cinematic-image-main/RESULTS.md. Exact cinematic runtime produced different POST1/POST5 pixels for portrait and retained WuWa still, including actual6144x3456 inference with4099x2306 synthetic guides. Two small-image frames were captured at S/B/P1..P5/D; D equals actual native output and diagnostic equals unmodified baseline byte-for-byte.6K mainly changes brightness/shading; useful visual goal remains unaccepted. NOT actual game temporal-guide/FormatBridge/Present proof. Several lab processes stalled after fenced successful image output; optional fast-fenced-exit later skips DLL detach, NOT teardown fix. All private prefixes stopped, no game or game-file changes; FINAL_EXTERNAL_RECHECK.json.


## Autonomous virtual PRE3 fixed and verified214618

See reviews/WUWA_PRE3_RESULT_20260910.md. After user authorized virtual/screenshots/autonomous research, actual GPU game diagnostics identified ordinarySR Depth resource19 incorrectlypairedwithview41 (Color10/MV34correct). Isolated strict19->ownedSRV21fix passedCPU andownedGPUdepth/stencil/crop/state/fencechecks. Virtual6KQuality PRE3 then reached228active receipts, handles1/2/3, oneCreateeach,6003Evaluateeach(18009total), successfulOFF/ON/currentGPUcompletion. No hard error/unsupported/budgetstatus. Selectedchainthroughput~22/s is NOTPresentFPS; peak sampled22332MiB. No usefulvisualquality/longtermacceptanceclaim. Voluntarystopafterverification; allowned/signedhashesandEngineRR1 restored, unitinactive. DefaultMain/release/deploymentnotautomigrated; sourcefixretainedinexactcandidate.
