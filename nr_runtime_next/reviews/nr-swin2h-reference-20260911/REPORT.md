# Swin2H inpview — complete bounded CPU arithmetic, with an ABI correction

## Critical finding: the requested pointer roles contradict the original

The aggregate **is 88 bytes**, not 1h96. However, fresh original-DLL decompression proves **input `+0`, output `+8`, slab `+16`**, not slab `+8` / output `+16`.

* `original.ptx:12`: `ld.param.b64 %rd9, [param+8]`.
* Lines 16,19: `ld.param.b64 %rd10, [param+16]`; `cvta.to.global.u64 %rd2, %rd10`.
* Lines 962–963: `%rd44 = %rd2 + lane_offset`; scalar load `[%rd44+28688]`.
* Lines 10985,10998 and 13314–13328: output addresses derive from **`%rd9`**, then `st.global`.

All 64 vector slab address chains are additionally **backwards affine-proved from the original `+16` parameter load**, independently of runtime registers. With external memory bound in the stated reversed order, the first coefficient load tries to read output+28688 and fails. The previous DS `next_boundary()` stopped before learned work, so it established neither slab nor output role. Its report's role assignment was not a learned-path proof.

No source/pointer swap hides this conflict. `run()` requires explicit `abi='original-verified-output8-slab16'`; omitting acknowledgement fails. **No successful forward under the incompatible requested role order is claimed.** The runnable result below uses the source-proven ABI.

## Result and reproduction

Full original `cc_tinlayout_fused_swin_2h_64_2_inpview_fp8` executes through **both original `ret`s**, on one **32×2 CTA**, with the actual block5 slab, all reached instructions, 4096 shared bytes and six **64-thread** barriers. **304 static MMA sites become 416 executed MMAs per warp, 832 per CTA**, because the original learned loop executes twice. No one-warp approximation, borrowed weight/scalar offsets, default missing operands, erased barriers or spinloops.

```sh
python -B reviews/nr-swin2h-reference-20260911/verify.py
```

Individual demonstration:

```sh
python -B reviews/nr-swin2h-reference-20260911/fixture.py \
  --synthetic --reference-policies --ack-original-abi
python -B reviews/nr-swin2h-reference-20260911/test_2h.py
```

CPU/static only: no GPU, Wine, compilation, installed changes, original header downgrade or sibling edits. Native variant selection is **unattested**. All deliverables are in this review.

## Original identity and encoded operands

`EVIDENCE.json` records fresh read-only DLL decompression equality and raw/checkpoint equality:

* Module01 original entry `[1982329,2202755)`, **220426 bytes**, SHA256 `f5979cb2032432e185a0d7fbcc9b24592902a72fd83920c5e110d7742b772c31`. Original module header remains **PTX 9.4 / sm_120**.
* `block5.layer0.layer`: raw offset **141527586**, **61760 bytes**, sorted 512-aligned upload offset **141544960**, SHA256 `1b905577285978107b21b5730aac2b0105d45f757b5e78334291d9b4ab5646bb`.
* Historical factory name: `cc_tinlayout_fused_swin_2h_inpview_64`, class `CCTinlayoutFusedSwin2H`. This is a historical association, not current launch binding.

Nominal container shape `[30880]` / F16 storage is **not a dense weight interpretation**. `TYPED_OPERANDS.json` checks **129 static slab load sites, 314 dynamic warp slab loads**, every lane address and loaded word, and direct typed MMA A/B E4M3, C FP16, and packed-half coefficient uses. Unread storage: `[28672,28688)`, `[28816,28832)`, `[57512,57520)`, `[61744,61760)`.

Recovered scalar/weight rules, all from this original entry:

* Initial packed-half coefficients: `28688 + 4*(lane%4) + 16*((j%16)//2)`, j=0..31.
* Loop vector blocks: source bases in `proofs_2h.LOOP_BASES`, `+16*lane`, plus pass×8192 for bases <16384, pass×4096 for 16384..24575, pass×2048 for 24576 onward. **Pass=0,1**, not `tid.y`.
* Post-exchange tables: bases 28832..31392 and 34976..37536, step512, **+3072*tid.y+16*lane**.
* Later tables: bases 41120..48800, step512, **+8192*tid.y+16*lane** (source executes the first and second halves in different stages).
* Final projection blocks: 57520,58032,59568,60080, **+1024*tid.y+16*lane**, used for each spatial output row-pair stage.
* Final packed-half coefficients: `61616 + 64*tid.y + 4*(lane%4) + 16*((j%8)//2)`, j=0..31.
* **Two distinct FP32 scalars** at `57504+4*tid.y`: bits `0x4018784b` = **2.3823421001434326**, and `0x411ea836` = **9.916067123413086**. They are converted by source `cvt.rn.f16.f32`; neither is a 1h scalar.

