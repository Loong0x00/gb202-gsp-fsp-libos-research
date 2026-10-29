# NVFlash 5.877 Debug Token / HULK transport static audit

Date: 2026-08-13  
Scope: offline disassembly and public-source comparison only. No updater/token
command was executed in this pass; no GPU, EEPROM, InfoROM, VBIOS, BAR, reset,
or firmware state was changed.

## Fixed inputs

| Artifact | SHA-256 | Role |
|---|---|---|
| `vbios_diff/hpe_static_tools/nvflash` | `d1aee0b0309475826b15bb8c31624d11a80e0e6d568bea6144be7e213df44780` | Linux NVFlash 5.877, ELF64, image base `0x400000` |
| NVIDIA `mctp-utils/mctp_utils/mctp_vdm_utils.py` | `169179e74fadf5bb49fb8d85a4ed46724e247cdceebd9a777b6445640ab819a7` | Public legacy NVIDIA VDM command definitions |
| NVIDIA `mctp-utils/mctp_utils/mctp_nsm_utils.py` | `84b95a74884e8ae6092f1041691b8f0695e635fc777cb8a563c5ef7ae06d46e6` | Public current NSM v2 comparison |

Public repositories:

- <https://github.com/NVIDIA/mctp-utils>
- <https://github.com/NVIDIA/nsmd>
- <https://github.com/NVIDIA/nvidia-code-mgmt>

The inspected `mctp-utils` checkout was at commit
`d9e131ab2501c89a04327845500e9388850e3312` (2026-07-24).

## Corrected short result

NVFlash exposes separate commands for installing and activating a Debug Token.
They are not aliases, but the static paths must be split by protocol generation:

1. `--installtoken` reaches a generic per-device installer at `0x5d6040`.
   For its chip-family `0x1a`/`0x1b`/`0x1c` branch, the complete wrapper chain
   is now statically closed to NVIDIA legacy VDM command `0x0b`
   (`InstallDbgToken`).
2. `--activatetoken` is statically closed to a four-byte-zero HULK NVDM request:
   NVIDIA vendor-defined message type `0x11`, payload `u32 0`.
3. The binary also contains legacy NSM Diagnostic wrappers, while current public
   `nsmd` uses NSM v2 chunked token installation. Neither fact proves that the
   GB202 `--installtoken` branch selects that wrapper.

The earlier revision of this report incorrectly mapped the CLI to the NSM v2
wrapper and incorrectly assigned current NSM v2 chunk fields to NVFlash 5.877.
Those claims are withdrawn.

## 1. CLI `--installtoken`: legacy NVIDIA VDM backend proved

The command-line branch calls offset `+0x480` on the interface returned by
`0x567048`. This factory returns `object+0x10`; the interface vptr is
`0xcfca78`, not the object's primary vptr `0xcfc4c8`.

The actual slot is:

```text
0xcfca78 + 0x480 = 0xcfcef8 -> 0x57dd39
0x57dd39: sub rdi, 0x10; jmp 0x57d8e2
```

`0x57d8e2` iterates selected devices/targets. At `0x57dcc1` it loads the primary
object vtable and calls primary slot `+0x338`, which is `0x5d6040` for both
observed host controller implementations (`0xcfc4c8` and `0xd003d0`). Thus the
CLI-to-generic-installer route is **PROVED**.

Inside `0x5d6040`, the `0x1a`/`0x1b`/`0x1c` branch first compares the selected
token record with the current GPU identity:

```text
0x5d621c   token-record method +0xa8 returns its identity bytes
0x5d6231   device method +0x190 obtains the current GPU identity object
0x5d6242   method +0x1c8 returns the device's 64-bit identity value
0x5d62a8..0x5d62d7   serialize it to eight bytes and reverse byte order
0x5d6388   memcmp token identity against the eight device bytes
```

Only a matching record reaches `0x5d64c4`. That call to `0x78f4ac` performs a
type-id-3 interface lookup through `0x7c3c34`, but there is one additional
wrapper layer that must not be skipped:

```text
0x78f4f0   allocate the 0x20-byte wrapper
0x78f403   construct it via 0x785294
0x78f434   wrapper primary vptr = 0xd35aa0
0xd35aa0 + 0xa0 = 0xd35b40 -> 0x791fca
0x5d64d7   call the wrapper's +0xa0 method with the matched token record
```

