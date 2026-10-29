# POST5 cinematic: frozen-source dataflow audit (CPU/read-only)

Scope: `/home/user/rt_5090_project/nr_runtime_next/reviews/quality-post5-cinematic-20260910-173726/source/native` exactly. Below, `runtime/`, `host/`, `shaders/` are relative to that directory; `../adapters/` is its frozen sibling, inspected only to finish WuWa copyback. No source/package/Main edits, builds, GPU, Wine, game, screenshots or control changes. No deployment. Hashes: `source-sha256.json`.

## Bottom line

**No proven “original Color five times” or “decode layer 1 instead of layer 5” bug in the inspected caller.** Each Evaluate is *configured* with its predecessor's image. That is not proof the signed implementation reads those bindings, preserves independent temporal history, writes the expected pixels, or that the game displays them. POST5 looking like POST1 remains unresolved by static evidence. Prioritize the binding/history/staging checks below, not another style adjustment.

## Proven in caller source, not proven pixels

| Boundary | Exact evidence / finding |
|---|---|
| POST source selection | `host/pipeline.cpp:148-167,201-228,345-355,388-397`: snapshots original NGX `Color` and `Output`, but POST selects **Output**, executes signed SR/RR first, then submits NR. WuWa likewise chooses `snapshot.output` at `host/wuwa_ingress.cpp:886-908`. Original game Color is not the NR layer source. Snapshot is taken before the signed call; assumes that call does not replace its Output binding internally. |
| Input isolation | `runtime/pipeline.cpp:397-426,482-494`: separately committed snapshot/base/ping0/ping1/decoded resources; each frame freshly copies current source/MV/depth into chain-owned resources. Encode runs once at `506-508`, not once per layer. POST validates `source == output`, RGBA16F and full output extent at `123-159`. |
| Parameters and resource aliases | `runtime/pipeline.cpp:243-310,438-456,534-535`: fresh allocated map for each layer; configure immediately precedes Create and Evaluate. Only resource keys set are `DLSSNR.Color=&input.read`, `MVec`, `Depth`, `Output=&output.write`. No original parameter-map copy, no bare `Color`/`Output` resource writes in this runtime path. Host bare-Color `ParameterGuard` is PRE-only (`host/pipeline.cpp:170-199,317-343,363-384`), not a POST override. |
| Pointer lifetime / ABI | `runtime/pipeline.cpp:23-49,78-79,434-456`; `runtime/interop.cpp:221-252`; `runtime/runtime_internal.h:65-92`: resource wrappers live in the stable global Chain array, not temporary locals; read/write wrappers identify the same image with different ReadWrite bits. Core-map setters use slots 0/3/4/6 (`runtime/ngx_parameters.cpp:7-30`), distinct from host feature-map ABI. Setters return void and there is **no runtime readback** proving values or alias precedence. |
| Independent contexts | `runtime/pipeline.cpp:15-21,434-457`: five CreateFeature1(feature 18) calls for POST5; duplicate handle pointer, numeric ID, or parameter pointer rejects the chain. `296-304,534-538,578-579`: per-layer evaluate count and first-use reset; common user controls/guides intentionally applied to all maps. This proves separate caller contexts, **not private allocations/history inside signed NR**. |
| Reset behavior | `runtime/pipeline.cpp:300-304,369-380,576-580`: reset on first use, frame reset, generation change or nonconsecutive frame ID; successful whole frame updates last frame/generation only after all five. Global host frame IDs (`host/pipeline.cpp:213-214`; `host/wuwa_ingress.cpp:57,823`) could cause per-owner gaps if multiple owners interleave; frequent resets are possible, not demonstrated. |
| Final descriptor | `runtime/pipeline.cpp:424-426,545-548`: descriptor creation and composition both select `(passes-1)&1`. `runtime/codec.cpp:159-181`: decode binding 0=snapshot, 1=base, **2=final**, 3=decoded. Static sets refer only to owned textures. `runtime/pipeline.cpp:727-737` rejects changed pass count/dimensions/order instead of silently reusing wrong parity. |
| Actual codec payload | `runtime/codec.cpp:98-104` uses embedded SPIR-V. CPU byte comparisons show all three embedded payloads equal frozen `.spv` files. Retained `codec-decode.spvasm:21-30,262-264,460` shows final binding 2 fetched and output binding 3 written (not an unused GLSL-only declaration). Full GLSL/SPIR-V semantic equivalence and runtime descriptor contents are not established. |
| Native current-output commit | `runtime/pipeline.cpp:555-574`: only after all layers, compose, EndInterop succeed, copies decoded into **this request's** `r.frame.output`, restores states. No retained game-output descriptor in the Chain. No copy of L1/base on success; error path fails chain, does not silently publish one successful layer (`740-748`). |
| WuWa second commit | `host/wuwa_ingress.cpp:928-950,981-994`: normalized slot is runtime's output, then exact token commits to game output. `../adapters/format_bridge/bridge.cpp:544-558,818-837,871-923,939-961`: selects free slot, retains current external pointers, rewrites per-slot descriptors, returns owned_color as source/output; token/list/frame/call-count validated. `672-692,982-987`: reads owned_color and writes current external_output. `702-715`: submitted slot only becomes free after its fence completes. No stale initial-game-output cache found. |

