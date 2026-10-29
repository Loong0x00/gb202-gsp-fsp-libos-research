# Finalpost host binding — one bounded CPU/static pass

## Result

**Recovered concrete bindings for every requested field**, including a named `blend_scale` → state pointer → aggregate `+0x68` chain. **The FP32 learned-RGB multiplier at `+0x30` is a literal `0.03125` (1/32), not the separately serialized blend scalar, in this host launcher.** No UI mapping is asserted.

Physical source opened read-only:
`/home/user/.local/share/Steam/steamapps/common/Wuthering Waves/Client/Binaries/Win64/nvngx_dlssnr.dll`

SHA256 verified on each collector/test import:
`e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e` (165,840,496 bytes).

This is static construction/binding proof for the named host CUDA family, **not** a capture of argument values, an upload-byte proof, or current-game D3D12 equivalence. The parent owns serialized-byte provenance and GPU tail-reference work; neither was duplicated here.

## Identity and aggregate anchor

All addresses below are preferred-image **VAs**, image base `0x180000000`; subtract that base for RVAs. `binding-evidence.json` also records exact DLL file offsets and instruction bytes.

- Constructor **`0x180074b70`** compares the descriptor type against `CCTinlayoutFusedPostBlockSwin1H` at `0x1800aff30` (`0x180074beb..bf2`). At `0x180074bad..bb4` it installs vtable **`0x1800bc530`**. It allocates 0x118-byte state and saves its pointer to layer-object **`+0x178`** at `0x180074cc9`.
- Vtable slots: `+08` → launcher **`0x1800758a0`**; `+30` → weight binder **`0x180075ce0`**; `+38` → kernel initializer **`0x1800760a0`**. These are actual table bytes, not inferred function names.
- Initializer `0x180076155..6189` selects the exact string **`cc_tinlayout_fused_post_block_swin_1h_32_fp8`** (`0x1800bc628`) when the layer name contains `_fp8`; otherwise the non-FP8 base name. The backend lookup result is retained at `0x18007619e`, then saved to state **`+0x10`** at `0x1800762eb`. Initializer also prepares the four suffix variants separately. This resolves the named post family, unlike the older supplied ordinary fused-1h logs, whose launcher used 0x60 bytes.
- Launcher loads state `S = *(layer+0x178)` into RBX at **`0x180075906`**. Its aggregate starts at **`A = RBP-0x80`**, proven by `LEA RAX,[RBP-0x80]` at **`0x180075b8c`**, pointer save at `0x180075bac`, and address-of-that-pointer passed at `0x180075c0c..c11`.
- State `+0x98` is the variant selector (`0x180075b0a`, `0x180075b62`). **When zero**, state `+0x10` supplies the base kernel handle (`0x180075bb8`) and argument byte count is **0xb8**, via `0x180075bea..c07`. Selectors 1–4 choose suffix handles and a larger 0x138-byte argument. Dispatch at **`0x180075c25`** calls backend-vtable **`+0x28`**, loaded at `0x180075c21`; its receiver is state `+0x38`.

Thus the first 184 bytes are demonstrably passed with the base finalpost handle on selector-zero, matching the previously carved single-aggregate ABI. This does not attest a particular runtime module hash or that the current game selects this branch.

## Requested field stores

Here `I` is the vector start loaded from the launcher's second argument at `0x1800758c7`; `N = (end-start)/8`; `O` is the output-vector start from its third argument at `0x1800758e6`. Entry numbering is zero-based. No semantic texture identities are inferred from it.

| Aggregate field | Proven host origin / gate | Exact load → store VA |
|---|---|---|
| **`+30` FP32 multiplier** | **constant 1/32**, bytes `00 00 00 3d`, VA `0x1800bc9a8`, file offset `0xbbba8` | `0x1800759d2` `MOVSS XMM0,[RIP+...]` → **`0x180075a1f`** `MOVSS [RBP-0x50],XMM0` |
| **`+34` decode flag** | normalized `layer_name.find("_rgb") != -1` | helper call `0x18007596b`; compare `0x180075992`; `SETNE AL` `0x180075a1c` → **`0x180075a24`** `[RBP-0x4c]` |
| **`+38` texture A** | `I[2]` if `N>2`, else 0 | `0x180075a3c` → **`0x180075a40`** `[RBP-0x48]`; zero at `0x180075a70` |
| **`+58` texture B** | `I[3]` if `N>3`, else 0 | `0x180075a5c` → **`0x180075a60`** `[RBP-0x28]`; zero at `0x180075a86` |
| **`+60` texture C** | `I[4]` if `N>4`, else 0 | `0x180075a6a` or zero at `0x180075a8a` → **`0x180075a94`** `[RBP-0x20]` |
| **`+68` half-scalar pointer** | `*(S+8)`, bound from the first qword of map value named **`blend_scale`**, absent key gives 0 | **`0x180075a98`** `[RBX+8]` → **`0x180075aa0`** `[RBP-0x18]` |

