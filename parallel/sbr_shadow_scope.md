# Local SBR recovery script vs. MODS shadow/reset scope

Status: **final, static cross-audit only**  
Date: 2026-07-21

## Scope and direct answer

This audit read `/home/user/hw_configs/nvidia-reset.sh`, the already-extracted
MODS 570.151 JavaScript/reset reports, and local public NVIDIA/Linux headers as
text. The script was **not** executed, sourced, syntax-traced, or passed to a
shell. No GPU, PCI function, MMIO aperture, driver, process, or service was
accessed or changed.

Direct result:

- The bridge operation in the script is a PCI **Secondary Bus Reset (SBR)**.
  In the MODS vocabulary, that belongs to the **hot-reset class**, not the
  boot-, fuse-, or base-reset classes.
- This is a class/semantics match, not proof that the shell script runs the
  same RM/FSP pre-reset and post-reset orchestration as MODS. The script unloads
  RM first and toggles the bridge directly.
- The script contains no software-override latch clear, fuse resense, saved-old
  raw value or restore, and no post-reset L2/topology validation. Therefore it
  is **not evidence of software-shadow rollback**.

Audited script artifact:

- size: 3,297 bytes
- SHA-256: `672d1fa39e3f7e70bff8729e0c6355dda673644bbcdba944faf9d31fa480f296`
- fixed GPU BDF: `0000:01:00.0`
- fixed upstream bridge BDF: `00:01.1`

## FACT

### 1. The shell operation really is SBR

The script performs these source-visible steps:

1. stop `lactd`;
2. find NVIDIA character/DRI nodes, TERM then KILL every holder, and abort if a
   holder remains;
3. unload `nvidia_drm`, `nvidia_uvm`, `nvidia_modeset`, and `nvidia`;
4. issue masked writes to the upstream bridge's `BRIDGE_CONTROL` word, first
   setting and then clearing bit `0x40`;
5. request a PCI rescan and confirm that `01:00.0` appears in `lspci`;
6. reload the four NVIDIA modules;
7. accept `nvidia-smi` success as verification, then restart `lactd`.

These operations are directly visible at `nvidia-reset.sh:28-103`. Linux's
public PCI register header names bridge-control bit `0x40` as
`PCI_BRIDGE_CTL_BUS_RESET` and comments it as `Secondary bus reset`
(`/usr/include/linux/pci_regs.h:166-172`).

The argument guard at `nvidia-reset.sh:9-14` makes any invocation with an
argument exit without the reset sequence; a genuine no-argument invocation
continues into the destructive workflow.

### 2. MODS names SBR as HotReset

The extracted MODS 570.151 argument table states:

```text
hot_reset -> Gpu.Reset=Gpu.HotReset -> "Do a secondary bus reset"
boot_reset -> Gpu.BootReset
fuse_reset -> Gpu.FuseReset
base_reset -> Gpu.BaseReset
```

The entries are adjacent and distinct at
`mods_audit/static/decoded/all/gpuargs.js:755-762`. Thus the correct MODS class
for the script's SBR is **hot reset**.

This is semantic classification, not numeric equality. The audited MODS
post-program mapper uses RM states `3/5/6/7` for
`hot/boot/fuse/base` respectively
(`L2_REENABLE_STATIC_FINDINGS.md:1208-1224`). The public BIF control instead
uses interface type values `2/4/5/8` for
`SBR/BOOT_DEVICE_FUSE/BOOT_DEVICE/BASE`
(`/usr/src/nvidia-610.43.03/src/common/sdk/nvidia/inc/ctrl/ctrl0080/ctrl0080bif.h:37-76`).
Those numbers live in different APIs.

As an additional naming cross-check only, public NVIDIA RM code calls its
bridge-bit implementation `kbifDoSecondaryBusHotReset`, sets bit `0x40`, then
clears it (`kernel_bif_gm107.c:1557-1614`). That older implementation is not a
GB202 lifecycle proof, but it independently confirms NVIDIA's use of “hot
reset” for SBR.

### 3. SBR is distinct from boot/fuse/base reset in the available interfaces

The public Blackwell-capable BIF header enumerates SBR separately from
`BOOT_DEVICE_FUSE`, `BOOT_DEVICE`, and `BASE`; it also says fundamental reset is
not supported for Blackwell and later, directing clients to boot-device-fuse or
boot-device instead (`ctrl0080bif.h:46-52,68-76`). Consequently the script's
plain bridge SBR cannot be relabelled as fuse, boot, base, fundamental, or cold
reset merely because it causes a substantial device restart.

The established MODS 570.151 shadow path also makes these classes operationally
distinct. Normal post-program reset/reinit selects existing coupling in this
priority: base, fuse, boot, otherwise hot. The normal writer does not establish
a coupling for this transaction (`L2_REENABLE_STATIC_FINDINGS.md:1208-1263`;
`parallel/shadow_reset_lifecycle.md:126-166`).

### 4. The script has no shadow rollback operations

The complete 103-line script contains none of the following:

- a read or snapshot of the prior raw shadow plan;
- a write restoring old raw values;
- the known latch-clear coded request `0x404f0000`;
- a read of the override latch represented by `0x820040.bit0`;
- a fuse-resense API or fuse-reset coupling request;
- a read/compare of raw `0x8234e0 + 4*FBP`;
- a read/compare of current/effective `0x822900 + 4*FBP`;
- a read/compare of fuse-status `0x820d70 + 4*FBP`;
- an LTS mask, L2 capacity, per-FBP topology, or memory integrity test.

Its post-reset checks are only device presence through `lspci` and general RM
availability through `nvidia-smi` (`nvidia-reset.sh:76-103`). Neither check
establishes the effective L2 topology.

By contrast, the separate MODS resense path first attempts state-6 coupling,
then issues `0x404f0000`, then conditionally enters reset/reinit. Both
preparatory results have weak/error-tolerant handling, and this path is separate
from normal direct-shadow success and failure tails
(`parallel/shadow_reset_lifecycle.md:168-197`). The shell script invokes none of
that host path.

### 5. Module reload is software reconstruction, not a fifth reset class

Unloading and reloading the NVIDIA modules discards and recreates host driver
state around the SBR. It is not itself a MODS hot/boot/fuse/base reset selector;
the script makes no explicit reset-coupling request and does not become a
managed invocation of MODS' reset/reinit dispatcher. In particular, the script
has already removed the NVIDIA kernel modules before it toggles the bridge.

## INFERENCE

1. The procedure can plausibly recover dirty RM/GSP state after all GPU users
   have been removed; that matches its stated original purpose. Success in that
   role says nothing about rollback of fuse-shadow state.
2. At the PCI reset-mechanism level, its closest and correctly named MODS peer
   is hot reset/SBR. At the full software-lifecycle level, equivalence is not
   established because MODS performs its own save, unload, firmware wait, and
   RM reconstruction around a coupling-selected reset, while the script relies
   on module unload/reload and PCI rescan.
3. A fresh module load may cause RM and firmware to rebuild their discovered
   topology. That could expose whatever effective topology survived or was
   recomputed by SBR, but it does not imply restoration of the pre-write raw
   plan or physical-fuse topology.
4. A successful `nvidia-smi` would show only that a basic management path came
   back. A partially changed or unexpectedly retained L2 mask could still pass
   that check.
5. Because the script supplies neither old raw data nor a latch-clear/resense
   request, treating it as rollback would require an undocumented implicit SBR
   side effect. No inspected source establishes that side effect.

## UNKNOWN

1. Whether GB202 SBR preserves, clears, consumes, or recomputes
   `0x820040.bit0`, raw shadow, fuse-status, and effective-mask state.
2. Whether GB202/GSP performs an implicit fuse resense during SBR or subsequent
   module initialization. The absence of an explicit shell operation cannot
   rule out hidden hardware/firmware behavior.
3. Whether an accepted or partially accepted shadow plan survives this exact
   board's SBR and driver reload.
4. Whether a malformed effective topology could prevent configuration access,
   GSP boot, module reload, or `nvidia-smi` before any useful diagnosis.
5. Whether the fixed bridge contains other downstream functions that SBR would
   also reset, and whether the fixed BDFs remain correct after firmware, slot,
   or enumeration changes.
6. Whether boot, fuse, base, cold power-cycle, or explicit resense would restore
   physical-fuse topology in every partial-failure state. None is currently a
   proven safe rollback.

## Evidence matrix

| Question | Result | Classification |
|---|---|---|
| What reset does the script issue? | PCI bridge SBR via bit `0x40` | **FACT** |
| Closest MODS reset class? | `HotReset` / hot, because MODS explicitly defines it as SBR | **FACT** |
| Is it boot/fuse/base/cold reset? | No such equivalence is shown; those are separately enumerated | **FACT** for separation; exact silicon-domain relation **UNKNOWN** |
| Does it clear the shadow latch? | No explicit operation exists in the script | **FACT**; implicit hardware clear **UNKNOWN** |
| Does it resense physical fuses? | No explicit resense/coupling operation exists | **FACT**; implicit firmware behavior **UNKNOWN** |
| Does it restore saved raw values? | It saves no old values and writes no raw plan | **FACT: no** |
| Does it validate L2 after reset? | Only `lspci` and `nvidia-smi`; no L2/effective check | **FACT: no** |
| Is it software-shadow rollback evidence? | No | **CONCLUSION from FACTS** |

## Minimal conclusion

`nvidia-reset.sh` is a forceful whole-device **hot/SBR recovery** procedure plus
driver reconstruction. It is not a boot/fuse/base reset selector and not a
shadow transaction undo path. Because it neither records/restores old raw masks
nor clears the latch/resenses physical fuses nor verifies effective L2 after
reset, it cannot close the project's rollback requirement. It must remain a
lab recovery tool for use only after display and every GPU user have moved away
from the RTX 5090; it provides no safety argument for a live shadow experiment.
