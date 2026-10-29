# Cyberpunk2077: independent multipass NR and true Pre-SR NR

User requested two parallel implementations using actual community code, then
Cyberpunk2077 tests. Work is isolated here; original bridge/router projects and
Minecraft/WuWa/HSR deployments are not modified. Two workers own`multipass/` and
`presr/` independently. Main owns the single5090 benchmark runner; simultaneous
GPU benchmark processes would invalidate comparisons and are not used.

## Source references

- wilsjo2/OptiScaler-DLSSNR-PreSR-Multipass,
  ec96f42f8d32a4fc82f7c4558c0ed12a9f90d853: per-pass persistent histories,
  padded-origin-zero resources, truePreSR for ordinarySR; RR forcePost.
- matiasLombo/neural-upstream,
  c06c07b27c3c5af0d916c3d9545434735d624bdf: pre-original-Evaluate Color binding,
  restoration and HDR luminance-gain composition.
- Local references under`/tmp/nr-presr-static-PgXuk8`; prior audit under
  `benchmark_logs/dlss5-presr-static-20260908`.

The older in-tree PreSR prototype is NOT accepted evidence: on2026-08-31 it
produced stale/repeated Cyberpunk regions even in copy/codec diagnostics. The
new branch must demonstrate correct data flow rather than merely enabling it.

## Test configuration and first baseline

Original game settings were6K/DLAA/path tracing, RR OFF, FG OFF. Tests preserve
6144x3456 output and path tracing, temporarily select ordinarySR Quality with
RR/FG/dynamic-resolution OFF. Every run restores original settings, service,
router, D5LC controls/status and existing logs after the game has exited.
Signed SR/RR/FG/NR and loader DLL hashes are checked unchanged. No global
wineserver kill, clock/power edits, save/account modifications or raw recording.

`run_case.py` uses a process lock, bounded240s lifetime,31,000MiB VRAM guard,
0.5s NVML samples, and three explicitly bounded window-only JPEG screenshots.
Screenshots can perturb frame pacing, so these are first functional benchmarks,
not pristine final performance runs; use`--no-images` for clean repeats.
Restoration evidence and per-case rollback bytes are in each`runs/*/before`.

First baseline `runs/20260909-072816-baseline-sr-quality-nr-off`:

- Game2.31, actual6144x3456, DLAA false, DLSSQuality2, RR false, FG off, PT true.
- Router input/render4096x2304 -> output6144x3456;1928 signedSR evaluations,
  no RR evaluations. Controller explicitly disabled Feature18.
- Official benchmark1616 frames/64.2395s,25.1559 averageFPS.
- Peak sampled VRAM21,892MiB. No new kernel NVRM/Xid events.
- Three window JPEGs obtained; first checked visually as actual benchmark scene.
- Original owned files restored byte-for-byte, signed/loader DLLs unchanged.

## Acceptance

Multipass: same binary/settings for1/2/3 passes, independent Feature18 histories,
actual neural dimensions reported separately from6K output, all layers must
succeed before final commit. Do not infer linear cost/VRAM scaling.

PreSR: low-resolution scene -> NR -> signedSR; original params restored, no
hidden post-NR. RR remains bypassed for pre-processing. Require a clean transport
or codec-only test before interpreting real NR output. Do not call it PreSR if
it is actually SR -> downsample -> NR -> upscale.

Both need real Create/Evaluate and output/visual evidence, not load-only success.
Use Vulkan GPU timestamps only when correctly scoped; CPU recording duration,
MFG FPS and the benchmark's total frame time are not isolated NR GPU time.
At task end restore production baseline rather than leaving an unaccepted lab
binary in the game. Accepted candidates can be deployed separately if requested.

## Completed real-game reproduction

Both branches passed the actual2077 run matrix; see [FINAL_RESULTS.md](FINAL_RESULTS.md), RESULTS.csv and RESULTS.json. Production components/settings were restored.
