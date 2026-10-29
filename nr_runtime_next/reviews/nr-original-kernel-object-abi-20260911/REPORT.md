# Original SM120 object ABI: surface evidence improved; keep launch BLOCKED

## Decision

**The surface low-word operand convention is supported by the compiler witnesses. The complete object ABI is NOT established: original TEX uses a raw two-uniform-register input, whereas documented CUDA `tex2D<float4>` explicitly supplies `{object.low32, 0}`. Keep the existing host gate unchanged.**

This is a static device-code/compiler review, not an experiment with opaque handles. No GPU discovery, CUDA initialization, Driver loading, Wine, resource creation, module loading, or kernel execution occurred. All writes are below this review directory. The original ELF and PTX were neither patched nor recompiled. The old `nr-original-finalpost-probe-20260911/SURFACE_ABI.md` and `host.cpp` remain unchanged.

## 1. Reproducible witnesses and byte provenance

Run CPU-only verification:

```sh
python3 reviews/nr-original-kernel-object-abi-20260911/verify_cpu.py
```

`evidence/commands.json` records every verification compiler/disassembler command. `TMPDIR` and nvcc `--keep-dir` are inside this directory. There is no host executable or launch harness here. `witness.cu` has a single 184-byte, align-8 aggregate: surface at +16 and source-A texture at +56, matching original offsets. Compile-time assertions enforce these offsets and size.

Built with `/opt/cuda/bin/nvcc`, **13.3.73**, `-arch=sm_120 -std=c++17 --cubin`:

* `documented_surface`: documented `surf2Dwrite(float4, cudaSurfaceObject_t, x, y, cudaBoundaryModeZero)`.
* `original_formatted_surface`: the same unchanged `cudaSurfaceObject_t` input, constraint `"l"`, to exact inline PTX **`sust.p.2d.v4.b32.zero`**. No handle arithmetic, truncation, reinterpretation, or dereference.
* `documented_texture_rgba`: documented `tex2D<float4>(cudaTextureObject_t,u,v)`; retains all components.
* `documented_texture_rgb`: the same documented call, retaining RGB only, matching original mask `0x7`.
* `documented_surface_half_bits`: documented raw `ushort4` surface write, an 8-byte HALF-storage control, **not** FP32-to-HALF conversion.

Supplemental controls: original-like 64-bit texture null test; direct ptxas compilation of **our generated PTX only**, with default settings, `-O0`, and `--set-texmode-raw=true`. The last is a diagnostic of the original raw convention, **not evidence that raw mode is a documented CUDA-object interface**. No original PTX version downgrade occurred: original bundle PTX remains **9.4**, our generated PTX is **9.3**, both target SM120.

Fresh cuobjdump outputs are checked instruction-by-instruction against ELF `.text` bytes, not merely entry names or opcode strings:

| Artifact | Bytes | Byte-checked instructions |
|---|---:|---:|
| Exact original ELF, selected entry | 2,789,376 | **3,336** |
| `build/witness.cubin` | 17,776 | 120 |
| `build/texture_control.cubin` | 21,208 | 152 |
| `build/witness_ptxas.cubin` | 17,776 | 120 |
| `build/witness_o0.cubin` | 19,376 | 216 |
| `build/witness_raw.cubin` | 17,776 | 120 |

Every cuobjdump PC tiles the entire selected `.text` section in 16-byte instructions. **728 own instructions checked**, including alignment padding. Independent `nvdisasm --print-life-ranges --print-instruction-encoding` output is also byte-checked for original/default/raw witnesses. nvdisasm omits trailing NOP padding; those omitted bytes are still covered by cuobjdump (original nvdisasm count 3,328 versus complete count 3,336).

Original ELF SHA-256: `feb368ff5279a7408b1e55554db6e468d7f114a24b18b2af8d7e6989a410c612`.
Original selected text SHA-256: `3e74332575bc4d8f579135269853ea8eff67d22a3a01a010a8c4bb1bd789c900`.
`RESULT.json` pins every cubin, selected text/info section, compiler/disassembler, relevant installed header, and unchanged external input. `SHA256SUMS` pins this review's retained files.

Original and witness metadata both declare parameter-bank base **0x380**, aggregate size **0xb8**, Mercury ISA **1.1**. Original CUDA API **0x86**, own compiler CUDA API **0x85** remain different and unmodified. Same architecture/instruction convention is not a module-load compatibility test.

## 2. Surface: the missing compiler-to-original bridge now exists

| Path | Object definition | Use |
|---|---|---|
| Original branch 1 | `aa80: LDCU UR8, c[0][0x390]` | `aa90: SUST.P.2D.STRONG.SM.IGN [R52], R12, UR8` |
| Original branch 2 | `cfc0: LDCU UR4, c[0][0x390]` | `cfd0: SUST.P.2D.STRONG.SM.IGN [R52], R8, UR4` |
| Our formatted witness | `0020: LDCU UR4, c[0][0x390]` | `0080: SUST.P.2D.STRONG.SM.IGN [R2], R4, UR4` |
| Our documented float4 write | same load, same parameter | `0080: SUST.D.BA.2D.128.STRONG.SM.IGN [R2], R4, UR4` |

