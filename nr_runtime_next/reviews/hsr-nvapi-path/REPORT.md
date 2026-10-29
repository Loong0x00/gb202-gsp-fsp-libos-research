# Retained HSR D3D11 DLSS resource-path review

**Method:** CPU-only, read-only static analysis of retained binaries, retained logs/maps, and source corresponding to the loaded compatibility interfaces. No game was started, no process was attached to, no memory was read or instrumented, and no production file was edited.

## Result

The evidence supports this path for signed D3D11 DLSS input consumption:

1. `NVUnityPlugin.real.dll` obtains native `ID3D11Resource*` values and stores them in the NGX parameter object under the literal keys `"Depth"` and `"MotionVectors"`.
2. It explicitly obtains the device's **immediate context** and passes that context, the feature handle, and the parameters to `NVSDK_NGX_D3D11_EvaluateFeature_C`.
3. The signed `nvngx_dlss.dll` D3D11 cubin backend creates an NVAPI SRV for an input resource, obtains a CUDA texture-object handle from that view, obtains an NVAPI resource handle for the underlying resource, appends that resource handle to the cubin read-resource array, and dispatches through `NvAPI_D3D11_LaunchCubinShader`.
4. On the loaded DXVK-NVAPI/DXVK stack, the NVAPI resource handle is the `ID3D11Resource*` value, and the launch read/write arrays are passed to `ID3D11VkExtContext1::LaunchCubinShaderNVX`. DXVK records those resources as bindless read/write dependencies and emits `launchCuKernelNVX`; it does not need ordinary `CSSetShaderResources` calls for this path.

Thus the principal retained signed path is **NVAPI cubin + CUDA texture/resource handles on the immediate D3D11 context**, not an ordinary CS-SRV binding path. The available evidence does not establish context-state swapping or a deferred-context detour. It also does not make zero scoped CS calls a cause; that observation is merely expected for this extension path.

## Exact artifacts and retained run

| Artifact | SHA-256 / identity |
|---|---|
| `.../Plugins/x86_64/nvngx_dlss.dll` | `ba685453f689201997db726fb0d904e969bdd148ea9a58a56ba5c1ead86eeaf9`, 51,276,856 bytes, version resource `3,7,10,0`, PE security directory present |
| `.../Plugins/x86_64/NVUnityPlugin.real.dll` | `a1db4a529bbc06fa3e0aefb61f95e97851b401633e5cf55a8f0f92640324f98a`, 1,391,408 bytes |
| loaded `system32/d3d11.dll` | `4ff4916573be5bfa433286d61594d1cc6901953694681c5e61f3d1263c025b97`; retained log identifies DXVK 3.0 |
| loaded `system32/nvapi64.dll` | `7f8e4666865fa35a042fd0867a6617e3647102ef27d24a36414bdcb92238df8e`; embedded build label `dwproton-11.0-4` (the nearby `gcc 14.0.0` is the compiler version, not the DXVK-NVAPI release) |

`hsr-runs/20260910-125914-native-ingress-probe-NR-OFF-physical-user-operated/unchanged-manifest.json` binds the two signed-path hashes above. `process-45152-world-maps.txt` binds that process to those files and the two compatibility DLLs above.

The retained JSONL has 3 successful Feature-1 creates, 162 forwarded evaluates, and 2 releases. Every recorded evaluate preserved `original_calls: 1`; sampled resources were reported as `formats: "26/33/19"`. The final diagnostic reports many global CS calls but `scoped_cs_calls: 0`, `views_examined: 0`. Those facts are observations, not a causal conclusion.

## Static evidence chain

### 1. NVUnity passes named resources and an immediate context

In exact `NVUnityPlugin.real.dll`:

- Function `0x18001fcf0` calls `NVSDK_NGX_Parameter_SetD3d11Resource` with:
  - `"Color"` from input-structure offset `+0x00` (`0x18001fd08..0x18001fd1c`)
  - `"Output"` from `+0x08` (`0x18001fd21..0x18001fd36`)
  - `"Depth"` from `+0x18` (`0x18001fd3b..0x18001fd50`)
  - `"MotionVectors"` from `+0x20` (`0x18001fd55..0x18001fd6a`)
- At `0x18002049e`, the same function calls `NVSDK_NGX_D3D11_EvaluateFeature_C` with its first argument preserved as the D3D11 context.
- Its caller at `0x180020a1c..0x180020a2e` invokes vtable offset `0x140` on `ID3D11Device`, which is `GetImmediateContext`, stores the result, and passes it as `rcx` to `0x18001fcf0` at `0x180020ae4..0x180020ae9`.
- The context is released at `0x180020b1b..0x180020b28`.

This is positive evidence that the HSR Unity bridge sends **resources, not preselected SRVs**, and that the context supplied to signed Evaluate is the immediate context.

### 2. The signed DLL dynamically resolves and invokes the NVAPI cubin path

`nvngx_dlss.dll` has no static `nvapi64.dll` or `nvcuda.dll` import. It loads `nvapi64.dll`, resolves `nvapi_QueryInterface`, and asks for the following IDs in executable code:

