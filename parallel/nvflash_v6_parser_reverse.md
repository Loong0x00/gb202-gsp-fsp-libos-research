# `nvflash` 5.877.0 Falcon descriptor classifier: bounded static reverse

Date: 2026-07-22 (Asia/Singapore)

## Scope and safety boundary

This report is limited to static inspection of:

```text
/home/user/rt_5090_project/vbios_diff/hpe_static_tools/nvflash
SHA256 d1aee0b0309475826b15bb8c31624d11a80e0e6d568bea6144be7e213df44780
ELF64 ET_EXEC, stripped
embedded version string: NVIDIA Firmware Update Utility (Version 5.877.0)
```

The file was **not executed**.  No GPU, driver node, MMIO/BAR/debugfs, reset,
firmware loader, MODS, or VBIOS write was accessed.  The work used bounded
`objdump` windows, direct table/string reads, and targeted executable-byte /
instruction-shape searches.  It did not run a whole-program decompiler.

## Bottom line

1. **FACT:** The classifier at VA `0x7dde66` maps internal values as follows:
   `0=unsupported/invalid`, `1=NVFLASH V1`, `2=NVFLASH V2`, `3=GFW V1`,
   `4=GFW V2`, `5=GFW V3`, `6=GFW V4`, and `7=a special raw NVFW-magic
   sentinel`.  Value 7 is not another documented Falcon descriptor style and
   the printer renders it as unsupported.
2. **FACT:** Input beginning `0d 06 50 00` (`0x0050060d`) does **not** take an
   explicit v6 case and does **not** take the unsupported case.  It falls into
   the legacy catch-all at `0x7ddead`, is assigned enum `3`, and is printed as
   `FALCON_UCODE_DESCRIPTOR_GFW_STYLE_V1`.
3. **INFERENCE (strong):** This is a legacy default/misclassification, not v6
   body support.  The `0x50` size word is never checked on this route, and the
   code projects old GFW-V1 offsets onto the v6 bytes.
4. **FACT:** This parser cannot reliably name any v6 body field at `+0x04` or
   later.  Its old-layout reads are evidence only of what 5.877.0 *mistakenly
   does with those bytes*, not evidence of the v6 schema.
5. **FACT (bounded negative):** No second parser that explicitly recognizes
   version `6` together with descriptor size `0x50` was found in this binary.
   There are no V5/V6 style strings and no executable immediate for
   `0x0050060d` or the combined version/size value.  **UNKNOWN:** A nameless
   generic/opaque-copy path could still carry such an object without parsing
   its body; the bounded search cannot prove that no such path exists.

## Address convention

The executable LOAD segment maps file offset `0` at VA `0x400000`; therefore
the principal code addresses below have file offset `VA - 0x400000`.

| Object | VA | File offset |
|---|---:|---:|
| classifier | `0x7dde66` | `0x3dde66` |
| descriptor printer | `0x7df574` | `0x3df574` |
| printer jump table | `0xd3ac38` | `0x93ac38` |
| relevant class vtable | `0xd3ad70` | `0x93ad70` |

**FACT:** Vtable `0xd3ad70 + 0x38` is `0x7dde66` and
`0xd3ad70 + 0x48` is `0x7df574`.  Constructors at `0x7de9f6` and `0x7dec37`
directly call `0x7dde66`, then store its return value at object offset `+0x40`.
This ties the classifier, enum field, and printer together without relying on
stripped symbol names.

## 1. Exact enum/style mapping

### 1.1 Printer proof

At `0x7df71f`, the printer compares the object enum against 6.  Values above
6 go directly to `0x7df8d3`, which emits
`FALCON_UCODE_DESCRIPTOR_UNSUPPORTED_VERSION`.  Values 0 through 6 use the
seven-entry absolute jump table at `0xd3ac38`:

| Enum | Jump target | Emitted style text | Classification |
|---:|---:|---|---|
| `0` | `0x7df8d3` | `FALCON_UCODE_DESCRIPTOR_UNSUPPORTED_VERSION` | **FACT** |
| `1` | `0x7df735` | `FALCON_UCODE_DESCRIPTOR_NVFLASH_STYLE_V1` | **FACT** |
| `2` | `0x7df806` | `FALCON_UCODE_DESCRIPTOR_NVFLASH_STYLE_V2` | **FACT** |
| `3` | `0x7df82f` | `FALCON_UCODE_DESCRIPTOR_GFW_STYLE_V1` | **FACT** |
| `4` | `0x7df858` | `FALCON_UCODE_DESCRIPTOR_GFW_STYLE_V2` | **FACT** |
| `5` | `0x7df881` | `FALCON_UCODE_DESCRIPTOR_GFW_STYLE_V3` | **FACT** |
| `6` | `0x7df8aa` | `UCODE_DESCRIPTOR_GFW_STYLE_V4` | **FACT** |
| `7` | pre-switch `>6` route | unsupported-version text | **FACT** |

The style strings occupy VA `0xd3a740..0xd3a843`; the V4 text begins at
`0xd3a98d`.  Each exact style-string address has one immediate code reference,
all in this printer.

### 1.2 Classifier proof

The return/set sites in `0x7dde66..0x7de25b` agree with the printer table:

| Enum | Classifier site | Recognition summary |
|---:|---:|---|
| `0` | e.g. `0x7ddf3f`, `0x7ddf68`, `0x7ddfa2` | structural/length validation failed |
| `1` | `0x7de086` | leading dword 1 plus old NVFLASH-layout checks |
| `2` | `0x7de016` | leading dword 2 plus old NVFLASH-layout checks |
| `3` | `0x7ddead` | catch-all after all recognized signatures fail |
| `4` | `0x7de168` | flags-version form, version byte 2, size `0x3c`, further consistency checks |
| `5` | `0x7de0d4` | byte `+1 == 3` |
| `6` | `0x7ddfa8` | byte `+1 == 4` |
| `7` | `0x7de1ec` | leading dword `0x5746564e` (`"NVFW"`) |

**FACT:** Enum 7 zeroes the normalized code/data fields at
`0x7de1ec..0x7de256`; helper `0x7de25e` also special-cases 7 and skips DMAP
searching.  Therefore the defensible label is “raw `NVFW` magic sentinel,”
not “GFW V5/V6.”

## 2. Exact `0x0050060d` control flow

Assume the classifier input buffer begins with:

```text
offset  bytes         interpreted scalar
+0x00   0d 06 50 00   little-endian dword 0x0050060d
```

The executed decisions are mechanically determined:

| VA | Operation | Result for `0d 06 50 00` |
|---:|---|---|
| `0x7dde6a` | load dword `[rdx]` | `eax=0x0050060d` |
| `0x7dde6c` | compare with 1 | false |
| `0x7dde75` | compare with 2 | false |
| `0x7dde7e` | load byte `[rdx+1]` | `cl=6` |
| `0x7dde82` | compare version with 4 | false |
| `0x7dde8b` | compare version with 3 | false |
| `0x7dde94` | test flags byte bit 0 | set; continue to version-2 test |
| `0x7dde99` | compare version with 2 | false |
| `0x7ddea2` | compare dword with `"NVFW"` | false |
| `0x7ddead` | set object enum to 3 | taken |
| `0x7ddf16` | return 3 | `GFW_STYLE_V1` |

**FACT:** The `word [rdx+2] == 0x3c` check at `0x7ddf6e` belongs only to the
version-2 route.  Version 6 never reaches it.  There is no check for
`word [rdx+2] == 0x50` on the v6 route—or anywhere in this classifier.

**FACT:** The parser therefore does not explicitly support v6, but it also
does not reject it as unsupported.  It silently assigns the old GFW-V1 enum.

**INFERENCE (strong):** “Misclassified as GFW V1” is more accurate than
“supported as GFW V1.”  No v6 predicate selected the branch, and the branch is
the residual destination for every non-NVFW byte pattern not recognized above.

## 3. Why this path cannot name v6 `+0x04..` fields

The enum-3 block at `0x7ddead..0x7ddf1b` performs these legacy projections:

| Raw input offset | Use in the enum-3 block |
|---:|---|
| `+0x08` | copied to normalized object `+0x90` |
| `+0x10` | copied to normalized object `+0x54` |
| `+0x14` | copied to normalized IMEM-size slot `+0x50/+0x58` |
| `+0x18` | copied to normalized object `+0x5c` |
| `+0x1c`, `+0x20` | used as two legacy code/load extents |
| `+0x24` | added to fixed raw base `+0x30` to form a data pointer |
| `+0x28` | copied to normalized object `+0x80` |
| `+0x2c` | copied to normalized DMEM-size slot `+0x78/+0x7c` |
| `+0x30` | treated as the start of image/code bytes |

