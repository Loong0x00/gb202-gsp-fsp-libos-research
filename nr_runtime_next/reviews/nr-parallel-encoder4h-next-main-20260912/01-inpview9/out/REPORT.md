# Block9 actual4H-INPVIEWC128 recovery

## Result / acceptance boundary

Recovered the **supplied actual4H source**, own197184-byte mixed slab, complete typed/native-fragment field maps, planar16 ingress, ordinary tiled output, both residual forks, exact source/operand/CFG maps and reproducible static checker. No 2H fields or instruction counts were transplanted.

- INPVIEW: **5404 instructions,88-byte ABI,8192 shared bytes**; ordinary4H reference: **4804 instructions**, same ABI/shared extent. Exact hashes are recorded in SOURCE_MAPs and match PACKET. Delivered PTX copies are byte-identical.
- Own slab:9 typed fields,197136 bytes read, three16-byte unread gaps. All typed elements are explicitly mapped. F16 packet container is not homogeneous F16 weights.
- **4616 post-ingress core instructions** match one-to-one after physical-register alpha-renaming, one explicit modular-add operand commutation and documented CFG/hoisting exceptions. This does NOT prove ingress equivalence or numeric equivalence.
- **272 static MMA;704 dynamic warp MMA;2816 CTA warp MMA** for compatible `(32,4,1)`. All three loops really execute four trips.
- **Existing ordinary4H native/CPU226-of8192 mismatch stays OPEN.** Main owns first exact numeric freeze/campaign. No identity MMA, replacement activation, neural numeric run or native closure is claimed.

The packet requests `openai-codex/gpt-6-astra/xhigh`. No model switching, delegation or nested worker occurred; runtime model identity is not independently exposed by these file tools.

## Evidence and source recovery

Exact entries: `cc_tinlayout_fused_swin_4h_128_4_inpview_fp8` and `cc_tinlayout_fused_swin_4h_128_4_fp8`. `.maxnreg168`; inpview declares p394, b16-rs430, b32-r4550, b64-rd345; ordinary p140,rs438,r4212,rd328. These are declarations, not measured occupancy or device launches. Both shared symbols are aligned16,8192 bytes, but are different family symbols.

Only PACKET and its exact non-DLL inputs were used. The provided independent DLL was **never opened, scanned, loaded or hashed**. HOST_REPORT/DS8_OUTPUT_CONTRACT are supplied static reports, not newly reacquired host/producer binary evidence. Packet `source_module_sha256` is metadata, not a hash we recovered by opening the DLL. Full source copies and lossless instruction/label maps retain the exact authoritative instruction text and line spans.

## Ingress and HH/producer distinction

INGRESS_CONTRACT.md gives every guard/address and ABI field. Actual source loads80/84 and selects positive effective overrides; ingress is raw E4M3, eight16-byte planes, singleton **pixel** broadcast, otherwise literal raw-zero OOB. Sixteen4-byte reads/thread are not sixteen planes. Byte-tag checks recover all8192 interior ingress bytes into the native tiled shared map.

DS8 learned primary and block9 input have the same pi16 convention **only with matching EH/EW versus DS8 trunc-half strides**. The host report proves ordered handle routing, not complete4H shape/+80/+84 setup. Its 2H zero-override/R8 proof must not be promoted to4H. Conditional rounded HH/WW without positive overrides can change plane strides; actual live HH/W/override provenance remains open. DS8's separate PH/PW padding is **sixteen-plane**, potentially overlapping under the supplied contract, and is not allocation evidence.

Output is four guarded16-byte/thread E4M3 stores into ordinary tiled C128, not planar16. Source computes trunc0(H/4),trunc0(W/4), no hidden ceil-to8. OUTPUT_CONTRACT.md retains exact negative-origin tile inequalities, byte envelopes and no-null/no-padding limitations.

## Actual math and both residual forks

