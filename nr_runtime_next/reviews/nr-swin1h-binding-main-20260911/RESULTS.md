# Actual Swin1H variant: TILESYNC, not plain

## Main-owned native metadata experiments

Runtime v1 SHA256 `e90b50e951c4d7d2b9b260f366113d89493ef63c45277adc9ed4e9d778c94c9b` added only the exact plain inpview name/96-byte ABI gate to the preceding pre264 observer. Original ELF independently proves the single 96-byte parameter (`SWIN96_ABI_CHECK.txt`). Eight ASan/UBSan mock scenarios passed.

- `144930-observer_off` / `145019-observer_on`: both succeeded, but **zero plain inpview submissions were observed**, despite successful function creation. This is retained negative selection evidence, not called a successful block1 capture.

Runtime v2 SHA256 `69caf30f906acfad284b759218cd6f15c727468db168171b6641bfdb331f7298` additionally permits the exact `cc_tinlayout_fused_swin_1h_32_1_inpview_tilesync_fp8` name, independently ELF-gated to 96 bytes (`SWIN96_TILESYNC_ABI_CHECK.txt`). Nine ASan/UBSan mock scenarios passed. The prior revision is preserved under `backups/plain-only/`.

- `145322-observer_off` / `145411-observer_on`: both succeeded. ON records pre264 / inpview-tilesync96 / post184 twice, six snapshots total, no drop/skip/coverage-gap records.

Every run: exit 0, Guardian 0, signed NVIDIA disk files unchanged. All five RGBA16F files in every run equal frozen 121525 byte-for-byte. Main's `verify.py` reproduces checks in `VERIFICATION.json`. Scope remains isolated POST1 768×432 two-frame native Vulkan via owned D3D12 interop, synthetic guides, normal reserve, unchanged identity IAT compatibility. Fast exit follows fenced output readbacks; **normal teardown, game/SR/Present and visual acceptance are not tested**.

## Actual 96-byte bindings

Both observed tilesync invocations use c11… fatbinary and grid `(48,28,1)`, block `(32,1,1)`, one 96-byte host extras aggregate:

- input `0x2507dc00` equals the preceding preblock's +248 downstream output;
- output `0x2531dc00`;
- slab `0x12c05600` equals the preblock-derived pool base +22016;
- +24..39 = H224, W384, origin(0,0);
- input dimension overrides +72/+76 = 0/0.

The existing static upload map assigns offset 22016 and size 20672 to `block1.layer0.layer`. These are pointer/slot/payload-identity relationships. **No GPU input/output/weight contents were read.** Addresses are opaque historical identifiers, not reusable pointers or lifetime proof. Other 96-byte fields must be interpreted against the actual tilesync PTX, not treated as the plain kernel's unused bytes.

## CPU result and remaining distinction

Sibling `nr-ptx-swin1h-20260911` now implements the complete **plain** inpview entry under explicit reference arithmetic: 5505 instructions, 256 FP8 MMAs, actual block1 slab and all four packed store paths. Main reran its 14 tests and artifact checksums successfully (`PLAIN_CPU_TESTS.log`, `PLAIN_CHECKSUM_TESTS.log`). Its output fixture is synthetic and does not become native data because actual pointer bindings are now known.

The observed native entry is **tilesync**. A separate CPU/static review at `nr-swin1h-tilesync-20260911` is in progress to prove/refute pure arithmetic equivalence and recover synchronization side effects. Do not silently substitute plain for tilesync, omit atomics or claim whole-block/native numerical parity. Full-model reconstruction and actual activation capture remain incomplete.

Changed files are confined to this review directory. `SOURCE_DIFF.patch` documents the three source-file differences from the preceding Main observer (two runtime observer files and its mock tests). No original PTX, frozen public ABI, installed game/configuration or signed DLL was edited.
