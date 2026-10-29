# Main complete bounded ViT projection CPU forward

Main restored exact `cc_vit_1d_projection_fp8`, own72ABI,8192+16 shared bytes. Source SHA
`07fb4c01932ede72fdfe0f82d47063c0be5aa1dbaabf18a13b5f568d3b959e50`.

Static factory/ctor proof is separate from the FFN contract: ctor711e0, vtable BBAF8,+8forward72b60,+38init738b0. The full retained forward (not a too-short .pdata fragment) creates a72-byte record, grid(8*ceil(N/128),1,4); init givesCTA(32,4,1). The optional later1-D→2-D repack path is not part of this plain projection run. Host p0=I[0] source and p8=I[1] skip; this differs from the FFN contract's vector ordering and was not inherited by name.

Real block32/layer4 slab1050624bytes, checkpoint47154884, SHA
`99fdd6de02b14af6c61ff13a103405c26fe1f4caa555dbc9b5236b6d660318b4`.
Matrix1024x1024 FP8 plus source-used2048-byte half coefficient suffix. Actual original arithmetic determines learned skip placement and ordered reduction, not an identity residual assumption.

The explicitly chosen bounded caller supplies:
- source = full attention output131072B, SHA7f93c03037ec60bfa9093cf9bdf38686754a868a275d953ea1fedb2f8349ab98;
- retained skip = full FFN contract output131072B, SHAa9493e2a256c8dd3f465d43edf99fc18c470111115fa3d5a84f2a07e6c6b70e6;
- fresh counter−1 and initially unproduced temp.

All32 CTAs(8groups×4z) reach originalret in four warps; **32768 real independently checked MMAs**,1024/CTA. z0 initializes all262144 temp bytes; z1/z2 execute original half RED, z3 loads/adds/quantizes. All131072 output bytes are produced exactly once, SHA
**`07b7b4ca88e84c5a073ebfb7ecd631edaeb131387b03daa90561e0b4682cc163`**.

Five Main tests PASS: ownhost/vtable/ABI; exact real source/skip/slab; all32 saved returns/ranges; original wait failure before producer; stale-ready flag with missing-temp rejection. No missing memory fill or mock arithmetic.

Documentation caveat: the initially copied run_full.py docstring and its generic classification retain old "expand" wording. The actual literal_execution.py input paths, input hashes, tests and this report establish that p0 is attention output. This is a prose carryover, not a data substitution; original execution receipts are retained rather than silently relabeled.

Together with the preceding full FFN, QKV and attention, this completes an **explicit bounded five-operator CPU composition using block32 weights**. The chosen inter-operator caller bindings still need a full block-executor/live-DAG audit; it is not automatically a verified native block32 invocation. QKV/attention/projection are still instruction-level references, not finished NN tensor lifts. Approximation/finite-domain/counter-epoch/SASS limitations propagate through the chain, including the QKV sqrt32 reference and old4h gap. No complete-network or native-equivalence claim. NoGPU/PE/Wine/installed/config/network changes.
