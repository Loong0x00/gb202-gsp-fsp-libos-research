# Main original4h native comparison — execution PASS, numeric mismatch

## Reviewed and executed

Main reran9 preparation tests,8319 CUDA-free contract checks and76 published artifact hashes. `verify_frozen.py` independently recomputed the original four-warp CPU reference and its pre-frozen8192-byte prediction, plus all128 SASS integer/address/control traces with unknown numerical values and scratch0/all1 checks. PTX/SASS per-lane byte support and shared epochs agree;26624 reused coefficient-read events are explicitly not treated as equal multiplicity.

Main-owned clone only; original worker gate remainsFALSE. Original module02 ELF1590184bytes, SHA256 `9cba6bc0001a80c902ee20fd5638bf442bdf0674aaada676d67a6d1b89ca0aaa`, unchanged with Mercury sections retained. Exact `cc_tinlayout_fused_swin_4h_128_4_inpview_fp8`, real block9slab197184bytes, synthetic block8DS-produced8192-byte input. Correct88ABI INPUT0/OUTPUT8/SLAB16;H=W8,origin0,overrides0;grid1/block32x4/dynamic0.

- **123501 load-only:** original function loads/resolves; actual167registers,8192user shared+1024driver reservation=9216ELF extent,local0,maxthreads384,cluster requirement0. No caller buffer allocation/kernel. All CUDA, normal cleanup and Guardian0.
- **123637 oneCTA:** owned input8192/output8704/slab197184,256-byte prefix/suffix guards. Launch/sync/readbacks/drained cleanup and Guardian all0. Hostexit2 is deliberately a valid numerically mismatching measurement, not an operational failure.

Both runs use serialized benchmark.lock, fresh no-games (including Minecraft), >=4GiB initial headroom,31000MiB global cap, armed Guardian and30s isolated child watchdog. No game/deployment/config/network/power/clock or signed-code modification.

## Frozen comparison

**226 of8192 FP8 bytes differ.** Per2048-byte microtile:125,56,26,19. Guards/input/slab unchanged, no outputNaNs and no retained/colliding complement poison.

- Original outputSHA `e86df801093922b4629bcd0a955495e736c3009d8799d6bb2e2efc84cba5a9f3`.
- Unchanged pre-frozen predictionSHA `0422ff26b9c9dedc3e4f547330b27b62bc9f037059739324e6c3a1340dacd312`.
- Max finite decoded absolute error .015625.220 differences have raw encoding distance1; three are signed-zero-only, one crosses sign nearzero, two have raw distance2. These diagnostics are NOT a tolerance acceptance.

This is a **new unresolved numerical gap**, not permission to call the reference exact.32 potential SASS multiply/add contractions require own-4h operand/rounding proof; finalpost fixes are not blindly applied. Separate CPU-only `nr-swin4h-numeric-gap-20260912` investigates source-backed causes; historical input/prediction remain unchanged.

`verify_runs.py` reproduces saved-output/freeze/argument/guard/cleanup checks without GPU. `COMPARISON.json` retains all226 indices. No native general MMA/intermediate parity, live selected game variant, actual NR-pool activation, fullnetwork/history/image or visual-quality claim. ELF identity and attributes do not prove which embedded code representation the driver selects.

## Fresh-context repeat

**125119** repeats the same frozen fixture after a separately recorded repeat plan, with unchanged binary/input/slab/policies. Original output and complete guarded buffer are byte-identical to123637 (e86df801…), again226/8192 mismatches vs the frozen CPU prediction. All CUDA/normalcleanup/Guardian0; host2 is the retained numerical mismatch. This supports repeatability on two contexts, not generalized determinism or a resolved numerical cause.

## Main contraction certificate review

`check_lineage.py` reruns32source pairs and32directed SASS QMMA→HMUL2/HFMA2 folds, six physical coefficient anchors and four shared fragment anchors, writing only Main artifacts. It additionally performs64 actual mutated-input rejection checks (broken equal HFMA operands or replaced square opcode). The worker’s original MUTANT_CHECKS labels were fact/count predicates, not executions of those mutation tests; they are not credited as swapped-role rejection proof. Individual PTX-pair-to-SASS-fold permutation, exact MMA/MUFU arithmetic and explanation of226 residual bytes remain unresolved. No corrected policy is proposed.