### Exact five-layer schedule / overwrite ambiguity

`runtime/pipeline.cpp:511-535` (same selection at Create: `441-443`):

| Layer | `DLSSNR.Color` | `DLSSNR.Output` | Meaning of output contents after successful GPU work |
|---|---|---|---|
| 1 | base.read | ping0.write | L1(base) |
| 2 | ping0.read | ping1.write | L2(L1(base)) |
| 3 | ping1.read | ping0.write | L3(...), **overwrites L1** |
| 4 | ping0.read | ping1.write | L4(...), **overwrites L2** |
| 5 | ping1.read | ping0.write | L5(...), **overwrites L3** |

Within each call, input and output are different textures. L2/L4 share an input *address*, but not an input *content generation*; same for L3/L5. Caching the correctly configured **per-handle** input at Create alone would still select the right address at Evaluate, because that handle's selection never changes. It would not explain all five reading base.

POST1 and POST5 both end in ping0. A pointer log, descriptor dump, final ping0 capture, or two copies recorded only after the loop cannot distinguish L1 from L5. Labeling the same late ping0 as both stages creates false equality. L1 must be copied before L3 overwrites it; ideally immediately after L1, before L2 even reads it.

### Synchronization / lifetime assessment

- `runtime/pipeline.cpp:513-531`: previous output UAV -> SRV, compute shader-write -> shader-read (RAW); recycled output SRV -> UAV, shader-read -> shader-write (WAR). `539-543` adds a compute write -> read/write memory barrier after every Evaluate. The sequence has no obvious missing ping-pong dependency **assuming signed work honors the advertised layouts and compute stages**.
- Final compose transitions final UAV -> SRV -> UAV (`runtime/codec.cpp:220-240`); other read ping returns to UAV (`runtime/pipeline.cpp:549-554`). Base encode transitions read -> GENERAL -> read (`runtime/codec.cpp:188-209`). Symbolic 1..10-pass/two-frame model passes; this is not API validation.
- `runtime/interop.cpp:262-300`: layouts come from interop; queue families ignored, boundaries compute-scoped. Signed transfer/non-compute writes or unadvertised layout changes are not covered by a proof here. A successful NGX return is not a resource-state validation result.
- `runtime/pipeline.cpp:695,701,740-745,765-780`: recording serialized on CPU; same chain resources reused across frames without waiting for GPU retirement; queue identity checked only **after submission**. Normal single-queue ordered frames can safely reuse these images. Reversed recorded-list submission, changed queue, or deferred signed descriptor/map consumption is not prevented before recording. Queue mismatch fails after work was already forwarded, not before hazard. No evidence that these conditions occurred.
- `host/queue_hooks.cpp:224,267-290`; `runtime/pipeline.cpp:781-801,620-649`: post-forward same-queue Signal and background completed-fence sampling prove submission/completion of recorded work, **not five distinct images**. Retirement protects handles/maps/views/resources; it does not create per-layer history buffers.

## Remaining suspects / useful tests, in priority order

