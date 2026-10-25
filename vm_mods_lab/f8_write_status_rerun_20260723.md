# GB202 `0x8200f8` direct-write rerun — 2026-07-23

Scope: isolated VFIO VM only. The RTX 5090 was passed through to the existing
`mods-lab-gpu-primary` VM. The host had the GPU bound to `vfio-pci`; the AMD
iGPU was the host display. No VBIOS, firmware, InfoROM, OTP, PCI config, clock,
voltage, reset, or persistent state write was performed.

Host precheck:

```text
01:00.0 NVIDIA GB202 [GeForce RTX 5090] [10de:2b85]
  Kernel driver in use: vfio-pci
01:00.1 NVIDIA GB202 HD Audio [10de:22e8]
  Kernel driver in use: vfio-pci

nvidia-smi on host: No supported GPUs were found
```

The host sysfs `resource0` path could not be used while the device was bound to
VFIO:

```text
mmap BAR0: Invalid argument
od ... resource0: Input/output error
```

The rerun was therefore done through the already-running isolated VM over the
serial console.

## Baseline

Command:

```text
sudo /mnt/prc/gb202_bar0_latch_probe --read-only
```

Relevant baseline:

```text
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

## `0x8200f8` open-then-restore probe

Command:

```text
sudo /mnt/prc/gb202_bar0_latch_probe --commit-f8-open-then-restore
```

Observed write/readback:

```text
phase open f8: BAR0[0x008200f8] = 0xfffffbff
phase open readback f8: BAR0[0x008200f8] = 0xfffffb8f
phase restore f8: BAR0[0x008200f8] = 0xfffffb8f
phase restore readback f8: BAR0[0x008200f8] = 0xfffffb8f
```

After the write attempt, all tracked PLM/latch registers and all raw/effective/
software L2 masks remained equal to the baseline.

## FSP status and guest kernel log

Command:

```text
sudo /mnt/prc/gb202_fsp_prc_read.static --status-only
```

Status after the write attempt:

```text
send_info 0x008f1f10 = 0x80000000 size=0 ready=0 err=0 intr_en=0 intr=1
recv_info 0x008f1f90 = 0x85000009 size=9 ready=1 credit=1 err=0 intr_en=0 intr=1
```

`sudo dmesg | tail -80` showed only earlier MODS open/enable/disable/close
lines and ISO mount messages. It showed no new Xid, PCIe AER, vfio fatal error,
FSP error, GSP error, or guest kernel fault attributable to this probe.

## Conclusion

The 2026-07-23 rerun reproduced the 2026-07-22 result:

- direct host-visible BAR0 write to `0x8200f8` is silently rejected/dropped;
- `0x8200f8` immediately reads back the old value `0xfffffb8f`;
- L2 raw/effective/software masks remain `0x12/0x12/0`;
- visible FSP mailbox status reports no ERR bit.

This supports the current model that `0x8200f8` is protected by a device-side
permission/lifecycle/auth gate rather than by a normal writable host BAR0 path.
