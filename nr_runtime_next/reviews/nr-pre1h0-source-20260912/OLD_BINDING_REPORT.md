# PREBLOCK264: concrete host/resource/control binding (CPU/static)

## Result

**All requested aggregate fields now have actual host-store provenance.** Main corrections to operation-based guesses:

- **+172 = effective `DLSSNR.LocalToneStrength`**, **+176 = effective `DLSSNR.LocalStructureStrength`**, each gated by a model-descriptor byte.
- **+180 = clamped `DLSSNR.Style` index / 128**, with a separate model-descriptor gate. **Not `DLSSNR.Intensity`.** This is a conditioning value; it does not change/override the original selected style or raw2 assets.
- **+184/+188** are derived from **`DLSSNR.UseAutoMask`, `DLSSNR.SkinStructureStrength`, `DLSSNR.LocalStructureStrength`**, with explicit mask-resource precedence.
- **+192 is model descriptor+0x61 normalized to 0/1**, **not a direct copy of `DLSSNR.UseAutoMask`**.
- **+196 colorGain is literal `0.0625` (1/16)**, not Intensity. PTX doubles it to half `0.125` before the separately rounded color normalization.
- **+200 is low32 of a per-layer 64-bit invocation counter**, initialized/reset to zero and incremented before dispatch. **+204 is its high32 host storage**, unused by this PTX, no longer unknown host padding.
- **+168 = (`DLSSNR.DepthInverted` effective request field != 0)**. However, **T3 is zero on the recovered frontend path**; assigning it the supplied `DLSSNR.Depth` resource would be wrong.
- **T0** is the selected Color/Backbuffer view, **T1** the named `dlssnr_prev_output` view, **T2** the `DLSSNR.MVec` view, **T4** the `DLSSNR.ControlMask` view. These have actual routing/store chains, not channel-count labels. T1–T3 are additionally zeroed when the **64-bit** invocation counter is zero.

These are conditional static bindings, **not captured frame values, live texture handles, sampler semantics, GPU completion or a full network execution**. The original 16-feature image/noise/guide input is preserved; nothing here establishes a 3D training source or objective.

## Source and proof boundary

Readonly physical DLL:
`/home/user/.local/share/Steam/steamapps/common/Wuthering Waves/Client/Binaries/Win64/nvngx_dlssnr.dll`

SHA256 **`e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e`**, **165,840,496 bytes**. All addresses below are preferred-image **VAs**, base **0x180000000**. Subtract base for RVA. `evidence.json` includes file offsets, original instruction bytes, decoded operands, source pins, and literal/table bytes.

Read the original preblock REPORT, `ingress_reference.py`, actual PTX entry, and prior binding/routing methodologies. Reused their read-only PE reader by import (never its writer). Capstone scans for selected xrefs were limited to the **699,904-byte `.text`**; retained proof decodes **22,519 bytes in 19 selected ranges**. Small `.rdata`, RTTI/vtable and `.pdata` reads only; full-file reads serve hashing/mapping, not whole-DLL analysis. No Ghidra, GPU, Wine, PE loading/execution, patch, PTX edits or model/source changes. All writes are in this review directory.

`binding_reference.py` is a finite-domain CPU transcription, not an ABI-complete launch implementation. It patches only the requested fields in a caller-provided 264-byte buffer; all transforms, dimensions and output/weight pointers remain caller-owned. Missing/mismatched ABI and unsupported inputs fail closed.

## 1. Exact entry-to-launch ABI gate — established statically