1. **Binding-consumption gap (unproven):** log/read back the exact core parameter map and nested VkImage/VkImageView/extent/ReadWrite immediately before each signed Evaluate; compare to its predecessor and inspect unexpected bare `Color`/`Output` defaults without setting them. A CPU fake-vtable recorder can check all keys/types and distinct map identity, including deliberately conflicting aliases. But a fake cannot establish the real core's alias rules or signed descriptor cache. No evidence supports adding bare aliases as a fix now.
2. **Borrowed history/cache assumption (unproven, important):** five unique handles do not prove NR internally copies temporal input/output. L1/L3/L5 externally share ping0 and L2/L4 share ping1. If signed history retains caller images rather than private history, those images are overwritten before later frames. Need a bounded signed callgraph/history-copy audit or later isolated test with dedicated per-layer outputs. Do not replace resources in live. Separate handles rule out accidental caller handle reuse, not this internal alias.
3. **Create/Evaluate shape mismatch (proven configuration, consequence unproven):** `runtime/pipeline.cpp:247-265` creates POST with Scale/ScalingRatio=.5, Upscaling=1 whenever work width > render width, but Evaluate sends 1/1/0. Generic/Input dimensions remain render-sized while Color/output subrects and images are work-sized (`266-277`). Check what signed Create caches (dimensions/layout/strides), whether scaling callback actually reconciles it; partial viewport writes/stale regions could mimic a weak extra pass. Not evidence that every layer receives original Color.
4. **Synchronization / cross-frame ordering (unproven):** fake command recorder should model exact RAW/WAR/WAW events, final restore, Begin/End failures, both distinct-layout and all-GENERAL mappings; reverse list submission and queue change tests should expose the admission limitation. CPU descriptor-lifetime test: hold frame A queued, configure frame B, ensure no per-frame descriptor storage referenced by A is mutated. Real signed state/stages still need separate evidence.
5. **Small raw deltas vs lost final deltas (unresolved):** five identical nonlinear transformations need not produce fivefold visual change. Decoder reads final, but `shaders/codec_decode.comp:29-35,87-100,131-144` clamps neural RGB to [0,1], reconstructs from original/proxy/final, and projects to original chromaticity at ColorStrength=0. This is an explicit composition path, not a bare-Color binding override. It can suppress differences or preserve mainly luminance changes; no actual control values/pixels were measured in this audit. Compare raw L1/L5 before blaming styles or transport.

Other scoped observations: optional pre-exposure is only set when valid (`runtime/pipeline.cpp:281-282`), so a retained map can keep an older value when validity drops; usage by this signed path is unproven. Codec descriptor sets are allocated but not freed on `release_chain` (`runtime/codec.cpp:124-131,146-150`; `runtime/pipeline.cpp:588-604`): eventual allocation failure, not evidence for same-input five times. These are secondary, not explanations proven for whitening.

## Bounded cached signed evidence

`signed-reader.txt` was generated from the retained NR DLL SHA256 `e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e`, **only** known reader RVA `0x19f30..0x1ac2a`. Color at `0x1a07f`, MVec `0x1a154`, Depth `0x1a234`, Output `0x1a317` each load the `DLSSNR.*` key and invoke Get through vtable +0x40. Color failure branches to nulling its field (`0x1a14a`), not a bare-Color fallback in this function. No bare `Color` key reference found in that reader. This supports the key names; it is not a full Vulkan Evaluate callgraph, internal cache audit, core setter ABI proof, current loaded-DLL identity proof, or a revalidated signature.

## Verification and next step

- `python3 cpu_audit.py`: 16 audited-input hashes, source binding/parity assertions, symbolic 1..10 passes across two frames, embedded/frozen SPIR-V equality; see `verification.txt`.
- `python3 signed_reader_probe.py`: bounded static PE decode only; see `signed-reader.txt`.
- `spirv-dis <frozen>/native/shaders/codec_decode.comp.spv -o <new-review>/codec-decode.spvasm`: CPU disassembly only. `spirv-val` passed for encode/decode/decode_r11 frozen modules; not runtime GPU validation.
- The highest-value next evidence is **GPU-retired, non-overwritten raw stage captures** from an explicitly authorized isolated diagnostic build; `CAPTURE_PLAN.md` specifies it. Nothing was implemented or deployed for that plan.
