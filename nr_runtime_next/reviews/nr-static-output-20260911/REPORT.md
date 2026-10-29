# NR output-side static proof audit — 2026-09-11

## Result / implementation decision

**Do not promote the historical full-PyTorch output path into a logical reference.** The supplied graph-factory artifacts establish descriptor contents, operator-name inventories, and serialized tensor boundaries. They do **not** establish an operand DAG, output equation, control/history ABI, or packed tensor interpretation. None of the output-side numerical formulas is sufficiently demonstrated here to implement honestly.

Delivered a standard-library-only, fail-closed CPU scaffold. Its implemented operations are inventory parsing, explicit descriptor-pair transcription, and the separately serialized blend scalar's F16 decoding. All NR numerical paths raise `UnsupportedProof`, including intensity zero. No approximate fallback, tuning, model invocation, GPU/Wine/native loading, signed-DLL change, or CUBIN extraction was performed. Existing sources were read only.

## Evidence levels and provenance

- **Observed artifact:** literal bytes/strings/vectors in the existing dump, or verified weight/checkpoint payloads.
- **Dumper convention:** field names supplied by `dump_graph_factory.cpp`; not independently established native member names or an execution ABI.
- **Unsupported reconstruction:** arithmetic/layout/control conclusions not furnished by those artifacts. Unsupported does not mean the opposite formula has been proved.

`graph-factory.log` is an **existing historical factory capture**, not a capture made in this review. Dumper lines 187–192 call the factory at DLL-relative RVA **0x39780** with argument **0**. This does not establish every graph variant or execution path. Lines 3–5 identify `CCNetwork`, `hnet-vigilant-squid`, and `crazy-cuckoo`. In contrast, `build_architecture_manifest.py:87` **hardcodes** `CC_Control_History_Blend_Quantize_With_Teacher_honest_tench_2026_07_04_22_30_weights`; it is not parsed from the trace. That name alone proves no history/tone/control formula or version match.

All 152 layer operator inventories match `architecture.json`; rebuilding that JSON from the existing trace and manifest is byte-identical. This confirms transcription, **not** the historical README/docstrings' stronger claims of exact executable topology or logically equivalent ordinary-PyTorch operations. The bounded older research note's “RGB residual/control blend” is a summary, not new operand evidence.

## Exact evidence table

Line numbers are 1-based; byte offsets are 0-based, into the named file, preserving original CRLF. They are **not machine-code instruction addresses**. `source_excerpts.json` supplies exact line/byte cross-references; `evidence.json` includes numbered inventories for every focused block.

