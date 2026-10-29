# Actual PRE-SR three-pass NR — combined implementation and runtime results

This extends the earlier separate-branch FINAL_RESULTS.md. The combined route
has now actually been implemented and run in Cyberpunk2077; it is not a3x estimate.

## Configuration

Cyberpunk2.31 / RTX5090 / GE-Proton10-34. Output6144x3456, input/render4096x2304,
ordinaryDLSS Quality, path tracing ON, RR/FG OFF. Same original NR controls as the
previous runs. Three independent persistent Feature18 histories process raw
`base -> A -> B -> A` at4096x2304. One HDR luminance composition then supplies
signedSR, which produces6K. No post-SR NR is called.

| Route | NR GPU mean | Benchmark averageFPS | Peak GPU memory MiB |
|---|---:|---:|---:|
| Combined branch, PRE-SR1 |7.600ms|20.569|23016|
| Combined branch, PRE-SR3 |23.243ms|15.361|25178|
| Previous POST-SR3 reference |51.530ms|10.493|29108|

Three-pass per-layer GPU means: **7.694 /7.736 /7.814ms**.
NR GPU time is about54.9% lower than the previous post-three-pass reference;
whole-benchmark FPS is about46.4% higher. Those are first-run comparisons, not
statistically repeated or quality-equivalent claims.

## Genuine execution / correctness receipts

-1-pass regression:1594 NR calls and bound/restored inputs; one build-only
 creation frame, all1595 signedSR calls successful, post mode0.
-3-pass:three distinct successful Creates with actual command-list-execution
 acknowledgements before use. Three build-only unbound frames, then **1227
 completed three-layer frames,3681 actual Feature18 calls**. All1227 Color
 binds/restores succeeded; all1230 original signedSR calls succeeded; post mode0.
- GPU timing rows separately record Create/setup and per-pass inference,
 attempted/successful/completed passes and cumulative per-layer counters.
 NR numbers above use valid completed rows after the first8 invocations.
 They are Vulkan timestamps, not CPU recording durations or MFG FPS.
- Both runs completed, no kernel NVRM/Xid events were observed, and the normal
 production components/settings/controls/markers were restored after game exit.
 Final owned-file and signed/loader hashes match the initial pre-lab baseline.

## Evidence and limitations

- `runs/20260909-091332-presr-multipass-1`
- `runs/20260909-091545-presr-multipass-3`
- `PRESR_MULTIPASS_RESULTS.json`: complete counters, dimensions and timing means.
- `PRESR_MULTIPASS_RESTORATION.json`: final restoration checks.

Each benchmark includes three bounded window-only screenshots. The checked
three-pass35s capture is an actual rendered benchmark scene, not an empty output.
Screenshots are not synchronized to the same game frame between runs and X11
tearing also exists in the original baseline. Do not use these few images to
claim3passes look better, exact image equality, or indefinite temporal stability.
No raw capture was requested. Run clean no-image repetitions for fine performance
comparisons and matched-frame captures for future quality evaluation.

## Candidate

`presr-multipass/copies/presr-multipass/`

- Router SHA256: `e42f19d60bc627414e2c2f6028c853fcb351896aa14ee1fb6121f5b4ef72e513`
- Service SHA256: `c54cc38b94d81fdb9e5baaaaede22926a6b9b7ee03321de630659828a921a91c`

Control: `DLSS5_PRE_PASSES=3`, process-lifetime latched; use the existing
`run_case.py --presr nr` marker/restore workflow. Source and attribution remain
in the independent`presr-multipass/`branch. The router preserves ABI-v2 and the
verified MSVC slot1 Color setter. `nr_evaluate_count` now explicitly counts the
sum of actual Evaluate calls across layers, not completed frames.

No experimental candidate remains installed. The previous8-run report and its
hash manifest were intentionally left as historical evidence.
