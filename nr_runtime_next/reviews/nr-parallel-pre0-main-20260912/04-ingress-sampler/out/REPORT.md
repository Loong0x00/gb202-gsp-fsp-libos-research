# Task D — independent PRE0 ingress candidate; sampler/native boundary

## Result and scope

**Completed a high-level, first-counter-zero, feature-only candidate**, not a PTX interpreter or NN forward. `preprocess_candidate.py` returns one tile of **logical[x][y][16] raw half bits**, optionally packed into the original 2048-byte shared fill. It requires an explicit raw-F32 sampler and an explicit named **NONNATIVE** approximate-operation policy. **15 CPU synthetic tests pass.** No weights, activations, MMA, first embedding, complete NN prediction, native execution or model freeze were attempted. Main owns review and first freeze.

The candidate independently transcribes the actual PTX feature equations. The old `Replay`/`Thread` source was read for review only; **nothing is imported, evaluated, wrapped, or reused from it**, including its ctypes/libm loading, parser, pinned external imports, embedding routine or numeric helpers. New isolated rational arithmetic implements the plain F32/F16 operations.

### Evidence strength

- Direct source read: current `pre0.ptx` **lines 1–610**, 17,943 bytes, prefix SHA256 `159efb08d316b30bf42a311952c9316ba15f3aa8764ae47a8cab7b3ffc135a4b`. `SOURCE_PREFIX_EVIDENCE.json` checks literal operation sites. The actual first barrier is **line 590**. The candidate stops at feature construction, before barrier/learned arithmetic.
- Host: **14 individually bounded .text windows**, **4,107 bytes read including the corrected overlapping window**, zero .text scans; three individually addressed .rdata slices totaling 92 bytes, three 4096-byte PE-header reads. `.text` size is checked against 699,904. No resource/payload traversal and no full-DLL read/hash.
- Packet whole-source/DLL hashes are **provided identity metadata, not independently recomputed**. Exact read-window bytes and SHA256 values are retained. Host routing/control claims beyond selected fresh windows explicitly rely on the allowed previous binding/Vulkan reports.
- Static evidence correction retained transparently: initial R12-gap decode started at `0x180050290`; correct instruction boundary is **`0x18005028f`**. Corrected window fully decodes and does not write R12. Initial frontend window's three-byte interior prefix at `0x180022620` is **not evidence**; valid T3-zero instruction starts **`0x180022623`**. `STATIC_BOUNDARY_CORRECTION.json` supersedes only these interpretation issues; original scripts/logs/bytes remain.

## 1. Exact feature dataflow and boundaries

API:

```python
from preprocess_candidate import preprocess_firstcounter0, SamplerPolicy
from approx_policies import reference_nonnative
# args264 and actual_raw_bits_sampler MUST be explicitly supplied by caller.
tile = preprocess_firstcounter0(
    args264,
    sampler=SamplerPolicy("caller-described policy", False, actual_raw_bits_sampler),
    approx=reference_nonnative(),  # explicit opt-in; NEVER native parity
    cta=(0, 0),
)
# tile.logical[x][y][c] is a uint16 encoding, NOT a host floating activation.
```

Sampler callback signature is `(handle64, x_f32_bits, y_f32_bits) -> four raw uint32 F32 words`. Missing source sampler/handle, malformed callback words, absent genuine mask response, missing approximation policy, inconsistent temporal handles, nonzero **full64** counter, and unsupported numeric/mirror domain fail closed. The code never silently zeros a real resource, invents noise, or applies `nan_to_num`.

The callback policies must be pure for a fixed resource snapshot. High-level cached coordinates and row-major pixel iteration are **not original per-thread operation counts or callback scheduling**. Dead prologue RCP operations for T3 extents / temporal ingress reciprocals and unused T4 transforms are eliminated; they cannot affect first-counter feature values. Thus zero inactive temporal extent fields do not require inventing a reciprocal result. RCP nevertheless remains an explicit supported/tested policy operation for the documented temporal boundary.

### Coordinates and logical layout

