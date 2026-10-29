# Blocks5–9: current static factory/ABI/routing proof

## Result

**Static type, origin, ordered-port and dispatch-branch evidence recovered. No live/native/numerical acceptance.**

Key findings:
1. Blocks6/7 are ordinary shifted **2H C64**, block8 is **2H DS, 69,936-byte packet slab**, and block9 is the next **4H inpview C128, 197,184-byte packet slab**. Their indices are matched to the supplied historical graph and actual factory operands, not inferred from stage names.
2. **Current block5 host code does not carry unrounded source dimensions through ABI+80/+84.** It stores zero there. The supplied inpview PTX therefore falls back to rounded ABI H/W. Its ability to accept positive overrides is not evidence that this host path supplies them.
3. **DS8 O0→block9 I0 and O1→decoder62 I1 are verified as static ordered-handle routes.** Decoder62 is 2H upsample: its skip is **ABI+24**, not the 1H upsample's +80.
4. Registration, dispatch selection, ordinary outputs and auxiliary signals are separate. No live handle, allocation extent, initialization or publication/fence claim follows.

All PE reads used the exact packet-listed local `in/nvngx_dlssnr.dll`. Preferred base **0x180000000**. Below, code addresses are **RVAs** unless written as full VAs; object/descriptor offsets are **hexadecimal**, ABI offsets **decimal**. Packet DLL SHA256 is `e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e`; this run checked its 165,840,496-byte size and bounded current bytes, **not a whole-file SHA256**.

## 1. Exact factory blocks and origins

|Block|Factory call→builder|Exact factory layer name|Cin→ordered regular output channels|R8B, R9D, caller+20|inp/out|X,Y|Regular I/O count|
|---:|---|---|---|---|---|---|---|
|5|3a2d0→64d60|`cc_tinlayout_fused_swin_2h_inpview_64`|64→64|0,−1,−1|1/0|0,0|1/1|
|6|3a381→64d60|`cc_tinlayout_fused_swin_2h_shifted_64`|64→64|1,1,1|0/0|−4,−4|1/1|
|7|3a42e→64d60|`cc_tinlayout_fused_swin_2h_shifted_64`|64→64|1,0,1|0/0|−4,0|1/1|
|8|3a4d1→64a40|`cc_tinlayout_fused_swin_2h_ds_shifted_64`|64→128,64|1,1,0|nested0/0|0,−4|1/2|
|9|3a67b→67010, first table iteration|`cc_tinlayout_fused_swin_4h_inpview_128`|128→128|0,−1,−1|1/0|0,0|1/1|

Internal types are `CCTinlayoutFusedSwin2H` for5–8 and `CCTinlayoutFusedSwin4H` for9. Dispatcher **3fe7b/3fea5** selects constructor64500 for2H; **3fec6/3fef0** selects667a0 for4H. These are not kernel launch calls.

Current factory witnesses include:
- `3a2af c644242801`: inpview flag1; `3a2b4 c7442420ffffffff`, `3a2bc 41b9ffffffff`: the two −1 origins.
- `3a36c 41b901000000` versus `3a41d 4533c9`: blocks6/7 differ in the Y flag despite sharing a shifted name.
- `3a4b8 89742420`: DS8's X flag is ESI=0; `39af3 33f6` initializes it, with no intervening write before block8. The wrapper passes inp/out0 to64d60 at64a7a..64a8b.
- First table pair at **b21d8** is `ffffffffffffffff`. Factory3a600/3a608 reads its second/first signed components;3a66c tests first iteration,3a671 sets inpview1. This is the next block after DS8, not a guessed number of stages.
- Builders store2/4 at L+48 (`65049 c7474802000000`, `672f9 c7474804000000`), Cin/Cout at L+50/+54 and flags at L+70/+74. Outview takes precedence over inpview, then ordinary; shifted prefix selection is independent.
- Strings were read at exact RIP-derived locations, including b9020/b9050, b9078/b90a0, b90c0 and b9890. Integer conversion/append supplies the channel suffix.

Move31df0 preserves L+70/+74 (`31e95..31ea1`). Layer copy1ea60 independently preserves them (`1eac0..1eac9`). Constructor64500 copies L into **C+8**, so L+70/+74 become C+78/+7c. Forward65b60 computes:

```
Y = s32(-4 * max(s32(C+78), 0))
X = s32(-4 * max(s32(C+7c), 0))
```

The supplied inpview/DS PTX prefixes independently add X to8×ctaid.x and Y to8×ctaid.y. The current4H forward also carries these origin arguments; no4H PTX was supplied or inferred.

### Packet slab dimensions, not invented payload types

