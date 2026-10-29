# GSP 610.43.03 Therm current-reading evidence

Firmware analyzed: `/lib/firmware/nvidia/610.43.03/gsp_ga10x.bin`.
The RM ELF used below starts at firmware-image offset `0x19f000`, maps its
executable load at VA `0x01000000`, and has SHA-256
`2a3820f063d139233591b45e9a6a606aff97e3d6af4223a8ce97edac649732a6`
when carved as `/tmp/gsp_19f000.elf`.

The Therm dynamic constructor is VA `0x01a0f4bc`.  Its chip index is loaded
with `lhu a2, 0x10(s8)` at `0x01a0f592`; `srli a4,a2,5` selects the HAL group
and `a2 & 31` selects the member.  The inline method table can be reproduced
with:

```
python hotspot_reader/gsp_therm_vtable_dump.py \
  /lib/firmware/nvidia/610.43.03/gsp_ga10x.bin --index 43 --index 65
```

The script locates the embedded RM ELF directly in the firmware image
(`selected ELF offset 0x19f040` for this exact file).  Relevant output:

```
slot      GA102      GB202
+198 0x0187c564 0x01a07ef8
+1c8 0x0187c4c0 0x01a07f58
+268 0x018776bc 0x01a08098
+2a0 0x0187a8b8 0x0187f674
```

## Old current-status method: slot +0x198

GA102/AD102 target `0x0187c564` supports operation 1 as follows (nonessential
error paths omitted):

```
0187c576  mv      s1,a2                 # operation
0187c57e  mv      s3,a3                 # sensor index
0187c580  mv      s5,a4                 # NvTemp *output
0187c582  beq     s1,1,0x187c5ca
0187c5ca  ld      a5,0x268(a1)
0187c5ce  jalr    a5                    # method +0x268 => count 8
0187c5d0  bgeu    s3,a0,error
0187c5d4  lui     a5,1
0187c5d6  add     a0,s2,a5
0187c5da  ld      a4,-0x468(a0)         # BAR0 mapping base
0187c5de  lui     a5,8
0187c5e0  addiw   a5,a5,0x118
0187c5e4  addw    a5,a5,s3
0187c5e8  slli    a5,a5,2
0187c5ea  add     a5,a5,a4
0187c5ec  lw      a5,0(a5)              # BAR0 0x20460 + 4*index
0187c5f0  srli    a4,a5,30
0187c5f4  andi    a4,a4,1               # bit 30: acceptance/ready test here
0187c5f8  slli    a5,a5,47
0187c5fc  srli    a5,a5,50              # bits 16:3
0187c5fe  xor     a5,a5,0x2000
0187c602  addw    a5,a5,-0x2000         # signed 14-bit SFXP9.5
0187c604  slliw   a5,a5,3               # SFXP9.5 -> NvTemp Q24.8
0187c608  sw      a5,0(s5)
```

Thus the register Celsius formula is:

```
accepted_by_this_method = (reg >> 30) & 1
celsius = sign_extend_14((reg >> 3) & 0x3fff) / 32.0
```

This name is deliberately method-local.  Nouveau's older integer path calls
bit 29 valid and bit 30 shadow, so bit 30 must not be presented as a universal
TSENSE validity bit.

GB202 replaces this method with:

```
01a07ef8  addi    sp,sp,-0x10
01a07efa  sd      s0,8(sp)
01a07efc  addi    s0,sp,0x10
01a07efe  ld      s0,8(sp)
01a07f00  addi    a0,zero,0x56          # NV_ERR_NOT_SUPPORTED
01a07f04  addi    sp,sp,0x10
01a07f06  ret
```

This is direct evidence that the old `0x20460 + 4*i` current-status interface
was intentionally removed from the GB202 Therm HAL.

## Generic sensor-reading method: slot +0x1c8

The generic dispatcher at `0x0187b088` first calls method `+0x268`; for sensor
type 1 it calls method `+0x1c8`, types 2 through 8 return zero, and type 9 reads
BAR0 `0x206f8` with the same SFXP9.5 conversion:

```
0187b09e  ld      a5,0x268(a1)
0187b0aa  jalr    a5
0187b0b6  li      a5,1
0187b0b8  bne     s1,a5,other
0187b0bc  ld      a5,0x1c8(s3)
0187b0c6  jalr    a5
...
0187b0e6  li      a5,9
0187b0e8  bne     s1,a5,unsupported
0187b0fc  lw      a5,0x6f8(BAR0+0x20000)
```

GA102/AD102 method `+0x1c8 = 0x0187c4c0` reads BAR0 `0x204a0` and performs the
same conversion.  GB202 method `+0x1c8 = 0x01a07f58` is another 16-byte stub
whose only result is `a0 = 0x56` (`NV_ERR_NOT_SUPPORTED`).

## 107 C threshold is not a current-temperature register

GB202 method `+0x2a0 = 0x0187f674` reads
`0xad0700 + 4*index`, masks `0x7ff8`, and decodes signed SFXP9.5.  On the tested
card, index 6 (`0xad0718`) decodes to 107 C.  Its caller at `0x01870838`
enumerates an enabled-threshold mask during initialization and computes a
minimum limit.  It does not compare this register with a live software-read
temperature.  The evidence therefore identifies `0xad0718` as a limit, not a
hotspot reading; an autonomous hardware comparator or another firmware
component remains the likely protection path.

## Private ThermDevice controls stop before a live getter

