# Owned GPU calibration proposal — NOT executed here

## Goal and stop rules

Measure the actual **five-layer POST NR incremental peak**, separately for the exact Ultra and Quality guide shapes, with **Quality SR + RR / POST5** remaining the product target. Ultra is a laboratory comparison only. Do not change the user's game mode to work around a refusal; do not start NR in a game against the existing guard.

Main must review/authorize and own the future GPU runs. This review only produced CPU fixtures and an unexecuted diagnostic host DLL. It did **not** produce a signed-NR GPU harness, executable GPU acceptance result, or evidence that Quality fits.

Use an ordinary owned test application and legitimately available signed NR/runtime components, not an impersonated game/protection environment. Do not alter executable integrity, leases, protection state, DB/network settings, or signed DLLs to admit a harness. If the existing owned test stack cannot initialize legitimately, stop and resolve its supported initialization path; do not fabricate game capability/completion evidence.

## Freeze inputs before any allocation test

1. Archive frozen hashes from `AUDIT_INPUTS.json`; include the real signed NR DLL and its model/assets, driver, DXGI/vkd3d/Vulkan stack, and any SR/RR binaries used by the owned reconstruction harness. Record verified signature, exact loaded path and SHA256, not just filename/version.
2. Both compared trials use the **same binary set**: frozen native runtime hash `b73c492ec88b45055132c96e0a7fcd9d24158e37933ee4b3408d070afea15593`, same host/harness version, same signed NR/models. If the diagnostics candidate host is used, use that exact candidate in both trials and explicitly label its difference from the historical frozen host. Never compare a recompiled optimized runtime against the old Ultra result and call it calibration.
3. Obtain actual Quality and Ultra render/guide extents plus common output/work extent from trustworthy owned input metadata or future authorized preflight receipts. Existing run155322 does not supply these. Do not derive Quality dimensions from the stale status estimate or assume a menu ratio. An owned synthetic size sweep is useful, but label it synthetic until matched to actual extents. No need to hot-switch the live game merely to reproduce an unsafe allocation attempt.
4. Freeze all NR scalar controls: intensity/local tone/local structure/skin structure, preset/style, masks/UI correction, depth/inversion/source flags, motion scaling, paper-white/codec transfer/color controls, exposure/jitter/reset pattern, and upscaling control. Preserve the exact `runtime/pipeline.cpp::configure` create/evaluate/callback contract, including the POST 0.5 create hint, 1.0 callback and `PerfQualityValue=0`. Those are not adjustable calibration knobs. Hash a normalized scalar JSON and the deterministic input sequence. The only intended paired difference is guide/render shape and shape-appropriate input resources; output and five passes stay fixed.

## Instrumentation and memory definitions

Use the owned harness to timestamp allocation/submit/retire milestones **outside** the unchanged runtime, and sample:

- In-process, same-LUID `QueryVideoMemoryInfo(0, LOCAL)` Budget, CurrentUsage, CurrentReservation and AvailableForReservation. Query the same API used by admission; do not replace this with total device occupancy.
- Device-wide memory from an independent existing collector, with sample times and cadence (~20–50 Hz if affordable), plus background-process baseline. Sampling gives a sampled peak, not guaranteed sub-millisecond allocation high-water mark. Use available noninvasive allocation tracing/high-water counters if the owned stack supports it; otherwise quantify this uncertainty and do not reduce the safety margin from sampled peaks alone.
- Exact D3D `GetResourceAllocationInfo` sizes for each harness/bridge texture, and FormatBridge owned byte count, slot dimensions and in-flight count. Include cached free slots. The runtime's five chain work surfaces + two guide surfaces are distinct from bridge textures; Vulkan imports are aliases, not duplicated textures.
- Five distinct returned handle IDs/create counts, per-layer Evaluate counts, post-forward submission acknowledgment, and completed fence samples. Successful recording or Signal alone is not completion. Retire/free milestones must be distinguished from mere Retire request/active_chains decrement; the frozen query excludes retiring chains and cannot prove their memory is gone.

If physical signed-NR allocation tracking is unavailable, report a **measured whole-stack incremental delta with background uncertainty**, not exact internal history bytes. Compare DXGI deltas with device-wide deltas to establish whether the deployed DXGI/vkd3d accounting includes NR's private Vulkan allocations before trusting residency deductions.

## Trials A/B: isolated, cold, five-layer increments

Run without the game and with stable, low unrelated GPU usage so the unchanged guard can admit the requested five layers safely. Use a new process for each trial to avoid opaque allocator caches/retiring owners. Alternate trial order (Quality, Ultra, Ultra, Quality), at least three successful cold repetitions per shape. All repetitions use the same binaries/scalars.

For each shape:

