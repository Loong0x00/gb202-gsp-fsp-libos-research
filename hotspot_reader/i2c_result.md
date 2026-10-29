# RTX 5090 I2C read-only inventory

`i2cdetect -l` reports the GPU at `0000:01:00.0` as adapters 1 through 7.
The non-GPU adapters are 0 and 8 through 10.  Read-only SMBus-receive scans
were run only on the seven GPU adapters:

```sh
for bus in 1 2 3 4 5 6 7; do sudo i2cdetect -y -r "$bus"; done
```

Observed addresses:

| adapter | acknowledged addresses |
|---:|---|
| 1 | `0x15`, `0x2b`, `0x67`, `0x68` |
| 2 | none |
| 3 | `0x3a`, `0x3b`, `0x50`, `0x54` |
| 4 | `0x30`, `0x37`, `0x50` |
| 5 | none |
| 6 | none |
| 7 | none |

There are no instantiated `/sys/bus/i2c/devices/*` clients for these GPU
addresses and no NVIDIA hwmon device.  The present hwmon drivers are `nvme`,
`nct6799`, `k10temp`, two `spd5118`, `asus`, `r8169`, and `mt7925`.

Status: **VERIFIED** that no GPU-I2C client is currently instantiated/bound and
that no NVIDIA hwmon node exists.  The identities and capabilities of the
unbound addresses are **UNKNOWN**; probing arbitrary device registers was
intentionally avoided.  The working hotspot candidate was instead found in
the on-die PTHERM MMIO window; its exact NVIDIA-private junction identity is
**INFERRED**, not established by this I2C inventory.

## Lightning cross-flash fan-control check (2026-07-26)

With MSI Lightning 800 W VBIOS active, Linux exported five NVIDIA adapters
named ports 1, 3, 4, 5 and 6.  A receive-byte scan reproduced the same onboard
port-1 devices at `0x15`, `0x2b`, `0x67` and `0x68`; the other acknowledged
addresses remained on display/DDC-like ports.  No new, separately enumerated
fan-controller client appeared.

Address `0x2b` is independently identified as the ASUS IT8915FN-56 power
detector.  With LACT stopped so it could not overwrite the normal NVIDIA fan
target, an all-register read-only A-B-A comparison produced two stable bytes:

| Fan 0 target | reported Fan 0 RPM | IT8915 `0xa2:0xa3` |
|---:|---:|---:|
| 30% | about 801 | `03 a0` |
| 100% | about 2307 | `04 58` |
| 30% restored | about 801 | `03 a0` |

The owner directly observed that only physical fans 1 and 3 changed speed;
fans 2 and 4 remained stopped throughout.  The IT8915 field therefore tracks
some consequence of the working fan group, but the raw value rises only about
20% while RPM nearly triples.  It is not demonstrated to be a PWM target or
tachometer, and is more consistent with a monitored load/derived quantity.
This experiment provides no evidence that IT8915 controls the omitted physical
fans 2 and 4.

Generic PMBus-style identity reads from `0x15`, `0x67` and `0x68` returned no
valid manufacturer/model strings and do not identify any of them as a fan
controller.  Their exact identities remain unknown; no configuration register
was written.  LACT and the original 30% fan target were restored after testing.
