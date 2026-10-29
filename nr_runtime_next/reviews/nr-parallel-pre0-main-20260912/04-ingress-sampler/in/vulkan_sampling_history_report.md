# NR Vulkan samplers and history update — 2026-09-11

## Result

**Vulkan mode 2 (A/C) is nearest, mode 0 (B) is linear. Both use normalized coordinates and clamp-to-edge in U/V/W.** This follows the actual sampler creation and NVX image-view-handle calls, not channel counts or the observed handle high words.

**H+60 is an NR-result history resource on the traced ordinary path, not a snapshot of selected Color.** It can be the network's direct output destination; alternatively the NR output is sent through a **separate compute copy kernel** into H+60. That kernel is **not `vkCmdCopyImage` or a proved byte/pixel identity copy**. The frontend has additional conditional paths; do not replace all of them with an unconditional `history = selected_color` or `history = output_pixels` assignment.

New CPU helpers cover sampler policy/ideal footprints and **opaque resource/dispatch/state planning only**. No history pixel-copy implementation or full temporal numerical recurrence is asserted.

## Scope / reproducibility

Read prior `nr-static-routing-20260911/REPORT.md`, `nr-vulkan-launch-abi-20260911/REPORT.md` and Main `nr-static-followup-main-20260911/RESULTS.md`. Main's already-observed first null B/C then nonnull B/C, mode integers and nonzero high words are supplied observations, not new captures by this worker. Current route is **NR_VULKAN**, not NVAPI_D3D12.

Exact DLL opened read-only:
`/home/user/.local/share/Steam/steamapps/common/Wuthering Waves/Client/Binaries/Win64/nvngx_dlssnr.dll`

SHA256 **e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e**. Preferred-image VAs, base **0x180000000**. `evidence.json` records offsets/hashes for **27 finalized host ranges, 10,463 decoded bytes**, plus small data/vtable reads. Exploratory bounded host slices and selected-operand/literal scans of the 699,904-byte `.text` were also used; finalized-byte count is not claimed to count every exploratory decode. No PTX prefix/prehead analysis, GPU, Wine, native PE execution, patch or deployment. All writes confined here.

## 1. Mode → sampler creation → handle, with API types proved

### Actual backend targets

Vulkan vtable **0x1800b40c8**:

| Slot | Target | Role in this proof |
|---|---|---|
| +a8 | **0x18004fb50** | Sampled image handle getter |
| +b0 | **0x18004fa70** | Storage image handle getter |
| +78 | **0x180046be0** | Common resource allocation wrapper |
| +258 | **0x18004e770** | Vulkan image/view creation |

The known indirect-call thunk at 0x1800ac428 jumps through RAX. Loader strings and stores independently identify:

- **0x18005149b..14ae:** `vkCreateSampler` → backend **+498**.
- **0x180051963..1976:** `vkGetImageViewHandleNVX` → **+520**.
- **0x1800519ab..19be:** `vkGetImageViewHandle64NVX` → **+528**.
- `vkCreateImage` → **+448**; `vkCreateImageView` → **+458** (`0x1800511cb..11de`, `0x18005125b..126e`).

### VkSamplerCreateInfo construction

Routine 0x180050240 initializes **R12=0** at **0x180050278** and preserves it through the creation slice. At **0x1800506c5**, the 80-byte sampler create-info starts **S=RBP-60**. Stores `506d1..506e1` zero its fields (padding +4..7 is not initialized or relied on). First call **0x180050734** writes its returned sampler to **backend+570**. Second call **0x18005075a** writes to **backend+580**; the only changed create-info field pair is a zero qword at **S+20**, instruction **0x18005073a**.

