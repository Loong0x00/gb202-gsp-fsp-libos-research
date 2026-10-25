# RTX 5090 / GB202: find the live Fan0 GSP address without scanning protected memory

## Role and task

You are taking over a source-led reverse-engineering investigation on a live
Linux desktop machine.  Produce an evidence-labelled plan and, only where the
evidence supports it, the smallest **read-only** validation experiment.

The immediate goal is **not** to modify a fan and not to flash firmware.  The
goal is to locate a defensible runtime address or enumeration route for the
GSP-resident FanCooler object that currently exists as logical `Fan 0`.

Specifically, determine whether any of the following can be recovered safely:

1. the GSP virtual pointer of the FanCooler board-object group or its index-0
   child;
2. a GSP virtual-to-physical mapping plus a legitimate read primitive; or
3. a supported GSP/RM debug or introspection operation that enumerates the
   relevant board-object group.

Do **not** substitute the broader goal of enabling logical Fan 1.  Fan 1 is
currently absent from the GSP runtime object graph and must not be created or
modified during this task.  Finding Fan0 is a controlled way to prove where
the existing object lives and how it can be observed.

## Machine and safety boundary

- Host: Arch Linux, kernel `7.1.4-arch1-1`, x86-64.
- GPU: RTX 5090 / GB202.  It is the display-driving GPU unless stated
  otherwise, and prior invalid read-only-looking address experiments have
  caused a GSP crash, frozen the desktop, then produced a black screen.
- Active NVIDIA driver and GSP firmware: `610.43.03`.
- Active cross-flashed VBIOS: MSI Lightning 800 W, version
  `98.02.2E.C0.0F`.
- The owner has remote SSH/recovery available, but that is **not** permission
  to crash/reset the GPU casually.

Hard prohibitions for this task:

- no VBIOS flash, no VBIOS modification, no GPU reset, no PCI FLR/SBR, no
  unloading/reloading NVIDIA modules, and no desktop/session restart;
- no writes to BAR0, VRAM/FB, GSP memory, GPIO, fan controls, FSP/GSP
  firmware, or RM controls that mutate state;
- no arbitrary or sequential BAR/FB/WPR address probing, even in small chunks;
- no fuzzing of RPC/control IDs or undocumented commands;
- no use of MODS or a VM as a reason to weaken these restrictions.

Permitted only after matching the exact `610.43.03` ABI and explaining the
data path:

- normal public read-only RM controls;
- a narrowly scoped host-only kprobe that uses `copy_from_kernel_nofault` on a
  known in-kernel pointer and is removed immediately after one capture;
- static analysis of the installed matching `nvidia.ko`, the open 610.43.03
  source tree, and the matching GSP image.

Every proposed runtime step must state: exact command/control ID, parameter
size and direction, why it is read-only, expected success value, expected
failure value, and rollback/removal action.  If that cannot be established,
do static work only.

## Ground truth: fan topology and the regression

The original ASUS Astral Black VBIOS creates two FanCooler channels:

- logical `Fan 0` / controller 0 drives physical fans **1 and 3** (case-rear
  side and case-front side);
- logical `Fan 1` / controller 1 drives physical fans **2 and 4** (middle and
  rear/backplate side).

This is direct observation using NVIDIA normal fan controls.  At 100% vs 30%,
the selected logical channel reached about 3270 RPM while the other remained
near 600 RPM.

The Lightning ROM advertises only `FAN_COOLERS = 00 ff ff ff`.  Its fan record
for GPIO3 is `function=0xff, selector=0x00`; the original Astral record is
`function=0xd1, selector=0x5c`, where `0x5c` routes PWM11.  Consequently only
Fan0 exists in the Lightning-booted GSP runtime group, and physical fans 2/4
do not run.

The requested target for this handoff is the existing **Fan0** object, not the
missing Fan1 object.

## Verified facts

### GSP object construction

Static analysis of the matching GSP-RM image established this construction
path:

```text
VBIOS FAN_COOLERS / fan-management entry
  -> temporary GSP cooler descriptor
  -> FanCooler child allocation at GSP VA 0x01b835ec
  -> persistent GSP BoardObjGrp, then insert via group vmethod +0x30
```

- The important importer begins at GSP VA `0x011cd878`.
- Its caller at `0x012f2772` passes the persistent group in RISC-V `a3`
  (`s6` immediately before the call).