**FACT:** Raw offsets `+0x04` and `+0x0c` are not read at all by this branch.
The header size `0x50` is ignored.  The block merely applies an older fixed
layout beginning at raw `+0x30`.

There is also a concrete incompatibility with the saved `FSP_RUN` object:

- the saved v6 descriptor has raw dword `+0x2c = 0x50534600`, whose bytes are
  `00 46 53 50` (the beginning of the visible `FSP_RUN` sequence);
- `0x7ddece` copies this value into normalized object slot `+0x78`;
- printer `0x7df64e` prints object `+0x78` after the label
  `"  DMEM Size = 0x"` at VA `0xd2b6b2`.

**FACT:** Thus this route would report the ASCII prefix as a gigantic legacy
“DMEM size” (`0x50534600`).  This is direct evidence that its generated labels
do not describe the v6 body.

**Conclusion:** Only the shared four-byte header may retain the separately
established generic interpretation (`flags`, version byte 6, size word
`0x50`).  From this binary's parser, every v6 body name at `+0x04..+0x4f`
remains **UNKNOWN**.  The old-layout reads above must not be promoted to v6
field definitions.

## 4. Search for another explicit v6/0x50 Falcon parser

The following bounded checks were performed:

- **FACT:** Exact strings contain styles only for NVFLASH V1/V2 and GFW
  V1/V2/V3/V4, plus unsupported.  There is no
  `FALCON_UCODE_DESCRIPTOR_*_V5`, `_V6`, or equivalent v6 label.
- **FACT:** The only `UCODE_DESCRIPTOR_GFW_STYLE_V4` address reference leads
  back to the printer at `0x7df8aa`; all six longer Falcon descriptor style
  strings likewise have exactly one immediate xref in that same switch.
- **FACT:** No executable instruction contains immediate `0x0050060d` or
  `0x00500006`.  The sole raw byte occurrence `0d 06 50 00` in the ELF is at
  file offset `0xb4dac1`, inside `.gcc_except_table`, not executable code.
- **FACT:** Targeted scans found no direct executable comparison of a header
  version byte at displacement `+1` with 6 and no comparison of a header size
  word at displacement `+2` with `0x50`.  Nearby structural false positives
  inspected around `0xbd77xx`/`0xbd93xx` are compression bit/Huffman tables,
  not Falcon descriptor logic.
- **FACT:** The one identified Falcon descriptor class vtable is
  `0xd3ad70`; its classifier and printer are the pair analyzed above.  Its
  constructor call sites both invoke `0x7dde66`.

**Bounded conclusion:** No second **explicitly v6-aware Falcon body parser**
was found in nvflash 5.877.0.  The evidence is strong enough to reject the idea
that the already identified classifier secretly has a v6/`0x50` case.

**UNKNOWN:** This does not prove a universal absence of all possible handling.
Code may locate/copy an `NVFW` container or opaque signed object without
decoding its Falcon body; indirect dispatch and nameless generic blob paths are
not equivalent to a v6 descriptor parser.  No field names or v6 layout should
be inferred from such hypothetical transport behavior.

## Final answer to the four requested questions

1. Enum mapping is conclusively `0 unsupported`, `1 NVFLASH V1`, `2 NVFLASH
   V2`, `3 GFW V1`, `4 GFW V2`, `5 GFW V3`, `6 GFW V4`; `7` is a special raw
   `NVFW`-magic sentinel rendered unsupported.
2. `0x0050060d` goes to `0x7ddead`, returns enum 3, and is printed as GFW V1.
   It is not explicitly supported as v6 and is not cleanly rejected.
3. No v6 body field after `+0x03` can be reliably named from this path.  The
   GFW-V1 projections are demonstrably nonsensical for `FSP_RUN`.
4. No second explicit version-6/size-`0x50` Falcon parser was found under the
   bounded static checks.  A generic opaque carrier remains possible but would
   not supply v6 field semantics.