| VkSamplerCreateInfo member | Offset | mode 0, backend+570 | mode 2, backend+580 |
|---|---:|---:|---:|
| sType | 0 | 31 = SAMPLER_CREATE_INFO | same |
| pNext / flags | 8 / 16 | null / 0 | same |
| magFilter / minFilter | 20 / 24 | **1 / 1 = LINEAR** | **0 / 0 = NEAREST** |
| mipmapMode | 28 | **0 = NEAREST** | same |
| addressModeU/V/W | 32/36/40 | **2/2/2 = CLAMP_TO_EDGE** | same |
| mipLodBias | 44 | 0 | same |
| anisotropyEnable / maxAnisotropy | 48 / 52 | false / 1.0 | same |
| compareEnable / compareOp | 56 / 60 | false / 0 (unused) | same |
| minLod / maxLod | 64 / 68 | 0 / 0 | same |
| borderColor | 72 | 0 (not clamp-to-border) | same |
| **unnormalizedCoordinates** | **76** | **0 = VK_FALSE** | same |

Installed Vulkan header types/enums/offsets are independently compile-asserted in `layout_test.c`. Khronos `samplers.adoc`, fetched read-only over HTTPS and retained as a short hash-identified excerpt, explicitly states **VK_FALSE means image coordinates range zero to one**. Thus these are **normalized**, not pixel-coordinate samplers. No driver-specific interpolation precision is implied.

### Sampled getter uses exactly those sampler slots

At **0x18004fb50**, inputs are `(backend, resource, &out, mode)`:

1. Null resource stores zero and returns success. Non-null resource must have **resource DWORD+30 = 0**, else return -5.
2. **0x18004fb94..fbaf** builds `VkImageViewHandleInfoNVX` at RSP+20: `imageView=*(resource+0)`, **descriptorType=1 = COMBINED_IMAGE_SAMPLER**, `sampler=*(backend+570 + sign_extend(mode)*8)`.
3. backend byte **+854** chooses 64-bit (**+528**) versus 32-bit (**+520**) getter. The 64-bit result is stored unchanged; the 32-bit branch explicitly zero-extends EAX at **0x18004fc35** before the qword output store.

Therefore integer **2 selects +580**, **0 selects +570**, regardless of image format or sampled channel count. There is no bounds-check on the native sampler-table index; the CPU helper deliberately rejects all other modes, including unproved mode1.

The observed A/C high word **0x11** and B high word **0x12** are **not host-side enum values** in this implementation: the host stores the API result, rather than constructing those high words. Nonzero high words corroborate the **64-bit getter branch** (the other branch zeroes them), conditional on the proved producer. Their internal driver encoding and numeric stability are not recovered.

Storage getter +b0 uses the same image view but **descriptorType=3 = STORAGE_IMAGE**, sampler zero (`0x18004faa9..fac0`). This is the view used for network output and copy destination, not the sampled mode0 history handle.

## 2. Concrete history format / view creation

Allocator **0x180017840** names **H+60** `dlssnr_prev_output`, as prior routing proved. Its descriptor at RSP+40 is now followed:

```
+00 width=H.dword00       +04 height=H.dword04
+08 native-format=-1     +0c internal-format=2
+10 mipLevels=1          +14 flags=0
+18 usage selector=1     +1c/+20 H.28/H.2c
```

`0x180046be0` explicitly sets R9D=0, calls `0x180046c20`; that routine copies the descriptor through `0x180045b80` (first 0x24 bytes preserved). On a new allocation, **0x18004732b..734f** dispatches **+258** with the copied descriptor and that false native-format flag. This is not the unrelated +28 format-query method.

At **0x18004e7e8..7f2**, Vulkan creation maps descriptor **+0c** through **0x180050120**. Its actual jump table entry **0x1800501d0** (index2) targets **0x18005016f**, which returns **97 = VK_FORMAT_R16G16B16A16_SFLOAT**. Thus **RGBA16F is established by format conversion, not merely a diagnostic resource name**.

Image create-info: sType14, imageType1 (2D), dimensions H.0 × H.4 × 1, one mip/array layer, samples1, optimal tiling0, usage **0xf** for this usage selector (`0x18004e7f5..864`). API call **0x18004e956** uses backend+448. View create-info at **RBP+40** (`0x18004ead4..eb7c`) uses that same format97, viewType1 (2D), **identity RGBA component swizzles**, color aspect1, base mip0/count1, base layer0/count1. Returned view is saved at **resource+0**, image at +8, format at +24, width/height at +28/+2c (`0x18004ebba..ebf4`). These are precisely the fields read by the sampled getter and resource query.

