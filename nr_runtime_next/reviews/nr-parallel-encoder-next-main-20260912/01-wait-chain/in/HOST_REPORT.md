# Encoder1H current-byte host/factory proof

## Result

**Conditional static closure:** factory blocks1–4, their actual origin pairs, block4's ordered outputs, primary→block5, and secondary→block66 skip are recovered from this worker's DLL. **No live/native/full-NN acceptance.**

Important corrections:
- Blocks2/3 both have a shifted name, but **different XY origins**.
- Block4 **O[0]→ABI+64** is primary; **O[1]→ABI+8** is secondary. Store order is not port order.
- Block66's skip input is **upsample ABI+80**, not +8; +8 is its output pointer.
- Block5 is **2H inpview with an 88-byte host aggregate**, not another 96-byte1H aggregate.
- Ordinary/DS1H host H/W are **unrounded incoming dimensions**. Do not transplant pre0 or2H rounding into this path.

DLL: own `in/nvngx_dlssnr.dll`, 165,840,496 bytes, SHA256 `e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e`. Preferred base `0x180000000`; shortened code addresses below are RVAs. **Object/descriptor offsets are hexadecimal; ABI offsets are decimal.**

## 1. Actual factory flags and origins

Factory39780 initializes its block vector empty, appends pre601f0, then these layers in order. The following are current call operands, not inferred from historical names.

| Block | Call→builder | Cin | R8B shifted | R9D→L+70 | caller+20→L+74 | inpview/outview | Expected (X,Y) |
|---:|---|---:|---:|---:|---:|---|---|
|1|39d9b→629d0|32|0|−1|−1|1/0|(0,0)|
|2|39eac→629d0|32|1|1|1|0/0|(−4,−4)|
|3|39fb9→629d0|32|1|0|1|0/0|(−4,0)|
|4|3a0bc→626b0|32|1|1|0|nested0/0|(0,−4)|
|5|3a2d0→64d60|64|0|−1|−1|1/0|(0,0)|

Builder629d0 establishes RBP=entryRSP−3b8; caller+20/+28/+30 become callee RBP+3e0/+3e8/+3f0. At62b30..62b72, outview takes precedence over inpview, otherwise ordinary; R8B independently selects the shifted prefix. Bounded `.rdata` reads confirm the exact strings. DS wrapper626b0 calls629d0 then replaces the name with `cc_tinlayout_fused_swin_1h_ds_shifted_32` for these operands.

The late factory call **3b82d→357b0(start1,end4,immediate0)** also matters. It sets:
- D2/3/4+68 = **[1]/[2]/[3]**;
- first L of blocks2..4, +138 = **[0]**;
- first L of blocks1..3, +f0 = **[0]**.

It does **not** change L+70/+74, L+90/+a8, D+38/+50 or the DS output records. These auxiliary tables are not a permutation of primary exported ports. The full network setup resolving auxiliary tables to live appended handles remains open.

## 2. Descriptor→runtime→96-byte1H ABI

Factory move31df0 preserves L+70/+74; block copy1e8a0 calls layer copy1ea60. Single-layer construction validates exactly one0x170-byte layer. Dispatcher3fdc0 selects61ee0 for the exact `CCTinlayoutFusedSwin1H` type.

**61ee0 copies L into C+8**, hence L+70/+74 become **C+78/+7c**. Forward637b0 computes:

```
Y = s32(-4 * max(s32(C[+78]), 0))
X = s32(-4 * max(s32(C[+7c]), 0))
```

With entry RSP=Q, three pushes and sub150 give RSP=Q−168, RBP=Q−68. Thus **A=RSP+70=RBP−90**. Supplied ordinary/DS PTX independently adds ABI+32 to8×ctaid.x and ABI+36 to8×ctaid.y, confirming the X/Y order.

| 1H common ABI offset | Current host value |
|---:|---|
|0|I[0]|
|8|DS: O[1]; ordinary/inpview: O[0]|
|16|S[0], weight pointer; live slab binding unproved|
|24,28|incoming signed H,W — **not rounded here**|
|32,36|X,Y|
|40|optional auxiliary input/wait handle|
|48,52|optional previous X,Y from referenced descriptor+74/+70|
|56|optional auxiliary output/signal handle|
|64|DS: O[0]; otherwise0|
|72,76|DS: D(H),D(W); otherwise0|
|80|zero qword|
|88,92|positive C+180/+184 override, otherwise0|

