# Swin native ordering and Vulkan dependency audit

## Result

**The original SM120 consumer code does not establish a stronger acquire protocol than the recovered PTX.** It polls with **`LDG.E.NA.STRONG.GPU`**, then reaches warp/CTA synchronization. There is no decoded post-poll `MEMBAR`, `CCTL*`, or acquire-labelled instruction. **`STRONG.GPU` must not be renamed “acquire”.** The original producer **does** contain `MEMBAR.ALL.GPU; ERRBAR; CGAERRBAR; STG.E.NA.STRONG.GPU ..., RZ`, corresponding to its PTX **GPU-release zero store**, not evidence that the consumer acquired it.

**Found an explicit Vulkan barrier, and its important bypass:** the wrapper normally records an **ALL_COMMANDS → ALL_COMMANDS, SHADER_WRITE → SHADER_READ|SHADER_WRITE** memory barrier **before** a launch. But on this Vulkan backend it **skips that barrier when the launcher's incoming-completion flag is true**—the standard wait/chained path. Thus “a barrier exists in the backend” does not close producer → polling-consumer visibility. A reset → producer dependency is a plausible **conditional** use of the non-skipped barrier; it is not attested execution or an NVX visibility guarantee.

No runtime bug, native whole-kernel equivalence, successful reset, stale-zero exclusion, safe readback, or actual consumer selection is concluded. Public `VK_NVX_binary_import` specification language is currently only stubs; this is an additional explicit API-semantics boundary, not a reason to invent CUDA-stream semantics for NVX commands.

## Scope and pinned sources

CPU/static only. No GPU, Wine, CUDA runtime, PE execution, compilation of PTX, instruction patches, header downgrades, observers, memory reads from a process, or device readbacks. Only `reviews/nr-swin-sync-native-order-20260911` was intentionally written. Prior protocol files were read/imported, never modified or run as writers.

- Physical DLL: `/home/user/.local/share/Steam/steamapps/common/Wuthering Waves/Client/Binaries/Win64/nvngx_dlssnr.dll`; SHA256 **`e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e`**.
- Module00 fatbinary: exact DLL file range **[0xdf0e0, 0xdf0e0+3944768)**; SHA256 **`c11e2eb6f6eeabadffe340dba74ec8c3f474f4ac4a8ed601d59e04d1d49bda3d`**.
- Its original SM120 ELF: fatbinary-relative **0x11a140**, DLL file **0x1f9220**, 2,789,376 bytes; SHA256 **`feb368ff5279a7408b1e55554db6e468d7f114a24b18b2af8d7e6989a410c612`**. Byte-identical to **`../nr-static-layout-20260911/finalpost-sm120.cubin`** despite that file's finalpost-oriented name.
- Module06 original SM120 ELF: DLL file **0x10f7310**, 171,136 bytes; SHA256 **`e67c8db5c29348f1650c532735b0d4740f6a003b7f932ae5c505a41ced082e7a`**. Carved without changes as `module06-original-sm120.cubin`.
- Original PTX: module00 and module06 in `../nr-ptx-bundle-20260911/modules/`; unchanged `.version 9.4`, `.target sm_120`. `ptx-evidence.json` pins full module hashes and complete entry byte ranges/hashes; `*.ptx-excerpts.txt` retain numbered original prefix/loop/release-tail lines. Nested PTX braces are retained, not mistaken for entry ends.
- Starting contract: **`../nr-swin-sync-protocol-20260911/REPORT.md`**. This audit follows its relaxed-consumer/release-producer finding and keeps its unobserved consumer/reset boundary.

`nvdisasm -c -hex -fun SYMBOL_INDEX` and `cuobjdump -sass -fun EXACT_NAME` decoded **seven selected functions only**. Both tools' complete selected-function outputs are retained. **Every decoded 16-byte instruction, including control bits and padding, was compared against original DLL bytes and against the other decoder.** Tool versions/hashes, section hashes and exact commands are in `sass-evidence.json`. This verifies the disassembly's byte provenance, not that two NVIDIA utilities are independent formal ISA specifications.

