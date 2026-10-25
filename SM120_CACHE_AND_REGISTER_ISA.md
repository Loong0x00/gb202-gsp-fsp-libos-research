# sm_120 SASS ISA: cache control and special-register access

Date: 2026-07-13  
Device: RTX 5090 / GB202 / sm_120  
Toolchain: CUDA 13.3.73, Driver 610.43.03, PTX ISA 9.3

This report is intentionally limited to the two families in
[`COMPILER_RE_BRIEF.md`](COMPILER_RE_BRIEF.md). Ordinary arithmetic/logic ISA is
out of scope.

## Evidence labels and bit numbering

- **verified**: emitted by legal PTX/CUDA/OptiX and matched by controlled
  compiler diffs; runtime claims additionally came from untouched
  ptxas-produced cubins.
- **inferred**: an offline `nvdisasm` decoder sweep or multiple encodings agree,
  but no legal source was found to execute the variant.
- **unknown**: no defensible semantic assignment.

`nvdisasm -hex` prints the low 64 bits first and the high 64 bits second. This
report numbers the complete instruction from bit 0 (low-word LSB) through bit
127 (high-word MSB). Thus high-word bit 8 is overall bit 72.

The shared predicate nibble is overall bits `[15:12]`: unpredicated/PT is `7`;
an OptiX-JIT `@!P0` sample uses `8`. The remaining predicate codes follow the
usual `P0..P6 = 0..6`, `!P0..!P6 = 8..e` pattern but are **inferred** here.
Scheduling/dependency-control bits outside the fields below vary with compiler
context and remain **unknown**; they are not silently called operand bits.

Reproduction and raw tables are under [`isa_re`](isa_re/README.md). The current
corpus contains 121 cache-policy PTX modules, 115 special-register attempts,
959 passing operand-field checks, a complete 256-selector decoder sweep, and 58
GPU-returned policy descriptors matching the recovered model.

## 1. `S2R` and `CS2R`

### 1.1 Encoding

| Field | Overall bits | Meaning | Evidence |
|---|---:|---|---|
| opcode | `[11:0]` | `S2R = 0x919`, `CS2R = 0x805` | **verified** |
| predicate | `[15:12]` | shared predicate nibble | PT/`!P0` **verified**, rest inferred |
| destination | `[23:16]` | 8-bit destination field | field **verified** on several legal register values; full `R0..R254` / `0xff = RZ` mapping decoder-enumerated/inferred |
| SR selector | `[79:72]` | 8-bit `SR_*` index | **verified** on legal samples; all 256 decoder-enumerated |
| CS2R width | `[80]` | `0 = CS2R.32`, `1 = 64-bit low/high pair` | **verified** |
| S2R bit 80 | `[80]` | decoder leaves mnemonic unchanged | **unknown/reserved candidate** |

Canonical examples:

```text
S2R R0, SR_LANEID
  high:low = 000fc00000000000:0000000000007919

CS2R.32 R0, SR_CLOCKLO
  high:low = 000fc00000005000:0000000000007805

CS2R R4, SR_CLOCKLO                 # %clock64, R4:R5
  high:low = 000fc00000015000:0000000000047805
```

The compiler consistently chooses `S2R` for lane/thread/CTA/SM-style state and
`CS2R` for clocks, global timer, PM counters and selected CGA configuration.
The hardware distinction implied by the `C` prefix is still **unknown**; it is
not assigned a guessed coherence meaning.

### 1.2 Complete selector space

The complete `0x00..0xff` table is delivered in:

- [`sr_index_catalog.md`](isa_re/results/sr_index_catalog.md)
- [`sr_index_catalog.tsv`](isa_re/results/sr_index_catalog.tsv)
- raw [`s2r_decoder.tsv`](isa_re/results/s2r_decoder.tsv)

The separate offline
[`s2r_destination_decoder.tsv`](isa_re/results/s2r_destination_decoder.tsv)
confirms the inferred full destination-name mapping without executing any
modified instruction.

Coverage summary:

```text
verified/direct public mappings                         19
verified compiler-lowering sources                       3
verified PM even-selector 32/64-bit encodings             8
inferred PM odd-selector high-half names                  8
verified OptiX-JIT SRZ                                   1
decoder-named but unexecuted selectors                  68
numeric SR<n>, semantics entirely unknown              149
                                                     ------
                                                        256
```

Important verified mappings:

| Index | Decoder name | Legal source | Meaning / lowering |
|---:|---|---|---|
| `00` | `SR_LANEID` | `%laneid` | lane index |
| `02` | `SR_VIRTCFG` | `%nwarpid` | packed source; ptxas extracts the PTX value |
| `03` | `SR_VIRTID` | `%warpid` | packed source; ptxas extracts the PTX value |
| `21..23` | `SR_TID.X/Y/Z` | `%tid.{x,y,z}` | thread indices |
| `25..27` | `SR_CTAID.X/Y/Z` | `%ctaid.{x,y,z}` | CTA indices |
| `32` | `SR_SMEMSZ` | `%total_smem_size` | CTA shared-memory allocation |
| `38..3c` | `SR_{EQ,LT,LE,GT,GE}MASK` | `%lanemask_*` | lane masks |
| `43` | `SR_VIRTUALSMID` | `%smid` | PTX SM identifier |
| `50/51` | `SR_CLOCKLO/HI` | `%clock`, `%clock_hi`, `%clock64` | 32-bit halves / 64-bit pair |
| `52/53` | `SR_GLOBALTIMERLO/HI` | `%globaltimer*` | timer halves / pair |
| `64..73` | `SR_PM0..7`, alternating `SR_PM_HI*` | `%pm0..7`, `%pm0_64..7_64` | legal 32/64-bit forms encode only even selectors plus CS2R width bit; odd high-half names are pair-inferred; configured event is undefined |
| `88` | `SR_CgaCtaId` | `%cluster_ctarank` | CTA rank within cluster |
| `8a` | `SR_CgaSize` | cluster-size-derived PTX values | raw CGA config feeding a ptxas table lookup |
| `ff` | `SRZ` | OptiX JIT | zero selector |

Public PTX registers such as `%ntid`, `%nctaid`, `%nsmid`, `%gridid`, many
`%envreg*`, reserved-shared-memory offsets and `%current_graph_exec` lower to
constant-bank loads or multi-instruction synthesis on this toolchain. They do
not imply an additional direct `SR_*` index.

### 1.3 Internal names: what can and cannot be said

`nvdisasm` names several otherwise undocumented state selectors:

- scheduler/execution candidates: `SR_ORDERING_TICKET`, `SR_INVOCATION_*`,
  `SR_THREAD_KILL`, `SR_AFFINITY`, `SR_HWTASKID`, circular-queue fields;
- resource candidates: `SR_REGALLOC` (`0x3d`), `SR_BARRIERALLOC` (`0x3e`),
  shared/local window fields, `SR_CTARegPoolSz`, `SR_TMemSz`;
- error/debug candidates: global/CGA/warp error status, `SR_ESR_PC{,_HI}` and
  context-save addresses;
- PM snapshot bank: `SR_SNAP_PM0..7` and high halves (`0x74..0x83`).

These are **inferred-name-only**. No patched selector was executed, so the
names do not prove value layout, privilege, update rules, or even that every
index is readable in a normal compute kernel. No decoder name exposes an
explicit cache-status or scoreboard-status register.

### 1.4 Read-only runtime observations

[`public_sr_values.tsv`](isa_re/results/public_sr_values.tsv) records untouched
legal probes. Selected observations from a one-thread launch:

```text
%nsmid = 170
lane 0 masks: eq=1, lt=0, le=1, gt=0xfffffffe, ge=0xffffffff
%clock64 and %globaltimer were live/nonzero
%pm0..7 and %pm0_64..7_64 were all zero without PM configuration
```

The `%pm*` event mapping remains officially undefined. `%envreg*` values are
driver-defined and are therefore recorded without invented semantics.

### 1.5 Writable CSR / perfmon control / barrier state

- PTX 9.3 defines `.sreg` as read-only.
- No legal PTX/CUDA trigger, ptxas output, or existing OptiX JIT cubin produced
  an `R2S`/CSR-write-style instruction.
- No perfmon-control write interface was found; only the read counters and
  decoder-named snapshot bank exist.
- `SR_BARRIERALLOC` is a decoder name only, not proof of a writable barrier CSR.

Strict conclusion: **no user-visible writable special-register/CSR access is
verified**. Hardware-private write mechanisms may exist but remain unknown.

## 2. `CCTL` and prefetch/control operations

### 2.1 Global/generic `CCTL`

| Field | Overall bits | Meaning | Evidence |
|---|---:|---|---|
| opcode | `[11:0]` | `0x98f` | **verified** |
| address register | `[31:24]` | `R0..R254`, `0xff = RZ` | **verified** (`R2`/`R4` matched pair) |
| extended address | `[72]` | `.E` when set | legal global + offline clear-bit decode |
| suboperation | `[91:87]` | five-bit code below | legal subset verified; rest inferred |

