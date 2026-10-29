# NR finalpost: bounded CPU/static findings

## Result / confidence

**Useful native evidence recovered; not a complete tensor-layout reconstruction.** The exact requested DLL hashes to `e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e`. The retained 4k/6k Nsight SQLite traces actually record the unsuffixed FP8 finalpost kernel, not the simple-blend/control-mask alternatives. Its code proves a packed, warp-oriented FP8/FP16 computation followed by conditional residual/color decoding and a sigmoid-weighted texture blend into a 2D surface.

No GPU, Wine, PE execution, DLL modification, or full-model implementation was performed. All new files are confined to this review directory. Existing sources were opened read-only.

## Source chain and selection

- Resolved game `Client/Binaries/Win64/nvngx_dlssnr.dll` from `wuwa-runs/20260911-100724-native-pre_sr-3-initial-off-physical-user-operated/before-manifest.json`; hashed the physical game DLL. The model-dump DLL independently has the same hash.
- Bounded initial searches: project depth 4; then model-dump/model-probe/presr-static depth 3 for CUBIN/ELF/SASS. Only unrelated codec/prime and ISA-test CUBINs were found; no retained NR finalpost CUBIN was found in these scopes. This is not a whole-filesystem absence claim.
- The exact DLL contains 15 directly recognizable, bounded ELF64 CUDA images. Contrary to a resource-only assumption, these are in PE **`.data`**, not `.rsrc`; no decompression or resource rewriting is required.
- Carved only the image containing the selected function: DLL file offset `0x1f9220` (2,069,024), RVA `0x1fa820`, extent **2,789,376 bytes**, SM120, ELF flags `0x6007802`. The extent includes the trailing program-header table, not just section contents. CUBIN SHA256: `feb368ff5279a7408b1e55554db6e468d7f114a24b18b2af8d7e6989a410c612`.
- Selected symbol **86**, `.text` section **87**, CUBIN file offset `0x187280`, size `0xd080` (53,376 bytes): `cc_tinlayout_fused_post_block_swin_1h_32_fp8`.
- Architecture block70 names `cc_tinlayout_fused_post_block_swin_1h_32_rgb`, with edges from block69 output0 and block0 output1. This is a strong family/final-stage correspondence, not an independently captured host block-index-to-launch binding.

### Compiled vs observed vs current game

The selected image contains all five FP8 names: base, `simple_blend`, `simple_blend_full_rect`, `control_mask`, `control_mask_full_rect` (also non-FP8 counterparts). Presence is not selection.

`nvcuda-eval.trace` lines 331–335 are only **cuModuleGetFunction lookups**. That trace ends in a page fault, so it is not proof that these functions executed.

Stronger retained evidence is in `nsys-dlssnr-{4k,6k}.sqlite`, read using SQLite `mode=ro&immutable=1`. Joining `CUPTI_ACTIVITY_KIND_KERNEL.demangledName` to `StringIds.id` finds **three actual base-FP8 finalpost launches in each trace**, with no suffixed finalpost launches:

| Retained native CUDA trace | Grid | Block | Registers/thread | Static/dynamic shared |
|---|---|---|---|---|
| 4k | 481 × 273 × 1 | 32 × 1 × 1 | 168 | 0 / 0 |
| 6k | 769 × 433 × 1 | 32 × 1 × 1 | 168 | 0 / 0 |

These old native CUDA captures contain names and launch metadata, **not argument values or module-content hashes**. Matching symbol, SM and 168-register metadata corroborates selection, but is not cryptographic attestation that the profiled module equals this carve. **The current game's D3D12 execution path has not been verified against this CUDA kernel or layout.**

## Argument ABI recovered

`finalpost-elf.txt` contains the selected `.nv.info` only:

- One `EIATTR_KPARAM_INFO`: ordinal/index 0, offset 0, **size `0xb8` (184 bytes)**, CBANK parameter space. It describes one aggregate, not 23 independently named arguments.
- `EIATTR_CBANK_PARAM_SIZE = 0xb8`.
- `EIATTR_PARAM_CBANK = {0x7c, 0x00b80380}`: symbol124 is its `.nv.constant0` section; parameter base **`c[0][0x380]`**, length `0xb8`.
- `EIATTR_MAXREG_COUNT = 0xa8` (168); exits at `0xc240`, `0xcfe0`.
- The `c[0][0x358]` descriptor and `c[0][0x37c]` load are **outside** the argument aggregate; do not mislabel them user fields.

