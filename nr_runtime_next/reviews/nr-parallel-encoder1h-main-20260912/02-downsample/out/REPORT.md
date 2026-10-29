# Block4 DS1h: own-source field and both-output recovery

## Result and scope

Exact `cc_tinlayout_fused_swin_1h_32_1_ds_fp8`: **5982 executable ops,96-byte ABI,264 static MMA**. Own source SHA `8eb9c92ff8a4ffff1c7906589d789188dc2ee6ee05b685adc8dc2650406327e5`; named block4 slab22720B SHA `f0d05533694577fa313f2655b00ada84f231f87ebc66ebbb7e8f0f7ea1ac88d2`. No pre0 formula/source/proof was read. Requested model identity is the packet's `openai-codex/gpt-6-astra/xhigh`; this worker does not independently attest or change its runtime model.

**Closed statically:** every slab operand field; ABI reads; both final-neuron→byte maps; learned32→64 dimensions/type/K boundary; unquantized residual and pooling forks; conditional current-byte output-vector binding; source CFG/barrier/private-warp behavior; exact ordinary common regions and explicit differences.

**Not closed:** real block4 activations, original/NN prediction, native half/MMA/RSQRT/RCP numerical equivalence, current variant/launch, allocations/alias/lifetime/visibility, or padding-enabled safety. Main owns freeze. No input/gate/deployment changes or nested agents.

## Every own field (half-open byte offsets)

|Range|Actual operand interpretation|Own load/consumer evidence|
|---|---|---|
|0..4096|FP8 expansion128x32, four hidden32 chunks|969/978 through4712/4721; direct raw ingress A|
|4096..8192|FP8 contraction32x128, four carried K32 chunks|1998/2007 through5706/5715|
|8208..8272|F16 gamma32, decoded-input early residual|427..783; half multiply790..952; first contraction C|
|8288..11360|FP8 QKV96x32|5948..5993 loads;6108..6437 MMA|
|11360..19552|F16 score bias64x64, two private query halves|9913..9976 and11757..11820; **MMA C seeds**, not B projections|
|19552..19556|one F32 Q-scale, converted half before Q multiply|7043;8158..8159|
|19568..20592|FP8 final32x32|11528/11537,13339/13348; nonzero half residual C|
|20592..20656|F16 final gamma32|6453..6818;6823..7040 half multiply of unquantized FFN|
|20656..22704|FP8 learned down64x32|13935/13944/13953/13962; eight N8 MMA13993..14042|

No operand loads touch8192..8208,8272..8288,19556..19568,22704..22720. **DS learned weights start20656, not20672:** they replace the ordinary tail range and extend by2048B overall. Container metadata F16[11360] is not the matrix dtype. `FIELD_MAP.json` includes all111 actual load sites and packed-byte formulas; `OPERAND_LOADS.json` enumerates all32 lanes/site.

## Unquantized forks and arithmetic boundaries

Ingress rawFP8 quartets feed expansion directly; a separate FP8→half decode times early gamma seeds first contraction. FFN32→128→32 uses four expansion/cubic/FP8/contract streams and carries half C between K32 contractions. The actual polynomial uses half operations: clamp z to[-4,4], then `z * fma(clamped, fma(-0.055908203125,abs(clamped),0.447265625),0.89453125)`; do not substitute a library GELU.

Unquantized FFN half `%r1563..%r1594` forks into final gamma×FFN half C; its separately quantized bytes feed QKV. Q/K normalization, raw-V movmatrix transpose, packed score mapping, approximate RCP, probabilityFP8 and two-K32 PV are retained exactly in ordinary-common source regions, not replaced by generic softmax. Final projection has one K32 and an unquantized gamma×FFN seed; outputs are top `%r2998..%r3013`, bottom `%r4117..%r4132`.

Those final halves fork again: high writer takes `Q8(F)`; down pooling uses **F itself**, never decoding high output. Pool tree is `half(half(half(F00+F01)+half(F10+F11))*half(0.25))`, followed by FP8. This is spatial average then32→64, **not** four-pixel concatenation/K128. Each of eight down N8 groups uses the same A quartet, a distinct learned B pair and half+0 C. There is no down bias or extra residual. Native MMA internal precision/order is deliberately an opaque operator; source half boundaries are not a float32-dot equivalence claim.

