# HSR Project-ID to native Feature 18 bootstrap — CPU/static review

## Decision

There is a real typed Project-ID Vulkan initializer for the owned Vulkan device. For the exact retained Core, it is the private export:

```cpp
NVSDK_NGX_Result __cdecl NVSDK_NGX_VULKAN_Init_ProjectID_Ext(
    const char* projectId,                         // RCX
    NVSDK_NGX_EngineType engineType,               // EDX
    const char* engineVersion,                     // R8
    const wchar_t* applicationDataPath,            // R9
    VkInstance instance,                           // [entry RSP+0x28]
    VkPhysicalDevice physicalDevice,               // [entry RSP+0x30]
    VkDevice device,                               // [entry RSP+0x38]
    PFN_vkGetInstanceProcAddr gipa,                 // [entry RSP+0x40]
    PFN_vkGetDeviceProcAddr gdpa,                   // [entry RSP+0x48]
    NVSDK_NGX_Version sdkVersion,                  // [entry RSP+0x50]
    const NVSDK_NGX_FeatureCommonInfo* featureInfo // [entry RSP+0x58]
);
```

Its exact retained-Core RVA is `0xD7A0`. The no-explicit-dispatch companion at RVA `0xD5D0` is:

```cpp
NVSDK_NGX_Result __cdecl NVSDK_NGX_VULKAN_Init_ProjectID(
    const char* projectId, NVSDK_NGX_EngineType engineType,
    const char* engineVersion, const wchar_t* applicationDataPath,
    VkInstance instance, VkPhysicalDevice physicalDevice, VkDevice device,
    NVSDK_NGX_Version sdkVersion,
    const NVSDK_NGX_FeatureCommonInfo* featureInfo);
```

These are private SDK-to-Core ABIs. They are **not** ABI-equivalent to the documented public static-wrapper function. The public declaration ends in `(featureInfo, sdkVersion)`; both private exports end in `(sdkVersion, featureInfo)`. The dispatch form is named `...Init_ProjectID_Ext`, not `...ProjectID_Ext2`.

A Project-ID-only HSR path therefore does not need a fabricated `0`, decimal conversion, hash, or guessed numeric application ID. The preferred design is to carry the captured typed identity separately and let Core initialize the owned Vulkan device through this Project-ID export (or through the documented public static wrapper). No implementation or gate approval is made by this review.

## Exact artifacts and run evidence

Read-only artifacts:

| artifact | SHA-256 |
|---|---|
| retained `_nvngx.dll` Core | `bdad96fdca36050a94a221bb89eab4fc5db6e53ef799494a68957a2e2b28e283` |
| retained signed Feature 18 `nvngx_dlssnr.dll` | `e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e` |
| retained signed SR `nvngx_dlss.dll` | `ba685453f689201997db726fb0d904e969bdd148ea9a58a56ba5c1ead86eeaf9` |
| retained `NVUnityPlugin.real.dll` | `a1db4a529bbc06fa3e0aefb61f95e97851b401633e5cf55a8f0f92640324f98a` |

`hsr-runs/20260910-125914-native-ingress-probe-NR-OFF-physical-user-operated/world-session-router.jsonl` contains exactly one Project-ID return in that world session:

```json
{"event":"ngx.init.return","path":"project_id","project_id":"231313132","project_id_complete":1,"engine_type":2,"engine_version":"2019.4.34f1","engine_version_complete":1,"sdk":20,"result":"0x00000001","original_calls":1}
```

This proves an actual, once-forwarded, successful private D3D11 Project-ID call. It does not prove a numeric application ID. The same session continues to report `appid:0`, meaning no numeric path was observed.

The world process map ties Core inode `49291219`, signed SR inode `49294309`, and `NVUnityPlugin.real.dll` inode `49295136` to the retained files. Signed NR is absent from that NR-OFF process map; its findings below are static, not run125914 invocation evidence.

`"231313132"` is a Project-ID string even though it contains only decimal characters. The exact Core's validator applies its GUID-like/32-digit checks only when `IdentifierType == Project_Id` and `EngineType == CUSTOM (0)`; Unity (`2`) bypasses that custom-ID validation. Parsing the string as integer `231313132` would change its type and meaning.