`0x390 = 0x380 + 16`. In every case the surface operand is **one uniform register containing the object's low 32 bits**, with no descriptor-pointer load. nvdisasm independently marks **only UR8 / UR4** as the surface instruction's uniform read. Upper object bits are not used by these stores. The host must nevertheless retain/pass the complete opaque API value, not manually truncate it.

The documented and formatted witnesses differ in store semantics, not handle preparation. Their store words are:

```
documented: 60ff040402007f9d 0011e4000810ad00
formatted:  60ff040402007f9b 0011e4000810af00
original 1: 60ff080c34007f9b 0023e2000810af00
original 2: 60ff040834007f9b 0023e2000810af00
```

Verification compares all instruction-payload bits after explicitly masking only the named register fields; original scheduling/control bits are retained and reported, not silently equated. Original/formatted high-word payload is identically `0810af00`. Register-index masks and predicates are explicit in `verify_cpu.py`.

**Closed, narrowly:** an actual nvcc13.3 CUDA surface-object input uses the same direct low-word uniform convention as the exact original formatted SUST; passing that same compiler input to original PTX spelling produces the corresponding original machine instruction. This removes the old “the wrapper is only an opaque intrinsic; no device witness exists” gap. It is compiler-backed compatibility evidence for these two surface operands, not a formal published cross-version SASS ABI guarantee and not launch authorization.

## 3. Texture: same TEX encoding, materially different two-register dataflow

Default documented `tex2D<float4>` RGB lowering:

```
0020 LDCU UR4, c[0][0x3b8]       // p+56 LOW32
0030 UMOV UR5, URZ               // explicit ZERO, not p+60
0050 TEX R6, R4, R4, UR4, 2D, 0x7
```

**TEX implicitly reads both UR4 and UR5.** This is verified by NVIDIA nvdisasm's UGPR liveness (`v v` at the TEX), not inferred from the printed single register name. The RGBA control changes only the component mask (`0x7` -> `0xf`). The null-guard and `-O0` controls also construct the zero upper word; null checking alone does not explain the difference.

Exact original source A:

```
9e10 @!UP0 LDCU.64 UR8, c[0][0x3b8]
9e40 @!P1  TEX R12, R14, R14, UR8, 2D, 0x7   // uses UR8 AND UR9
c350 @UP0  LDCU.64 UR6, c[0][0x3b8]
c380 @P1   TEX R3, R8, R8, UR6, 2D, 0x7      // uses UR6 AND UR7
```

No intervening redefinition of either pair member exists on these short def-use chains. `0x3b8 = 0x380 + 56`; original therefore forwards **both** words of the opaque input. Other original texture inputs at +88/+96 likewise use full-pair loads; the blocked proposal disables those, but source A still matters.

The diagnostic **own** raw-mode ptxas build changes preparation to:

```
0020 LDCU.64 UR4, c[0][0x3b8]
0040 TEX R6, R4, R4, UR4, 2D, 0x7
```

Its TEX's full 128 bits are identical to our default witness's TEX; the different defining instructions matter. Original TEX payloads also match after explicit register/predicate masks, including high-word payload `081e0700` excluding the final destination register. **Name/opcode-only comparison would have missed the actual ABI question.**

Raw provenance is not speculation from code names:

* Original fatbin SHA-256 `c11e2eb6f6eeabadffe340dba74ec8c3f474f4ac4a8ed601d59e04d1d49bda3d` literally contains the complete pinned original ELF at byte **1,155,392**.
* The bytes **`--set-texmode-raw=true`** occur at fatbin byte **88**; fresh cuobjdump reports `ptxasOptions = --set-texmode-raw=true -split-compile=0`.
* Pinned original kernel PTX is an exact **265,352-byte** substring at byte **1,283,746** of that bundle's decompressed PTX, not a same-named unrelated kernel.
* Bundle PTX compile options are associated-container evidence, not a claim to know the historical ELF compiler command; the raw diagnostic independently reproduces its full-pair input pattern.

**Remaining blocking question:** no consulted official API contract guarantees that the high 32 bits of every genuine `cuTexObjectCreate` return are zero, or interchangeable with the default compiler-supplied zero in the raw TEX pair. The API deliberately calls the object opaque. A default documented witness does not justify forwarding arbitrary high bits; a raw witness does not make that forwarding a documented object convention. If a genuine handle happened to have high32 zero, the two observed pair values would coincide, but that is a conditional bit observation, **not a measured result or sufficient API guarantee**. Do not mask, rebuild, or try handles to work around this.

## 4. Official API-level chain (more than matching typedef widths)

Fetched official documents, complete responses, URLs, response headers, timestamps and SHA-256 are under `evidence/docs/`; `DOCS.md` lists precise anchors and extracted-text references. Live API/PTX documentation currently identifies itself as CUDA **13.4**; the conventional C++ programming guide is pinned to the official **13.0.0 archive**. No claim that those are nvcc13.3's exact build-time manuals.

The documented chain is:

1. Driver `cuSurfObjectCreate(CUsurfObject*, CUDA_RESOURCE_DESC*)` creates/returns a **surface object** for an array resource; `cuTexObjectCreate(CUtexObject*,...)` creates/returns a **texture object** and sampling description. Neither returns an ordinary pointer to host-readable descriptor bytes.
2. Driver/runtime manuals describe the APIs as largely interchangeable; the C++ guide explicitly permits mixed Driver/runtime code in the same current context. Surface/texture creation pages reciprocally cross-reference their Driver/runtime counterparts and describe the same opaque object/resource model.
3. C++ guide §§10.9.1.4 and 10.8.1.5 document **`surf2Dwrite(...,cudaSurfaceObject_t,...)`** and **`tex2D<T>(cudaTextureObject_t,float,float)`**. §§6.2.14.1–2 describe objects passed into device functions, and §13.3.1.6.2 describes host-created objects being used/passed on the device.
4. NVIDIA's pinned `cuda-samples/simpleTextureDrv` supplies an especially explicit bridge: `cuTexObjectCreate(&TexObject,...)` (host lines 169–183), `&TexObject` passed through `cuLaunchKernel` (194–197), then kernel `CUtexObject tex` (line 36) directly supplied to documented `tex2D<float>(tex,...)` (line 51). No handle conversion or descriptor arithmetic. Its immutable revision and whole-file hashes are saved. This is authoritative NVIDIA example code in addition to the API documentation, not third-party ABI lore.
5. Our local headers and compiled witnesses provide the concrete SM120 lowering from those supported CUDA C++ object inputs. Typedef identity/width is corroboration only; **the common documented API object model plus compiler lowering** is the surface operand evidence.

The cross-references/general interoperability statement are an API-level connection, **not a direct published promise about the opaque object's high bits or raw SASS operands**. Thus this chain does not cure the texture raw-mode discrepancy. In particular, do not substitute an archived NVX/Vulkan numeric handle for an API-created object.

## 5. Formatted HALF support and coordinates

* Driver array creation documentation lists `CU_AD_FORMAT_HALF` and allows `NumChannels = 4`. The C++ guide §6.2.14.3 explicitly includes 16-bit-float CUDA-array components and says arrays are accessed through texture fetching or surface reading/writing. Use a 2D array (`Depth=0`) with `CUDA_ARRAY3D_SURFACE_LDST` for the surface resource, and zero resource-descriptor flags. These are documented resource categories; allocation/device limits remain untested.
* PTX §9.7.13.2 says **`sust.p` is formatted**: four `.b32` elements mean R,G,B,A, FLOAT formats interpret them as FP32 and convert to the destination sample format. With a four-channel HALF array this describes FP32-to-RGBA16F conversion, **not** a 16-byte raw write. No CPU conversion implementation or assumed rounding proof is substituted here.
* Original `.p` X is a **sample/pixel index**. Do **not** multiply original X by 8 or 16. Y is a row index.
* Documented `surf2Dwrite` compiles to unformatted **`sust.b` / `SUST.D.BA`**. Its X is a **byte offset**; row-pitch scaling of Y is internal. Raw `ushort4` at pixel x requires X=8*x; raw `float4` would use X=16*x for an appropriate raw layout. The float4 witness is not proposed as a HALF formatted-store replacement.
* `.zero` drops out-of-bounds surface stores. The documented boundary mode chosen in the witness matches that policy, not the formatted conversion semantics.
* `tex2D<float4>` is the documented floating fetch; HALF components promote to FP32 before filtering. Driver point/normalized/clamp configuration is documented, but a descriptor with those settings does not prove the original raw TEX handle binding. Actual conversion rounding, NaNs, ties, subnormals and end-to-end numerical behavior remain unverified.

## 6. Hidden constants and residual load/runtime boundary

Original loads a 64-bit **global-memory descriptor** at `06a0: LDCU.64 UR4,c[0][0x358]`; subsequent `LD.E`/`LDG.E` instructions use `desc[UR4]` alongside separate device pointers. Our documented texture-output witness loads the **same c0[0x358]** and uses `STG.E.128 desc[UR4][R2.64]`. The load encodings agree modulo scheduling. This is an ordinary compiler-generated hidden descriptor convention, **not a descriptor dereference through the surface handle**.

The only original constant-bank-zero accesses below p-base are **0x358** and **0x37c** (the `LDC R1` prologue value, also in our witnesses). Original and witness `.nv.constant0.<entry>` are both **0x438 bytes, all zero on disk**, including these locations. They are not evidence of valid descriptor values at launch. Loader/runtime initialization, correct resource context, full original memory-descriptor contract and all actual memory accesses remain unmeasured.

Before any original-kernel test the main reviewer still needs: a supported answer for the raw texture high-word boundary; supported Driver acceptance of untouched API0x86/Mercury1.1 ELF; complete parameter/memory/resource review and normal error handling. Runtime resource creation, hidden-constant population, launch/synchronization, bounds behavior, formatted rounding and numerical parity are all unverified. **No existing host gate was edited or ungated.**
