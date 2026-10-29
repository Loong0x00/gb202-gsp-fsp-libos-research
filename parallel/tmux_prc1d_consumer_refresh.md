# PRC 0x1d and task 2/subobject 1 consumer refresh

Date: 2026-07-22

Status: complete; static-only

## Scope, evidence vocabulary, and safety

This audit used only local static material:

- the private MODS 570.151 ELF at mods_audit/static/extracted_inner/mods
  (392,339,552 bytes; SHA-256
  c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf);
- decoded MODS JavaScript at mods_audit/static/decoded/all/gpuargs.js;
- the official-origin local Open GPU Kernel Modules repository at
  /home/user/nvidia-live-recovery-lab/greenfield/open-gpu-kernel-modules,
  read through immutable local tags;
- installed current source at /usr/src/nvidia-610.43.03;
- /tmp/gsp_inner_19f040_a.elf (82,577,496 bytes; SHA-256
  bda917c95547644398eaf77fefe6c7f1b701c962db91f88bffaed6448a218a47),
  /tmp/gsp_inner_61074.elf (82,593,880 bytes; SHA-256
  bff2477fea7c8c8fde194006009f060f8eb1761fe2a1951235530dd57950b2a8),
  and /tmp/fmc_gb202_prod.bin (503,808 bytes; SHA-256
  7db6adc7015aba4938d87c60f403d433b31546e4b56a546465e6be5154a11e6a);
- the four saved GB202 ROM/NVFW images inventoried at
  parallel/vbios_fsp_inventory.md:33-51 and their bounded Falcon-v6 target
  regions at parallel/vbios_fsp_inventory.md:100-136.

Inventory boundary: the scoped local binary set contains the private R570
MODS package and current R610 GSP/GSP-FMC material, but no separately
extracted readable R580 FSP runtime. R580 binary-consumer semantics therefore
cannot be claimed; R580 coverage is the complete 25-tag public-source scan
described below. Sources: mods_audit/570.151_GB202_5090.zip,
/tmp/gsp_inner_19f040_a.elf, /tmp/gsp_inner_61074.elf,
/tmp/fmc_gb202_prod.bin, and the tagged source root listed above.

The local tag scan covered all 52 cached NVIDIA release tags: 25 R570 tags
(570.86.15 through 570.211.01), 25 R580 tags (580.65.06 through
580.173.02), and two R610 tags (610.43.02 and 610.43.03). Representative
peeled commits used for line citations are 570.153.02 at
d5cb404571333ebf7a0b9922306e5bb2b63c4859, 580.126.09 at
455d4b8b75f56d7483489c255705d064fdedf3c6, and 610.43.03 at
452cec62d827034798072827d3866d1881662b77.
The local public repository has no exact 570.151 tag, so the 570.153.02
source citation is not treated as source for the private 570.151 MODS binary;
the cross-version negative result comes from all 25 cached R570 tags.

Evidence labels:

- FACT: directly established by a cited source line, ELF virtual address, or
  explicitly bounded negative scan.
- INFERENCE: a constrained interpretation of facts, but not directly shown by
  the GB202 FSP consumer.
- UNKNOWN: the available static material cannot decide the point.

No MODS or firmware was executed. No live GPU, /dev/nvidia device, MMIO/BAR,
PCI configuration, debugfs, reset, rebind, unload, firmware operation,
credential bypass, or cryptographic cracking was used.
Static commands were limited to bounded rg/git-grep, readelf, strings,
small objdump windows, direct byte reads, and the existing bounded Capstone
window helper; there was no Ghidra import or whole-file decompilation.

## Direct answers