## Official header and CodeView boundary

The official v310.7 headers define:

- `NVSDK_NGX_Application_Identifier_Type_Project_Id = 1`;
- `NVSDK_NGX_ProjectIdDescription` as `(const char* ProjectId, EngineType, const char* EngineVersion)`, size 24 in the official CodeView data;
- `NVSDK_NGX_Application_Identifier` as a discriminator plus a union of `ProjectDesc` and `uint64_t ApplicationId`, size 32 in CodeView;
- the public `NVSDK_NGX_VULKAN_Init_with_ProjectID(...)` with 11 arguments and final order `(featureInfo, sdkVersion)`;
- under `NGX_SNIPPET_BUILD`, only numeric Vulkan `Init`, `Init_Ext`, and `Init_Ext2`; there is explicitly no Core-to-Snippet Project-ID interface.

The official debug Vulkan object contains these named private PFNs:

```text
PFN_NVSDK_NGX_CORE_VULKAN_Init_ProjectID:
NVSDK_NGX_Result (const char*, NVSDK_NGX_EngineType, const char*,
 const wchar_t*, VkInstance, VkPhysicalDevice, VkDevice,
 NVSDK_NGX_Version, const NVSDK_NGX_FeatureCommonInfo*)*

PFN_NVSDK_NGX_CORE_VULKAN_Init_ProjectID_Ext:
NVSDK_NGX_Result (const char*, NVSDK_NGX_EngineType, const char*,
 const wchar_t*, VkInstance, VkPhysicalDevice, VkDevice,
 PFN_vkGetInstanceProcAddr, PFN_vkGetDeviceProcAddr,
 NVSDK_NGX_Version, const NVSDK_NGX_FeatureCommonInfo*)*
```

All eight inspected debug variants (six normal x64 and two `khr`) produce the same five normalized private Vulkan PFN type lines. All 14 normal/`khr`, debug/release/iterator Vulkan objects have byte-identical `NVSDK_NGX_VULKAN_Init_with_ProjectID` disassembly after removing only the object-path banner. That wrapper selects:

- `...Init_ProjectID_Ext` when both dispatch pointers are supplied, staging SDK version before feature info; or
- `...Init_ProjectID` without dispatch pointers, again staging SDK version before feature info.

This independently verifies the private ABI; it is not inferred by casting the public declaration.

## Exact Core dataflow

### 1. Project tuple becomes a discriminated identifier

At Core RVA `0x5CDB0` (D3D11) and RVAs `0xD5D0`/`0xD7A0` (Vulkan), the implementation constructs a local `NVSDK_NGX_Application_Identifier`:

```text
IdentifierType = 1 (Project_Id)
ProjectDesc.ProjectId = caller projectId pointer
ProjectDesc.EngineType = caller engineType
ProjectDesc.EngineVersion = caller engineVersion pointer
```

The SDK version and feature info remain separate common-init arguments. They are not fields of the identifier union.

### 2. Core resolves a CMS ID; it does not parse or emit a Project-ID hash

Both the D3D11 and Vulkan common paths reach exact Core RVA `0x499C0`. Its discriminant switch is:

- type `0`: store `ApplicationId XOR 0x0E658703` in the Core context;
- type `1`: load Project-ID mapping data, call the mapper at RVA `0x492F0` on the typed `ProjectDesc`, and store the mapper's returned `uint64_t` in the Core context;
- other type: fail invalid-parameter.

The Project mapper selects the engine section, matches engine version, then looks up Project ID. An exact mapping supplies `cmsID`; otherwise a matching engine/version item supplies `generic-cmsID`. The visible FNV-1a operations at `0x497C7` are only the implementation of an unordered-map lookup by Project-ID string; that hash is not returned as the CMS ID. If no engine/version mapping item is found, the mapper returns its compiled fallback `0x0E658703`.

This establishes the initial Project-path context value. A later guarded Core policy can replace a generic Unity/UE value with a snippet's embedded application ID: RVA `0x47A80` resolves and invokes the snippet's no-argument `NVSDK_NGX_GetApplicationId`, and RVA `0x38C60` checks whether the current context value is generic Unity `0x08618954` or generic UE `0x086AA7B4`. If the embedded value differs and a further internal lookup accepts it, RVA `0x39011` writes that embedded value back to the same context field. Static analysis does not prove that all of those guards selected the override in run125914.

