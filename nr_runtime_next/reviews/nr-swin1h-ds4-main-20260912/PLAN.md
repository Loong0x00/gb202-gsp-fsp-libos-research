# Block4 recovery plan (original preparation snapshot)

**Superseded progress:** firstNN/default72CTA/all432proofs and heldout63CTA now PASS. See PROGRESS.md for current state; publicAPI/bridge/seal remain pending. The text below preserves the pre-prediction plan.

Own current5982op96ABI source/slab and actual original3C32 input staged, see IDENTITY.json. No block4 prediction/original numerical run yet.

Latest same-model suffix worker finished at nr-parallel-encoder-proof-main-20260912/02-ds-tail/out. Main read report and confirms requirements for review (not yet all worker proofs independently rerun):
- Input final-half rows explicitly raster versus Main's tile-major64; do not silently confuse them.
- Pool uses coordinate-dependent ordered pairs: rho=pooledy%2, sigma=pooledx//2; three RN-half adds then RN-half quarter. This agrees with previously source-proved pre0 ordered pair classes, but block4 still needs own operand proof.
- Unquantized finalhalf forks: highFP8 skip independently, pool from originalhalf, NOT decoded highFP8.
- Pooled FP8 physicalK reads canonicalMainPI(k). Down matrix20656..22704,2048B, oneK32 per each8 N8 MMAs,32→64, zero C; no down bias/residual/identity fallback. Logical serializedRank r means actualMMA-N MainPI(r), not another guessed permutation.
- Low4planar16planes fromABI64; highC32 fromABI8. Padding source writes8planes with72/76 dimensions/different strides and conditionalbarrier; preserve exactly. FirstH=W64,allocatedlow32 should avoid padding, but verify actual CFG/footprint. No actualnativeOOB/allocationsafety claim.
- Worker caught and retained failed uniformpool-order assertion before any fullNN prediction. PriorFFN prose was ambiguous; actual outercubic MUL uses rawz, not clippedz. Fullcore requires Mainalpha+operand review, not that one witness alone.

Next: independently parse current fullsource/validatecommon ordinarycore, suffix and field maps; build own transparent NN with explicit numeric policies, freeze complete firstprediction before original execution; then actualfull72CTA high/low stores, every264MMA/scalar/fork/writerproof, heldout/API/chain tests. Do not modify sealed pre0/block1/decoder artifacts.

Parallel source jobs actually active at nr-parallel-encoder-next-main-20260912: ordinary wait/chained variants, and block5 2H-INPVIEW88ABI. They do not run fullNN/original numerical campaigns. No DLL/PE/Wine/GPU/network execution or deployment/gate change authorized/performed in this stage.
