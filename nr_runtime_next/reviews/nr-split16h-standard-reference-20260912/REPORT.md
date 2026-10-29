# Block24 standard Split16H — CPU forward-only milestone

## Result

This review recovers **only** the two requested literal module-04 entries:

| graph layer | literal FP8 entry | ABI / CTA grid / warps | exact block24 slab |
|---|---|---|---|
| 0 | `cc_split_swin_16h_ffwd_512_fp8` | 56 B: `src@0,out@8,slab@16,H/W@24`; `(ceil(W/8),ceil(H/8),2)`, 8 warps | 524288 B, `0b034c80…908059` |
| 1 | `cc_split_swin_16h_ffwd_proj_512_fp8` | 72 B: `src@0,skip@8,out@16,slab@24,H/W@32`; `(2*ceil(W/8),ceil(H/8),1)`, 4 warps | 263168 B, `2c51c65e…ab8d22` |

`standard_reference.forward_first_two(h,w,v0)` is a usable bounded CPU forward for `F = layer0(V0)` then `P = layer1(F, skip=V0)`. It requires complete finite E4M3 byte spans, exact slabs, explicit standard route, valid geometry, and an explicit MMA policy. It does not synthesize missing source/skip bytes, join neighboring slabs, or repack `F` before layer1.

At 8×8 the confined synthetic finite witness produces:

* `F` SHA-256 `1ebf2a3fe5c6fc49205ec338c15bb9c9235ba614f94cb79212ea96be3c231c26`
* `P` SHA-256 `d237334d5a508ec7e8116c8dc09e7baf3c7b01ce3ae6e9fd5436b7a60b385e7b`
* 12,288 dynamic MMAs, with every actual 32-lane A/B/C fragment compared to an independently implemented finite E4M3 dot + RN-half-C oracle.
* 819,200 independently checked half scalar operations, actual source store byte-map ownership, full layer0/layer1 slab-byte coverage, four original 9-epoch barrier sequences, reverse-warp schedule equality, and a residual perturbation that changes layer1 output.

The source byte-map test uses the producer/store equations from the literal final address/register sequence and compares the actual output offsets; it is not an `(offset,offset)` constructed identity map. The MMA callback receives actual VM lane registers, not a reconstructed dense/checkpoint axis.

## Provenance

`architecture.json` directly identifies block24’s four slabs as `524288, 263168, 917568, 263168` bytes. This review independently re-reads raw `WEIGHTS_HT.bin` at source offsets 8696397 and 9220761 and checkpoint payloads `block24.layer0.layer` and `block24.layer1.layer`; each raw/checkpoint/retained slab byte sequence is equal. `PROVENANCE.json` records paths, offsets, module line slices, and hashes.

Both retained PTX files are exact literal slices from `reviews/nr-ptx-bundle-20260911/modules/module-04-dll-00bd0990.ptx`. No `inpview`, `wait`, `chained`, or tilesync entry is accepted. The local helper contains only generic parsing/arithmetic support inherited from the two requested reference families; this review derives its own standard ABI, shared ranges, mbarrier counts, warps, grids, and source/store map equations.

## Boundary

This is **verified CPU instruction-reference equivalence for this bounded first-two-layer execution**, not native GPU equivalence or a standalone whole neural model. The reference uses explicit finite RN policies and does not claim native tensor-core accumulation/rounding parity. No native golden activation was available.

Layers 2 (`qkv_shifted`) and 3 remain deliberately unexecuted; no shift is inferred from the layer2 name, and no causal analysis is started. The known 4h/226 numeric gap remains unresolved and is not hidden by a precision claim. A captured live predecessor byte bridge, complete attention policy/layout proof, later layers, and CPU/GPU/native end-to-end equivalence remain required before the user’s final standalone-model goal can be claimed.

## Reproduce

```sh
cd reviews/nr-split16h-standard-reference-20260912
PYTHONDONTWRITEBYTECODE=1 python3 -B verify.py
```

The verifier runs only `test_standard_reference.py` and writes nothing. `TESTS.log` is the recorded confined run.
