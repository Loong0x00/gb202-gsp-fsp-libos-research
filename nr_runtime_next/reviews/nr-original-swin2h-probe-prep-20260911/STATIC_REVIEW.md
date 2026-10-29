# Exact original 2h inpview: static memory/control review

Scope: **only** `cc_tinlayout_fused_swin_2h_64_2_inpview_fp8`, module01,
H=W=8, X=Y=0, overrides=(0,0), grid=(1,1,1), block=(32,2,1).
No other inpview/wait/chained/ds kernel inherits this review.
All ranges below are half-open. `l` is lane 0..31, `y` is warp/tid.y 0 or 1.

## Identity, code bounds, exact ELF metadata

Fresh read-only DLL scan/carve and original fatbin equality were checked, not just
an existing cubin filename. Original DLL SHA256:
`e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e`.

| Item | Bounds/identity |
|---|---|
| Original module01 fatbin | DLL `[4858400,7332088)`, 2473688 bytes; SHA `2a2627a5c3b2e9f2d3143c39322af284b03540caa7bd246e0a5481949aca7eb7` |
| Exact original inner ELF | DLL `[5690584,7332088)`, 1641504 bytes; SHA `a10a8083b9489622fe290d669f05f38db7308c3c10771d0f0d6f22718e3cb1ae` |
| Original PTX module | Fresh zstd decompression, SHA `0ebd93ef1f85ac4b1981a2dc31e49c00273e107ebe397bb13b0a72bc97face99`; **9.4 / sm_120 unchanged** |
| PTX entry | Module bytes `[1982329,2202755)`, 220426 bytes; SHA `f5979cb2032432e185a0d7fbcc9b24592902a72fd83920c5e110d7742b772c31` |
| ELF function | Symbol74, section75; ELF bytes `[705792,747392)`, 41600 bytes; SHA `9b75f4a0951707a183e1ef413da0764ed636419c45b9c3eca90ef639e8ba0450` |
| Encoded SASS | **All 2600 16-byte instructions** byte-checked against ELF, no selected-excerpt substitution |
| ELF header | ELF64 little-endian CUDA machine190, ET_EXEC, flags `0x6007802`, SM120 |
| Selected info | ELF offset36944, 484 bytes, SHA `e48d5553349946c5e239a27494d936a8bb8ed8b9122a8583ef40127cf35ce593` |
| Aggregate | One ordinal0 parameter, offset0, size `0x58=88`; parameter cbank base `0x380`, size88 (`0x580380`) |
| Resources | **REG168, STACK0, LOCAL0, SHARED5120**, constant0=984 bytes; texture/surface/sampler0 |
| Barriers | EIATTR_NUM_BARRIERS=1 resource, used by six barrier instructions; MAXREG_COUNT=0xa8 |
| Shared section | NOBITS, size5120, align16; not a 4096-byte dynamic allocation |
| Other metadata | CUDA API version0x86, Mercury ISA1.1, EXIT offset0xa170; selected `.rela.text` size0 |

`MANIFEST.json` retains every selected section's size/offset/flags/alignment/hash,
including original `.nv.capmerc` and `.nv.merc.*` sections. They are **not removed
or rewritten**. General-purpose readelf warns about CUDA-specific section info
values; stderr is retained, and cuobjdump metadata/resource decoding is recorded.
No application relocations in the selected native `.text`; Mercury relocation
metadata is present and unchanged. Loading this original ELF does not by itself
prove which embedded representation a future driver selects.

## ABI and all constant/global memory

**INPUT+0, OUTPUT+8, SLAB+16.** Never use the historical reversed labels.
SASS confirms: input c0[0x380], output c0[0x388] at0x7be0/0x9e90,
slab c0[0x390] at0x0320/0x9890. Scalars: H/W c0[0x3a0]/[0x3a4],
X/Y c0[0x3a8]/[0x3ac], overrides c0[0x3d0]/[0x3d4]. Bytes24..31 and48..79
are not read by this entry and remain zero. Parameter size is88, **not96**.

Additional constant loads: c0[0x358..0x360) supplies the CUDA global-memory
`desc[UR6]` descriptor, not a caller texture/surface handle; c0[0x37c..0x380)
loads R1 (driver launch state, no local-memory accesses follow). These are supplied
by the Driver launch environment, not borrowed from NR. No other constant bank
loads occur. Module-level common resources report GLOBAL2 and CONSTANT[4]16;
this exact entry has no constant4 load, symbol-reference relocation, or memory
address chain to those globals. No extra caller buffer/NR pool is indicated.

Complete SASS census: **97 LDG (33 scalar,64 vector),4 STG,20 LDS,8 STS**.
`STATIC_REVIEW.json` inventories **every** global/shared/constant site, predicate,
operand, and reviewed address family. Full disassembly and code-only text are
provided, not just memory excerpts. All opcodes are checked against a complete
allow-list. No texture/surface, atomics/reductions, generic/local memory,
asynchronous copies, calls, indirect branches, external flag loads or waits.