Therefore the final Core-generated number is Core-selected state: normally the mapped exact/generic CMS ID, with this guarded embedded-ID override possible. It is neither the textual Project ID, a decimal conversion of it, nor an invented hash.

### 3. Snippets receive only that numeric Core-selected value

After context creation and snippet policy, exact Core D3D11 RVA `0x5D950` loops feature indices `0..17` and invokes whichever snippet initializer is available as one of:

```text
Init(context.cmsId, dataPath, d3d11Device, sdkVersion)
Init_Ext(context.cmsId, dataPath, d3d11Device, sdkVersion, parameters)
```

Exact Core Vulkan RVA `0xC8B0` similarly invokes:

```text
Init(context.cmsId, dataPath, instance, physical, device, sdkVersion)
Init_Ext(context.cmsId, dataPath, instance, physical, device,
         sdkVersion, parameters)
Init_Ext2(context.cmsId, dataPath, instance, physical, device,
          gipa, gdpa, sdkVersion, parameters)
```

The first argument in every branch is the same numeric context field initially populated by `0x499C0` and potentially replaced only by Core policy such as the guarded embedded-ID override above. No `NVSDK_NGX_Application_Identifier`, discriminant, Project-ID pointer, engine type, or engine-version pointer crosses the Core-to-Snippet call boundary.

The only parameter keys populated in the inspected D3D11/Vulkan init loops are:

```text
Context.GPU.ArchID
Context.GPU.SMVer
Minimum.Logging.Level       (when applicable)
Disable.Other.Logging.Sinks (when applicable)
Log.Callback                (when applicable)
```

There is no Project-ID/engine identity key in this parameter transport. The official parameter headers likewise expose no such key.

### 4. Exact signed snippet behavior

Neither exact signed NR nor exact signed SR exports any Project-ID initializer. Both export numeric Vulkan `Init`, `Init_Ext`, and `Init_Ext2` only.

- Signed NR `Init_Ext2` RVA `0x251A0` forwards its RCX numeric first argument to common RVA `0x23DD0`, which stores it in its per-device context at offset `+0x20`.
- Signed SR `Init_Ext2` RVA `0x5B560` forwards its RCX numeric first argument to common RVA `0x5A2F0`, which stores it in its per-device context at offset `+0x18`.

Both exact snippets export `NVSDK_NGX_GetApplicationId`, but each implementation is only `mov eax, 0x0E658703; ret`. It is the snippet's compiled embedded value, not a query for the Project mapper's current/final context result. Core can consider it in the guarded generic-ID override above, but callers must not independently promote it to HSR's application ID without observing that Core actually selected it.

## What is and is not known about the numeric CMS ID

Run125914 did not capture the first argument of signed SR's `D3D11_Init`/`Init_Ext`, so the actual Core-resolved CMS ID remains unobserved.

Four other local NGX mapping copies, all SHA-256 `9ad4db5b1d7c65bf87611421ce1d8efe7b1cc403f5f4ab0bc2e96b2e46e00bea`, contain a Unity `.*` entry with generic CMS ID `8618954` and no Project-specific Unity mappings. The exact Core also contains code comparing a CMS value with `0x08618954`. This makes `0x08618954` a strong initial mapping-data candidate, but not run125914 evidence: the HSR prefix's mapping file was absent after restoration, Core may apply the guarded embedded-ID override, and no Core-to-Snippet numeric call was logged. Neither `0x08618954` nor embedded `0x0E658703` may be copied into `actualAppId`, attach state, or any gate as if observed.

There is no retained-Core export that queries the mapped current CMS ID. `NVSDK_NGX_UpdateFeature` and the Feature Discovery/Requirements APIs accept typed identity for update/discovery purposes; they do not initialize the owned Vulkan device and are not substitutes for Project-ID Init. The snippets' `GetApplicationId` constant is also not such a query.

## Current Main gap

