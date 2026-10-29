# GB202 thermal register / private NvAPI evidence (driver 610.43.03)

Scope: read-only experiments on `0000:01:00.0` (GeForce RTX 5090).  No MMIO
write, firmware change, or kernel patch was performed.

## Bottom line

* **VERIFIED observational structure:** BAR0 offsets
  `0x00ad0a90..0x00ad0aa4` and `0x00ad0ad0..0x00ad0ae4` are two six-word live
  PTHERM temperature groups.  Within each group, word 4 (`0xad0aa0` or
  `0xad0ae0`) equalled the raw-word maximum of words 0..3 in all 650 samples.
  The winning source changed between word 0 and word 3, making a MAX
  aggregation interpretation strong rather than a fixed sensor merely
  remaining hottest.  Word 5 is another temperature-shaped auxiliary value.
* **VERIFIED mirror relation, UNKNOWN role:** in the 250-sample trace that
  included them, `0xad0b50 == 0xad0aa0` and `0xad0b70 == 0xad0ae0` as exact
  raw words in every sample.  They are redundant mirrors for this reader, not
  independent proof of a private hardware-MAX register role.
* **INFERRED junction/hotspot:** the operational reader reports
  `max(decode(0x00ad0aa0), decode(0x00ad0ae0))`.  The signal is physically
  temperature-shaped and rose from 42.6 C idle to 81.375 C while edge rose
  from 39 C to 68 C.  Its identity as the GB202 junction/hotspot aggregate is
  strongly inferred from that behavior and the observed MAX invariant,
  but NVIDIA has published neither the GB202 register symbols nor the
  per-channel sensor mapping.
* **UNKNOWN private semantics:** NVIDIA's names for the aggregate and mirror
  words, the four source locations, the auxiliary word, and the exact purpose
  of the two groups (which can differ during transients) are unknown.  They
  must not be named GPC numbers, live/shadow, or even/odd banks without private
  GB202 hwref evidence.
* **VERIFIED:** the two legacy pre-Blackwell live-temperature HAL slots are
  unavailable on GB202: both are replaced by `NV_ERR_NOT_SUPPORTED` stubs.
  This does not invalidate the independently observed Blackwell PTHERM banks.
* **VERIFIED:** the private NvAPI thermal-channel API advertises `GPU_MAX`, but
  returns the invalid `255.0 C` sentinel for it in both status and PMUMON.
  Its other live value is `GPU_AVG` (edge); the integer value near 60--68 C is
  explicitly the `MEMORY` primary channel, not hotspot.

The raw values and numerical invariants are verified; the NVIDIA-private
roles and final hotspot label remain inferred/unknown as marked above.

## Public-source negative evidence

### NVIDIA open KMD / published hwref

`/usr/src/nvidia-610.43.03/src/common/inc/swref/published/blackwell/gb202/dev_therm.h`
contains only:

```
line 27: NV_THERM_I2CS_SCRATCH = 0x00ad00bc
lines 28-29: scratch data field/init value
```

The companion `dev_therm_addendum.h`, lines 27--30, only assigns FSP boot
status meanings to that scratch register.  There is no GB202 TSOSC, TSENSE,
current-temperature, or maximum-temperature register definition.

### Upstream Nouveau

Linux master `3b029c035b34bbc693405ddf759f0e9b920c27f1` (2026-07-13):

* `include/nvhw/ref/gb202/dev_therm.h`, lines 8--14, likewise contains only
  `0xad00bc` and its FSP scratch aliases.
* `nvkm/engine/device/base.c`, lines 2837--2851, defines GB202 without a
  `.therm` subdevice.
* `nvkm/subdev/therm/Kbuild`, lines 1--18, ends at `gp100.o`; there is no
  Blackwell thermal implementation.
* `nvkm/subdev/therm/gp100.c`, lines 33--44, is the old path: BAR0 `0x20460`,
  data mask `0x1fff8`, bit 30 shadow diagnostic, bit 29 valid, integer result
  `(reg & 0x1fff8) >> 8`.