| Observation | Exact location / offset | What it establishes; boundary |
|---|---|---|
| Object block vector / descriptor strides | `dump_graph_factory.cpp:11–14,199–225`: object +0x70, block stride 0xe0, block layer vector +0x20, layer stride 0x170 | Capture's object interpretation. Block70 is at **0x3d40** in saved `graph-factory-blocks.bin`, whose size is 71×0xe0. Saved pointers are historical, not live addresses. |
| Post layer identity | log **2808** @ **0x4a67a**, **2809** @ **0x4a6db** | `cc_tinlayout_fused_post_block_swin_1h_32_rgb`, `CCTinlayoutFusedPostBlockSwin1H`. `rgb` is a name, not proof of residual semantics, channel order, tensor shape, alpha or ranges. “finalpost” in this report denotes this output-side target, not a newly resolved native symbol. |
| Block70 vectors | log **2804–2806** @ **0x4a590**, **0x4a5cd**, **0x4a610** | Dumper-labelled `input_blocks=[69,0]`, `input_block_outputs=[0,1]`, `completion_input_blocks=[0]`. Under that convention the explicit pairs are **(69,0), (0,1)**. This does not identify original RGB/history/control operands or establish that completion is an additional tensor input. |
| Block70 field offsets | dumper **220–225**; saved block70 +0x38, +0x50, +0x98 | Those three vectors occupy 16,16,8 bytes respectively. Saved +0x68,+0x80,+0xb0,+0xc8 triples are all zero. Log omissions elsewhere must not generally be defaulted to zero: dumper also suppresses invalid/unreadable/empty vectors. |
| Post operator inventory | log **2812** @ **0x4a81e**, layer +**0x58**; log2810 reports **1344=42×32 bytes** | Exactly 42 string entries. No operand identities, constants, dimensions, strides, convolution flags, normalization epsilon, output uses, or per-op edges. |
| Five-entry raw vector | log **2811** @ **0x4a7a9**, layer +**0xa8**, 40 bytes; log **2813** @ **0x4a9c1** | Values **[0,1,2,3,4]**. Consistent with that sole small valid vector, but its native meaning/arity is unproved. Do not name these entries RGB, history, tone, etc. |
| Separate blend scalar | `manifest.json` record `block70.layer0.blend_scale`; `WEIGHTS_HT.bin` **147406234 / 0x8c93d9a** | Shape [1], 2 bytes **eb39**, independently matching checkpoint `F16 [1]`: **0.73974609375**. Its numerical use, broadcast axis and connection to intensity are not proved. |
| Post payload | `block70.layer0.layer`, resource **147406312 / 0x8c93de8**, length **21808 / 0x5530**, end-exclusive **0x8c99318** | Serialized F16 container [10904], byte-identical to checkpoint payload. Flat container dtype/byte count does not establish matrix dtype, packing, orientation or channel roles. |
| Checkpoint cross-check | blend absolute file offset **147408912**, layer **147408914** | Header-validated F16 metadata and direct byte comparisons, without safetensors/torch imports or evaluation. Full artifact hashes match the historical manifest. |

**Dumper weaknesses relevant to “edges”:** `print_u64_vector` (`dump_graph_factory.cpp:107–123`) emits no field offset for layer `field=raw`. The all-offset scan (`241–243`) is heuristic and can reinterpret operator-string objects as integers: e.g. block67–69's 128 raw integers represent a 32×32-byte string-vector allocation, not 128 arithmetic edges. The builder parses only named **block** INDEX_VECTOR records and layer strings at +0x0/+0x20/+0x58; it drops all layer raw vectors. Consequently the JSON is not an operand-level graph. Block field names are authored at dumper220–225, not strings recovered from the native object.

### Block70 operator entries (zero-based, inventory only)

```text
 0 convolution        1 alias              2 mul                3 mul
 4 add                5 convolution        6 clamp              7 abs
 8 mul                9 rsub              10 mul               11 add
12 mul               13 convolution       14 mul               15 add
16 constant_pad_nd   17 convolution       18 linalg_vector_norm
19 clamp_min         20 div               21 linalg_vector_norm
22 clamp_min         23 div               24 mul               25 stack
26 bmm               27 add               28 clamp             29 _softmax
30 sub               31 detach            32 add               33 bmm
34 convolution       35 mul               36 add               37 mul
38 convolution       39 mul               40 mul               41 add
```

The last five entries **do not establish** `RGB + scale*intensity*prediction`, and `sub,detach,add` do not establish a straight-through or approximate-softmax forward equation. The two `clamp` entries cannot be assigned to RGB or bounds [0,1] from their positions. There is no literal `tanh`, `gelu`, or `upsample_bilinear2d` in this inventory; this alone is not proof that a fused implementation cannot implement related arithmetic.

## Nearby decoder: known connections versus guessed math

