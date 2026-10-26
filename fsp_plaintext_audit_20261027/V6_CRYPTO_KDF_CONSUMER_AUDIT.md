# FSP v6 Crypto Descriptor / KDF Consumer Audit

**Scope:** read-only local static analysis of MODS 570.151, 570.215 and 570.278, plus locally carved v6 descriptors. No firmware was executed; no GPU, BAR, device node, VM or firmware-update path was touched. This report is additive and keeps observations separate from hypotheses.

## Executive findings

1. The local v6 descriptor corpus has an outer `0x50`-byte record. At `+0x28` is a `0x28`-byte child beginning `01 28 01 01`, followed by an 8-byte object identifier and 28 bytes of opaque data. The first `01` plausibly identifies an inner descriptor v1; `0x28` agrees exactly with the child length. The meanings of the last two `01` bytes are **not recovered**.
2. MODS exposes stable error-name mappings for AES-GCM authentication/decryption, KDF configuration/execution/timeout, crypto-structure descriptor versions/sanity and `NON_FSP_DECRYPTION_DEV_NOT_ALLOWED`. These are error-code/name tables, not the hidden FSP implementation or proof of the exact branches that raise the errors.
3. MODS does contain a host-side software AES-256-GCM decrypt path. In the 570.215 decompilation it copies a 32-byte key from a caller-owned structure at `param_2+0x44`, uses a 12-byte IV, no AAD and a 16-byte tag. No KDF/root-key derivation is visible in that routine. Its internal caller reaches it with an explicit software-mode flag, but the recovered path is not tied to the v6 `FSP_RUN` descriptor or to the FSP sender.
4. No evidence found for a dev-fused bypass, for the source of the FSP KDF root/key, or for host software decrypt of the encrypted `FSP_RUN` payload. The available error names alone do not establish a bypass or its absence inside the encrypted FSP.

## Samples, hashes and address convention

All addresses below are **ELF virtual addresses (VA)** unless explicitly marked file offset (FO). For the file-backed ELF load segment in these samples, `FO = VA - 0x400000`; table/string FOs are included where useful. Function labels such as `SwDecryptCandidate` are analyst labels, not recovered ELF symbols.

| MODS build/sample used | Size | SHA-256 | Notes |
|---|---:|---|---|
| 570.151 `mods_audit/static/extracted_inner/mods` | 392,339,552 | `c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf` | Also matches the extracted 570.151 `mods` copy byte-for-byte. |
| 570.215 `/home/user/mod570_215_static/extracted/home/570.215/mods` | 392,897,664 | `6645d5de5e0ce3c9dacd79e264e46398cb1296107d4dba15cbb3a84ea82e5856` | Addressed sample for the disassembly/table checks. |
| 570.278 `fsp-offline-crypto-audit-MYwexsWH/mods_versions/570.278/mods` | 393,278,528 | `1d55a7e4fc0ffcad1405ae0a512dc1e5b11e183dad6a14ec34e2dc8042b74f72` | Addressed sample for the disassembly/table checks. |

There is also a separate same-size 570.215 `mods_sul5_host` copy (SHA-256 `603ce19a8d2926a2c89d71b55407ef858ab73be7b2872d85c14d12612a73dcc5`). Its relevant decrypt-function, error-table and string windows are byte-identical to the addressed 570.215 copy, but the whole files are not identical. The Ghidra project is `ghidra/mods_crypto`; its decompilation was checked against the selected 570.215 code bytes at the listed addresses.

## Descriptor bytes and what can be inferred

### Direct specimen

`vbios_diff/gb202_fwsec_opt_20260925/gb202_5090_fe_tpu_app24_target0f_descriptor.bin` is an 80-byte standalone descriptor (FO 0). SHA-256: `ccc6647fda7d26f4de03f65d46cc683b52c5cb0dac1d3ed75b2e1a08885870fc`.

Observed layout:

```text
FO +0x00  0d                         outer flags
FO +0x01  06 50 00                   v6 marker / 0x50-sized outer record pattern
FO +0x04  ...                        other outer metadata (not assigned here)
FO +0x28  01 28 01 01                40-byte inner crypto child header
FO +0x2c  00 46 53 50 5f 52 55 4e    8-byte ID: NUL + "FSP_RUN"
FO +0x34  c9 67 dd ff c2 1a c0 cd fd 91 6a f9
          8a 8c 49 d2 98 16 db 2f 8f a3 bf 77 27 fb 98 9b
                                     28 opaque child bytes
```

The whole corpus scan (`scan_v6_crypto_headers.py`, `v6_crypto_header_scan.json/.log`) scanned 350 firmware-like files and found 203 records / 36 unique descriptor bodies. Every record had `desc[+0x28:+0x2c] == 01 28 01 01`; no alternative values for the last two bytes were available for differential naming. Outer flags observed were `05`, `0d`, `1d` and `1f`.

### Bounded interpretation

- **Observed:** the outer record is `0x50` bytes and its child starts at `+0x28`, so child size is `0x50 - 0x28 = 0x28`. The second child byte is also `0x28`.
- **Hypothesis:** child byte 0 (`01`) is a version-1 selector. This agrees with the MODS error name `UNSUPPORTED_CRYPTO_STRUCT_DESC_V1_VERSION` (code `0x217`) but does not prove that this is the exact structure/version namespace checked by the encrypted FSP.
- **Unknown:** the two final header bytes (`01 01`) have no observed variation or recovered enum names. The 8-byte ID is visibly an object identifier, but the rest of the outer metadata fields are not fully assigned.
- **Hypothesis only:** the 28-byte tail could be `IV12 || tag16`, because the MODS software GCM routine below uses a 12-byte IV and 16-byte tag and `12+16=28`. There is no recovered dataflow from this v6 descriptor to that routine, so this must not be treated as established field semantics. The exact AAD range and any association between outer fields and GCM inputs remain unknown.

The scan is a local byte-layout parser, not the consumer: no MODS code path was found that reads these v6 records and dispatches the `.FSP_RUN` object into `SwDecryptCandidate`.

## Error-string cross-reference and version differences

The existing extraction (`extract_mods_error_map.py`, `mods_error_map.json`, `mods_crypto_errors.txt`) recovers 600 error codes. 570.151 and 570.215 use an indirect code-to-case table; 570.278 has a contiguous 600-entry 64-bit name-pointer table. These are error-name lookup structures, not the FSP crypto implementation.

| Error code | Error string | 570.151 mapping | 570.215 mapping | 570.278 mapping |
|---:|---|---|---|---|
| `0x16c` | `AES_256_GCM_AUTHENTICATION_ERROR` | case VA `0x1859231` | case VA `0x189b551` | string VA `0x8cb2ef0` |
| `0x16d` | `AES_256_GCM_DECRYPTION_ERROR` | present in table | present in table | present in table |
| `0x1a0` | `KDF_CONFIG_ERROR` | case VA `0x1858f25` | case VA `0x189b245` | string VA `0x916f535` |
| `0x1a1` | `KDF_EXECUTION_ERROR` | present in table | present in table | present in table |
| `0x1a2` | `KDF_SHA_TIMEOUT_EXPIRED` | present in table | present in table | present in table |
| `0x213` | `UNSUPPORTED_CRYPTO_STRUCT_DESC_V4_VERSION` | case VA `0x1858868` | case VA `0x189ab88` | string VA `0x8cb4138` |
| `0x214` | `CRYPTO_STRUCT_DESC_V4_SANITY_FAILURE` | case VA `0x1858859` | case VA `0x189ab79` | string VA `0x8cb4168` |
| `0x215` | `UNSUPPORTED_CRYPTO_STRUCT_DESC_V5_VERSION` | case VA `0x185884a` | case VA `0x189ab6a` | string VA `0x8cb4190` |
| `0x216` | `CRYPTO_STRUCT_DESC_V5_SANITY_FAILURE` | case VA `0x185883b` | case VA `0x189ab5b` | string VA `0x8cb41c0` |
| `0x217` | `UNSUPPORTED_CRYPTO_STRUCT_DESC_V1_VERSION` | case VA `0x185882c` | case VA `0x189ab4c` | string VA `0x8cb41e8` |
| `0x218` | `UNEXPECTED_CRYPTO_MSG_TYPE` | case VA `0x185881d` | case VA `0x189ab3d` | string VA `0x916f8e3` |
| `0x222` | `NON_FSP_DECRYPTION_DEV_NOT_ALLOWED` | case VA `0x1858787` | case VA `0x189aaa7` | string VA `0x8cb4280` |