- Constructor **0x18005fbf0** compares descriptor type to literal **`CCTinlayoutFusedPreBlockSwin1H`** at **0x1800b1e50** (`0x18005fc53..fc69`). It installs vtable **0x1800b7d38** at `0x18005fc2d..fc34`, allocates **0xd0** state bytes, stores **S = *(layer+0x178)** at **0x18005fcfd**.
- Actual vtable **+8 → 0x180060cf0** (launcher), **+0x38 → 0x180061510** (initializer).
- Initializer inspects layer-name substrings `_ds` and `_fp8`; **0x180061641** selects the exact literal **`cc_tinlayout_fused_pre_block_swin_1h_32_1_ds_fp8`**, VA **0x1800b7e40**, when both exist. `0x18006166c..1683` chooses FP8 vs non-FP8 name. Backend virtual+0x20 lookup at **0x18006169a** is called with **32,1,1** creation arguments; returned handle stored to **S+8** (`0x1800616a0`), backend receiver to **S+0x10** (`0x1800616a4`). No runtime selection is presumed.
- Launcher entry RSP=Q; after five pushes and subtracting 0x1a0, **RSP=Q-0x1c8**, **RBP=Q-0xc8**. Therefore aggregate **A=RSP+0x70=RBP-0x90**. Do not reuse finalpost's RBP-0x80 origin.
- At **0x180060fd1..fdb**, `&A` is stored in local pointer slot RSP+0x50. **0x18006100c..1015** passes the address of that pointer slot at caller stack+0x28; **0x180060fea** passes byte count **0x108 = 264** at stack+0x30. Handle **S+8** enters RDX at **0x180061008**; backend **S+0x10** enters RCX at `0x180060fe2`. Virtual **+0x28** dispatch at **0x180061026**, through the independently checked JMP-RAX CFG thunk.
- Actual PTX has **one `.param .align 8 .b8 ...[264]`**, not 264 independent arguments and not the 184-byte postblock ABI. The same launcher also serves other preblock names; **size alone is not entry identity**.

**Gate for any later parent-owned capture:** bind the observed kernel handle to this exact entry (and observed module identity), verify one aligned-8 264-byte aggregate, and read it via the correct pointer indirection for the actual interception API. This review permits no capture itself. The prior observer's function creation is not submission evidence. `abi_gate()` checks the metadata tuple only; it cannot prove a live handle/name association.

## 2. Every requested store

All offsets in this table are **decimal aggregate offsets**. State offsets and VAs are hexadecimal. State is R11 in the launcher, loaded at **0x180060d78**.

| A offset | Host load | Host store | Concrete origin |
|---:|---|---|---|
| 168 u32 | S+88 at **60ed2** | RBP+18 at **60ed9** | effective request P+104 != 0 (`DepthInverted`) |
| 172 f32 | S+8c at **60edc** | RBP+1c at **60ee5** | P+e4 if N byte+68 else +0 |
| 176 f32 | S+90 at **60eea** | RBP+20 at **60ef3** | P+e8 if N byte+68 else +0 |
| 180 f32 | S+94 at **60ef8** | RBP+24 at **60f01** | normalized Style if N byte+6a else +0 |
| 184 f32 | S+98 at **60f06** | RBP+28 at **60f0f** | P+f8, derived skin override |
| 188 f32 | S+9c at **60f14** | RBP+2c at **60f1d** | P+fc, derived structure override |
| 192 u32 | S+a0 at **60f22** | RBP+30 at **60f36** | N byte+69 != 0 |
| 196 f32 | literal at **60f29** | RBP+34 at **60f31** | **VA 0x1800b80e8, bytes 00 00 80 3d = 1/16** |
| 200..207 u64 | S+c8 at **60f39** | RBP+38 at **60f40** | pre-increment invocation count; **60f44** increments S+c8 |

Abbreviated code addresses `60ed2` etc mean VA **0x180060ed2**. No argument field above is named from the PTX operation alone.

### Effective request → network setter → layer setter

Wrapper **0x180021bb0** retains effective request **P in R14**, feature state H in R12, and the successful CCNetwork RTTI cast in RSP+e0. At **0x180022548..2636** it calls network setter **0x18003f490**. The following are **caller pre-CALL stack offsets**:

| Wrapper slot | Value | Network-setter local after prologue |
|---:|---|---:|
| +58 | normalized P+104 (`DepthInverted`) | +148 |
| +60 | P+e4 (`LocalToneStrength`) | +150 |
| +68 | P+e8 (`LocalStructureStrength`) | +158 |
| +70 | computed Style f32 | +160 |
| +78 | ControlMask view | +168 |
| +80 | P+f8 | +170 |
| +88 | P+fc | +178 |