|Block|Packet container|Packet data_offsets, end-exclusive|Bytes|
|---:|---|---|---:|
|5|F16[30880]|141517952–141579712|61,760|
|6|F16[30880]|146536832–146598592|61,760|
|7|F16[30880]|147333088–147394848|61,760|
|8|F16[34968]|147416658–147486594|69,936|
|9|F16[98592]|147486594–147683778|197,184|

Every span and `2×shape[0]` was checked. These are packet metadata coordinates, **not asserted PE file offsets/VAs or live slab bindings**. The historical block5 report describes mixed E4M3/F16/F32 fields, so “F16 container” must not be promoted to uniformly F16 weights. No new slab extraction, DS/4H learned-matrix reconstruction or numerical weight execution was performed.

DS builder64a40 doubles L+54 and explicitly creates two12-byte records **(128,5,0),(64,3,0)** at L+d8:64ca7..64cb7, then24-byte copy64d12 and end64d1b. Codes5/3 are retained as codes, not guessed enum names. Ordinary/inpview leaves this vector empty; exporter3dfd0 defaults to one output (`3e157 bf01000000`), otherwise emits ascending record indices. Thus two DS ports are structural, not a name-derived inference.

## 2. Actual 88-byte2H host ABI and the source-dimension gap

Let incoming layer arguments be h,w. The block call loads them from `*(block+128)+16*layer`, +4/+8 at2b37a..2b390. Complete setup provenance and live values remain open.

With entry RSP=Q, forward65b60 sets RBP=Q−78h and RSP=Q−178h. The non-upsampling aggregate is **A=RBP−80h=Q−f8h**. Dispatch `65f5d 48c744243058000000` passes **0x58=88 bytes** through backend virtual+28 (`65f7a 498b4228`).

|ABI byte offset|Non-upsampling2H host value|
|---:|---|
|0|I0|
|8|DS: O1; ordinary/inpview: O0|
|16|S0 weight pointer; actual packet-slab binding unproved|
|24|zero qword|
|32,36|R8(h), R8(w), **rounded** H/W|
|40,44|X,Y|
|48|optional auxiliary input/wait handle|
|56,60|optional previous X,Y from referenced descriptor L+74/+70|
|64|optional auxiliary signal output|
|72|DS: O0; otherwise0|
|80,84|DS: D(h),D(w); **ordinary/inpview:0,0**|

Exact signed expressions, with `tdiv` truncating toward zero and `s32` wrapping:

```
R8(n) = s32(8 * tdiv(s32(n+7), 8))
D(n)  = s32(4 * tdiv(s32(tdiv(s32(n+1),2)+3), 4))
```

For nonnegative, nonoverflowing dimensions these are ceil-to8 and ceil-to4 of ceil(n/2). GridX/Y use ceil-to8 tile counts of rounded W/H minus negative X/Y origins, respectively. Negative arithmetic is not Python floor division.

**Decisive byte witnesses:**
- `65d42 83e3f8` / `65d57 83e0f8`: H/W rounding; stores at65db1/65dae are A+32/+36.
- `65d3c 4533c0` clears R8D; **`0x180065dc7: 4c8945d0` stores zero qword at A+80**.
- `65dcb 7437` skips the DS-only body for block5. No later common-path store restores unrounded dimensions. The entire common path65d29..65f84 contains **no read of C+180/+184**.
- DS-only `65dcd 488b06; 65dd0 488945c8` places O0 at A+72;65de9/65e01 place D(h/w) at A+80/+84.
- C+180/+184 are initialized −1 at64558. Their positive-value reads at65c20/65c35 belong exclusively to the **upsample** branch, selected by the `upsample` substring. Even hypothetical positive values there cannot change block5's shown inpview aggregate.

The supplied inpview PTX declares88 bytes, loads H/W32/36, X/Y40/44 and independent overrides80/84. Lines34–37 implement:

```
EH = ABI80 > 0 ? ABI80 : H
EW = ABI84 > 0 ? ABI84 : W
```

Consequently the current block5 aggregate yields **EH=R8(h), EW=R8(w)** under this supplied PTX ABI—not an unrounded source override. **Do not substitute the1H +72/+76 fields.** In DS8's supplied PTX, +72 is a64-bit pointer and +80/+84 are also loaded; their host role is DS output geometry, not block5's ingress override role.

### DS4 primary→5 specifically

Current DS4 host bytes were reacquired: `63a81 488b06; 63a84 488945b0` places ordered O0 at1H ABI+64, with D(h4/w4) at+72/+76 (`63a9c`, `63ab3`). The generic primary cache/gather below verifies block5 I0 receives this ordered primary handle.