| Block | Explicit dumped descriptor pairs / relevant metadata | Historical shortcut, not proved |
|---|---|---|
| 39 | (38,0),(30,1); `CCDecInputUpsample`; inventory `convolution,convolution,mul,add` (log1866–1879) | `deep_skip + conv(deep)*dec_mix` (`full:444`) supplies its own operand assignments and omits any separately demonstrated second-convolution semantics. |
| 48 | (47,0),(22,1) | Bilinear resize, source slicing, projection+bias+skip. |
| 56 | (55,0),(14,1), shifted type | Same; `alias`/padding identity and layout unproved. |
| 62 | (61,0),(8,1) | Same. |
| 66 | (65,0),(4,1), 36 operators (log2746–2756) | Same (`full:201–206`), not a demonstrated native upsample contract. |
| 67–69 | `input_layers=[66]`, `[67]`, `[68]`; omitted output fields; log2760,2774,2788 | Preserve these raw fields; do not translate to block-output0 without consumer/default semantics. All three have identical 32-name inventories and 20672-byte payload lengths, **not** established identical weights/layouts. Block69 has `outview` in its type. |
| 70 | (69,0),(0,1); completion [0]; five-entry raw vector | Passing `(x,skip0)` alone does not implement any external-input or completion semantics. |

This supports the *declared skip-reference pattern*, not a complete executable decoder. Empty fields at stage boundaries and the mixed `input_layers`/`input_blocks` vocabulary specifically preclude casually asserting all default connections. The reference exposes paired descriptor indices only, not live tensor routing.

## Audit of historical Python assumptions

`full` below is `dlssnr_full_pytorch.py`; `middle` is `dlssnr_pytorch.py`.

| Area | Existing code evidence | Classification / required action |
|---|---|---|
| RGB residual equation | `full:471–473` (line473 byte **0x4dc9**) returns `clamp(rgb + residual.float()*(blend_scale*intensity),0,1)`; `residual=self.neural(rgb)` | **Guessed equation and operand identity.** No DAG connects original RGB, the separate scalar, intensity, or post output this way. Do not retain it as a reference. |
| Blend scalar | `full:375` byte **0x3e69** reads `.item()` | Scalar existence/value verified; its placement/multiplication is not. Also unproved whether a separately wrapped blend would duplicate native finalpost work. |
| Output tanh / clamp distinction | `full:180,194,473` | Current checked source has **no direct output tanh**. It uses GELU `approximate="tanh"` internally, standard softmax, and a final [0,1] clamp. Do not misreport an old output-tanh equation. The inventory's clamp/abs/rsub names do not prove GELU-tanh. |
| Output projection | `full:109–114,218–220`; line109 byte **0xf6d**, line219 **0x23f4** | Interprets leading bytes as 3×16 dense FP16 weights, eight params at relative96, first three as bias; selects first16 channels. Those arithmetic/layout assignments lack proof. Remaining five params are loaded but not used. |
| Post input merge | `full:161–164,207–211`; line210 byte **0x21f5** | Tail viewed as 32×16×1×1, bilinear resize with `align_corners=False`, first16 source channels, convolution + skip. Despite variable `post_depthwise`, call has no groups argument: this is not an implemented depthwise convolution. Neither this grouping nor merge formula is proved. |
| Post core / padding | `full:171–199`, `windows:57–77` | Ordinary GELU, normalization, attention, projection/residual and roll/pad logic are authored assumptions. Block70 type has no `shifted` substring, so this code's post window call does not shift, despite the inventory containing `constant_pad_nd`; no shift distance or padding contract is thereby established. |
| Decoder resampling | `full:201–217` | Bilinear upsampling and average-pool downsampling, channel truncation, interpolation geometry and add skips are unsupported. Type suffixes and convolution-name counts do not fix them. |
| Input range / channels | `full:397–401`; line400 byte **0x43b7** | Requires multiples of32, constructs 32 zero channels, RGB=`2*rgb-1`, channel3=1. Trace block0 contains `mul,ones_like,detach,cat,cat,...`, not their operands/constants/channel order. [0,1]→[-1,1] and filler channels are guesses. |
| Image I/O | `full:476–487` | PIL RGB, /255 and output clipping/8-bit rounding are frontend choices, not evidence for native HDR/SDR, linear/sRGB, pre-exposure, alpha or output limits. |
| History/control/tone | `full:381,471` signatures: `neural(rgb)`, `__call__(rgb,intensity=1)` | No history input/output, warp/motion/depth input, reset/validity logic, tone, structure, skin or mask path. Cannot prove these are disabled/unneeded; cannot assign five vector indices to them. Native/frontend controls mentioned in README are separate-layer observations, not finalpost formulas. |
| Attention/packing parity | `middle:30–47,126–151,194–218`; `full:27–41,180–199` | Raw reshape, sanitization, standard softmax, and GELU are not justified by byte counts or name order. The two files even choose different middle dimensions/interpretations (Swin head_dim32 vs16; ViT hidden4096 vs2048). Fitting byte counts proves neither layout nor logical parity. No such operations are ported here. |