The following names are **operation-derived roles**, not recovered source identifiers. Offset = CB0 address minus `0x380`.

| Aggregate offset | CB0 | Width / demonstrated role |
|---|---|---|
| `+00` | `380` | 64-bit address, predicated 32-bit input loads |
| `+08` | `388` | 64-bit address, 512-byte-tile / lane×16 packed input loads |
| `+10` | `390` | output surface handle field; low word feeds both SUST instructions |
| `+18` | `398` | 64-bit packed parameter/slab address, many fixed-displacement loads |
| `+20,+24` | `3a0,3a4` | 32-bit integer extents used in bounds/index math (Y/X ordering in output bounds) |
| `+28,+2c` | `3a8,3ac` | 32-bit X/Y tile-origin offsets: CTA index×8 + origin |
| `+30` | `3b0` | FP32 multiplier on three learned output components |
| `+34` | `3b4` | 32-bit flag enabling ×8,+0.5,saturate color decode and alpha=1; also gates optional texture blending |
| `+38` | `3b8` | 64-bit texture-A handle, optional sampled RGB base |
| `+40..+54` | `3c0..3d4` | six FP32 texture-A coordinate transform coefficients |
| `+58` | `3d8` | 64-bit texture-B handle; five RGB samples in optional blend |
| `+60` | `3e0` | 64-bit texture-C handle; two-component sample feeding optional coordinate displacement |
| `+68` | `3e8` | optional 64-bit pointer to a **half scalar**; null gives 1, otherwise finite check and saturate |
| `+70` | `3f0` | 32-bit nonzero test enabling coordinate displacement |
| `+74..+a8` | `3f4..428` | FP32 transforms/scales for texture B/C; `424,428` multiply displacement components |
| `+ac,+b0` | `42c,430` | 32-bit image extents for source bounds and reciprocal normalized coordinates |
| `+b4..+b7` | `434..437` | not directly read in the selected disassembly; do not assign semantics |

**No host binding was recovered for NRIntensity/Tone/Structure/Skin or for the semantic names of textures A/B/C.** In particular, do not equate the half-scalar pointer or `+30` multiplier with a UI control solely from these operations.

## Small usable layout/epilogue evidence

All offsets below are **instruction offsets inside the selected function**, not DLL offsets. See `layout-epilogue-excerpts.txt`, or the complete single-function `finalpost-code.txt` / tool outputs.

### Packing constraints

1. **One warp per CTA, two store sites.** `SR_LANEID`, CTA.X/Y×8 appear at `0x0010..0x0110`; output coordinates are rebuilt from lane bits at `0x9690..0x9970`. The second store path increments the first Y coordinate by **4** at `0xc110`. Boundary predicates guard both paths. This is consistent with an 8×8 tile covered by 32 lanes writing up to two pixels each; it is not proof of the complete lane-to-channel permutation.
2. **Input `+08` is not plain NCHW contiguous FP16.** `0x0d10..0x0e90` forms `base + tile_index*512 + lane_id*16` and loads 128 bits/lane. The complete warp spans one 512-byte slab. Neighboring tile loads and lane SHFL/PRMT operations surround the computation. Tile index generation includes divided extents and boundary handling; a simple `.view(N,C,H,W)` cannot stand in for this packing.
3. **Mixed native precision is explicit.** `F2FP.SATFINITE.E4M3.F16`, `PRMT ... 0x5410`, `QMMA.16832.F16.E4M3.E4M3`, `HMMA.16816.F16`, packed `HMUL2/HFMA2`, and FP32 `MUFU` coexist. A scalar all-FP32 interpretation or a generic FP16 convolution does not preserve native rounding/packing.
4. **The `+18` slab uses fixed offsets**, e.g. loads at `+0x2050`, `+0x2090`, `+0x4cd0`, `+0x5130`, `+0x5330`, with lane-dependent base adjustments. This supports a packed parameter layout, not direct row-major semantic weight matrices. We did **not** recover the full weight permutation, all submatrix boundaries, or prove the runtime slab is a byte-for-byte upload of the serialized tensor.
5. Output uses **`SUST.P.2D.STRONG.SM.IGN`**, at `0xaa90` and `0xcfd0`, from the `+10` surface handle and `R52:R53` coordinates. There is no final linear `STG` into a presumed NCHW output. The code prepares three FP32 color components and a fourth 0/1 component; actual channel format/conversion requires the runtime surface descriptor and is not established by this carve alone.

