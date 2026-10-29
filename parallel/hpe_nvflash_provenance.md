# HPE package → `nvflash` provenance audit (static only)

Date: 2026-07-22 (Asia/Singapore)

## Scope and safety boundary

This was a bounded, offline, read-only audit of the HPE-related files under
`vbios_diff/` and the existing local reports.  `nvflash`, the `.scexe`, and the
RPM payload were **not executed or installed**.  No GPU/device node, driver,
MMIO/BAR, debugfs, firmware loader, MODS, reset, network, or system-wide file
scan was used.

The questions answered here are deliberately separate:

1. Is the saved `nvflash` byte-for-byte the archive member carried by the
   saved `.scexe`? **Yes (FACT).**
2. Is that `.scexe` byte-for-byte the RPM member? **Yes (FACT).**
3. Are the local containers internally consistent? **Yes (FACT):** every
   available RPM/XZ/gzip/member digest or checksum tested successfully.
4. Do the local bytes cryptographically authenticate HPE as the publisher?
   **No such proof is present (FACT/UNKNOWN):** the RPM has digest tags but no
   standard public-key signature tag, the `.scexe` has no detached signature
   member, and no trusted external acquisition record/key is stored locally.

## 1. Exact local chain

### 1.1 RPM → `.scexe`

Top-level saved package:

```text
vbios_diff/NVIDIA_RTX_PRO_6000_Blackwell_96GB_PCIe_GPU_VBIOS-98.02.9E.00.01-1-0.x86_64.rpm
size    8,471,656 bytes
SHA256  183c76f5ea0d5e72796fe1cf2f1ce5d8c31796e3f6d7876c19121a4e41784fe8
```

**FACT:** The RPM payload contains one regular file (plus its parent
directory), with the exact archive path:

```text
./usr/local/bin/NVIDIA_RTX_PRO_6000_Blackwell_96GB_PCIe_GPU_VBIOS-98.02.9E.00.01/
  NVIDIA_RTX_PRO_6000_Blackwell_96GB_PCIe_GPU_VBIOS-98.02.9E.00.01.scexe
```

The member is 8,481,142 bytes and hashes to:

```text
4c1e99989a81099e6b352c54b39bd313d88ee1fcc7207524d61f250869b3ab94
```

**FACT:** A streaming `cmp` between that member and the saved file at
`vbios_diff/hpe_rpm_extracted/usr/local/bin/.../*.scexe` returned equality.
The RPM main header also records file-digest algorithm 8 (SHA-256) and the same
`4c1e...ab94` member digest.

### 1.2 `.scexe` → gzip/tar → `nvflash`

Saved `.scexe`:

```text
size    8,481,142 bytes
SHA256  4c1e99989a81099e6b352c54b39bd313d88ee1fcc7207524d61f250869b3ab94
```

**FACT:** Its textual wrapper sets `_SKIP=414`, and line 72 implements the
payload read as `tail -n +$_SKIP $0 | gzip -cd`.  The first gzip header is
therefore exactly at file offset `0x2765` (10,085):

```text
wrapper prefix [0x0000,0x2765) SHA256
737a130aebe1e66d90d9063618877b1dbc02fa1cf8aa8ca90fa5bf8f3ef5f347

gzip tail [0x2765,EOF) SHA256
a750c0800ff7fc8c32dbb41cae48bb011f2c418332550e89bb8c93e88345b1a7
```

The gzip tail is 8,471,057 bytes.  Its gzip CRC/length test succeeds.  It
expands to an 18,554,880-byte tar stream with SHA-256:

```text
2deac00d896fbd71fae8f45a96bca77be5216e1ee3375e43078a28580cea31e2
```

**FACT:** The tar has exactly four regular-file members:

| member | bytes | archived mtime |
|---|---:|---|
| `hpsetup_generic` | 20,661 | 2025-12-19 |
| `nvflash` | 16,309,920 | 2025-12-19 |
| `nvfw_RTXPRO6000BWSE_0003_251124.1.0_prod-signed.fwpkg` | 2,204,365 | 2025-12-19 |
| `NVIDIA_Firmware_License.txt` | 14,701 | 2025-12-19 |

Archive timestamps are metadata, not authenticity proof.

**FACT:** In the uncompressed tar, the `nvflash` header starts at `0x5400`
and its raw file data is `[0x5600,0xf934a0)`.  Hashing that exact range, and
independently streaming the named member through `bsdtar`, both produce:

```text
d1aee0b0309475826b15bb8c31624d11a80e0e6d568bea6144be7e213df44780
```

The saved file is:

```text
vbios_diff/hpe_static_tools/nvflash
size    16,309,920 bytes
SHA256  d1aee0b0309475826b15bb8c31624d11a80e0e6d568bea6144be7e213df44780
```

**FACT:** A streaming `cmp` between the tar member and this saved file returned
equality.  Therefore the current `hpe_static_tools/nvflash` is an exact member
extraction, not a rebuilt, patched, or differently packaged copy.

## 2. Version and binary identity (without execution)