Delta **0xf0 = return address 8 + pushes 0x20 + local allocation 0xc8**. This avoids a one-slot Windows x64 ABI error. The network setter:

- **0x18003f4b6..4fd** gates tone/structure with N byte+68; **0x18003f501..507** gates Style with N byte+6a.
- **0x18003f51e** reads N byte+69. **0x18003f657..668** normalizes it with SETNE before passing it onward.
- Iterates blocks' actual first layer; RTTI at **0x18003f5d0..5f3** identifies **`CCTinlayoutFusedPreBlockSwin1HLayer@HNetCpp`**, descriptor VA **0x1811414b0**, before invoking the concrete setters.
- Calls **0x1800617a0** at `0x18003f642`; its **0x180061806** writes S+88 from the incoming depth flag.
- Calls **0x180061710** at **0x18003f689**. Tone/structure/Style enter XMM1/2/3 and are stored at **0x180061738/1746/174e** to S+8c/90/94. The two override stack arguments go through **0x18006171b/1740 → 1756/175e** to S+98/9c. Mode goes through **0x180061717 → 1721** to S+a0. ControlMask goes through **0x180061727 → 172c** to S+a8.

N+68/69/6a are not guessed UI flags: the network descriptor is copied to **N+8** (`0x18002794f..7956`), and copy routine **0x18001eedd..eef1** preserves descriptor bytes **+60/+61/+62**, respectively. Their original authoring labels/live values are not claimed. Holding a descriptor fixed, changing UseAutoMask changes overrides, **not directly +192**; model selection might separately change descriptor flags and is outside this equivalence.

### NGX key destinations, derived controls, and overrides

Reader **0x180019f30**, destination Praw in RDI:

| Literal key | Destination | Key-reference / getter VA | Getter missing/error fallback |
|---|---:|---|---|
| `DLSSNR.LocalToneStrength` | +e4 | **1a982 / 1a993** | 1 |
| `DLSSNR.LocalStructureStrength` | +e8 | **1a9b9 / 1a9c7** | 1 |
| `DLSSNR.UseAutoMask` | +f0 | **1a9ed / 1a9fb** | 0 |
| `DLSSNR.SkinStructureStrength` | +f4 | **1aa21 / 1aa2f** | -1 |
| `DLSSNR.Style` | +ec via temporary | **1aaad / 1aac0**, store **1aae6** | 0 |
| `DLSSNR.DepthInverted` | +104 | **1ab19 / 1ab27** | 1 |

“Missing/error” above is specifically the native `(return & 0xfff00000)==0xbad00000` condition, not a universal getter-success convention. Addresses have prefix 0x1800.

Reader **0x18001aa4b..aaa1** derives the overrides, finite values:

```
if Praw.ControlMask resource != null: UseAutoMask = 0
if UseAutoMask != 0:
    Praw.f8 = SkinStructureStrength if SkinStructureStrength >= 0
               else LocalStructureStrength
    Praw.fc = LocalStructureStrength
else:
    Praw.f8 = Praw.fc = -1
```

**Important actual-host caveat, not hidden raw-key equivalence:** evaluation first copies the reader's request to RBP+20 (`0x1800186e9..876e`), then calls **0x18001ac30** at **0x180018866**. This optional control-provider path can overwrite +e4/+e8/+e0/+ec/+f0/+f4 at **0x18001add4/adea/ae00/ae1c/ae2f/ae53**. It recomputes +f8/+fc via **0x18001b280**, called at **0x18001ae82**, with the same mask precedence/fallback. Provider IDs 1/2/3/4/5/6 are visible here; their external API/UI labels are **not** established. If that provider path is inactive, original getter values remain. Our bindings therefore say **effective named request**, not necessarily unchanged user-supplied NGX values.

Evaluation copies the resulting full request into final P at RBP+1c0 at **0x1800192fd..938c**, preserving the control offsets, then overrides only the leading 24-byte source descriptor (next section). It passes P to wrapper R8 at **0x180019800**, call **0x180019811**.