All SASS PCs below are **function-relative bytes**. All host addresses are preferred-image **VAs**, base `0x180000000`. Host excerpts give file offsets and bytes. Aggregate offsets are decimal bytes.

| Entry suffix (`cc_tinlayout_fused_swin_1h_32_1_…`) | Symbol index | ELF file start | DLL file start | Code bytes |
|---|---:|---:|---:|---:|
| wait_fp8 | 71 | 0xd5780 | 0x2ce9a0 | 0xa480 |
| chained_fp8 | 70 | 0xcb100 | 0x2c4320 | 0xa680 |
| tilesync_fp8 | 72 | 0xdfc00 | 0x2d8e20 | 0xa180 |
| wait | 74 | 0xf4500 | 0x2ed720 | 0xa600 |
| chained | 73 | 0xe9d80 | 0x2e2fa0 | 0xa780 |
| tilesync | 75 | 0xfeb00 | 0x2f7d20 | 0xa200 |
| `cc_cb_clear` (module06) | 18 | 0x3000 | 0x10fa310 | 0x180 |

The standard non-FP8 entries are also present and decoded; no claim of native absence from a name filter. ds/outview/inpview/upsample SASS are outside this bounded audit.

## 1. Exact wait/chained consumer correspondence

### Address prefix and gating

Selected `.nv.info` metadata (`*.elf-info.txt`) identifies one **96-byte** aggregate and parameter constant-bank base **0x380**. Loads agree with the PTX ABI:

| Aggregate | Native constant offset | Meaning from original PTX |
|---|---|---|
| +24/+28 | c[0][0x398]/[0x39c] | H/W |
| +32/+36 | c[0][0x3a0]/[0x3a4] | current X/Y origins |
| +40 | c[0][0x3a8], 64-bit | incoming flag base |
| +48/+52 | c[0][0x3b0]/[0x3b4] | predecessor PX/PY origins |
| +56 | c[0][0x3b8], 64-bit | outgoing flag base |

The native prefix implements the signed min/subtract, divide-by-eight lowering, origin overlap and thread-zero gating recovered in the protocol report. In its ordinary nonoverflow/nonnegative-dimension domain:

```text
C = ceil((W - min(PX,0))/8); R = ceil((H - min(PY,0))/8)
dx = X + 8*ctaid.x - PX; dy = Y + 8*ctaid.y - PY
x0 = floor(max(dx,0)/8); y0 = floor(max(dy,0)/8)
x1 = min(C, (dx+8 > 0 ? ceil((dx+8)/8) : 0))
y1 = min(R, (dy+8 > 0 ? ceil((dy+8)/8) : 0))
word = incoming + 4*s32_wrap(iy*C + ix)
```

For FP8 wait, after prefix: **R0=iy/y0, UR8=y1, UR4=C, R4=x0, R6=x1**. Chained instead uses **UR9=y1, UR5=C**, with the same R0/R4/R6 loop roles. `S2R` of all three thread IDs and `LOP3.LUT ... 0xfe` form the nonzero-thread gate; wait **0x300** / chained **0x3b0** branch to the join for nonzero threads or an empty row interval. The column-empty check is at wait **0x340** / chained **0x3f0**. No incoming-null test is introduced in these native loop fragments.

The CPU loop reference starts **after** the geometry prefix with explicit loop-register inputs; it does not claim to emulate the complete native prefix or arbitrary overflow geometry. The prior PTX interpreter remains the source for complete prefix arithmetic checks.

### Actual instructions: FP8 wait

Full raw-byte/file-offset anchors are in **`sass-excerpts.txt`**; compact excerpt:

```sass
0380 LDC.64 R2, c[0x0][0x3a8];
0390 IADD R7, R8, R5;                 // R8=iy*C, R5=ix
03a0 IMAD.WIDE R2, R7, 0x4, R2;
03b0 LDG.E.NA.STRONG.GPU R7, desc[UR16][R2.64];
03c0 IADD R5, R5, 0x1;              // next-column bookkeeping, not poll address
03d0 ISETP.NE.U32.AND P1, PT, R5, R6, PT;
03e0 ISETP.GT.AND P0, PT, R7, -0x1, PT;
03f0 @P0 BRA 0x440;
0400 NANOSLEEP 0x40;
0410 LDG.E.NA.STRONG.GPU R7, desc[UR16][R2.64];
0420 ISETP.GT.AND P0, PT, R7, -0x1, PT;
0430 @!P0 BRA 0x400;
0440 @P1 BRA 0x380;
0450 IADD R0, R0, 0x1;
0460 ISETP.NE.U32.AND P0, PT, R0, UR8, PT;
0470 @P0 BRA 0x340;
0480 WARPSYNC.ALL;
... constant loads and integer/address calculations ...
07d0 BAR.SYNC.DEFER_BLOCKING 0x0;
```

**Any signed nonnegative value passes.** The early increment of R5 does not advance R2 during retries. Negative values repeat sleep → load → signed test at the **same address**. Accepted words advance columns, then rows. Stale zero is indistinguishable from a new zero here. `NANOSLEEP 0x40` is the original PTX `nanosleep.u32 64` correspondence, not a promise of measured delay or forward progress.

Chained FP8 has the same control flow with first/retry loads at **0x460/0x4d0**, a **`YIELD` at 0x480**, sleep at **0x4c0**, retry branch **0x4f0 → 0x4c0**, next-column **0x500 → 0x430**, next-row **0x530 → 0x3f0**, **`WARPSYNC.ALL` 0x540**, and CTA **`BAR.SYNC.DEFER_BLOCKING 0x0` 0x610**. Its descriptor operand is UR18 instead of UR16. `YIELD` is not interpreted as a memory-acquire operation.

### Data loads, cache and CTA barrier

Both consumer prefixes contain only flag `LDG`s before the CTA barrier. Native scheduling moves constant loads and integer work between the warp join and CTA barrier, not ordinary global data loads.

- Wait: first ordinary `LDG` **0x890** is `.128.STRONG.SM`; first predicated input `.128.STRONG.GPU` at **0x9f0**.
- Chained: corresponding first ordinary `.128.STRONG.SM` at **0x8d0**, first predicated input `.128.STRONG.GPU` at **0xb10**.
- PTX input accesses are **`ld.weak.global.cg.v4.u32`**, e.g. wait line131 / chained line144. `.STRONG.GPU` also appears in this ordinary-data lowering; its spelling is not a source-level acquire guarantee.
- PTX `.cg` specifies caching in L2 and below, not L1. `.L1::no_allocate` is a cache-allocation hint. The observed native `.NA` is recorded as a correspondence, **not** reverse-engineered into an undocumented flush/invalidation/coherence rule.
- `BAR.SYNC.DEFER_BLOCKING 0` corresponds to the source CTA `bar.sync 0`. It is not a common barrier between producer and consumer kernels. No extra GPU-acquire guarantee is assigned to the undocumented `DEFER_BLOCKING` qualifier, the `desc[...]` descriptor, uniform registers, or scheduling/control bits.

The two `wait` bodies have **no MEMBAR anywhere**. The two `chained` bodies have their only MEMBAR at the **outgoing publication tail**, after arithmetic and stores—not after incoming polling. Across all seven selected entries, no decoded `CCTL*`, acquire-labelled instruction, atomic RMW, or fence opcode was found. These are **bounded disassembly observations**, not a proof that absent names imply absent hardware effects.

## 2. Producer release and module06 reset

### FP8 tilesync outgoing publication

Thread IDs are read at **0x9c80/0x9ca0/0x9cc0**; **0x9dd0** builds P0 for nonzero thread IDs. The final possible ordinary output store and publication are:

```sass
9fd0 STG.E.NA.128 desc[UR16][R2.64+0x200], R4;
9fe0 BAR.SYNC.DEFER_BLOCKING 0x0;
9ff0 @P0 EXIT;
a000 LDCU.64 UR6, c[0x0][0x3b8];
a010 UIADD3 UR5, UPT, UPT, UR18, UR4, URZ;
a020 UIMAD.WIDE UR6, UR5, 0x4, UR6;
a030 MOV.64 R2, UR6;
a040 MEMBAR.ALL.GPU;
a050 ERRBAR;
a060 CGAERRBAR;
a070 STG.E.NA.STRONG.GPU desc[UR16][R2.64], RZ;
a080 EXIT;
```