| Question | Result | Evidence level |
|---|---|---|
| What values are allowed for knob 0x1d? | The device-side allowed set is not published. After native normalization, 0 through 65535 is only a necessary host round-trip envelope, not the FSP schema. Boolean and 1-means-arm are unproved. See MODS 0x252cce0..0x252ce27, 0x185f1c0..0x185f2ee, and 0x185ea20..0x185eb45. | FACT for host envelope; UNKNOWN for allowed values |
| Is one-shot consumed or self-cleared? | The name says ONE_SHOT, but the host sends no user-controlled one-shot mode: its write vector is ID16/value16 plus a fixed zero16 tail. It immediately reads the knob back and never performs a post-task-2 clear/read/rearm. The consumer, consumption point, and self-clear timing are unavailable. See MODS 0x18603df..0x186045f, 0x185f1c0..0x185f299, and 0x185f2a6..0x185f474. | FACT for name/host behavior; UNKNOWN for implementation |
| How is task 2/subobject 1 related? | It is a separate PRC-family transaction with its own floorsweep payload. The sender does not copy knob ID 0x1d or its value into that payload. Conditional ordering is PRC write/readback first, then task 2; neither transaction implies the other. See MODS 0x185f284..0x185f2ee, 0x106c4e0..0x106c5bc, and 0x10960bc..0x1096231. | FACT for host protocol; UNKNOWN for an internal FSP dependency |
| What do QCAP and success prove? | QCAP entry 0x13 proves advertised PRC message-family presence. A zero response status proves the command passed the visible response check. Neither supplies a PLM snapshot or proves d0/dc/f8 changed. See MODS 0x1857b10..0x1857b46, 0x185df58..0x185e024, 0x185e530..0x185e55c, and 0x185d6c7..0x185d748. | FACT as protocol only; UNKNOWN for PLM state |
| What d0/dc/f8 evidence exists? | A Hopper sibling path skips the same task only when d0 and dc compare as already lowered, strongly suggesting task 2 prepares those two PLMs. It does not test f8. No readable GB202 consumer or returned state proves an actual write; f8 remains especially unresolved. See MODS 0x1094990..0x1094b23. | INFERENCE for d0/dc purpose; UNKNOWN for actual GB202 effect and f8 |

## 1. Exact identity of knob 0x1d

FACT: The MODS constructor builds the 44-byte name
PRC_KNOB_ID_FLOORSWEEPING_ALLOW_INB_ONE_SHOT from rodata at VAs
0x9224d30, 0x9224d40, and 0x9224c10, then stores ID 0x1d in the same
temporary record at 0x1860458. The earlier 0x1c store belongs to the preceding
RPR_ALLOW_INB record. Source: mods_audit/static/extracted_inner/mods at
0x18603df..0x186045f.

FACT: The insertion loop copies a std::string from record offset 0 and a
32-bit ID from offset 0x20, then advances by 0x28. There is no type, default,
range, enum, Boolean, persistence, or one-shot metadata in this table record.
Source: the same MODS ELF at 0x1860a75..0x1860aab.

FACT: The decoded command-line callback uppercases the supplied name and
applies parseInt to the supplied value, but performs no isNaN, range, enum, or
target-specific check. Source:
mods_audit/static/decoded/all/gpuargs.js:16481-16487.

FACT: The stock PRC-write array starts empty, and pre-init forwards it only
when nonempty. Thus the decoded stock script does not itself auto-inject a
0x1d write. This does not establish the FSP reset/default value. Source:
mods_audit/static/decoded/all/gpuargs.js:251-252 and 7362-7365.

UNKNOWN: No target-specific caller, source schema, or consumer in the readable
material defines the reset/default value. An empty host array means only that
this host path sends no requested write. Sources:
mods_audit/static/decoded/all/gpuargs.js:251-252,7362-7365 and the 52-tag
negative scan in section 7.

## 2. Allowed values: what the host proves and what it does not

### 2.1 Native normalization

FACT: After the JavaScript parse, the native conversion has a ToUint32-shaped
implementation: NaN/infinity/zero selects output zero; large magnitudes use
fmod with the double 2^32 stored at VA 0x920cdf0; negative values are
normalized modulo 2^32; and the result is stored as a dword. Source:
mods_audit/static/extracted_inner/mods callback
0x116bf28..0x116bf4e, numeric conversion
0x252dee0..0x252df11 and 0x252cce0..0x252ce27; bytes at 0x920cdf0 are
00 00 00 00 00 00 f0 41.

FACT: This conversion is normalization, not a 16-bit validator. In particular,
the original command-line spelling and the resulting dword are not
interchangeable. Sources: gpuargs.js:16481-16487 and MODS
0x252cce0..0x252ce27.

### 2.2 Wire width and readback equality

