# GB202 `0x8200f8` + `0x8200e0/0x8200f4` bounded race probe — 2026-07-23

Scope: isolated VFIO VM only. Host display remained on the AMD iGPU; the RTX
5090 was passed through to the already-running `mods-lab-gpu-primary` VM.

No VBIOS, firmware, InfoROM, OTP, PCI config, clock, voltage, reset, latch
request, raw L2 mask, effective L2 mask, or software L2 mask write was
performed. The only device registers written by this test were:

```text
BAR0[0x008200f8]
BAR0[0x008200e0]
BAR0[0x008200f4]
```

## Tool

Static guest binary:

```text
43b6a6dbae5fb42f730e03d3b2407bb9532d07042b1857b596b59fb54e6eecd6  gb202_f8_e0f4_race_probe
```

ISO:

```text
7b9d01e0a7a10555a753bae379ac4647fc96d1ead9cc94b9e82b8a4adc503feb  gb202-f8-e0f4-race.iso
```

The binary requires the known RTX 5090 baseline before running. It writes only
the three PLM-like words above. If any tracked PLM or L2 value changes from
baseline, it attempts to restore `f8/e0/f4` and stops immediately.

Written values:

```text
f8 baseline/open: 0xfffffb8f -> 0xfffffbff
e0 baseline/open: 0x00800b8f -> 0x00800bff
f4 baseline/open: 0x00800b8f -> 0x00800bff
```

Patterns:

```text
f8_e0_f4
e0_f4_f8
f8_f8_e0_f4_f8
e0_f8_f4_f8
```

## Baseline

```text
BDF=0000:00:01.0 resource0=/sys/bus/pci/devices/0000:00:01.0/resource0

initial fixed:
  latch=0x00000000
  d0=0xfffffbff
  dc=0xfffffbff
  e0=0x00800b8f
  f4=0x00800b8f
  f8=0xfffffb8f
  fc=0x80842bcf
  reset=0x00000001
  swovr=0x00000001

initial L2:
  fbp0..7 raw       = 0x00000012
  fbp0..7 effective = 0x00000012
  fbp0..7 software  = 0x00000000

initial FSP/MNOC:
  send=0x80000000
  recv=0x85000009
```

## 1024-iteration run

Command:

```text
sudo /mnt/f8race/gb202_f8_e0f4_race_probe 1024
```

Result summary:

```text
pattern=f8_e0_f4       changed=0 l2_changed=0 max_f8=0xfffffb8f max_e0=0x00800b8f max_f4=0x00800b8f
pattern=e0_f4_f8       changed=0 l2_changed=0 max_f8=0xfffffb8f max_e0=0x00800b8f max_f4=0x00800b8f
pattern=f8_f8_e0_f4_f8 changed=0 l2_changed=0 max_f8=0xfffffb8f max_e0=0x00800b8f max_f4=0x00800b8f
pattern=e0_f8_f4_f8    changed=0 l2_changed=0 max_f8=0xfffffb8f max_e0=0x00800b8f max_f4=0x00800b8f
```

Each 1024-iteration pattern took roughly `5.4–6.1 ms`. FSP/MNOC status stayed:

```text
send=0x80000000
recv=0x85000009
```

## 4096-iteration run

Command:

```text
sudo /mnt/f8race/gb202_f8_e0f4_race_probe
```

Result summary:

```text
pattern=f8_e0_f4       changed=0 l2_changed=0 max_f8=0xfffffb8f max_e0=0x00800b8f max_f4=0x00800b8f elapsed_ns=21794554
pattern=e0_f4_f8       changed=0 l2_changed=0 max_f8=0xfffffb8f max_e0=0x00800b8f max_f4=0x00800b8f elapsed_ns=21803615
pattern=f8_f8_e0_f4_f8 changed=0 l2_changed=0 max_f8=0xfffffb8f max_e0=0x00800b8f max_f4=0x00800b8f elapsed_ns=24639291
pattern=e0_f8_f4_f8    changed=0 l2_changed=0 max_f8=0xfffffb8f max_e0=0x00800b8f max_f4=0x00800b8f elapsed_ns=23198758
```

Final tracked state remained identical to baseline:

```text
final f8 = 0xfffffb8f
final e0 = 0x00800b8f
final f4 = 0x00800b8f

final fbp0..7 raw       = 0x00000012
final fbp0..7 effective = 0x00000012
final fbp0..7 software  = 0x00000000

final FSP/MNOC:
  send=0x80000000
  recv=0x85000009
```

Guest `dmesg | tail -100` after the run showed old MODS driver open/close
lines and ISO mount messages. It showed no new Xid, PCIe AER, vfio fatal error,
FSP error, GSP error, or guest kernel fault attributable to this probe.

After the run, VM `ide2-cd0` was restored to:

```text
/home/user/rt_5090_project/vm_mods_lab/gb202-prc-read-tools.iso
```

## Interpretation

This does not rule out an internal sub-PCIe-read-latency transient that the host
cannot observe. It does rule out a host-visible window under the tested bounded
write patterns:

- repeated `f8` writes combined with `e0/f4` writes did not make any of the
  three PLM-like registers read back the open value;
- raw/effective/software L2 state never changed;
- visible FSP/MNOC status never reported an error or changed ready/credit state.

So the best current model remains closer to "the host-visible writes are
dropped/refused before they become observable state" than to "the writes take
effect for a useful host-visible window and are then reverted."
