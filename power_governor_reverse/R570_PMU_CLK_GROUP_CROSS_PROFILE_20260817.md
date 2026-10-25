# R570 MODS clear-PMU CLK group cross-profile audit

Date: 2026-08-17

Safety boundary: static reads of the local R570.151 MODS binary and extracted
ELF windows only. No GPU, RM method, fan, clock or voltage control was touched.

## Result

All ten large, structurally valid, unencrypted PMU RISC-V images embedded in
the local MODS binary were scanned for their 0x38-byte CLK BoardObj group
descriptor sequence. Every image contains the same relevant group order:

```text
... 0x07, 0x08, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x10, 0x16 ...
```

No image contains group `0x11` between `0x10` and `0x16`, or elsewhere in the
same descriptor run. This extends the previous GB202-only result: the current
R610 VF-tuple group cannot be recovered merely by choosing a different clear
R570 PMU profile from this MODS package.

## Discriminator

The descriptor identity is structural, not a byte-frequency search. Each row
is 0x38 bytes and begins with a u64 group enum followed by a code pointer. In
the GB202 image, for example:

```text
file +0x0e460: group 0x0b, register function 0x202f64d0
file +0x0e498: group 0x0c
file +0x0e4d0: group 0x0d
file +0x0e508: group 0x0e, register function 0x202f52de
file +0x0e540: group 0x10
file +0x0e578: group 0x16
```

`0x202f64d0` is independently identified as the VF-relation registration by
its `0x2610b0 / 0x30 / 0x80` BoardObj identity. `0x202f52de` is independently
identified as propagation-top-relations. Those anchors validate that this is
the CLK group table and make the missing `0x11` gap meaningful.

## Ten-image scan

The names below are their original MODS file offsets. Some 2 MiB extraction
windows contain a duplicate loaded copy of the same descriptor table; both
copies produce the same sequence.

| Image window | group-0x0b descriptor offset(s) | 0x11 present |
|---|---:|---:|
| `B9589C0.elf` | `0xe460`, `0x129cd0` | no |
| `BA729C0.elf` | `0xfcd0`, `0x1494d0` | no |
| `BBAC9C0.elf` | `0xf4d0`, `0x143338` | no |
| `BCDDC60.elf` | `0x12098` | no |
| `BE65C60.elf` | `0x7a860`, `0x1e8460` | no |
| `BE9AC60.elf` | `0x45860`, `0x1b3460` | no |
| `BECFC60.elf` | `0x10860`, `0x17e460` | no |
| `C03FC60.elf` | `0xe460`, `0x129cd0` | no |
| `C159C60.elf` | `0xfcd0`, `0x1494d0` | no |
| `C293C60.elf` | `0xf4d0` | no |

The first six valid RISC-V images in MODS were separately excluded because
their section names and strings identify SEC2 applications rather than PMU.

## Current R610 package boundary

The installed R610.57.04 firmware package exposes `gsp_ga10x.bin` and a
31,744-byte `ucodes_ga10x.bin`. The latter contains `NVUCODES`, 19 non-zero
bytes and otherwise zeros; it is a manifest/placeholder, not a PMU executable.
No separate GB202 PMU ELF or image is installed. The R610 PMU body therefore
remains inside the authenticated/encrypted GSP firmware payload rather than a
missed standalone host file.
