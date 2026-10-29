# Main original 2h inpview native oracle

## Result

**191747: one original 32x2 CTA produces4096/4096 FP8 output bytes identical to the pre-frozen literal-PTX CPU prediction.** Output SHA256 `3ec96811ccf3e8feb034b6cdab773efcb3294185e1384da28de151f21563d0f6`.

Original complete module01 CUBIN unchanged (`a10a8083b9489622fe290d669f05f38db7308c3c10771d0f0d6f22718e3cb1ae`), exact `cc_tinlayout_fused_swin_2h_64_2_inpview_fp8`, real61760-byte block5 slab, synthetic4096-byte DS input. Correct88-byte ABI INPUT0 / OUTPUT8 / SLAB16, H=W8, origin0, zero overrides, grid1, dynamic shared0. No textures, surfaces, flag dependencies or borrowed NR allocations.

Independent full readback checks: input and slab unchanged; both256-byte output guards unchanged; every output byte differs from its initial complement poison. All CUDA launch/sync/readback/drained cleanup statuses0, normal context destruction successful, host0, Guardian0. `run.py` distinguishes execution success from numerical equality (host2 would be a valid mismatching measurement, not a tolerance pass).

Main first reran7 preparation tests,43 CUDA-free packing checks and the frozen artifact hashes. Runtime/fixture/source/ELF/Guardian pins were approved before each run. Serialization used project benchmark.lock, fresh no-games, >=4GiB starting GPU headroom, global31000MiB cap, armed Guardian and30s isolated child watchdog. No installed files, game configurations, signed code, network, clocks or power settings changed.

## Shared-resource correction retained

**191319** loaded successfully but failed the initial assumption that Driver function static-memory reporting equals ELF total extent; no allocations/launch followed. CUDA cleanup0, Guardian deliberately terminated−15 by error cleanup. This remains a failed operational run, not discarded evidence.

**191601** independently resolves the accounting difference with an own compiler witness, also only loaded: original/witness each report4096 function bytes, device driver reservation1024, each ELF extent5120. All CUDA/cleanup/Guardian0. See `SHARED_ACCOUNTING_ERRATUM.md`. Original worker gate remains false; Main phase snapshots/binaries reside in `backups/`.

## Limits

This is one synthetic fixture's **final FP8 bytes**, not all832 individual native MMA results or all intermediate half/F32 values. Known source-to-SASS contraction differences (32 extra HFMA2 sites) and generic approximation/accumulation questions are not resolved by matching quantized output. The frozen policy remains unchanged; no policy fitting or reseeding occurred.

Plain-kernel selection within a real NR submission, block5 runtime binding, predecessor readiness, multi-CTA concurrency, complete network/image/history execution and visual quality remain unproved. Original ELF identity alone does not identify the driver's selected embedded representation. This CPU reference result is not an installed game-image fix.

Recheck without GPU: `python3 -B verify.py`. See `VERIFICATION.json`, all run approvals/status logs, original frozen prediction and initial rejected-run evidence.