**Style normalization:** **0x1800224a9..250d** indexes the selected wrapper catalog record (stride **0xf0**) using wrapper+40 and reads its signed count at record+64. For a valid record and positive count C, the unsigned P.ec index is clamped to `min(index,C-1)`; otherwise zero. Converted to f32 at **0x180022500**, multiplied by literal **1/128**, VA **0x1800b0d6c**, at **0x180022505**. N+6a can subsequently force zero. No source/style asset is edited by this review.

`DLSSNR.Intensity` is genuinely read at **0x18001a922** into Praw+e0, but the proven preblock scalar chain above **does not use that field**. Do not bind Intensity to +180 or colorGain simply because it is another scalar control.

## 3. T0–T4: exact launcher and upstream identities

Let I be the launcher's actual second-argument vector. It is loaded at **0x180060d19**, count from end-start. Direct launcher construction:

| Field | Binding | Load/store VAs |
|---|---|---|
| T0 +0 | I[0], mandatory vector entry | **60d82 → 60dff** |
| T1 +8 | I[1] if count≥2 and S.c8!=0, else 0 | **60d8f → 60e1c → 60e28** |
| T2 +16 | I[2] if count≥3 and S.c8!=0, else 0 | **60d9c → 60e20 → 60e35** |
| T3 +24 | I[3] if count≥4 and S.c8!=0, else 0 | **60da6 → 60e2d → 60e3d** |
| T4 +32 | S+a8, independently of counter and I length | **60e41 → 60e48** |

It does **not** read I[4] as T4. The zero-counter predicate is **64-bit** (`0x180060df4..e2d`), while the PTX noise uses only the low32. At counter 2^32, seed is zero but temporal handles are not zeroed by this gate.

### Actual graph routing, with conditions stated

For **block index zero, no D+38 block-output edges, matching preblock first-layer type**, network forward **0x18003cc80** constructs the input prefix:

```
V = [ external_inputs[0], N.298, N.2a0, N.2a8, ... ]
```

This is proved by **0x18003cec2..cf60** (no-edge/index/type gates and external0 insertion) and **0x18003cf65/cfa2/cfda** (ordered state reads/appends). Additional external/runtime entries can follow. Layer forward **0x18002afd4..b046** uses descriptor+a8 as an ordered gather, then dispatches layer vtable+8 at **0x18002b3a6**, exactly as prior routing methodology proved.

Historical `graph-factory.log` block0 has type `CCTinlayoutFusedPreBlockSwin1H` and actual **layer+a8 = [0,1,2,3]** (lines 19–24). Thus, **when the stated block0 branch applies**, I[0..3] are exactly the four values above. No missing descriptor vector is silently inferred empty from a dumper's omission. This historical graph name is not proof that today's runtime selected the `_1_ds_fp8` entry; constructor/initializer/launcher proof is separate.

### Frontend resource chain (successful-view path)

- **T0 / E[0]:** wrapper **0x180021dae..1dcc** requests backend virtual+0xa8 with resource **P+0**, mode **2**, output RSP+d0. **0x180022739..2776** puts that output in a one-element external vector passed to network forward. Evaluation **0x180019390..93af** selected this resource descriptor from effective **`DLSSNR.Color` or `DLSSNR.Backbuffer`**. Getter destinations are Praw+0 / +a8. It is **not proven pristine original RGB**; named `dlssnr_original_color` is the separate H+50 allocation, not this direct binding.
- **T1 / N.298:** wrapper **0x180022085..209d** requests view of **H+60**, mode **0**, output RSP+c8. Resource allocator **0x1800178f3..794f** uses literal **`dlssnr_prev_output`**, destination H+60. Wrapper passes the view as RDX at **0x18002262e**, setter stores N+298 at **0x18003f4cc**.
- **T2 / N.2a0:** wrapper **0x1800220f0..210e** requests view of **P+18**, mode **2**, output RSP+c0. Reader's actual **`DLSSNR.MVec`** key at **0x18001a154** targets Praw+18. Wrapper passes view as R8 at **0x180022626**, setter stores N+2a0 at **0x18003f4d3**.
- T1/T2 frontend pair is allowed only when H byte+68 is set, effective `DLSSNR.Reset` field P+100 is zero, P+18 is nonnull and H+60 is nonnull (**0x180021d3a..1da2**, **0x180022054..207f**). Setter **0x18003f49d..4b3** additionally clears both if global byte **0x1800e06d0** is zero. These precede the launcher's separate counter-zero gate. Live state/resource contents are not known.
- **T3 / N.2a8:** wrapper unconditionally sets **R9D=0 at 0x180022623** immediately before setter call; setter stores R9 to **N+2a8 at 0x18003f4da**. Therefore T3 is **null on this path**, even though `DLSSNR.Depth` has a real getter into Praw+30. There is **no P+30 → T3** chain here. More general callers can supply N+2a8; no named depth identity for those callers is asserted.
- **T4 / S.a8:** reader **0x18001a3f0..a402** binds literal **`DLSSNR.ControlMask`** to Praw+60. Wrapper **0x180022328..235b** initializes output to zero and, if P+60 nonnull, requests mode **2** view into RSP+b8. **0x1800224a1 → 225b9** carries that output into setter caller slot+78; network **0x18003f67c..684** passes it onward; layer **0x180061727..172c** stores S+a8. That exact field is T4. Mask transform P subrect is separately built at wrapper RSP+178, copied via S+b0 to aggregate+112..135.

