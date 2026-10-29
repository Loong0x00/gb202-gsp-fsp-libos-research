# GB202 HULK / Debug Token / PRC knob gate follow-up

Date: 2026-07-23

Scope: static/local inspection only.  No MODS/nvflash/updater execution, no GPU
MMIO/BAR writes, no reset.

## Short conclusion

The current evidence says the blocked L2 path is probably not missing a raw
register address.  One concrete authorization lead is an older HardwareUnlock
subtype bit:

```text
HardwareUnlock subtype 0x00020000 -> prc_knob_en
```

That bit name appears in NVIDIA host tools (`nvflash` / Dell updater), not in the
GSP image itself.  This fits the live result where direct PRC transport reaches
FSP but a write attempt returns:

```text
0x000001e4 = PRC_ERROR_PERSISTENCE_NOT_SUPPORTED
```

Later NVIDIA Nova documentation proves that the observed request used only the
`ACTIVE` flag, not the `PERSISTENT` flag.  Therefore the error name proves what
FSP returned, but does not prove that persistence was requested or that the
failure was caused by a missing HULK/Debug Token.  The visible authorization
vocabulary nevertheless includes `prc_knob_en`.

This does not prove that enabling `prc_knob_en` is sufficient to open GB202 L2
floorsweep bits.  It does prove that NVIDIA tooling has an explicit feature name
for PRC knob enablement, and that the older updater places it in the
HardwareUnlock Debug Token family.

## GSP HULK input path

Target image:

```text
/tmp/gsp_inner_19f040_a.elf
size: 79 MiB
file type: data
RISC-V base used for this audit: 0x01000000
```

Relevant strings:

```text
file off 0x0e77698 -> RmActivateHulk
file off 0x0e776a8 -> RMHulkCertSize
file off 0x0e776b8 -> RMHulkCert
file off 0x0e878f0 -> RmDisableFwseclic
file off 0x0e87950 -> RmHulkDisableFeatures
file off 0x0e87968 -> RmIgnoreHulkErrors
```

### Config load

At `0x0150f2da..0x0150f32c`, GSP clears local HULK state and reads
`RmActivateHulk`, then `RMHulkCertSize`.

Key instructions:

```text
0x0150f2da: sb       zero, 0x2e8(s1)
0x0150f2de: sw       zero, 0x2ec(s1)
0x0150f2e2: sd       zero, 0x2f0(s1)
0x0150f2ea: auipc    a1, 0x968
0x0150f2ee: addi     a1, a1, 0x3ae      ; RmActivateHulk
...
0x0150f310: auipc    a1, 0x968
0x0150f314: addi     a1, a1, 0x398      ; RMHulkCertSize
...
0x0150f328: lw       a1, 0x2ec(s1)
0x0150f32c: bnez     a1, 0x2a2
```

### External certificate buffer

At `0x0150f5d0..0x0150f61e`, GSP allocates `cert_size + 4`, zeroes it, writes the
size dword at the front, then reads `RMHulkCert` into `buffer + 4`.

Key instructions:

```text
0x0150f5d2: c.addi   a1, 4              ; allocation size = cert_size + 4
0x0150f5dc: auipc    ra, 0x3b2          ; allocator call
0x0150f5e4: sd       a0, 0x2f0(s1)      ; cert buffer pointer
...
0x0150f5f4: auipc    ra, 0x6d2          ; memset-like call
...
0x0150f60e: c.sw     a4, 0(a5)          ; first dword = cert_size
0x0150f610: ld       a1, 0x2f0(s1)
0x0150f614: c.addi   a1, 4              ; destination = buffer + 4
0x0150f606: auipc    a0, 0x968
0x0150f60a: addi     a0, a0, 0xb2       ; RMHulkCert
```

So the external HULK payload shape visible to GSP is:

```text
u32 cert_size
u8  cert_bytes[cert_size]
```

### HULK NVDM send

At `0x0150ef4c..0x0150ef68`, if the cert size and pointer are nonzero, GSP sends
the size-prefixed blob as FSP NVDM type `0x11`.

```text
0x0150ef4c: lw       a3, 0x2ec(s1)      ; cert_size
0x0150ef52: ld       a2, 0x2f0(s1)      ; cert_buffer
0x0150ef58: c.li     a6, 0
0x0150ef5a: c.li     a5, 0
0x0150ef5c: c.li     a4, 0x11           ; HULK NVDM type
0x0150ef5e: c.addiw  a3, 4              ; payload length = cert_size + 4
0x0150ef64: auipc    ra, 0
0x0150ef68: jalr     ra, ra, -0x64c     ; sender at 0x0150e918
```

There is also a flashed-token/default path at `0x01510108..0x0151013a`:

```text
0x0151011c: c.li     a6, 0
0x0151011e: c.li     a5, 0
0x01510120: c.li     a4, 0x11
0x01510122: c.li     a3, 4
0x01510124: addi     a2, s0, -0x2c
0x01510132: sw       zero, -0x2c(s0)    ; 4-byte zero payload
0x01510136: auipc    ra, 0xffffe
0x0151013a: jalr     ra, ra, 0x7e2      ; sender at 0x0150e918
```

Fact: this confirms GSP passes HULK material to FSP as NVDM type `0x11`.

Inference: the GSP side is not doing a literal `0x8200f8` write in this path.
The register operation, if any, is inside the FSP/FWSECLIC/HULK handler after it
accepts the payload.

## Debug-token vocabulary in nvflash/updater

Target host tools:

```text
/home/user/rt_5090_project/vbios_diff/hpe_static_tools/nvflash
  ELF64 x86-64, stripped, 16 MiB

/home/user/rt_5090_project/vbios_diff/dell_8d_payload/RTXPRO6000_98.02.8D.00.01_FW_upgrade.bin
  ELF64 x86-64, stripped, 96 MiB
```

The two tools contain the same debug-token string cluster.  HPE offsets:

```text
0x008ea3b8 debug_fw_unlock
0x008ea3de runtime_debug_unlock
0x008ea3f3 feature_unlock
0x008ea54b bar0_decoupler_unlock
0x008ea580 nvlink_global_hulk
0x008ea5c7 prc_knob_en
```

Dell offsets:

```text
0x008f33b8 debug_fw_unlock
0x008f33de runtime_debug_unlock
0x008f33f3 feature_unlock
0x008f354b bar0_decoupler_unlock
0x008f3580 nvlink_global_hulk
0x008f35c7 prc_knob_en
```

HPE `nvflash` maps token type ids as follows:

```text
type 0x01 -> debug_fw_unlock
type 0x02 -> jtag_unlock
type 0x04 -> hw_unlock
type 0x08 -> runtime_debug_unlock
type 0x10 -> feature_unlock
```

The type dispatcher at `0x52c381` selects the following branch for token type
`0x04` (`hw_unlock`).  In both binaries, `0x52c566` compares the subtype in
`esi` with `0x00020000` and returns `prc_knob_en` at `0x52c6bf`:

```text
0x00000001 -> memqual
0x00000002 -> global_functional_debug
0x00000004 -> speedo_kappa_iddq
0x00000008 -> ecc_enable
0x00000010 -> reduced_global_functional_debug
0x00000020 -> ssg_debug
0x00000040 -> inband_recovery
0x00000080 -> arch_functional_tests
0x00000100 -> ecc_unlock
0x00000200 -> ssg_host2jtag
0x00000400 -> bar0_decoupler_unlock
0x00000800 -> i2cc_access
0x00001000 -> ecc_poison_disable
0x00002000 -> nvlink_global_hulk
0x00004000 -> xbar_debug
0x00008000 -> lower_rom_protection
0x00010000 -> recreate_inforom_rw
0x00020000 -> prc_knob_en
0x00040000 -> sm_speed_select_throttle
0x00080000 -> mse_trex_traffic_en
```

The caller at `0x440959..0x440975` loads the token type from structure offset
`+0x20` into `edi`, loads one subtype-mask value into `esi`, then calls
`0x52c381`.  This closes the type/subtype dispatch: the mapping above is the
older updater's HardwareUnlock table, not its type-`0x10` FeatureUnlock table.

Important boundary: these mappings are only used to print/serialize parsed
token request/token information.  They do not contain a local way to manufacture
an accepted token.  Current NVIDIA `nsmd` also calls `PrcKnobEn` a
HardwareUnlock subtype, but assigns it `0x00001000`; no public source provides a
wire-level conversion between the two mask generations.

## Token request fields

The host tools know the following token-request fields:

```text
ChallengeNonce
DeviceSerialNumber
DeviceSerialNumberArray
FirmwareVersion
AgentVersion
LifecycleState
TokenConfig
NvidiaSignature
OemSignature
InstallStatus
ProcessingStatus
SkuInformation
NvidiaRatchet
OemRatchet
ValidityCounter
CertificateChain
MeasurementTranscript
DeviceId
TokenTypeSubtypeList
Payload
LegacyToken
UnitFeatureMask
ChipId
KeypairUUID
PSID
```

The install error strings include:

```text
Signature verification failed
Nonce is invalid or expired
Token lifecycle state does not match device state
Token version is older than the device ratchet value
Token does not match this device serial number
Token does not match this device PSID
Debug token feature is disabled due to security restrictions
Debug token is not compatible with the current firmware version
```

