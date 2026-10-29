# Main: real image through frozen native NR chain — 2026-09-10

## Finding

**The tested runtime does not universally collapse POST5 to POST1.** Real GPU pixels differ for a portrait and a retained WuWa RR still. In two captured WuWa frames, all P1…P5 raw stages differ; decoded D equals the actual D3D12 output readback byte-for-byte, and the instrumented result equals the unmodified cinematic DLL output byte-for-byte. This is materially stronger than Evaluate counts.

**This does NOT establish a fix or root cause for the live game's poor benefit.** These are owned offscreen fixtures, no game/SR/RR execution, actual temporal-guide sequence, WuWa FormatBridge R11 conversion, or Present. The still uses synthetic zero motion and constant depth0.375. The actual6K test visually retains the user's main complaint: mostly brighter/changed shading, not an obvious fivefold gain in useful detail.

## Images

- [Portrait input / POST1 / POST5](portrait-baseline.png), 768x768 inference.
- [WuWa input / POST1 / POST5](wuwa-baseline.png), 768x432 inference from an exact8x8 linear-HDR box reduction of retained6K RR input.
- [WuWa S/B/P1…P5/D](wuwa-stages-frame-3.png), two-frame stage evidence in `STAGE_RESULTS.json`. B/P stages are proxy-domain previews; S/D use a fixed HDR preview. Do not compare numbers across domains directly.
- [Original6K input / POST1 / POST5](wuwa-6k-baseline.png), **6144x3456 actual inference**, all previews reduced identically after processing. Not a game-resolution change.

No per-image auto-exposure/contrast normalization or user-game screenshot was used.

## Exact configuration and evidence

Frozen runtime SHA256 `5b4f8afd1b545cad6d4f3ccbfd089c02b2cf0ff79d7bbfdb9277e74d98e508ba`, the same runtime used in the live cinematic trial. Style raw2; intensity/local tone/local structure/skin structure2; mask1; preset0; HDR transfer0.6; color1; paper-white/MV scale1. Each separate process cold-latches POST1 or POST5; input is restored every frame and **BEFORE GPU readback must exactly equal input bytes**. Outputs are mapped only after their own exact real D3D12 fence completes. Separate handles/counts and submitted receipts are also checked.

Diagnostic clone SHA256 `deb605d45247f91ce5ecec8b463fe33ce9527337fc8e82c87b9eb8662f599e5b` inserts immediate per-layer READBACK copies before ping-pong overwrite; exact-fence background dump, two attempts, one staging bundle. It changes interop boundaries, so the byte-identical unmodified baseline comparisons are important. It is not deployed in games.

Primary captured run: `runs/20260910-182346-wuwa-still-L5-capture`, 768x432 Color /512x288 guides. Captures at D5R frames2 and3 (first and second Evaluate):

| Evidence | Frame2 | Frame3 |
|---|---:|---:|
| S equals exact restored input | yes | yes |
| P1 vs P5 raw proxy RGB MAE |0.0900784|0.0972303|
| CPU composed P1 vs P5 HDR RGB MAE |0.0526828|0.0592248|
| GPU D equals native output including alpha |byte exact|byte exact|
| Diagnostic vs unmodified corresponding output |byte exact|byte exact|

Real core parameter getter observations agree with intended namespaced resources; metadata records each map, handle, wrapper, image/view, Evaluate/reset, list/queue/fence tuple. This is not a signed-descriptor-consumption trace.

`P1_VS_INDEPENDENT_POST1.json`: composing captured P1 on CPU reproduces independent POST1 to numerical precision (MAE approximately7.5e-8 after observed FP16 toward-zero conversion). `CPU_COMPOSE_QUANTIZATION.json`: CPU P5 composition reproduces GPU D at approximately1e-7 MAE; >99.93% exact RGB components after that conversion, p99 error0. This supports the frozen codec math, without claiming universally mandated GPU rounding. Float32-vs-half unquantized max error0.0143 occurs at HDR value17.1393 vs17.125, not a wholesale routing discrepancy.

Full6K runs `182854` POST1 and `182943` POST5 use original retained Color without resizing; guide dimensions4099x2306 match the live Quality dimensions, but values remain synthetic. Both complete two actual Evaluate frames. L1 vsL5 final linear RGB MAE0.0371022, exact component equality0.1434%; fixed8x downsample comparison MAE0.0365930. Corresponding small-image second-frame difference is about0.0592. Resolution changes the observed result/amplitude here, but this does not establish a universal receptive-field or quality explanation. See `FULL6K_RESULTS.json`.

Small-image constant-guide tests at768x432 guides and512x288 guides produce identical corresponding outputs. Thus the Create/Evaluate scaling mismatch did not cause a difference in this particular constant-guide fixture; real nonuniform guides remain untested.

## Harness failures, explicitly retained

- `180750` POST1: all four fenced pixel captures completed, but an overstrict assertion demanded that the runtime's sampled completion record equal the latest frame. The frozen runtime intentionally coalesces samples. Main reviewed harness now accepts a valid sampled frame while preserving exact per-frame harness fences, counts and input equality. No runtime fix/fallback was made.
- `181010`, `181322`, `181407`: GPU work, pixel files and SUCCESS receipt completed, then **process teardown stalled** until the40s isolated lab deadline. These are not clean-lifecycle passes. Original records remain failed.
- Later `--fast-exit` is explicit lab-only TerminateProcess after all GPU copies are fenced, files flushed and result checks complete. It skips DLL process-detach validation; **the teardown issue is not fixed**. `normal_teardown_tested:false` is in receipts. Do not confuse it with a game timer; no game was launched.
- `182235` diagnostic launch was correctly refused by the harness's original frozen-only hash allowlist before GPU work. Main added a second exact hash, available only with the explicit diagnostic opt-in. No generic DLL acceptance.

Signed modules/graphics pins and copied executable hashes are in each run's INPUT_HASHES.json. Hardware Guardian was armed for GPU execution and VRAM<=31000MiB retained. Later successful image-data cases have Guardian exit0. Earlier failure cleanup deliberately terminated only the private lab prefix/monitor. No global Wine shutdown, game install/config modification or other GPU test ran in parallel.

## Local UE

Found `/home/user/.cache/Epic/UnrealEngine/5.7` and UnrealBuildTool configuration. No editor executable found in the bounded common-directory searches performed. This is not an exhaustive absence claim. The native runtime fixture did not require UE.

## Remaining investigation

The new evidence narrows the generic runtime chain/codec/copy path under these fixtures; it does not clear live game inputs, temporal reset/guide behavior, final R11 bridge conversion or game tone mapping/Present. Do not promise that more layers or a new style will improve quality. Preserve this same-source pixel test as a regression before any future code change.