FACT: The generic writer constructs a six-byte vector: knob ID low/high,
requested value low/high, then two literal zero bytes. Helper 0x18563d0 is a
single-byte vector append, confirming that the last two calls add bytes
rather than perform container-only bookkeeping. The writer then sends task
13/submessage 2. Source: MODS 0x185f1c0..0x185f27f,
0x185f284..0x185f299, and 0x18563d0..0x1856406.

FACT: The generic reader sends task 12/submessage 2, requires a four-byte
response vector, zero-extends its first 16-bit word into the output dword, and
returns MODS status 0x12e for the wrong response-vector length. Source: MODS
0x185ea20..0x185eb45.

FACT: After a successful write response, the writer immediately reads the
same ID and compares the zero-extended 16-bit readback with the complete
requested dword. A mismatch returns 0x12f. Source: MODS
0x185f2a6..0x185f2ee and 0x185f458..0x185f474.

FACT: Let D be the normalized dword. The value portion of the wire vector is
D modulo 2^16, while the equality check requires the returned zero-extended
16-bit value to equal D. Therefore D in 0..65535 is a necessary condition for
this generic host path to report readback equality. It is not sufficient: the
device can reject any subset based on ID, policy, phase, SKU, or state.
Sources: MODS 0x185f1c0..0x185f299, 0x185ea20..0x185eb0b, and
0x185f2a6..0x185f2ee.

UNKNOWN: The FSP-accepted set for ID 0x1d is not present. Neither {0,1}, 1 as
arm, 0 as disarm, nor any other enum is proved. The error vocabulary in
section 5 shows that invalid-value rejection exists in this firmware family,
but not which values ID 0x1d accepts. Source: MODS
0x1858480..0x185a7b4 and jump table VA 0x930de00.

INFERENCE: The words ALLOW and ONE_SHOT make a Boolean arm interpretation
plausible, but names are not validators. Current public source explicitly
states value 1 semantics for a different knob, protected-PCIe ID 0x2d, which
demonstrates that NVIDIA publishes per-knob value semantics when available;
that statement cannot be transferred to 0x1d. Sources:
/usr/src/nvidia-610.43.03/src/nvidia/src/kernel/gpu/arch/hopper/kern_gpu_gh100.c:563-603.

## 3. One-shot lifecycle and the task-13/task-2 boundary

FACT: For each requested PRC write, the generic writer first reads current
state. If current equals requested, it skips task 13. Otherwise it sends task
13/submessage 2, immediately reads the same knob, and requires equality.
Source: MODS 0x185f336..0x185f37b, 0x185f1c0..0x185f2a0, and
0x185f2a6..0x185f2ee.

FACT: The task-13 vector contains ID16, value16, and a fixed zero16 tail. The
local code does not name that tail; error name
PRC_TASK_PRC_OBJ_WR_INVALID_OPTIONS makes an options/reserved interpretation
plausible but does not define its bits. The two bytes are constants, not
derived from the knob name, requested value, or a user-selected one-shot,
persistence, lease, generation, session, consume-count, or rearm mode.
Sources: MODS 0x185f1c0..0x185f299, append helper
0x18563d0..0x1856406, and error case 0x1858b65/string VA 0x8c91670.

INFERENCE: If task-12 reads the same state word that is armed by task 13, a
simple self-clear before the immediate readback would make the writer return
0x12f. A design with a separate readable shadow and an internal one-shot
generation remains possible. Sources: MODS 0x185f2a6..0x185f2ee and
0x185f458..0x185f474.

FACT: The GB20x floorsweep sender independently builds a floorsweep payload,
sets task 2 and subobject 1, passes a null response-vector argument, waits for
the common sender status, and propagates a nonzero result. The payload comes
from the floorsweep builder at 0x106bfd0; no ID 0x001d or requested knob value
is copied from the task-13 request. Source: MODS
0x106c4e0..0x106c5bc.

FACT: On the conditional normal path, task 2 returns before pending host
floorsweep apply can execute; a nonzero task status exits before that apply.
Source: MODS 0x10960bc..0x10960d4 and 0x1096221..0x1096231.

FACT: The PRC-write array is optional, while task 2 has its own doFsp,
feature, initialization, and error gates. Thus task 2 can be reached without
a host 0x1d write, and a successful 0x1d write does not guarantee that task 2
will be sent. Sources: gpuargs.js:251-252,7362-7365; MODS
0x10960bc..0x10960d4 and 0x106c4f1..0x106c5c0.