The mode integers above are literal backend API arguments, not asserted filter/address/normalized-coordinate enums. Prior resource-allocation/forward proof is pinned; no current Vulkan/D3D12/CUDA object identity or resource bytes are captured.

## 4. Counter and original feature interpretation

Constructor **0x18005fcf1** initializes S+c8 to zero; dedicated method **0x1800616e0** sets it to zero again (`0x1800616e7`). Network reset-like method **0x18003dc70** identifies first preblock layers by RTTI and invokes it at **0x18003dcda**. This review does **not** establish a direct `DLSSNR.Reset` → counter-reset invocation chain (Reset's frontend texture gate is separately proven above).

The host copies the old qword to A+200 then increments it **before dispatch**, so it is an invocation counter, not demonstrated global frame number, random-source entropy or completion count. Low32 wraps every 2^32 invocations; full64 controls the first-invocation temporal gate. Concurrent invocation behavior is not reconstructed.

The original input reference still supplies the exact vector:

```
[noise0,noise1,noise2,1, sourceRGB, guideRGB,
 H(Style_condition), tone_control, structure_control,
 skin_override_feature, structure_override_feature, 0]
```

The last four feature formulas remain those in the prior PTX report, including ControlMask Y/Z multiplication and mode-dependent sentinel/fallback logic. Host bindings give the real names, not new arithmetic. In particular +192 may remain 1 while UseAutoMask is off and overrides are -1. No full Swin replay, training interpretation, 3D claim, or raw2/style alteration follows.

## Verification and reproduction

From project root:

```sh
python -B reviews/nr-preblock-binding-20260911/collect_evidence.py
python -B reviews/nr-preblock-binding-20260911/test_binding.py
```

**11 CPU/static tests pass.** They verify exact DLL SHA, pinned inputs, every retained decode boundary/instruction byte transcription, vtable/name/264-byte dispatch, requested load/store offsets, intermediate Windows stack slots, actual literal key destinations, literal constants, gates/routing, style clamp, independent UseAutoMask/mode behavior, mask precedence, counter low32/full64 distinction/wrap and scoped patch preservation. One synthetic integration test patches the new bindings into an explicit 264-byte fixture and runs the **unchanged original PTX ingress CPU reference with real pinned block0 weights**: source=1 gives source/guide half 1/16, channel10=Style2/128, followed by tone=.25, structure feature=1, skin=.125, structure override=.75. Only T0 is sampled at counter zero. This is **synthetic**, not measured native arithmetic; the existing explicit libm approximate policy is retained.

GNU objdump independently checks the launcher/control-store and network-setter slices in `objdump-check.txt`. `verification.txt` retains commands/results. Main has a concrete ABI gate and host bindings, but **no live preblock submission/arguments, sampler implementation, resource contents, provider-override state or model-descriptor flag values have been observed here**.