Use `Q` below only for the source `cvt.rn.satfinite.e4m3x2.f16x2` boundary, not an invented high-level quantizer or identity. FP16 operations, packed lane order, explicit FMA versus separate multiply/add, approximate reciprocal/rsqrt and reduction trees remain in SOURCE/OPERAND/MATH maps.

1. **Raw X fork:** ingress raw bytes -> shared. One branch feeds expand MMA directly. Another later reloads the identical raw X, decodes E4M3 -> half2 (2724–2870), multiplies residual1 F16 gain98320 (2885–3498), and preserves these values as dense-mix MMA C seeds. No input decode/reencode is inserted in the raw branch.
2. **Expand / cubic / grouped contraction loop (914–2723):** four outer output chunks j0,32,64,96. Expand uses four K32 blocks, total K128,512 expanded outputs over four heads/chunks. The actual activation is:
   `z=max_h(min_h(x,4),-4); p=fma_h(-0.055908203125,abs_h(z),0.447265625); q=fma_h(z,p,0.89453125); y=mul_h(x,q)`.
   Final multiplication uses original x, not clipped z. This is the source cubic approximation, **not conventional SiLU substituted by name**. Its output is Q-converted before grouped contraction; contraction accumulates in half over the four trips.
3. **Dense mix/residual1 (3657–3825):** Q(grouped result) -> shared -> dense N128,K128 MMA, with decoded-X*gain seeds. Quantize final mixed intermediate **Y** and store shared3945/3954/3963/3972.
4. **Raw Y fork / QKV (4078–4506):** raw Q(Y) feeds dense384x128 projection, four K32 trips; separate preserved raw shared Y later feeds residual2. Q/K square/sum reductions use packed half arithmetic, shuffle butterfly2 then1 and pair swaps, clamp with half-converted source F32 epsilon `6.199999916134402e-05`, convert each half to F32 for `rsqrt.approx.ftz.f32`, and round back to half. One F32 scale/head at180512 is converted to half and used in this normalization path. Q/K and V fragment transforms and quantization, including movmatrix operations, are retained exactly; group numbering in FIELD_ELEMENTS is native-source coordinates rather than an inferred framework transpose.
5. **Attention top/bottom:** two straight-line spatial halves, each32 query positions. Each has16 QK MMA with **F16 bias C** and16 probability*V MMA. The source exp-like path is NOT replaced by exp/softmax: half2 FMA uses half-converted source constants `0.04491037502884865`, `1.3008946180343628`, clamps to half1.03125..1.5693359375, then shifts packed bits left5 and adds integer2146992128. Exact packed-bit handling and row-reduction/shuffle order remain authoritative. Row sums clamp by epsilon, use F32 `rcp.approx.ftz` then half conversion; probabilities are quantized before PV. There is no claimed exact-real exp or conventional stabilization equivalence.
6. **Residual2 / output mix:** top reloads raw Q(Y) at9010/9019; bottom at11539/11548. Each decodes to half, multiplies F16 gain196912 and seeds dense output MMA C. PV is separately Q-converted into shared. Output mix consumes these raw PV bytes and E4M3 weights180528, yielding half accumulators, then final E4M3 conversion/stores. Residual2 is **decoded quantized Y**, not unquantized Y, raw X or an ABI skip pointer.

## Static versus dynamic MMA

|Phase|Static|Trips|Dynamic per warp|
|---|---:|---:|---:|
|Expand + grouped contraction|80 (64+16)|4|320 (256+64)|
|Dense mix/residual1|16|4|64|
|QKV|48|4|192|
|Top QK + PV|32 (16+16)|1|32|
|Top output mix/residual2|32|1|32|
|Bottom QK + PV|32|1|32|
|Bottom output mix/residual2|32|1|32|
|Total|272||704|

All MMA are `mma.sync.aligned.m16n8k32.row.col.f16.e4m3.e4m3.f16`. Backedges2723/3825/4506 compare **old** counters<96 and then take the branch after increment/move; old values0,32,64,96 give four executions, not three. No hidden attention loop or full-K128 single MMA is invented. The nominal arithmetic shape count agrees with2816 warp MMA x4096 scalar product terms, but no products were numerically evaluated.

