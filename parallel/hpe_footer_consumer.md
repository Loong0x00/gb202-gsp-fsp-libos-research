# HPE `.fwpkg` 0x400 P-384 footer consumer / trust-anchor audit

Date: 2026-07-22 (Asia/Singapore)

## Scope and safety boundary

This was a bounded, offline, read-only inspection of three possible consumers
of the extra HPE package footer:

- archive member `hpsetup_generic` (20,661 bytes, SHA-256
  `b54916c5a3f14473330c6d141bf0cedb1b43950b215826797f81a78d0b65d02f`);
- saved `nvflash` 5.877.0 (SHA-256
  `d1aee0b0309475826b15bb8c31624d11a80e0e6d568bea6144be7e213df44780`);
- PLDM component 1 of the HPE package (SHA-256
  `ad14aa1e6caa2ce307d2a06bf67cd26425c9f1a3bccd8aef0023aaf2a8fb8545`).

No archive member or firmware was executed. No GPU/device node, PCI/BAR/MMIO,
driver, debugfs, reset, MODS, network, or updater action was used. Inspection
was limited to the package structure, the complete small Perl wrapper, one
identified PLDM-parser function, a small MCU/CEC crypto window, and bounded
constant/key searches. This report does not study how to bypass any check.

The package itself is:

```text
nvfw_RTXPRO6000BWSE_0003_251124.1.0_prod-signed.fwpkg
SHA-256 620b673fcbee27d90693610477344332e5f3d47ba538903f9ebcd09db52abe27
```

Its relevant exact partition, already independently validated in
`fwpkg_container_auth.md`, is:

```text
PLDM header  [0x000000,0x00014d)
component 0  [0x00014d,0x1d1f1d)
component 1  [0x1d1f1d,0x219ecd)
extra footer [0x219ecd,0x21a2cd)  (0x400 bytes)
```

## Executive result

- **FACT:** The footer is internally self-consistent: its carried P-384 key
  verifies the ECDSA/SHA-384 signature. That proves a byte-integrity relation,
  not the publisher identity.
- **FACT:** `hpsetup_generic` does not parse or authenticate the footer. It
  delegates the whole filename to `nvflash`.
- **FACT:** The identified `nvflash` PLDM package parser validates the standard
  PLDM UUID and header CRC, consumes the declared components, then returns at
  the end of the component loop. It does not consume or require EOF after the
  extra 0x400 bytes.
- **FACT:** The footer magic, footer SPKI, raw EC point, and tested common key
  fingerprints are absent from `nvflash`; its four embedded P-384 PEM keys are
  different keys used by an MCU/CEC challenge-attestation path.
- **FACT:** Component 1 is an MCXN236/Cortex-M33 MCU firmware image containing
  PLDM, SPDM/device-identity, NBOOT, eFuse version and key-revocation logic. It
  contains neither the footer magic nor the footer public key/point/hash.
- **BOUNDED CONCLUSION:** No pinned key/hash or concrete verifier for this
  footer was found in the three permitted artifacts. The evidence strongly
  supports that the ordinary saved `hpsetup_generic` -> `nvflash` PLDM parse
  path tolerates/ignores the trailing footer.
- **UNKNOWN:** A different HPE deployment/catalog tool, an unexamined generic
  indirect path, or external policy could consume it. Therefore this is not a
  universal proof that no HPE software ever verifies the footer.

## 1. `hpsetup_generic` is only an orchestrator

### FACT

The complete 568-line archive member was read statically. It imports only Perl
control/terminal-color facilities; it contains no hash, PEM, ECDSA, X.509,
certificate, signature, or trust-store routine.

The image-selection path invokes:

```text
./nvflash -v nvfw_RTXPRO6000BWSE_0003_251124.1.0_prod-signed.fwpkg
```

to obtain Version, Board ID, and Hierarchy ID. The write path later passes the
same filename to:

```text
./nvflash --index=<index> -A <fwpkg filename>
```

The script checks device/image Board ID and Hierarchy ID equality and treats
the child process exit status as success/failure. It does not open the package
or independently inspect its final bytes.

### Conclusion

**FACT:** `hpsetup_generic` is not the footer verifier and supplies no trust
anchor. If the packaged workflow validates the footer, that validation must be
below it (`nvflash`/device) or outside it (another HPE distribution layer).

## 2. The identified `nvflash` PLDM parser stops after declared components

### 2.1 Exact bounded control-flow evidence

The standard package parser begins at VA `0x4735c0` (file offset `0x735c0`).
Its observed operations are:

1. `0x4735f1..0x473630`: read the standard package header and compare its
   16-byte identifier against the accepted PLDM UUID values;
2. `0x473636..0x473c9c`: parse the standard header, device records and component
   records;
3. `0x473c9c..0x473d60`: obtain the stored header CRC and recompute the standard
   CRC32 (`0xedb88320` polynomial); failure reaches the adjacent
   `Checksum mismatch` path;
4. `0x473d62..0x473f60`: record the position immediately after the header,
   iterate over the declared component records, and copy/read each declared
   component extent;
5. after the final registered component, branch directly to the epilogue at
   `0x473f60` and return at `0x473f6e`.

For this package, header size plus the two registered component sizes ends
exactly at `0x219ecd`, the first byte of the extra footer. In the bounded
function there is no third component, footer parse, EOF equality assertion,
or read of the remaining `0x400` bytes.

**FACT:** This parser authenticates only the unkeyed standard PLDM header CRC.
That CRC is not the P-384 footer signature and is not a publisher trust anchor.

### 2.2 Footer-specific constant/key search

The following byte sequences were searched across the complete saved ELF:

- footer header/magic `5f 32 cb 08` (and the full 18-byte raw header);
- full 120-byte footer SPKI DER;
- its 97-byte uncompressed EC point;
- SHA-1, SHA-224, SHA-256, SHA-384, and SHA-512 of that SPKI;
- the known footer PEM SHA-256.

All were **not found**. The footer SPKI SHA-256 is:

```text
525f6d09a398b8b1f8890ca100e3a849337f0bb28d5c5ff5c9bc72d7331e4c34
```

This is a bounded negative: it rules out a literal pin of those tested forms,
not every possible transformed, external, or dynamically provided policy.

### 2.3 The four embedded P-384 PEM keys are unrelated MCU/CEC keys

`nvflash` does contain four literal P-384 public keys. Their file offsets and
SPKI SHA-256 fingerprints are:

| file offset | SPKI SHA-256 |
|---:|---|
| `0x932680` | `eb8ffeeef0d53b55333e1920d23c1f738261a8d806384203a8467a63854cfc50` |
| `0x932760` | `14cd85ee61401d92d85866db716d7b08ed0c391ab9ff5c8abc679cccd0e43ff1` |
| `0x932840` | `2d510720562416781eaf1719a5a5d9ffbbc5d06a2ae8b26f2a341cfad8759abd` |
| `0x932920` | `e8e2614aefe6495211dc8944d696e94f2c31523b2cc3c0be5401984422ec9fb0` |

None equals the footer key. Their only direct key-address references found are
at `0x71a778`, `0x71a814`, `0x71a8cb`, and `0x71a902`. That local function first
compares a 48-byte attestation value against a small table, selects one of the
four keys, and calls the same verification helper. Its adjacent diagnostic
strings explicitly say:

```text
MCU Device
CEC FW Version
Send SEND_CHALLENGE failed.
Attestation Information
CEC Chip State
```

**FACT:** These four keys belong to the MCU/CEC challenge-attestation family,
not the PLDM outer-footer parser. The mere presence of a statically linked
OpenSSL implementation likewise does not establish footer verification.

### `nvflash` conclusion

**Strong bounded inference:** The ordinary PLDM parser treats the 0x400 footer
as tolerated trailing data. No literal trust anchor for its carried key was
found. A whole-program claim is deliberately not made because nameless
indirect/generic paths were outside this audit.

## 3. PLDM component 1 contains a different, device-internal trust domain

### FACT: identity and role clues

The component begins with a plausible Cortex-M vector table (initial stack
`0x20038000`, Thumb reset vector `0x00007661`). Static strings identify:

```text
Cortex-M33
SDK_25_03_00_FRDM-MCXN236
MCU Firmware PLDM Task
src/nv/spdm/spdm_cert_chain.cpp
NVIDIA MCU SMA pCA
Failed to initialize NBOOT
ImageKeyRovocationOptIndex read fail
Invalid key_revoke
efuse version: ...
boot from slot ...
```

These establish an NXP MCXN236 MCU firmware with PLDM update handling,
SPDM/device-identity certificate construction/attestation, and its own secure
boot/update-slot controls. They do not identify an HPE outer-package verifier.

### FACT: footer material is absent

Within the complete `0x47fb0`-byte component, bounded searches found no:

- HPE footer magic `5f 32 cb 08`;
- footer SPKI or raw EC point;
- footer SPKI/PEM SHA-256;
- PEM `-----BEGIN` marker.

There is one DER-shaped P-384 SPKI sequence at component-relative `+0x417be`.
It is embedded inside an apparent SPDM device-certificate template near
`NVIDIA MCU SMA pCA` data; OpenSSL can parse its ASN.1 shape but rejects it as
a valid standalone EC public key. Its 120 raw bytes hash to
`42b3fb483ad7d7b0737320057358f623827128c6edae5aa45412874b328f8194`,
which is not the footer SPKI fingerprint. A second P-384 OID at `+0x4598e` is
among certificate-building constants adjacent to `spdm_cert_chain.cpp`.

Finally, component 1's registered range ends before the outer footer begins.
The host parser extracts/transfers registered component extents; the footer is
not part of component 1's bytes. Thus the saved component's SPDM/NBOOT key
material is evidence of a separate MCU/device trust domain, not a copy of the
HPE wrapper key.

### Component conclusion

**FACT:** No matching outer-footer key, hash, or format marker exists in the
saved MCU image. **UNKNOWN:** Firmware already present on a device could differ
from this update image, but nothing in this saved component closes the footer
publisher-authentication chain.

## 4. Final FACT / UNKNOWN boundary

### FACT

1. The footer signature can be verified with its own carried public key.
2. The carried key is not an X.509 chain and no trusted issuer accompanies it.
3. `hpsetup_generic` delegates the package without verifying the footer.
4. The identified `nvflash` PLDM parser stops at the declared component end and
   does not consume the footer.
5. No tested literal pin of the footer key/hash is present in `nvflash` or
   component 1.
6. `nvflash`'s four literal P-384 keys and component 1's certificate material
   belong to MCU/CEC/SPDM/device-identity paths and do not match the footer key.

### UNKNOWN

1. Which HPE tool originally defined/consumed the `0x400` footer format.
2. Whether an external HPE catalog or management layer pins this key/hash.
3. Whether an unexamined indirect/generic code path can self-check the footer.
4. Whether any such external verifier authenticates the key to HPE/NVIDIA,
   rather than merely checking self-consistency with the key carried in-band.

The most defensible present statement is therefore:

> The saved package contains a valid self-consistency signature, but this
> bounded audit found neither its verifier nor a pinned publisher trust anchor.
> The packaged `hpsetup_generic` -> `nvflash` PLDM parser path appears to ignore
> the trailing 0x400 bytes.

