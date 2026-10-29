# `nvflash` 5.877.0 update compatibility boundary (bounded static audit)

Date: 2026-07-22 (Asia/Singapore)

## Scope and safety boundary

This is a narrow, offline compatibility audit of the already saved executable:

```text
/home/user/rt_5090_project/vbios_diff/hpe_static_tools/nvflash
SHA256 d1aee0b0309475826b15bb8c31624d11a80e0e6d568bea6144be7e213df44780
embedded version claim: NVIDIA Firmware Update Utility (Version 5.877.0)
```

Only a few string cross-references and bounded disassembly windows around the
`.fwpkg`, `NVFW`, PLDM-update, and NVDM-receive paths were inspected.  The ELF
was **not executed**.  No GPU, driver/device node, MMIO/BAR, debugfs, firmware
loader, MODS, reset, network, or whole-program decompiler was used.

This report distinguishes local host-format checks from statuses returned by
an update transport.  It does not investigate defeating or bypassing any
verification.

## Bottom line

1. **FACT:** `nvflash` does not treat the entire `.fwpkg` as one opaque blob.
   It selects a package parser by the filename extension, parses the PLDM
   package header/device records/component metadata, validates the package
   UUID, validates the declared header length, and recomputes the PLDM header
   CRC32 locally.
2. **FACT:** Component image bytes are then separated/copied according to the
   parsed component sizes.  The host also recognizes the outer `NVFW` magic
   and has code that copies/re-packs ranges of that container.  Therefore the
   correct boundary is not “host sees no structure at all.”
3. **FACT:** The inspected host parser does not thereby gain Falcon-v6 body
   semantics.  The separate bounded classifier audit showed that descriptor
   `0d 06 50 00` has no explicit v6 case and is incorrectly projected onto an
   old GFW-v1 layout.  Thus recognizing/copying an `NVFW` container is not
   evidence that 5.877.0 decrypts or cryptographically validates its nested
   `FSP_RUN` Falcon-v6 body.
4. **FACT:** PLDM and NVDM error messages examined here are emitted *after* a
   virtual transport/protocol call returns a response/status object.  These
   are different from the local PLDM-header UUID/length/CRC checks.
5. **UNKNOWN:** The bounded windows do not identify the exact component that
   cryptographically verifies the nested Falcon-v6 object.  The binary also
   contains host crypto/certificate code for other firmware formats, while
   update paths expose device/firmware verification result codes.  It would
   be an overclaim to assign every signature check either wholly to the host
   or wholly to the device.

## Address convention

For the relevant executable and read-only segments, the ELF virtual address
is the file offset plus `0x400000`.  Code addresses below are virtual
addresses.

## 1. What the host parses locally

### 1.1 `.fwpkg` extension dispatch

The literal `.fwpkg` is at file offset `0x885e38` / VA `0xc85e38`.

- At `0x445e2a..0x445e43`, the host compares the input filename extension with
  `.fwpkg`; on equality it calls `0x4708e4`.
- The independent duplicate dispatch at `0x44b6ce..0x44b6e7` does the same.
- `0x4708e4` opens/reads the named file into a host-side stream/buffer and
  passes the bytes through the package object constructors and parser
  dispatch.  This is a local file path, not a device response path.

**FACT:** `.fwpkg` is a recognized host-side input format, not merely an
extension forwarded unchanged to a device.

### 1.2 PLDM package UUID and records

The common PLDM package parser begins at `0x4735c0`.

- `0x473606..0x473630` compares the first 16 bytes against two accepted UUID
  constants at `0xc89740` and `0xc89750`.
- A mismatch reaches `0x47370b..0x473732`, which constructs the local exception
  text `Firmware Package is invalid, Pldm Header UUID mismatch`
  (`0xc885a0`).
- The following parser loop allocates host objects for the package device-ID
  records and reads their variable-length fields.  Later loops build the
  component table.

The saved HPE package starts with exactly the first accepted UUID:

```text
f0 18 87 8c cb 7d 49 43 98 00 a0 2f 05 9a ca 02
```

**FACT:** UUID rejection is a local input-format check performed before an
update transport is involved.

