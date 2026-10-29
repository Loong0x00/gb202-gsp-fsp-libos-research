# Autonomous WuWa PRE3 result — 2026-09-10

## Outcome

**Fixed the immediate ordinary-SR/PRE ingress blocker in an isolated candidate; real virtual-game PRE3 execution, OFF/ON and cold rollback passed.** No claim of useful visual improvement, high/steady FPS, artifact-free rendering, permanent migration or broad long-term acceptance.

User explicitly authorized autonomous investigation, screenshots as needed, and virtual displays before this work. No credentials were entered or account DB written by tools. Normal saved-session connection was clicked in the virtual game; game-owned login writes were left intact. No global network/hardware settings changed.

## Root cause — not Color and not insufficient memory

Diagnostic run `wuwa-runs/20260910-212737-native-pre_sr-3-initial-off-6144x3456/MAIN_NORMALIZE_FAILURES.jsonl` captured eight real failures before allocation/NR work:

- ordinary SR, PRE, requested3, active render4099x2306, output6144x3456;
- Color resource/view10/10 (RGBA16F),4100x2308, correct;
- MV resource/view34/34 (FLOAT2),4099x2306, correct;
- **Depth resource19 (R32G8X24_TYPELESS),4100x2308, but caller requested view41 (R32_FLOAT)**;
- concrete plan reason `unsupported_format`; format-pool budget fit.

The old WuWa normalizer reused the RR pure-R32 depth contract after switching to ordinary SR. Correct owned view for that resource is **21 (R32_FLOAT_X8X24_TYPELESS), depth plane0**, excluding stencil. This explains PRE not starting; it does **not** explain poor visual benefit of the earlier RR POST5 runs, which used a different valid depth contract.

## Fix / isolated scope

`reviews/wuwa-sr-depth19-fix`: shared strict depth selector, host owned-SRV selection and truthful resource evidence, narrow WuWa adapter/format validation, CPU regressions. OrdinarySR19/21 accepted; wrong19/41, stencil22, DSV20, unknown resources and RR19 rejected. Existing41/41 and HSR contracts preserved. Color contract, NR shader/model, all guards, default reserve, Style2 and frozen public ABIs unchanged.

The view21 is **created by our normalizer**; this does not claim observation of a game-created SRV. Actual game GPU resource states are still declared at the integration seam, not independently queried.

Main immutable candidate:
`reviews/wuwa-pre3-depth19-main-20260910-214528`

- package manifest SHA256 `03ba45bed51c8e1a463ebc97041fab1b507a41827adc9360245f4b9896c991d0`
- host `087f492a2ea068888e420a9d5f2a22dbff754e7f150d803a2c309d5317446b3e`
- unchanged runtime `9e0154fac9d821f9d51a18e7fe163114e12b9f0924e93e7bb724aeb3bf80caaa`
- unchanged DXGI `f266b6d89e4df02bf6cc763fa09cb05d4e216a1b3764457fb484a27771015061`

Default Main native/adapter development sources and accepted releases were **not overwritten** by this candidate. Main runner/tests gained explicit virtual PRE3, exact package pins, shared fresh-SR confirmation and reversible startup-RR override. No automatic selection of this candidate for normal game launch.

## Verification ladder

1. CPU: old frozen validator rejects actual19/41 and legal19/21; new validator accepts only legal ordinary-SR19/21. Existing policy/format/ABI checks and negative controls pass.
2. Owned GPU fixture `reviews/wuwa-depth19-gpu-main/runs/20260910-214251`: actual forwarded SRV21, depth.375, stencil9 excluded, MV(.5,-.25),32x20/active31x19 including shifted crop, input-state restoration, exact fence-before-readback. Wrong19/41 records no commands/SRVs/allocations. **Fake NR producer, no SR/game**, D3D12 debug layer/GBV unavailable. Earlier214043 attempted fixture rejected19/21 after a staging/build mismatch; failure retained. Current fixed executable/hash was reselected before the successful test; no game test preceded that success.
3. Virtual game `wuwa-runs/20260910-214618-native-pre_sr-3-initial-off-6144x3456`: actual ordinarySR,6K output/Quality4099x2306, NR initiallyOFF, then fresh cold-override SR confirmation, then NR enabled after normal login gate. PRE3, Style2, strengths2, transfer0.6/color1, mask1, paper/MV1, **normal reserve** (about2.91GB), no fixed game timeout.
4. Real execution: **228 active status receipts**, handles1/2/3, one Create each, **6003 successful Evaluate calls each =18009 NR calls**. Original SR result/parameter-restore and GPU completion checks passed as required by active state. OFF→ON retained distinct contexts and regained current-epoch completion; second epoch's last sampled completion count879/frame17376. Counts are not a claim of per-pixel quality.
5. No error/unsupported/budget-exceeded status in fixed game run. Five telemetry samples caught `awaiting adapter signed-SR commit acknowledgement` in flight; these are not presented as uninterrupted active receipts. Four disabled receipts correspond to explicit OFF controls.
6. Screenshots show world/UI before/after activation; camera/animation differ, not a same-source visual comparison. Startup took time; early background-only screenshots are not evidence of an invisible-UI bug.

Sampled global VRAM reached **22332MiB**; early active samples around20829MiB. Full-chain Evaluate throughput in longer sampled segments was approximately22–22.45 per second, **not a Present/base/FG FPS measurement**. GPU cost remains substantial; no performance success promise.

## Cleanup

After verification, Main explicitly disabled NR and requested stop (not a duration timeout). Unit became inactive/Resultsuccess. `RESTORED.json` and independent `MAIN_VERIFICATION.json` verify:

- all16 owned entries restored/removed as originally present;
- five signed-file hashes unchanged;
- no game PID;
- Engine.ini exact original restored, including `DenoiserMode=1`;
- normal display/Quality configuration restored and old phase service restored;
- no game/account/position saves rolled back.

The prior210228 game's automatic removal of its Accessibility section was preserved by the scoped RR rollback rather than overwritten; that distinction is documented in its own cold check. Current final214618 Engine.ini matches that run's baseline exactly.

Evidence is retained in the run, especially `MAIN_VERIFICATION.json`, `OFF_ON_PROOF.json`, `MAIN_LAST_ACTIVE.json`, `actions.json`, `startup-rr-override.json`, status/budget logs and virtual screenshots. The GUI/default installed backend is not silently switched to this experiment.