For local `x,y in 0..7`, `X=8*bx+x`, `Y=8*by+y`:

```
Xr = X if X<W else 2*W-X-2
Yr = Y if Y<H else 2*H-Y-2
u = DIV.approx.ftz(F32add.ftz(F32_RN_s32(Xr), .5), F32_RN_s32(W))
v = DIV.approx.ftz(F32add.ftz(F32_RN_s32(Yr), .5), F32_RN_s32(H))
tex_axis = F32mul.ftz(F32fma.rn.ftz(coord, extent, offset), post_scale)
```

**ONE upper-side mirror only**; no lower-side handling, repeated reflection or sampler clamp substitution. Odd dimensions are not universally forbidden: width7/CTA0 and width9/CTA1 are admissible; width5/CTA1 is rejected because later pixels require more than one mirror. Conservative dimensions `2..2^30-1` avoid original signed coordinate/doubling overflow. Noise uses **unmirrored `(X,Y)`**.

Logical features:

```
[noise0,noise1,noise2,H(1), sourceR,sourceG,sourceB,
 guideR,guideG,guideB,H(Style@180), tone11,structure12,skin13,structure14,H(+0)]
```

`p=8*y+x`, shared byte address `1024*(c//8)+16*p+2*(c%8)`. The candidate's axes are explicitly **[x][y][16]**, not old row-major `[pixel][feature]`. All 2048 bytes are tested for exact single coverage. This is not a graph-port/output geometry claim and does not repeat the rejected factor-of-four composition.

### Integer/noise equations

Every product, mad and integer sum result below is reduced mod `2^32` **before** later shifts. All right shifts are logical.

```
z = u32(X*-1918454973) XOR u32(Y*-669632447)
    XOR u32(seed*-1640531527) XOR 608135816
r = u32(((z >> ((z>>28)+4)) XOR z) * 277803737)
state = r XOR (r>>22)
```

Four rounds use **the same `state`**, not a chained evolving state:

```
(a,b) = (747796405,-1403630843), (-93469191,1192405134),
        (-895109107,568162667), (-2094846927,878960812)
t = u32(state*a+b)
q = u32(((t >> ((t>>28)+4)) XOR t) * 277803737)
word = u32(((q>>30) XOR (q>>8))+1)
U = F32mul.ftz(F32_RN_u32(word), bits(0x33800000))
```

`word` is in `[1,2^24]`; no logarithm-at-zero workaround is necessary. For U0/U2 independently: `L=LG2.approx.ftz(U)`; `N=F32mul.ftz(L,0x3f317218)`; `R=SQRT.approx.ftz(F32mul.ftz(N,0xc0000000))`. Angles separately multiply U1/U3 by **literal `0x40c90fdb`**, then SIN/COS.approx.ftz. Finally each radius/trig multiplication is **F32 RN/FTZ then half RN**. No algebraic flattening of ln(2), -2, radius or angle products.

### Color and half rounding

```
scale_h = H(F32add.ftz(gain@196, gain@196))
normalize(c) = Hmul(Hsub(H(c), H(.5)), scale_h)
```

Each `H`, `Hsub` and `Hmul` rounds separately to half; **no half FTZ**. F32 gain addition has input/output FTZ. No source-sample FTZ is inserted before the unmodified half conversion. Source alpha is ignored. `gain=.75, source=.2` gives **half `0xb734` = -0.4501953125**, not flattened `H(.2*1.5-.75)`. Zero gain preserves the original signed-zero half multiplication, not an invented all-positive-zero vector.

At first counter zero, guide channels are the original **bitwise copy of the already normalized source**, PTX lines **325–328**. There is no second texture or second normalization in that branch. A future reprojected guide must normalize **its reconstructed F32 RGB separately** with the same three half boundaries, never normalize/blend already-normalized source as a substitute.

### Plain and approximate numeric scope