The name search uses layer-object string **`+8`**, needle `_rgb` at **`0x1800b2048`**, start index zero (`0x180075949..596b`). Helper **`0x18003cb80..3cc76`** returns character offset or -1. The integer flags from the comparison at `0x180075992` survive to `SETNE`; intervening instructions are only MOV-family/XORPS, not integer XOR. The subsequent texture-A branch overwrites XMM0 **after** the `+30` store, so it does not change the proven literal.

Additional direct bindings, retained in JSON:
- `+00 = I[0]` (`0x1800759ff`); `+08 = I[1]` (`0x180075a07`). The literal validation error calls these two inputs “main + enc0 skip”; upstream graph-to-runtime-vector routing was not followed.
- `+10 = O[0]` (`0x180075a0e`), with validation string “1 output (CudaSurface)”. Surface format is not recovered.
- `+18 = *(S+0)` (`0x180075a15`), from map key `layer` through binder store `0x180075f8b`.
- `+70 = (layer byte +0x188 != 0)` (`0x180075aa4`), default zero in constructor. No control/UI label assigned.

## Named `blend_scale` pointer chain

The binder's second argument is a string-keyed map. Existing `ghidra-weight-bind.log` establishes the compatible node layout (string at node+0x20, value at node+0x40), and this selected binder's native comparisons/loads independently expose those offsets.

1. **`0x180075e85`** loads `R12 = *(layer+0x178)`, retaining state S for later stores.
2. **`0x180075fa0..5faf`** constructs an 11-byte string from **`0x1800b21c8 = "blend_scale\0"`**. **`0x180075fbf`** calls lookup helper **`0x18001e290`** with this key. Subsequent code checks the returned node's sentinel and compares its string (`0x180075fd0..6001`). A failed match substitutes the map sentinel.
3. **`0x180076037`** compares the candidate with the map sentinel. If present, **`0x18007603c`** loads **`R13 = *(node+0x40)`**; otherwise R13 remains zero. **`0x180076040`** stores **`*(S+8) = R13`**. No floating-point conversion or multiplication is performed here.
4. The launcher reads exactly `*(S+8)` at **`0x180075a98`** and stores it into **A+0x68** at **`0x180075aa0`**. The independently carved SASS interprets that field as an optional pointer to one half value.

**What is now justified:** the map entry named `blend_scale` supplies the pointer consumed by the kernel's optional half-scalar path, not the host literal `+30` multiplier. **What is not yet justified:** that this runtime map entry points at an unmodified upload of the specific serialized `eb39` payload, its lifetime/allocation/transfer path, or its relationship to any UI control. No host upload routine was traced or executed. This is intentionally a small completed binding proof, not a complete model proof.

The upstream origins of `I[2..4]` remain unresolved. In particular, do not rename them original image/history/motion/control or identify them with the five dumped graph-vector entries merely because the counts line up.

## Scope and verification

- Read both prerequisite reports and all three supplied small decompiler logs. **Did not open or modify the existing quick2 Ghidra project**; no Ghidra run was needed.
- Capstone 5.0.7 decoded only the 699,904-byte PE `.text` for RIP-relative references to bounded `.rdata` name searches, then five selected host ranges. PE resource contents were not analyzed; whole-file reading served source hashing/mapping only. No full-DLL autoanalysis, GPU, Wine, native PE execution, patch, extraction or tensor/model evaluation.
- `host-xrefs.json` records original named-string references. Its historical `function` keys are containing **.pdata fragments**, not always full function extents. The focused text dumps join the contiguous fragments of the selected methods explicitly.
- GNU objdump independently confirmed the crucial constant, flag and pointer/texture store slice; retained in `objdump-binding-check.txt`.
- **7 CPU tests pass**, checking source hash, vtable targets, every recorded aggregate offset/store byte sequence, literal value/load, flag-preservation slice, named-weight pointer instructions, and base-handle/184-byte dispatch instructions. They validate static transcription, not native execution parity.

Reproduce, from project root:
```sh
python -B reviews/nr-static-binding-20260911/inspect_binding.py
python -B reviews/nr-static-binding-20260911/collect_proof.py
python -B reviews/nr-static-binding-20260911/test_binding.py
objdump -d -M intel --start-address=0x18007598e --stop-address=0x180075aa8 \
  '/home/user/.local/share/Steam/steamapps/common/Wuthering Waves/Client/Binaries/Win64/nvngx_dlssnr.dll'
```

All writes are confined to **`reviews/nr-static-binding-20260911/`**. No unrelated project files changed. Stop point reached: concrete host binding recovered; no additional whole-model/upload investigation attempted.
