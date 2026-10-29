# Task B — independent normal-writer and exact padding audit

## Result

**Main's normal-writer corrections are confirmed. Arbitrary padded C32 geometry is not supported by this source contract.** The critical additional finding is that the original padding code zeros **four 16-byte planes**, whereas the normal low output writes **two 16-channel FP8 planes**. It also uses allocated strides rather than normal strides. Nonempty padding can therefore alias normal output and writes beyond a hypothetical `32*AH*AW` allocation. This is a source finding, **not** a claim about an inspected host allocation or a proposed kernel fix.

The conservative default `H=W=128`, `AH=AW=64`, grid `(16,16,1)`, block `(32,1,1)` has 524288 high bytes, 131072 low bytes, no zero stores, no duplicate normal words, and no output-footprint holes. No NN prediction or original kernel execution was performed.

Machine-readable contract: `PADDING_CONTRACT.json`. Detailed tests: `geometry_tests.json`; exact per-lane/channel reduction provenance: `reduction_provenance.csv`.

## Scope and independence

- CPU/static only. No copied Python input was imported or executed. No DLL/PE read, load, execution, Wine, CUDA, GPU, network, nested agent, input mutation, traversal to referenced original locations, or full-NN numerical campaign.
- This worker did not change/select an API model; the packet requests `openai-codex/gpt-6-astra`, `xhigh`. Runtime model identity is not independently observable from these inputs.
- I read the indexed source, separately inspected the PTX tail, and matched **every one of 941 indexed instructions at PCs5518–6458** in order against the copied PTX. Tail label targets were derived from that PTX, not taken on faith from Main's interpreter.
- Normal audit independently seeds **symbolic final MMA D identities**, using standard `m16n8` D-fragment rows/columns, and traces the actual skip conversions/packing and low selectors/shuffles. No half/FP8 neural value is fabricated or evaluated; conversion tags and half trees are provenance only. Main's script was read as a claim, not run or copied as the proof engine.
- Padding audit interprets the **original integer predicates, counters, branches, all 60 original b32 zero-store sites, and all suffix PCs**. Only the original constant-zero stores produce address events. Normal store occupancy is separate algebra; normal neural stores are not executed.
- Barrier6028 is an observed CFG event, never replaced with a CPU synchronization primitive. Counting arrivals does not prove native memory visibility, inter-CTA order, or a successful GPU launch.

## Parameters and normal outputs

Use `H=param.s32(+240)`, `W=param.s32(+244)`, `AH=param.s32(+256)`, `AW=param.s32(+260)`. “Allocated” here names the suffix's stride/bound parameters; no host allocation binding was inspected. Ingress dimensions at +208/+212 are separate and were not proven equal to H/W.

### +216 high skip: pixel H/W, not tile H/W

PCs4039–4047 form `Ht=trunc(H/4)`, `Wt=trunc(W/4)`. Each CTA has four candidate 4x4 tiles:

```
ty = 2*ctaid.y + phase       phase=0,1
tx = 2*ctaid.x + quadrant_x  quadrant_x=0,1
store iff ty < Ht && tx < Wt
byte = 512*(ty*Wt+tx) + 16*lane + byte_in_lane
```

Actual stores: PCs4796,4814,5560,5577. All 2048 symbolic bytes of an 8x8x32 CTA agree with the C32 map. For tile-local neuron `m=4*(Y%4)+X%4`, the intra-tile byte is

```
16*(4*(m%8)+(c%8)//2) + 8*(c//16) + 4*(m//8)
+ 2*((c%16)//8) + c%2.
```

The tile base is `512*((Y//4)*(W//4)+X//4)`. Thus **H/W are high pixel extents** for admitted divisible-by4 geometry; the tile stride is 512 bytes. The guard drops partial 4x4 tiles rather than writing individual edge pixels. Positive dimensions not divisible by4 do not give a complete HxWx32 high skip.

### +248 normal low: two planar16 planes, floor positive extents

PCs5831–5837 compute `h=trunc(H/2)`, `w=trunc(W/2)`, not ceil. For nonnegative H/W this is floor. Stores5880,5913,5946,5980 have guard `0<=y<h && 0<=x<w` and byte equation

```
byte = 16*((k//16)*h*w + y*w + x) + k%16,  k=0..31.
```

Lane geometry is `y=4*cy+lane//16+2*j`, `x=4*cx+(lane//4)%4`, `j=0,1`. Neither AH/AW nor the pointer-null test controls these normal stores.

Independently confirmed physical low channel → final logical channel:

```
pi(k) = 16*(k//16) + 2*((k%16)//4) + 8*((k%4)//2) + k%2
[0,1,8,9,2,3,10,11,4,5,12,13,6,7,14,15,
 16,17,24,25,18,19,26,27,20,21,28,29,22,23,30,31]
```

### Exact reduction order, not merely the four-neighbor set

Final D registers are produced at PCs4752–4759 and5518–5525. The skip FP8 fork reads those registers at4760–4775 and5529–5544. The low fork at5583 onward still reads the **original F16 D registers**, not stored/decoded FP8 skip.

The selector/shuffle permutation is `s=(lane&19)|((lane>>1)&4)|((lane<<1)&8)`; the four source lanes are `s,s^4,s^16,s^20`. Selectors are evaluated in those **source lanes**, not the destination lane. All eight packed reductions at5580–5830 were traced independently.

For every physical channel at a given low pixel, define `dx=(lane>>3)&1`, `dy=(lane>>4)&1`. Relative to high pixel `(2*y,2*x)`, the exact ordered leaves are:

```
A=(dy,dx), B=(dy,1-dx), C=(1-dy,dx), D=(1-dy,1-dx)
FP8( RN16( RN16( RN16(A+B) + RN16(C+D) ) * half(0.25) ) )
```

Lane0–7: `(00,01,10,11)`; lane8–15: `(01,00,11,10)`; lane16–23: `(10,11,00,01)`; lane24–31: `(11,10,01,00)`. The order is the same for both halves, both channel planes and both vertical phases at the same destination lane. The CSV lists **all 512 low bytes**, their final channel, reduced register/half, and each source register/lane/half. The first tree is literally PCs5607,5608,5609,5613; the other seven preserve the same pair+pair structure.

## Exact original padding contract

### Entry, thread index, and barrier6028

PCs5984–5991 compute

```
a = trunc_s32(wrap_s32(H+1)/2)
b = trunc_s32(wrap_s32(W+1)/2)
```

These are ceil(H/2),ceil(W/2) **only for nonnegative, nonoverflowing inputs**. The suffix exits if pointer+248 is null, or if `AH<=a && AW<=b`. This is not a null guard for the preceding normal stores, and cropped metadata does not suppress those stores.

For the active suffix:

```
T = ntid.x*ntid.y*ntid.z
t = ((tid.z*ntid.y)+tid.y)*ntid.x + tid.x
y0=4*ctaid.y; x0=4*ctaid.x
B = (y0<AH && y0+4>a) || (x0<AW && x0+4>b)
```

Barrier6028 occurs iff the suffix is active and B. B is CTA-uniform in ordinary nonoverflowing geometry; it does not depend on lane/tid. **The barrier precedes `t>63` rejection**, so a >64-thread CTA does not omit its higher threads from this barrier. All exercised CTAs had either T arrivals or no arrivals. This does not establish native visibility. CTAs whose B is false can still reach root tail loops without this barrier.

### Local 4x4 boundary loop — PCs6029–6083 and6336–6458

After the barrier, only `t<64` participates. The literal compiler loops partition `i=t+n*T`, `i<64`, with

```
q=i&3; y=y0+(i>>4); x=x0+((i>>2)&3)
write iff y<AH && x<AW && !(y<a && x<b).
```

There are no explicit lower-bound checks here. For ordinary nonnegative CTA coordinates, coordinates are nonnegative. Each admitted `(q,y,x)` performs **four** original b32 zero stores at base+0,+4,+8,+12:

```
base byte = 16*(q*AH*AW + y*AW + x), q=0,1,2,3.
```

This is the crucial **four-plane/64-byte-per-pixel zero footprint**, not the normal two-plane/32-byte footprint. Do not silently restrict q to0,1, change strides, clear a fabricated buffer, or remove/insert barriers.

The source first calculates remaining iterations `r88`, executes `(r88+1)&3` scalar iterations through6054/6049, then (if r88>=3) executes four-way bodies6356,6380,6404,6431. Companions track `i+T,i+2T,i+3T`; the join6348 advances by4T. In no-overflow geometry this is equivalent to the counter progression above, but the test executes the original CFG rather than substituting that progression.

### Root-only tails — PCs6084–6335

Only CTA `(0,0,0)` runs these tails. Let, for positive nonoverflowing grid dimensions,

```
R=min(4*nctaid.y,AH); S=min(4*nctaid.x,AW)
Y0=max(R,a); X0=max(S,b).
```

The test retains the source's actual shifts/masks before min/max; these simplified formulas must not be extended through signed wrap.

