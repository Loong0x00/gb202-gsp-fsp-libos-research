# GB202 `0x8200f8` direct-write status probe — 2026-07-22

Scope: isolated VFIO VM only. No VBIOS, firmware, InfoROM, OTP, PCI config,
reset, clock, voltage, or persistent state write was performed.

Command sequence:

1. FSP MNOC mailbox status read.
2. BAR0 read-only L2/PLM snapshot.
3. Bounded `0x8200f8` open-then-restore probe using
   `/mnt/prc/gb202_bar0_latch_probe --commit-f8-open-then-restore`.
4. FSP MNOC mailbox status read.
5. Guest `dmesg` tail.

The first attempted run used the dynamic `/mnt/prc/gb202_fsp_prc_read` and
stopped before any write because the guest lacked `GLIBC_2.38`. The successful
run used `/mnt/prc/gb202_fsp_prc_read.static`.

## Baseline before write

```text
FSP_STATUS_BEFORE
send_info 0x008f1f10 = 0x80000000 size=0 ready=0 err=0 intr_en=0 intr=1
recv_info 0x008f1f90 = 0x85000009 size=9 ready=1 credit=1 err=0 intr_en=0 intr=1

0x00820040 latch_request        = 0x00000000
0x008200d0 plm_floorsweep_0     = 0xfffffbff
0x008200dc plm_l2_raw_sw        = 0xfffffbff
0x008200e0 plm_8200e0           = 0x00800b8f
0x008200f4 plm_8200f4           = 0x00800b8f
0x008200f8 plm_latch            = 0xfffffb8f
0x008200fc plm_8200fc           = 0x80842bcf
0x00820434 reset_coupling       = 0x00000001
0x008212ac disable_sw_override  = 0x00000001

fbp0..7 raw       = 0x00000012
fbp0..7 effective = 0x00000012
fbp0..7 software  = 0x00000000
```

## Write/readback

```text
phase open f8: BAR0[0x008200f8] = 0xfffffbff
phase open readback f8: BAR0[0x008200f8] = 0xfffffb8f
phase restore f8: BAR0[0x008200f8] = 0xfffffb8f
phase restore readback f8: BAR0[0x008200f8] = 0xfffffb8f
```

After the write attempt, all fixed PLM/latch registers and all raw/effective/
software L2 masks stayed equal to the baseline values.

## Visible status after write

```text
FSP_STATUS_AFTER
send_info 0x008f1f10 = 0x80000000 size=0 ready=0 err=0 intr_en=0 intr=1
recv_info 0x008f1f90 = 0x85000009 size=9 ready=1 credit=1 err=0 intr_en=0 intr=1
```

The guest `dmesg` tail after the probe showed only prior MODS driver
open/enable/disable/close lines and ISO mount messages. It showed no new Xid,
PCIe AER, vfio fatal error, FSP error, GSP error, or kernel fault for this
probe.

## Interpretation

At the currently visible host/FSP surfaces, direct host BAR0 write to
`0x8200f8` behaves like a silent reject/drop:

- the target register immediately reads back the old value;
- adjacent L2/PLM/latch state is unchanged;
- FSP MNOC mailbox status has no ERR bit and no changed ready/credit pattern;
- the guest kernel log has no visible fault event.

This does not prove there is no hidden internal counter or firmware-private
diagnostic state. It does show that the surfaces currently available to the
host-side tools do not expose a useful error return for this direct write.

## Follow-up debug-scratch attempt

After the above result, the public 610 headers were used to identify additional
read-only debug/status offsets:

```text
0x00ad00bc  NV_THERM_I2CS_SCRATCH_FSP_BOOT_COMPLETE
0x008f0320  NV_PFSP_FALCON_COMMON_SCRATCH_GROUP_2(0)
0x008f0324  NV_PFSP_FALCON_COMMON_SCRATCH_GROUP_2(1)
0x008f0328  NV_PFSP_FALCON_COMMON_SCRATCH_GROUP_2(2)
0x008f032c  NV_PFSP_FALCON_COMMON_SCRATCH_GROUP_2(3)
0x000014dc  NV_PBUS_SW_SCRATCH_GSP_FMC_ERROR
0x00110040  NV_PGSP_FALCON_MAILBOX0
0x00110044  NV_PGSP_FALCON_MAILBOX1
```

A direct `od -j offset` read from sysfs `resource0` failed with `Input/output
error`, even for offsets that existing `mmap()` tools can read. This is a sysfs
resource-file access limitation, not a GPU result.

The local `gb202_bar0_latch_probe.c` was extended with read-only debug status
modes and rebuilt:

```text
98a63afb96c3d40ffa82d2cea8a73321552fc396bf8a4eb2abe876a0353a03c6  gb202_bar0_latch_probe
8c25af3e032a20cbb70f2f8586ac40cdd4c1ea9cca2c5512d30d99fadff7418e  gb202-prc-read-tools.iso
```

That extended tool was not executed in the guest during this run: `/mnt/prc` is
a read-only ISO, the QEMU monitor socket was not accessible to the current host
user, the guest has no compiler, and the guest has no network route for HTTP
transfer. Therefore FSP scratch/GSP mailbox/PBUS-FMC before/after comparison
remains a pending read-only follow-up.
