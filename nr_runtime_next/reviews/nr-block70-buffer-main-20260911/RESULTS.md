# Native buffer metadata and PREBLOCK264 — Main verification

## Accepted evidence

Four isolated, Main-owned runs:

| Revision | Observer OFF | Observer ON | Runtime SHA256 |
|---|---|---|---|
| buffer metadata | 20260911-141353 | 20260911-141443 | 0fef444c8461b2cf6faeabfd429ff8020064394bd7186cb0710cafbb8f54d24b |
| +exact PREBLOCK264 capture | 20260911-142748 | 20260911-142838 | 5ca25ef7e0a5065c515324815a34fbf5ddf04a9eae436cc3882139498ed15f10 |

All returned exit 0 / Guardian 0 with signed NVIDIA disk files unchanged. All five RGBA16F pixel files in each run are byte-identical to the earlier frozen 121525 baseline. Scope: POST1, 768×432, two frames, owned D3D12/native Vulkan interop, synthetic guides. This is not game, SR, Present, image-quality acceptance or normal-teardown validation. Fast exit followed fenced readbacks. Normal reserve and pre-existing filename-identity IAT compatibility remain unchanged; no new signed-code patch was introduced.

`verify.py` reproduces the pixel comparison, actual argument/source identities, pointer relationships and address bounds. `VERIFICATION.json` retains the machine-readable results. Original buffer-only source/binaries/approval are preserved under `backups/buffer-only/`; historical runs were not replaced.

## Newly observed preblock values

Exact live entry: `cc_tinlayout_fused_pre_block_swin_1h_32_1_ds_fp8`, fatbinary c11e…d3d, 264-byte aggregate. The 264-byte size was independently checked in original ELF metadata (`PREBLOCK_ABI_CHECK.txt`) and the static host launcher. Capture only allows this exact added name, not all preblock variants. The second revision records pre/post/pre/post as `nr-kernel-args-01..04.bin`; sizes are 264/184/264/184. Log ordinals are not runtime cookies.

Both captured preblock invocations contain:
- effective tone/structure = 2 / 2;
- Style condition = 0.015625 = raw2/128;
- skin/structure overrides = 2 / 2;
- descriptor mode = 1, color gain = 0.0625 = 1/16;
- invocation counters 0, then 1;
- active source 432×768, padded output 448×768, downstream 224×384.

T0 matches the following postblock's selected Color/Backbuffer handle. T1 and T2 match its previous-output and MVec handles: null on invocation zero, nonnull on invocation one. T3 and external ControlMask T4 are null on both. **T3 being null proves no depth texture at this preblock slot on this path, not that every other depth consumer is excluded, and not whether the learned model encodes geometry.** T4 null does not mean automatic masking is disabled. Descriptor mode is not the UseAutoMask key.

Preblock's first output pointer equals the following postblock's `enc0skip`. Its weight pointer is the same pool base that reconstructs the post slab at +147429888 and blend scalar at +147429376. These are live pointer/argument relationships, not observed GPU payload bytes.

Static provenance and 26 independently rerun CPU tests: sibling `nr-preblock-binding-20260911` (11) and `nr-ptx-preblock-input-20260911` (15). Main's new preblock observer scenario plus six existing scenarios also passed native CPU and ASan/UBSan builds. The first embedding MMA remains F16 K16, not FP8.

## Buffer ownership metadata and read bounds

Post main/skip resolve uniquely to one observed live 32,562,176-byte workspace buffer. Slab/scalar resolve to a separate observed live 147,719,680-byte weight pool. Both report usage `0x20032`: STORAGE, UNIFORM, TRANSFER_DST, DEVICE_ADDRESS, **not TRANSFER_SRC**. No buffer usage, kernel arguments, GPU memory or command stream was changed by these observers.

Across the complete 97×57 post launch grid, the independently recovered read equations produce 688,128 non-padding load events for each input, with ranges contained inside the observed buffer intervals:
- main relative range [0, 2752512);
- skip relative range [0, 11010048).

This is address containment only. It does not prove bound-memory lifetime, queue ownership, GPU contents, completion, or safe readback authorization.

CTA (1,1) needs only 512 distinct main bytes and 2048 skip bytes. The sibling sparse-capture package proposes 11 spans totaling 24,368 bytes including the 21,808-byte slab. Its own shader compiled, but **no capture integration or GPU execution exists**. Missing exact cookie/list/fence association, bound-memory lifetime coverage and NVX synchronization/state evidence remain explicit blockers. Do not use transfer copies on these source buffers or infer permission from a buffer address.

## Remaining work

Continue ordinary Swin-family CPU reconstruction in parallel. Before any activation readback, implement and review the private recording/submission/fence bridge and memory-lifetime coverage, with negative mock tests. Sparse missing bytes must fail replay rather than be zero-filled. Real activation-to-native-output comparison, temporal recurrence and complete image-to-image/model numerical equivalence remain unproven. No training-objective or “3D equals dark/high contrast” conclusion follows.
