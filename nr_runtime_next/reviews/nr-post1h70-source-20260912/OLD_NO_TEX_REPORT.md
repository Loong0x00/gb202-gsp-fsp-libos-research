# Original finalpost, no textures: static exclusion complete; launch still BLOCKED

## Decision and scope

**A=B=C=0 excludes ALL 14 original TEX instructions on BOTH output paths.** This is the original kernel's implemented optional-source path, not handle masking, kernel patching, an image-input API, or evidence of full-model execution. The claim is architectural non-execution of TEX under the original null gates; it does not promise that earlier memory operations cannot fault.

Prepared **`blockedhost.cpp`**, a separate clone of the hard-blocked `../nr-original-finalpost-probe-20260911/host.cpp`. It has no texture objects, source arrays, texture API symbols/calls, or source fixture. Only owned main/skip/slab/blend allocations and an owned RGBA16F output array/surface remain. The full opaque `CUsurfObject` is packed unchanged at +16. Main approval/runtime hard gate remains **false**, before Driver loading, with no CLI/build-option override. **Do not ungate on the strength of this static proof.**

The proposed scope is **ORIGINAL compiled neural arithmetic plus formatted surface output on synthetic internal main/skip features**, using the original finalpost slab. It is **NOT actual-image processing, the full model, native numerical parity, or a performed GPU experiment**.

Read the preceding `nr-original-kernel-object-abi-20260911/REPORT.md`: surface low-word operand convention has compiler-backed support; raw-TEX high-word compatibility remains unproved. This review **avoids executing raw TEX altogether**; it does not solve its ABI for nonzero textures. Compiler-backed surface evidence is retained, not replaced with manual handle truncation or descriptor fabrication.

## 1. Exact provenance and proof method

* Untouched original ELF: 2,789,376 bytes, SHA-256 `feb368ff5279a7408b1e55554db6e468d7f114a24b18b2af8d7e6989a410c612`.
* Selected `.text`: SHA-256 `3e74332575bc4d8f579135269853ea8eff67d22a3a01a010a8c4bb1bd789c900`.
* Exact original PTX: 265,352 bytes, SHA-256 `b2471a490b1c5a8817689d14358d648283823ced2165f84b0fef3e13ee928bc8`.
* Fresh CPU `cuobjdump` disassembly: **all 3,336 instructions**, including padding, tile and byte-match that original text, in 16-byte units. Exact selected metadata retains **API 0x86**, Mercury 1.1, parameter base 0x380 and size 0xb8. No ELF modification, PTX compilation, PTX header downgrade, device compilation or alternate module path.
* `prove_exclusion.py` enumerates every TEX, builds whole-entry direct-control-flow graphs, verifies slice-entry/endpoint dominance and no alternate interior entries, and evaluates the actual predicate instructions of four SASS slices. Reconvergence targets are added as conservative extra edges; unknown branches can take either edge. History skip targets cannot return to any skipped TEX. No learned number, coordinate, bounds result, decode flag or blend value is substituted to make the gates pass.
* Predicate domains are `{false}`, `{true}`, or `{false,true}`. Null constants come from actual `LDCU.64` parameter loads. U64 checks consume both words. Boolean conjunction with a known false is false even if other inputs are arbitrary. Unrecognized operations inside proof slices fail. PTX independently uses its actual predicate/branch instructions and full-source reachability, not just matching null-check strings.
* Semantic mutation tests operate on in-memory instruction/source copies only. Production proof separately requires the pinned original bytes. No mutant is compiled, saved as device code, or launched.

This is a bounded static control-flow certificate, **not a full SASS interpreter, formal ISA proof, or driver/runtime test**. Its SASS semantics use the ordinary meanings of the disassembled U64 comparisons, predicate LUTs, vote and branch instructions, consistent with the prior compiler witnesses. `evidence/control-and-color-slices.txt` provides the exact chains for manual review; `evidence/exclusion.json` records every excluded site.

## 2. ALL original TEX sites and SASS chains

Offsets below are aggregate offsets; `c0[0x380+offset]` is the corresponding parameter location. A=+56, B/history=+88, C/motion=+96.