Table locations:

- 570.151: 600-qword code-to-case table at **VA `0x930de00` / FO `0x8f0de00`**.
- 570.215: 600-qword code-to-case table at **VA `0x937b140` / FO `0x8f7b140`**.
- 570.278: 600-qword name-pointer table at **VA `0x934a080` / FO `0x8f4a080`**.

The 570.151 and 570.215 case targets above were checked against the `mov esi, string_VA` instructions in their case blocks. In 570.278, the listed values are direct pointers to the matching NUL-terminated names. The numeric codes and names are stable across these samples despite the lookup representation and addresses changing. In particular, `0x217` is a *crypto-structure descriptor* v1 error; it is not evidence that the outer FSP envelope itself is v1. The outer v6 envelope and inner structure are separate layers unless a consumer proves otherwise.

The following are the corresponding **string VAs** (FO is VA minus `0x400000`), including the additional diagnostics cross-referenced in the host decrypt path:

| String | 570.151 VA / FO | 570.215 VA / FO | 570.278 VA / FO |
|---|---|---|---|
| `AES_256_GCM_AUTHENTICATION_ERROR` | `0x8c90a68` / `0x8890a68` | `0x8cf5f20` / `0x88f5f20` | `0x8cb2ef0` / `0x88b2ef0` |
| `AES_256_GCM_DECRYPTION_ERROR` | `0x90fb7fc` / `0x8cfb7fc` | `0x9166b1e` / `0x8d66b1e` | `0x916f3d4` / `0x8d6f3d4` |
| `KDF_CONFIG_ERROR` | `0x90fb95d` / `0x8cfb95d` | `0x9166c7f` / `0x8d66c7f` | `0x916f535` / `0x8d6f535` |
| `KDF_EXECUTION_ERROR` | `0x90fb96e` / `0x8cfb96e` | `0x9166c90` / `0x8d66c90` | `0x916f546` / `0x8d6f546` |
| `KDF_SHA_TIMEOUT_EXPIRED` | `0x90fb982` / `0x8cfb982` | `0x9166ca4` / `0x8d66ca4` | `0x916f55a` / `0x8d6f55a` |
| `UNSUPPORTED_CRYPTO_STRUCT_DESC_V4_VERSION` | `0x8c91cb0` / `0x8891cb0` | `0x8cf7168` / `0x88f7168` | `0x8cb4138` / `0x88b4138` |
| `CRYPTO_STRUCT_DESC_V4_SANITY_FAILURE` | `0x8c91ce0` / `0x8891ce0` | `0x8cf7198` / `0x88f7198` | `0x8cb4168` / `0x88b4168` |
| `UNSUPPORTED_CRYPTO_STRUCT_DESC_V5_VERSION` | `0x8c91d08` / `0x8891d08` | `0x8cf71c0` / `0x88f71c0` | `0x8cb4190` / `0x88b4190` |
| `CRYPTO_STRUCT_DESC_V5_SANITY_FAILURE` | `0x8c91d38` / `0x8891d38` | `0x8cf71f0` / `0x88f71f0` | `0x8cb41c0` / `0x88b41c0` |
| `UNSUPPORTED_CRYPTO_STRUCT_DESC_V1_VERSION` | `0x8c91d60` / `0x8891d60` | `0x8cf7218` / `0x88f7218` | `0x8cb41e8` / `0x88b41e8` |
| `UNEXPECTED_CRYPTO_MSG_TYPE` | `0x90fbd13` / `0x8cfbd13` | `0x9167035` / `0x8d67035` | `0x916f8e3` / `0x8d6f8e3` |
| `NON_FSP_DECRYPTION_DEV_NOT_ALLOWED` | `0x8c91df8` / `0x8891df8` | `0x8cf72b0` / `0x88f72b0` | `0x8cb4280` / `0x88b4280` |
| `SwDecrypt(), gcm_crypt_and_tag() failed with 0x%x` | `0x8cad758` / `0x88ad758` | `0x8d12da0` / `0x8912da0` | `0x8d3b5d8` / `0x893b5d8` |
| `fuserework_debug_gfw_pub_key.bin` | `0x8c78438` / `0x8878438` | `0x8cdd650` / `0x88dd650` | `0x8d08f38` / `0x8908f38` |