This is the outgoing **+56 + 4*(rowStride*ctaid.y+ctaid.x)** flag address from the source, separate from the ordinary output pointer. All threads reach the CTA barrier; only thread zero follows the release tail. PTX lines **13563–13577** show `bar.sync 0`, thread-zero branch, address calculation and **`st.release.gpu.global.L1::no_allocate.s32 ..., 0`**.

The standalone native `MEMBAR.ALL.GPU` is therefore a concrete implementation component of an **already release-ordered PTX store**. It does not establish a new consumer acquire. Public Binary Utilities documentation names `MEMBAR` “Memory Barrier”, `ERRBAR` “Error Barrier” and `CGAERRBAR` “CGA Error Barrier”; it does not provide the complete SM120 bitfield/ordering semantics needed to promote the latter two into a cross-kernel acquire mechanism.

Chained FP8 has the same publication sequence at **0xa4c0** (CTA barrier), **0xa4d0** (nonzero-thread exit), **0xa530/0xa540/0xa550** (MEMBAR/error barriers), **0xa560** (zero store). Its thread-zero predicate is independently recomputed at **0xa0d0/0xa100/0xa130/0xa2b0**. This tail cannot retroactively order the consumer's earlier ordinary input reads as an acquire.

Non-FP8 cross-check:

| Entry | Poll loads | Incoming CTA barrier | Outgoing CTA barrier | MEMBAR | Release zero STG |
|---|---|---|---|---|---|
| wait | 0x3c0, 0x420 | 0x640 | — | — | — |
| chained | 0x460, 0x4d0 | 0x6f0 | 0xa620 | 0xa690 | 0xa6c0 |
| tilesync | — | — | 0xa060 | 0xa0c0 | 0xa0f0 |

Same poll/sign/sleep shape and outgoing `MEMBAR; ERRBAR; CGAERRBAR; STG...RZ`; no alternative acquire pattern was found in these standard variants.

### Original `cc_cb_clear`

Module06 SASS, complete meaningful body retained in `cc_cb_clear.*`:

```sass
0050 IMAD R5, R5, UR4, R0;           // ntid.x*ctaid.x+tid.x
0060 ISETP.GE.AND P0, PT, R5, UR5, PT; // signed index >= count
0070 @P0 EXIT;
0080 LDC.64 R2, c[0x0][0x380];      // base
0090 LDCU.64 UR4, c[0x0][0x358];    // descriptor, not aggregate
00a0 MOV R7, 0xffffffff;
00b0 IMAD.WIDE R2, R5, 0x4, R2;
00c0 STG.E desc[UR4][R2.64], R7;
00d0 EXIT;
```

Matches original `st.global.b32 ..., -1` and signed guard; **not a zero fill, not a release store, no MEMBAR/CCTL/CTA barrier**. No generation check is added by native code. Static existence and creation of this kernel remain distinct from actual launch/completion.

## 3. Bounded Vulkan launch/command dependency chain

Only **1,622 bytes of host code in 13 relevant slices** were retained, plus exact vtable/literal bytes. `host-evidence.json`, named `*.txt`, and independent `objdump-barrier.txt` pin them. The earlier ABI audit supplies the surrounding module/function dispatch chain; no unrelated graph or queue-manager search was expanded here.

### Wrapper prelaunch branch

Common wrapper vtable **0x1800b28e0**, +0x28 → **0x1800449a0**. Its eighth argument is a byte flag, wrapper stack **[RSP+0x148]** after its 0x108 stack delta.

```text
if flag != 0:
    lower_backend.vtable+0x50(&kind)
    if u32(kind-1) <= 1:
        skip prelaunch barrier
otherwise:
    lower_backend.vtable+0x150(wrapper.commandBuffer, NULL, 0)
select function (lower vtable+0xd8)
record launch (lower vtable+0x140)
return (no wrapper postlaunch barrier)
```