Fact: token acceptance is bound to nonce/serial/PSID/lifecycle/ratchet/firmware
state, not just a filename or board-name check.

Inference: a random or old token blob, even for a similar GPU, is very unlikely
to activate on the user's GB202 retail card.

## Command-handler boundary in nvflash

The command description table contains these debug-token commands:

```text
dbgtokenrequest  <filename>  Download signed transcript for Debug Token request
installtoken     <TOKEN>.bin Install Debug Token
erasetoken       [revoke]    Erase Debug Token
querytoken       [filename]  Query Debug Token information on device/file
activatetoken               Activate Installed Debug Token
aggregatetoken   <directory> Concatenate token binaries in the directory
```

The string references show the parser/handler block around
`0x0091eb83..0x0091fd5d`.

Observed static boundaries:

```text
0x0091eb83...  dbgtokenrequest branch
  parses dbgtokenrequest <filename>
  calls device/vtable path to collect token request/transcript
  writes returned buffer to the named output file

0x0091efad...  installtoken branch
  parses installtoken <TOKEN>.bin
  reads/parses token file
  checks file object type == debug token
  calls device/vtable path to install/process token

0x0091fb11...  activatetoken branch
  parses activatetoken
  calls device/vtable path, then host-side status/reporting path
```

The debug-token install status formatter is at `0x0079b646`.  It handles a
`status - 0x1000` switch:

```text
0x1000 -> unexpected internal processing error
0x1001 -> token format invalid/corrupted
0x1002 -> signature verification failed
0x1003 -> nonce invalid/expired
0x1004 -> token lifecycle state does not match device state
0x1005 -> token type not supported on this device
0x1006 -> failed to write token to device storage
0x1007 -> token version older than device ratchet value
0x1008 -> device internal processing error
0x1009 -> debug token feature disabled on the device
0x100a -> debug token feature disabled due to security restrictions
0x100b -> token incompatible with current firmware version
0x100c -> token does not match device serial number
0x100d -> token does not match device PSID
0x100e -> token already installed
0x100f -> no token installed
0x1010 -> hash verification failed during processing
```

Fact: these are not plain host-side string checks.  The command branches call
device/vtable methods and then format returned status.  The host binary contains
the vocabulary and file parser, but the acceptance decision is beyond the
command parser.

## MODS contrast

Target:

```text
/home/user/rt_5090_project/mods_audit/static/extracted_inner/mods
size: 392,339,552 bytes
inspection: strings-only / no execution
```

Relevant hits:

```text
0x08cca11d RMHulkCert
0x08cca128 RMHulkCertSize
0x08cca137 RmHulkDisableFeatures
0x08cd7192 Get HULK Debug Token status
0x08d84235 RmDisableFwseclic
0x08daf9f7 RmActivateHulk
```

Decoded JS arguments also expose:

```text
activate_hulk -> Registry.ResourceManager.RmActivateHulk
  "Activate HULK license with token flashed to EEPROM"

Registry.ResourceManager.RmDisableFwseclic = 1
```

MODS' own RM-style registry path mirrors the GSP evidence:

```text
0x07338978: reads RmActivateHulk
0x073389b6: reads RMHulkCertSize into object +0x2e4
0x07338c2f: allocation size = cert_size + 4
0x07338c7d: first dword of buffer = cert_size
0x07338c67: reads RMHulkCert into buffer + 4
```

So both GSP and MODS use the same visible external shape:

```text
u32 cert_size
u8  cert_bytes[cert_size]
```

MODS contains many HULK/FWSECLIC diagnostic strings, including:

```text
HULK License verification requires -hulk_cert command line argument
Usage: Gpu.SetHulkCertificate(binary, length)
Stop GPU init after processing HULK.
Load HULK via MODS instead of RM
HULK license verification failed
HULK license verification succeeded
extension_HULK_Register_Override
HULK Cert mismatch at Addr:'0x%08x' with Mask:'0x%08x' and Data:'0x%08x'
CERT_HULK_REG_READ_BACK_VERIFY_MISMATCH
CERT_HULK_REG_RMW_RBV_READ_BACK_VERIFY_MISMATCH
CERT_HULK_DEVID_MISMATCH
CERT_HULK_ECID_MISMATCH
PRI_TRANSACTION_ERROR
```

No `prc_knob_en`, `UnitFeatureMask`, `dbgtokenrequest`, `installtoken`, or
`activatetoken` hit was found in this MODS binary through the same strings
filter.

Interpretation:

1. MODS has the HULK certificate / FWSECLIC path and can reason about register
   override payloads.
2. MODS does not appear to include the same debug-token request/install manager
   found in nvflash/updater.