### Public nvgpu

OE4T nvgpu `a4145c7b6e05af9b5ee4b8da246e3b3820023dca`:

* `include/nvgpu/bios.h`, lines 1018--1023, proves that VBIOS thermal-device
  class `0x02` is `GPU_GPC_TSOSC`; lines 1032--1058 define primary GPU average,
  GPU maximum, board, memory and supply channels plus device/provider indices.
* `common/pmu/therm/ucode_therm_inf.h`, lines 42--45, carries a
  `gpc_tsosc_idx`; lines 109--113 return `current_temp` in the PMU channel
  status object.
* Neither the GA100 nor GA10B generated `hw_therm` header contains `tsosc`,
  `tsense`, `sensor`, or `temp` register definitions.  The older TU104 header
  only exposes `therm_i2cs_sensor_00_r() = 0x20400` (line 129), used as the
  integer internal/edge sensor.

This tree proves the object model and Q24.8 data path, but supplies no GB20x
GPC TSOSC MMIO address.

## GSP HAL: old live-register methods are explicit GB202 stubs

Reproduction and full disassembly are in `gsp_therm_current_evidence.md` and
`gsp_therm_vtable_dump.py`.

```
slot      GA102/AD102   GB202
+0x198    0x0187c564    0x01a07ef8
+0x1c8    0x0187c4c0    0x01a07f58
+0x268    0x018776bc    0x01a08098
```

**VERIFIED:** old slot `+0x198` reads `0x20460 + 4*i`, accepts the sample only
when raw bit 30 is set, and decodes:

```
accepted_by_this_method = (reg >> 30) & 1
temperature_C = sign_extend_14((reg >> 3) & 0x3fff) / 32.0
```

The acceptance-bit name is method-local: Nouveau's older integer reader calls
bit 29 valid and bit 30 shadow, so bit 30 is not asserted to be a universal
TSENSE validity bit.

It converts to NvTemp Q24.8 by shifting that signed 14-bit value left three.
Old slot `+0x1c8` reads `0x204a0` with the same conversion.  On GB202 both
slots are 16-byte stubs returning `a0 = 0x56` (`NV_ERR_NOT_SUPPORTED`), and
the old count method at `+0x268` returns `0xff` instead of 8.

Read-only live confirmation: `0x200bc`, `0x20400`, `0x20460`, `0x204a0`, and
`0x206f8` all read `0xbadf1100` on this GB202.

## GB202 live PTHERM words and observed MAX aggregation

The working read-only register set is:

| role | BAR0 offsets | physical addresses with BAR0=`0xd8000000` | status |
|---|---|---|---|
| bank A sources, four words | `0x00ad0a90, a94, a98, a9c` | `0xd8ad0a90..0xd8ad0a9c` | **VERIFIED live temperatures**; identities **UNKNOWN** |
| bank A observed aggregate | `0x00ad0aa0` | `0xd8ad0aa0` | 650/650 exact MAX of the four sources; relation **VERIFIED**, private role **INFERRED** |
| bank A auxiliary | `0x00ad0aa4` | `0xd8ad0aa4` | live temperature; role **UNKNOWN** |
| bank B sources, four words | `0x00ad0ad0, ad4, ad8, adc` | `0xd8ad0ad0..0xd8ad0adc` | **VERIFIED live temperatures**; identities **UNKNOWN** |
| bank B observed aggregate | `0x00ad0ae0` | `0xd8ad0ae0` | 650/650 exact MAX of the four sources; relation **VERIFIED**, private role **INFERRED** |
| bank B auxiliary | `0x00ad0ae4` | `0xd8ad0ae4` | live temperature; role **UNKNOWN** |
| aggregate A mirror | `0x00ad0b50` | `0xd8ad0b50` | 250/250 raw-equal to `0xad0aa0`; role **UNKNOWN** |
| aggregate B mirror | `0x00ad0b70` | `0xd8ad0b70` | 250/250 raw-equal to `0xad0ae0`; role **UNKNOWN** |

