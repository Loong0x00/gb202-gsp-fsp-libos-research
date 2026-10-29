# `prc_knob_en` Debug Token mask generation audit

Date: 2026-08-13

Scope: static/read-only comparison. No updater, token install, MODS, MMIO, reset,
or GPU write was executed.

## Result

The HPE and Dell Blackwell update tools do **not** place `prc_knob_en` under
`FeatureUnlock`. Both version-5.877 binaries place it under GPU token type
`0x04`, which their own type-name dispatcher calls `hw_unlock`:

```text
old updater HardwareUnlock subtype 0x00020000 -> prc_knob_en
current nsmd  HardwareUnlock subtype 0x00001000 -> PrcKnobEn
```

Thus the parent token family agrees (`HardwareUnlock`), while the subtype mask
does not. The public evidence does not define a conversion between these two
mask layouts; code that prepares or interprets a token must use the ABI/version
associated with that token and consumer.

## 1. Static samples

```text
HPE nvflash
path: /home/user/rt_5090_project/vbios_diff/hpe_static_tools/nvflash
banner: NVIDIA Firmware Update Utility (Version 5.877.0)
SHA-256: d1aee0b0309475826b15bb8c31624d11a80e0e6d568bea6144be7e213df44780

Dell RTX PRO 6000 updater
path: /home/user/rt_5090_project/vbios_diff/dell_8d_payload/RTXPRO6000_98.02.8D.00.01_FW_upgrade.bin
banner/version strings: NVIDIA Firmware Update Utility / 5.877.0
SHA-256: 6e1ccf97addee26c3c836cc4c87b4fdd0151cf78edb4df921b35338479e6ab61
```

Both are ELF64 x86-64 images with `.text` at VA `0x405000`, file offset
`0x5000`. Their relevant code has the same virtual addresses; `.rodata` is
shifted by `0x90000` in the Dell image.

## 2. Type/subtype dispatch closure

Function `0x52c34f` maps GPU token type identifiers:

```text
0x01 -> debug_fw_unlock
0x02 -> jtag_unlock
0x04 -> hw_unlock
0x08 -> runtime_debug_unlock
0x10 -> feature_unlock
```

Function `0x52c381(type, subtype)` uses `type` as a jump-table index. In both
images, case `4` enters the branch at `0x52c53a`; case `16` is a separate branch
and does not enter that code.

The case-4 branch contains:

```text
0x52c566  cmp esi, 0x00020000
0x52c56c  je  0x52c6bf
0x52c6bf  mov eax, <address of "prc_knob_en">
0x52c6c4  ret
```

The string is at:

```text
HPE:  file offset 0x008ea5c7, VA 0x00cea5c7
Dell: file offset 0x008f35c7, VA 0x00cf35c7
```

Caller `0x440959..0x440975` loads a subtype dword into `esi`, loads the token
type from structure offset `+0x20` into `edi`, and calls `0x52c381`. The caller
slice is byte-identical in both binaries (SHA-256
`4d7e53284f83354918e9f0b907b3faa8481fd891df0d0428e55522282c6afd4d`).
This makes the classification independent of string proximity or naming
guesswork: old `0x20000 -> prc_knob_en` is a HardwareUnlock subtype mapping.

## 3. Old and current common-name masks

NVIDIA current source:

- <https://github.com/NVIDIA/nsmd/blob/develop/nsmd/nsmDebugToken/debugTokenUtils.cpp>
- audited local file SHA-256
  `ee06baf4181912188f9de57241a7feba4f1d056a8826fc2da6844d06bf83a5fc`

Both tables use GPU token type `4` for HardwareUnlock, but many common names
move after the first five entries:

| HardwareUnlock subtype | updater 5.877 | current `nsmd` |
|---|---:|---:|
| `MemQual` | `0x000001` | `0x000001` |
| `GlobalFunctionalDebug` | `0x000002` | `0x000002` |
| `SpeedoKappaIddq` | `0x000004` | `0x000004` |
| `ECCEnable` | `0x000008` | `0x000008` |
| `ReducedGlobalFunctionalDebug` | `0x000010` | `0x000010` |
| `ECCUnlock` | `0x000100` | `0x000020` |
| `Bar0DecouplerUnlock` | `0x000400` | `0x000040` |
| `I2ccAccess` | `0x000800` | `0x000080` |
| `ECCPoisonDisable` | `0x001000` | `0x000100` |
| `NvlinkGlobalHulk` | `0x002000` | `0x000200` |
| `LowerRomProtection` | `0x008000` | `0x000400` |
| `RecreateInforomRW` | `0x010000` | `0x000800` |
| `PrcKnobEn` | `0x020000` | `0x001000` |
| `ArchFunctionalTests` | `0x000080` | `0x004000` |
| `SsgDebug` | `0x000020` | `0x008000` |

This is a layout revision, not a single isolated PRC-bit discrepancy. The old
table also contains names absent from current `nsmd`, while current `nsmd`
contains later additions such as `Nuke`, `CxlDebug`, `VideDebug`,
`PxucGlobalHulk`, `TargetMaskUnlock`, and `I2cVregUnlock`.

## 4. Evidence boundary

**PROVED**

- Both inspected 5.877 update tools decode `prc_knob_en` as subtype `0x20000`
  of GPU HardwareUnlock token type `4`.
- Current `nsmd` decodes `PrcKnobEn` as subtype `0x1000` of the same named token
  type.
- HardwareUnlock is a distinct parent type from HULK license objects and from
  FeatureUnlock.

**NOT PROVED**

- that old and current masks are carried in the same wire/TLV representation;
- that either mask alone enables PRC object `0x1d`, MODS task 2, register
  `0x8200f8`, or L2 floorsweeping;
- that a token accepted by one generation/device is accepted by the other;
- that `PRC_ERROR_PERSISTENCE_NOT_SUPPORTED` means a token was missing.

The mapping strengthens `PrcKnobEn` as a concrete non-HULK authorization
candidate. It does not make it a target-compatible authorization sample or
prove sufficiency for GB202 L2 changes.