`0x791fca` is the legacy NVIDIA VDM Debug Token installer. Its fixed nine-byte
request prefix is:

```text
0x791feb   7f
0x791fef   47 16 00 00       NVIDIA IANA 0x1647, little-endian
0x791ff6   80
0x791ffa   01
0x791ffe   0b                InstallDbgToken
0x792002   01
```

It then obtains the token bytes through the record's virtual method `+0x10`,
appends them to the request, submits the request through the wrapped device
transport, and returns the device response byte. Therefore, for this installer
branch, the CLI-to-legacy-VDM-`0x0b` route is **PROVED**. It is not the current
public NSM-v2 chunk protocol.

## 2. CLI `--activatetoken`: distinct operation, HULK NVDM request proved

The command-line branch calls secondary-interface slot `+0x498`. On vptr
`0xcfca78` this is:

```text
0xcfca78 + 0x498 = 0xcfcf10 -> 0x589b30
```

`0x589b30` accepts chip-family selectors `0x1a`, `0x1b`, or `0x1c`, obtains a
device wrapper via `0x794d4a`, then invokes wrapper slot `+0x90`.

The interface adjustment matters:

```text
0x793832   primary vptr = 0xd360c8
0x793839   secondary vptr at object+0x30 = 0xd36220
0xd360a0   vptr[-0x28] = 0x30
0x794e61..0x794e68   return object+0x30
0xd36220 + 0x90 = 0xd362b0 -> 0x795f2e -> 0x795e26
```

`0x795e26` constructs the exact request header/payload:

```text
0x795e32   byte 0  = 0x7e
0x795e36   bytes 1..2 = 0x10de       NVIDIA PCI vendor ID
0x795e3c   byte 3  = 0x11
0x795e40   bytes 4..7 = 0x00000000
```

It sends through `0x797110`, which checks message type `0x7e`, vendor `0x10de`,
matching response command/type byte, and response status at `reply+0x0c`.
NVFlash prints either:

```text
Debug token has been successfully activated.
Debug token cannot be activated. Please use --getfwlog to check DMEM logs...
```

Independent GSP disassembly closes the semantic identity. The
`RmActivateHulk` default/flashed-token path at `0x01510108..0x0151013a` sends:

```text
NVDM type = 0x11
length    = 4
payload   = u32 0
```

That is byte-for-byte the payload generated by NVFlash activation after the
outer NVIDIA VDM header. Therefore the strongest supported interpretation is:

```text
--activatetoken -> activate/process an already installed HULK token
                -> FSP HULK NVDM type 0x11, zero/default packet
```

This proves a two-stage device flow: installation/staging and activation are
separate operations. It still does not prove what authorization features the
installed token grants.

## 3. MODS FSP use-case name and protocol-layer separation

MODS contains a host-side FSP use-case formatter at `0x1857e50`. Its dispatch
maps use-case byte `0x80` to the literal `LoadHulk`:

```text
0x1857e98  cmp dl, 0x80
0x1857e9d  mov esi, 0x90fa54c     ; "LoadHulk"
```

This is a different layer of numbering:

```text
host FSP use case 0x80 "LoadHulk"
    -> device NVDM type 0x11 "HULK"
    -> zero/default packet or size-prefixed certificate payload
```

Do not equate use-case code `0x80`, NVDM type `0x11`, and payload value zero as
one flat enum.

The same MODS binary independently maps protocol command `0x0c` to
`DebugTokenErase`, `0x0f` to `DebugTokenQuery`, and `0x09` to
`BackgroundCopy` at `0x1857f90`. These names confirm adjacent command
vocabulary, not a public token signer.

## 4. Legacy NVIDIA VDM token installer and public definition agree

Public NVIDIA `mctp_vdm_utils.py` defines:

```text
InstallDbgToken       = 0x0b
EraseDbgToken         = 0x0c
QueryDbgTokenStatus   = 0x0f
```

Its `DebugTokenInstallHandler` reads the token file's 16-byte outer package
header, then submits a complete legacy token record in an NVIDIA vendor-defined
request. The public handler currently assumes a 264-byte record; that fixed
length must not be generalized to every NVFlash token format.

NVFlash's `0x791fca` implementation uses NVIDIA IANA 5703 (`0x1647`), command
`0x0b`, version 1. The wrapper proof in section 1 establishes that the
`0x1a`/`0x1b`/`0x1c` install branch actually invokes it; this is stronger than
the mere presence of an otherwise unreferenced encoder.

