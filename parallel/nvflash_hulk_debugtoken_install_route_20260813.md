# NVFlash 5.877 HULK / Debug Token install-route boundary

Date: 2026-08-13

Scope: offline strings/help and public NSM structure comparison only. Neither
updater was executed; no token, license, GPU storage, firmware, BAR, reset, or
flash operation was performed.

## Short answer

NVFlash 5.877 contains two different device-provisioning families:

```text
HULK/InfoROM: --wrhlk, --rdhlk, --rmhlk, --licflash, --license
Debug Token:  --dbgtokenrequest, --installtoken, --activatetoken,
              --querytoken, --erasetoken, --aggregatetoken
```

The first stores/uses HULK/HLK license objects. The second stages a signed Debug
Token on the device and activates a device-side debug authorization session.
They are not aliases.

## 1. HULK/HLK path

Version-5.877 help strings say:

```text
--rdhlk <filename>     Read HULK license file object to file.
--wrhlk <filename>     Install unlock license into EEPROM.
--rmhlk                Remove HULK license object.
--licflash <file.lic>  Install unlock license objects.
--license <filename>   Provide a HULK/license file for the current operation.
```

Therefore `--wrhlk` is a persistent provisioning operation aimed at the GPU's
EEPROM/InfoROM license-object storage. `--license` can be a transient input to
the current flash/update operation and must not be assumed to persist.

MODS' `-activate_hulk` help independently describes activating a HULK license
with a token already flashed to EEPROM. Its `-hulk_cert` path instead supplies
an in-memory certificate buffer to RM/MODS for delivery.

Device-side HULK verification remains the trust decision: RM/GSP/MODS transports
the object; FWSECLIC/FWSEC/SEC2/FSP (architecture-dependent) validates the
signature and identity/policy and performs the licensed action. The exact GB202
consumer path is not reduced to a single publicly named firmware module, but it
is not host-side command-line trust.

## 2. Debug Token path

The exact command names present in both HPE and Dell 5.877 binaries are:

```text
querytoken
dbgtokenrequest
installtoken
erasetoken
activatetoken
aggregatetoken
```

Visible examples include:

```text
--dbgtokenrequest dbg_token_request.bin
--installtoken <TOKEN>.bin
--aggregatetoken <directory>
```

The intended workflow is:

```text
GPU/device generates request + fresh identity/state/challenge
  -> external NVIDIA/OEM signing service returns signed token
  -> nvflash --installtoken sends the token to device-side storage
  -> nvflash --activatetoken asks device firmware to activate it
  -> --querytoken reports installed/active state
  -> MODS QueryDebugToken can observe the resulting state
```

The updater's own device-returned failures prove the verifier checks at least:

```text
signature
nonce / expiry
device serial number
chip lifecycle / fuse state
firmware version compatibility
token format/version/authentication
```

It also prints `Failed to write debug token to device storage`, so the install
target is device-side storage/staging, not a host configuration file. The exact
physical medium and lifetime are not established by that string alone.

The 5.877 static call chain is now closed for the installer branch used for
chip-family selectors `0x1a`/`0x1b`/`0x1c`:

```text
--installtoken
  -> 0x57dd39 / 0x57d8e2
  -> per-device installer 0x5d6040
  -> match token record against current device's eight-byte identity
  -> type-id-3 wrapper 0x78f4ac, vptr 0xd35aa0
  -> wrapper +0xa0 = 0x791fca
  -> NVIDIA legacy VDM, IANA 0x1647, InstallDbgToken command 0x0b
```

The separately closed activation chain is:

```text
--activatetoken
  -> 0x589b30
  -> 0x795e26
  -> NVIDIA NVDM type 0x11, length 4, payload u32 0
  -> same packet shape as GSP RmActivateHulk's flashed/default-token path
```

Thus the evidence supports a concrete two-stage flow: install a signed token
through legacy Debug Token VDM `0x0b`, then ask FSP to activate/process the
already-installed HULK object through NVDM `0x11`. This still says nothing by
itself about which feature bits that object grants.

The `0x1b` selector is GB200 architecture in NVIDIA's published RM headers, and
the generated `GB200 + implementation 2` row is GB202. Therefore this static
install branch covers GB202. It does not establish that any public token is
signed for `10de:2b85` or that a retail RTX 5090 would accept one.

NVIDIA's current public NSM header independently defines chunked
`nsm_install_token_req` messages with `chunk_offset`, `chunk_length`,
`length_remaining`, and token data; query/erase/status operations are separate.
The archived header is:

```text
downloads/public_workflow_text/nvbmc_docs/debug_tokens/debug-token.h
SHA-256 1d0626c3a19a30883cbeb5907fca41ae14103505584cae11cc02a3ecb0460b86
```

That NSM-v2 interface is a later protocol-generation comparison. It must not be
assigned to NVFlash 5.877's proved legacy VDM install path.

## 3. “Installed for whom?”

NVFlash is the transport/provisioning client. The signed object is installed
for a trusted GPU/device firmware endpoint to validate and consume. Once
activated, the resulting device-side authorization state can affect hardware
protection policy; host tools such as MODS/RM only observe or exercise the
newly permitted path.

For `PrcKnobEn`, the public material does not yet identify the exact final
consumer or prove that activation changes PRC object `0x1d`, `0x8200f8`, or L2
floorsweeping. FSP is a strong architectural candidate on Blackwell, but the
current nvflash call chain has not closed that attribution to one firmware
component.

## Fixed updater samples

| File | Version | SHA-256 |
|---|---|---|
| HPE `nvflash` | 5.877.0 | `d1aee0b0309475826b15bb8c31624d11a80e0e6d568bea6144be7e213df44780` |
| Dell RTX PRO 6000 updater | 5.877.0 | `6e1ccf97addee26c3c836cc4c87b4fdd0151cf78edb4df921b35338479e6ab61` |

## Boundary

These binaries prove that request/install/activate/query machinery exists and
close the host-side install/activate transports. They do not provide a signed
`PrcKnobEn` token, a signer/private key, a successful 2b85 install log, or proof
that such a token authorizes L2/PRC object `0x1d` on retail GB202.