| Query ID | Function | Exact code example |
|---|---|---|
| `0x09d52986` | `NvAPI_D3D11_GetResourceHandle` | `0x1800019ae` |
| `0x0ed98181` | `NvAPI_D3D11_CreateCubinComputeShader` | `0x1800025d7` |
| `0x32c2a0f6` | `NvAPI_D3D11_CreateCubinComputeShaderEx` | `0x1800026e7` |
| `0xb672be19` | `NvAPI_D3D11_CreateCubinComputeShaderWithName` | `0x180002817` |
| `0x427e236d` | `NvAPI_D3D11_LaunchCubinShader` | `0x18000293a` |
| `0x01682c86` | `NvAPI_D3D11_DestroyCubinComputeShader` | `0x180002a76` |
| `0x65cb431e` | `NvAPI_D3D11_CreateShaderResourceView` | `0x180002d17` |
| `0x9006fa68` | `NvAPI_D3D11_GetCudaTextureObject` | `0x180002ef6` |

The common evaluator called by exported `NVSDK_NGX_D3D11_EvaluateFeature` retrieves required `"Color"`, `"MotionVectors"`, and `"Depth"` resource values at `0x18003841f..0x1800384c4`. It later copies those three values in that order into the processing structure at offsets `+0x100`, `+0x108`, and `+0x110` (`0x180039819..0x18003983c`).

The signed implementation's `NGXCubinD3D11::GetInputTextureViewHandle`-shaped function is at `0x1800684c0`:

- obtains resource type/texture descriptor at `0x1800685a1..0x1800685f3`;
- reads the resource format and calls the format-normalization function at `0x1800685f9..0x180068608`;
- puts the returned format into the SRV descriptor and calls the `0x65cb431e` wrapper at `0x18006860d..0x180068632`;
- calls the `0x9006fa68` wrapper at `0x1800686c0..0x1800686db`, writing a CUDA texture handle;
- calls the `0x09d52986` wrapper at `0x180068721..0x180068730`, writing an NVAPI resource handle;
- appends that resource handle to the launch metadata's read-resource array at `0x18006884b..0x1800688be`;
- returns the CUDA texture handle to its caller at `0x1800688c1..0x1800688c5`.

The caller at `0x180069d20` writes that returned handle into the kernel-parameter slot. Dispatch at `0x180067b20` forwards the packed kernel parameters plus explicit read/write arrays and counts to the `0x427e236d` wrapper at `0x180067c0c`.

The DLL also contains CUDA/fatbin kernels with depth and motion variants such as `hiluma_engine_input_depthinv_mvlo_hdr_rel`, `...mvhi...`, `g_depth_inverted`, and `sharedDepth`. These names are supporting evidence; the call chain above is the decisive evidence.

### 3. The signed typed-view mapping is 33 -> 34, not 37

The format-normalization function is at `0x180068920`. It is called immediately before constructing the NVAPI SRV descriptor.

Independent decoding of its switch table gives:

| Resource `DXGI_FORMAT` input | SRV-format return | Meaning |
|---:|---:|---|
| 26 | 26 | `R11G11B10_FLOAT` remains 26 |
| 33 | **34** | `R16G16_TYPELESS` -> `R16G16_FLOAT` |
| 19 | **21** | `R32G8X24_TYPELESS` -> `R32_FLOAT_X8X24_TYPELESS` |
| 37 | 37 | 37 would pass through only if the resource were already 37 |

For input 33, the switch selects `0x18006895f`, which executes `mov eax, 0x22` (34). For input 19, it selects `0x180068989`, which executes `mov eax, 0x15` (21). Input 26 takes the identity path at `0x18006898f`.

Consequences for the retained `26/33/19` snapshot:

- Motion resource format remains **33, `DXGI_FORMAT_R16G16_TYPELESS`**.
- The signed cubin path's private motion SRV is statically selected as **34, `DXGI_FORMAT_R16G16_FLOAT`**.
- It is **not** 37 (`DXGI_FORMAT_R16G16_SNORM`).
- Depth resource format remains 19, with private SRV format 21.

The current production files still contain a hard-coded motion-view requirement of 37 (`adapters/hsr_native/hsr_view_contract.h` and `adapters/hsr_native/d3d11_transport.cpp`). They were not changed. Static evidence contradicts treating that 37 as the signed path's view contract; a runtime boundary observation should confirm 34 before any production change.

### 4. Exact compatibility-stack behavior bypasses ordinary CS binding

Exact loaded `nvapi64.dll` disassembly shows:

- public `NvAPI_D3D11_GetResourceHandle` at `0x21b40ad70` calls helper `0x21b452950`;
- helper `0x21b452950` is `mov [r8], rdx; ret`, i.e. writes the incoming `ID3D11Resource*` as the handle;
- public `NvAPI_D3D11_LaunchCubinShader` at `0x21b40ba60` forwards all launch arguments to helper `0x21b481db0` at `0x21b40bb24`;
- helper `0x21b481db0` forwards to the context extension vtable at offset `0x48`.