| Path | TEX sites (hex PC) | Excluding chain |
|---|---|---|
| 0 A | **9e40** | `9d10 LDCU.64 UR8,c0[3b8]`; `9dc0 ISETP.EQ.U64.OR P1,PT,RZ,UR8,P1`; `9e40 @!P1 TEX` |
| 0 C | **a210** | common history gate below |
| 0 B | **a770, a7a0, a7b0, a7c0, a7d0** | common history gate below |
| 1 A | **c380** | `c250 LDCU.64 UR8,c0[3b8]`; `c300 ISETP.NE.U64.AND P1,PT,RZ,UR8,P0`; `c380 @P1 TEX` |
| 1 C | **c750** | common history gate below |
| 1 B | **cca0, cce0, ccf0, cd00, cd10** | common history gate below |

### A, path 0

`9d20/9d60` form the coordinate rejection condition in P1. `9dc0` ORs it with the **64-bit A==0** condition. Hence P1=true for every active lane regardless of coordinates. `9de0 VOTEU.ALL UP0,P1` is true; the `9e10 @!UP0` full-pair object load is disabled. P1 is not redefined before **`9e40 @!P1 TEX`**, so the fetch is disabled independently of that uniform-load optimization.

### A, path 1

`c260/c2a0` form the source bounds condition P0. `c300` sets P1=`(A!=0) AND P0`, so P1=false. `c320 VOTEU.ANY UP0,P1` is false, disabling `c350 @UP0 LDCU.64`. There is no P1 redefinition before **`c380 @P1 TEX`**. This proves the fetch disabled even if coordinates/learned registers are unconstrained.

### B/C, path 0

```
a090 LDCU.64 UR10,c0[3d8]                 // B +88
a0d0 LDCU.64 UR12,c0[3e0]                 // C +96
a110 UISETP.NE.U64.AND UP0,UPT,UR10,URZ,UPT
a120 UISETP.NE.U32.AND UP0,UPT,UR9,URZ,UP0 // also decode !=0
a130 ISETP.NE.U64.AND P1,PT,RZ,UR12,P1     // also bounds
a140 PLOP3.LUT P2,PT,PT,PT,UP0,0x80,0x8   // P2=UP0
a150 PLOP3.LUT P1,PT,P1,P0,P2,0x80,0x0    // P1=all three AND
a170 @!P1 BRA 0xaa60
```

B=0 forces UP0/P2=false; C=0 independently forces P1=false. P0 is the blend-positive comparison and may have either value. The branch skips **all six** C/B fetches and rejoins at `aa60/aa70`, before `aa80` surface-object load and `aa90 SUST`.

### B/C, path 1

`c610 LDCU.64 UR4,c0[3d8]` loads B, `c650 LDCU.64 UR8,c0[3e0]` loads C. `c660/c670` compute UP0=`B!=0 AND decode!=0`; `c680` ANDs `C!=0` into P0 (the retained bounds predicate). `c690` copies UP0 to P2; `c6a0` sets P0=`P0 AND P1 AND P2`, where P1 is blend-positive. **`c6b0 @!P0 BRA 0xcfa0`** skips all six C/B fetches, rejoining before `cfc0` object load and `cfd0 SUST`.

Thus A=0 and **either** B=0 or C=0 already suffice; the proposed contract more strictly requires **all three zero**. Tests include all 27 combinations of each handle being zero, low-word-only nonzero, or high-word-only nonzero. Cases outside that sufficient condition correctly fail to prove exclusion; nonzero-only-high32 is never mistaken for null.

## 3. Independent exact PTX check

Initial immutable loads: line 1368 `%rd4=param+56`, line 1369 `%rd5=param+96`.