- In that allocation branch the parent group is dynamically allocated and
  zeroed with size `0x2b0`; a FanCooler child allocation variant is `0xf0`
  bytes, with descriptor-derived fields copied beginning at child `+0x80`.
- These are boot-time VBIOS-table importers, not normal RM command handlers.
  No public runtime reparse/create operation was found.
- Retargeting an otherwise valid Fan0 control to index 1 returned RM status
  `0x1f`, while its unmodified index-0 form succeeds.  This directly proves
  that Lightning boot has no dormant Fan1 child.

### GSP GPIO boundary

- The raw GB202 GPIO selector implementation is at GSP VA `0x01802f74`
  (`OBJGPIO + 0x250`).  Given an existing runtime GPIO record, it replaces the
  low selector byte while preserving higher bits.
- The desired Astral operation would be `pin=3, selector=0x5c`, but no exposed
  RM control reaches that primitive with caller-controlled values.
- `ActivateHwFunction(function=0xd1,pin=3)` returned `0x0000ffff`; it checks
  Lightning's existing `ff/00` record and cannot create/upgrade it.
- Normal privileged GPIO direction/output controls succeeded through a narrow
  host-side bridge but did not start physical fans 2/4.  Thus simple static
  GPIO high/low is disproven; this is a mux/runtime-record problem.

### GSP heap existence and known host interfaces

- Public `NV2080_CTRL_CMD_GSP_GET_RM_HEAP_STATS` (`0x20803602`) succeeded:

```text
managed=0x0a9045e0  largest_free=0x06096800
current allocated=0x0102b660 usable=0x00ffb3f0 tracking=0x00030270 allocations=12327
```

The managed heap is 169.017 MiB.  It is a real protected GSP-managed heap,
not a speculative small carveout.

- `KernelGsp::pWprMeta` is at offset `0xa80` in the exact installed
  `610.43.03` `nvidia.ko`; this is verified by matching source and by the
  `kgspGetWprEndMargin_IMPL` instruction `mov 0xa80(%rsi), %r12`.
- `pWprMeta` points to a 4 KiB CPU-mapped system-memory descriptor.  A one-shot
  kprobe captured it successfully without accessing GPU memory.  Runtime
  output was:

```text
host metadata=ffff8d429fbf5000
nonwpr=[0x7e6780000,+0x300000]
gspFwWprStart=0, gspFwHeapOffset=0, gspFwHeapSize=0x8700000,
gspFwOffset=0, gspFwWprEnd=0, fbSize=0
```

This is expected for Hopper+/Blackwell: CPU RM requests a heap size, while
FSP/ACR fills actual layout offsets during boot.  The host path receives only
`nonWprHeapOffset` and `frtsOffset` back through `GspStaticConfigInfo`; it does
not provide the actual heap base.

- The public `NV2080_CTRL_CMD_FB_GET_FB_REGION_INFO` (`0x20801320`) was tested
  and returned only one ordinary allocatable region:

```text
base=0x300000  limit=0x7d95cffff  tag=0
```

The matching host source explicitly filters `bRsvdRegion` and `bInternalHeap`.
It therefore does **not** reveal GSP reserved or GSP reserved-heap regions.
Do not infer a WPR address from the unreported space.

- `NV2080_CTRL_CMD_INTERNAL_GET_WPR_REGION_INFO` (`0x20801364`) returned
  `0x56` even after the narrow host `bInternal` bridge.  Evidence indicates it
  needs a genuine RM-internal caller, not merely the internal flag.
- `INTERNAL_MEMMGR_MEMORY_TRANSFER_WITH_GSP` (`0x20800afa`) is not usable on
  this build: its generated host implementation returns
  `NV_ERR_NOT_SUPPORTED` unconditionally.  It would also need a physical
  surface, while the target FanCooler is behind a private GSP virtual heap.

### Invalid paths already closed

- Direct CPU BAR0 reads of target GPIO/PTHERM locations return protected
  sentinel `0xbadf1100`; a direct test write read back the same sentinel.  It
  did not crash but is not proof of an accepted internal write.
- Linux userspace `resource0` accesses fail (`mmap EINVAL`, `pread EIO`).
- An earlier wide, read-only-looking GSP/FB address experiment crashed GSP.
  Do not retry with smaller chunks or different stepping.