- **Bottom:** `y in [Y0,AH)`, `x in [0,AW)`, all four q planes. Counter limit `L=4*AW*(AH-Y0)`, stride T. Source guards `AH-Y0>=1`, then signed `t<L`. Scalar body6118; four-way body6146; loop join6213.
- **Right:** `y in [0,R)`, `x in [X0,AW)`, all four q planes. Limit `L=4*R*(AW-X0)`, stride T. Source first requires `min(AW-X0,AH)>=1`, then signed `t<L`. Scalar body6237; four-way body6265; join6332. The right counter is `%r5569`; bottom uses a copy, so the right sequence starts with the original t.
- Each tail uses remainder iterations `(remaining+1)&3` followed by a four-way loop, with the source's signed/unsigned division and comparison distinctions preserved.

All eleven inventory backward edges in this suffix were exercised:
`6062→6049,6066→6049,6080→6049,6138→6118,6215→6146,6257→6237,6334→6265,6355→6084,6440→6348,6444→6348,6458→6348`.
Some backward branches are joins/exits, not iteration predicates. Earlier ingress backedges are not padding and were not executed.

### Coverage, aliasing, and holes

For positive dimensions, no geometry overflow, `4*Gx>=b`, `4*Gy>=a`, and grid.z=1, the local rectangles plus root tails cover exactly the allocated rectangle outside `[0,a)x[0,b)`, **in all four planes**, once per zero word. Local/root regions are disjoint. Changing T redistributes zero work but not that multiset. The independent rectangle oracle and literal CFG agree, including T=1,2,3,7,16,17,31,32,64,128. Nonwarp T values test the suffix only, not legal full-MMA execution.

- A hypothetical low C32 allocation is `32*AH*AW` bytes. Every emitted q=2/3 interval is outside it. This is a conditional capacity finding; the real allocation may differ and was not discovered.
- Enlarging the allocation to64 bytes/pixel does **not** repair semantic layout: normal rows/plane1 use h/w, zero rows/planes use AH/AW. Padding can land on valid normal bytes and leave other allocated bytes untouched. Both same-CTA and cross-CTA aliases occur.
- Cross-CTA overlap has no global barrier. A zero/normal alias cannot be assigned a deterministic final value by this CPU trace. Even an ordered same-CTA overwrite would not become a valid padding operation.
- Undergridding leaves valid output unwritten and can miss padding: e.g. H=W16, AH=AW10, Gx=Gy1 misses the right strip `y=4..7,x=8..9` as well as neural coverage. No arbitrary-grid claim.
- Normal output addresses ignore grid.z and warp ID. grid.z>1 duplicates normal stores; local padding also repeats per z, although root tails run only at z=0. Multiple warps duplicate normal addresses even when zero work remains uniquely partitioned. Shapes such as `(16,2,2)` expose the suffix's tid.z dependence, not a supported ingress/MMA launch.
- Positive odd H/W have a floor-normal versus ceil-padding gap. With AH/AW equal ceil, the entire padding suffix can skip despite low allocated holes. Negative extents and wraparound must be rejected, not reinterpreted as positive ceil dimensions.

## Static test evidence

All counts below are bytes. “OOB” assumes a hypothetical `32*AH*AW` capacity. “Holes” are bytes in that capacity touched by neither normal occupancy nor zero events; they are footprint observations, not predicted values.

| HxW; AHxAW; grid | Normal low | Zero | Normal∩zero | Zero OOB | Holes |
|---|---:|---:|---:|---:|---:|
|128x128;64x64;16x16|131072|0|0|0|0|
|124x120;62x60;15x16|119040|0|0|0|0|
|128x128;65x64;16x16|131072|4096|1024|2048|1024|
|128x128;64x68;16x16|131072|16384|7680|8192|7680|
|8x8;7x9;1x1 root tails|512|3008|256|1504|256|
|8x8;7x9;3x2 local loops|512|3008|256|1504|256|
|129x129;65x65;17x17|131072|0|0|0|4128|
|9x9;6x6;2x2|512|704|112|352|400|
|16x16;10x10;1x1 undergrid|512|1792|192|896|1984|

Additional counterexamples in the JSON:

- Crop `128x128;60x60`: no zero stores, but **15872 normal bytes outside** the hypothetical allocation. Normal writer does not honor cropped allocation dimensions.
- Crop+pad `8x8;3x6`: 160 overlap bytes, 192 zero OOB bytes, 32 holes, despite the normal packed span fitting by total capacity.
- Even nondiv4 `10x10;5x5`: low footprint is dense800 bytes, but high output is only2048 of nominal3200 bytes, leaving1152 high bytes absent. Dense low does not imply compatible high geometry.
- Negative `H=-4,W=8,AH=2,AW=4`: normal is empty, suffix uses a=-1 and zeros512 bytes, including256 beyond hypothetical C32 capacity. Negative AH/AW cases are invalid capacities and perform no protective normal cropping.
- Null +248 skips padding but leaves512 bytes of normal address intent in the 8x8 case; this is not a permitted null output.