3. If MODS can help this L2 path, it would likely be by loading an already valid
   HULK blob (`-hulk_cert` / `RMHulkCert*`) or by using an EEPROM-flashed token,
   not by locally minting a `prc_knob_en` debug token.

### MODS register-override parser / verifier

Static xrefs in MODS locate the register override parser around
`0x01862e80` and the verifier around `0x01862b88`.

The parser recognizes:

```text
extension_HULK_Register_Override
addr
mask
data
```

The verifier iterates 12-byte records.  In MODS' internal vector layout the
record is:

```text
u32 mask
u32 data
u32 addr
```

The readback check is:

```text
actual   = read32(addr)
observed = actual & ~mask
expected = data   & ~mask
pass     = observed == expected
```

Relevant code window:

```text
0x01862bd8: rdi = GPU/register-access object
0x01862bdb: esi = [record + 8]        ; addr
0x01862be1: call [vtable + 0x220]     ; read32(addr)
0x01862be7: r9d = [record + 0]        ; mask
0x01862bea: r8d = [record + 4]        ; data
0x01862bf1: ebp = ~mask
0x01862bf3: eax = read32(addr) & ~mask
0x01862bf5: ebp = data & ~mask
0x01862bfb: cmp eax, ebp
```

On mismatch it prints:

```text
HULK Cert mismatch at Addr:'0x%08x' with Mask:'0x%08x' and Data:'0x%08x'
(Masked off register value:'0x%08x' does not match expected value:'0x%08x')
HULK license verification failed
```

This confirms that HULK material can describe register effects plus readback
verification.  It still does not provide a valid GB202/2b85 HULK material blob.

### Local FWSECLIC/HULK error-code mapping

MODS also has a formatter for FWSECLIC/HULK errors.  In the inspected xrefs the
string pointer is pushed and the local error value is passed in `r9d`.

Useful HULK-related entries:

```text
0x3b -> CERT_HULK_ECID_MISMATCH
0x41 -> CERT_HULK_DEVID_MISMATCH
0x4a -> VERIFY_ENG_HULK_3AES_SIG_MISMATCH_WITH_GPU_FUSE
0x4e -> CERT_HULK_OPCODE_UNDEFINED
0x4f -> CERT_HULK_REG_READ_BACK_VERIFY_MISMATCH
0x50 -> CERT_HULK_REG_RMW_RBV_READ_BACK_VERIFY_MISMATCH
0x51 -> HULK_INST_IN_SYS_VERIFICATION_FAILED
0x52 -> CERT_HULK_STRICT_ID_DEVID_MISMATCH
0x53 -> CERT_HULK_STRICT_ID_ECID_MISMATCH
0x54 -> PRI_TRANSACTION_ERROR
```

If future FWSECLIC logs expose one of these codes, this table can quickly tell
whether the failure is ID/signature/policy or actual register readback.

## Local artifact search

Constrained local search under `/home/user/Downloads` and
`/home/user/rt_5090_project` found no `Enthusiast.key`, no debug-token binary,
and no GB202/2b85 HULK blob by filename.

Relevant files found are only:

```text
HULK_figueroa_2685.js
HULK_figueroa_2816.js
HULK_figueroa_2817.js
HULK_figueroa_2929.js
HULK_figueroa_3414.js
HULK_figueroa_3415.js
```

Those are old sample HULK scripts already inventoried elsewhere; they do not
target GB202/RTX 5090 device id `0x2b85`.

## Relation to the L2 question

Known live hardware facts from earlier VM tests:

```text
FSP CAPS: HULK NVDM type 0x11 exists, version 1
FSP CAPS: PRC NVDM type 0x13 exists, version 1
Direct PRC read works.
Direct PRC noop write reaches FSP but returns 0x1e4.
Direct BAR0 writes to 0x8200f8/0x8200e0/0x8200f4 do not stick.
Opening 0x8200dc is insufficient for L2 raw/effective mask changes.
```

New interpretation:

1. HULK (`0x11`) is the path for a signed/device-bound action blob.
2. PRC (`0x13`) is present but write-gated.
3. `prc_knob_en` is a real older HardwareUnlock subtype bit (`0x20000`).
4. `bar0_decoupler_unlock` is also a real older HardwareUnlock subtype bit
   (`0x400`), but there
   is no direct evidence yet that it opens `0x8200f8`.
5. `nvlink_global_hulk` explains why previous string searches kept finding
   NVLink-related HULK names.  It does not prove GB202/RTX 5090 has usable NVLink
   hardware.

Practical consequence: the next useful static work is to map the
`dbgtokenrequest/installtoken/activatetoken` command handlers to the exact
device protocol calls, then compare that with the existing FSP NVDM `0x11/0x13`
paths.  Full FSP plaintext extraction remains a poor-return path unless a new
safe post-decrypt readout appears.