This proves the **new native history allocation path**. Cache reuse, all imported A/C formats/swizzles, current image bytes and format conversion precision are not reconstructed. A's four sampled components and C's two are not used to guess those formats.

## 3. NR output routing and end-of-evaluation history

Use prior notation: **P** evaluated request, **H** feature record, **W** wrapper receiver. P+0 is selected Color/Backbuffer, **P+48 is `DLSSNR.Output`** (parameter read `0x18001a313..a325`, literal 0x1800aed80). These must not be conflated, although a caller may alias the underlying resources.

### A. Wrapper selects a storage destination before forward

Let **F** be wrapper's fifth argument (byte at its RSP+430). It comes from evaluation local **RBP-7e** at `0x1800197f5..97f9`. No current capture of F is claimed.

**0x180021f0e..1f8f**, successful path:

| Predicate | Network output resource Q | Tail-copy predicate T |
|---|---|---|
| F and CCNetwork cast succeeds and H+70 nonnull | **H+70** | true |
| Otherwise F and H+60 nonnull | **H+60 directly** | false |
| Otherwise | **P+48 (request Output)** | false |

Q is saved at RSP+98, storage-view getter +b0 supplies RSP+d8. That view is used as **network-forward output**, not as A: `0x18002277e..27c8` passes it as R8; range path uses the corresponding local via `0x1800227e7..2800`.

### B. Wrapper tail may dispatch Q → H+60, then sets valid

At **0x1800228aa..2932**, if **T && H+60 != null && W+80 != null**, call **0x18001c650**:

- source descriptor **RSP+128 = {Q, x=0, y=0, width, height}**;
- destination descriptor **RSP+110 = {H+60, x=0, y=0, width, height}**;
- width = H+8 if nonzero else H+0; height = H+c if nonzero else H+4 (resolved at `0x180021cd8..1d0d`).

Then **0x180022932 stores H.byte68=1**, even when any of those copy gates skips the dispatch. It is not conditional on GPU completion, nor proof the copy produced pixels. The caller also does not use this as a fenced transfer receipt.

### C. Outer evaluation's ordinary copy direction is conditional

After the wrapper call at **0x180019811**, special/fused predicates can skip this ordinary branch or select **0x18001c920** postprocessing instead (`0x18001983a..98a9`). For the ordinary **0x1800198ab..19907** branch, H+60 must exist:

- History descriptor D = `{H+60, 0,0, H.dword08,H.dword0c}`.
- O = original request's **Output descriptor at RBP+68** (Praw+48).
- Predicate **R = RBP-7c** selects direction with the actual two CMOVs:
  - **R=false:** source **O**, destination **D** — **Output → history**.
  - **R=true:** source **D**, destination **O** — **history → Output**.

R's construction at **0x180018f6d..8ffe** tests nonzero Output subrect offsets or extent mismatch against H.0/H.4 (querying resource size when descriptor extents are zero), and requires H+60. R=true forces F=true through **0x180019064..9077**. Thus it is unsafe to read the mere existence of a late copy as invariably Output→history.

For the ordinary equal-size/no-special path, F=false, the network writes **P.Output**, then the outer compute copy dispatches **P.Output→H+60**. For the size/subrect path, F=true sends NR to H+60 or H+70 (followed by the wrapper copy to H+60), and the outer copy dispatches **H+60→Output**. **Neither source is the selected-color descriptor P+0.** These establish resource-level NR-result history, not a pure selected-input-color history. “NR result” here means the network/finalpost output, not the pre-finalpost latent tensor; finalpost itself already uses A/B/C.