## 5. Current NSM v2 is a separate protocol-generation comparison

Current public NVIDIA `nsmd`/`nvidia-code-mgmt` uses NSM Diagnostic message type
4 and commands Install/Erase/Query Token. Its v2 install request carries:

```text
u32le chunk_offset
u32le chunk_length
u32le length_remaining
u8     token_data[chunk_length]
```

Current code routes a signed, caller-supplied token blob through D-Bus/nsmd to
the device and queries processing status separately. It does not expose an
independent HULK signer or private key.

NVFlash 5.877 also contains an older NSM wrapper whose common envelope uses a
legacy one-byte payload size (`0x79be90`, framing byte `0x89`). That wrapper must
not be described as the current NSM v2 common-request/chunk format. No proven
CLI edge from `--installtoken` to that particular wrapper has been established.

## 6. Device-side validation boundary

The binary's token status/reason handling recognizes failures for signature,
nonce/expiry, lifecycle, token type, device storage, ratchet/version, firmware
compatibility, serial number, PSID, security policy, and hash verification.
Therefore a correctly shaped blob is not sufficient; the device firmware makes
the acceptance decision.

For the L2/PRC question:

- **PROVED:** `--activatetoken` reaches FSP's HULK NVDM activation/default path.
- **PROVED:** install and activate are distinct operations: install uses legacy
  VDM `InstallDbgToken` `0x0b`; activation uses HULK NVDM `0x11` with a zero
  payload.
- **PROVED:** NVIDIA tooling knows HardwareUnlock/`PrcKnobEn` token vocabulary.
- **NOT PROVED:** the required GB202 token exists publicly or that it can be
  generated locally.
- **NOT PROVED:** `PrcKnobEn` or HULK is necessary or sufficient for PRC object
  `0x1d`, L2-slice floorsweeping, or registers `0x008200f8/0x008200dc`.
- **NOT PROVED:** the earlier PRC error `0x1e4` was caused by a missing token.

## 7. Runtime-attempt boundary

An earlier invocation with a public sample failed during `/dev/mem` mapping
with `EPERM`. It produced no observed device submission and no state change.
That failure cannot determine whether host-side parsing had already started,
or whether the device would accept/reject the token. The concrete install
backend above was established by static call-chain closure, not by this failed
runtime attempt.

## 8. GB202 applicability of the `0x1b` branch

This branch is directly relevant to GB202 rather than merely adjacent
Blackwell code. NVIDIA's published RM headers define:

```text
NV_PMC_BOOT_42_ARCHITECTURE_GB100 = 0x1a
NV_PMC_BOOT_42_ARCHITECTURE_GB200 = 0x1b
```

The generated architecture/implementation table maps
`GB200 + IMPLEMENTATION_2` to `GB202`:

```text
driver_gpio_internal_610.43.03/src/common/inc/swref/published/nv_ref.h
driver_gpio_internal_610.43.03/src/nvidia/generated/g_hal_archimpl.h
```

NVFlash's installer explicitly accepts the architecture value `0x1b` at
`0x5d6177..0x5d617a`. Thus the proved legacy-VDM install path covers the GB202
architecture family. This is protocol applicability, not evidence that a
particular retail `10de:2b85` token exists or would pass firmware validation.

## 9. GB202 `--querytoken`: extended legacy-VDM status response

The same architecture dispatch gives `0x1a`, `0x1b`, and `0x1c` an extended
query path. At `0x59e85b..0x59e8d6`, these architectures obtain the same outer
wrapper through `0x78f4ac` and call wrapper slot `+0xb8`:

```text
0xd35aa0 + 0xb8 = 0xd35b58 -> 0x78ffb0
```

`0x78ffb0` constructs a nine-byte NVIDIA IANA request with no additional
payload:

```text
7f 47 16 00 00 80 01 0f 02
|  |-----------| |  |  |  `- request/version byte 2
|  | IANA 0x1647 |  |  `---- QueryDbgTokenStatus command 0x0f
|  |              |  `------- request bit/type byte 1
|  |              `---------- 0x80
|  `------------------------- NVIDIA IANA, little-endian
`---------------------------- MCTP VDM message type
```