All plain F32 add/sub/mul/FMA use exact rational arithmetic then RN-even F32, with **signed FTZ on each operand/result**. FMA is one rounded product-plus-add, not two operations. Integer-to-F32 and F32-to-half conversions do not inherit an absent FTZ modifier. Half operations preserve gradual subnormals and signed zero. RN ties, FMA-vs-split distinction, all finite half round trips, and randomized finite binary operations are independently tested with `struct` conversions.

Finite consumed input/results only: consumed NaN/Inf and overflow are rejected, not sanitized. Native exceptional behavior is intentionally not claimed. Ignored sampler components still require raw uint32 encoding, but their floating value may be NaN because no operation consumes them.

**DIV/RCP/LG2/SQRT/SIN/COS always cross `ApproxPolicy`.** Optional `reference_nonnative()` explicitly chooses exact rational RN for DIV/RCP and platform host-libm binary64 then RN F32 for other operations. That is **not PTX approximation bit/error emulation** and is never selected by default. Wrapper FTZ applies before and after the callback. Native approximate ops, native compiler instruction selection/contraction, selected native-code-vs-PTX path, and actual GPU bits remain unverified.

## 2. Controls and full64 counter are not UI guesses

Fresh launcher stores corroborate aggregate origin `A=RSP+0x70=RBP-0x90`, 264-byte length and pointer-to-pointer dispatch, scalar stores, qword counter copy and pre-dispatch increment. Named-control/resource origins below additionally use `old_pre_binding_report.md`.

| Offset | Binding / required interpretation |
|---:|---|
|172|Effective `LocalToneStrength`, gated by model descriptor byte+0x60 (network N+0x68)|
|176|Effective `LocalStructureStrength`, same gate|
|180|Clamped `Style` index /128, separately gated by descriptor+0x62; **not Intensity**|
|184/188|Effective skin/structure overrides; ControlMask takes precedence over UseAutoMask derivation|
|192|Model descriptor byte+0x61 normalized to 0/1 (N+0x69), **not UseAutoMask**|
|196|Host literal **1/16**, independently reread at `0x1800b80e8`; candidate honors explicit ABI gain bits, including synthetic .75 tests|
|200..207|Pre-increment **u64 invocation count**; noise reads only +200 low32; +204 is real host high32 storage|

For finite controls `B=@172,C=@176,a=@184,b=@188,M=u32@192`:

- **T4 present:** sample T4; `11=H(F32mul.ftz(T4.Y,B))`, `12=H(F32mul.ftz(T4.Z,C))`; `13=14=H(-1 if M!=0 else +0)`. Ignore T4.X/W and override values. Mask remains active at counter zero.
- **T4 absent, M=0:** `11=H(B),12=H(C),13=14=H(+0)`. No synthetic sample and **no actual multiply by 1**.
- **T4 absent, M!=0:** compare FTZ values of a/b. If `max(a,b)>=0`, `11=H(B),12=H(1),13=H(C if a<0 else a),14=H(C if b<0 else b)`; otherwise `H(B),H(C),H(-1),H(-1)`. Selected raw bits, not comparison-flushed replacement values, feed H. Original unordered comparisons on NaNs are outside the admitted finite domain.

With no mask, effective UseAutoMask derives a/b: when enabled, skin is SkinStructureStrength if nonnegative else LocalStructureStrength, structure is LocalStructureStrength; otherwise both -1. A control-provider path can override effective named request fields. These are **not default values for this candidate**; actual post-provider/model-gated ABI is caller input.

Launcher gating uses **64-bit** `test rax,rax` at `0x180060e15` on S+0xc8; copies old qword at `0x180060f39..40`; increments at `0x180060f44`. At count `2^32`, seed=0 but temporal handles stay eligible. At `2^64-1`, next host count wraps to0. The candidate requires full64 zero and rejects nonzero T1/T2/T3 instead of mutating them. `launcher_texture_gate` is a separately named pure gate helper, not a stateful execution or resource fill. Counts are invocations, not demonstrated frame numbers, GPU completions or entropy. Concurrency/reset-to-counter linkage is not reconstructed.

## 3. Sampler descriptor and native boundaries

