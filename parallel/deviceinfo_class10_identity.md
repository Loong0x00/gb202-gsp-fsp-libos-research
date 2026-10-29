# PTOP DeviceInfo2 class `0x10` identity audit

Scope: local MODS 570.151 ELF
`mods_audit/static/extracted_inner/mods` (SHA-256
`c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf`),
the existing offline GB202 RegHal decoder, and the locally installed NVIDIA
610.43.03 published sources.  This was a bounded, offline audit.  MODS was not
executed and no device interface was opened.

## Result

On the embedded GB202 (`chip=0xff2`) RegHal table, MODS helper `0xdd2550`
mechanically maps:

```text
PTOP DeviceInfo2 raw DEV_TYPE_ENUM 0x22 -> MODS internal class 0x10
```

The complete GB202-specific map has 51 supported entries.  Internal classes
`0x33` and `0x34` are present as conditional construction cases in the helper,
but their two RegHal enum IDs have no GB202 rows and therefore are not inserted.
An unrecognized raw value is diagnosed and returns internal class `0x35`, the
helper's invalid/sentinel result.

For the fuse-writer path, class `0x10` is **definitely the device class used to
resolve the fuse PRI aperture**:

```text
logical domain 5
  -> ordinary fuse accessor: class 0x10, instance 0, selector 0x10ef4000
  -> class vector empty:
       fixed selector instance 0 = 0x820000
  -> class vector nonempty, exact instance 0 present:
       return that PTOP record.devicePriBase
  -> class vector nonempty, exact instance 0 absent:
       unsafe read from vector.end()+0x18; no error and no fallback
```

NVIDIA's local published source explicitly names `0x820000` as
`NV_FUSE0_PRI_BASE`, and the host implementation describes its getter as
"Get FUSE base address".  Thus this is not merely a numeric coincidence.

The remaining naming distinction is important:

- **FACT:** GB202 raw numeric type is `0x22`; MODS internal numeric class is
  `0x10`; that class is consumed as the fuse-aperture class in this path.
- **Strong INFERENCE:** the semantic internal device-type name is `FUSE`.
- **UNKNOWN:** the exact C++ enumerator token used in MODS, and the exact public
  `NV_PTOP...DEV_TYPE_ENUM_FUSE` macro spelling.  The locally published
  Blackwell headers do not publish a symbolic name for raw `0x22`, so this
  report does not invent one.

## FACT: what `0xdd2550` actually builds

The helper takes the raw PTOP type in `ESI`, stores it in `EBX`, and obtains a
chip-specific RegHal object.  It then conditionally builds a cached vector of
8-byte pairs:

```text
pair +0x0 = chip-specific raw DEV_TYPE_ENUM constant
pair +0x4 = MODS internal class
```

Each construction block first asks whether one `0x42adcbXX` constant is
supported for the chip.  When it is, the block reads that constant and appends
it together with a literal internal-class value.  For the target block:

```text
0xdd3748  mov  esi,0x42adcb0a
0xdd374d  call RegHal_constant_getter
0xdd3758  mov  dword ptr [rsp+0xc],0x10
0xdd3764  call append_pair
```

The existing offline decoder gives the GB202 value of that exact ID:

```text
RegHal ID 0x42adcb0a
  row 17559
  kind=constant-setter
  constant=0x00000022
```

The lookup tail at `0xdd2d51..0xdd2e66` scans the cached 8-byte records, compares
the caller's raw value with pair `+0x0`, and returns pair `+0x4`.  If there is no
match, `0xdd2dec` prints `Unknown device type found in PTOP - %u` and
`0xdd2dff` returns `0x35`.

## FACT: complete GB202 raw-type to internal-class map

This table combines only two mechanical observations:

1. the literal class paired with each RegHal ID in bounded helper window
   `0xdd2e70..0xdd3859`; and
2. the constant value decoded for that ID from the embedded GB202 table.

It is sorted by PTOP raw type, matching the helper's input-to-output direction.