All captured words use the same packed form as the legacy GSP conversion:

```
accepted_by_legacy_method = (raw >> 30) & 1
q5 = sign_extend_14((raw >> 3) & 0x3fff)
temperature_C = q5 / 32.0
```

For these GB202 words, bit 30 was set in every captured sample, bits 2:0 were
zero, and the value field changed in 1/32 C steps.  The formula is therefore
**VERIFIED observationally** for this register set and independently matches
the exact old-GSP instructions at VA `0x0187c5f0..0x0187c604`.  The name of
bit 30 is not verified for GB202: report only that it was observed set, not
that it is universally `VALID` or `READY`.  Nouveau's older integer path
assigns different names to bits 29 and 30.

The strongest structural check is the numerical aggregation relation.  Across
both raw traces (650 samples):

```
raw(0x00ad0aa0) == max(raw(0x00ad0a90), raw(0x00ad0a94),
                       raw(0x00ad0a98), raw(0x00ad0a9c))
raw(0x00ad0ae0) == max(raw(0x00ad0ad0), raw(0x00ad0ad4),
                       raw(0x00ad0ad8), raw(0x00ad0adc))
```

The relation held 650/650 for both banks with zero raw-word error.  Source 0
won 371 times and source 3 won 279 times in each bank.  In the 250-sample
trace, both mirror relations also held 250/250.  The old CSV header called
the mirrors `hwmax` and computed a six-word software maximum; that provisional
check was degenerate because the six words already included the aggregate.
`validation/audit_trace.py` corrects this by ignoring all derived columns and
recomputing the four-source relation from raw address/value pairs.

The 400-sample trace covered candidate 42.594--81.375 C while edge covered
39--68 C; the largest instantaneous candidate-minus-edge delta was 20.781 C.
The two banks are nearly identical at steady state but can differ during fast
transients (up to about 11.9 C in that trace), so their exact relationship is
**UNKNOWN**, not a verified live/shadow pair.  Taking the larger observed
aggregate avoids dropping a transient peak.

Reproduce without mapping `/dev/mem` or writing MMIO:

```sh
cd /home/user/rt_5090_project/hotspot_reader
make gb202_hotspot
sudo ./gb202_hotspot -r
sudo ./gb202_hotspot -c -r -i 100
```

`gb202_hotspot.c` submits only `NV2080_CTRL_GPU_REG_OP_READ_32` operations of
type `GLOBAL` through `NV2080_CTRL_CMD_GPU_EXEC_REG_OPS`; it contains no
register-write opcode/path.  The direct operational value is:

```
hotspot_candidate_C = max(decode(BAR0+0x00ad0aa0),
                          decode(BAR0+0x00ad0ae0))
```

Status of that last semantic name and the private aggregate role is
**INFERRED**; the live temperature behavior and exact numerical invariants
above are **VERIFIED**.

### GSP static evidence, limits, and selector safety

No GSP RM function was found that directly reads these live or aggregate
offsets.  A complete recognized BAR-access inventory of the 610.43.03 RM ELF
plus exact-u32 searches found no consumer of `0xad0a90..aa4`,
`0xad0ad0..ae4`, `0xad0b50`, or `0xad0b70`.  The nearest code at VA
`0x0187e56c` reads configuration arrays `0xad0a10+4*i` and
`0xad0a50+4*i`; VA `0x0187e79c` reads `0xad0b10+4*i` and
`0xad0b30+4*i`.  Those are configuration accesses, not current-temperature
reads.  This supports, but does not prove, an autonomous PTHERM update/MAX
path.  Exact firmware function names are stripped and therefore **UNKNOWN**.

The firmware also contains an indexed PTHERM programming helper at VA
`0x017b01f8`.  It writes selector/data ports `0x00ad07f0/0x00ad07f4`, gathers
up to 12 selected 7-bit indices from a mask, and fills a 12-slot mapping.  The
public full-GB202 architecture has 12 GPCs, so a relationship to GPC TSOSC
selection is plausible, but linking those selector indices to these live bank
positions is only **INFERRED**; the exact mapping remains **UNKNOWN**.