No immediate displacement appeared in a CCTL encoding: PTX offsets `-4`, 4,
16, 128 and 4096 were first folded into the address register by an integer
add, followed by the same CCTL word.

| Code | Decoder mnemonic | Legal PTX trigger | Status |
|---:|---|---|---|
| `0` | `PF1` | `prefetch{.global}.L1`, `prefetchu.L1` | **verified** |
| `1` | `PF2` | `prefetch{.global}.L2`, `L2::evict_normal` | **verified** |
| `2` | `WB` | none found | **inferred-name-only** |
| `3` | `IV` | none found | **inferred-name-only** |
| `4` | `IVALL` | post-load for acquire cluster/GPU/SYS | **verified** with `.E=0`, `RZ` |
| `5` | `RS` | none found | **inferred-name-only** |
| `6` | `IVALLP` | none found | **inferred-name-only** |
| `7` | `WBALL` | none found | **inferred-name-only** |
| `8` | `WBALLP` | none found | **inferred-name-only** |
| `9` | `PML2` | `prefetch.global.L2::evict_last` | **verified** |
| `a` | `DML2` | `applypriority.global.L2::evict_normal` | **verified** |
| `b` | `RML2` | `discard.global.L2` | **verified** |
| `c..1f` | invalid/unrecognized | none | **unknown** |

Examples:

```text
CCTL.E.PF1 [R2]   000fc00000000100:000000000200798f
CCTL.E.PF2 [R2]   000fc00000800100:000000000200798f
CCTL.E.PML2 [R2]  000fc00004800100:000000000200798f
CCTL.E.DML2 [R2]  000fc00005000100:000000000200798f
CCTL.E.RML2 [R2]  000fc00005800100:000000000200798f
CCTL.IVALL         000fc00002000000:00000000ff00798f
```

### 2.2 Local `CCTLL`

`prefetch.local.L1/L2` lowers to a distinct opcode:

```text
CCTLL.PF1 [R0]    000fc00000000000:0000000000007990
CCTLL.PF2 [R0]    000fc00000800000:0000000000007990
```

`CCTLL` has opcode `0x990`, the same address field `[31:24]`, and the same
suboperation field `[91:87]`. Legal sources verify `PF1/PF2`; offline decoding
names `WB/IV/RS` at codes `2/3/5`. Other codes were rejected by the decoder.

## 3. Scalar `LDG` / `STG` cache behavior

### 3.1 Opcodes and operands

| Instruction | opcode `[11:0]` | Register fields |
|---|---:|---|
| scalar `LDG` | `0x981` | data `Rd=[23:16]`, descriptor `UR=[31:24]`, address `Ra=[39:32]` |
| scalar `STG` | `0x986` | address `Ra=[31:24]`, data `Rs=[39:32]`, descriptor `UR=[71:64]` |

The validator checked these layouts, plus S2R/CS2R/CCTL fields, against 959
ptxas and OptiX-JIT operand instances with zero failures.
For scalar LDG the current allocator kept all three operands at register index
4, so their distinct roles are decoder-confirmed rather than established by a
controlled register-allocation diff; STG and the other families cover several
register values.

### 3.2 Common scalar modifier fields

| Field | Bits | Value → mnemonic |
|---|---:|---|
| L2 fetch-ahead size | `[69:68]` | `0` none, `1` `LTC64B`, `2` `LTC128B`, `3` `LTC256B` |
| data size/sign | `[75:72]` | `1 U8`, `3 S8`, `5 U16`, `7 S16`, `9 32b`, `b 64b`, `d 128b`; even values rejected |
| semantics/scope | `[80:77]` | table below |
| L1 cache operation | `[86:84]` | `0 EF`, `1 normal`, `2 EL`, `3 LU`, `4 EU`, `5 NA`; `6/7` invalid |

Verified PTX-to-L1 mapping:

| PTX | SASS | cache field |
|---|---|---:|
| default / `L1::evict_normal` | no suffix | `1` |
| `.cs` / `L1::evict_first` | `.EF` | `0` |
| `L1::evict_last` | `.EL` | `2` |
| `.lu` | `.LU` | `3` |
| `L1::evict_unchanged` | `.EU` | `4` |
| `L1::no_allocate` | `.NA` | `5` |

The semantics/scope field was exhaustively named offline; only values exercised
by legal PTX are promoted to verified:

| Value | LDG decoder | STG decoder | Legal source status |
|---:|---|---|---|
| `0` | default | default | **verified** weak/default |
| `1` | `CONSTANT.PRIVATE` | same | inferred |
| `2` | `CONSTANT.CTA` | same | inferred |
| `3` | `CONSTANT.CTA.PRIVATE` | same | inferred |
| `4` | `CONSTANT` | `STRONG.SM.PRIVATE` | LD `.nc` **verified**; ST inferred |
| `5` | `STRONG.SM` | `STRONG.SM` | **verified** CTA / `.ca` / `.wb` |
| `6` | `STRONG.GPU.PRIVATE` | same | inferred |
| `7` | `STRONG.GPU` | same | **verified** cluster or GPU / `.cg` |
| `8` | `MMIO.GPU` | same | decoder only; never executed |
| `9` | `CONSTANT.SM` | same | inferred |
| `a` | `STRONG.SYS` | same | **verified** SYS / volatile / `.cv` / `.wt` |
| `b` | `CONSTANT.SM.PRIVATE` | same | inferred |
| `c` | `MMIO.SYS` | same | decoder only; never executed |
| `d` | `CONSTANT.VC` | `SYS.ORDERED` | inferred |
| `e` | `CONSTANT.VC.PRIVATE` | `STRONG.SYS.ORDERED` | inferred |
| `f` | `CONSTANT.GPU` | `MMIO.SYS.ORDERED` | inferred; never executed |

Important canonicalizations:

- PTX `.cluster` and `.gpu` both encode `STRONG.GPU` on this target.
- `ld.acquire.{cluster,gpu,sys}` uses the same LDG encoding as relaxed, then
  appends `CCTL.IVALL`; CTA acquire has no IVALL.
- `st.release.{cta,gpu,sys}` prepends `MEMBAR.ALL.{CTA,GPU,SYS}` and then uses
  the same scoped STG as relaxed. Cluster release maps to `MEMBAR.ALL.GPU`.
- `.volatile`, `.cv` loads and `.wt` stores canonicalize to `STRONG.SYS`.
- `ld.global.{ca,cg}.nc` canonicalizes to the same `CONSTANT` form; `.cs.nc`
  independently adds `EF`.

These are compiler-lowering facts, not permission to equate PTX memory ordering
with cache residency.

## 4. 256-bit L2 eviction-priority form

PTX 9.3 requires a 256-bit vector form for the direct L2 eviction-priority
qualifier on sm_100+. On sm_120 it uses separate opcodes:

```text
LDG ... .256 opcode = 0x97e
STG ... .256 opcode = 0x97f
```

The L1 field remains `[86:84]`. L2 priority is independent at `[82:81]`:

| Value | Suffix | PTX |
|---:|---|---|
| `0` | `EFL2` | `L2::evict_first` |
| `1` | `ENL2` | default / `L2::evict_normal` |
| `2` | `ELL2` | `L2::evict_last` |
| `3` | invalid | none |

Example showing independent L1/L2 fields:

```text
LDG.E.EL.ELL2.256 R8, R4, desc[UR4][R4.64]
  high:low = 000fc00008241908:fe0000040404797e
```

For this specialized form, decoder-confirmed operand positions are:

- LDG: first destination `high[7:0]`, second destination `low[23:16]`,
  descriptor `low[31:24]`, address `low[39:32]`;
- STG: descriptor `high[7:0]`, address `low[31:24]`, first source
  `low[39:32]`, second source `low[23:16]`.

The cache fields are **verified** by legal PTX pairs; the specialized register
layout is **inferred/decoder-confirmed** because the legal corpus used one
allocator arrangement.

## 5. `createpolicy` and the 64-bit descriptor

### 5.1 Lowering and consumption

There is no dedicated `CREATEPOLICY` SASS opcode on this sm_120 toolchain.
`createpolicy.fractional/range` lowers to ordinary float/integer packing. A
`ld/st.global.L2::cache_hint` then moves the resulting 64-bit value to a UR pair
used as the `desc[URx]` operand. Changing policy changes descriptor-construction
instructions and UR contents; the LDG instruction word itself can remain
identical.