The `SwDecrypt` diagnostic is loaded at the instruction addresses listed in the preceding cross-version function table (`0x19d89a8`, `0x1a1bee8`, `0x1a274e8` respectively). This ties the string to the local software-GCM failure path, not to the `0x16c` error-name entry. The FuseRework filename is a separate file/authentication flow; its presence does not identify a v6 KDF input or key source.

## MODS host software decrypt path

### Cross-version addresses

The same-shaped local decrypt function, wrapper and adjacent crypto-operation function are present in all three samples. Addresses are ELF VAs:

| Build | `SwDecryptCandidate` | wrapper | adjacent operation candidate | wrapper direct call sites | GCM-failure log instruction |
|---|---:|---:|---:|---|---:|
| 570.151 | `0x19d8750` | `0x19d8b90` | `0x19d8c10` | `0x19d96dd`, `0x19d97de` | `0x19d89a8` |
| 570.215 | `0x1a1bc90` | `0x1a1c0d0` | `0x1a1c150` | `0x1a1cc1d`, `0x1a1cd1e` | `0x1a1bee8` |
| 570.278 | `0x1a27290` | `0x1a276d0` | `0x1a27750` | `0x1a2821d`, `0x1a2831e` | `0x1a274e8` |

The `SwDecryptCandidate` entry is 0x440 bytes before the wrapper in each build; its failure-log instruction is consistently at entry `+0x258`. The wrapper has two direct call sites in each build. In the 570.215 caller `FUN_01a1c5b0`, the first wrapper call passes mode flag `1` and the second passes `0`; the first is the software GCM branch. Matching wrapper/candidate call layout and the diagnostic are present in 570.151 and 570.278.

### 570.215 decompilation summary

The relevant Ghidra artifacts are `ghidra_swdecrypt_decompiled.c` and `ghidra_swdecrypt_wrapper.c`. The helper uses length/data pairs at `+0x4c8/+0x4d8` in its input objects. Pseudocode preserving the observed arguments:

```c
key = copy(param_2 + 0x44, 0x20);       // 32 caller-supplied bytes
ciphertext = copy(param_3->data, param_3->len);
tag = copy(param_4->data, param_4->len);
iv = copy(param_5->data, 0x0c);         // exactly 12 bytes copied

rc = GcmCryptAndTagWrapper(
        key, /* mode */ 0, iv, 0x0c,
        NULL, 0,                            // no AAD
        ciphertext, plaintext, param_3->len,
        tag, 0x10);                         // GCM tag length 16
if (rc != 0) {
    log("SwDecrypt(), gcm_crypt_and_tag() failed with 0x%x", rc);
    return 0xf0;
}
copy(param_6->data, plaintext, param_3->len);
return 0;
```

This is a raw-key AES-256-GCM software decrypt operation; the wrapper calls the local GCM init/update/finalize implementation (Ghidra labels `GcmCryptAndTagWrapper` at VA `0x17adf70`, `GcmInit` at `0x17adab0`, `GcmUpdate` at `0x17adc80` and `GcmFinalize` at `0x17addb0`). No KDF call is visible between copying the 32-byte key and invoking GCM. The 16-byte tag length is fixed at the GCM call; the tag input object is copied using its own length, so the caller's object shape is also relevant.