Special frontend processing is not silently equated to these copies: **0x18001c920** defaults its NR-result input to H+60 when its separately supplied source is null (`0x18001ca7a..ca7f`) and selects Praw+48 as storage output (`0x18001ca4a..ca6c`), then dispatches the other registered kernel (index0, `0x18001d164..d19f`). Its numerical compositing/UI behavior is not modeled here, and the helper rejects special/fused paths. Later frontend stages and application-level input/output aliasing remain boundaries; no all-configurations pixel recurrence is claimed.

## 4. The copy is a shader dispatch, not a byte copy

Actual **0x18001c650** receives source as R9 and destination as arg5:

- **0x18001c68a..c6af** obtains source sampled handle with **mode2**.
- **0x18001c6b5..c6cd** obtains destination storage handle via +b0.
- **0x18001c701/721** calls descriptor helper **0x18001c520** on each. It produces **six floats `{offsetX, offsetY, extentX, extentY, 1/resourceWidth, 1/resourceHeight}`**, falling back from zero descriptor extents to queried resource dimensions (`0x18001c596..c622`). These are physical-resource reciprocals, not subrect reciprocals.
- Destination extent supplies dispatch dimensions **ceil(width/16) × ceil(height/16)** on the positive bounded domain (`0x18001c89d..c8d7`).
- **0x18001c72a..c760** selects kernel index **1**. Actual registration table **0x1800e00f8** names **`cg2r_copy_kernel`**, with block **16×16×1**; initializer `0x18001daf0..db3b` consumes that table. Dispatch `0x18001da60` uses backend+140, the proved Vulkan NVX compute launcher.

There is **no `vkCmdCopyImage` call in this traced helper**. Source mode2 gives its sampler policy but does **not** prove its shader coordinate equation, bounds behavior, store rounding, alpha rules or exact resampling. The registration's name does not prove pixel equality. This review intentionally does not pretend to recover those by assigning Python image arrays. Exact shader body/ABI and store-format conversion are the next bounded task if pixel recurrence is required.

## 5. Reset / validity is control state, not image zeroing

- Wrapper pair gate (`0x180021d3a..1da2`, `0x180022067..210e`): supply B/C only if **H.byte68 != 0, P.Reset == 0, H+60 nonnull, MVec nonnull**; N setter's global gate can additionally zero the pair, as prior report proved.
- Allocation mismatch/release path **0x1800178cd..78ed** clears H+60 and H.byte68. New allocation has no proved image-clear operation here.
- Evaluation resource/dimension reconfiguration clears H.byte68 at **0x180018d12**, **0x180018dcf**; missing history clears it at **0x180018df8** and forces request Reset before allocation. These selected sites are not claimed to enumerate every write in the DLL.
- **A request Reset suppresses history use on that evaluation; it does not establish zero pixel contents or freeze future history.** Reaching the wrapper tail still sets H.byte68=1. The next non-reset frame can use the newly produced resource contents.
- **Validity is marked before the outer ordinary Output→H compute dispatch**, when that branch is used. It is host bookkeeping for ordered evaluation, not an independently checked copy/fence success flag. First-null/second-nonnull observed B/C is consistent with this, but does not prove image contents.

## Verification / limits

**9 tests pass**, including byte/hash/target checks, extraction of both create-info snapshots from actual Capstone-decoded stores (owned synthetic bytes, no API execution), all initialized sampler fields, independent format target, resource-state gates/directions, fail-closed special modes, and ideal normalized nearest/linear footprints. **Compiled Vulkan header assertions pass**; GNU objdump independently confirms sampler stores. `verification.txt` records commands/results.

`resource_reference.py` returns ideal footprint indices/weights and symbolic copy dispatches only. It does **not** implement hardware subtexel precision, resource reads, format/channel conversion, copy shader arithmetic, or a complete graph/temporal evaluator. Sampler/header proof is exact; mathematical ideal footprints are not native GPU parity. No training-origin or training-objective inference is made.

Reproduce from this directory:

```sh
python -B collect.py
python -B test_resource.py
cc -std=c11 -Wall -Wextra -Werror layout_test.c -o layout_test
./layout_test
```