* Path 0 A: line **13878** `%p177=(A==0)`; `%p181=bounds_reject OR %p177`; branch to `$L__BB5_51` (13923), bypassing TEX **13915**.
* Path 1 A: line **16006** `%p255=(A!=0)`; `%p259=bounds_ok AND %p255`. The source branch is not taken; unconditional branch to `$L__BB5_62` (16053) bypasses TEX **16045**.
* Path 0 history: `%p187=(C!=0)`, `%rd9=param+88`, `%p188=(B!=0)`. The complete AND chain through `%p195` is false; `%p196=true` branches to **14123**, bypassing TEX **13985, 14077–14081**.
* Path 1 history: corresponding `%p265/%p266`, `%rd10=param+88`, `%p273/%p274` branch to **16258**, bypassing TEX **16118, 16212–16216**.

All 14 TEX occurrences are inventoried, not only source A. Both PTX and corresponding original SASS proofs pass.

## 4. No-A arithmetic, signed zero and rounding

With decode flag **1**, scale **1/32**, history disabled, each RGB channel is mathematically

```
NoAcolor = clamp(8 * (learned / 32) + 0.5, 0, 1); alpha = 1.
```

Original no-A SASS uses `9f30..9f50 @P1 FMUL.FTZ` on path 0 and `c470..c490 @!P1 FMUL.FTZ` on path 1. The subsequent decode uses `FFMA.FTZ` with 8 and .5, then `FADD.FTZ.SAT` with RZ (`9f80..9fe0` / `c510..c560`). These are before the skipped history blocks and unchanged formatted surface stores.

A mathematically constant A=.5 has contribution `fma(.5,.125,-.0625)=0`, but **do not blindly assert identical intermediates**: for learned=-0, no-A multiplication preserves -0, whereas source-present RN FMA with +0 yields +0. Our test demonstrates that exact predecode bit difference with decode disabled. With the required decode enabled, both yield .5. CPU finite-FP16 exhaustive checks cover **63,488 values**, including ±0, subnormals and extrema: both paths' selected color formula agrees bitwise with the .5-source diagnostic after decode under the named FP32 RN/FTZ policy.

The multiplication scale and expansion of finite half inputs are exact here; the decode FMA still has FP32 rounding boundaries. This CPU result uses glibc `fmaf` with FE_TONEAREST checked, and is **not a native numerical measurement**. NaN/Inf arithmetic inputs fail closed in the reference; TEX exclusion itself does not depend on finiteness. Original SASS saturation/NaN behavior, native MMA accumulation/contraction, approximation instructions, and formatted RGBA16F conversion rounding are not proved by this finite test. Stored diagnostic RN-half values are labelled **NOT surface proof**.

Both full connected CPU-reference policies ran from the synthetic main/skip fixtures through the finalpost arithmetic to 64 stores, with **zero source-sampling calls**:

* `RN_f32_reference`;
* `measured_SM120_half_input` (reads existing pinned CPU-side RCP/RSQRT measurement tables, makes no GPU calls and rejects out-of-domain inputs).

Both explicitly use `exact_inner_dot_then_RN_half_reference_NOT_native_equivalence`. Each fixture result has RGB range approximately **0.4954338074–0.5035247803**, alpha 1. These are CPU predictions, not GPU outputs or a parity assertion.

## 5. Owned resources, launch contract and hard gate

Preserved: one **184-byte** argument aggregate; output **16x16**, origin **(0,0)**, grid **(1,1,1)**, block **(32,1,1)**, decode **1**, multiplier **1/32**. All pointer/object slots in the template are cleared before filling owned allocations. +56/+88/+96 remain exactly zero; no source arrays/texture creation or destruction/readback calls exist.

| Resource | Owned bytes / shape | Purpose |
|---|---:|---|
| main | 1472 | synthetic finite E4M3 internal features; full allocation initialized |
| skip | 3072 | synthetic finite E4M3 internal features; full allocation initialized |
| slab | 21808 | original encoded finalpost bytes, unchanged |
| blend +104 | **2** | actual original FP16 coefficient, **0.73974609375**, not zero/null substitution |
| output | 16x16 RGBA16F | surface-enabled array, all initialized to half poison `0x7e55` |