The response completion code is byte `+0x09`. Completion code `5` is handled
as “query status is not supported”; other nonzero values are printed as the
device completion code. A success response whose complete vector length is
exactly `0x26` bytes has a 28-byte payload at response offset `+0x0a`; the
function copies that payload into its result and sets a separate
`extended-fields-valid` Boolean. A shorter compatible response copies only the
first 16 payload bytes and leaves that Boolean clear.

The CLI at `0x59e89c..0x59edcb` proves the meanings of the first 20 payload
bytes:

| Payload offset | Width | CLI / MODS meaning |
|---:|---:|---|
| `0x00` | 1 | token status: installed/non-installed |
| `0x01` | 8 | device identifier / serial number |
| `0x09` | 1 | firmware fuse: `1=Debug`, otherwise `Prod` in this formatter |
| `0x0a` | 4 | token type |
| `0x0e` | 2 | CLI “Validity Counter”; MODS JS calls the same concept `usageCounter` |
| `0x10` | 2 | token configuration bitmap |
| `0x12` | 2 | processing status |
| `0x14` | 8 | copied by the backend but not rendered by this CLI path; semantic meaning unknown |

The token-type jump table at `0xcf2808` maps the consecutive enum values:

```text
0x00  NO_TOKEN
0x01  DEBUG_FW_UNLOCK
0x02  JTAG_UNLOCK
0x03  HW_UNLOCK
0x04  RUNTIME_DEBUG_UNLOCK
0x05  FEATURE_UNLOCK
```

Values `0x06..0x10` and values greater than `0x10` render as
`UNKNOWN_TOKEN_TYPE`; this is an enum, not a feature bitmap.

MODS' decoded `prntutil.js` independently renders `tokenStatus`, `tokenType`,
`usageCounter`, `config`, and `processStatus`. It documents configuration bits
for temporary/persistent, manual/automatic processing, and several enable or
mandate policies; process status values are rendered as not processed,
processed, verification failure, runtime error, or unknown.

This closes an important observation boundary but not the authorization
content. The query result reports a broad token type such as `HW_UNLOCK`; it
does **not** expose the HardwareUnlock subtype/feature bitmap. Therefore
`--querytoken` alone cannot show whether a token contains `PrcKnobEn`,
`NvlinkGlobalHulk`, `PxucGlobalHulk`, or any L2/floorsweeping permission.

## 10. Legacy token-file container and record path

The file parser at `0x437ea0` reads a fixed 16-byte outer header and requires
the header's `u16` at file offset `+0x04` to equal `0x10`. Header byte `+0x01`
must be 1 or 2; value 2 reaches the legacy debug-record parser. Header byte
`+0x00` selects whether a per-record length is read as `u16` or `u32`, and the
`u16` at `+0x02` is consumed as the record count. These are observed parser
roles; the static code does not provide authoritative names such as “magic” or
“version” for every header field.

For legacy records, `0x4374ee` accepts three first-dword tags:

```text
0x49445447    bytes 47 54 44 49
0x49544449    bytes 49 44 44 49
0x49544445    bytes 45 44 54 49
```

It constructs a record with vptr `0xc84a68`; TLV1 uses a separate parser
branch. The record deserializer at `0x43ee1a` consumes a fixed `0x74`-byte
region, two `u16`-sized variable regions, and a fixed `0x60`-byte tail. The
serializer at `0x43ec30` proves the total serialized size is
`0xd8 + len1 + len2` and emits the complete record.

The GB202 installer uses three methods of this exact record object:

```text
record +0x10 = 0x43ec30   serialize the complete record to bytes
record +0x80 = 0x43eb2a   return Token Attributes u16 at object+0x26
record +0xa0 = 0x43eb94   return FW Version u32 at object+0x2c
record +0xa8 = 0x43ebfe   return Device Identifier u64 at object+0x40
```

If flag bit `0x8` is clear, the installer compares the record identity with the
current GPU's eight-byte identity before submission. At `0x791fca`, method
`+0x10` supplies the complete serialized record appended behind VDM command
`0x0b`. Thus the outer file header is host-side packaging; the serialized
record is the device-submitted authorization object.

The static parser alone does not prove that the fixed `0x60`-byte tail is a
signature, nor what bytes a signature covers. Those semantics remain unknown
until a validation/printing caller or firmware parser supplies names.