Fresh byte windows corroborate the old Vulkan report's sampler creation/getter proof; API member offsets/enums are inherited from that allowed report's prior header checks (no outside header or network read here).

`VkSamplerCreateInfo S=RBP-0x60`, `0x1800506c5..75a`:

| Member | mode0 / backend+0x570 | mode2 / backend+0x580 |
|---|---|---|
|flags|0|0|
|mag/min|1/1 = LINEAR|0/0 = NEAREST|
|mipmap|0 = NEAREST|same|
|address U/V/W|2/2/2 = CLAMP_TO_EDGE|same|
|unnormalizedCoordinates|0 = normalized|same|
|anisotropy / comparison|disabled|same|
|maxAnisotropy|1.0|same|
|LOD bias, minLOD, maxLOD|0,0,0|same|

R12 starts zero, its preservation is checked across the corrected window, and the second create changes only mag/min via the zero qword at `S+20`. Loader literals/stores establish `vkCreateSampler -> backend+0x498`, `vkGetImageViewHandleNVX -> +0x520`, `vkGetImageViewHandle64NVX -> +0x528`.

At `0x18004fb50`, sampled getter builds **COMBINED_IMAGE_SAMPLER** descriptor type1 and selects `backend+0x570+8*sign_extend(mode)`. Backend byte+0x854 selects 32/64-bit NVX getter. The 32-bit branch zero-extends; the 64-bit result is stored unchanged. **Raw handle high words are not filter enums**, and no driver bitfield is decoded here. Storage descriptors have a different producer; never reinterpret them as sampled handles.

On the recovered frontend, **T0/T2/T4 are mode2, T1 is mode0; T3 is zero**. The sampler creation flags are therefore not wholly unknown on that conditional Vulkan path. Nevertheless the raw NVX internal descriptor flags, actual descriptor/resource association, imported T0/T2/T4 formats/swizzles, texel snapshot, subtexel/filter precision, format conversion, and native arithmetic are not captured. The previous report establishes a **new H+60 RGBA16F allocation path**, not today's bytes or all cache/import cases. There is **no general T3 sampler binding proof**.

Accordingly no default nearest/linear host image sampler is implemented. Mathematical ideal footprints alone would not justify native bit claims. The explicit raw-F32 `SamplerPolicy` is the hard boundary even when known high-level Vulkan modes are available. Caller `native_bit_oracle=True` is only an attribution, not a validation by this program.

## 4. Beyond first counter: exact gates; no temporal resource invention

### Host and PTX gates

Conditional on the recovered block0/no-block-output-edge/matching-first-layer path and ordered gather `[0,1,2,3]`, launcher input vector is `I=[external_selected_source,N.298,N.2a0,N.2a8]`. Fresh selected windows corroborate pair/global gates; full upstream naming/routing is inherited from the binding report.

- T0=I[0], selected Color/Backbuffer sampled view, mandatory. Not proven pristine original RGB and not named `dlssnr_original_color` allocation.
- Frontend T1/T2 require `H.byte68!=0`, effective `Reset==0`, MVec and H+60 nonnull, successful views. Setter global byte `0x1800e06d0==0` additionally clears both.
- Launcher T1=I[1] only when count>=2 and **full64 counter!=0**, T2=I[2] when count>=3 and counter!=0, T3=I[3] when count>=4 and counter!=0; otherwise each is zero.
- Frontend explicitly supplies **R9D=0 at 0x180022623**; setter writes N+0x2a8. Thus T3 is zero here **despite a genuine Depth getter**. Do not bind requested Depth to it. Other callers remain unproved.
- T4=**S+0xa8**, independent of counter/vector length, **not I[4]**. It is the effective ControlMask view with its independent transform.
- PTX: if **T1==0 OR T2==0**, guide copies source; T3 is never sampled. With both present, T3 null skips selector only; T2 is sampled once and T1 five times. T4 is independently controlled as above.

### Exact T3 selector and five-tap reconstruction boundary