**Do not write `0x00ad07f0` or `0x00ad07f4`.**  Reading the data port without
changing its selector cannot enumerate the table, while writing the selector
would violate the read-only guardrail and can race/corrupt GSP-owned thermal
configuration.  The working reader neither reads nor writes these ports.

## Other PTHERM/TSENSE candidates that must not be reported as hotspot

The exact raw capture is `mmio_known_candidates_20260714.txt`.

* **VERIFIED threshold, not current:** `0xad0054 = 0x08046e00` decodes as
  110 C with the old bits-16:3 formula.  GSP code reads it as a limit.
* **VERIFIED threshold table, not current:** `0xad0714 = 0x03580da0` stores
  109 C and `0xad0718 = 0x03480d60` stores 107 C as low-14-bit Q9.5.  GSP
  slot `+0x2a0` reads `0xad0700 + 4*i` while initializing enabled limits.
* **INFERRED invalid TSENSE shadow:** NVIDIA's published LS10 switch hwref
  places BJT current sensors at Therm offset `+0xf10..+0xf24,+0xfa0..+0xfa8`,
  with temperature in bits 13:0, valid bit 30 and enable bit 31.  Applying
  only this structural layout to GB202's verified `0xad0000` Therm base:
  `0xad0f10..24` and `0xad0fa0/fa4` all have valid=0; `0xad0fa8` also has
  valid=0 and an impossible 337.5 C payload.
* **INFERRED invalid maximum shadow:** LS10 names offset `+0xf40` the maximum
  TSENSE register (temperature bits 13:0, sensor number bits 24:16).  GB202
  `0xad0f40 = 0x001f08cd` has a 70.406 C payload but sensor number 31, outside
  the published BJT indices 0..8.  It remained bit-identical while edge and
  power changed.  It is therefore an invalid/stale shadow, not a verified
  live hotspot.
* **VERIFIED raw, INFERRED meaning:** `0xad0f44 = 0xffffffcf` is a stable
  near-all-ones word.  Under the same LS10 layout it resembles an
  unprogrammed warning/overtemp threshold, but that semantic mapping is not
  published for GB202.

Other dynamic PTHERM Q9.5-like words such as `0xad0460/464` and
`0xad04b8..c4` tracked edge/board-like zones.  They are distinct from the
verified live groups and aggregate candidates above; their semantic names
remain **UNKNOWN**.

## Private NvAPI exact IDs and layouts

Reproduce with:

```
python hotspot_reader/nvapi_thermal_probe.py \
  --raw-dir hotspot_reader/nvapi_probe_output
```

The script invokes only Get/Status/Samples calls.  Driver library SHA-256:
`14a4861b513d9575a679bc470209e532bfceba688631c6be6eda40ff559b7817`.

| Interface | ID | successful version | size |
|---|---:|---:|---:|
| `NvAPI_GPU_ThermDeviceGetInfo` | `0x6ff0350c` | `0x0002f7d4` | `0xf7d4` |
| `NvAPI_GPU_ThermChannelGetInfo` V2 | `0x0bc8163d` | `0x00020ab0` | `0x0ab0` |
| `NvAPI_GPU_ThermChannelGetInfo` V3 | `0x0bc8163d` | `0x00033650` | `0x3650` |
| `NvAPI_GPU_ThermChannelGetStatus` V2 | `0x65fe3aad` | `0x000200a8` | `0x00a8` |
| `NvAPI_GPU_ThermChannelGetStatus` V3 | `0x65fe3aad` | `0x000334c8` | `0x34c8` |
| `NvAPI_GPU_ThermalPmumonThermChannelsGetSamples` | `0xa7f97cf3` | `0x000135b8` | `0x35b8` |

The installed wrapper's version validators also accept ChannelInfo V1
`0x000101cc` and ChannelStatus V1 `0x0001003c`.  V2/V3 above were actually
invoked and returned `NVAPI_OK`; PMUMON compares exactly against `0x135b8`.