FACT: The visible host path neither rereads 0x1d after task 2 nor writes a
clear value as a paired close. It receives no remaining-use count, lease,
generation, prior value, or undo handle from the task-2 call. Sources: MODS
0x106c570..0x106c5bc and 0x10960cc..0x1096243.

INFERENCE: If 0x1d really gates floorsweep task 2, the visible host evidence
leaves an internal FSP/hardware lookup or consumption of state established
earlier as the compatible linkage. It does not prove that linkage. The host
provides ordering, not a data-flow edge. Sources: MODS
0x185f284..0x185f2ee and 0x106c570..0x106c58c.

UNKNOWN: The consumer point, whether 0x1d is required, whether a rejected task
consumes the shot, whether the readable value self-clears, and how rearming
works are all unavailable without the private GB202 FSP consumer. The
readable GSP and GSP-FMC artifacts are not that consumer; see section 7.

## 4. QCAP and command status are protocol facts, not PLM proof

### 4.1 What QCAP 0x13 contains

FACT: The private task-to-QCAP mapper returns key 0x13 for both task 2 and
task 13. It derives the result from the task number and bitmask 0x4713e; it
does not inspect a register or credential. Source: MODS
0x1857b10..0x1857b46.

FACT: The QCAP parser splits each returned dword into low16 and high16,
stores them as two tree-node dwords, and labels the resulting columns
NvdmType and Version. Thus the entry is a message-family/version tuple, not a
PLM snapshot. Source: MODS 0x185df58..0x185e024; format strings at VAs
0x90fc132 and 0x90fc149.

FACT: Public R570, R580, and R610 headers all define NVDM type 0x13 as PRC
and type 0x15 as FSP_RESPONSE. Sources:
open-gpu-kernel-modules@570.153.02:
src/nvidia/arch/nvalloc/common/inc/fsp/fsp_nvdm_format.h:36-42;
open-gpu-kernel-modules@580.126.09 at the same path:36-42; and
/usr/src/nvidia-610.43.03/src/nvidia/arch/nvalloc/common/inc/nvdm_format.h:
43-50.

FACT: The task-2 packet builder tests QCAP presence before sending. Absence
logs Floorseeping PRC isn't supported by FSP or is not yet active and returns
raw MODS status 0x12d. Presence only permits the independent send to proceed.
Source: MODS 0x185e530..0x185e55c; log string VA 0x8c928a8.

### 4.2 What a command response contains

FACT: The public generic command response is three packed 32-bit fields:
taskId, commandNvdmType, and errorCode. It has no subobject result, knob
state, PLM value, token, prior value, lease, or consume count. Sources:
open-gpu-kernel-modules@570.153.02 and @580.126.09:
src/nvidia/arch/nvalloc/common/inc/fsp/nvdm_payload_cmd_response.h:35-42;
/usr/src/nvidia-610.43.03/src/nvidia/arch/nvalloc/common/inc/fsp/
nvdm_payload_cmd_response.h:35-42.

FACT: The public parser checks size, logs those three fields, and maps only
errorCode to an NV status. Sources:
open-gpu-kernel-modules@570.153.02:
src/nvidia/src/kernel/gpu/fsp/arch/hopper/kern_fsp_gh100.c:505-539;
open-gpu-kernel-modules@580.126.09 at the same path:508-544; and
/usr/src/nvidia-610.43.03/src/nvidia/src/kernel/gpu/fsp/arch/hopper/
kern_fsp_gh100.c:465-500.

FACT: The private common sender enters the selected transport's
response-completion/parser path and returns that status before the
floorsweep dispatcher continues. Both private parsers require response type
0x15 and a zero error dword for their visible success path. Sources: MODS
0x185e890..0x185e8ed, 0x185d6c7..0x185d748, and
0x185ccc3..0x185cd4d.

FACT: Therefore QCAP 0x13 presence and command status zero are two separate
protocol observations: advertised family/version, then accepted completion.
Neither response contains d0, dc, or f8 state. Sources: MODS
0x185df58..0x185e024 and 0x185d6c7..0x185d748; public response definitions
cited above.