## Exact 88-byte family/layout boundary

Input `+0`, output `+8`, slab `+16`; H/W `+32/+36`, X/Y `+40/+44`, input-view H/W overrides `+80/+84`. Bytes `[24,32)` and `[48,80)` are unread by this entry.

Bounded public domain: H,W in `[8,4096]`, divisible by4; X,Y and effective origins `(X+8*cta.x,Y+8*cta.y)` in `[-4096,4096]`, divisible by4; nonnegative CTA coordinates; overrides `(0,0)` or exactly `(H,W)`; positive disjoint global spans; input/output each exactly `64*H*W` bytes; exact historical slab. The argument factory uses synthetic addresses, so large caller buffers require suitably separated caller-provided addresses. Only actually loaded sparse input bytes need exist; holes reject. Spatial OOB zeros come **only from original predicates**.

### DS → 2h input

H,W here are **the preceding DS H/2,W/2**. Input physical bytes are `[4,H,W,16]`:

```
input_offset(row,col,c) = 16*(((c//16)*H+row)*W+col)+c%16
```

For original global load site j=0..15 and lane l:

```
row = Yeff + 4*tid.y + 2*(j%2) + l//16
col = Xeff + 4*(j//8) + (l//4)%4
group = (j%8)//2
word_offset = 16*((group*H+row)*W+col)+4*(l%4)
```

Clip by actual row/column bounds. Each warp reads four spatial rows, **2048 interior bytes**; both warps cover all 4096 bytes of an 8×8×64 tile. The DS-produced sparse fixture is accepted without a dense tensor reshape.

### 2h output is a different packed layout

Original store tile q=0..3, lane l, warp y:

```
1024*((Yeff/4+q//2)*(W/4)+Xeff/4+q%2) + 512*y + 16*l
```

Each valid 4×4 tile is 1024 bytes: two 512-byte warp channel halves. A full interior CTA writes **4096 bytes**, not the input `[4,H,W,16]` representation.

A logical map defined by the source's final C-fragments (not checkpoint axes), for c=0..63:

```
m = 4*(row%4)+col%4
l = 4*(m%8)+(c%8)//2
j = 4*((c%32)//16)+2*(m//8)+(c%16)//8
byte = 1024*((row//4)*(W//4)+col//4)
       +512*(c//32)+16*l+2*j+c%2
```

`output_offset()` is independently tested as a complete bijection; tagged original store slices test rectangular/shifted/clipped addresses and packed bytes. The next native consumer/binding is not attested.

## New-family executable math and stages

The mathematical reference is the original **5459-instruction operational DAG plus its one retained backedge**, not a guessed dense network. Registers are 32-lane bit vectors **per warp**; all source arithmetic and operand dependencies execute. All MMAs are E4M3×E4M3 with FP16 C/D; no F16-input MMA is substituted.

For each packed-half element, ordinary `add`/`mul` implement `RNhalf(x+y)` / `RNhalf(x*y)`, and `fma.rn` implements `RNhalf(x*y+z)` in one rounding. Source clamp/abs, polynomial activation, normalization, permutation, quantization and residual operations remain literal instructions. No existing 1h attention/normalizer body is called. FP8 packing is `satfinite_E4M3(RN-source-half)` in original order.

Per MMA, decode the **actual** source fragments into A[16,32], B[32,8], C[16,8], then the explicit reference policy is

```
D[m,n] = RNhalf(C[m,n] + exact_sum_k A[m,k]*B[k,n])
```

Each subsequent MMA reads the rounded previous D exactly where the source specifies it. For lane `l=4*g+t`, forward fragment maps are:

* A element i=0..15: row `g+8*((i%8)//4)`, k `4*t+i%4+16*(i//8)`.
* B element i=0..7: k `4*t+i%4+16*(i//4)`, n `g`.
* C/D element i=0..3: row `g+8*(i//2)`, n `2*t+i%2`.

The independently forward-mapped finite binary64-exact dot implementation matches **all 832 actual MMAs** against the reused strict exact oracle. This checks operands and fragment placement, not just a final hash.

PCs are zero-based parsed original instructions:

| PC range | Per-warp learned work / boundary |
|---|---|
| `[0,833)` | All raw ingress loads, splitting/conversion; no learned MMA |
| `[833,1209)` | Actual packed-half coefficients and initial residual products |
| `[1209,2104)` | 112 MMA sites executed **twice**, distinct learned banks, literal nonlinear work; `%p379` starts true and becomes false, `%r4619` becomes1 |
| `[2104,2176)` | Quantize/pack and write full shared slab; barrier0 |
| `[2176,3342)` | Both warps read both producers, 96 MMAs, 32 explicit rsqrt calls per warp; barrier1 |
| `[3342,4296)` | 32 MMAs, two explicit reciprocal calls, retained shared residual read, new shared writes; barrier2 |
| `[4296,4426)` | 16 final projection MMAs, quantization, upper output microtiles; barrier3 |
| `[4426,5350)` | 32 MMAs, two reciprocal calls, **retained second half** of initial shared slab, new shared writes; barrier4 |
| `[5350,5459)` | 16 final projection MMAs, quantization, lower output microtiles; barrier5 then both `ret`s |

The sole backedge `2103 → 1209` is a two-pass learned loop, not removed polling. No atomics, external flag loads or spin-wait backedges exist in this exact entry. This does **not** excuse removing them from any other selected wait/chained variant.

### Real cross-warp shared semantics

`warp_machine_2h.py` is a scoped adaptation of pinned strict scalar/warp semantics: parse the original shared declaration, route original shared v4 operations, and yield at each original barrier. `swin2h_reference.schedule()` runs **both** coroutine warps to the same barrier and releases only after all64 arrivals. Retiring early/mismatched barriers/one-warp CTA fail. The reverse warp scheduling order gives identical registers and output.

Every shared byte must have a producer. Cross-warp RAW/WAR/WAW without the required barrier rejects; bounds/alignment reject; storage is **not initialized to zero**. Each read records its producer epoch, warp, lane, PC and bytes. Independent source address schedules reconstruct every write/read and byte, including cross-warp reads and retained old storage:

| Epoch | Shared effect |
|---|---|
| 0 | warp y writes `2048*y+512*j+16*l`, j=0..3; union `[0,4096)` |
| 1 | both warps read all `[0,4096)`; **4096 cross-warp byte reads** |
| 2 | read original `[0,2048)`, then overwrite it; **1024 cross-warp byte reads** before overwrite |
| 3 | both read new `[0,2048)`; **2048 cross-warp byte reads** |
| 4 | read **original epoch0 `[2048,4096)`**, then overwrite `[0,2048)`; **1024 cross-warp byte reads** |
| 5 | both read new `[0,2048)`; **2048 cross-warp byte reads** |

1792 lane-level shared v4 events, no holes. Exact PCs/formulas are in `SHARED_PROOF.json` and `proofs_2h.SHARED_RULES`. Tagged nonuniform original shared-exchange tests separately prove both producer warps are used. There is no one-warp “barrier passed” shortcut.

## Fixture, verification and limits

The input is the pinned previous review's **synthetic DS-produced** 4096-byte fixture (SHA256 `07520ef881b33707e82d9adcfcf4d21324e365eca1c6159db53a4e010a369f14`). It is supplied as an explicit sparse dictionary. With H=W=8, origin0 and one32×2 CTA, both warps return and produce 4096 packed output bytes, SHA256 `3ec96811ccf3e8feb034b6cdab773efcb3294185e1384da28de151f21563d0f6`. This is a synthetic CPU DS→2h composition using real historical slabs, **not captured activations or native launch selection**.

Twelve tests pass: all832 independent MMAs; actual block5 identity/all129 slab sites/two distinct scalars; complete shared byte/owner/barrier coverage; reverse schedule; two-pass loop; rectangular shifted/clipped full sparse arithmetic; tagged original ingress; tagged original cross-warp shared exchange; tagged original output stores/logical bijection; missing-input/slab/policy/ABI/geometry rejection; shared races/deadlocks/bounds; generic dependency namespace isolation and missing operands. Existing helpers are hash-pinned and loaded with generic `sys.modules` entries restored; no unrelated namespace is overwritten. New-family ABI, slab, layouts, stages and shared memory are local implementations.

**Numerics are conditional:** caller must supply MMA, RSQRT, RCP policies. Demonstration policies use finite exact dot+C then RN-even half per MMA, gradual half subnormals, and explicit RN-f32 reference rsqrt/reciprocal instead of hardware `approx.ftz`. Native tensor-core accumulation/rounding, approximation/FTZ, contraction of unadorned half operations and SASS/PTX selection remain unproved. No native numerical parity is claimed.

Also unproved: incompatible requested pointer roles; singleton/odd/non-four-aligned geometry; unequal overrides; actual native variant and block5 binding; incoming DS waits/flags/epochs/publication; multi-CTA publication and downstream consumer; full-model/frame execution. `BOUNDARIES.json` records these separately from the complete bounded arithmetic result.
