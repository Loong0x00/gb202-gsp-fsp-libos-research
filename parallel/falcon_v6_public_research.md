# Falcon-v6 / `FSP_RUN` public-source audit

Date: 2026-07-22 (Asia/Singapore)

## Scope and safety boundary

This audit used only saved files, public source/documentation, Git history, and
repository metadata.  It did **not** access a GPU, execute firmware, run MODS,
read MMIO/BAR/debugfs, reset/rebind a device, or modify a VBIOS.

The requested questions were:

1. What is publicly defined for a Falcon ucode table entry and descriptor v6?
2. Is `flags.bit2`, `app=0x24`, `target=0x0f`, or `FSP_RUN` publicly named?
3. Did NVIDIA's public definition change between releases?
4. Does any public Falcon/v6 source define AES-GCM, a 12-byte IV, or a
   16-byte authentication tag for the 28-byte opaque descriptor tail?

## Bottom line

- **FACT:** NVIDIA publishes the Falcon table-entry layout
  `ApplicationID:u8, TargetID:u8, DescPtr:u32` and a generic four-byte `vDesc`
  header layout.  The latter assigns bit 2 the name `ENCRYPTED`, bits 15:8 to
  descriptor version, and bits 31:16 to descriptor size.
- **FACT:** For the three locally unique GB202 objects, raw word 0 is
  `0x0050060d`: low byte `0x0d`, version `6`, descriptor size `0x50`.  Raw bit 2
  is set.  The same low byte also sets **bit 3**, while the public header calls
  bits 7:3 `RESERVED`.  Thus the public header is demonstrably incomplete or
  stale for this v6 value; it is not a complete v6 specification.
- **FACT:** NVIDIA OpenRM 610.43.03 defines descriptor bodies only for v2 and
  v3 and rejects/skips other versions.  It has constants only through v4.  It
  contains no v5/v6 body, decryption implementation, or mapping for
  `app=0x24`, `target=0x0f`, or `FSP_RUN`.
- **FACT:** The relevant public header/body definitions first appeared in the
  515.43.04 source release and remained unchanged through 610.43.03.  Searching
  the available official Git history produced no historical
  `FALCON_UCODE_DESC_V5`, `FALCON_UCODE_DESC_V6`, v6-version constant, or
  `FSP_RUN` definition.
- **FACT:** Current upstream Linux `nova-core` independently supports only
  Falcon descriptors v2/v3 and selects production FWSEC application ID `0x85`.
  It supplies no v6 or `0x24/0x0f` mapping.
- **FACT:** `linux-firmware` exposes GB202 GSP bootloader and FMC files, plus a
  GSP-RM link in `WHENCE`; it does not expose a file named FSP/FSP_RUN or a v6
  descriptor definition.
- **UNKNOWN:** Every field after v6 descriptor offset `+0x04`, the formal
  meaning of the printable bytes `FSP_RUN`, the encryption algorithm and
  coverage, and the numeric meanings of application `0x24` and target `0x0f`.
- **INFERENCE (weak):** The exact 28-byte tail can be split as 12 bytes plus
  16 bytes, matching conventional AES-GCM IV/tag sizes used elsewhere in
  NVIDIA's confidential-computing code.  No public source connects that
  unrelated representation to Falcon descriptor v6, so this is only a
  testable layout hypothesis, not a decoded field definition.

## Pinned public revisions