**FACT:** Static ELF inspection identifies the member as a stripped ELF64
x86-64 `ET_EXEC` with Linux ABI tag 2.6.32.  It was never launched.

Static string extraction finds one complete utility banner at file offset
`0x942678`:

```text
NVIDIA Firmware Update Utility (Version 5.877.0)
```

A second bare `5.877.0` string occurs at `0x942b08`.  Thus **5.877.0 is the
embedded version claim**.  This does not independently authenticate its
publisher.

**FACT:** The ELF note table contains only `.note.ABI-tag`; there is no GNU
build-id note or standard in-file ELF signature note.  **UNKNOWN:** This
bounded observation cannot exclude a proprietary integrity mechanism inside
the program, but it supplies no external publisher authentication.

## 3. What the outer checks do and do not prove

### 3.1 RPM integrity is internally verifiable

The RPM signature header begins at `0x60`, has seven index entries, and ends at
`0x1194`; the aligned main header is `[0x1198,0x1cfc)` and the XZ payload begins
at `0x1cfc`.

**FACT:** All stored digest values reproduce exactly:

| RPM item | covered bytes | stored and recomputed value |
|---|---|---|
| tag 269 SHA-1 | main header `[0x1198,0x1cfc)` | `f71976ef4daa50b3b17cfef5e819fafc15629cd9` |
| tag 273 SHA-256 | main header `[0x1198,0x1cfc)` | `dfae37987d692e18496c85ed821c2d483773c7b42ad4c6ec16734c17b07b5795` |
| tag 1004 MD5 | main header plus payload `[0x1198,EOF)` | `4fcb30bbb06b39ed3ee84eba1a9b1e78` |
| main-header payload digest, algorithm 8 | compressed XZ payload `[0x1cfc,EOF)` | `bb891e758d411345d8d607ae3852092827d4271b5d00ed53cefc506107435210` |
| main-header file digest, algorithm 8 | `.scexe` member | `4c1e99989a81099e6b352c54b39bd313d88ee1fcc7207524d61f250869b3ab94` |

The XZ stream's own SHA-256 integrity check also passes, and a full archive
test reports no structural error.

These checks prove that the saved archive is self-consistent and that the
member was extracted exactly.  Unkeyed digests do **not** prove who created
the archive because someone replacing bytes could recompute them.

### 3.2 No standard RPM publisher signature is present

**FACT:** The seven RPM signature-header tags are raw tags `62`, `269`, `273`,
`1000`, `1004`, `1007`, and `1008`.  There is no standard DSA/RSA header
signature (tags 267/268), PGP/GPG signature (tags 1002/1005), or PGP5 signature
(tag 1006).  Tag 1008 is reserved space, not a signer certificate.

Consequently there is no local RPM public-key signature to validate against
an HPE key.  This is stronger than merely saying that a verification tool/key
is missing: the relevant signature packet is absent from the package.

### 3.3 `.scexe` has transport integrity, not publisher authentication

**FACT:** The textual `.scexe` prefix contains no hash, signature, certificate,
or digest verification.  Its unpack routine only decompresses gzip and
extracts tar.  The complete four-member tar contains no detached signature or
manifest member.  A full static read of the small `hpsetup_generic` script
shows it invokes `nvflash` and names the `.fwpkg`, but it contains no checksum,
digest, certificate, or signature-verification routine for `nvflash`.

The gzip CRC32 and tar header checksum protect against accidental corruption;
they are not cryptographic publisher authentication.  The word `prod-signed`
belongs to the **firmware package member's filename** and must not be treated
as a signature over the neighboring `nvflash` executable or over the outer
`.scexe`.

## 4. Source-attribution limit

**FACT:** Unsigned RPM metadata claims:

- summary: `HPE Firmware Flash component for GPU VBIOS for NVIDIA RTX PRO 6000 Blackwell 96GB PCIe GPU`;
- license: `HPE Software License Agreement v1`;
- build host: `nvidia-flash1`;
- RPM URL field: literal `None`.

No origin-URL extended attribute is present on the RPM, `.scexe`, or extracted
`nvflash`, and the existing local project reports contain no saved HPE download
URL for this exact RPM.  Because the RPM is not public-key signed, those
self-declared strings are useful identification clues but are forgeable.

**UNKNOWN:** From the permitted local evidence alone, the original download
server, TLS transaction, and official HPE publication record cannot be
reconstructed or authenticated.  Establishing that would require an external
HPE catalog/hash/signature record, which was intentionally outside this
offline audit.

## Conclusion

- **FACT:** `hpe_static_tools/nvflash` is byte-exact to the `.scexe` tar member.
- **FACT:** The `.scexe` is byte-exact to the RPM member.
- **FACT:** The complete local chain passes its available digest/checksum and
  archive-integrity checks.
- **FACT:** The extracted executable's embedded version claim is 5.877.0.
- **FACT:** The RPM has no standard public-key signature packet, and neither
  outer layer carries a detached signature for `nvflash`.
- **UNKNOWN:** Official HPE publisher authenticity cannot be proven from this
  local package alone.