**Blend must stay allocated.** The pointer has its own null check, but with the required nonnull owned pointer the 16-bit loads **`a040 LDG.E.U16`** and **`c5c0 LDG.E.U16`** occur before the B/C gates `a170/c6b0`. Null history does NOT suppress these loads. PTX likewise loads `%rs436` / `%rs499` before history conjunctions. Allocation extent and fixture are checked; it is freed only in normal owned-resource cleanup after draining.

The slab is copied from original raw weight-file offset 147406312 (SHA `197024afb1f78602dc08cfd5ae87c413385237c5f537dd5dcfeae742be85eca8`); blend comes from raw file offset 147406234. Whole weight-file provenance is checked by the existing upload contract. Main/skip independent read sets and complete CPU prefix/prehead execution fit the minimal extents. This is not a complete original-SASS address proof.

The two store maps cover exactly 64 unique pixels in an 8x8 tile; 192 outside pixels must remain byte-exact poison. Original formatted X is a **pixel/sample index**, not an 8- or 16-byte-scaled index. Surface object from `cuSurfObjectCreate` is passed **whole and unchanged**; the compiler-supported low-word SASS convention is not implemented as a host-side mask. Pure CPU packing tests use a high-word-nonzero sentinel only, never a runtime handle, to verify all 64 bits survive.

The clone retains original ELF hash validation, no fallback module/JIT path, exact SM120 check, owned context/module/resource lifecycle, post-launch synchronization before reads, error records and drain-aware cleanup. Its planned launch is never reached: `main_approval_and_runtime_contract_established=false`, missing/malformed CLI returns 64 and well-formed proposal syntax reaches return 78 before `proposed_run`. The worker **did not invoke that executable**, even with `--help`. Only the separate **pure CPU packing-test executable** ran; it calls packing validation, not the proposal entry or Driver.

## 6. Remaining blockers: do not blindly ungate

1. **Main reviewer approval and operational authorization** remain absent. No GPU initialization, Driver loading, resource creation, module load, launch, synchronization, Wine, or GPU run occurred.
2. Untouched **API0x86/Mercury1.1** ELF acceptance by the installed Driver remains untested. Host-only compilation with the current **CUDA_VERSION=13030** headers is not that test.
3. Runtime-owned resource/opaque-surface compatibility and formatted RGBA16F conversion remain unmeasured. The prior compiler-backed surface convention is narrow evidence, not a formal cross-version SASS ABI or operational guarantee.
4. Hidden constants **c0[0x358]** (global-memory descriptor) and **c0[0x37c]** (prologue convention) are not supplied or fabricated by this host. Loader population and the original full memory-descriptor contract remain unproved. On-disk zero constant banks do not prove runtime values. Complete SASS memory/resource safety remains a separate review boundary.
5. Numerical parity remains open: native neural MMA arithmetic/approximations/contraction, output conversion and execution-time memory behavior were not measured. This reference is not an image/model test.

The raw texture high-word uncertainty remains for **any nonzero texture family**, but is not an executed-operand boundary in this strictly null-texture proposal. No previous gate or installed file was changed.

## 7. Reproduce and retained evidence

```
bash reviews/nr-original-finalpost-no-texture-20260911/verify_cpu.sh
```

CPU/static only: fresh cuobjdump and byte/metadata checks, g++ host-only C++20 builds with `-Wall -Wextra -Wpedantic -Werror`, `readelf -d`, **17 passing Python tests**, **188 rejected pure-CPU argument mutants**, 27 handle combinations, all 14 alternate-TEX-entry mutants, all 12 history-target mutants, 10 predicate/load mutants, 5 PTX mutants, unsupported-op/extra-TEX rejection, exhaustive finite-half semantics, and both full CPU-reference policies. No CUDA library is linked into the proposal.

`EXTERNAL_PINS.json` plus `provenance_cpu.py` check 23 external inputs and six earlier ABI-review source pins. Read-only `sha256sum -c` checks of both prior reviews' complete `SHA256SUMS` passed; logs are retained. Git status was unavailable because this working directory is not a Git repository; integrity is recorded with hashes instead. Every write is beneath this new review directory. `FILES_CHANGED.txt` enumerates exact files; `SHA256SUMS` pins the retained deliverable.
