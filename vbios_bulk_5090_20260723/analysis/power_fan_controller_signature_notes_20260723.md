# RTX 5090 VBIOS power / fan-controller / signature notes

Scope: static local ROM-file inspection only. No flashing, no GPU access.

## Short result

The board power limit is plainly present in the VBIOS power-policy area, but it is inside signed policy data. Editing the bytes is not expected to produce a bootable/accepted Blackwell VBIOS unless the signature chain is also valid.

The fan-related compatibility issue is not just a fan curve. The ROM contains a fan-controller/cooler topology table. In the local RTX 5090 corpus, boards differ in the logical fan-controller slots advertised by `FAN_COOLERS`.

## Power limit location

For the current 1961983-byte RTX 5090 VBIOS samples, BIT `P` v2 points to:

- `P + 0x2c` = `POWER BUDGET`
- relative pointer `0x3f70d`
- absolute ROM offset `0x8f70d`

The table header in these Blackwell samples is:

```text
0x8f70d: 40 38 66 14
version = 0x40
header  = 0x38
record  = 0x66
entries = 0x14
```

This is newer than the old envytools parser support (`0x10/0x20/0x30`), so the whole table should not be over-trusted as fully decoded. The power fields themselves are still obvious because they are little-endian milliwatt values and change exactly with the known BIOS power targets.

Important repeated fields:

| ROM class | `0x8f822` / `0x8f826` | `0x8fa20` / `0x8fa24` | `0x8fa82` / `0x8fa86` / `0x8fa8a` |
|---|---:|---:|---:|
| common 575W BIOS | `575000` | `575000` | `400000 / 575000 / 575000` |
| common 600W BIOS | `600000` | `600000` | `400000 / 600000 / 600000` |
| MSI Lightning 800W | `800000` | `800000` | `400000 / 800000 / 800000` |
| MSI Lightning 1000W | `1000000` | `1000000` | `400000 / 1000000 / 1000000` |
| ASUS/GALAX XOC 2001W | `2001000` | `2001000` | `400000 / 2001000 / 2001000` |

`0x8f7bc` / `0x8f7c0` and `0x9015e` / `0x90177` also commonly contain `1001000` or `1000000`, but those do not by themselves identify the board power target. They look like another cap/profile/rail field.

## Fan-controller / cooler topology

BIT `P` v2 also points to fan-related tables:

- `P + 0x58` = `FAN COOLERS`, absolute `0x909f4`
- `P + 0x5c` = `POWER FAN_MGMT`, absolute `0x90a65`
- `P + 0x64` = `FAN TEST`, absolute `0x90c9a`

`FAN_COOLERS` starts:

```text
version = 0x10
header  = 9
record  = 26
entries = 4
```

The next four bytes behave like logical cooler/controller slot IDs, with `ff` meaning an unused slot:

| sample | apparent active fan-controller slots |
|---|---|
| MSI Lightning 800W / 1000W | `00 ff ff ff` => slot `0` only |
| local ASUS Astral Black/LC-class ROMs | `00 01 ff ff` => slots `0,1` |
| GALAX HOF, ASUS Matrix, MSI Trio, Gigabyte, Palit, Zotac, Inno3D | `00 01 02 ff` => slots `0,1,2` |

This matches the practical cross-flash rule people observe: BIOS images are more likely to behave across boards when board controller/fan topology is compatible. A mismatch can mean wrong PWM/TACH/GPIO/I2C mapping, bad fan behavior, telemetry errors, or firmware/tool refusal. It is not the same thing as the fan curve.

Do not generalize the two-channel result to Astral White.  Public PCB comparison
and modification evidence shows Astral Black uses two GPU fan channels while
Astral White uses three: its rear-side fan has dedicated PWM and tach signals.
Matrix VBIOS exposes the third control on an unmodified Black card, but it is
inert until the separate fan-routing modification is performed.  The local
Matrix ROMs identify this third channel as PWM tag `0xFA` on GPIO line 1 and
tach tag `0xFB` on GPIO line 2; non-Matrix local Astral ROMs mark both lines
unused.  This fan-routing change is separate from the 100-kohm EEPROM-SI strap
change used for Matrix-VBIOS acceptance.

Source: <https://www.hardwareluxx.de/community/threads/offizieller-nvidia-rtx-5090-overclocking-und-modding-thread.1363289/page-124#post-31082403>

## Relationship between fan-controller tables and power limit

They are related as board-policy data, not as one field controlling the other.

- Power target/limit lives in `POWER_BUDGET`.
- Fan controller topology lives in `FAN_COOLERS` / `POWER FAN_MGMT` / `FAN TEST`.
- A high-power BIOS may require matching board cooling/controller/VRM sensor topology to be safe and accepted.
- The fan-controller table does not appear to cryptographically authorize the power limit. It is a compatibility/safety/configuration dependency.

## VBIOS signing

The TPU MD5/SHA1 values are only file identifiers. They are not the GPU security signature.

The local RTX 5090 corpus shows a layered NVIDIA firmware-authentication design:

- nested image hash coverage uses SHA-384-like records;
- adjacent signature-shaped material is 96 bytes, matching P-384-size ECDSA-style signatures;
- public-key-shaped material is 96 bytes, matching a P-384 uncompressed point without prefix;
- the HPE/NVFW package layer previously verified as ECDSA P-384/SHA-384;
- no simple copy-paste signature reuse, repeated-r style defect, or trivial self-verification defect was found in the 23-ROM corpus.

Practical consequence: power bytes can be located, but arbitrary byte edits should be treated as invalidating the signed policy chain on Blackwell.
