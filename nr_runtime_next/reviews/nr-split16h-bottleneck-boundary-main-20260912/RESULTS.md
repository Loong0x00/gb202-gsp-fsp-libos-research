# Main parallel work: block30 boundary, not waiting for QKV

## Exact targets and conditional execution

Architecture inspection identified block30's separate `proj_pool_512` and `final_head_512` layers before the first ViT repack. Exact plain FP8 entries were copied from literal module04; no source version or installed DLL was changed. The pool entry is80-byte ABI, **not restored yet**. The final-head entry is its own40-byte ABI:

- p0 input, p8 output, p16 weight slab;
- geometry factors at32/36; +24 unread by this entry.

The source's warp bits split both channel work and the two rows of4x4 spatial tiles. Main did **not** reuse the FFN's four-warp launch: this conditional test explicitly supplies CTA(32,8,1),grid(4,1,1),factors(8,8),z0. These agree with complete bounded source support, but **host-selected/live launch and producer ownership have not yet been independently accepted**.

`head_reference.py` executes the original stream with real block30/layer4 slab524304bytes, SHA
`3ab0bf4b8e4b55cd4f60a8473d9cb0100896c1fd8328179188db43e427a50a4c`.
The file range is resolved from the safetensors named header, not a guessed constant delta from raw HT.

All four CTAs reach originalret in all eight warps;2048 real independently checked MMAs per CTA,8192 total. Every one of65536 output bytes is produced exactly once. Original async/barriers/loops are retained. Output SHA:
`0bf88030e2ea19c70c6ae3e030df325748328b39163f5e2312897342128eb77b`.

This is evidence for an actual learned final-head computation in the chosen domain, not a padding/duplication workaround for the512/1024 transition. Complete typed input/output logical maps and host graph binding remain separate obligations.

## Conditional byte-level repack composition

That exact65536-byte output is supplied, unchanged, to the previously source-pinned byte-copy repack reference at factors8x8. Output also65536bytes, SHA:
`576d3dffbd65800f14da642069b5ea77c94b5025f08cfabd3f104b0970b3d1c9`.
Deleting the final source byte is rejected. No unknown bytes are filled.

This is an explicit conditional caller composition, **not recovered live block30→31 binding**. It yields N64; it must not be fed to the existing fixed-N128 FFN by inventing64 extra tokens. The pool stage, actual host geometries, N64 FFN admission and full graph connection remain open.

All work CPU/static only. No GPU, PE, Wine, installed/config/network changes. No native or whole-network equivalence claim.
