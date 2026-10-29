# Static-first logical reconstruction: first native output fragments

2026-09-11. User requests a logically consistent reconstruction, static-primary and dynamic-assisted, not visual parameter tuning. **This milestone is not a complete model or a validated native-equivalent forward.** All work here and the three linked reviews was CPU/static. No GPU/Wine/game/model launch, signed-DLL patch, runtime deployment or old forward-script modification.

## New substantive result

The old `dlssnr_full_pytorch.py` ends with an unconditional `clamp(rgb + residual * blend_scale * intensity, 0, 1)`. Its use of `block70.layer0.blend_scale` as that RGB residual multiplier is not the role recovered in the selected native path:

1. Host launcher VA `0x1800758a0` constructs a **184-byte aggregate**.
2. Aggregate `+0x30` is the literal FP32 **1/32**, not that serialized blend scalar. `+0x34` is the layer-name substring test `_rgb`.
3. `+0x68` instead receives the pointer bound from the **`blend_scale` weight-map entry**, via layer state `+8`.
4. In the selected SM120 kernel, the `+0x30` field scales three learned components. A conditional source-sample contribution and conditional range decode follow.
5. The `+0x68` half scalar participates in the **optional sigmoid-weighted sampled-texture blend**. Texture A/B/C bind to input-vector entries 2/3/4; their actual runtime resource identities are NOT established.

This is a specific correction to the reconstruction plan, not a claim that the model's darkening/3D behavior has been explained. Nor does it establish an overall scale-error ratio in the old output: the old learned tensors/layouts were themselves unvalidated.

## What was verified

### Byte provenance

`byte_contract.py` statically verifies exact-hash DLL -> unique RCDATA/WEIGHTS_HT -> extracted map -> safetensors, with **all 153 payloads byte-identical**, 147,683,778 payload bytes. The 152 layer tensor names correspond to the graph inventory; the extra named tensor is `block70.layer0.blend_scale`.

- DLL SHA256 `e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e`.
- Resource SHA256 `836f445d06ecd2e59bb9f17b84b91c143396fd76ccda1c9dc7fe81d5edd548f4`.
- `blend_scale` bytes `eb39` decode as the scalar half **0.73974609375**.
- Serialized F16 storage does **not** mean dense FP16 kernel matrices. Raw payloads, including NaN-like bit patterns, are never silently sanitized.

### Static native selection and layout constraints

See [layout review](../nr-static-layout-20260911/FINDINGS.md). The selected CUBIN is carved unchanged from PE `.data`, not assumed to reside in `.rsrc`. Hash `feb368ff5279a7408b1e55554db6e468d7f114a24b18b2af8d7e6989a410c612`.

Archived 4k/6k CUDA Nsight traces each record three executions named `cc_tinlayout_fused_post_block_swin_1h_32_fp8`. Merely finding function lookups in the old crashing nvcuda trace is NOT launch evidence. Archived events do not attest module hashes, and current D3D12 selection remains unverified.

Known constraints include 512-byte warp-oriented input slabs, FP8/FP16/FP32 mixed operations, a 184-byte aggregate, and two surface-store paths. Complete channel/weight permutations, runtime slab upload, surface descriptors and image-resource identities remain unknown.

### Small executable CPU references

`epilogue_reference.py` is deliberately **not** an image-to-image forward:

- `color_decode`: selected C440..C560 arithmetic, requiring already unpacked learned values and already sampled/aligned texture components, with explicit predicate states.
- `host_bound_color_decode`: applies the statically recovered 1/32 multiplier and `_rgb` name test. No guessed public NR control mapping.
- `weight_map_blend_alpha`: applies the named half scalar to an **already-computed sigmoid response**. It does not replace native MUFU.EX2/RCP with an unlabelled ordinary exp implementation.
- `execute`: follows the six FFMA.FTZ instructions at CF40..CF90 using the eight entry-register values. It preserves the staged FMA order instead of algebraically collapsing it into a different rounded expression.

The six instruction encodings (96 bytes) occur uniquely at CUBIN file offset 1,655,232 and are checked against their disassembly. A further 23 color-decode instruction sites are checked in the pinned disassembly. CPU arithmetic uses finite FP32 inputs, glibc fmaf in FE_TONEAREST, and explicit FTZ modeling; nonfinite/overflow domains fail instead of being silently replaced. **Native numerical corner-case parity remains untested.**

Ignoring rounding, the decoded branch with texture-A sample present has the form:

```
color = saturate(sample_A + learned_RGB / 4)
```

but the real reference keeps the preceding 1/32 multiply, sample_A/8 - 1/16 addition, x8 + 1/2 decode, predicates and separate rounding steps. Without the texture sample or without `_rgb`, different branches apply. The optional later blend is conceptually:

```
beta = saturate(sigmoid(learned_component) * saturated_half_scalar)
color = color + beta * (normalized_resampled_B - color)
```

Neither this description nor the CPU functions identify B as history, C as motion, or any coefficient as an exposed UI parameter. The tensor bindings/upload values still need to be followed.

## Verification

Main reran **62 CPU/static tests**: Main byte/fragment tests 33, graph/output review 10, PE/CUBIN bounds/parser tests 12, host-binding tests 7. All pass. Physical DLL hash was rechecked unchanged. Test logs and proof JSON files are retained here.

Coverage includes truncated/overlapping containers, duplicate names/JSON keys, raw-byte preservation, constant/branch decode behavior, finite zero/full blend, no invented final clamp in the six-FMA fragment, FMA-versus-unfused rounding, FTZ input/output handling, source-bounds suppression, and the distinct role of the blend scalar. These tests verify parsers and the small references, **not the full neural network**.

## What logical equivalence still requires

1. Resolve finalpost input-vector resource identities and the runtime packed-slab construction; keep the 1/32 and blend-scalar roles distinct.
2. Recover lane/channel permutations and the learned-output computation before these fragments. Operator-name inventories are not an operand DAG; a finite old PyTorch output is not evidence of correct computation.
3. Use a minimal original-native capture to check the launch aggregate, selected kernel and referenced descriptors/slab bytes. The older CUDA probes contain compatibility mechanisms that must be audited before reuse; do not casually run a helper that modifies signed-module memory. Prefer a separately verified isolated native entry without such modification.
4. Compare corresponding intermediate boundaries with explicit precision/rounding tolerances, then expand toward a full forward and temporal/history behavior. Current D3D12 correspondence is a separate check.

No dynamic step above was run this round. Existing game installations, frozen packages, historical model outputs and source artifacts remain untouched.

## Evidence directories

- [Graph/output assumption audit](../nr-static-output-20260911/REPORT.md)
- [Native kernel/layout audit](../nr-static-layout-20260911/FINDINGS.md)
- [Exact host field bindings](../nr-static-binding-20260911/REPORT.md)
- Main: `BYTE_PROVENANCE.json`, `EPILOGUE_PROOF.json`, `byte_contract.py`, `epilogue_reference.py`, test files and logs.