| Source | Pinned revision | Why it matters |
|---|---|---|
| NVIDIA `open-gpu-kernel-modules` | tag `610.43.03`, commit [`452cec62d827034798072827d3866d1881662b77`](https://github.com/NVIDIA/open-gpu-kernel-modules/commit/452cec62d827034798072827d3866d1881662b77), verified as `main` by `git ls-remote` on 2026-07-22 | Newest NVIDIA public driver snapshot in the local clone and on the remote at audit time |
| First NVIDIA public source release | tag/commit [`515.43.04` / `1739a20efc4acb55fd1dc53dcc66057b70c2613c`](https://github.com/NVIDIA/open-gpu-kernel-modules/commit/1739a20efc4acb55fd1dc53dcc66057b70c2613c) | Introduced the relevant public Falcon descriptor definitions |
| NVIDIA `open-gpu-doc` | commit [`9fdf5c4062007929d9f4e6cbad9c9771fe61b880`](https://github.com/NVIDIA/open-gpu-doc/commit/9fdf5c4062007929d9f4e6cbad9c9771fe61b880), remote `master` on 2026-07-22 | Official VBIOS/Falcon documentation |
| Linux `master` | commit [`248951ddc14de84de3910f9b13f51491a8cd91df`](https://github.com/torvalds/linux/commit/248951ddc14de84de3910f9b13f51491a8cd91df), remote `master` on 2026-07-22 | Current independent upstream parser (`nova-core`) |
| `linux-firmware` release metadata | tag [`20260622`](https://gitlab.com/kernel-firmware/linux-firmware/-/tree/20260622) and current `main` commit [`18cf97993f06c0a28d88cee30b7b646807642acd`](https://gitlab.com/kernel-firmware/linux-firmware/-/commit/18cf97993f06c0a28d88cee30b7b646807642acd) | Current public GB202 firmware inventory |
| Envytools | commit [`f102b82381f3f11cee113d16374c87091db039d9`](https://github.com/envytools/envytools/commit/f102b82381f3f11cee113d16374c87091db039d9) (still remote `master` on 2026-07-22) | Widely used community VBIOS parser; useful as a parser-boundary cross-check |

## 1. Public table and descriptor boundary

### 1.1 Falcon table entry

**FACT:** NVIDIA's current source defines a six-byte table entry as:

```c
bios_U008 ApplicationID;
bios_U008 TargetID;
bios_U032 DescPtr;
```

See
[`kernel_gsp_fwsec.c:100-123`](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/452cec62d827034798072827d3866d1881662b77/src/nvidia/src/kernel/gpu/gsp/kernel_gsp_fwsec.c#L100-L123).
This makes the raw interpretation of local entry bytes
`24 0f <little-endian-u32>` a **FACT**: application byte `0x24`, target byte
`0x0f`, followed by a descriptor pointer.

**UNKNOWN:** No inspected NVIDIA public source assigns a symbolic name to
application `0x24` or target `0x0f`.  The current parser names only application
IDs `0x05`, `0x45`, and `0x85`, and its selection code skips all others.  It
does not use `TargetID` to identify the selected FWSEC object.  See
[`kernel_gsp_fwsec.c:125-127,619-625`](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/452cec62d827034798072827d3866d1881662b77/src/nvidia/src/kernel/gpu/gsp/kernel_gsp_fwsec.c#L125-L127)
and
[`kernel_gsp_fwsec.c:619-625`](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/452cec62d827034798072827d3866d1881662b77/src/nvidia/src/kernel/gpu/gsp/kernel_gsp_fwsec.c#L619-L625).

### 1.2 Generic four-byte `vDesc` header

**FACT:** NVIDIA publishes these bit positions for the generic descriptor
header:

| Bits | Public name |
|---:|---|
| 0 | `FLAGS_VERSION` |
| 1 | flags reserved |
| 2 | `FLAGS_ENCRYPTED` |
| 7:3 | `VDESC_RESERVED` |
| 15:8 | descriptor `VERSION` |
| 31:16 | descriptor `SIZE` |

The exact source is
[`kernel_gsp_fwsec.c:129-146`](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/452cec62d827034798072827d3866d1881662b77/src/nvidia/src/kernel/gpu/gsp/kernel_gsp_fwsec.c#L129-L146).

For raw `word0 = 0x0050060d`:

| Raw component | Value | Evidence classification |
|---|---:|---|
| low byte | `0x0d` | **FACT** |
| raw bit 0 | `1` | **FACT**; public generic header names this flags-version available |
| raw bit 2 | `1` | **FACT**; public generic header names bit 2 `ENCRYPTED` |
| raw bit 3 | `1` | **FACT**; public generic header nevertheless places it in `VDESC_RESERVED` |
| bits 15:8 | `0x06` | **FACT**; generic extraction yields descriptor version 6 |
| bits 31:16 | `0x0050` | **FACT**; generic extraction yields descriptor size 80 bytes |

**Important limitation:** It is fair to report “raw bit 2 is set, and the
published generic header calls bit 2 `ENCRYPTED`.”  It is stronger than the
evidence to call the whole low byte a fully documented v6 flags field.  The set
bit 3 conflicts with the older public `RESERVED` declaration, and the same file
contains no v6 constant or body definition.

### 1.3 Public descriptor bodies stop at v2/v3

**FACT:** The NVIDIA file defines full C bodies for only:

- `FALCON_UCODE_DESC_V2`, 60-byte minimum;
- `FALCON_UCODE_DESC_V3`, 44-byte minimum.

See
[`kernel_gsp_fwsec.c:148-196`](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/452cec62d827034798072827d3866d1881662b77/src/nvidia/src/kernel/gpu/gsp/kernel_gsp_fwsec.c#L148-L196).
The parser accepts only versions 2 and 3 and skips every other version; see
[`kernel_gsp_fwsec.c:627-669`](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/452cec62d827034798072827d3866d1881662b77/src/nvidia/src/kernel/gpu/gsp/kernel_gsp_fwsec.c#L627-L669).

**FACT:** The full Falcon symbol
`NV_BIT_FALCON_UCODE_DESC_HEADER_VDESC_FLAGS_ENCRYPTED` occurs only at its
macro definition in the current official source tree.  (Other unrelated RM
subsystems also have flags whose shorter suffix is `FLAGS_ENCRYPTED`.)  The
public Falcon parser never tests this bit and exposes no descriptor decrypt
path.  Therefore the macro name does not publish an
algorithm, key source, nonce/IV layout, authentication-tag layout, ciphertext
start, or encrypted-length rule.

**FACT:** The exact public-format boundary for the saved GB202 object is thus
the four-byte word at descriptor `+0x00`.  Assigning v2/v3 names such as
`StoredSize` to v6 words at `+0x04` and later is an **INFERENCE**, not a public
definition.

## 2. Exact local observations, kept separate from public semantics

The four canonical samples reduce to three unique descriptor objects.  This
table only restates saved-byte observations already independently inventoried
in `parallel/vbios_fsp_inventory.md` and
`parallel/fsp_v6_payload_compare.md`:

| Saved sample | Descriptor file offset | First four bytes | Printable observation |
|---|---:|---|---|
| RTX 5090 FE (ASUS copy is identical here) | `0x11b304` | `0d 06 50 00` | bytes at descriptor `+0x2d..+0x33` are `FSP_RUN` |
| Dell RTX PRO 6000 8D | `0x128104` | `0d 06 50 00` | same seven printable bytes |
| HPE RTX PRO 6000 9E | `0x12cd04` | `0d 06 50 00` | same seven printable bytes |

**FACT:** `FSP_RUN` is a seven-byte printable sequence inside the 80-byte
descriptor.  It is not null-terminated on its right: descriptor `+0x34` is
already sample-dependent opaque data.  The eight-byte window
`[+0x2c,+0x34)` is `00 46 53 50 5f 52 55 4e`.

**UNKNOWN:** Public material does not name that byte window as a string field,
object name, entry point, stage name, target name, or task dispatcher.  It also
does not map the sequence to application `0x24` or target `0x0f`; that
association is only a local positional observation.

## 3. Public history: no v6 definition appeared

### 3.1 NVIDIA OpenRM release history

**FACT:** The local Git object database contains 209 NVIDIA release tags from
`515.43.04` through `610.43.03`.  The remote `main` SHA was independently
verified with `git ls-remote`.

`git log -L 90,146:src/nvidia/src/kernel/gpu/gsp/kernel_gsp_fwsec.c origin/main`
attributes the table/header block only to release commit
`1739a20efc4acb55fd1dc53dcc66057b70c2613c` (`515.43.04`, 2022-05-09).
There is no later modification to that block.  The first-release text already
contains versions v1-v4, the bit-2 `ENCRYPTED` label, and only v2/v3 bodies;
see the pinned
[`515.43.04` source at lines 94-176](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/1739a20efc4acb55fd1dc53dcc66057b70c2613c/src/nvidia/src/kernel/gpu/gsp/kernel_gsp_fwsec.c#L94-L176).

**FACT (bounded negative):** The following exact Git-history searches over all
available refs returned no commit:

```text
git log --all -S FALCON_UCODE_DESC_HEADER_VDESC_VERSION_V6 -- .
git log --all -S FALCON_UCODE_DESC_V6 -- .
git log --all -S FALCON_UCODE_DESC_V5 -- .
git log --all -S FSP_RUN -- .
```

This is a negative over the inspected official repository history, not a claim
about NVIDIA private source.

### 3.2 NVIDIA's VBIOS documentation

**FACT:** NVIDIA's official BIOS Information Table document defines BIT token
`0x70` and says its v2 data is a 32-bit “Falcon Ucode Table Pointer.”  It does
not define the pointed-to table's application IDs, target IDs, descriptor
versions, encryption flags, or bodies.  See
[`BIT_FALCON_DATA (Version 2)`](https://nvidia.github.io/open-gpu-doc/BIOS-Information-Table/BIOS-Information-Table.html#BIT_FALCON_DATA_v2).

**FACT:** The document's relevant section entered `open-gpu-doc` in commit
`60b67c31fcad6d0dc9603a034994a12efe3d5202` (2019-04-24) and has no later file
history in the inspected 88-commit repository.

**FACT:** NVIDIA's separate
[`Falcon Security`](https://nvidia.github.io/open-gpu-doc/Falcon-Security/Falcon-Security.html)
document discusses signed microcode, secure modes, and hardware signature
validation.  It publishes no VBIOS descriptor v6, AES-GCM envelope, IV, nonce,
or authentication-tag layout.

### 3.3 Current upstream Linux parser

**FACT:** At Linux commit `248951dd...`, `nova-core` represents only
`FalconUCodeDescV2` and `FalconUCodeDescV3`; see
[`firmware.rs:51-176`](https://github.com/torvalds/linux/blob/248951ddc14de84de3910f9b13f51491a8cd91df/drivers/gpu/nova-core/firmware.rs#L51-L176).
Its VBIOS parser recognizes only versions 2 and 3 and returns `EINVAL` for
others; see
[`vbios.rs:924-947`](https://github.com/torvalds/linux/blob/248951ddc14de84de3910f9b13f51491a8cd91df/drivers/gpu/nova-core/vbios.rs#L924-L947).

**FACT:** The same parser names FWSEC application IDs `0x05`, `0x45`, and
`0x85`, selects `0x85`, and provides no `0x24` or `0x0f` mapping; see
[`vbios.rs:814-915`](https://github.com/torvalds/linux/blob/248951ddc14de84de3910f9b13f51491a8cd91df/drivers/gpu/nova-core/vbios.rs#L814-L915).

**Caution:** Search results titled `[PATCH v6]` refer to the sixth revision of
a Linux patch series, not Falcon descriptor version 6.  The resulting merged
code still decodes only descriptor v2/v3.

### 3.4 `linux-firmware` metadata

**FACT:** NVIDIA-authored commit
[`050f0a1e3a76d671c073b59c813a4119b610b725`](https://gitlab.com/kernel-firmware/linux-firmware/-/commit/050f0a1e3a76d671c073b59c813a4119b610b725)
(authored 2025-04-29, committed 2025-05-16) added GSP-RM 570.144 for Hopper and
Blackwell.  For GB202 it added:

- `nvidia/gb202/gsp/bootloader-570.144.bin`;
- `nvidia/gb202/gsp/fmc-570.144.bin`;
- a `WHENCE` link from `nvidia/gb202/gsp/gsp-570.144.bin` to the shared
  GA102-family GSP-RM image.

The GB202 path is visible at the
[`20260622` tree](https://gitlab.com/kernel-firmware/linux-firmware/-/tree/20260622/nvidia/gb202/gsp).
The same two actual GB202 blobs were present on current `main` at audit time.

**FACT (bounded negative):** That GB202 tree and the corresponding `WHENCE`
metadata contain no standalone FSP/FSP_RUN file and no Falcon v6 descriptor
definition.  This supports only a file-inventory negative; it does not prove
where device-internal FSP runtime code resides.

### 3.5 Envytools parser trap

**FACT:** Current Envytools master knows only application IDs `0x01` (`PRE_OS`)
and `0x04` (`DEVINIT`) and target `0x01` (`PMU`); see
[`bios.h:1710-1756`](https://github.com/envytools/envytools/blob/f102b82381f3f11cee113d16374c87091db039d9/nvbios/bios.h#L1710-L1756).
Its parser does not branch on descriptor version and reads descriptor `+0x00`
as `stored_size`, then applies the legacy body layout; see
[`p.c:128-245`](https://github.com/envytools/envytools/blob/f102b82381f3f11cee113d16374c87091db039d9/nvbios/p.c#L128-L245).

**FACT:** Applying that code to the GB202 object would mislabel v6 `word0`
`0x0050060d` as a stored size.  Envytools is useful for the outer legacy table,
but its descriptor output is not evidence for v6 field names.

## 4. The 28-byte `12 + 16` AES-GCM hypothesis

### 4.1 What is directly observed

**FACT:** The public generic header yields descriptor size `0x50`.  The stable
printable sequence ends at `+0x33`, leaving exactly:

```text
[+0x34,+0x50) = 0x1c = 28 bytes
```

A proposed split is:

```text
[+0x34,+0x40) = 12 bytes
[+0x40,+0x50) = 16 bytes
```

The 28-byte sequences differ across the three unique saved descriptors and do
not contain a stable printable label like the preceding bytes.  That fact
alone does not identify two fields or a cryptographic primitive; “opaque tail”
is only a neutral label for the currently undefined bytes.

**FACT:** The three descriptor bases (`0x11b304`, `0x128104`, `0x12cd04`) are
all congruent to 4 modulo 16.  Therefore candidate tag offset `descriptor+0x40`
is also congruent to 4 modulo 16 in the actual file.  `+0x40` is a round
relative offset, but it is **not** an absolute 16-byte file alignment.

### 4.2 The real cross-subsystem size match

**FACT:** NVIDIA's separate UVM confidential-computing interface defines a
16-byte cryptographic authentication tag and an IV byte array of length 12:

- [`UVM_CSL_CRYPT_AUTH_TAG_SIZE_BYTES = 16`](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/452cec62d827034798072827d3866d1881662b77/src/nvidia/interface/nv_uvm_types.h#L884-L895);
- [`UvmCslIv.iv[12]`](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/452cec62d827034798072827d3866d1881662b77/src/nvidia/interface/nv_uvm_types.h#L1088-L1098).

Another confidential-computing header explicitly names a 12-byte AES-256-GCM
IV (`96/8`), and a separate control structure names a 16-byte AES-256-GCM auth
tag (`128/8`):

- [`cc_drv.h:39-74`](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/452cec62d827034798072827d3866d1881662b77/src/common/sdk/nvidia/inc/cc_drv.h#L39-L74);
- [`ctrl2080internal.h:3869-3883`](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/452cec62d827034798072827d3866d1881662b77/src/common/sdk/nvidia/inc/ctrl/ctrl2080/ctrl2080internal.h#L3869-L3883).

### 4.3 Why this is not a Falcon-v6 definition

**FACT:** None of the cited UVM/CC declarations refers to VBIOS, a Falcon
descriptor, FSP_RUN, application `0x24`, target `0x0f`, or descriptor v6.

**FACT:** `UvmCslIv` is not exactly a standalone 12-byte structure: after its
12-byte `iv` array it has an additional `NvU8 fresh` member.  The UVM auth tag
is declared in a different structure.  The public source does not present a
contiguous `UvmCslIv.iv[12] || authTag[16]` wire layout.

**FACT (bounded negative):** Searches of the pinned NVIDIA tree found no line
combining Falcon/FWSEC/FSP descriptor terminology with AES, GCM, IV, nonce, or
authentication-tag fields.  The one FSP-path nonce hit is a 32-byte TNVL
attestation-request nonce in `fsp_tnvl_rpc.h`, unrelated to a VBIOS descriptor.
Current Linux `nova-core` `vbios.rs`, `firmware.rs`, and `firmware/fwsec.rs`
also contain no AES/GCM/IV/tag definition.

**INFERENCE (weak, retained only as a candidate):** Explicit raw bit 2, an
opaque 28-byte suffix, and the conventional `12 + 16` AES-GCM dimensions make
“12-byte IV followed by 16-byte tag” a plausible hypothesis to test against a
future same-format source or multiple controlled samples.  It is not enough to
name either subrange today.  Other 28-byte metadata layouts remain possible,
and there is no public basis to choose AES-GCM, byte order, AAD, ciphertext
coverage, or field order.

## 5. FACT / INFERENCE / UNKNOWN ledger

### FACT

1. Entry bytes are application, target, and little-endian descriptor pointer.
2. Raw target word 0 is `0x0050060d` in all three unique saved objects.
3. The generic public header calls bit 2 `ENCRYPTED`; raw bit 2 is set.
4. Raw bit 3 is also set even though the same old public header labels bits
   7:3 reserved.
5. Generic extraction gives descriptor version 6 and size 80 bytes.
6. Public NVIDIA and current Linux parsers implement only v2/v3 bodies.
7. `FSP_RUN` is observed at descriptor `+0x2d`; no public field assigns that
   sequence semantics.
8. No inspected public mapping names app `0x24` or target `0x0f`.
9. The v6 public-body gap persisted from NVIDIA release 515.43.04 through
   610.43.03.
10. GB202 `linux-firmware` metadata exposes GSP bootloader/FMC, not a standalone
    FSP_RUN object.
11. The opaque suffix is exactly 28 bytes; NVIDIA uses 12-byte AES-GCM IVs and
    16-byte tags in an unrelated confidential-computing subsystem.

### INFERENCE

1. The v6 object is a newer/private extension of the published common envelope.
2. Treating raw bit 2 according to the generic header as an encryption marker
   is a medium-confidence compatibility inference.  The v6 sample's set bit 3
   already contradicts the old `RESERVED` declaration, and its encryption
   coverage/algorithm is not published.
3. The `12 + 16` split is a weak cross-subsystem size analogy only.
4. A `word1`-sized payload region may be a useful bounded carving hypothesis,
   but `word1` is not publicly defined as v6 `StoredSize`.

### UNKNOWN

1. Formal symbolic meanings of application `0x24` and target `0x0f`.
2. Every v6 body field after descriptor `+0x04`.
3. Meaning and field boundaries of the bytes containing `FSP_RUN`.
4. Whether bytes `[+0x34,+0x50)` are one field, two fields, or padding plus
   metadata.
5. Encryption algorithm, mode, key hierarchy, IV/nonce, authentication tag,
   AAD, compression order, signature scheme, and byte coverage.
6. Whether the production task-2 consumer is in this object, immutable chip
   ROM, or another authenticated stage.

## 6. Negative-result boundary

The negative result is deliberately limited to:

- all Git refs available in the local clone of NVIDIA
  `open-gpu-kernel-modules`, including the verified `origin` refs and 209
  NVIDIA release tags through remote `main` / 610.43.03;
- the complete 88-commit history and current tree of NVIDIA `open-gpu-doc`;
- current upstream Linux `nova-core` files named above;
- `linux-firmware` GB202 tree and `WHENCE` at release `20260622` and current
  main;
- current Envytools master;
- exact public-web searches for `0050060d`, `0d 06 50 00`, `FSP_RUN` with
  GB202/NVIDIA/`0x24`, and v5/v6 descriptor symbol names.

No search result supplied a public Falcon-v6 body, AES-GCM field layout,
`0x24/0x0f` mapping, or formal `FSP_RUN` definition.  This does **not** prove
such information never existed in private NVIDIA source, internal tools,
device ROM, or unindexed material.
