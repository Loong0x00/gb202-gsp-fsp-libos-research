# MODS 570.151 HULK / Debug Token frontend interface audit

Date: 2026-08-13

Scope: decoded JavaScript/SPC frontend plus offline ELF strings/xrefs only. MODS
was not executed; no GPU, FSP, BAR, token, certificate, reset, or flash action
was performed.

## Short result

MODS has a direct **submit an already-signed HULK object** interface:

```text
-hulk_cert <file.js|file.hulk>
```

The frontend reads the bytes and calls `Gpu.SetHulkCert(binary, length)`; the
native binding advertises `Gpu.SetHulkCertificate(binary, length)`. This is an
object loader/delivery path, not a request generator or signer.

For GPU Debug Tokens, the visible MODS frontend exposes only
`GpuSubdevice.QueryDebugToken(outputObject)`. No decoded JS argument/method or
native usage string for installing, generating, requesting, loading, or writing
a Debug Token was found. `DebugTokenErase` and `DebugTokenQuery` occur as
protocol command-name formatters, but only `QueryDebugToken` is registered as a
visible JS method in the inspected frontend.

## 1. Command-line HULK inputs

Decoded `gpuargs.js` registers:

```text
stop_init_after_hulk     -> Gpu.StopInitAfterHulk
hulk_cert <filename>     -> ArgHandleHulk(filename)
verify_hulk_with_xml <s> -> Gpu.HulkXmlCertArg
hulk_disable_features n  -> g_HulkDisableFeatures
ignore_hulk_errors       -> g_HulkIgnoreErrors=true
load_hulk_via_mods       -> g_LoadHulkViaMods=true
skip_hulk_if_revoked     -> g_SkipHulkIfRevoked=true
activate_hulk            -> Registry.ResourceManager.RmActivateHulk=true
```

Adjacent input:

```text
psdl_cert <filename>     -> ArgHandlePsdl(filename)
```

`activate_hulk` does not upload a key: its own help says it activates a HULK
license using a token already flashed to EEPROM.

## 2. Exact `hulk_cert` file handling

`ArgHandleHulk`:

1. uses the supplied path, or falls back to `$HULK_DIR/<filename>`;
2. for `.js`, imports the file and reads global `g_hulk_cert`;
3. for `.hulk`, opens it as binary and calls `ReadBinary()`;
4. rejects every other extension;
5. saves the bytes and length in `g_HulkCert/g_HulkCertLength`.

Later initialization performs:

```javascript
Gpu.SetHulkCert(g_HulkCert, g_HulkCertLength);
Gpu.HulkDisableFeatures = g_HulkDisableFeatures;
Gpu.HulkIgnoreErrors    = g_HulkIgnoreErrors;
Gpu.LoadHulkViaMods     = g_LoadHulkViaMods;
Gpu.SkipHulkIfRevoked   = g_SkipHulkIfRevoked;
```

The corresponding ELF usage string is:

```text
Usage: Gpu.SetHulkCertificate(binary, length)
```

SPC examples use precisely this frontend:

```text
g_HULK_license = "HULK_figueroa_2685.js"
AddToSpecArgs("-hulk_cert " + g_HULK_license)
```

and, for PG504SKU200:

```text
g_HULK_license = "HULK_figueroa_3414.js"
g_HULK_memrepair_license = "HULK_figueroa_3415.js"
AddToSpecArgs("-hulk_cert " + g_HULK_license)
```

The normal SPC line passes only the ordinary license; the memrepair variable is
not automatically substituted into that invocation.

## 3. Debug Token frontend

Decoded `prntutil.js` calls only:

```javascript
subdev.QueryDebugToken(debugToken)
```

and renders returned fields:

```text
tokenStatus
tokenType
usageCounter
config
processStatus
```

The native registered method has usage:

```text
Usage: GpuSubdevice.QueryDebugToken(pTokenStatus)
```

The decoded JS tree has no Debug Token install/generate/request/write method.
The only broad-regex false positive is the display string `Installed` returned
after a successful query. The native strings likewise have no
install/generate/request/activate/load/set/write Debug Token command.

The ELF contains `DebugTokenErase` and `DebugTokenQuery` in a protocol
command-code-to-name formatter (`0x1857f90`): command `0x0c` prints
`DebugTokenErase`, and command `0x0f` prints `DebugTokenQuery`. This proves the
underlying protocol vocabulary, not a user-facing MODS submission API.

## 4. What this means

**PROVED**

- MODS accepts an existing `.hulk` binary or JS-wrapped HULK payload.
- MODS forwards the byte buffer through its HULK loading path and can choose
  MODS-side loading instead of RM-side loading.
- MODS can inspect status/configuration of an already present GPU Debug Token.
- MODS can request activation of an EEPROM-flashed HULK token.

**NOT FOUND**

- a MODS command to create `LicenseRequest.bin` or an equivalent Debug Token
  request;
- a MODS command to install a `PrcKnobEn`/HardwareUnlock token image;
- a local signer/key-generation path;
- a mapping from queried `tokenType` to PRC object `0x1d` or L2.

Therefore `-hulk_cert` is the simple submission interface for a signed HULK
object. If the needed authorization is instead a Unified HardwareUnlock Debug
Token, the inspected MODS frontend appears to assume that it was provisioned by
another tool/path and only queries it.

## Fixed files

| File | SHA-256 |
|---|---|
| `mods_audit/static/extracted_inner/mods` | `c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf` |
| `mods_audit/static/decoded/all/gpuargs.js` | `14b37e0792addab7c5eb770509bfd85bd59553de2e076a2a8637a0d812397c16` |
| `mods_audit/static/decoded/all/prntutil.js` | `c5ca510d4ce61e0fd347dd195856253005fb7f5194e0dae4708f2bfe7c93d2d7` |
| `mods_audit/static/decoded/all/mathslink_args.js` | `6ccad03f5199254d1e8ac2f2cff0250a83b745fdd2a6e09a5857c9357233b3de` |
| `mods_audit/static/decoded/all/mathslink_guts.js` | `6c2f75129f27ae75811382446aac9f20b1322e7f7ab69d6ab2793d7c711cc670` |