DXVK 3.0 source at tag commit `97fe0c66f89d3c8977578e1b500907306d4af536` matches the loaded version and names that extension `ID3D11VkExtContext1::LaunchCubinShaderNVX`. In `d3d11_context_ext.cpp` it:

- casts each read/write array element to `ID3D11Resource*`;
- inserts them with `DxvkAccess::Read` / `DxvkAccess::Write`;
- copies launch parameters by value;
- emits `ctx->launchCuKernelNVX(...)`.

`DxvkContext::launchCuKernelNVX` states that the explicit arrays are for barriers/tracking because the resources are used **bindlessly**, synchronizes them, and invokes `cmdLaunchCuKernel`.

The same source's device extension creates the requested SRV, converts its image view to an NVX driver handle, combines that image-view handle with the sampler in `GetCudaTextureObjectNVX`, and calls `vkGetImageViewHandleNVX`. Cubin creation/launch uses `vkCreateCuModuleNVX`, `vkCreateCuFunctionNVX`, and `VkCuLaunchInfoNVX`.

The copied DXVK-NVAPI source is an upstream reference at the nearest upstream commit before the custom DLL's PE build timestamp. It is not claimed as custom-build provenance. The relevant source routines agree with the exact loaded-binary disassembly above.

A separate retained prior HSR log on the same named stack records, in order, successful `CreateCubinComputeShaderWithName`, `GetResourceHandle`, `CreateShaderResourceView`, `GetCudaTextureObject`, and `LaunchCubinShader` calls. It is useful corroboration but is not used as a hash-bound observation for the 20260910 run.

## Deferred contexts and context-state swapping

Evidence ranking:

- **Immediate context supplied by HSR Unity bridge: high confidence.** This is established by the concrete `ID3D11Device::GetImmediateContext` call and data flow into Evaluate.
- **NVAPI cubin/CUDA handle route: high confidence.** This is established by executable call chains, query IDs, exact compatibility-binary forwarding, and retained prior NVAPI logs.
- **Deferred/context-state route for this call: unsupported by current evidence.** No references to `CreateDeferredContext`, `FinishCommandList`, `ExecuteCommandList`, `CreateDeviceContextState`, or `SwapDeviceContextState` were found in extracted ASCII/UTF-16 strings. This is only negative evidence because COM methods need not retain names.
- DXVK implements `LaunchCubinShaderNVX` for both immediate and deferred context templates and copies state “in case this gets called from a deferred context.” That proves capability, not use. It does not override the positive fact that NVUnity supplied an immediate context here.

No claim is made that hidden internal context activity is impossible. It is simply unnecessary to explain the observed absence of scoped CS calls, and no positive evidence currently supports it.

## Smallest next diagnostic

No diagnostic code was produced or run under this task's read-only constraint.

The smallest next diagnostic for the remaining **runtime typed-view confirmation** is one evaluation-scoped observer at the NVAPI query-ID boundary for **`NvAPI_D3D11_CreateShaderResourceView` (`0x65cb431e`)**, not more D3D11 CS hooks:

1. Arm for exactly one forwarded signed Evaluate call, on that thread only.
2. Preserve the existing closed input Gate and call the original signed Evaluate exactly once.
3. In the NVAPI SRV wrapper, ignore every resource except the exact canonical COM identities already captured from NGX parameters `MotionVectors` and `Depth`.
4. Before forwarding, record the supplied `D3D11_SHADER_RESOURCE_VIEW_DESC` and underlying `D3D11_TEXTURE2D_DESC`.
5. Forward the original NVAPI call once and unmodified. On success, record `(*ppSRV)->GetDesc`, `(*ppSRV)->GetResource` identity, `NvAPI_Status`, and the returned driver handle.
6. Expected result from this static review: motion resource/view `33/34`, depth resource/view `19/21`. Format 33 must remain labeled typeless; 37 is not an acceptable reinterpretation of it.

This single boundary observes the actual private view made by the signed cubin path and is sufficient to settle the typed contract. It should be attempted before a launch hook.

Only if final launch ownership still needs independent confirmation, add one second narrow observer for **`NvAPI_D3D11_LaunchCubinShader` (`0x427e236d`)** and compare the read array against the resources observed above. On this exact compatibility DLL, those handles are resource pointers. For a version-agnostic observer, correlate them through `NvAPI_D3D11_GetResourceHandle` (`0x09d52986`) rather than blindly treating arbitrary NVAPI handles as COM pointers. Also record `pDeviceContext->GetType()`; the expected value is immediate.

Do not hook broad D3D11 surfaces, parse arbitrary packed cubin parameters, change exports, open the input Gate, alter the frozen ABI, or add a second signed Evaluate invocation.

## Confidence boundary

Static evidence establishes the route and predicts the exact private view formats strongly. What remains unobserved in the 20260910 run is the runtime `pDesc`/returned-view pair at the NVAPI SRV boundary and, optionally, membership of the two identities in a particular cubin launch's read array. The proposed one-hook diagnostic closes the first gap with the smallest scope.