The record's own print method `0x43f102` and its accessors provide a stronger
field map. Object offsets convert to serialized offsets by subtracting `0x1c`:

| Object offset | Serialized offset | Width | Proved meaning |
|---:|---:|---:|---|
| `0x24` | `0x08` | 2 | total record length |
| `0x26` | `0x0a` | 2 | Token Attributes; GB202 installer tests bit `0x8` |
| `0x2c` | `0x10` | 4 | FW Version |
| `0x30` | `0x14` | 16 | Nonce |
| `0x40` | `0x24` | 8 | Device Identifier |
| `0x48` | `0x2c` | 4 | Token Type |
| `0x4c` | `0x30` | 2 | Life Cycle State |
| `0x4e` | `0x32` | 2 | Validity Counter |

When Token Attributes bit `0x8` is clear, the GB202 installer requires the
record Device Identifier to equal the current GPU's byte-reversed eight-byte
identifier before it submits the record. The named fields prove identity,
lifecycle, validity, nonce, and firmware-version binding material exists in the
record format; they do not prove which fields are mandatory for every token or
what a particular signer covers.

The remaining fixed bytes, both variable regions, and the 96-byte tail do not
receive HardwareUnlock subtype/feature-mask, PSID, serial-number, or signature
names in this record class. In particular, the legacy record parser still does
not reveal where a `PrcKnobEn` feature bit would reside.

## 11. Public signer boundary: no local signing path established

The public NVIDIA `nvidia-code-mgmt` Debug Token updater provides an independent
first-party boundary for the install workflow.  Its `nsmTokenInstallV2()` selects
an already-supplied token by the endpoint's `TokenDeviceID`, writes those bytes
unchanged to a `memfd`, and passes that file descriptor to the NSM `InstallToken`
action.  It contains no token-signing operation.  Its device-error registry maps
both `InvalidToken` and `TokenAuthFailed` to the instruction:

```text
Check Debug Token is valid and signed by NVIDIA. Request the debug token again.
```

Audited source inputs:

| Artifact | SHA-256 | Relevant evidence |
|---|---|---|
| `nvidia-code-mgmt/debug_token/update_debug_token.hpp` | `c8c89c010bdd331524eb9e086cda23d80035e8c81fb1fb17b3102fb8bb2786fa` | `InvalidToken` / `TokenAuthFailed` require an NVIDIA-signed token |
| `nvidia-code-mgmt/debug_token/nsm_debug_token.cpp` | `231c7ca1574e61e2d57cec73f4ef7a97836aa05494c2c367e5356efdffff21a4` | chooses by `TokenDeviceID` and transfers supplied bytes; no signer |

The source is NVIDIA's public `nvidia-code-mgmt` repository, inspected at commit
`49a3a1d1423b68d66617ca0175d6ebb197387e6c` (2026-06-09).  This code services
BMC/NSM Debug Tokens and is not, by itself, the GB202 FSP verifier.  It is
therefore corroboration of the production workflow—not proof of the GPU
signature algorithm or key hierarchy.

`OpenSMA` separately defines a modern `TLV1` vocabulary containing
`NvidiaSignature` (tag `0x000b`), `OemSignature` (`0x000c`), certificate-chain,
device-ID, lifecycle, validity, type/subtype-list, payload, and legacy-token
fields.  Its MCU-token verifier hashes the header and all TLVs except the
NVIDIA-signature TLV, then verifies a P-384 ECDSA signature against an embedded
public key.  That is useful evidence that NVIDIA uses signed, identity-bound
TLV tokens, but **must not be projected onto the GPU legacy record**: the GPU
record's signature field, covered bytes, algorithm, and public-key source are
still not statically established here.

**PROVED:** NVFlash 5.877 can package, identity-match, and submit a legacy
Debug Token to the GB202-family VDM install endpoint, then activate HULK by a
separate request.  NVIDIA's public updater treats token signing as external to
the installer and explicitly requires an NVIDIA-signed token on authentication
failure.

**NOT FOUND:** a GB202/`10de:2b85` signed token, a target-compatible HULK,
NVIDIA/OEM signing private key, or a local NVFlash/MODS signing routine.

**NOT PROVED:** that the public OpenSMA signature procedure is the GPU's
procedure, that any unsigned synthetic legacy record could be accepted, or that
`PrcKnobEn` is necessary/sufficient for the observed PRC/L2 operation.