- Public GSP test/fuzz controls are fixed tests, not generic RPC dispatch.
- ASUS GPU Tweak / local I2C evidence does not supply an external controller
  for physical fans 2/4.

## What is uncertain

1. The live GSP virtual address of the BoardObjGrp and its Fan0 child.
2. The GSP heap's physical base and private page-table format.
3. Whether any authenticated debug/diagnostic RPC can enumerate BoardObjGrp or
   inspect its allocations on this retail, GSP-enabled firmware.
4. Whether a host-visible cached copy of BoardObjGrp/FanCooler exists outside
   the GSP heap.  No evidence currently proves one exists.

## Required reasoning and output

First audit the supplied records and source files.  Then respond in this form:

1. **Facts confirmed by supplied evidence** — cite file paths and symbols.
2. **Corrections/counterexamples** — identify any invalid inference above.
3. **Candidate routes**, ranked by discriminating power and safety.  Include
   only routes with an exact source-backed API/function boundary.
4. For the best route, give one minimal experiment.  It must be read-only,
   non-scanning, and have exact expected outputs for success/failure.
5. If no safe experiment exists, give a concrete static-research plan: exact
   GSP code regions/functions/strings/callers to inspect next and what result
   would make each lead viable or dead.
6. State clearly whether the result is a **GSP virtual address**, GPU FB
   physical offset, CPU physical address, or host virtual pointer.  Never call
   them all “absolute address”.

Do not claim that private firmware makes the task impossible merely because it
is difficult.  Conversely, do not propose blind enumeration, arbitrary memory
reads, or generic undocumented-control probing.  The standard of proof is a
source-level path plus a minimal runtime discriminator.

## Files to attach / inspect

Attach these text/source files in full; they are the core evidence set:

```text
/home/user/rt_5090_project/fan_runtime_mapping_20260724.md
/home/user/rt_5090_project/gsp_heap_runtime_20260726.md
/home/user/rt_5090_project/gpio_internal_bridge/README.md
/home/user/rt_5090_project/gpio_internal_bridge/bridge_uapi.h
/home/user/rt_5090_project/gpio_internal_bridge/nv_gpio_internal_bridge.c
/home/user/rt_5090_project/gpio_internal_bridge/gsp_heap_stats_probe.c
/home/user/rt_5090_project/gpio_internal_bridge/nv_gsp_wpr_metadata_probe.c
/home/user/rt_5090_project/gpio_internal_bridge/fb_regions_probe.c
/home/user/rt_5090_project/gpio_internal_bridge/sysmem_phys_probe.c
/home/user/rt_5090_project/gpio_internal_bridge/wpr_region_probe.c
/home/user/rt_5090_project/driver_gpio_internal_610.43.03/src/nvidia/arch/nvalloc/common/inc/gsp/gsp_fw_wpr_meta.h
/home/user/rt_5090_project/driver_gpio_internal_610.43.03/src/nvidia/inc/kernel/gpu/gsp/gsp_static_config.h
/home/user/rt_5090_project/driver_gpio_internal_610.43.03/src/nvidia/src/kernel/gpu/gsp/kernel_gsp.c
/home/user/rt_5090_project/driver_gpio_internal_610.43.03/src/nvidia/src/kernel/gpu/gsp/arch/hopper/kernel_gsp_gh100.c
/home/user/rt_5090_project/driver_gpio_internal_610.43.03/src/nvidia/src/kernel/gpu/gsp/arch/blackwell/kernel_gsp_gb10b.c
/home/user/rt_5090_project/driver_gpio_internal_610.43.03/src/nvidia/src/kernel/gpu/mem_mgr/mem_mgr_ctrl.c
/home/user/rt_5090_project/driver_gpio_internal_610.43.03/src/common/sdk/nvidia/inc/ctrl/ctrl2080/ctrl2080fb.h
/home/user/rt_5090_project/driver_gpio_internal_610.43.03/src/common/sdk/nvidia/inc/ctrl/ctrl2080/ctrl2080gsp.h
```

This handoff intentionally does **not** include `nvidia.ko`, a GSP binary, or
any artifact that requires the reviewer to perform local disassembly.  The
decoded results needed for review are recorded in
`fan_runtime_mapping_20260724.md` and in the facts above.  The provided
610.43.03 open-source files are sufficient to audit the host-side interfaces
and the WPR-layout conclusions.  Do not ask for or execute unrelated MODS
payloads or VM images.