V2 info has a `0x28`-byte header, 32 records of `0x54`, then five primary
channel indices.  V2 status has the same header and 32 signed Q24.8 values.
V3 status has a `0x48`-byte header, three 32-bit request masks at `+0x08`, and
96 records of `0x8c`; each record starts with signed Q24.8 current temperature.

PMUMON V1 has a `0x98`-byte header; sample count is at `+0x10` (50 here).
Each sample is `0x110` bytes beginning at `0x98`; its first `0x50` bytes are
private metadata and the following 32 signed words are Q24.8 temperatures.

Observed primary indices were `[1, 0, 255, 2, 255]` for
`[GPU_AVG, GPU_MAX, BOARD, MEMORY, PWR_SUPPLY]`:

| channel | metadata | current result |
|---:|---|---:|
| 0 | raw class 2, `GPU_MAX`, internal, GPU0 | `0xff00 / 256 = 255.0 C` invalid |
| 1 | raw class 2, `GPU_AVG`, internal, GPU0 | dynamic edge, ~55.5 C |
| 2 | raw class 4, `MEMORY`, internal, GPU0 | 60--68 C, dynamic integer granularity |
| 3..23 | other advertised types | `255.0 C` invalid |

The old reverse-engineered device/provider union is valid only for channel
class 1.  Channel 2 has class 4, so its zero bytes in that union are reserved
and must not be interpreted as `device=0, provider=0`.  Its target metadata is
unambiguous: it is the primary memory channel.  PMUMON returned the same
channel pattern in all 50 history samples; there was no extra hotspot value.

The V3 status layout has three 32-bit request masks (96 possible channel
slots).  The driver advertised only group 0 bits 0--23.  A forced, read-only
single-bit scan of every other slot (`--scan-hidden-v3`) made 72 calls; every
one returned `NVAPI_ERROR` (`-1`) and no data.  Thus groups 1/2 and group 0
bits 24--31 do not provide an unadvertised channel on this driver.

`ThermDeviceGetInfo` returned mask `0x007fffff` (23 devices).  Its V2 layout
has a `0x54`-byte header and 96 records of `0x294`.  Device indices 9 through
21 all have external class `0x82`, and a class-specific word at record `+0x30`
runs from 5 through 17.  This resembles a GPC-TSOSC device collection given
the public VBIOS object model, but the exact `0x82` name and its register
mapping are private; label this **INFERRED**.

A later exact wrapper scan found a corresponding GET interface: QueryInterface
ID `0x9034c146`, RM control `0x20808549`, accepted version `0x000207c4`.
Its inferred name is `NvAPI_GPU_ThermDeviceGetStatus`.  Disassembly verifies
that only the caller's 96-bit object mask flows into the zeroed RM request;
records flow back to the caller.  Five read-only calls with mask
`0x007fffff` returned `NVAPI_OK`, but every class `0x82` status payload for
devices 9..21 was zero and all five `0x7c4` responses were byte-identical.
Thus the entry point exists but supplies no current hotspot on this card.
The GET name and class meaning remain **INFERRED**; the control ID, direction,
zero result, and raw captures in `therm_device_status_idle_20260714/` are
**VERIFIED**.

The apparent neighboring GSP controls `0x20808533/34` are not missing thermal
device status calls.  Their QueryInterface IDs and neighboring GetInfo/Set
entries identify them, **strongly inferred**, as
`NvAPI_GPU_FanPolicyGetStatus` (`0x15b85505`) and
`NvAPI_GPU_FanPolicyGetControl` (`0x0fe87b7f`).  Their wrappers are verified
GET-only and their returned records were static under load.  They are not
junction-temperature getters.

The separate thermal-monitor GETs, query IDs `0xb2c9d666` and `0x4b4bd039`,
map to controls `0x20808543/44`.  The card advertises monitor mask `0x1ff`.
Five status samples showed only object type/flags and two 64-bit running
timestamp/counter-like fields; there was no Q24.8 or Celsius-scale current
temperature.  This is consistent with threshold monitors rather than sensors.