**Conditional dimension example, not a live input:** if h5=D(h4), h4=65 gives h5=36, block5 H=40 and EH=40 because its override is0. For w4=73, w5=40 and EW=40. Thus this host path does not generally preserve the unrounded source-effective height. Equality can still hold for compatible dimensions or different live shape provenance; neither is captured here.

This is a concrete host/source ABI distinction, **not an assertion of actual padding OOB, missing producer writes, unsafe allocation or a numerical failure**. No live geometry, allocation extent or full NN was obtained.

## 3. Verified DS8 routes, including decoder62 skip

DS8 regular outputs are not auxiliary completion outputs:

|Ordered port|2H host pointer|Host aggregate geometry|Verified consumer|
|---|---:|---|---|
|O0, primary|ABI72|ABI80/84=D(h8),D(w8)|block9 I0|
|O1, secondary|ABI8|ABI32/36=R8(h8),R8(w8)|decoder62 I1→upsample ABI24|

Shape query66260 independently returns D(h/w),128 channels for DS output0 (`66380..663cb`). Its output1 metadata returns **raw h/w,64 channels** (`6641d..66442`), while the forward aggregate's main H/W are rounded. This metadata/launch distinction must not be erased or turned into a physical extent/padding conclusion.

The current routing chain is:
1. D+38 empty and block index k>0 selects N+110[k−1]:3cec2..3ced6 and3d0c4..3d0da. D initialization31b70 zeroes +38/+50 and explicit export selectors. Blocks5–9 do not overwrite primary selectors.
2. Setup3e791..3e7c4 fills that cache from **T[k][0]**, where T is N+1f0; empty output vectors can yield0. `3e7c1 488b00; 3e7c4 4a8904e9` is the decisive first-output load/store.
3. Export3dfd0 uses the last layer and ascending output indices absent explicit D+b0/c8. Network3ce5d..3cea5 copies ordered T[k] into the block output vector. Last/single-layer2ad36..2ad77 preserves that prefix.
4. Empty first-layer L+90/+a8 selects block input0 (`2af5e 4d8b0424`). Current4H forward `6802d 498b07; 68037 48894580` places I0 at its aggregate+0. **This closes DS8 O0→9 statically.**
5. Decoder62 factory `3b199→657b0` constructs2H upsample. Current `3b1b8/3b1c0` writes **[61,8]** to D+38;3b1e8/3b1f0 writes **[0,1]** to D+50, with D=RBP−20h. These exactly match the historical excerpt.
6. Indexed gather3d100..3d1a8 fetches **T[61][0], T[8][1]** in that order. Upsample builder657b0 sets L+a8=[0,1] at658cf..65924; layer gather2aff0..2b046 preserves it.
7. Upsample uses **U=RBP−10h**, a different local aggregate base. **`0x180065c53: 498b4708` loads I1; `0x180065c59: 48894508` stores U+24.** U+8 is O0. **This closes DS8 O1→decoder62 skip statically, without borrowing1H's +80.**

For2H upsample, positive C+180/+184 override incoming dimensions and are stored at U+32/+36 without the common path's rounding. This does not establish compatibility with decoder61 or DS8 secondary storage. The upsample PTX is outside the supplied scope.

## 4. Registration versus dispatch, and auxiliary routing

2H vtable **b8950**: slot0=64720 deleting destructor, +8=65b60 forward, +38=66460 initializer. Initializer66460 calls backend virtual+20 and stores its returned handle at S+8; actual forward calls backend virtual+28 with a selected handle. Constructor64500 zero-initializes the additional2H handles. A constructor/vtable literal is not a launch.

Selector64780 checks `_fp8` independently, with family precedence **upsample→DS→inpview→outview→ordinary**. Shifted/unshifted names share the family kernel literal; origins are arguments. Supplied PTX entries are `_fp8`, but these unmutated factory names lack that suffix. Actual live name mutations and backend selection remain open.

Let G be the byte referenced at **0x1800e06d1**, whose value was **not read**. It gates availability of appended auxiliary input/output handles.

|Family|Registration|Actual dispatch branch under shown state|
|---|---|---|
|2H ordinary6/7|S+8 base, S+10 same base; S+18 tilesync, S+20 wait, S+28 chained; S+30=true via62210|mask=2×(aux input≠0)+(signal output≠0). Nonzero S[10h+8×mask] wins; otherwise base. Stores input atABI48, signal atABI64.|
|2H inpview5|S+8 base; S+38 inpview_tilesync; S+30=false|Nonzero S+38 **and G-gated extra O1** select tilesync; otherwise base under constructor/initializer state.|
|2H DS8|S+8 base; S+40 ds_wait; S+30=false; S+38 initially0|Nonzero S+40 **and G-gated extra I1** select wait. O1 is the regular skip output, so an additional signal output would be **O2**, not O1.|
|4H inpview9|Current selector66a30 and initializer682f0: S+8 base, S+38 inpview_tilesync; S+30=false|Current forward68158..6816d requires nonzero S+38 and an extra signal output; otherwise its shown fallback branches apply. This row was independently inspected, not inferred from2H names.|

