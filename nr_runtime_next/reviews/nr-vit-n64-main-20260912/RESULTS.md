# Main: N64 is supported by original instructions, not invented input padding

The exact65536-byte pool→head→repack output feeds real block31 weights, with geometry factors8×8 in each operator's own ABI. All five complete original CPU grids now return normally, preserving loops, per-instruction arithmetic, elections, async copies, mbarriers, split polls and reductions.

| stage | full CTAs | real independently checked MMA | output |
|---|---:|---:|---|
|expand|32|131072|262144B,8fd387155219050bc177c5ea813eccbaf5941aa3a0c8e40f451b86403a9fc71e|
|contract|32|131072|65536B,e0826b627acffd5abcfa2184728f02f499ed41224a8e9ac630e785dc4ce73935|
|QKV|32|98304|Q/K/V each65536B; hashes inQKV_FULL_GRID.json|
|attention|32|8192|65536B,5e8c559fc6fd15c3e9c9ceca98d539394ec0a06140dcce452540494a9b35bfc1|
|projection|32|32768|65536B,43bc2ff775b2ea222fba26d8790e1814bb785053df50fdc5d6cde3d815b43222|

Five-op total401408 MMA; preceding pool/head adds24576 (total425984). QKV still executes65536 measured-half-domain RSQRT calls including internal padding work; attention executes8192 measured reciprocal calls. Those dynamic counts are not counts of distinct valid NN norm values or proof of full native behavior.

## Exact source masking

Every expand CTA issues64 input bulk reads covering exactly65536 bytes, never the missing upper65536. Original `r4=ceil(N/32)*2` and comparison-controlled fallback paths explicitly create zero FP8 words and store them to shared memory (e.g. original st.shared at source lines253/307 and later unrolled blocks). These are ORIGINAL defined inactive-compute states, not fabricated external tokens or replacement arithmetic. All four warps still execute real MMA; only64 valid rows are globally stored (8192 bytes/CTA). Full262144 output has no holes.

Dropping those actual zero-shared stores makes the literal executor fail on missing shared state. Removing the last real input byte also fails at an actual original global read. Thus `unknown_activation_padding=False` means no invented caller activations; it does not deny the source's own explicit internal zero handling.

Contract/projection temporary memory is exactly131072B and QKV393216B in these conditional executions. All bytes are initialized by their original z0 stores before any consumer reads, with no prefilled holes. Fresh counters−1 remain explicit caller conditions; native epoch/init/relaxed visibility is not thereby proved. Five tests PASS: all grids/hashes and byte edges; all expand read footprints; actual missing-last-byte; original masked-shared-store negative; stale-ready missing temp rejection.

## Primary connection

Block31's input-repack descriptor routes contract I as layer0 output1 (repacked original skip), then layer0 output0 (expanded). The explicit byte composition follows this, with subsequent QKV(P),Attention(Q,K,V),Projection(A,P). Outer graph source selection and all-size allocation lifecycle remain separate; do not treat adjacency or old collector field names as proof.

## Main metadata erratum

The first projection receipt classification copied the phrase `block31 FFN projection`; that is a documentation leftover, not the actual operator. Exact projection.ptx is `cc_vit_1d_projection_fp8`, its weight is named block31.layer4.layer, input is attention SHA5e8c… and retained skip is contract SHAe082…. Initial receipt is preserved. The actual executed source/inputs/1050624-byte slab and1024MMA/CTA are unambiguous.

NN tensor lift and independent valid-row intermediate checks follow in `../nr-vit-n64-tensor-main-20260912/`. This work resolves the former N64-admission blocker, NOT complete network/native equivalence. The upstream pool fixture is conditional; QKV sqrt32 RNf32/native approximate gaps and original4h226/8192 remain open. NoGPU/PE/Wine/installed/game/network changes.
