# DGX Spark FieldDiag package audit

Date: 2026-10-27

## Scope and safety

Source directory supplied by the user:

`/home/user/nvidia-fieldiag/`

The packages and contained executables were not installed or executed. Analysis consisted of hashing, archive listing/selective extraction, string search, strict format carving, public-source comparison, and offline AES-GCM authentication tests. Original `.deb` files were not modified.

## Input packages

| Package | Bytes | SHA-256 |
|---|---:|---|
| `dgx-spark-fieldiag_1.0.7-1_arm64.deb` | 849,563,022 | `ddae0fbfc5f3be881cbe32eb8a320b8dc53e1cdc42dc36049c3dc529f8009a25` |
| `dgx-spark-fieldiag_1.0.8-1_arm64.deb` | 806,802,642 | `9d25c2f7272de1fabafa1927a5e32c4f1809ddf80c6aaf45ed1cf57011503bf5` |
| `dgx-spark-fieldiag_1.0.9-1_arm64.deb` | 806,812,378 | `4daec155dee89a84c7f7e4d6da96c21e0314e55553fa699bbd0bb50404ec30a7` |
| `dgx-spark-fieldiag_2.0.4-1_arm64.deb` | 812,973,682 | `9bee126388bd45b97bb43f781cf93b0a9a304fe15449b2e9de3842a26498ebf6` |

These are public DGX Spark ARM64 packages, not the requested Blackwell PCIe Field Diagnostics `629-INT27-DIAG-008` package.

Each `.deb` contains a large nested OneDiag archive:

- 1.0.7: `onediagfield.r9.257.3.tgz`, 855,906,852 bytes
- 1.0.8/1.0.9: `onediagfield.r9.257.3.tgz`, 812,604,988 bytes
- 2.0.4: `onediagfield.r9.257.8.tgz`, 818,616,898 bytes

## Embedded MODS/FieldDiag executable

The nested archive contains `dgx/tests/mods.580/fieldiag`, a stripped AArch64 ELF.

| Package versions | Internal version strings | SHA-256 |
|---|---|---|
| 1.0.7, 1.0.8, 1.0.9 | `580.120`, `629.580.36` | `09babac01221b2a440903149c7a88b38dec2a97a18e1dff7b55b1e69ba609c16` |
| 2.0.4 | `580.116`, `629.580.34` | `383147f07018911fe55537dd7a35eced01ac9c4b65873dc55dd634fe35483b48` |

Selected copies and scripts were extracted under:

`external_dgx_spark_fielddiag/`

## Direct target-material search

The executable contains the same expected external filenames and APIs as MODS 570:

- `fuserework.bin`
- `fuserework_debug_gfw_hash.bin`
- `fuserework_debug_gfw_pub_key.bin`
- `fuserework_debug_gfw_sig.bin`
- `SetReworkBinaryFilename`
- `SetReworkPublicKeyFilename`
- `SetReworkRSASignatureFilename`
- `SetReworkSHAHashFilename`
- `GetSkuReworkInfo`
- `FRB Riscv Start`

However, none of those four files is present in any nested archive member list. The only explicitly named FRB/FUB files remain the legacy `frb_ga100.bin` / `fub_ga100.bin` strings or material; no Blackwell FuseRework file was found.

The two literal `FSP_RUN` byte strings in each executable occur inside error/name tables (`ICU_FSP_RUNTIME_COMPONENT_NOT_FOUND` and `INVALID_FSP_RUNTIME_VERSION`), not in valid Falcon-v6 envelopes. `inventory_fsp_run.py` returned zero records for both FieldDiag ELFs.

## FuseRework ABI confirmation in MODS/FieldDiag 580

AArch64 direct string-reference recovery located:

- default `fuserework.bin` constructor reference near VA `0x10a051f0`
- auth-sidecar constructor near VA `0x10ce9814`
- transfer/execute routine near VA `0x10ce9c90`

The 580 implementation preserves the 570.215 payload shape:

- hash read length: `0x30` = 48 bytes
- public key read length: `0x180` = 384 bytes
- RSA signature read length: `0x180` = 384 bytes
- command selector: `0x0f`
- embedded length value: `0x0348`
- response remains a 4-byte acknowledgement equal to `0x0000000f`

Therefore the public GB202 GSP-RM debug GFW authentication files are not drop-in FuseRework sidecars: the public 580.119.02 GB202 GFW uses a 97-byte ECC public key and a 96-byte signature, while FuseRework explicitly demands 384-byte public-key and signature files.

Assembly evidence:

- `external_dgx_spark_fielddiag/fieldiag580_fuserework_default_ctor.asm`
- `external_dgx_spark_fielddiag/fieldiag580_fuserework_flow.asm`
- `external_dgx_spark_fielddiag/aarch64_fuserework_string_refs.txt`

## Strict mode-2 carving

Scanning both distinct FieldDiag ELFs with the recovered type-2/3/4 size equations produced:

- 68 records total
- 34 unique objects
- every object occurs identically in both executables

Breakdown:

- 3 unique type-2 containers
- 2 unique type-3 containers
- 29 unique type-4 GFW containers

All five type-2/type-3 objects are byte-identical to objects already carved from MODS 570.215. Thus FieldDiag 580 does not add a new Blackwell FuseRework main helper; it repeats the old helper set.

The 29 type-4 GFW objects are newer than the MODS 570 set. Their authentication prefixes were correctly recovered and all 58 occurrences pass `SHA-384(image) == stored_hash`:

- 26 ECC-authenticated occurrences
- 32 RSA-3072-authenticated occurrences
- 6 unique public keys

Artifacts:

- `external_dgx_spark_fielddiag/carved_mode2/`
- `external_dgx_spark_fielddiag/carved_type4_auth/`
- `external_dgx_spark_fielddiag/carve_mode2.log`
- `external_dgx_spark_fielddiag/extract_type4_auth.log`

## Exact public-source attribution

Generated bindata sources from NVIDIA's public `open-gpu-kernel-modules` tag `580.119.02` were downloaded into the analysis directory and parsed. Thirteen of the 29 type-4 objects match public GSP-RM GFW images byte for byte, including:

- GB202 CC production GFW: SHA-256 `0ddb8ca6891a5215c674954223eb191d70aa7b01cb11665b984e3c5eadf7a78a`, 257,096 bytes
- GB202 production GFW: SHA-256 `c62856e9787222fc68c1c41e44e4ba7c022f9aaff3a56622f3437e3382af50ee`, 215,624 bytes
- GB202 debug GFW: SHA-256 `9245f416f4daa1b145b0b3521e5012e934988092e80c5d316a080ff68e978780`, 215,624 bytes

The full exact map is stored in:

`external_dgx_spark_fielddiag/public_gfw_exact_map.json`

This proves that these objects are ordinary driver GSP-RM GFW bindata, not a hidden `fuserework.bin` merely lacking a filename.

Sixteen private type-4 objects remain unattributed by the public 580.119.02 generated-source set. They occur as several production/debug-sized pairs and have valid GFW authentication material. All 29 type-4 objects, including the unattributed set, are represented through the executable's standard generated bindata record/map/getter layout; the missing FuseRework main object instead follows the explicit external `fuserework.bin` file-loader path. No reference links that filename/loader to one of these embedded getters. This makes the 16 objects much more likely ordinary private firmware components than a hidden renamed copy of the external FuseRework bundle, although exact component names still require attribution.

Getter mapping evidence is stored in:

- `external_dgx_spark_fielddiag/gfw_getter_map.json`
- `FIELDDIAG580_PRIVATE_GFW_ATTRIBUTION.md`

## AArch64 FSP sender audit

The newer AArch64 implementation has the same seven direct calls to its generic FSP sender as the x86-64 MODS 570.215 build:

- one 7-byte `0x82` status request
- FuseRework command `0x0f`, with a `0x346`-byte request and exact 4-byte ACK
- one 2-byte internal `0x0c` wrapper with a 4-byte response
- one `0x0e` request with a 12-byte response
- three `0x0e` requests with 24-byte responses

No caller receives an FSP/GFW-sized response or writes a bulk plaintext image. The FieldDiag 580 ELF also contains a general host software AES-256-GCM helper, but its explicit caller-provided key/IV/tag objects are not connected to the FSP sender, an `FSP_RUN` descriptor, or FuseRework.

Detailed evidence:

`FIELDDIAG580_AARCH64_FSP_SENDER_AUDIT.md`

## Offline key/KDF test

New FieldDiag 580 public keys, signatures and SHA-384 image hashes were tested as AES-256 candidates and bounded HMAC-SHA256 KDF roots against the three locally extracted literal `FSP_RUN` objects:

- unique authentication materials: 64
- direct AES-256 candidates: 851
- direct GCM authentication trials: 5,106
- KDF-derived GCM trials: 207,360
- successful tags: **0**

Result:

`external_dgx_spark_fielddiag/fielddiag580_auth_candidate_audit.json`

## Conclusion

The DGX Spark packages are useful because they provide a newer MODS/FieldDiag implementation and 29 newer signed GFW containers. They independently confirm that FuseRework 580 still expects the same external four-file bundle and the same 48/384/384 authentication lengths.

They do **not** contain the required files and do not contain a valid `FSP_RUN` image or plaintext. The key missing main file remains:

`fuserework.bin`

with required sidecars:

- `fuserework_debug_gfw_hash.bin`
- `fuserework_debug_gfw_pub_key.bin`
- `fuserework_debug_gfw_sig.bin`

The best remaining use of this package is static attribution of the 16 private type-4 GFW objects and differential analysis of the newer AArch64 FSP sender; it is not itself the requested Blackwell PCIe FieldDiag/FuseRework payload.
