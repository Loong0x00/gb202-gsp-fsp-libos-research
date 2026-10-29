# Exact NR Vulkan launch ABI — CPU/static proof

## Result

**Resolved. `pExtras` is neither the 184-byte aggregate itself nor an argv whose first element points to that aggregate.** In this exact DLL's Vulkan producer it points directly to a **five-qword, CUDA-style tagged buffer descriptor**:

```text
pLaunchInfo->paramCount = 0
pLaunchInfo->pParams    = NULL
pLaunchInfo->extraCount = 1                    // genuinely ONE, despite the five qwords below
pLaunchInfo->pExtras    = E
E[0] = (void *)1                              // BUFFER_POINTER tag, NOT a readable address
E[1] = A                                     // raw packed aggregate address
E[2] = (void *)2                              // BUFFER_SIZE tag
E[3] = &N                                    // pointer to an eight-byte size_t
E[4] = NULL                                  // END tag
N = 184                                      // base-finalpost case
```

Thus the buffer is **`pExtras[1]`**, and its byte count is **`*(size_t *)pExtras[3]`**. **Do not dereference `pExtras[0]` (it is address/tag 1), do not copy 184 bytes from `pExtras`, and do not dereference the first qword of `A` as another argument pointer.** The original caller's `argv[0]` indirection has already been removed by the wrapper.

**Also resolved the module-hash mismatch without a GPU run:** the parent's newly available CPU capture, `runs/20260911-122501-observer_on/observed-finalpost-module.cubin`, hashes to the observed **c11e2e…** and is **byte-for-byte a complete embedded CUDA fatbinary**, not an ELF. Its contained SM120 ELF is **exactly the previously carved feb368… ELF**. Both that ELF and the fatbinary's compressed SM120 PTX declare a 184-byte base-finalpost parameter ABI. No host transformation is needed to explain size/hash differences.

## Scope and source identity

- Exact physical DLL opened **read-only**: `/home/user/.local/share/Steam/steamapps/common/Wuthering Waves/Client/Binaries/Win64/nvngx_dlssnr.dll`.
- Size 165,840,496; SHA256 **`e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e`**.
- All addresses below are preferred-image VAs, base **`0x180000000`**. `ADDRESS_PROOF.json` gives file offsets, table bytes, and hashes of bounded disassembly ranges; text excerpts give every instruction's file offset and machine bytes.
- Read the requested `20260911-121737-observer_on/finalpost-trace-v1.log`: observed c11 module size 3944768, exact base FP8 finalpost name, two submissions with `paramCount=0`, `extraCount=1`, and correct parameter-read refusal. No new pixel-equivalence claim is needed for this static task.
- Current supplied live path is **NR_VULKAN through owned D3D12 interop**, not NVAPI_D3D12. No filename/IAT compatibility changes, observer changes, patches, Wine, game/PE execution, GPU calls, or unknown-process-memory reads were performed. All writes are in this review directory.

## 1. Literal Vulkan name → dispatch slot

The only bounded `.text` RIP reference to literal **`vkCmdCuLaunchKernelNVX` at `0x1800b4890`** is:

```text
18005191b  LEA RSI,[literal vkCmdCuLaunchKernelNVX]
180051922  MOV RAX,[RDI]
180051925  MOV RDX,RSI
180051928  CALL [1800ac428]
18005192e  MOV [RBX+518],RAX
```

The loader prologue at `0x180050d3c` establishes `RDI = backend+0x3a8`; `0x180050d94..daa` resolves **`vkGetDeviceProcAddr`**, literal at `0x1800b4448`, and saves its result at that slot. `0x180051914` supplies the backend's device at `+0x390` as RCX for the command-name lookup. Independent literal/table evidence ties the returned command pointer specifically to **backend+0x518**. Module/function names resolve analogously to **+0x4f8/+0x500** (`0x18005180e/1856`).

The indirect-call cell **`0x1800ac428`** contains `0x1800a7c30`; its bytes **`ff e0` = JMP RAX**. These calls execute the RAX-loaded target, not a separate unrelated routine. The actual launch loads `[RDI+0x518]` at **`0x18004f409`**, and calls it at **`0x18004f427`**, with RCX=command buffer and RDX=launch-info address.

## 2. Caller Backend+0x28 → Vulkan implementation

There are **two distinct vtables**. Confusing them would incorrectly identify Vulkan-vtable+0x28, which is not the launch method.