## Both final/neuron→byte contracts

Full formulas/guards are in `OUTPUT_CONTRACT.json`. Let `pi(c)=16*(c//16)+4*((c%8)//2)+2*((c//8)%2)+c%2`. This permutation is derived from this source's C packs, shuffle-pool A basis and writers; it was not imported from pre0.

**High, ABI+8:** four4x4 tiles, each512 bytes, canonical tiled C32. For a pixel y,x and final MMA channel c, m=4*(y%4)+x%4, lane=4*(m%8)+(c%8)//2, j=2*(c//16)+m//8, u=(c//8)%2, e=c%2. Byte=`512*((y//4)*trunc0(W/4)+x//4)+16*lane+4*j+2*u+e`, value=`Q8(F[y,x,c])`. Actual128-bit stores at11722/11739/13535/13552. High guards use full-tile bounds from24/28 and high-grid origins32/36. Guarded-out high tiles are unwritten; there is no high zero-fill suffix.

**Low, ABI+64:** learned A channel k receives pooled final channel `pi32_inverse(k)`. Eight N8 MMA prove N64; writer independently emits16 pooled pixels×64 bytes/CTA. For learned output n and pooled pixel y,x, byte=`16*(((n//16)*HD+y)*WD+x)+pi(n)%16`, value=`Q8(D[y,x,n])`, where **HD=trunc0(H/2), WD=trunc0(W/2)** from24/28. This is four16-byte channel planes, not ordinary tiled C and not neuron-index-contiguous rank. Actual `st.global.v2.b16` stores are FP8 byte pairs, not F16 output. Origins halve `Y+8*cy,X+8*cx`; each store checks0<=y<HD,0<=x<WD. Pointer-null and padding extents are not checked by the learned writer.

`HIGH_WRITER_PROOF.json` traces2048 final-neuron bytes through actual high conversion/pack/address instructions. `POOL_BASIS_PROOF.json` follows all512 pooled A-byte tags through actual selects/shuffles/half-tree structure, proving spatial2x2 membership and channel basis. `LOW_WRITER_PROOF.json` traces1024 learned-neuron bytes through actual low writer arithmetic.

## Host port order: source store order is not graph port order

Own static PE window at`0x1800637b0`, header and two string slices establish `_ds` versus upsample branch. EntryQ gives RSP=Q−0x168, RBP=Q−0x68, **A=RSP+0x70=RBP−0x90**. RSI is output-vector begin.

- `63a14 mov rax,[rsi+8]` → `63a32 [rsp+78]=rax`: **A+8=O[1]**, high.
- `63a81 mov rax,[rsi]` → `63a84 [rbp−50]=rax`: **A+64=O[0]**, low.
- `63a44/63a59` store incoming h,w at24/28, **not rounded**.32/36 derive−4×nonnegative state7c/78. `63a88..63ab3` store `ceil4(ceil(h/2)),ceil4(ceil(w/2))` at72/76. Overrides88/92 are ignored by this entry.
- `63bb7..63c31` passes pointer-to-A and96 bytes. Auxiliary flags/handles can select other variants; no currently dispatched handle is observed.

Compose with **historical**, not live, `outer_graph.json`: block4 export0→encoder5 input0 (2h inpview64); block4 export1→block66 input1 (C32 upsample skip). Prior supplied host report documents generic vector/table order, not newly rescanned here. The actual DS pointer operands, not source store order or a channel metadata integer, attach layouts to ports.

## Preserved padding discrepancy / source barriers and loops

**Do not merge the data and padding layouts.** Data uses HD/WD and four16-byte planes. Padding uses ABI72/76 and **eight16-byte planes**, addressing `16*((p*PH+y)*PW+x)+b`, p0..7,b0..15. It skips only after learned stores if pointer is null or both padding extents<=ceil(H/2),ceil(W/2). Thus that late null check does not make the output optional.