### Residual/color decode, not an unconditional residual add

The first store path (`0x9d10..0x9fe0`) and second (`0xc250..0xc560`) implement the same shape of operations. Ignoring FTZ/rounding and writing operation-derived symbolic names:

```
rgb = learned_rgb * field_30
if texture_A_is_present_and_pixel_in_source_bounds:
    rgb += sample_A * 0.125 - 0.0625
alpha = 0
if field_34 != 0:
    rgb = saturate(rgb * 8 + 0.5)
    alpha = 1
```

The constants are directly in SASS (`0x3e000000=0.125`, `-0.0625`, `0x41000000=8`, `+0.5`). In the decoded branch with texture A present, algebra gives `saturate(sample_A + 8*field_30*learned_rgb)`, subject to native arithmetic. A reconstruction should preserve these gates rather than always treating the learned output as RGB or always adding it to the source.

### Optional sigmoid-weighted resampled blend

At `0x9ff0..0xa170` / `0xc570..0xc6b0`, null half-scalar pointer defaults to 1; otherwise a U16 load is converted from half, infinities are rejected and the value saturated. The extra blend requires a nonzero decode flag, both texture B/C handles, a positive scalar and source-coordinate bounds.

The blend samples two coordinates from texture C and optionally offsets the lookup (`field_70`, scales at `+a4,+a8`). It builds cubic-like interpolation weights using `-0.5,1.5,2.5`, and combines **five texture-B RGB samples**, normalized by the sum of their weights.

`0xa7e0..0xa8c0` (also `0xcd20..0xcdf0`) uses `-1.442695...`, `MUFU.EX2`, `+1`, reciprocal and saturate:

```
beta = saturate(sigmoid(learned_fourth_component) * half_scalar)
rgb = rgb + beta * (normalized_resampled_B_rgb - rgb)
```

The final three FMAs are explicit at `0xaa30..0xaa50` / `0xcf70..0xcf90`. This sigmoid is **not** the stored alpha; alpha remains the preceding 0/1 component. No claim that texture B is temporal history is needed to use this observation.

## Serialized payload cross-check (CPU only)

`block70-payload-check.json` checks exact bounds and byte equality between the two supplied serializations, without importing torch:

- `block70.layer0.layer`: 10,904 F16-designated elements, 21,808 bytes; WEIGHTS_HT offset 147,406,312; safetensors data-relative bytes `[147394850,147416658)`.
- `block70.layer0.blend_scale`: bytes `eb39`, half value **0.73974609375**, WEIGHTS_HT offset 147,406,234; safetensors `[147394848,147394850)`.

Both are byte-identical. **This does not bind `blend_scale` to any specific native argument field**, establish semantic matrix ordering, or establish how the runtime prepares FP8 data.

## Concrete remaining blocker / next plan (not executed)

The static carve and archived kernel-event traces lack the **184-byte launch aggregate values, surface/texture descriptors, host field bindings, and runtime packing transformation**. Therefore this finding is enough to constrain a reconstruction's finalpost semantics and packed-input ABI, but insufficient for a logically complete byte-exact mapping or a current-D3D12 equivalence claim.

Next CPU step: follow the host launch-aggregate construction and upload/repack calls for the exact DLL, correlating the aggregate offsets above to resource identities and slab generation. A later separately authorized native CUDA capture could record the 184 bytes plus referenced descriptors/slab boundaries for one launch, then test small CPU pack/unpack cases. A D3D12-path capture would be a separate requirement. **None of those dynamic steps were run.**

## Reproduce / verification

From this directory:

```
python -B static_extract.py
python -B -m unittest -v test_static_extract.py
python -B inspect_selected.py
```

12 tests pass: truncation, hostile offsets/counts, PE boundaries, ELF section/program ranges, SHT_NOBITS handling, strings, SM120 flag decoding and exact carved extent. Initial test expectation for string-table length was corrected from 272 to 273; final passing log is `tests.txt`.

`source-manifest.json` records physical sources/hashes and the compact 15-image inventory. `inspection-manifest.json` records commands, tool versions and script hashes. readelf, nvdisasm and cuobjdump all parse the selected CUBIN; only one function's disassembly and selected metadata are retained. No large all-kernel dump is retained.