### 1.3 Header length and CRC32 are local checks

At `0x473c9c..0x473d25`, the parser compares its current parsed position with
the package's declared header length.  A mismatch constructs the local text
`Package header size mismatch` (`0xc88f1d`).

At `0x473cde..0x473d60`, it computes CRC32 byte-by-byte over the parsed package
header.  The loop uses polynomial `0xedb88320`, inverts the final accumulator,
and compares it with the stored 32-bit checksum.  A mismatch reaches
`0x473d99..0x473dc0`, which constructs `Checksum mismatch` (`0xc88f3a`).

The saved HPE package provides a useful exact cross-check:

```text
declared header size:  bytes 4d 01 -> 0x014d (333 bytes)
CRC-covered prefix:   [0x000,0x149) (329 bytes)
stored CRC bytes:     70 9d db db -> 0xdbdb9d70
recomputed CRC32:     0xdbdb9d70
first component:      starts at package offset 0x14d with "NVFW"
```

**FACT:** This CRC is the PLDM package-header integrity check.  CRC32 is not a
cryptographic publisher signature and does not authenticate who produced the
package.

### 1.4 Component images are separated as byte ranges

After the header CRC succeeds, `0x473d62..0x473f20` iterates the parsed
component descriptors.  For each component it uses a 32-bit component-size
field (read at the per-component object offset `+0x10`), advances the running
package offset, allocates/resizes a host byte vector, and copies the declared
range with `memmove`.

The saved package physically consists of the header followed by the GPU NVFW
component and a second management-MCU component; the first component is the
exact 1,908,176-byte canonical HPE NVFW already inventoried elsewhere in this
project.

**FACT:** The package layer supplies component-sized byte buffers.  It does
not simply submit all 2,204,365 package bytes as one undifferentiated block.

## 2. How far the host understands `NVFW`

### 2.1 Outer-container recognition is explicit

Several host-side component/image paths compare the four-byte little-endian
magic `0x5746564e` (`"NVFW"`):

- `0x45d2c3` first invokes the common PLDM parser `0x4735c0`; while walking the
  resulting component image ranges, `0x45d317` directly checks the component
  start for `NVFW` and dispatches to an image object on a match.
- Another package/image path begins at `0x451a80`, likewise calls the common
  PLDM parser, and checks for `NVFW` at component-relative `+0x400`
  (`0x451ed8`) and `+0x1000` (`0x451eeb`).  The matching branches allocate a
  larger host image object and bulk-copy selected ranges into it.

**FACT:** The host recognizes and re-houses/copies outer NVFW ranges.  Calling
the complete NVFW image “opaque to nvflash” would therefore be too strong.

### 2.2 The nested Falcon-v6 body remains outside the proven parser boundary

Outer recognition does not establish nested-format semantics.  The companion
audit `parallel/nvflash_v6_parser_reverse.md` proves that the identified Falcon
descriptor classifier at `0x7dde66` has explicit cases only through GFW v4.
For saved Blackwell header bytes `0d 06 50 00`, it falls through to the legacy
GFW-v1 default, ignores the `0x50` header size, and gives nonsensical old-field
labels to the v6 bytes.

**FACT:** In the inspected 5.877.0 ELF, no explicit Falcon version-6/size-0x50
body parser has been identified.

**UNKNOWN:** A transport may still preserve and submit the nested v6 bytes
unchanged while host code parses other parts of the surrounding VBIOS/NVFW.
The bounded static evidence cannot name the v6 encryption/authentication
fields, plaintext, or verifier from this binary.

## 3. Which errors are protocol/transport results

### 3.1 PLDM request-update result

At `0x7b649a..0x7b64b4`, the PLDM state machine invokes a virtual update method
and receives a response object.  It then reads response byte `+0x04`:

- zero continues;
- nonzero response codes are formatted after `0x7b64ca`;
- the text `ERROR: Unable to initiate firmware update.` is emitted at
  `0x7b6510` as part of that returned-result path.

**FACT:** This message is downstream of a protocol call and returned response
code.  It is not produced by the local `.fwpkg` UUID/length/CRC parser.

### 3.2 PLDM component transfer result