### INPUT: read-only 4096 bytes

Sixteen predicated 32-bit global load sites; no writes. The full interior family
(from original PTX address chains, with SASS geometry/address setup reviewed at
0x0000..0x12c0) is, j=0..15:

```
row = 4*y + 2*(j%2) + l//16
col = 4*(j//8) + (l//4)%4
group = (j%8)//2
offset = 16*((group*8+row)*8+col) + 4*(l%4)
```

All predicates admit this interior tile. 16×32×2×4=4096 bytes; every input byte
is covered exactly once. Physical layout `[4,8,8,16]`, **not the output layout**.
SASS reordered ingress: ledger intentionally does not invent a per-site PTX-j
bijection. The complete PTX execution events independently retain each original
load PC/lane/offset/data; the SASS census/family review is not a SASS interpreter.
No data-dependent pointer chasing or addresses derived from activations/weights.

### SLAB: read-only61760 bytes

Actual `block5.layer0.layer`, raw file offset141527586, checkpoint payload
offset141532016, sorted512-aligned historical upload offset141544960.
Raw/checkpoint/slab bytes all checked equal; SHA
`1b905577285978107b21b5730aac2b0105d45f757b5e78334291d9b4ab5646bb`.
The nominal F16 container shape30880 does not define dense learned axes.

* Initial coefficients: SASS eight scalar loads at0x0ef0..0x12c0,
  `28688+4*(l%4+k)`, k=0,4,...28. PTX's32 scalar sites reuse these values.
* Learned loop: 28 vector sites at0x1780..0x31c0; base+16*l plus
  pass×8192 for base<16384, pass×4096 for base16384..24575,
  pass×2048 for base24576 onward. Pass is0,1, **not warp y**.
  SASS R164/165 is the slab root; R102/103, R100/101, R104/105 are
  pass-adjusted affine roots (setup0x1750..0x1840,0x30d0..0x3140).
* Exchange tables:12 vector sites0x3f00..0x3fb0; base28832..31392 and
  34976..37536 step512, +3072*y+16*l. Setup0x3e40/0x3e90/0x3ed0.
* Later tables:16 vector sites0x4c60..0x5190 and0x7f70..0x7fe0;
  bases41120..48800 step512, +8192*y+16*l; setup0x3d50,0x4990,0x4bd0.
* Final projection:8 vector sites0x7530..0x7560 and0x9b10..0x9b40;
  bases57520,58032,59568,60080, +1024*y+16*l. Setup0x74f0..0x7510.
* Distinct FP32 scalar at0x4570:57504+4*y, bits0x4018784b /0x411ea836,
  **2.3823421001434326 /9.916067123413086**. Setup0x4540.
* Final packed-half coefficients:8 SASS scalar sites0x7340..0x7490 and
  0x9a20..0x9af0;61616+64*y+4*(l%4+k), k=0,4,8,12 per half.
  Both halves are retained. No substitution of 1h coefficient/scalar locations.

Enumerating the reviewed vector/scalar address forms gives61704 unique bytes:
`[0,28672),[28688,28816),[28832,57512),[57520,61744)`.
The remaining56 bytes are unread. Allocation stays the **entire61760-byte slab**.
PTX trace has10048 lane loads /110848 read bytes including repetitions; these
counts are **not** claimed equal to optimized SASS load counts. All SASS load
addresses are naturally aligned for their4/16-byte width and stay in the slab.

### OUTPUT: write-only4096 bytes, complete coverage

Four original SASS128-bit stores at0x7e40,0x7f50,0xa050,0xa150, q=0..3:

```
offset = 1024*q + 512*y + 16*l
```

Original predicates depend on geometry, not learned values. All four microtiles
are valid at H=W=8,origin0. 4×2×32×16=4096 bytes; exact byte-ownership enumeration
shows no holes/overlap. Output c0[0x388] pointer roots and lane offsets are visible
at0x7be0..0x7e40,0x7ef0..0x7f50,0x9e90..0xa050,0xa0f0..0xa150.
No output read, no input/slab write, no flag publication. Output packing is four
4×4×64-byte microtiles, each with two512-byte warp/channel halves.

Host allocates **4608 output bytes**, passes allocation+256, initializes two
outer256-byte guards (0xa5/0x5a), and compares all4096 payload bytes. The poison
is frozen prediction XOR0xff, so no predicted byte equals initial poison.
On exact equality no byte retained poison; on mismatch a byte equalling poison
may be a numerical collision, **not proof of a missed store**. Guards detect
bounded adjacent corruption, not arbitrary OOB accesses. Input/slab full readback
must remain unchanged. Sync failure forbids all readback.

