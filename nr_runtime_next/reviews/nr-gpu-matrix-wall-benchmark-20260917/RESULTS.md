# RTX5090 NR matrix wall/cache benchmark

## Scope

- Original DLL: public512×512 route,50 evaluations, actual CUDA events and wall clock.
- Original kernel breakdown: Nsight Systems over10 public512 evaluations; this is the real N96 path.
- Logical matrix upper bound: resident BF16/FP8 PyTorch matrices with matching dimensions, but **not** source-bitwise arithmetic.
- Cache counters: Nsight Compute on the exact original SM120 CUBIN N64 contract kernel. This exposes the kernel family’s utilization/cache character but is not an N96 counter capture.

## Wall clock

| path | GPU ms | wall ms |
|---|---:|---:|
| Original DLL full71, steady median |4.4182|4.4227|
| Original DLL summed kernels/frame |1.9295|—|
| Original DLL ViT31–38 kernels/frame |0.5475|—|
| Logical resident BF16 ViT8 stack |0.3328|0.3329|

The approximate logical ViT is1.64× faster than the exact original ViT kernel sum, implying only about0.215ms/~4.9% whole-frame gain if ViT alone were replaced. The larger whole-model opportunity is the ~2.49ms gap between summed kernel execution and DLL event/wall duration, plus CPU submission: steady median submit was2.6661ms for156 launches/frame.

## N96 matrix microtimes

| operation | original exact CUBIN | logical BF16 | logical FP8 |
|---|---:|---:|---:|
| Expand96×1024×4096 |~15.77µs/block|7.35µs|5.35µs|
| Contract96×4096×1024 |20.99µs|7.81µs|—|
| QKV96×1024×3072 |16.48µs|5.59µs|—|
| Projection96×1024×1024 |11.89µs|4.22µs|—|
| Attention32h,N96,D32 |3.08µs|5.97µs|—|

These are not numeric-equivalence comparisons: original kernels include source residuals, quantization, normalization and exact rounding. They nevertheless show that the linear kernels leave substantial5090 throughput unused, while NVIDIA’s specialized N96 attention is faster than generic SDPA.

## Transfer hypothesis

Explicit pinned H2D wall/GPU time:

-96MiB:1.751ms;
-140.842MiB (entire model payload):2.582ms.

Such a transfer every frame would be disastrous. It is **not what the measured DLL does**: Nsight recorded exactly153 H2D calls both in the earlier3-evaluation capture and the new10-evaluation capture. The153 copies total6.119ms at feature construction/initialization, not153 copies per frame. The specific “stream all weights each frame for low-VRAM cards” hypothesis is rejected.

## Cache/utilization evidence

Exact original CUBIN N64 FFN-contract counters:

- L1 sector hit rate:46.36%;
- L2 sector hit rate:37.33%;
- DRAM throughput:9.59% of sustained peak;
- tensor-pipe active:5.56%;
- active warps:8.18%.

This is not a DRAM-bandwidth-saturated kernel. Low cache hit rates combined with very low active-warps/tensor-pipe utilization indicate latency/occupancy is poorly hidden. This supports the user’s L1/cache-latency concern more than a VRAM-bandwidth explanation. N96 must still receive its own counter capture before treating the percentages as identical.

## Conclusion

NVIDIA’s unusual layout is not simply useless: its N96 attention is excellent and fusion avoids intermediate traffic. But on RTX5090 the batch1 small-M linear path and156-stage launch/synchronization structure are plausibly negative relative to a Blackwell-specific resident CUTLASS/cuBLASLt + CUDA-graph/persistent implementation. The first optimization target should be launch/synchronization and low-occupancy linear kernels, not host weight streaming.

## Preserved failures/caveats

- First standalone N96 CUBIN timing harness timed out because its guessed standalone launch/counter protocol did not match the public chained protocol; no timing from it is used.
- Nsight Systems wrapper was killed while waiting for re-parented Wine processes, but produced a valid report that was exported afterward.
- First NCU run lacked counter permission; second used invalid metric suffixes; both are retained.
- Direct NCU child capture of the public N96 DLL reported no matched kernels, so cache percentages remain N64-family evidence only.