Boundary CTAs conditionally execute the sole `bar.sync0` at14436, then thread-stride over128 plane/pixel items in their4x4 low tile, zeroing outside the ceil/2 interior. CTA0 separately zeroes uncovered bottom/right strips. The latter can run without the barrier. Padding loops contain backward branches and peeled/four-way-unrolled work; full exact CFG is retained. There is no math backedge or shared-memory operation, and no grid barrier/publication proof.

Static address-only H=W60,PH=PW32,origin−4,grid8x8 preserves a concrete discrepancy:15872 zero bytes;7936 lie beyond nominal64×32×32 bytes;6464 overlap dense learned64×30×30 payload bytes; maximum exclusive address131072. This **does not prove128 learned channels**, nor live corruption/allocation size; it rules out claiming the general padding helper matches the learned64-channel writer. H=W59 additionally exposes floor/2 data versus ceil/2 padding exclusion. H=W62,grid9x9 exercises17 barrier CTAs and gives the same8064-byte zero set for32 and64 threads.

For positive multiples8 with hostPH=H/2,PW=W/2, padding is disabled and the learned-data layout is coherent. Tested64→32 example has zero padding stores/barrier visits. This is a source domain, not a live allocation/native acceptance guarantee.

All neural work is private warp: only laneid and CTA x/y determine payload; no warpid/tid partition, shared memory or shared epochs. Two private32-query halves share prepared register banks. Additional warps/CTA-z duplicate payload store addresses; only padding uses linear full tid/ntid and CTA-z. Full active warp, legal launch shape, pointer aliasing and GPU visibility remain open.

## Ordinary comparison, failures, verification

Own ordinarySHA`15ddfc388ff77a4a1ce1bd4bbad79d44df220dda70f731a379eefa1694e0a8cd`,4902ops/256MMA. `EXACT_ALPHA_REGIONS.json` records a register/label bijection and4898 literal alpha-equal instructions. Four matched exceptions are explicit: three commuted integer-add sources and one y-origin recomputation use. DS-only regions are two ABI loads, three y-origin instructions, pooling/down/writers/padding around the relocated return. `ORDINARY_COMPARISON.json` lists exact inserted/noncommon instructions and both CFGs; **whole-kernel CFG equivalence is not claimed**.

Initial parser/counting error, naive-alpha conflicts and display/warning caveats are preserved in`FAILURES.md` and`source_index_initial_failed.json`. Corrected parser counts asserted5982/4902. Generated instruction index is a provenance index, not compilable PTX (some vector braces stripped by initial tokenizer).

Command: `python out/static_tests.py` — PASS. It evaluates only integer addresses/guards/padding CFG and opaque symbolic neuron/operand tags, never floating neural math.111×32 own slab-load addresses;512 pooled scalar tags;2048 high bytes;1024 low bytes; learned64x32 B-byte bijection; alpha comparison; padding disabled/enabled/boundary/odd-size checks. Source and own slab hashes match packet identities. No fullNN/original prediction or model execution.

## Exact actual input paths read

- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-encoder1h-main-20260912/02-downsample/PACKET.json`
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-encoder1h-main-20260912/02-downsample/in/downsample.ptx`
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-encoder1h-main-20260912/02-downsample/in/ordinary.ptx`
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-encoder1h-main-20260912/02-downsample/in/ordinary_reference.py.txt`
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-encoder1h-main-20260912/02-downsample/in/ordinary_results.md`
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-encoder1h-main-20260912/02-downsample/in/pre_post_host_report.md`
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-encoder1h-main-20260912/02-downsample/in/outer_graph.json`
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-encoder1h-main-20260912/02-downsample/in/nvngx_dlssnr.dll`
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-encoder1h-main-20260912/02-downsample/in/block4-slab.bin`

`ACTUAL_PATHS_READ.json` separately lists self-generated artifacts reloaded and own static scripts executed. `READ_LEDGER.json`:31 bounded authorized-input chunks/windows, each text payload<=2000 lines. PE:0 text scans,1×4096B window,4096B header,2×32B rdata slices. Output-artifact reloads are not counted as new project-input windows. No DLL/PE loading/execution, Wine/GPU/CUDA/network, outside discovery/recursion, nested agents, original numeric run, or input mutation. Explicit writes only under this task's `out/`.