This section documents source equations only; **candidate deliberately rejects this temporal execution**. Every F32 operation below carries the source RN/FTZ boundary. Let `A,S,M,F` denote F32 add, sub, mul and single-round FMA; `D,R` denote explicit approximate DIV/RCP.

1. Optional T3 samples center, TL, TR, BL, BR using normalized offsets `dx=R(T3.extentX)`, `dy=R(T3.extentY)`, followed by its own FMA/mul transform. Compare **X only**. `@168==0` chooses strict minimum; nonzero strict maximum. Ties **and unordered comparisons** keep the prior selection. Selected normalized offset is `M(selected_dx,D(T3.extentX,T2.extentX))` and Y analogue. T3 null yields the original explicit zero offset, not a dummy resource.
2. Sample T2 at transformed `A(u,selected_dx),A(v,selected_dy)`. Reproject `coordX=M(F(T2.X,@160,u),F32(W))`, `coordY=M(F(T2.Y,@164,v),F32(H))`. **FMA**, not flattened multiply/add. T2.Z/W are unused.
3. For each axis, `base=A(floor_ftz(A(coord,-.5)),.5)` and `f=min(max(S(coord,base),0),1)`. Source-order weights:

```
f2=M(f,f); f3=M(f,f2)
w0=F(A(f,f3),-.5,f2)
w1=A(S(M(f3,1.5),M(f2,2.5)),1)
w3=M(S(f3,f2),.5)
w2=S(S(S(1,w0),w1),w3)
wm=A(w1,w2)
```

4. Positions `A(base,-1)`, `A(D(w2,wm),base)`, `A(base,2)` are each max-then-min clamped to **[.5, ingress_extent-.5]**, multiplied by `R(ingress_extent)`, then independently transformed for T1. This clamp is to ingress W/H, not an assumed physical T1 image dimension.
5. T1 taps in source order: **LM, MT, MM, MB, RM**. Weights `a=M(w0x,wmy)`, `b=M(w0y,wmx)`, `c=M(wmx,wmy)`, `d=M(w3y,wmx)`, `e=M(w3x,wmy)`. Denominator order: `s0=A(b,a); s1=A(c,s0); s2=A(d,s1); s3=A(e,s2); inv=R(s3)`. Each RGB numerator: `n0=M(b,MT); n1=F(a,LM,n0); n2=F(c,MM,n1); n3=F(d,MB,n2); n4=F(e,RM,n3); reconstructed=M(inv,n4)`.
6. Separately `H(reconstructed)`, `Hsub(...,H(.5))`, `Hmul(...,scale_h)` for guide RGB. Not one bilinear lookup, not sixteen-tap gather, not unrenormalized cubic, not reusing source sample values.

### Genuine history/state gaps

The previous Vulkan/history report establishes resource-level NR-result history, **not `history=selected_color`**. H+60 can be direct network output, or receive a separate `cg2r_copy_kernel` dispatch. On ordinary equal-size paths network Output is later sent Output→history; size/subrect paths can reverse outer direction history→Output after NR is routed to H+60/H+70. Special/fused frontend processing differs.

The copy is a compute shader, **not `vkCmdCopyImage` or a proved identity assignment**. Its exact coordinates, shader arithmetic, alpha/store conversion, dispatch success/order, exceptional paths and current resource contents are not lifted. Reset suppresses history use; validity bookkeeping can be set before outer copy and is not GPU completion or an image clear. Counter reset has its own host method, without a newly proven direct Reset→counter-reset chain. No arrays of zeros stand in for these resources, no numerical temporal recurrence is invented, and no current T1/T2/resource identity is claimed observed.

## 5. Verification and handoff

Run from this `out/` directory (all logs retained):

```
PYTHONDONTWRITEBYTECODE=1 python -B test_preprocess_candidate.py
PYTHONDONTWRITEBYTECODE=1 python -B static_checks.py
PYTHONDONTWRITEBYTECODE=1 python -B static_supplement.py
PYTHONDONTWRITEBYTECODE=1 python -B static_boundary_correction.py
PYTHONDONTWRITEBYTECODE=1 python -B verify_source_prefix.py
```

