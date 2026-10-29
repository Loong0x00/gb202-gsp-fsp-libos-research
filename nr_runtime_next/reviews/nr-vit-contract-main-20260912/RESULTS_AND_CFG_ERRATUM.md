# Main full bounded 1-D contract and expand→contract CPU composition

## Actual execution, not a point/map-required substitute

`literal_execution.py` executes the exact original `cc_vit_1d_ffn_contract_fp8` body,72-byte ABI,CTA(32,4,1),canonicalN128, real block32/layer1 slab4196352bytes. `run_full.py` executes **all32 CTAs**: eight128-feature groups times four z partitions. Every CTA reaches originalret in all four warps with4096 independently checked real FP8 MMAs: **131072 MMAs total**.

The caller supplies the sealed complete CPU expand output as p0, and retains its original input as p8:

* p0:524288bytes, SHA `b0435e97871e72c2cf17263355c42bdc35d4399509ef5193635828aca67ce87e`.
* p8:131072bytes, SHA `9f3bbadde7e1cca83b7f14b4204bddfb425696cb69f5719874ccf82abaaac7cf`.
* p24:real block32/layer1 slab, SHA `5c0a940e75c7df37d50098a53796a5014019844d347dabe8c34d73dff4ca6696`.
* p16:all131072 bytes produced, SHA **`a9493e2a256c8dd3f465d43edf99fc18c470111115fa3d5a84f2a07e6c6b70e6`**.
* p40:all262144 bytes produced by originalz0 stores before originalz1/2 reductions andz3 reads. Initially unproduced; never zero-filled.

This is a complete bounded CPU FFN pair composition at N128: expand1024→4096, contract4096→1024 with original learned skip C. It is **not the entire block32** (its QKV/attention/projection remain separate), live DAG binding, arbitrary shape support, native GPU equivalence or whole-model equivalence.

## Corrected source control, explicit state assumptions

The old `nr-vit-contract-reference-20260912/REPORT.md` incorrectly said z0 polls counter−1. Main independently read the actual branch:

`setp.eq.b32 %p69,%r1675,0` then `@%p69 bra BB46_119`.

Therefore z0 goes directly to p40 stores. Nonzeroz's sole leader waits for counter>=z−1; its other threads reach bar.sync135 and wait. z1/2 RED, z3 load/add/pack, then all paths reach bar.sync176 before the leader releases counter=z. The corrected worker followup is useful but still only a point/subset model requiring supplied maps; **it was not treated as actual full original execution**.

Our caller explicitly provides fresh independent counter words−1. This is an admitted CPU precondition, **not a kernel initializer or recovered live epoch/lifetime proof**. The CPU scheduler runs source-ready z0→z1→z2→z3 and records actual0/1/2 observations. Source-control dependencies are not a portable release/acquire proof: the original consumer uses relaxed loads, not acquire. Native visibility remains open.

## VM adaptations and real tests

Main added original not.b32, global RED half2, release/counter load and nanosleep forms to its private copied generic VM. Arithmetic remains exact/independently checked; no MMA=C, no identity callbacks, no unknown memory fill. Finite-half overflow remains a fail-closed unsupported domain.

The first attempted z1 execution correctly stopped because the old generic VM required a full warp at each bar.sync. Original z>0 splits its leader into the poll loop. The new private VM **holds31 lanes at the same static barrier PC**, executes the remaining lane's original poll/backedge, and only yields a full-warp arrival after that lane joins. It does not erase the poll or release a partial CTA. Different static barrier-PC rendezvous remains unsupported. The earlier failure is retained in `BEFORE_PARTIAL_BARRIER_SUPPORT.log`.

`test_literal_execution.py`: six tests PASS. They check the31+1 rendezvous and delayed release, unsupported mixed-PC rejection, exact bitwise NOT, independent finite half-add/subnormal behavior and overflow refusal, actual original z1-before-z0 waiting failure, stale-ready-counter plus missing-temp rejection, and all32 saved execution receipts/bounds. The initial test incorrectly expected infinity instead of the existing finite-domain refusal; its failure is preserved in `TESTS_BEFORE_OVERFLOW_DOMAIN_FIX.log`, not misreported as a successful native overflow test.

Full CPU grid execution took181seconds. `FULL_GRID.json` records all32 CTA returns,131072 MMAs, actual region support and18/19 barriers (z0/nonzeroz). No GPU, PE, Wine or game execution; no installed/config/network changes.

## Remaining boundary

Contract currently has a full original-instruction CPU reference; its NN-facing logical tensor lift is being derived separately. The expand NN tensor reference exposes logical weights/activations already. Their CPU composition is useful evidence, not permission to explain original-model causes before native/full-network equivalence is established. The stable original4h226/8192 gap and other model/state paths remain unresolved.