## Threads, shared storage and barriers

CTA compatibility assumption `(32,4,1)` follows source lane/head addressing and supplied4H registration operands; it is not an observed launch. tid.y is the head/output32-channel role; all four warps participate in shared dense cross-head mixes. Lane IDs define fragment and pixel roles; no independent producer-only warp, async copy, polling role or warp-specialization branch is present.

Ten barriers, each `bar.sync0`: **868,3501,3649,3826,3974,7374,9467,9949,11991,12451**. All tested boundary paths reconverge and execute all ten. No barrier is inside a repeated math loop. SHARED_MAP.json records full phase coverage:
- raw X occupies0–8192, then is consumed and decoded before3501;
- grouped contraction Q output overwrites0–8192, synchronized before dense mix;
- Q(Y) overwrites0–8192, synchronized before QKV;
- after7374, residual top reads its old Y locations while PV top replaces0–4096;
-9467 publishes that CTA-local PV,9949 separates its consumption from reuse;
- residual bottom retains Y in4096–8192, while PV bottom reuses0–4096;11991 precedes its output mix;
-12451 is retained final synchronization.

No inter-CTA/inter-kernel acquire, release, publication, allocator ownership or buffer lifetime follows from these CTA barriers or weak global load modifiers.

## Common-core alpha / CFG proof with explicit exceptions

Anchor831 in inpview to253 in ordinary, after distinct ingress. Match4616 operations exactly by opcode, operand structure and constants, then validate one-to-one physical-register alpha map and branch destinations. Exceptions are not silently normalized away:
- distinct input ABI/global-pointer setup, effective overrides, pixel-planar guards/load paths versus ordinary tiled ingress;
- inpview7375–7382 delays signed H/W truncation that ordinary computes32–39;
- inpview9888 versus ordinary9302 commutes two add.s32 operands, valid modulo32 bits;
- inpview9892–9897 and9920–9923 recompute X coordinate/guards that ordinary retains from ingress;
- branch9906 enters the four-instruction guard-rematerialization block before its paired ordinary continuation, so **raw basic-block isomorphism is not asserted**;
- shared mangled symbol and label identities are renamed explicitly.

The post-ingress inpview-only18 operations plus the582-operation prefix difference explain the exact600-operation total difference. Whole-stream heuristic alignment4693 and its register conflicts are retained only as exploratory evidence, not the proof. CORE_ALPHA_VERIFIED, both CFG maps and full reaching-definition OPERAND maps expose all exceptions.

## Verification / remaining gaps

Final regenerated verification: **735/735 checks passed**. Run `python -B out/checker.py` from the task directory. Final count is in VERIFY_RESULTS.json / VERIFY_LOG.txt (initial731-check run had one deliberately preserved raw-CFG-target failure; the explicit four-op rematerialization exception was then checked). Tests cover source hashes/counts, full field bijections, direct MMA B/C tags, raw slab/codec roundtrips, all8192 interior input/output layout bytes, signed and singleton boundaries, loop counts and barriers. Floating neural loads/MMA/activations stay opaque in the address walker.

Open: actual4H host H/W and effective overrides/HH rounding; live shape/launch/grid and variant selection; slab binding; DS8 learned/padding/consumer stride agreement and initialized coverage; allocations/aliasing/lifetime; publication/fences; exact approximate-MMA/nonlinear numerical behavior; **226/8192 native gap**. No GPU, Wine, network, game, deploy, gate, DLL loading, outside discovery, nested worker or original/full-NN numeric execution occurred.

Failed parsers, the output-cap incident, initial CFG test and assumptions are retained in FAILURES.json and failed-run artifacts. READ_LEDGER.json distinguishes primary tool/projection units from an early inefficient internal128-lane source reread loop; it does not hide that raw read-call count under a primary-unit claim.