UNKNOWN: A zero response cannot establish that GB202 changed a PLM, what
value it wrote, whether a permission window remains open, or whether an
internal one-shot has already been consumed. The host-visible response lacks
the fields needed to prove any of those claims. Sources: MODS
0x106c570..0x106c5bc and the public response definitions above.

## 5. Error vocabulary and status mapping

### 5.1 Private 570.151 error-name table

FACT: MODS function 0x1858480..0x185a7b4 indexes a bounded table at VA
0x930de00 by firmware error code; wrapper 0x185a7c0 formats the numeric code
and selected name. Selected PRC/floorsweep entries are:

| Firmware code | Diagnostic name | MODS case / string VA |
|---:|---|---|
| 0x0af | PRC_TASK_FLOORSWEEPING_INVALID_OPTIONS | 0x1859d44 / 0x8c8f908 |
| 0x1e0 | PRC_TASK_PRC_OBJ_WR_INVALID_OPTIONS | 0x1858b65 / 0x8c91670 |
| 0x1e3 | PRC_ERROR_INVALID_KNOB_ID | 0x1858b38 / 0x90fbbe4 |
| 0x1e4 | PRC_ERROR_PERSISTENCE_NOT_SUPPORTED | 0x1858b29 / 0x8c916e8 |
| 0x1e5 | PRC_ERROR_PERSISTENCE_NOT_ALLOWED | 0x1858b1a / 0x8c91710 |
| 0x1e6 | PRC_ERROR_PERM_KNOB_ID_INVALID | 0x1858b0b / 0x8c91738 |
| 0x1e8 | PRC_ERROR_FEATURE_NOT_ALLOWED | 0x1858aed / 0x90fbc1a |
| 0x1ea | PRC_ERROR_PERMISSION_KNOB_ID_INVALID | 0x1858acf / 0x8c91758 |
| 0x223 | INVALID_PRC_KNOB_VALUE | 0x1858778 / 0x90fbdcc |
| 0x23a | PRC_ERROR_INVALID_KNOB_VAL | 0x185861f / 0x90fbef2 |

FACT: This table proves that the firmware-family diagnostic vocabulary has
invalid-value, invalid-ID, task-option, feature-policy, permission-knob, and
persistence categories. It does not bind any one of those errors to knob
0x1d, GB202, or a particular value. Source: MODS
0x1858480..0x185a7c0 and jump table VA 0x930de00.

UNKNOWN: The allowed task-2 option combinations are also not exposed. Code
0x0af names invalid floorsweeping options, but it is not an enum or validator
table, and the private FSP-side branch that emits it is unavailable. Source:
MODS error case 0x1859d44/string VA 0x8c8f908 and GB20x payload builder
0x106bfd0 reached from 0x106c51e..0x106c537.

### 5.2 Private MODS caller-visible mapping

FACT: If a syntactically received private response has a type other than
0x15 or a nonzero firmware error dword, both the MNoC and EMEM parsers format
the detailed code/name but return raw MODS status 0x12d. Sources: MODS
0x185d6c7..0x185d748 and 0x185ccc3..0x185cd4d.

FACT: QCAP absence for task 2 also returns 0x12d. Consequently, the caller's
0x12d alone does not distinguish unsupported capability, wrong response
type, or a specific firmware application error; the detailed log is needed.
Source: MODS 0x185e530..0x185e55c, 0x185d6c7..0x185d748, and
0x185ccc3..0x185cd4d.

FACT: PRC read response-length mismatch is separately 0x12e, and post-write
readback mismatch is 0x12f. Transport/send failures before a parsed response
can propagate their own nonzero status and must not be collapsed into this
0x12d statement. Sources: MODS 0x185eaf8..0x185eb45,
0x185f2a6..0x185f2ee, 0x185f458..0x185f479, and
0x185e890..0x185e8ed.

### 5.3 Public R570/R580/R610 mapping

FACT: R570.153.02 publicly names only FSP_OK and four 0x9e..0xa1 errors in
this header. Its GH100 mapper handles 0, object-not-found, and invalid-data
cases; all other firmware errors become NV_ERR_GENERIC. Sources:
open-gpu-kernel-modules@570.153.02:
src/nvidia/inc/kernel/gpu/fsp/kern_fsp_retval.h:24-28 and
src/nvidia/src/kernel/gpu/fsp/arch/hopper/kern_fsp_gh100.c:1593-1614.

