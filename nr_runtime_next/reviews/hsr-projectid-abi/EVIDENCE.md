# HSR D3D11 Project-ID ABI review (CPU/static only)

## Decision

The private x64 core export ABI is verified for the exact retained core and is independently corroborated by the official MSVC static libraries:

```cpp
NVSDK_NGX_Result __cdecl NVSDK_NGX_D3D11_Init_ProjectID(
    const char* InProjectId,                         // RCX
    NVSDK_NGX_EngineType InEngineType,               // EDX (32-bit enum)
    const char* InEngineVersion,                     // R8
    const wchar_t* InApplicationDataPath,            // R9
    ID3D11Device* InDevice,                          // [entry RSP+0x28]
    NVSDK_NGX_Version InSDKVersion,                  // [entry RSP+0x30]
    const NVSDK_NGX_FeatureCommonInfo* InFeatureInfo // [entry RSP+0x38]
);
```

This is **not** the public static-wrapper ABI. The public declaration is:

```cpp
NVSDK_NGX_D3D11_Init_with_ProjectID(
    projectId, engineType, engineVersion, dataPath, device,
    featureInfo, sdkVersion);
```

The final two public arguments are therefore `(featureInfo, sdkVersion)`, while the private export takes `(sdkVersion, featureInfo)`. Casting `NVSDK_NGX_D3D11_Init_ProjectID` to the public wrapper type would be wrong.

Verification is specific to the retained core SHA-256 below. A changed core must be reverified or rejected before this private hook is used.

## run113832 says resolution, not invocation

Source log reviewed:

`hsr-runs/20260910-113832-native-ingress-probe-NR-OFF-physical-user-operated/latest-session-diagnostic.jsonl`

The parsed log has:

- core resolution sightings for `NVSDK_NGX_D3D11_Init`, `...Init_Ext`, then `...Init_ProjectID`;
- later snippet-side sightings for `...Init` and `...Init_Ext`;
- zero `init.return`, zero `init_ext.return`, and zero `ngx.init.app_id.observed` events;
- 455 `ingress.diagnostic` records whose `appid` is `0`.

That `0` is only the initialized-but-unset `g_observed_app_id` state. It is **not** evidence for a numeric application ID of zero and must not become `actualAppId=0`. Likewise, resolving `...Init_ProjectID` is not evidence that it was invoked. The diagnostic source set its `g_project_id_init_observed` flag in the resolver branch, so the emitted field named `project_init_resolved` records exactly resolution despite the misleading internal variable name.

No runtime Project ID or engine-version value is present in run113832.

## Official source and static-library evidence

### Public/header boundary

`/home/user/rt_5090_project/nvidia-dlss-official/include/nvsdk_ngx.h`:

- lines 97–102 explicitly warn that same-named functions differ across SDK, Core, and Snippet boundaries;
- lines 148–165 give the `NGX_SNIPPET_BUILD` four-argument D3D11 numeric Init and five-argument Init_Ext forms;
- lines 168–176 give the public SDK static-wrapper numeric form;
- lines 242–254 explicitly provide **no** Project-ID Core-to-Snippet declaration, but give the seven-argument public `Init_with_ProjectID` form when not building a snippet.

The header alone therefore does not authorize assigning the public wrapper signature to the private export.

### Exact private typedef from CodeView

Read-only extraction of the D3D11 object from official debug libraries found this named CodeView UDT in both CRT variants:

```text
Type: NVSDK_NGX_Result (const char*, NVSDK_NGX_EngineType, const char*,
      const wchar_t*, ID3D11Device*, NVSDK_NGX_Version,
      const NVSDK_NGX_FeatureCommonInfo*)*
UDTName: PFN_NVSDK_NGX_CORE_D3D11_Init_ProjectID
```

The same CodeView data separately types `NVSDK_NGX_D3D11_Init_with_ProjectID` with `FeatureCommonInfo*` sixth and `Version` seventh. This independently establishes the reversal rather than deriving the private ABI from the public declaration.

The final private call in the release static wrapper stages:

- `RCX = projectId`
- `EDX = engineType`
- `R8 = engineVersion`
- `R9 = applicationDataPath`
- `[RSP+0x20] = device`
- `[RSP+0x28] = sdkVersion`
- `[RSP+0x30] = converted featureInfo`

All ten local `nvsdk_ngx_{d,s}{,_dbg,_iterator...}.lib` variants showed this final-call pattern once. `STATIC_EVIDENCE.txt` contains the source excerpts, exact CodeView lines, disassembly, and the ten-variant table.

## Evidence from the exact retained binaries

### Identity and mapping tie

Retained files read without modification:

- `NVUnityPlugin.real.dll`: SHA-256 `a1db4a529bbc06fa3e0aefb61f95e97851b401633e5cf55a8f0f92640324f98a`, inode `49295136`.
- `_nvngx.dll`: SHA-256 `bdad96fdca36050a94a221bb89eab4fc5db6e53ef799494a68957a2e2b28e283`, inode `49291219`.

The run113832 process map names those same paths and inodes. Its core base was `0x6fffd79d0000`. The retained core exports have RVAs:

- Init: `0x5cc70`, yielding runtime `0x6fffd7a2cc70` (exactly the logged original);
- Init_Ext: `0x5cb30`, yielding runtime `0x6fffd7a2cb30` (exactly the logged original);
- Init_ProjectID: `0x5cdb0`, yielding expected runtime `0x6fffd7a2cdb0`.

This ties the disassembled core implementation to the physical-run mapping without treating the Project-ID resolution as a call.

### Retained NVUnityPlugin static path

At RVA `0x20600`, the retained plugin contains one direct call to the public Project-ID wrapper thunk and no direct call to its numeric static-wrapper thunk. If this call site executes, it supplies:

- project ID from identity object offset `+0x00`;
- engine type immediate `2`, which the official enum defines as Unity;
- engine version from offset `+0x08`;
- application data path from offset `+0x10`;
- feature info `nullptr`;
- SDK version `0x14`.

The public wrapper at RVA `0x37e40` then calls the private function pointer with SDK version sixth and feature info seventh, exactly as in the official static library. These are static implementation facts, **not proof that the physical run executed the call**. The project ID and engine-version strings are supplied dynamically and were not recovered as constants.

### Retained core implementation

The private export at RVA `0x5cdb0` preserves RCX/EDX/R8/R9 as project ID, engine type, engine version, and data path; reads stack arguments 5–7 at entry offsets `+0x28/+0x30/+0x38`; constructs an `NVSDK_NGX_Application_Identifier` with discriminator `1` (Project ID); and forwards SDK version and feature info separately to its common initializer. This agrees with the named official private PFN.

## Optional diagnostic patch

`PROPOSED_PROJECT_ID_CAPTURE.patch` is an unapplied patch against current `adapters/hsr_native/router.cpp` base SHA-256:

`8f9f13fe449b5e909c6a8459aca60b7e5f8d7071bda3f5beef9b3653c5e360c6`

It:

1. intercepts only the exact private core name `NVSDK_NGX_D3D11_Init_ProjectID`;
2. never aliases or casts `NVSDK_NGX_D3D11_Init_with_ProjectID`;
3. distinguishes export resolution from actual routed invocation;
4. emits a bounded, JSON-safe event with path, Project ID, engine type, engine version, SDK version, exact result, and original-call count;
5. calls a present original exactly once and returns its unmodified result;
6. does not derive, invent, or store a numeric application ID from project identity;
7. leaves `g_observed_app_id == 0` on a Project-ID-only path, so the existing numeric attach remains closed;
8. makes no host/protocol, gate, protection, deployment, or signed-file change.

The patch also labels successful/failed numeric Init and Init_Ext invocations, allowing a future diagnostic log to establish the actually chosen path rather than infer it from resolution order.

If this is merged into the prior diagnostic-only source, `project_init_resolved` should read `g_project_id_export_resolved`, while actual invocation should be represented by the `path:"project_id"` return event (or a separately named `project_init_called` field). Resolution must never set the invocation flag.

The patch cross-compiles with the existing MinGW C++20 warning-as-error flags and applies cleanly in dry-run. It was not linked, run, deployed, or applied to Main.

## Numeric attach cannot represent project identity

The frozen `D5nAdapterAttachV1` is 64 bytes and contains only `uint64_t ngx_application_id`. A Project-ID identity is a tuple `(projectId, engineType, engineVersion, sdkVersion)` and cannot be losslessly or truthfully encoded in that numeric field. In particular, neither zero nor a hash is an application ID.

If the host is to support Project-ID-only initialization later, it needs a **separate optional project-identity API/export** with an explicit discriminant and bounded/copied Project-ID and engine-version data. It must be independently negotiated and attested; absence or rejection must keep the path closed. It must not repurpose reserved fields, mutate `D5nAdapterAttachV1`, or automatically approve/open any gate.

No changes are proposed to frozen `D5nAdapterAttachV1` (64), `D5nRawFrameV1` (200), `D5nRawFrameResultV1` (216), `D5nFrameCommitV1` (72), or other existing protocol layouts.

## Remaining evidence boundary

ABI research is complete for the retained binary. The **actual runtime choice and actual Project-ID/engine-version values remain unproven** until a separately authorized physical diagnostic executes the verified capture. That future observation is not gate approval.