1. Finalpost `0x1800758a0` builds aggregate **A=RBP-0x80** and writes A to local `argv[0]` at `0x180075bac`. Base selector zero retains state `+0x10` as the kernel handle and sets byte count **0xb8** (`0x180075bb8`, `0x180075bf2..c07`). At `0x180075c0c..c11`, the address of `argv[0]` is passed as arg6; arg7 is byte count. `0x180075c21..c25` dispatches receiver-vtable **+0x28**.
2. The receiver is a common wrapper, constructor **`0x1800447b0`**, vtable **`0x1800b28e0`**. Constructor saves the lower backend to wrapper **+8**. Table **`0x1800b2908 = vtable+0x28` contains `0x1800449a0`**.
3. Wrapper launch **`0x1800449a0`** receives `(this, kernelHandle, gridX, gridY, gridZ, argv, byteCount, flag)`. Its stack delta is **0x108**, so `[RSP+0x138]` is incoming arg6 and `[RSP+0x140]` arg7. Crucial unwrapping:
   - **`0x180044a32`** loads argv; **`0x180044a3a`** loads **`argv[0] = A`**.
   - **`0x180044a49`** saves A at local descriptor **D+8**, D=RSP+0x48.
   - **`0x180044a4e..55`** copies the **low 32 bits** of byteCount to **D+0x10**. 184 is exact; no size_t-wide wrapper preservation is claimed for arbitrary huge inputs.
   - D's vtable **`0x1800b28b8`** is installed at `0x180044a3d..44`. Getter +0x10=`0x180044790` returns `[D+8]`; getter +0x18=`0x1800447a0` returns DWORD `[D+0x10]` in EAX. Getter +8 returns type=1.
4. Wrapper first selects the kernel through lower-backend vtable **+0xd8** (`0x180044a1d..24`). Vulkan target **`0x18004d1b0`** resolves the handle and stores the selected record at backend **+0x140** (`0x18004d1ec`).
5. Wrapper calls lower-backend vtable **+0x140**, not +0x28, at **`0x180044a7b..82`**, passing D as RDX, wrapper+0x10 command buffer as R8, and grid dimensions.
6. Vulkan constructor `0x18004c42d..434` installs vtable **`0x1800b40c8`**. Its **+0x140 slot at `0x1800b4208` is `0x18004f2f0`**: the proven NVX launch implementation.

## 3. Exact VkCuLaunchInfoNVX stores and descriptor layout

In **`0x18004f2f0`**, set **L=RBP-0x69** (RDX at `0x18004f3fa`), **E=RBP-9**, and **Naddr=RBP-0x79**.

| Launch field | Offset from L | Stack address | Proven write |
|---|---:|---|---|
| sType | 0 | RBP-0x69 | `0x18004f3c0`: 1000029002 / 0x3b9b3b4a |
| pNext | 8 | RBP-0x61 | zero by `0x18004f3cb` |
| function | 16 | RBP-0x59 | selected-record+0x38 → `0x18004f3d7` |
| grid X/Y/Z | 24/28/32 | RBP-0x51/-0x4d/-0x49 | `0x18004f3e7/3de/3e4` |
| block X/Y/Z | 36/40/44 | RBP-0x45/-0x41/-0x3d | `0x18004f3ee/3f4/3fe` |
| sharedMemBytes | 48 | RBP-0x39 | selected-record+0x50 → `0x18004f41b` |
| **paramCount** | **56** | **RBP-0x31** | **`0x18004f410`: qword zero** |
| **pParams** | **64** | **RBP-0x29** | **`0x18004f414`: qword zero** |
| **extraCount** | **72** | **RBP-0x21** | **`0x18004f41f`: qword one** |
| **pExtras** | **80** | **RBP-0x19** | **`0x18004f401..405`: E** |

`XOR ECX,ECX` at `0x18004f39e` supplies the qword zeros. Total struct size is **88 bytes**, independently compile-checked against installed Vulkan headers.

Descriptor construction:

| Address | Value | Instruction proof |
|---|---|---|
| E+0 | 1 | `0x18004f375`: `[RBP-9]=1` |
| E+8 | **A**, returned by D getter+0x10 | `0x18004f386..39a`: getter call, `[RBP-1]=RAX` |
| E+16 | 2 | `0x18004f3b4`: `[RBP+7]=2` |
| E+24 | **Naddr** | `0x18004f3a8..3ac`: LEA RBP-0x79, store `[RBP+0xf]` |
| E+32 | 0 | `0x18004f3a4`: `[RBP+0x17]=RCX=0` |
| Naddr | zero-extended DWORD byteCount | `0x18004f368..36c` getter+0x18; `0x18004f37d..37f` zero-extension then qword store |

Installed CUDA header `/opt/cuda/targets/x86_64-linux/include/cuda.h` lines 5108–5145 independently names tag **1 = CU_LAUNCH_PARAM_BUFFER_POINTER**, **2 = CU_LAUNCH_PARAM_BUFFER_SIZE**, **0 = CU_LAUNCH_PARAM_END**, with the latter size payload pointing to `size_t`. The machine writes above, not a generic interpretation of `extraCount`, establish the five-qword span. **Do not generalize this producer-specific shape to arbitrary NVX clients.**

## 4. Exact c11 module provenance — no host compilation hypothesis needed

During this CPU task the parent's next run deposited the already requested capture. Read-only equality checks establish:

| Object | Location / size / SHA256 |
|---|---|
| Observed complete module | **3,944,768 bytes**, `c11e2eb6f6eeabadffe340dba74ec8c3f474f4ac4a8ed601d59e04d1d49bda3d` |
| Exact same DLL slice | file **0xdf0e0**, RVA **0xe06e0**, VA **0x1800e06e0**, same full 3,944,768 bytes |
| Fatbinary header | `50 ed 55 ba 01 00 10 00 30 31 3c 00 00 00 00 00`; 16-byte header + 0x3c3130 payload = 0x3c3140 total |
| Contained ELF | module-relative **0x11a140**, DLL file **0x1f9220**, **2,789,376 bytes** |
| Contained ELF SHA256 | **`feb368ff5279a7408b1e55554db6e468d7f114a24b18b2af8d7e6989a410c612`**, exactly equal to prior `nr-static-layout-20260911/finalpost-sm120.cubin` |

CPU `cuobjdump --list-elf/--list-ptx` reports **one SM120 ELF and one SM120 PTX**. CPU `--dump-ptx` reports compressed PTX, `.version 9.4`, `.target sm_120`; only its header and exact finalpost declaration are retained:

```ptx
.entry cc_tinlayout_fused_post_block_swin_1h_32_fp8(
.param .align 8 .b8 cc_tinlayout_fused_post_block_swin_1h_32_fp8_param_0[184]
)
.maxnreg 168
```

Static pointer/size flow also directly agrees:

- **`0x18003d8c3`** loads qword size from **`0x181122590` = 3944768**; **`0x18003d8ca`** LEAs **`0x1800e06e0`**. Both are passed to `0x180035ef0` at `0x18003d8d6` (module group index zero).
- `0x180035ef0` constructs the common wrapper, then wrapper-vtable+0x10 → **`0x180044b60`** simply stores pointer at wrapper+0x18 and DWORD size at +0x20.
- Wrapper function lookup `0x180044830` forwards those stored values at **`0x180044899/489d`** through lower-backend+0x60, whose Vulkan table target is **`0x18004e390`**.
- Vulkan module creation sets Lm=RBP-0x29. **`0x18004e46e`** writes input pointer to **Lm+24=pData**; **`0x18004e472`** writes zero-extended input DWORD size to **Lm+16=dataSize**. **`0x18004e4a4..4ab`** dispatches backend+0x4f8=`vkCreateCuModuleNVX`.
- Optional `VkCuModuleTexturingModeCreateInfoNVX` pNext sets use64bitTexturing=1 on its gate (`0x18004e476..48b`); this is not a module-byte rewrite.

**Therefore comparing the full c11 fatbinary hash to the 15 direct ELF hashes was comparing different containers.** The exact prior ELF is inside c11, unmodified. **Driver-internal image selection (ELF versus PTX), JIT, relocation, and GPU-resident instruction bytes remain unobserved.** The host ABI and both contained base-finalpost signatures agree on 184 bytes; this does not independently attest every internal driver transformation.

## Safe follow-up boundary

This review proves a producer-specific ABI; it does **not** implement or authorize a generic pointer scanner. An exact-module/name/producer-gated observer may use a checked, bounded **40-byte** descriptor read, verify the **1/A/2/Naddr/0** shape, then a checked **8-byte** size read requiring **184**, then a checked **184-byte** read at **A=E[1]**. Validate non-null pointers, overflow, readable spans and failure paths at every step. Do not assume `extraCount=1` means the buffer is `pExtras[0]`, or means a generic five-element-array API contract. No contained device pointers should be dereferenced. Keep argument capture synchronous before the original call; these descriptor/size locals are stack-lifetime data.

## Verification

- `python -B .../inspect_abi.py`: exact source hash, bounded 699,904-byte `.text` literal references (skip-data enabled).
- `python -B .../collect_proof.py`: 14 bounded code ranges, exact table slices, file offsets and hashes.
- `python -B .../test_abi.py`: **5 CPU tests pass**, including instruction-level straight-line replay with **owned synthetic memory**, actual byte-decoded wrapper/getter/Vulkan stores, and 184/312-byte cases. Unsupported instructions/calls or unowned accesses fail closed. This is not native PE execution or full control-flow emulation.
- `cc -std=c11 -Wall -Wextra -Werror .../layout_test.c -o .../layout_test && .../layout_test`: all Vulkan offsets, 88-byte size, and sType pass without linking/loading Vulkan.
- `python -B .../module_proof.py`: full module/DLL equality, embedded ELF/prior-carve equality, ELF parameter-size metadata, and independently decompressed PTX 184-byte declaration pass.
- GNU `objdump` independently confirms the exact descriptor/launch store slice (`objdump-launch.txt`).

Here `...` is `reviews/nr-vulkan-launch-abi-20260911`. All outputs and test sources are confined there.