| PTOP raw type | MODS class | RegHal enum ID | Published name when locally numeric |
|---:|---:|---:|---|
| `0x00` | `0x00` | `0x42adcb0d` | — |
| `0x0d` | `0x05` | `0x42adcb2a` | — |
| `0x0e` | `0x02` | `0x42adcb1d` | — |
| `0x10` | `0x01` | `0x42adcb1c` | — |
| `0x12` | `0x08` | `0x42adcb14` | — |
| `0x13` | `0x06` | `0x42adcb17` | `LCE` |
| `0x14` | `0x07` | `0x42adcb0e` | — |
| `0x15` | `0x03` | `0x42adcb1e` | — |
| `0x16` | `0x04` | `0x42adcb21` | — |
| `0x17` | `0x09` | `0x42adcb08` | — |
| `0x18` | `0x0b` | `0x42adcb11` | `HSHUB` |
| `0x19` | `0x0a` | `0x42adcb01` | — |
| `0x1a` | `0x0c` | `0x42adcb09` | — |
| `0x1b` | `0x11` | `0x42adcb07` | — |
| `0x1c` | `0x1c` | `0x42adcb20` | — |
| `0x1d` | `0x1b` | `0x42adcb1f` | — |
| `0x1e` | `0x0d` | `0x42adcb0c` | — |
| `0x1f` | `0x28` | `0x42adcb31` | `TMR` |
| `0x20` | `0x17` | `0x42adcb12` | — |
| `0x21` | `0x13` | `0x42adcb04` | — |
| **`0x22`** | **`0x10`** | **`0x42adcb0a`** | unpublished; fuse semantic closed below |
| `0x23` | `0x20` | `0x42adcb25` | — |
| `0x24` | `0x26` | `0x42adcb2f` | — |
| `0x25` | `0x27` | `0x42adcb30` | — |
| `0x26` | `0x22` | `0x42adcb27` | — |
| `0x27` | `0x21` | `0x42adcb26` | — |
| `0x28` | `0x0f` | `0x42adcb2b` | — |
| `0x29` | `0x12` | `0x42adcb0b` | — |
| `0x2a` | `0x0e` | `0x42adcb29` | — |
| `0x2b` | `0x14` | `0x42adcb00` | — |
| `0x2c` | `0x1a` | `0x42adcb16` | — |
| `0x2d` | `0x29` | `0x42adcb34` | — |
| `0x2e` | `0x1e` | `0x42adcb23` | — |
| `0x2f` | `0x15` | `0x42adcb02` | — |
| `0x30` | `0x24` | `0x42adcb2d` | — |
| `0x31` | `0x25` | `0x42adcb2e` | — |
| `0x32` | `0x1f` | `0x42adcb24` | — |
| `0x33` | `0x1d` | `0x42adcb22` | `PBUS` |
| `0x34` | `0x23` | `0x42adcb28` | — |
| `0x35` | `0x18` | `0x42adcb13` | `HUBMMU` |
| `0x36` | `0x19` | `0x42adcb15` | — |
| `0x37` | `0x16` | `0x42adcb05` | — |
| `0x38` | `0x2a` | `0x42adcb10` | — |
| `0x39` | `0x2b` | `0x42adcb0f` | — |
| `0x3a` | `0x2c` | `0x42adcb1a` | — |
| `0x3b` | `0x2d` | `0x42adcb1b` | — |
| `0x3c` | `0x2e` | `0x42adcb32` | — |
| `0x3d` | `0x2f` | `0x42adcb33` | — |
| `0x3e` | `0x31` | `0x42adcb2c` | — |
| `0x3f` | `0x30` | `0x42adcb06` | — |
| `0x40` | `0x32` | `0x42adcb03` | — |

The locally published names in the last column are deliberately sparse:

- `blackwell/gb202/dev_top_zb.h` publishes `LCE = 0x13`;
- `blackwell/gb100/dev_top.h` publishes `HSHUB = 0x18`;
- `blackwell/gb100/dev_top_zb.h` publishes `TMR = 0x1f`, `PBUS = 0x33`, and
  `HUBMMU = 0x35`.

These named rows independently validate that `0xdd2550` is translating the
published PTOP DeviceInfo2 type namespace.  They do not supply a public name
for raw `0x22`.

### Conditional classes absent on GB202

The helper has two more source cases:

```text
RegHal ID 0x42adcb19 -> internal class 0x33
RegHal ID 0x42adcb18 -> internal class 0x34
```

Both decode to zero rows in the GB202 table.  Because the helper tests support
before appending, neither pair exists in the GB202 runtime cache.  They are
therefore source-level possibilities, not entries in the GB202 map above.

## FACT: class `0x10` is the fuse-aperture selector in the audited path

The GB202 domain resolver's logical-domain-5 branch is:

```text
0x125c1f6  mov  esi_input, ecx       # caller instance -> lookup instance
0x125c1f8  mov  0x10ef4000, edx      # fixed-selector RegHal ID
0x125c1fd  mov  0x10, esi            # DeviceInfo2 internal class
             -> 0x1252200
```

`0x1252200` asks whether the lazily parsed DeviceInfo2 vector for class `0x10`
is populated.  Its exact behavior has three branches:

1. If the vector is empty, it resolves `0x10ef4000` with the same requested
   instance.
2. If the vector is nonempty and the exact requested instance exists, it
   returns that record's `devicePriBase`.
3. If the vector is nonempty but the exact requested instance is absent, the
   selector fallback has already been discarded.  The lookup reads the dword
   at `vector.end()+0x18` and returns it as a base, with no diagnostic or status
   channel.  This is an unsafe out-of-range no-match path, not a valid
   relocation or fallback.

The embedded GB202 selector rows used only by the empty-vector branch are:

```text
instance 0 -> 0x00820000
instance 1 -> 0x00bf0000
```

The ordinary GB20x fuse accessor constructs instance 0.  NVIDIA's local
published source independently identifies its fallback address:

```c
// published/blackwell/gb100/hwproject.h
#define NV_FUSE0_PRI_BASE 0x820000

// src/kernel/gpu/arch/hopper/kern_gpu_gh100.c
/*! @brief Get FUSE base address ... @return NV_FUSE0_PRI_BASE */
return NV_FUSE0_PRI_BASE;
```

Finally, the caller is `GB20xFuseAccessor::ProgramSwFusePlan`; it passes logical
domain 5 before the returned base is added to the domain-relative fuse-plan
offset.  Therefore, for this path, class `0x10` is not merely correlated with
fuse code: it is the selector that supplies the base of the fuse PRI aperture.
For any offline safety model, a nonempty class-`0x10` vector without exact
instance 0 must be rejected rather than treated as a reason to use `0x820000`.

## INFERENCE: semantic and symbolic names

It is safe to call the **semantic device type** `FUSE`: all four independent
pieces agree—fuse-accessor caller, logical domain 5, fallback selector, and the
published `NV_FUSE0_PRI_BASE` name.

It is not safe to claim that the stripped MODS C++ source spelled its internal
enumerator exactly `DEVICE_TYPE_FUSE`, `HW_DEVICE_FUSE`, or another guessed
token.  Likewise, NVIDIA's naming convention makes a public macro such as
`NV_PTOP_ZB_DEVICE_INFO_DEV_TYPE_ENUM_FUSE` plausible, but the local 610
published headers omit raw `0x22`, so that precise spelling remains an
inference rather than a recovered fact.

## UNKNOWN

- Whether this RTX 5090's live DeviceInfo2 table contains a raw-type-`0x22`,
  instance-0 row.  No live table was read.
- If present, the row's actual `devicePriBase`; `0x820000` is the statically
  proved ordinary fallback and the expected primary fuse base, not a captured
  runtime row.
- Whether the hidden physical producer guarantees that a nonempty normal
  class-`0x10` vector contains instance 0.  The MODS no-match behavior does not
  enforce that invariant safely.
- The exact proprietary MODS C++ enumerator token for internal class `0x10`.
- The exact public symbolic macro token NVIDIA would assign to raw `0x22`;
  local 610 headers publish the numeric field and several peer values, but not
  this name/value pair.
- Whether raw type `0x22` has the same meaning in every older or future chip
  table.  The numeric conclusion here is GB202-specific.

## Reproduction notes

The bounded binary windows were:

```text
objdump -d -M intel --start-address=0xdd2550  --stop-address=0xdd2e70 mods
objdump -d -M intel --start-address=0xdd2e70  --stop-address=0xdd3860 mods
objdump -d -M intel --start-address=0xdd2230  --stop-address=0xdd2367 mods
objdump -d -M intel --start-address=0x12521f0 --stop-address=0x12522c0 mods
```

The GB202 constant was recovered without executing MODS:

```text
python3 gb202_reghal_offline.py --id 0x42adcb0a --include-metadata
```

A bounded batch invocation decoded the remaining `0x42adcbXX` IDs and verified
that the 51 supported raw constants are unique.  Here `mods` abbreviates
`mods_audit/static/extracted_inner/mods`.  The public-source cross-checks came
only from `/usr/src/nvidia-610.43.03`.