FACT: R580.126.09 and current R610 add only the PRC-specific public symbol
FSP_ERR_PRC_ERROR_INVALID_KNOB_ID = 0x1e3 and map it to
NV_ERR_INVALID_ARGUMENT; their default remains NV_ERR_GENERIC. Sources:
open-gpu-kernel-modules@580.126.09:
src/nvidia/inc/kernel/gpu/fsp/kern_fsp_retval.h:24-29 and
src/nvidia/src/kernel/gpu/fsp/arch/hopper/kern_fsp_gh100.c:1589-1614;
/usr/src/nvidia-610.43.03/src/nvidia/inc/kernel/gpu/fsp/kern_fsp_retval.h:
24-29 and
/usr/src/nvidia-610.43.03/src/nvidia/src/kernel/gpu/fsp/arch/hopper/
kern_fsp_gh100.c:1583-1608.

FACT: Across all cached tags, that public symbol has zero hits in all 25 R570
tags and is present in every one of the 25 R580 and two R610 tags. This
version transition adds invalid-ID host mapping only; it does not add an
invalid-value schema for 0x1d. Source scope:
/home/user/nvidia-live-recovery-lab/greenfield/open-gpu-kernel-modules,
the 52 release refs listed in Scope.

FACT: Neither public mapper names private invalid-value codes 0x223 or 0x23a;
if received through this generic mapper, they take its default generic path.
This is public-host mapping behavior, not proof that a particular GB202
firmware can emit those codes for 0x1d. Sources: the R580/R610 headers and
switches cited immediately above.

## 6. Static d0/dc/f8 state evidence

### 6.1 d0 and dc

FACT: The Hopper sibling implementation for the same task 2/subobject 1
first checks RegHal read/constant pairs 0x10e0c000/0x40e0c000 and
0x1059c000/0x4059c000. Project RegHal reconstruction maps those pairs to the
0x8200d0 OPT/floorsweep PLM and 0x8200dc L2 PLM. If both compare as the
constant state, the function logs Skipping FSP FS because PLMs are already
lowered! and omits the send; otherwise it sends task 2/subobject 1. Sources:
MODS 0x1094a27..0x1094ae9 and log VA 0x8c09e98;
parallel/l2_plm_static_permissions.md:147-159 and
parallel/task2_lifecycle_audit.md:321-322.

INFERENCE: That sibling precheck is strong semantic evidence that task
2/subobject 1 is intended to prepare at least d0 and dc. GB20x also waits for
the task before its host floorsweep apply, which is compatible with that
purpose. Sources: MODS 0x1094990..0x1094ae9,
0x106c570..0x106c5bc, and 0x10960cc..0x1096231.

UNKNOWN: The inference is not an instruction-level GB202 effect. The GB20x
sender does not read back d0/dc, the command response has no PLM snapshot,
and no readable GB202 FSP task handler was found. Sources: MODS
0x106c4e0..0x106c5bc and public response definitions in section 4.

### 6.2 f8

FACT: The Hopper task-2 precheck tests d0 and dc only; there is no f8 RegHal
query in that bounded function. Source: MODS 0x1094990..0x1094b23.

FACT: A current GB20x MODS security query uses RegHal ID 0x405c4100,
reconstructed as an f8 bit-4 comparison, but it only queries and never sets
the field. Sources: MODS 0x151b059..0x151b070 and
parallel/l2_plm_static_permissions.md:147-159,290-295.

FACT: The only direct 0x8200f8 access in the audited current GSP block is a
read at 0x0108c4ae. That helper may write 0x820040 and 0x82013c, but it does
not write f8. Source: /tmp/gsp_inner_19f040_a.elf
0x0108c494..0x0108c4e8.

FACT: Constructor replay binds that helper only for TU102 and TU116. Current
public source gives GB202 ChipHal index 65, and the replay binds index 65 to
the no-side-effect success stub at 0x019b4ea0 instead. Sources:
/usr/src/nvidia-610.43.03/src/nvidia/generated/g_chips2halspec_nvoc.c:
129-133; /tmp/gsp_inner_19f040_a.elf 0x019bcbf4 constructor,
0x019be874..0x019be87c store, and 0x019b4ea0 stub;
parallel/gsp_f8_consumer_lifecycle.md:241-293.