## Small next proof target (static first; not tuning)

**Target: the actual output-store backward slice that consumes `block70.layer0.blend_scale` — not the whole Swin decoder.** The five trailing inventory names are only a search hint, never a proposed equation.

1. Start from the known factory RVA **0x39780**, post type/class strings and the `blend_scale` serialization key. Read-only host analysis should locate the post descriptor consumer/dispatcher, scalar load/binding, external-input binding, and destination output handle. Determine native meanings of block +0x98 and layer +0xa8 before treating them as tensor arguments. Record actual host RVAs/instruction bytes and input/output slot definitions; this review does **not** invent a finalpost function RVA.
2. Coordinate with the existing CUBIN/layout worker for the **already extracted** matched kernel identity/hash and parameter map. Do not duplicate extraction. Request the minimal machine-code slice from blend scalar load to final output store, with load origins, predicate paths, conversion/rounding, constants and operand uses. If scalar is only consumed on the host, prove that path instead. If it is unused in the selected variant, record that, rather than force a role.
3. Acceptance gate for a first numerical CPU function: every multiplicative/additive operand traced to a specific scalar/feature/input, channel order and strides known, operation order and precision known, store conversion and any saturation known, control/history/reset selection either resolved or explicitly excluded by a proven predicate. Keep an unsupported gate for every other branch. No output clamp, tanh, range transform or intensity-zero identity unless directly justified.
4. Only then add CPU golden tests from those constants/instructions: individual basis inputs, scalar bit pattern eb39, signed/out-of-[0,1] values, branch/predicate cases and proven rounding boundaries. Later dynamic comparison can validate that **small block** on identical explicit operands. Image appearance or parameter sweeps are not a proof criterion.

If the output-store slice requires too much unresolved packing, reduce the next target further to **external slot identification + scalar parameter binding**; that alone removes a major uncertainty without inventing arithmetic.

## Deliverables / verification

- `strict_output_reference.py`: fail-closed CPU contract and exact metadata helpers; no numerical model.
- `test_strict_output_reference.py`: 10 tests for all inventories, block70 observations, descriptor pairs, missing/invalid-field rejection, F16 scalar, explicit failures including zero intensity, historical output AST, and no accelerator/model imports.
- `collect_static_evidence.py`: reproducible read-only artifact checks; writes only beside itself.
- `evidence.json`: focused blocks, zero-based inventories, offsets, descriptor triples and verified block70 tensor payloads.
- `source_excerpts.json`: exact source lines and original byte offsets, including bounded historical note.
- `source_hashes.json`: SHA-256 and length of all source artifacts consulted. Resource hash **836f445d06ecd2e59bb9f17b84b91c143396fd76ccda1c9dc7fe81d5edd548f4**; checkpoint hash **890a53f05473dd6fd0980d1ca8501cfd84c1f6d7330b9531ca0981b6a6778d0e**; both verified against manifest.
- `architecture.regenerated.json`: byte-identical reproduction of historical JSON, **not** an enhanced executable graph.
- `verification.txt`: collection, tests and rebuild/cmp results.

Run from this review directory with `PYTHONDONTWRITEBYTECODE=1 python -B collect_static_evidence.py` then `python -B -m unittest -v test_strict_output_reference`. Historical builder is a pure text/JSON operation; the logged command regenerates only into this directory. Tests validate evidence handling/failure boundaries, not native numerical equivalence. Dynamic validation remains deliberately deferred.
