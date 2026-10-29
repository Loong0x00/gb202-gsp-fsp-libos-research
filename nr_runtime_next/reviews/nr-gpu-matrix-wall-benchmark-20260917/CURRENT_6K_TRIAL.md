# Current RTX 5090 6K matrix trial (2026-09-17)

## Scope and safety

- GPU: RTX 5090, current driver/runtime.
- Exact-DLL case: 6144x3456, 30 consecutive evaluations, current `nvngx_dlssnr.dll`.
- Logical trial uses the recovered current graph dimensions, but ordinary PyTorch BF16/FP8 arithmetic. It is a speed experiment only: it is neither source-bitwise nor a replacement full 71-block implementation.
- `benchmark.lock`, no-game check, recovery Guardian, 31,000 MiB cap and 4 GiB reserve were active.
- Peak observed allocation was 6,544 MiB for the exact-DLL run, 4,343 MiB for the ViT graph run, and 5,646 MiB for the spatial trial.

## Exact current DLL baseline

For the stable middle interval, iterations 15--24, medians were:

- GPU event span: **20.940096 ms**
- wall: **20.953250 ms**
- CPU submit: **2.675350 ms**

The complete 30-iteration median wall time was 21.222700 ms. The 15--24 interval avoids both initial clock ramp and late outliers.

The earlier Nsight Systems run of the same DLL/6K geometry measured 18.442258 ms/frame summed CUDA kernels, of which block31--38 ViT was 3.631596 ms/frame and the Swin families were 14.503771 ms/frame. Event-span minus summed kernels is not all removable CPU launch overhead: the host finishes submission long before the 6K GPU work completes, and stream waits/copies are not represented by the kernel sum.

## 5090-friendly tiled ViT trial

The 6K bottleneck head is nominally 54x96 and padded to 56x96. The experiment represents this as 56 independent 8x12/N96 tiles and flattens their linear layers into large resident matrix operations. Eight blocks were executed, including logical FFN, QKV, SDPA and projection.

| implementation | measured wall / stack |
|---|---:|
| BF16 resident logical stack | 4.983210 ms |
| FP8 resident logical stack | 2.119471 ms |
| FP8 plus CUDA Graph | **2.098319 ms** |

CUDA Graph saved only about 0.021 ms: this trial is GPU-work-bound, not Python-launch-bound.

Against the earlier exact ViT kernel sum, the approximate FP8 graph is 1.73x faster (3.631596 -> 2.097679 ms). If only this stage were transplanted and all other current costs remained, the projected complete 6K wall time is:

`20.953250 - 3.631596 + 2.097679 = 19.419333 ms`

This is a measured-stage projection, not a measured hybrid full-model result.

## Spatial/Swin counterexample

A straightforward materialized FP8/BF16 rewrite of the recovered spatial core shapes was also run. It was deliberately retained even though it failed as an optimization:

| stage | one logical core | graph block count | scaled core total |
|---|---:|---:|---:|
| C32, 5,308,416 tokens | 5.222869 ms | 10 | 52.228692 ms |
| C64, 1,327,104 tokens | 2.786640 ms | 8 | 22.293119 ms |
| C128, 331,776 tokens | 1.251509 ms | 12 | 15.018112 ms |
| C256, 82,944 tokens | 0.522848 ms | 16 | 8.365568 ms |
| split C512, 20,736 tokens | 0.200373 ms | 16 | 3.205973 ms |
| **total core projection** | | | **101.111465 ms** |

This bound omits several source operations and is still about seven times slower than the 14.503771 ms source Swin kernel sum. The narrow K32--K256 spatial layers benefit enormously from the source's fused window/layout/attention kernels; converting them into separately materialized GEMMs is the wrong optimization. The first unchunked C32 SDPA attempt also failed with `CUDA error: invalid argument` at 82,944 windows and is preserved in `FIRST_TORCH_6K_SWIN_FAILURE.log`; the successful rerun used independent 32,768-window launch chunks.

## Conclusion

The direct experiment falsifies the earlier 12 ms near-term estimate. With the implementation available today:

- exact current full model: **20.95 ms** steady 6K;
- 5090-friendly approximate block31--38 stage: **2.10 ms**;
- projected hybrid full frame after replacing only that stage: **about 19.42 ms**;
- generic full spatial matrix decomposition: rejected as drastically slower.

Reaching 12--13 ms would require new fused spatial kernels that preserve the existing layout/window fusion while increasing 5090 parallelism. CUTLASS/PyTorch materialized GEMMs alone do not provide that result.

## Evidence

- `dll6k/cuda-probe-inner.log`
- `TORCH_6K_TILED_VIT.json`
- `TORCH_6K_SWIN_BOUND.json`
- `FIRST_TORCH_6K_SWIN_FAILURE.log`
- `TORCH_6K_SWIN_BOUND_R2.log`
- `GPU_6K_RUN_RECEIPT.txt`
- `MAX_USED_6K_MIB.txt`, `MAX_USED_VIT6KG_MIB.txt`, `MAX_USED_SWIN6K_MIB.txt`