Exact anchors: flag test **0x1800449d1**, kind call **49e0..49e4**, unsigned kind branch **49ee..49f3**, zero R8/R9 and barrier dispatch **49fc..4a0d**, join **4a13**, function selection **4a1d..4a24**, launch **4a7b..4a82**.

Vulkan vtable **0x1800b40c8**:

- +0x50 → **0x18004fdd0**, writes **kind=2** and returns zero.
- +0x150 → **0x180050ad0**, the barrier builder below.
- +0x140 → **0x18004f2f0**, NVX kernel launch, dispatches `[backend+0x518]` at **0x18004f427**. That implementation has no pipeline barrier around the command.

Therefore **flag=true skips the barrier on this exact Vulkan backend**. No assumption about runtime backend-kind memory is needed for this static target—the method writes literal 2.

### Exact global barrier arguments

In the reached NULL-resource/zero-mode branch of **0x180050ad0**, entry SP is S and post-prologue SP is S−0xb8. The memory barrier is at **S−0x58**:

```c
VkMemoryBarrier mb = {
    .sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER, // 0x2e
    .pNext = NULL,
    .srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT, // 0x40
    .dstAccessMask = VK_ACCESS_SHADER_READ_BIT |
                     VK_ACCESS_SHADER_WRITE_BIT // 0x60
};
vkCmdPipelineBarrier(commandBuffer,
    VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, // 0x10000
    VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, // 0x10000
    0, 1, &mb, 0, NULL, 0, NULL);
```

The loader ties literal **`vkCmdPipelineBarrier` 0x1800b47c0** to backend **+0x4d0** at **0x180051693..16a6**. The builder loads that slot at **0x180050b36** and calls at **0x180050b45**. Cell **0x1800ac428 → 0x1800a7c30**, bytes `ff e0` (`jmp rax`), confirms the indirect target mechanism. The field and stack arguments were **replayed from the original x86 instructions on owned synthetic memory**, stopping before the API call; installed Vulkan header constants/layout also pass a compile-only check.

This is a **global memory barrier**, not an execution-only barrier and not a per-buffer barrier. Its source access mask is shader-write, **not ALL/MEMORY_WRITE**; ALL_COMMANDS stage masks do not broaden access masks to every access class.

### Who sets the skip flag?

The same standard 1h launcher from the protocol report supplies it:

- **0x180063aff** clears DIL.
- Standard branch **0x180063b08..3b11** sets **DIL=(incoming_pointer != 0)**.
- The incoming/outgoing mask chooses base/tilesync/wait/chained handles, but missing specialized handles can fall back without clearing DIL.
- **0x180063bbc** stores DIL to outgoing arg8 **[RSP+0x38]**; dispatch at **0x180063c31**.
- Special incoming path sets DIL=1 at **0x180063b86**; no broader special-family SASS conclusion is drawn.
- Reset forward branch requires start_block==0. R13=start_block at **0x18003ccb8**; after that zero gate **0x18003cd54** passes **R13B=0** as reset launch arg8.

Consequently, on the proven standard branch and valid Vulkan dispatch:

| Launch condition | Flag | Wrapper prebarrier |
|---|---:|---|
| `cc_cb_clear` reset branch | 0 | recorded before clear |
| tilesync producer, incoming pointer absent | 0 | recorded before producer |
| wait/chained, incoming pointer present | 1 | **skipped** |
| base fallback with incoming pointer still present | 1 | **still skipped** |

A hypothetical command sequence along these branches is:

```text
barrier → clear(-1) → barrier → tilesync(release zero) → wait/chained(no prebarrier)
```

The barrier **before producer**, not the one before clear, is the candidate reset → producer dependency. There is **no corresponding wrapper barrier between that producer and the incoming-pointer consumer**. Later barriers cannot be moved backward across that consumer in the proof.

### Command recording versus execution