At `0x7b6da7..0x7b6e3e`, the state machine builds a byte vector from a component
range and invokes another virtual method at `0x7b6e21`.  Its integer return is
stored in `ebx` at `0x7b6e40`; zero succeeds, while nonzero results reach the
formatter using `ERROR: Transfer failed with PLDM result code: 0x`
(`0xd38bb8`) at `0x7b6efb`.

**FACT:** The component is transported as a sized byte buffer at this layer,
and the displayed PLDM result code is returned by that update method.

**UNKNOWN:** The virtual-call window alone does not separate a remote firmware
completion code from a lower driver/transport failure for every possible
nonzero value.

### 3.3 NVDM receive status

At `0x797a3a..0x797a49`, an NVDM receive interface is called virtually.  The
returned object pointer is read at `0x797a4b`, and its status dword at object
offset `+0x0c` is tested.  Only a nonzero status reaches the literal
`NVDM firmware update receive failed with error code 0x` (`0xd35ea0`) at
`0x797a5f..0x797a78`.

**FACT:** This is a post-receive status report, not a local package-structure
check.

**UNKNOWN:** From this bounded indirect-call window, the producer of every
status value (device firmware, kernel/driver bridge, or host transport layer)
cannot be uniquely assigned.

### 3.4 Verification result propagation

The PLDM update state machine contains separate returned-result branches for
verification timeout/failure, including `ERROR: Timeout occurred while
verifying firmware image.` and `ERROR: Verify failed with PLDM result code:
0x`.  A different update path at `0x5aeb4e..0x5aeb5b` receives an integer from
a virtual verification method; returned value `0x1102` is mapped at
`0x5aebbc..0x5aebee` to `VBIOS verification failed,
NV_STATUS_ERR_CODE_EROT_VERIFY_FW_FAILED.`

**FACT:** The host propagates verification outcomes returned by update/device
interfaces.  Merely finding the corresponding text in `nvflash` does not mean
the host itself performed the cryptographic operation.

## 4. Hash/signature verification boundary

| Layer | What is established | Classification |
|---|---|---|
| PLDM `.fwpkg` header | Host checks accepted UUID, declared header size, and CRC32 | **FACT** |
| PLDM component table | Host parses metadata and separates/copies component byte ranges | **FACT** |
| Outer GPU `NVFW` | Host recognizes `NVFW` magic and copies/re-packs container ranges | **FACT** |
| Nested Falcon-v6 `FSP_RUN` | Identified descriptor parser has no v6 body support | **FACT** |
| PLDM/NVDM update outcome | Host displays response/status values returned after protocol/transport calls | **FACT** |
| Exact v6 cryptographic verifier | Could be a device secure-loader stage, but this bounded ELF audit does not identify it | **UNKNOWN** |
| All other BIOS/certificate verification | The ELF contains host crypto/BCRT/certificate code as well as device error mappings; per-path ownership was not traced here | **UNKNOWN** |

The important compatibility distinction is therefore:

```text
host local work:
  file selection -> PLDM header/records/components -> UUID/size/CRC32
  -> recognize outer NVFW -> copy/re-pack image ranges

transport/device-facing work:
  submit sized component/image buffers -> receive PLDM/NVDM status
  -> report device/transport verification outcome

unresolved boundary:
  exact parser/decryptor/authenticator for the nested Falcon-v6 FSP_RUN object
```

## Conclusion

- **FACT:** `nvflash` 5.877.0 is structurally aware of `.fwpkg` and outer
  `NVFW`; it is not a blind whole-package copier.
- **FACT:** Its local package integrity check is CRC32 over the PLDM header,
  and the saved HPE package reproduces the stored CRC exactly.
- **FACT:** Component payloads cross the update layer as sized byte buffers,
  while PLDM/NVDM errors examined here are returned protocol/transport
  statuses.
- **FACT:** No explicit Falcon-v6 body support has been established in this
  ELF, so outer NVFW handling cannot be promoted into a claim that the host
  understands or verifies `FSP_RUN` v6 internals.
- **UNKNOWN:** The exact secure component that authenticates the nested v6
  object remains outside the evidence boundary of this audit.
