# True pre-SR Feature 18 multipass candidate

This directory combines the GPU-validated `../presr` signed-SR seam with the
independent-history/raw-ping-pong design from `../multipass` and
wilsjo2/OptiScaler-DLSSNR-PreSR-Multipass commit
`ec96f42f8d32a4fc82f7c4558c0ed12a9f90d853`.

## Processing contract

For `DLSS5_PRE_PASSES=N` (`1..3`, clamped, default `1`, latched for the process):

```text
current input Color active rectangle (for example 4096x2304)
  -> compact immutable original
  -> HDR encode once to immutable neural base
  -> pass 1: base -> A       (persistent Feature 18 history 1)
  -> pass 2: A -> B          (persistent Feature 18 history 2)
  -> pass 3: B -> A          (persistent Feature 18 history 3)
  -> HDR luminance composition once against original/base
  -> temporary Color bind -> signed Feature 1 SR -> immediate Color restore
```

The final bind occurs only if every requested evaluation and Vulkan interop
completion succeeded. Invalid contracts, build-only creation calls, pending
creation submission, and failures leave the game's Color, its arrival state,
and SR parameter metadata intact. The router rejects Feature 13/RR and disables
the ordinary post callback whenever pre-SR is requested. The dedicated service
exports no `DLSS5_PostEvaluate`.

Each pass has a distinct handle/reset/history plus cumulative Create calls,
Create successes, Evaluate calls, Evaluate successes, and completed-frame
counters. A completed frame is counted for every requested layer only after the
whole stack and `EndVkCommandBufferInterop` succeed. ABI-v2
`nr_evaluate_count` is the cumulative **sum of actual EvaluateFeature calls**
across layers, including a failed call; it is not a success or complete-frame
count.

Feature creation is one missing handle per build-only invocation. A handle is
not used until ReShade API 18 reports execution of the exact native command
list that recorded its creation. A later service callback is not treated as
submission evidence. Feature-contract or raster changes reset/release all
histories only after `vkDeviceWaitIdle`; raster rebuilds then invalidate views,
descriptors, and owned surfaces.

## Build and test

```bash
make -C router all
make -C service presr-multipass
make -C tests clean check
```

The timing-enabled service writes real Vulkan timestamp intervals to
`dlss5-gpu-timing.csv`. `feature_create_ms` is separate.
`feature18_pass{1,2,3}_ms` and aggregate `feature18_ms` contain only actual
inference calls (including required inter-pass GPU barriers). Create-only and
codec-only rows report `feature18_ms=0`; router `cpu_record_us` is CPU command
recording time and is not inference.

## Benchmark handoff

Use the packaged matched pair after a cold settings-restored launch:

```bash
cd ..
python3 run_case.py presr3 --presr nr \
  --service presr-multipass/copies/presr-multipass/01-dlss5-presr-service.addon64 \
  --router presr-multipass/copies/presr-multipass/00-dlss-ngx-router.addon64 \
  --env DLSS5_PRE_PASSES=3
```

The intended validated contract is output `6144x3456`, input/work/guides
`4096x2304`, path tracing on, RR and FG off. Build/source tests prove neither
runtime success nor image quality; the main benchmark worker owns GPU testing.
Artifact hashes are in `copies/presr-multipass/SHA256SUMS`.