## Shared footprint and barriers: important 4096 vs5120 distinction

PTX declares4096 user bytes. **Original SASS/ELF reserves5120 static bytes.**
SASS user base is `0x400 + (SR_CgaCtaId <<24)` (0x3c20..0x3d00 and
0x9b50..0x9b70). With this ordinary one-CTA, non-cluster launch, CTA rank=0.
Thus user shared addresses are **[1024,5120)**, and `[0,1024)` is not accessed
by explicit LDS/STS in this function. We do not guess why the toolchain reserves
that prefix. Host supplies **dynamicShared=0** and requires runtime static5120,
register168, local0, binary120, maxthreads≥64, no required cluster setup; any
difference aborts before allocation/launch. No shared attribute override/setter.

For the following table add physical bias1024 and lane16*l:

| Epoch | SASS sites | Access offsets excluding bias/lane | Barrier |
|---|---|---|---|
|0|STS0x3e70,3eb0,3ec0,3ee0|2048*y+{0,512,1024,1536}; fill all4096 user bytes|0x3ef0|
|1|8 LDS0x3fd0..0x4630|{0,512,1024,2048,3072,1536,2560,3584}; both warps read all4096|0x4be0|
|2|LDS/STS0x74b0..0x74e0|512*y+{0,1024}; read old before replacing first2048|0x7520|
|3|4 LDS0x75c0..0x7870|{0,1024,1536,512}; read new first2048|0x7f60|
|4|LDS0x9850,99d0;STS9a70,9ae0|read512*y+{2048,3072} retained epoch0; write512*y+{0,1024}|0x9b00|
|5|4 LDS0x9b90..0x9e00|{0,1024,1536,512}; read new first2048|0xa160|

Every shared site is128-bit, bounds/alignment checked by enumeration. PTX
independent producer/epoch simulation:1792 lane events; cross-warp byte reads
4096,1024,2048,1024,2048 by epochs1..5; no implicit initialization, missing
producer, RAW/WAR/WAW shortcut. Reversed warp scheduling matches. Six64-thread
CTA barriers all use resource0; there are **not six separate barrier resources**.
`BAR.SYNC.DEFER_BLOCKING` is ordinary compiled CTA synchronization, not an
external flag wait. Exactly32×2 threads are mandatory.

## Full loops and terminal control flow

PTX5459 static instructions, one learned backedge2103→1209. Its two passes give
112 loop MMA sites×2 +192 other sites=416 MMAs/warp, **832/CTA**. Both warp
coroutines reach the original terminal `ret` after all six barriers.

SASS304 QMMA sites. Learned backedge **0x3c00→0x1750**: R10 initialized0 at0x1320,
set1 at0x3bc0; UP0 starts true at0x1330, copied into UP1 at0x3ac0 then cleared
at0x3bd0. Branch uses old UP1: one repeat only, no memory condition. Five other
forward branches skip geometry/OOB paths. **There is also an unreachable
self-branch0xa180→0xa180 after unconditional EXIT0xa170**, followed by15 NOPs.
It is recorded, not erased or misreported as no backedges. No earlier branch
targets it. Reachable code `[0,0xa180)`, unreachable padding `[0xa180,0xa280)`.
No external polling or pre/post publication protocol in this exact function.

## Precision and proof limits

Frozen prediction is the completed2h **literal PTX operational reference**, not a
SASS rewrite: exact finite MMA dot+C then RN-even half per MMA, explicit RN-f32
rsqrt/reciprocal stand-ins for approx.ftz, literal half instruction rounding,
E4M3 satfinite. CPU recomputation matched every frozen output byte before GPU.

SASS has320 HMUL2 vs PTX352 mul.f16x2,128 HADD2 vs160 add.f16x2,224 HFMA2 vs192
explicit fma.rn.f16x2. Square/sum sites such as0x44b0/0x44f0 and0x4c30/0x4c70
already warrant a **source-to-SASS contraction audit**; counts alone are not a
complete provenance/rounding proof. General native precision is unknown even if
this single fixture later matches. Tensor-core accumulation, approximation/FTZ,
and fusion differences may produce a legitimate mismatch. Do not alter frozen
predictions or select a tolerance after seeing GPU results; audit separately.

Automated results prove exact container/code bytes, complete opcode/site census,
reviewed affine footprint enumeration, and full operational PTX execution. They
**do not constitute a numerical SASS emulator or an independently executed
per-lane SASS ingress/address replay**. Runtime loading/attributes/code-path
selection and actual synchronization/memory/numerical behavior remain untested.
This is a proposed plain-kernel arithmetic measurement only: no native game
variant/block5 binding, DS publication, multi-CTA concurrency, downstream consumer,
or full-model/frame attestation.