UNKNOWN: There is no visible GB202 f8 setter, restore, or task-2 state return.
Task 2 may modify f8 inside opaque firmware, or it may not; neither QCAP
presence nor status zero decides this. Sources: MODS
0x1094990..0x1094b23 and 0x106c570..0x106c5bc; current GSP evidence cited
above.

## 7. Cross-version source and packaged-artifact boundary

### 7.1 All cached public 570/580/610 tags

FACT: An exact git-grep over src in all 52 local release tags returned zero
hits for each of:

- PRC_KNOB_ID_FLOORSWEEPING_ALLOW_INB_ONE_SHOT
- FLOORSWEEPING_ALLOW_INB_ONE_SHOT
- ALLOW_INB_ONE_SHOT
- INVALID_PRC_KNOB_VALUE
- PRC_ERROR_INVALID_KNOB_VAL
- PRC_TASK_FLOORSWEEPING_INVALID_OPTIONS
- 0x8200d0, 0x8200dc, and 0x8200f8

The same tag set returned zero case-insensitive hits for floorsweep and
subobject within FSP-scoped source paths. Source scope:
/home/user/nvidia-live-recovery-lab/greenfield/open-gpu-kernel-modules,
refs 570.86.15..570.211.01, 580.65.06..580.173.02, and
610.43.02..610.43.03.

FACT: The public protocol facts persist across releases: PRC is NVDM 0x13,
the generic response has task/type/error only, and R580/R610 add public
invalid-knob-ID mapping. None of these source additions supplies a 0x1d
schema, task-2 consumer, one-shot clear, or d0/dc/f8 state report. Sources:
the tagged/public lines cited in sections 4 and 5 plus the bounded negative
scan above.

### 7.2 Readable packaged 610 GSP-domain artifacts

FACT: Streaming strings scans of /tmp/gsp_inner_19f040_a.elf,
/tmp/gsp_inner_61074.elf, and /tmp/fmc_gb202_prod.bin found zero instances of
the target name/fragments and the selected invalid-option/value names. The
first two are RISC-V ELF executables; the third is not an ELF. Sources: the
three files and hashes listed in Scope; their readelf headers identify both
ELFs as RISC-V EXEC images.

FACT: Current generated GB202 bindata names identify these packaged objects
as GSP images, including g_gsp_gb20x_dyn_spdm_concatenated_fmc_prod_image.bin
and g_gsp_gb20x_dyn_prd_gfw_image.bin. They do not identify a readable FSP
runtime. Sources:
open-gpu-kernel-modules@610.43.03:
src/nvidia/generated/g_bindata_kgspGetBinArchiveConcatenatedFMC_GB202.c:32
and
src/nvidia/generated/g_bindata_kgspGetBinArchiveGspRmFmcGfwProdSigned_GB202.c:
32.

UNKNOWN: A stripped numeric implementation need not contain diagnostic
strings, so zero string hits do not prove that GSP has no related transport
code. They do show that these GSP-domain artifacts offer no string-anchored
0x1d schema or readable FSP task-2 consumer. Sources: the bounded scans and
artifact classifications immediately above.

### 7.3 Saved GB202 FSP-target candidates

FACT: The four canonical ROM/NVFW samples reduce to three distinct
app 0x24/target 0x0f descriptor/region byte groups. Their descriptor word0 is
0x0050060d, which carries the encrypted flag, version 6, and size 0x50 under
the existing parser; the inferred immediate regions have entropy near 7.999
bits/byte. Sources: parallel/vbios_fsp_inventory.md:100-136,170-180 and
parallel/fsp_v6_payload_compare.md:39-75.

FACT: Bounded strings scans over the three unique inferred regions produced
zero selected target/error-token hits:

- GeForce common:
  vbios_diff/unverified_TPU_276859_RTX5090_FE_98.02.2E.00.03.rom,
  file range 0x11b354..0x144754;
