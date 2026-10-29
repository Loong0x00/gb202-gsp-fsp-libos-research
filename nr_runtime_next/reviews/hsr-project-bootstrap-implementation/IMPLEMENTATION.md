# HSR Project-ID bootstrap implementation (isolated CPU candidate)

## Scope and evidence boundary

This tree is an isolated copy of the current native host/runtime and HSR adapter. It implements the typed Project-ID path described by:

- `../hsr-project-runtime-identity/EVIDENCE.md`
- `../hsr-project-runtime-identity/STATIC_EVIDENCE.txt`

No Main source, game/prefix, protection component, GPU, Wine, or network/state setting was touched. The implementation is a buildable candidate, not runtime approval.

The captured HSR identity remains exactly:

- Project ID string: `"231313132"` (never parsed as a number)
- engine: Unity (`2`)
- engine version: `"2019.4.34f1"`
- NGX SDK version: `20`

## Optional API and ownership

Existing `D5nAdapterAttachV1` remains 64 bytes and still requires a nonzero numeric `ngx_application_id`. The Project path uses separate optional exports:

```text
DLSS5_NativeAdapterAttachProjectV1(const D5nAdapterProjectAttachV1 *)
DLSS5_NativeRuntimeSetProjectIdentityV1(const D5nProjectIdentityV1 *)
```

`D5nProjectIdentityV1` is explicitly discriminated as `D5N_IDENTITY_PROJECT_ID_V1`. It contains inline, length-delimited Project-ID/engine-version bytes and an inline UTF-16 application-data path, plus engine type, SDK version, and an explicit flag recording the null `FeatureCommonInfo` policy. It contains no caller string pointer.

The adapter stages bounded copies before forwarding the original D3D11 Project-ID call exactly once, but publishes only after that original returns `0x00000001`. Repeated identical successful tuples are accepted. A conflicting successful tuple or an incomplete successful capture permanently closes the adapter Project path. Adapter binding, host, and runtime each copy and validate their own value; no borrowed input pointer survives any API return.

The original `FeatureCommonInfo` is forwarded only to the original D3D11 call. It is not copied because it can contain nested path and callback pointers. The official public Vulkan Project-ID declaration makes this argument optional (`nullptr` default), so the owned Vulkan call explicitly uses null. The captured SDK version and application-data path are copied as required value metadata. Core-created numeric snippet parameters are forwarded unchanged by the observer and are never retained.

## Pinned private Core call

Only the private export below is used:

```text
NVSDK_NGX_VULKAN_Init_ProjectID_Ext(..., gipa, gdpa, sdkVersion, featureInfo)
```

The implementation requires all of:

- loaded Core file SHA-256 `bdad96fdca36050a94a221bb89eab4fc5db6e53ef799494a68957a2e2b28e283`;
- Project-ID export RVA `0xD7A0`;
- exact signed NR file SHA-256 `e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e`;
- exact signed NR Vulkan initializer RVAs `0x13F50`, `0x25050`, and `0x251A0`.

A hash/export mismatch fails closed. The public wrapper's final argument order is not cast onto this function; the verified private `(sdkVersion, featureInfo)` order has its own function type.

## Feature 18 proof and CMS separation

Static Core RVA `0xC8B0` increments an index from 0 and exits at `0x12`, so its feature loop covers only indices `0..17`. That loop bound does **not** prove that the exact `e16...` Feature 18 module occupies or is invoked from one of those internal entries.

For one synchronous Core Project-ID call, the runtime installs a fresh, bounded resolver scope. It accepts compatibility only when Core freshly resolves an initializer from the exact pinned NR module and the returned wrapper observes exactly one call whose:

- instance, physical device, and `VkDevice` are the owned Vulkan handles;
- dispatch pointers (for `Init_Ext2`), SDK version, and copied data path match;
- original exact signed-NR initializer returns success; and
- first numeric argument is nonzero and consistent.

The wrapper forwards that first argument unchanged. It is stored only as `core_selected_cms_id` and logged as `cms_internal_bootstrap`; it is never copied to `app_id`, attach identity, or gate state. The original Project identity remains separately typed.

If Core uses a cached initializer pointer and the fresh `GetProcAddress` scope misses it, proof is absent and bootstrap fails closed. Likewise Core success without the exact NR call, NR success without Core success, multiple calls, wrong device/metadata, failed original return, resolver restoration failure, or any hash/RVA mismatch fails closed.

No supplemental direct `NVSDK_NGX_VULKAN_Init_Ext2` fallback is enabled. With only a missed/absent resolver observation, this implementation cannot both prove the CMS was selected by **this** Vulkan Project init and prove NR was not already initialized. Calling direct would risk a double init. The static same-`context.cmsId` flow alone does not remove that dynamic ambiguity.

## Gates and legacy behavior

Identity registration never approves reconstruction, phase, control, completion, or publication gates. Existing gate and completed-frame requirements remain in place. Runtime `compatible` becomes true only after the full Core-plus-exact-NR proof above.

The numeric CP2077/WuWa path keeps the original nonzero `D5nAdapterAttachV1` and direct signed-NR `Init_Ext2` behavior. The new runtime export is optional during runtime loading and is used only by the separate HSR Project attach.

Frozen sizes remain:

- `D5nAdapterAttachV1`: 64
- `D5nRawFrameV1`: 200
- `D5nRawFrameResultV1`: 216
- `D5nFrameCommitV1`: 72
- D5LC v1: 72
- D5RP v1: 32

## Remaining owned-GPU proof

A fresh owned GPU harness must still demonstrate, in one process and on the actual owned `VkDevice`:

1. exact Core and exact `e16...` NR pins pass;
2. private Vulkan Project-ID Core init returns success;
3. the bounded resolver wrapper actually observes exact NR initialization once;
4. Core-selected internal CMS is forwarded unchanged;
5. runtime `bootstrap_count == 1` and `compatible == 1`;
6. existing creation/evaluation/completion gates still remain closed until their independent evidence is satisfied.

If item 3 is absent because Core cached the pointer or did not bind NR in indices `0..17`, this candidate intentionally remains incompatible. A future supplemental path would need stronger same-call CMS capture and no-prior-NR-init proof before it could be enabled.