Wrapper constructor initializes +0x10 to zero. Wrapper vtable+8 setter **0x180044b70** simply copies the supplied command-buffer value into **wrapper+0x10**. Both prebarrier and launch load that same field (**0x180044a02**, **0x180044a72**); the lower launch forwards it to the NVX command. Neither path submits a queue or waits for command completion. This establishes **same-wrapper command-buffer argument flow**, conditional on no intervening mutation; it does not attest shared command-buffer identity across different wrappers or recorded/submitted/completed runtime operations.

Vulkan's public synchronization chapter explicitly says **submission order itself defines no execution or memory dependencies**. Do not replace the missing local dependency with CPU call order, same queue order, or generic CUDA-stream guarantees. The official **`VK_NVX_binary_import` appendix expressly has no specification language for `vkCmdCuLaunchKernelNVX`**, only stubs. Thus even the non-skipped shader-access barrier is an identified dependency **candidate**, conditional on valid recording/submission and the driver's NVX stage/access contract; the fetched public sources alone do not establish that contract for this binary. No assumption from the different `VK_NV_cuda_kernel_launch` extension is imported.

## 4. What is and is not proved

**Proved statically:** exact original fatbinary/ELF provenance; original encoded loops; sign predicate and same-address retry; two CTA synchronization points in chained; outgoing release lowering with MEMBAR; negative clear store; explicit prelaunch global barrier construction; exact standard incoming-pointer skip condition and Vulkan kind=2; bounded command-buffer field flow.

**Not proved:** hidden SM120 acquire encoding or full semantics of `.STRONG`, `.NA`, `.DEFER_BLOCKING`, descriptors/control bits; driver-selected ELF versus PTX/JIT/relocated GPU code; actual wait/chained/reset selection and parameters; actual barrier execution; NVX shader-access classification; reset completion before producer; publication/ordinary-data visibility; workspace generation, ownership/lifetime or concurrent reuse; forward progress; readback synchronization.

Therefore the answer is **not “native acquires because STRONG”**, **not “bug because no CCTL/acquire name”**, and **not “safe because MEMBAR/barrier exists”**. Producer-side ordering is concrete; a stronger native consumer acquire and an actually executed end-to-end visibility dependency remain unestablished. The protocol report's proof boundary remains necessary, now narrowed by a positive backend barrier finding **and its consumer bypass**.

## Verification and deliverables

**8 CPU/static tests passed** (`tests.txt`): all seven complete instruction streams vs original DLL and both decoders; full PTX entry hashes/ranges; exact ordering-site inventory; negative/unknown/nonnegative/stale-zero loop cases; same-address retries, bounds and nonzero-thread bypass; **400 randomized native nested-loop address cases**; pinned host ranges/vtables; original-instruction barrier-argument replay; caller skip-flag and setter checks.

The loop reference executes only a whitelist of decoded nested-loop instructions with explicit post-prefix inputs and explicit observed `(address,value)` pairs. It returns `needs_observation`, `instruction_budget`, or `warpsync_intent`. It never returns acquired visibility, CTA completion, native kernel success or output pixels. Tests do not establish concurrency/numerical parity.

Reproduction, from repository working directory (`D=reviews/nr-swin-sync-native-order-20260911`):

```sh
python -B "$D/collect_sass.py"
python -B "$D/collect_host.py"
python -B "$D/collect_excerpts.py"
python -B "$D/test_static.py"
cc -std=c11 -Wall -Wextra -Werror -fsyntax-only "$D/barrier_layout_check.c"
# Optional network-only documentation refresh:
python -B "$D/collect_docs.py"
```

`verification.txt` records final checks. `SHA256SUMS` pins local deliverables. `docs-evidence.json` pins public URLs/retrieval times/full-response hashes; `*-docs.txt` retain bounded contexts (NVX appendix retained whole). Binary Utilities search found no `STRONG.GPU`/`DEFER_BLOCKING` documentation in that public page; this is a scoped documentation result, not a claim no documentation exists anywhere. No local Git repository was available for a diff; write scope was enforced by explicit output paths. The original DLL hash is checked again by the final tests.