- Dell Pro 8D:
  vbios_diff/dell_8d_payload/RTXPRO6000_GB202_GPU_98.02.8D.00.01.nvfw,
  file range 0x128154..0x15ed54;
- HPE Pro 9E:
  vbios_diff/hpe_scexe_payload/RTXPRO6000_GB202_GPU_98.02.9E.00.01.nvfw,
  file range 0x12cd54..0x163d54.

UNKNOWN: The encrypted flag and high entropy make those candidates opaque;
entropy alone does not distinguish encryption from compression or another
high-entropy encoding. Under the no-cracking boundary, they cannot provide a
plaintext task table, validator, one-shot state machine, or d0/dc/f8 write
sequence. Sources: parallel/vbios_fsp_inventory.md:18-25,170-180 and
parallel/fsp_v6_payload_compare.md:64-75,135-149.

## 8. Final classification

### FACT

- ID 0x1d is exactly named
  PRC_KNOB_ID_FLOORSWEEPING_ALLOW_INB_ONE_SHOT, but its MODS table record
  contains only name and ID. Source: MODS 0x18603df..0x186045f and
  0x1860a75..0x1860aab.
- The host normalizes to a dword, writes ID16/value16 plus a fixed zero16
  tail, reads a u16 back, and compares it with the full dword. D in
  0..65535 is only a necessary host success envelope. Source: MODS
  0x252cce0..0x252ce27, 0x185f1c0..0x185f2ee,
  0x18563d0..0x1856406, and 0x185ea20..0x185eb45.
- Task 13/submessage 2 and task 2/subobject 1 are separate transactions.
  They share PRC QCAP key 0x13, not a visible knob-value data flow. Source:
  MODS 0x1857b10..0x1857b46, 0x185f284..0x185f2ee, and
  0x106c570..0x106c58c.
- QCAP gives NVDM type/version, and command response gives task/type/error.
  Neither is a PLM snapshot. Source: MODS 0x185df58..0x185e024 and public
  response definitions in section 4.
- Private MODS preserves detailed firmware error names in logs but collapses
  parsed application errors to 0x12d; public R580/R610 special-case only
  invalid knob ID 0x1e3. Sources: MODS 0x185d6c7..0x185d748,
  0x185ccc3..0x185cd4d; public mappings in section 5.

### INFERENCE

- The Hopper sibling's d0/dc already-lowered precheck strongly indicates that
  task 2/subobject 1 prepares those PLMs before host floorsweeping. It does
  not prove the GB202 consumer's writes. Source: MODS
  0x1094990..0x1094ae9 and 0x106c570..0x106c5bc.
- The knob name makes an arm-once interpretation plausible. If task 2
  consumes it, that dependency must be internal to FSP/hardware rather than
  conveyed in the task-2 payload. Source: MODS
  0x18603df..0x186045f, 0x185f1c0..0x185f299, and
  0x106c570..0x106c58c.

### UNKNOWN

- The exact allowed/default values for 0x1d, including whether 0 and 1 are
  valid and whether 1 means arm.
- Whether a task-2 attempt consumes the shot, when the state self-clears,
  what readback exposes, and how it is rearmed.
- The allowed task-2 floorsweep option combinations and which detailed error
  GB202 returns for each rejection.
- Whether GB202 task 2 actually writes d0, dc, or f8, their resulting values,
  the duration of any permission window, and any internal restore.
- The private GB202 FSP task-2/subobject-1 consumer itself; the relevant saved
  FSP-target regions are not available as readable plaintext under the
  permitted static methods. Sources for all five boundaries: the 52-tag
  negative scan and packaged-artifact analysis in section 7.

## Plain-language summary

The static evidence identifies the knob and the host protocol, but not the
firmware policy. MODS can only round-trip a normalized 16-bit value, and it
immediately checks that value after writing; that does not tell us which
values FSP accepts or how ONE_SHOT is consumed. Task 2/subobject 1 is a
separate PRC command. Hopper code strongly suggests it prepares the d0/dc
floorsweep permissions, while f8 has no comparable task-2 evidence. QCAP
0x13 and a zero command status are capability/completion facts only, never
proof of PLM state. The exact GB202 consumer remains inside an unreadable
private FSP payload, so allowed values, self-clear timing, and actual
d0/dc/f8 effects remain unknown.