This matches CUDA 13.3's installed
`/usr/include/cccl/cuda/__annotated_ptr/access_property_encoding.h` and the
official [NVIDIA CCCL source](https://github.com/NVIDIA/cccl/blob/main/libcudacxx/include/cuda/__annotated_ptr/access_property_encoding.h).

### 5.2 Common top byte

| Bits | Meaning |
|---:|---|
| `63` | reserved, observed 0 |
| `62` | L2 sector promote 256 B, observed 0 in createpolicy corpus |
| `61` | L1 invalidate/don't-allocate flag, observed 0 |
| `[60:59]` | descriptor mode: `2` fractional/interleaved, `3` range/block |
| `[58:57]` | primary L2 action: unchanged `0`, first `1`, last `2`, normal-demote `3` |
| `56` | secondary: unchanged `0`, evict-first `1` |

### 5.3 Fractional descriptor

| Bits | Meaning |
|---:|---|
| `[55:52]` | for legal PTX `fraction` in `(0,1]`: `uint32(trunc(f32(f32(fraction) * f32(15.99)))) & 0xf`; ptxas emits the binary32 constant `15.989999771...`, an FP32 multiply, unsigned truncation, and a 4-bit mask |
| `[51:0]` | zero in this form |

Selected values returned by the GPU:

```text
normal/unchanged, 1.0       0x16f0000000000000
first/unchanged, 0.75       0x12b0000000000000
last/unchanged, 1.0         0x14f0000000000000  # persisting
last/first, 0.5             0x1570000000000000
```

### 5.4 Range descriptor

| Bits | Meaning |
|---:|---|
| `[55:52]` | block-size enum; block bytes = `2^(12 + enum)` |
| `51` | reserved |
| `[50:44]` | low seven bits of `base / block_bytes` |
| `[43:37]` | primary block count, normally clamped to `1..127` |
| `[36:0]` | reserved/zero |

The block-size enum is `max(0, ceil(log2(total_bytes)) - 19)`. The primary count
is the number of aligned blocks touched by `[base, base + primary_bytes)`, with
unaligned endpoints rounded outward.

CUDA 13.3 CCCL documents a PTX bug for enum `13`: a count above 127 becomes 1
instead of saturating to 127. The sm_120 legal probe reproduced that exact
behavior with a `0xffffffff`-byte range. The recovered model matches all 58
runtime samples; see
[`policy_descriptor_validation.tsv`](isa_re/results/policy_descriptor_validation.tsv).

`createpolicy.cvt.L2` compiled to a low-32-bit zero-extension in the isolated
probe, but no API-produced opaque source value was available to establish its
end-to-end semantics. It remains **partially verified / semantically unknown**.

## 6. Relation to RT/TTU cache work

The existing project already proves that CUDA persisting pre-touch can protect
OptiX AS backing in L2, while TTU requests do not inherit the stream policy
directly. That result is preserved in
[`L2_PERSIST_RT_FINDINGS.md`](rt_cache_probe/L2_PERSIST_RT_FINDINGS.md).

Nothing in this compiler corpus proves a user-controlled TTU-L0 cache bit:

- ordinary LDG/STG/CCTL fields control the SM-side/global-memory path;
- current OptiX D0–D4 triangle-fetch encodings still have no differentiated
  cache-policy operand;
- `EIATTR_LD_CACHEMOD_INSTR_OFFSETS` cannot be transferred to TTU by analogy.

Therefore RT/TTU direct cache priority remains **unknown**. The only verified
software route is indirect L2 protection via ordinary CUDA access.

## 7. Remaining unknowns and stopping boundary

- Runtime semantics of 68 decoder-named internal SR selectors and all 149
  numeric selectors; patched encodings were deliberately never executed.
- Whether `S2R` bit 80 has any hardware meaning.
- Legal high-level triggers and exact semantics for CCTL `WB/IV/RS/IVALLP/
  WBALL/WBALLP` and local CCTLL `WB/IV/RS`.
- Target-independent scheduler/dependency-control bits of the 128-bit word.
- A legal producer and semantic validation for `createpolicy.cvt` input.
- Any writable CSR/perfmon/barrier-control path.
- Any TTU cache-policy field.

Those items cannot be promoted without either a new legal compiler trigger or
additional vendor documentation. They are left explicit rather than filled by
raw-opcode execution.

## 8. Primary references

- [NVIDIA PTX ISA 9.3](https://docs.nvidia.com/cuda/parallel-thread-execution/)
- [NVIDIA CCCL](https://github.com/NVIDIA/cccl)
- local CUDA 13.3 CCCL descriptor source noted above
- project handoff: [`CLAUDE_SW_CACHE_CONTROL_FINDINGS.md`](rt_cache_probe/CLAUDE_SW_CACHE_CONTROL_FINDINGS.md)
- existing TTU work: [`OPTIX_JIT_REVERSE_FINDINGS.md`](rt_cache_probe/OPTIX_JIT_REVERSE_FINDINGS.md)