The installed `/usr/lib/libnvidia-api.so.1` maps private NvAPI query ID
`0x6ff0350c` to RM GET control `0x20808536` (`ThermDeviceGetInfo`).  A direct,
read-only RM GET succeeds with parameter size `0x63d0`.  Its returned device
mask is `0x007fffff`; records begin at `+0x34` with stride `0x64`.

For devices 9 through 21, the internal class tag at record `+0x00` is `0x16`.
The library's class mapper at x86-64 VA `0x0001f170` maps that tag to external
class `0x82`.  The class-`0x82` serializer at VA `0x000216cf` only reads the
internal subtype byte at record `+0x14` and maps it to the public record's
class-specific word at `+0x30`; it never reads or converts a temperature.
The 13 returned subtype values are internal `[9..20, 0]`, mapped to external
`[5..17]`.  The byte-level mapping above is **verified**.  The semantic name
GPC TSOSC is **strongly inferred** from the published VBIOS class value
`GPU_GPC_TSOSC = 0x02`, the adjacent `0x81`/`0x83` class numbering, and the
13-object collection; no private NVIDIA symbol naming `0x82` is present.
In either case, the record does not expose a sample or register address.

Private NvAPI query ID `0x41716ac2` maps to read-only RM control
`0x20808537`.  It accepts NvAPI version/size `0x0001deb8` and returns a
ThermDevice PMUMON ring: a `0x98`-byte header followed by up to 50 samples of
stride `0x990`.  Per-device summary records start at sample `+0x50` with
stride `0x48`.  The wrapper copies each record's first word, then converts
internal Q16.16 at record `+0x10` to an integer percentage by multiplying by
100; these fields are not degrees Celsius.

The only selectable GET mode is the input word at NvAPI buffer `+0x18`
(internal control payload `+0x14`): mode 0 returned 50 history samples and
mode 1 returned one latest sample.  Both modes populated only device records
0 and 1; GPC-TSOSC device records 9 through 21 remained zero.  There is no
input device mask or alternate GET mode that requests their current values.
The GSP handler for this control is VA `0x0186bb2c` and feeds a generic ring
buffer snapshot path, not a per-device current-temperature virtual method.

## Controls 0x20808533/34 are static fan-policy GETs, not hotspot

The final two previously-unclassified Thermal controls were also audited.
In the installed `libnvidia-api.so.1` QueryInterface table at VA `0x000c12a0`,
entries 433 and 434 are:

```
query ID     wrapper VA   accepted public version(s)   RM control
0x15b85505   0x0002a5b0  0x000108a8                  0x20808533
0x0fe87b7f   0x0002a760  0x00010eac, 0x000214ac      0x20808534
```

No installed NVIDIA header or binary symbol supplies names, but the IDs are
the long-lived `NvAPI_GPU_FanPolicyGetStatus` and
`NvAPI_GPU_FanPolicyGetControl` IDs.  This identification is **strongly
inferred**, not symbol-verified: they sit between the corresponding fan-policy
GetInfo (`0x76a38d54`) and SetControl (`0x2b2a2a45`) entries in the installed
QueryInterface table, and their record shape is a fan-policy table.  The GSP
handler selecting a Therm BoardObj group does not make it a temperature-sensor
getter; fan policy is implemented in the same subsystem.
The first wrapper copies the caller's object mask from public `+0x04` to the
RM envelope at `+0x14`; the second copies the mask to `+0x1c` and a one-bit
option from public `+0x08` to `+0x20`.  Both paths only submit their respective
GET and copy returned records back to the caller.

The GSP command descriptors and wrapper control flow verify the GET
classification:

```
descriptor VA  command       params  handler       flags
0x01c1b100     0x20808533    0x28c   0x012fc198    0x48
0x01c1b120     0x20808534    0x614   0x018702a4    0x48
```

Handler `0x018702a4` obtains a group callback through object offsets
`+0x158`, `+0xe0`, `+0x1fa8`, and the Therm group slot `+0x420`, then
tail-calls the generic
BoardObj status traversal at `0x01bc9f08`.  That traversal eventually invokes
the selected object's status method through its callback at `+0x08`.  This is
a read/status walk; it is not a register or policy SET path.

The reproducible probe is `fan_policy_get_probe.py`.  On this GB202 it
found individually accepted object bits 0, 1, 4 and 5 (`mask=0x00000033`).
The public info records start at `+0x28`, stride `0x44`; V2 status records
start at `+0x2c`, stride `0xa4`.  Every valid status record has the same pair
`record+0x24 = 0x00000042` and `record+0x28 = 0x0000ffbe` (low signed halves
are +66 and -66), plus static table-like values.  Five one-second reads while
the GPU was at 98% utilization, about 268 W and 57 C edge were byte-identical:

```
SHA-256 e898349dfdfd65169b8f3d262729cea02c199609d8d47209de1d9a01a036216e
```

Thus these controls are **verified GET paths** and their returned data is
**verified static during load**.  Their private API names are **strongly
inferred** as fan-policy status/control.  They do not contain a changing
temperature or a hotspot value.

Consequently, for GB202 the live GPC-TSOSC getter VA, BAR0 offset, and decode
formula remain **unknown**: neither private GET control reaches such a getter,
and the legacy top-level Therm current methods that did reveal an MMIO formula
are the explicit `NV_ERR_NOT_SUPPORTED` stubs documented above.