Concrete aliases: height padding first zeros byte65536, which is normal plane1's first byte. Its zero footprint ends at266239 while hypothetical capacity is133120. Width padding first aliases byte1024 and reaches278527 against capacity139264. A root CTA height-zero store at PC6173/byte65664 aliases a different CTA's normal output, so the conditional barrier is not a global repair.

## Admissible geometry and unresolved bindings

Admit only a **conservative static writer family**, not a native launch approval: positive H/W divisible by8; AH=H/2, AW=W/2; grid `(W/8,H/8,1)`; block `(32,1,1)`; separate nonnull, adequately aligned/sized output spans; no alias with read inputs; no unintentional integer geometry overflow (a conservative bound is `H*W*32<2^31`). In this family the suffix exits before barrier6028 and zero stores. Source barriers471 and838 are outside this suffix proof and remain unchanged.

The divisible-by4/non8 case124x120→62x60 also passed normal footprint checks with ceil tile-grid coverage, but is **not** a general host/ingress/native approval. I do not claim arbitrary padded, cropped, odd, negative, large-wrap, multiple-warp, or z-replicated shapes work. External tensor-port identity, actual capacities, +216/+248 pointer aliasing, producer completion, sampler/MMA numerical behavior, and native visibility remain open. The copied post consumer is a downstream claim, not proof of host binding.

## Verification and preserved failure

- `python out/stage_sources.py`: PASS; five bounded input windows staged; all941 tail opcodes matched in source order.
- `PYTHONDONTWRITEBYTECODE=1 python out/audit_geometry.py`: latest PASS in `audit_run_03.log`; 20 named geometry cases, ten additional suffix-only thread-count cases, 2048 high symbolic bytes, 512 low symbolic bytes, every padding PC and all11 backward edges exercised.
- Run01 reached the counterexample checks but failed a **test coverage assertion**, because branch6444→6348 had not been hit. Preserved unchanged as `audit_geometry_failed_01.py` and `audit_run_01.log`. Adding a partial-valid 6x6 suffix fixture (not altering source logic/barriers) exercised it; run02 and run03 passed. No failed native/numerical experiment occurred.
- `final_validation.log` records syntax, contract, and deliverable checks. No input was rewritten.

## Exact read paths and bounds

There were **19 bounded input-window reads including the explicitly required packet read**. All requested windows were <=2000 lines; no payload/binary scans. Exact paths actually read:

1. `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/02-writers-padding/PACKET.json` — required first read.
2. `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/02-writers-padding/in/pre_code_index.txt` — manual windows `(start,count)=(1,350),(5450,1011),(470,100),(4735,140),(4038,24)`; staged windows `(469,4),(4040,9),(4753,75),(5519,941)`.
3. `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/02-writers-padding/in/pre_identity.json` — up to100 lines.
4. `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/02-writers-padding/in/main_rejected_geometry.md` — up to200 lines.
5. `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/02-writers-padding/in/pre_inventory.json` — up to250 lines.
6. `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/02-writers-padding/in/main_output_basis.json` — first700 lines only, not a full-file audit.
7. `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/02-writers-padding/in/post_consumer_prefix.py.txt` — up to150 lines; text only.
8. `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/02-writers-padding/in/main_derive_outputs.py.txt` — up to500 lines; text only, never imported/executed.
9. `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/02-writers-padding/in/pre0.ptx` — manual `(1,80),(14000,1466)`; staged repeat `(14000,1466)`.

All other explicit data reads were own output artifacts, each below2000 lines (validation reads included):

- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/02-writers-padding/out/writer_index_windows.txt`
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/02-writers-padding/out/labels.json`
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/02-writers-padding/out/geometry_tests.json`
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/02-writers-padding/out/staging.log`
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/02-writers-padding/out/audit_run_01.log`
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/02-writers-padding/out/audit_run_02.log`
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/02-writers-padding/out/audit_run_03.log`
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/02-writers-padding/out/audit_geometry.py`
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/02-writers-padding/out/PADDING_CONTRACT.json`
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/02-writers-padding/out/REPORT.md`
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/02-writers-padding/out/PROGRESS.md`

Own executed source additionally includes `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/02-writers-padding/out/stage_sources.py`. The allowed DLL, slab, old reports, and PE helper were **not** read. Referenced original paths inside copied documents were not followed. All writes are under this task's `out/`; instructions are scope restrictions, not a claimed hard sandbox.