`SwDecryptWrapper` at `0x1a1c0d0` branches on its boolean mode argument. When nonzero it calls `SwDecryptCandidate` with the caller's data/tag/IV/output objects and then continues through a common helper; when zero it skips the GCM candidate. The direct caller at `0x1a1c5b0` invokes both modes. This proves a MODS-internal host software decrypt call exists. It does **not** establish a user-facing decrypt API, a dev-fuse exemption, or use on a v6/FSP_RUN descriptor.

The immediate key source visible at this function boundary is `param_2+0x44`; the function does not derive it. The containing object is prepared/used in the adjacent internal crypto-operation flow (including `ConfigureCryptoObject` at `0x1a1bb50` and `CryptoOperationWrapper` at `0x1a1b610`), but the source of the 32 bytes and any relationship to a KDF root were not recovered. The decrypted output is copied back to a caller-provided output object; there is no evidence this is the encrypted FSP image.

The GCM failure path returns local status `0xf0`; it does not return the mapped FSP error `0x16c` or policy code `0x222`. Thus the shared error names must not be conflated with the local helper's return values.

## KDF and dev-mode limits

- The mapped names `KDF_CONFIG_ERROR` (`0x1a0`), `KDF_EXECUTION_ERROR` (`0x1a1`) and `KDF_SHA_TIMEOUT_EXPIRED` (`0x1a2`) establish that the FSP/RM error namespace contains KDF-related failures. They do not reveal KDF algorithm, configuration fields, label/context, root-key source, fuse bank, or whether derivation occurs in FSP, a crypto engine, or a prior stage.
- `NON_FSP_DECRYPTION_DEV_NOT_ALLOWED` (`0x222`) is a stable error name. The recovered evidence is its code-to-name mapping; no host-side conditional tied to dev-fuse state was established. The software helper itself copies a key and branches on an explicit caller mode flag; no dev-fuse read/check or bypass is visible in that helper/wrapper.
- Therefore neither “dev fused bypass exists” nor “the FSP has no dev bypass” is supported. The encrypted FSP's policy branch is not available for this static audit.
- Existing `FSP_SENDER_CALLSITE_AUDIT.md` finds seven direct MODS calls to `FspSendRequestCandidate` (570.215), none shaped as a bulk `FSP_RUN` plaintext-return wrapper. This narrows the visible host API but does not rule out a private FSP-internal decrypt/KDF service.
- `fuserework_debug_gfw_pub_key.bin` and the RSA-3072 FuseRework authentication flow are separate host-side update/authentication material; no evidence links them to the v6 AES key or the KDF root.

## Open questions / next evidence needed

1. Obtain or recover the actual FSP consumer/parser for the v6 record; MODS error names and the byte scanner do not identify that consumer.
2. Establish whether child header bytes 2 and 3 are cipher/mode/flags, and whether the 28-byte tail is `IV12 || tag16`; also map any AAD to outer fields.
3. Trace the 32 bytes consumed at `param_2+0x44` back to its producer and determine whether that code path is unrelated test data, a derived key, or a key handed in by a caller.
4. Recover KDF configuration and the root-key source/ladder, including any fuse or device-state dependencies.
5. Locate the actual check behind `NON_FSP_DECRYPTION_DEV_NOT_ALLOWED` and determine whether any dev-fused policy exception exists. No bypass was demonstrated here.
6. Determine whether any host call can receive plaintext for the `FSP_RUN` object. Current sender and software-helper evidence does not show such a call.

## Reproducibility pointers

- Descriptor scan: `scan_v6_crypto_headers.py`, `v6_crypto_header_scan.json`, `v6_crypto_header_scan.log`.
- Error maps: `extract_mods_error_map.py`, `mods_error_map.json`, `mods_crypto_errors.txt`.
- 570.215 Ghidra decomp: `ghidra_swdecrypt_decompiled.c`, `ghidra_swdecrypt_wrapper.c`.
- FSP host sender boundary: `FSP_SENDER_CALLSITE_AUDIT.md`, `ghidra_fsp_sender_18a0d40.c`.
- Separate FuseRework flow: `FUSEREWORK_ABI.md`.