`native/runtime/interop.cpp` rejects `!app_id`, resolves `NVSDK_NGX_VULKAN_Init_Ext2` from signed NR, and directly calls that numeric Core-to-Snippet ABI with the owned Vulkan handles, dispatch pointers, API version, and null parameters. That function has no discriminant or typed identity arm. Adding Project fields to feature parameters would not reproduce Core's path, because the exact Core consumes the union before the snippet call and sends only its selected numeric context value.

Likewise, the current 64-byte `D5nAdapterAttachV1` rejects a zero numeric ID and has no typed identity field. This is why the Project path needs separate negotiation rather than a relaxed zero check or repurposed reserved field.

## Feasible designs

### Preferred: separate typed identity plus Core Vulkan Project-ID init

1. Intercept the exact private D3D11 Project-ID ABI already verified for the pinned Core.
2. Copy Project ID and engine version into adapter-owned bounded storage while the call arguments are valid. Stage the copy before forwarding, but publish it only if the original returns success exactly once. Store engine type and SDK version as values. Repeated identical success is acceptable; any conflicting successful tuple fails closed.
3. Transfer that value through a **new, optional, explicitly Project-ID-discriminated API**. Every adapter/host/runtime boundary must deep-copy the strings; no caller pointer may be retained.
4. On the owned Vulkan device, call either:
   - the documented public static `NVSDK_NGX_VULKAN_Init_with_ProjectID` with public final order `(featureInfo, sdkVersion)`; or
   - only for pinned Core SHA-256 `bdad96...`, private `NVSDK_NGX_VULKAN_Init_ProjectID_Ext` with exact final order `(sdkVersion, featureInfo)`.
5. Do not then call signed NR `NVSDK_NGX_VULKAN_Init_Ext2` a second time. Core's verified init loop is the component that resolves the CMS ID and invokes signed NR's numeric `Init_Ext2`.
6. Fail closed if the typed export is absent/rejected, the Core hash differs, Core Project-ID Init fails, or Feature 18 is not demonstrably initialized. Identity success is bootstrap evidence only, never gate approval.

The current source loads signed NR and patches its module filename identity before direct initialization. A future Core-init implementation would have to order any required signed-module discovery/identity setup before Core Init and separately prove that Core bound the exact `e16bc...` Feature 18 module. Static control flow proves the mechanism, not that future dynamic binding.

### Diagnostic alternative: capture Core's real CMS ID

A diagnostic can hook the exact signed-SR Core-to-Snippet `NVSDK_NGX_D3D11_Init` and `Init_Ext` signatures, call the original exactly once, and accept the numeric first argument only after successful return associated with the successful Project-ID initialization. That value would be a real Core-selected CMS ID, unlike `231313132`, zero, or a local hash.

Run125914 shows resolution of both signed-SR init names but did not hook their invocation. Therefore this alternative is not yet populated. Replaying a D3D11/SR-observed CMS ID directly into Vulkan/NR is also not a documented public identity-conversion API; it should remain closed until separately justified. Carrying the typed tuple remains necessary for provenance and for the preferred Core Project-ID path.

## ABI preservation

A Project identity must not be smuggled through `D5nAdapterAttachV1.ngx_application_id`, reserved fields, or an ephemeral pointer. Use a separate optional export/structure with an explicit identity kind and length-delimited or fixed-capacity owned string bytes. A clean negotiation can add a Project-specific attach/register path without changing the meaning of legacy attach with application ID zero.

This review makes no changes to and requires preserving:

- `D5nAdapterAttachV1` — 64 bytes;
- `D5nRawFrameV1` — 200 bytes;
- `D5nRawFrameResultV1` — 216 bytes;
- `D5nFrameCommitV1` — 72 bytes;
- D5LC v1 — 72 bytes;
- D5RP v1 — 32 bytes.

No code, automatic gate approval, GPU/Wine/game run, production deployment, signed-file edit, or process-memory modification was performed.

## Remaining proof boundary

Static evidence is sufficient to select a truthful design and exact ABI. Before implementation approval, a CPU harness should verify the new copy/negotiation/conflict semantics and the exact private-call staging. A separately authorized runtime diagnostic would still be needed to prove exact Feature 18 binding and successful Project-ID Vulkan bootstrap on the owned device. Those observations must not themselves open the reconstruction/phase/control gates.