Actual layer-call arguments come from `*(block+128)+16*layer`, H/W at+4/+8 (`2b37a..2b3a6`). Their complete shape-inference provenance and live values are not captured.

**Tail-field caution:** the supplied inpview PTX prefix reads optional dimensions at **+72/+76**, falling back to+24/+28 when nonpositive. This host non-DS path zeroes+72/+76 and stores positive C+180/+184 at **+88/+92** instead. Do not silently equate those pairs or claim the override reaches that supplied PTX entry. This is a concrete reason not to claim all-operand/native acceptance.

## 3. Signed division and dimensions

Let `s32` wrap modulo2^32 and `tdiv` truncate toward zero. The exact DS expression is:

```
D(n) = s32(4 * tdiv(s32(tdiv(s32(n+1), 2) + 3), 4))
```

For nonnegative values without addition overflow: **D(n)=4×ceil(ceil(n/2)/4)**. The code uses `cdq; sub eax,edx; sar1`, then signed-bias rounding to4. Substituting Python `//` for negative divisions is wrong.

Common1H secondary dimensions stay **H,W**, not ceil8(H/W). Consequently **secondary=2×primary is not universal**: symbolic test H=65 gives primary36 and secondary65. This is a rounding counterexample, not a proposed live geometry.

In the ordinary positive/nonoverflow domain:

```
gridX = ceil((W - min(X,0))/8)
gridY = ceil((H - min(Y,0))/8)
```

The exact instructions retain wrapping32-bit arithmetic, sign tests and truncation. PTX signed coordinate division by4 likewise truncates toward zero, not floor. Never divide pixel H/W again by tile counts.

Shape query63ee0 corroborates DS output0's D(H),D(W),64-channel metadata and output1's rawH,W,32-channel metadata. It does not establish a neuron-byte layout.

## 4. DS output records and actual graph paths

DS builder records are ordered **(64,5,0),(32,3,0)**, 24 bytes at L+d8, copied at62982 and end set at6298b. **Codes5/3 are not assigned guessed enum names.** Ordinary/inpview leaves this record vector empty, yielding default output count1. Export helper3dfd0 emits the last layer's outputs in ascending index unless explicit D+b0/D+c8 selections exist.

| Block4 vector/graph port | ABI pointer | ABI H,W | Historical consumer |
|---|---:|---|---|
|O[0] / primary0|64|72,76 = D(H),D(W)|block5 I[0]|
|O[1] / secondary1|8|24,28 = H,W|block66 I[1] → upsample ABI+80|

Exact DS pointer witnesses:
- `63a14: 488b4608` loads O[1]; `63a32: 4889442478` stores A+8.
- `63a81: 488b06` loads O[0]; `63a84: 488945b0` stores A+64.

Network forward copies ordered T[k] from N+1f0 into the block output vector (`3ce5d..3cea5`); the block's last/single layer preserves that prefix (`2ad36..2ad77`). Appended auxiliary outputs do not precede it.

**Primary→block5.** Empty D+38 and k>0 selects N+110[k−1]; current assignment3e7b2..3e7c4 fills that cache from **T[k][0]**. Empty first-layer L+90/+a8 gathers V[0]. Block5's64d60 flags select2H inpview; its runtime forward65b60 independently places I0 at A2+0. **Dispatch65f5d sends0x58=88 bytes.** Its ordinary path rounds H/W to8 and stores them at A2+32/+36; do not reuse the1H96 ABI.

**Secondary→block66.** Supplied historical graph says D66+38=[65,4],D66+50=[0,1]. Current factory independently writes those exact vectors at3b3b2..3b40d, with D=RBP−20. Current indexed gather3d100..3d1a8 retrieves the actual selected handles, not labels. Builder63400 sets L+a8=[0,1], and block gather2afd4..2b046 preserves the order.

Upsample uses a **different aggregate U=RBP−20**. `638d1: 498b4108` loads I1 and `638d9: 48894530` stores **U+80**. U+8 is O0. Thus block4 secondary reaches the skip operand without guessing from names.