**15 tests pass**, including exhaustive 63,488 finite half bit-pattern round trips, RN ties/subnormals/signed zero/FMA, 1,500 random finite primitive cases, gain .75/source .2 → b734, zero gain, uint32 hash wrapping via independent NumPy formulation, four-round shared state, all six explicit approximate ops, source-guide copy, [x,y,16]/2048-byte packing, transformed coordinates, odd/single-mirror rejection, required sampler/policy failures, mask precedence/real response requirement, full64-vs-low32 and counter wrap. These are **feature-only synthetic tests, not a native or old-interpreter equivalence oracle**.

Static runs validated API strings/stores, literal host gain, corrected R12 preservation and bounded literal source sites. No test failure occurred; the discovered disassembly-boundary correction and all earlier successful logs remain visible rather than rewritten. No input mutation or outside project file discovery was performed.

Remaining review gates: actual entry/module/264-byte launch association and arguments, raw sampler responses or independently justified sampler policy, actual control/provider/model state, native approximate bits, producer/resource closure, and all learned computation. If separately authorized later, Main may gate a read-only runtime capture of these facts or a native-op microcomparison. **This worker did not dynamically load anything and does not authorize that experiment or a full-network run.**

## Actual read paths and budget

Project inputs actually read (absolute, no outside report/link targets followed):

1. `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/04-ingress-sampler/PACKET.json`
2. `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/04-ingress-sampler/in/old_ingress_report.md`
3. `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/04-ingress-sampler/in/old_ingress_reference.py.txt`
4. `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/04-ingress-sampler/in/old_pre_binding_report.md`
5. `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/04-ingress-sampler/in/pre0.ptx` (only lines1–610; read twice)
6. `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/04-ingress-sampler/in/vulkan_sampling_history_report.md`
7. `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/04-ingress-sampler/in/main_rejected_geometry.md`
8. `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/04-ingress-sampler/in/pre_identity.json`
9. `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/04-ingress-sampler/in/pe_readonly.py` (text review only; **not imported/executed**, because it reads the whole DLL)
10. `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/04-ingress-sampler/in/nvngx_dlssnr.dll` (only bounded header/.text/.rdata reads enumerated above)

**30 bounded project-input read operations:** 9 initial tool reads (including packet), 11 first-static physical reads, 7 supplement reads, 2 correction reads, 1 bounded source audit. Every text read <=610 source lines or the requested <=2000 report lines; no output was truncated. PE limits: 14/32 .text target windows, largest 1,078/4,096 bytes, 0/2 scans. `pre_code_index.txt`, `pre_inventory.json`, `pre_slab.bin`, `old_pre_full_report.md` were **not read**. Self-authored `out/` scripts/modules/logs and final contract/report are used for tests/review only; normal Python/NumPy/Capstone imports are tooling, not additional project discovery.

## Files created (all under this task's `out/`)

- `preprocess_candidate.py`: independent high-level feature/numeric/gate implementation.
- `approx_policies.py`: explicitly opt-in nonnative test policy.
- `test_preprocess_candidate.py`, `test_run_01.log`: synthetic tests and passing log.
- `INPUT_CONTRACT.json`, `REPORT.md`, `PROGRESS.md`: review contract, findings and status.
- `static_checks.py`, `static_supplement.py`, `static_boundary_correction.py`, `verify_source_prefix.py`: bounded reproducible static/source checks.
- `STATIC_EVIDENCE.json`, `STATIC_SUPPLEMENT.json`, `STATIC_BOUNDARY_CORRECTION.json`, `SOURCE_PREFIX_EVIDENCE.json`: exact byte/source evidence, including retained correction.
- `static_disasm.txt`, `static_run.log`, `static_supplement_run.log`, `static_boundary_correction_run.log`, `source_prefix_run.log`: retained evidence/run logs.
- `verification.json`: final local artifact/contract/scope audit (no new project-input reads).