2H registration passes (32,2,1);4H registration passes (32,4,1) to the backend registration interface. Those operands are not observed device launches. Current4H selector literals are `cc_tinlayout_fused_swin_4h_128_4_inpview[_fp8]` and corresponding `_inpview_tilesync[_fp8]`. Supplementary externally mutated state can alter fallback possibilities.

Current late factory **3b841→357b0(start5,end8,mode0)** establishes:
- D6/D7/D8+68=[5]/[6]/[7]; first L6/L7/L8+138=[0];
- first L5/L6/L7+f0=[0].

The last RSI write before this call is `3b5be 33f6`, confirming literal5..8 rather than assuming an offset. The next call3b855 starts the9..14 auxiliary range. These tables do **not** permute DS regular ports or give block9 an auxiliary wait on DS8.

Auxiliary transport remains a separate appended suffix: network3d282..3d2ff appends N+1d8[k] after primary inputs; layer2b2d9..2b364 uses L+138 indices relative to the tail of its block input vector. Layer-to-layer auxiliary selection2b225..2b280 explicitly adds the producer's regular output count before indexing its auxiliary suffix. Thus signal index0 is not primary output0. Full setup resolution from D+68 to live suffix handles is still open.

If G and all intended suffix handles are present, the static configuration permits5 tilesync→6/7 chained→8 DS-wait. It does **not prove that schedule ran**, that those handles were allocated/initialized, or that producer writes are visible. The supplied inputs do not contain ordinary/wait/chained2H PTX. The user's1H relaxed-poll/sign-negative-pending caution is retained: **no acquire or2H polling semantics are inferred from1H or from variant names**.

## 5. Boundary checks, verification and limits

Artifacts:
- `CURRENT_WITNESSES.json`: explicit expected-byte witnesses with full VAs and containing `.pdata` entries, current scalar bytes, exact historical block excerpts and packet slab metadata.
- `PE_LEDGER.json`: every initial PE slice, one linear scan, every raw disassembly window including rejected cuts. `VERIFY_INITIAL_RESULTS.json` and `VERIFY_RESULTS.json` retain both rounds of bounded current-byte rereads.
- `FACTORY_SUMMARY.json`, `SOURCE_EXCERPTS.json`, `READ_LEDGER.json`, `FAILURES.json`, `PROGRESS.md` and `VERIFY_LOG.txt` preserve scope, decisions and accounting.

**`python -B out/verify.py`: 275/275 checks passed.** The initial254-check run also passed and is retained. Checks include fresh byte agreement, explicit byte constants, window/linear-scan agreement, `.pdata` entry-to-window continuity, exact literals and vtable slots, signed rounding, packet-span arithmetic, both PTX ABI prefixes, alias-tolerant opaque-handle routing and dispatch fallback cases. These checks do not emulate a neural network or validate GPU memory semantics.

The main2H prologue `.pdata` entry is [65b60,65b88), followed by [65b88,65fb3). Bounded unwind bytes at d8b94 include the latter's chained-unwind record back to65b60, so its continuation is not treated as a fresh stack frame. All selected witnesses belong to accepted complete windows; Capstone id0 is skipped before any operand access.

Budget: **one699,904-byte `.text` linear scan;30 windows,29,119 bytes total, each≤4,096; no second scan.** Additional scalar/header/`.pdata` slices and byte-only verification rereads are bounded and ledgered separately. Final primary read/output-unit accounting is in `READ_LEDGER.json` and remains below36.

Preserved current issues: three clipped terminal decodes were rejected and repaired, one early1,167-line projection hit the tool's50KB cap (its temporary spill was not read), and one512-byte scalar request mistargeted b4f00 and was not used as family evidence. No2,000-line primary projection violation occurred. Historical failures are retained as historical, not silently reclassified as this run's failures or successes.

### Precisely open live claims

Live shape arguments and their complete provenance; graph/name mutations; packet slab→S0 binding; real backend/variant handles and launch; allocator slots, byte extents, aliasing, ownership and reuse/lifetime; regular/auxiliary allocation and initialization; full D+68 suffix resolution; source/producer layout compatibility and padding writes; submission/completion and inter-kernel publication/fences;2H wait/poll semantics and relaxed-load visibility; original numeric behavior and full-NN/native acceptance. Two ports do not imply two nonaliasing allocations. No actual padding-OOB assertion, GPU/Wine/DLL loading, network, game/deployment/gate action, nested worker, old-helper main or original numeric run occurred.