Upsample U+24/+28 are ceil8(effectiveH/W), and U+88/+92 are effectiveH/W; positive C+180/+184 overrides otherwise incoming arguments. Equality with block4 secondary H/W, and compatibility with block65 main, remain unproved without shape/live arguments.

**Source basis stays independent.** Primary/secondary are ordered host ports attached to opaque handles; no packed/planar/C/A byte basis, allocation extent or numerical DS result is inferred from metadata or names. The supplied pre0 basis is an independent starting boundary, not re-executed here.

## 5. Registration is not dispatch

1H vtable b8108 has **slot0=621b0 deleting destructor**, **+8=637b0 forward**, **+38=641c0 initializer**. The destructor frees state, destroys the embedded descriptor and conditionally frees C. Constructor vtable slot0 is not evidence of a launch.

Selector623f0 handles `_fp8` separately; family precedence is upsample→ds→inpview→outview→ordinary. Shifted/unshifted origins share a kernel literal. Init invokes backend virtual+20 and stores its return at S+8. The actual launch later uses backend virtual+28 and a selected handle.

| Family | Other registered handles | Actual common-path conditions |
|---|---|---|
|ordinary|S+18 tilesync, S+20 wait, S+28 chained|G gates supplementary I1/O1. mask=2×(input≠0)+(signal-output≠0); use nonzero S[10+8×mask], else baseS+8.|
|inpview|S+38 inpview_tilesync|Nonzero alternate **and** G-gated extra O1 select it; otherwise base under shown initialization.|
|DS|S+40 ds_wait; S+38 remains initialized0|Nonzero wait handle **and** G-gated extra I1 select wait; otherwise base under shown initialization. O1 is the regular secondary, **not** the signal output; that extra would be O2.|

G is the byte referenced at `0x1800e06d1`; its value was **not read**. Externally changed state can affect fallback alternatives, retained in the JSON. Supplied PTX entries are `_fp8`; unmutated factory names here are not. Neither a literal, successful static lookup nor a registration site proves a live FP8/base/tilesync/wait/chained dispatch. No GPU sync semantics are inferred from those names.

## 6. Allocation, lifetime and acceptance boundary

A concrete static pool chain exists: setup stores base/size at N+250/+258, forms **poolbase=incomingbase+N+208**, resolves a slot through N+1a8[block][layer][output], reads offset at N+178+16×slot and appends poolbase+offset to T. Invalid selections can produce zero.

Still open: live slot values/byte extents, ownership, aliasing, reuse/lifetime, weight-to-slab binding, graph/name mutations, actual backend handles, live H/W, complete auxiliary resolution, device submission/completion/publication and producer-consumer fences. Two ports do **not** imply two non-aliasing allocations. Host vector copies are not device-extent or GPU-visibility evidence. No full native/all-operand acceptance is asserted.

## Verification and preserved failures

- `python out/verify.py`: **104 checks passed**, including own-DLL byte matches, structured instruction witnesses, vtable slots, signed32 rounding, negative PTX division, XY order and aliased/non-aliased routing.
- **2×699,904-byte `.text` scans; 32 windows, 30,436 bytes total, each≤4,096.** Bounded additional `.rdata`, header and `.pdata` fragments retained. Capstone id0 is skipped.
- The second scan rejected **22 clipped/misaligned window decodes**; originals remain flagged false, never selected witnesses.
- **Line-bound failure preserved:** the first combined projection was2,124 lines and tool-truncated, exceeding the requested2,000-line bound. Its automatic spill file was not read. Subsequent projections were bounded. Do not represent this run as perfect line-budget compliance.
- `out/slice_failure.txt` preserves one malformed hexadecimal CLI invocation, which failed before reading a new slice. Corrected bounded slice reads succeeded.
- `pre_post_host_report.md` supplied targets; conclusions used here were rebuilt from own bytes. The large copied previous proof JSON was not read/adopted.

`HOST_PROOF.json` contains selected original-byte witnesses and decoded operands, every bounded raw code window, invalid-boundary flags, `.rdata` strings, header/`.pdata` fragments, PTX prefixes, historical/current separation and test results. All task-controlled writes are under this `out/`; no inputs/deployment/gates changed.
