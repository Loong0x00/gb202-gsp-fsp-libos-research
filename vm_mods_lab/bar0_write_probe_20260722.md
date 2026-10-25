# GB202 BAR0 write probe result — 2026-07-22

Scope:

- VM: `mods-lab-gpu-primary.service`, RTX 5090 passed through as `0000:00:01.0`.
- Host GPU/audio remain bound to `vfio-pci`.
- No PCI config, reset, VBIOS, InfoROM, OTP, or host driver bind operation was performed.

Tool:

- Source: `vm_mods_lab/gb202_bar0_latch_probe.c`
- ISO: `vm_mods_lab/gb202-latch-tools-v2.iso`
- Guest mount: `/mnt/latchtools`

Baseline before writes:

- `0x820040 latch_request = 0`
- `0x8200dc plm_l2_raw_sw = 0xfffffb8f`
- `0x8200f8 plm_latch = 0xfffffb8f`
- `0x8212ac disable_sw_override = 1`
- all `raw_fbp[0..7] = 0x12`
- all `effective_fbp[0..7] = 0x12`
- all `software_fbp[0..7] = 0`

Experiment 1:

```text
sudo /mnt/latchtools/gb202_bar0_latch_probe --commit-latch-bit0
write BAR0[0x820040] = 1
readback BAR0[0x820040] = 0
raw/effective/software L2 masks unchanged
```

Experiment 2:

```text
sudo /mnt/latchtools/gb202_bar0_latch_probe --commit-fbp0-bit1-clear-then-restore
write BAR0[0x820040] = 1
write BAR0[0x8234e0] = 0x10
readback fbp0 raw = 0x12
write BAR0[0x820040] = 1
write BAR0[0x8234e0] = 0x12
readback fbp0 raw = 0x12
all raw/effective/software L2 masks unchanged
```

Observed safety state:

- VM remained reachable through serial.
- `mods-lab-gpu-primary.service` remained active.
- Host kernel log check over the immediate window did not show matching NVIDIA/vfio/PCIe/AER/Xid messages.

Interpretation:

- Ordinary userspace `resource0` CPU/BAR writes do not visibly change either the latch request register or the tested L2 raw-shadow word.
- If `0x820040` is self-clearing, the follow-up raw write still did not stick.
- Therefore the next useful path is not “plain mmap BAR0 and poke value”; it must be a transaction path that carries the device-side privilege/context expected by the PLM/gated writer, or a MODS/FSP path that runs before/around the normal init sequence.