1. **T0 — empty owned baseline:** initialize device/queue/runtime compatibility only; no NR private chain. Record 10 s stable budget/usage and background.
2. **T1 — input + bridge baseline:** allocate the owned source/motion/depth/output at the recorded shape; normalize enough owned frames to exercise the four-slot bridge pool without any NR allocation. A legitimate disabled runtime probe allocates no NR histories. Actually submit/fence/retire these frames; retain cache as in production. Record sizes/counts and 10 s baseline. Disabled-probe evidence remains disabled, never completion of NR.
3. **T2 — five-layer cold admission/create:** call the unchanged POST5 runtime with its normal budget guard. Capture the fresh admission receipt. If any guard refuses, **stop that trial** with all requested/charged/available terms; no reduced reserve, forged residency, lowered output quality, fewer passes labeled as five, or direct signed-NR bypass of a rejected runtime. Create both render-shape trials only when the owned environment genuinely has safe headroom.
4. **T3 — acknowledged create, then five evaluations/frame:** submit/Signal correctly, then run a fixed deterministic sequence long enough to expose lazy workspace/history allocations (e.g. >=600 fully evaluated frames and >=100 actually completed fence samples, plus a 30 s stable plateau). Exactly five handles, one Create each, no shared history/parameter identity, one Evaluate/layer/frame. Preserve the frozen codec/NR controls. An error, missing completion, residency fault or approaching guard margin stops the trial without unsafe early freeing.
5. **T4 — safe retirement:** stop new submissions; forward all already recorded lists, observe their real fences, request retirement and independently establish eventual resource release or end the owned process normally. Never fake a fence/completion value or release resources still in use. Record post-retirement and post-process usage. Persistent residuals belong in the report, not silently subtracted as freed memory.

Report, per trial and accounting source:

```text
bridge/input increment = T1 baseline - T0 baseline
NR5 create increment = max sampled usage during T2 - T1 baseline
NR5 warm increment = max sampled usage during T3 - T1 baseline
NR5 total peak increment = max(T2, T3) - T1 baseline
post-retire residual = T4 plateau - T1 baseline
```

Use paired baseline variability/error ranges, not subtraction of unrelated minima/maxima. The NR5 increment includes runtime-owned surfaces, five signed NR histories/workspaces, views/descriptors and driver overhead. It excludes already allocated bridge/input baseline but includes any **additional** bridge growth after T1; track and report that separately rather than assuming it is zero. A derived `NR5 increment - actual runtime surface bytes` is only an estimate of private NR+overhead, not a tensor-memory measurement.

Compare `ΔNR5_Quality - ΔNR5_Ultra` with the model's `Δsurfaces + Δhistories`; at fixed POST output/pass count the model predicts `Δhistories=0`, but the signed implementation may depend on guide dimensions. Preserve both creation and warmed peaks.

## Trial C: controlled lifecycle discrimination, not forced overlap

Only after A/B characterize both shapes and sufficient **measured plus conservatively reserved** headroom exists:

- First test **serial release/recreate**: finish/fence/retire Ultra owner, prove resources released, create Quality owner. This distinguishes a persistent model refusal from overlap with an old chain. Process exit/restart is a valid clean reference, but not a test of hot rebuild.
- Then optionally test **different-owner hot rebuild** in the owned process, retaining old-chain work only as normal lifecycle requires. Query before every new allocation. If the unchanged guard refuses, preserve the receipt and allow normal retirement; do not force the overlapping allocation. Compare old/new owner IDs, preflight usage and refusal-to-release timeline against the serial case.
- A **same-owner shape mutation** should invalidate adapter admission and fail the frozen runtime's mismatch check if reached; it is not a supported automatic rebuild. The CPU fixture covers the admission model; do not claim the runtime should allocate a second same-owner chain. Any lifecycle fix is a separate reviewed change, not part of this diagnostics patch.
- Format slot measurements should distinguish compatible reuse, free incompatible release-before-create, and busy old slots. A free/cached slot is allocated but not necessarily physically resident. Leave all fence/retirement safety intact.

## Decision gate before any later game validation

A successful owned Quality trial alone does **not** establish game fit. SR + RR Quality's own baseline, scene peaks, VRAM Budget variability, possible cold-rebuild overlap and untracked driver overhead must also fit with the unchanged reserve. The existing ~14527–14569 MiB whole-device plateau cannot substitute for a fresh DXGI process baseline.

Main should first correlate new adapter receipts (real Budget/CurrentUsage/key/NR-charge/format-net/reserve) with runtime admission receipts and owned memory increments. Possible follow-ups, each separate review:

- Proven lifecycle overlap/lost admission evidence: correct lifecycle or ledger with genuine fence-backed residency proof; never set `already_resident=true` just to pass admission.
- Proven estimator overstatement across repeated shapes/creation/warm peaks: propose a calibrated upper envelope with explicit unseen-shape fallback, uncertainty reserve and regression coverage. Do not choose a smaller constant simply because one Quality trial fits.
- Insufficient safe Quality POST5 headroom: report that honestly. Do not force overbudget, silently reduce passes, reduce output/guide quality, or recommend Ultra Performance as acceptance of the requested Quality result.

Future game use, package changes and GPU acceptance are Main's separately authorized work; this worker performed none of them.
