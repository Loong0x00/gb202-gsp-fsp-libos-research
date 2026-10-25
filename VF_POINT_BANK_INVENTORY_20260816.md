# GB202 global VF-point and clock-offset inventory — 2026-08-16

Runtime target: RTX 5090, NVIDIA 610.57.04, current active VBIOS/state.

## Global `CLK_VF_POINTS` object

Commands and sizes:

- INFO `0x20809021`, `0x8208` bytes
- STATUS `0x20809022`, `0x98208` bytes
- GET_CONTROL `0x20809023`, `0x1020c` bytes
- SET_CONTROL `0x2080d024`, `0x1020c` bytes

INFO advertises flat points 0 through 647. They form seven contiguous banks:

| Flat indices | Count | Point type | Domain | Direct frequency-point result |
|---:|---:|---:|---|---|
| 0..126 | 127 | `0x11` voltage-indexed | GPC | effective: point 0 `225 -> 240 MHz`, restored |
| 127..253 | 127 | `0x11` voltage-indexed | XBAR | effective: point 0 `225 -> 240 MHz`, restored |
| 254..258 | 5 | `0x0f` frequency-indexed | MCLK | voltage-point frequency-offset field is cleared/ignored |
| 259..385 | 127 | `0x11` voltage-indexed | SYS | effective: point 0 `180 -> 195 MHz`, restored |
| 386..512 | 127 | `0x11` voltage-indexed | NVD | effective: point 0 `180 -> 195 MHz`, restored |
| 513..639 | 127 | `0x11` voltage-indexed | PWR | CONTROL retains `+15 MHz`; STATUS unchanged at points 0 and 63 |
| 640..647 | 8 | `0x0f` frequency-indexed | PCIE | voltage-point frequency-offset field is cleared/ignored |

The second BoardObj group has no active point mask in this runtime capture.

Every bank accepted a root byte-identical SET and returned an identical
GET_CONTROL preimage. A real `+15000 kHz` write to the voltage-point frequency
offset field changed both CONTROL and STATUS only for GPC, XBAR, SYS, and NVD.
All test writes were immediately restored and the final GET_CONTROL/STATUS
reads matched their original values. No new Xid was logged.

The `0x0f` result does not prove that those records have no type-specific
voltage control. It proves that they do not accept the `0x11` record's tested
per-point frequency-offset field. They are frequency-indexed rather than the
127-point voltage-indexed F(V) curves.

### MCLK type-0x0f STATUS values

A subsequent read-only `--bank-csv MCLK` capture decoded all five records:

| point | effective MCLK | source/effective voltage | total frequency offset |
|---:|---:|---:|---:|
| 0 | 405 MHz | 530 mV | 0 MHz |
| 1 | 810 MHz | 555 mV | 0 MHz |
| 2 | 7001 MHz | 650 mV | 0 MHz |
| 3 | 13801 MHz | 715 mV | 0 MHz |
| 4 | 15001 MHz | 715 mV | +1000 MHz |

The durable CSV is `mclk_vf_bank_20260816.csv`. These STATUS values are enough
for offline type-5 endpoint conversion between MCLK and XBAR/SYS. They do not
establish the writable CONTROL semantics of type `0x0f` records.

## Global `CLK_DOMAINS` frequency offsets

INFO `0x20809019` reports nine domains. GET/SET_CONTROL
`0x2080901b/0x2080d01c` exposes a `0xff` mask, hence records 0 through 7.

| Index | API mask | Domain | INFO offset range (MHz) | `+15 MHz` SET/readback | Effective classification |
|---:|---:|---|---:|---|---|
| 0 | `0x00000001` | GPC | -1000..8000 | exact | advertised adjustable |
| 1 | `0x00000002` | XBAR | -1000..1000 | exact | advertised adjustable |
| 2 | `0x00000010` | MCLK | -1000..5000 | exact | advertised adjustable |
| 3 | `0x00000004` | SYS | -1000..1000 | exact | advertised adjustable |
| 4 | `0x00100000` | NVD | -1000..1000 | exact | advertised adjustable |
| 5 | `0x00080000` | PWR | 0..0 | value retained | not advertised; no decisive hardware shift |
| 6 | `0x00200000` | PCIE | 0..0 | value retained | not advertised; measurement unchanged |
| 7 | `0x00000040` | API40 | 0..0 | value retained | not advertised; measurement unchanged |
| 8 | `0x00000008` | API08 | 0..0 | no control-mask bit | no offset record in this control object |

The low-level SET handler accepting a value is not a capability signal. The
INFO range and final STATUS/hardware behavior distinguish the five real
frequency-offset domains from three inert control slots.

## Voltage-offset boundary

Each exposed clock-domain control record contains signed rail-by-domain offset
slots at `record + 0x10 + rail_index * 4`. Only the XBAR-domain, rail-1/MSVDD
path has been runtime-validated to alter the winning physical MSVDD request on
this build. The existence of matching storage in other domain records is not
evidence that every domain/rail combination is effective. The exact current
global-rail offset field remains unresolved.

## Probe commands

```text
./xbar_vf_point_demo --bank-read BANK
sudo ./xbar_vf_point_demo --bank-noop BANK
sudo ./xbar_vf_point_demo --bank-probe BANK POINT
./xbar_clock_demo --domain NAME
sudo ./xbar_clock_demo --domain NAME OFFSET_KHZ SECONDS
```
