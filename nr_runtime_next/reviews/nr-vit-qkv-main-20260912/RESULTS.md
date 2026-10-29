# Main took over and completed bounded original QKV CPU forward

No replacement agent was launched. Main searched only the named regular module05 PTX, the pinned DLL's .rdata/.text sections and named safetensors header entries. The stopped95-minute recursive-search task supplied no QKV result and is not credited for this work.

## Independently recovered identity and host contract

Exact entry: `cc_vit_1d_qkv_fp8`, source93311bytes, SHA
`d9c05b923ffcf28e047adb1d9cda1a958191d7811051dda5feb0172cf9ef9917`.

Its own ABI is **80bytes**, not the FFN's72:

| offset | static host binding / original source role |
|---|---|
|0|I[0], feature input|
|8/16/24|O[0]/O[1]/O[2], separate Q/K/V outputs|
|32|layer-state weights|
|40|O[3], split counter|
|48|optional temp output selected through host vector metadata; three half planes when supplied|
|56/64|other route flags; unread by this plain entry|
|72/76|geometry factors, product N|

Factory class string `CCVit1DQKV` leads through call434f0 to ctor712a0. Its own vtable BBA48 has forward+8→72e40 and init+38→73a50. Main retained bounded PE fragments (including split .pdata pieces), rather than treating a partial fragment as the whole function. Init sets CTA(32,4,1). Forward records0x50bytes and grid(16*ceil(N/128),1,2). The descriptor configuration independently records1024 features and32/32 head fields. This establishes static launch/binding facts, not live branch truth or workspace ownership.

The real block32/layer2 slab is3145856bytes at checkpoint44009026, SHA
`b46023eb5092ddcec3a1f40dd6058fc3d8a888bfa50834a639c5b3fefbe0cf05`.
Its **first128bytes are32 F32 head-scale values**, addressed as4*(2*group+warpParity). The FP8 matrix begins after128 and occupies3145728bytes. This is source-backed; it is not an assumed128-byte tail or dense-F16 reinterpretation of the serialized container.

## Actual full-grid execution

`literal_reference.py` implements own8192-byte shared input storage plus16 barrier bytes, separate Q/K/V outputs, two-z partial state and source counter control. It retains original loads, copies, barriers, polling and all arithmetic. z0's original stores initialize temp; z1 waits for counter>=0, loads/adds partials, normalizes and stores Q/K/V. The caller supplies a fresh counter−1 and initially unproduced temp/output; no holes are zero-filled to force progress.

Input is the unchanged full Main FFN output,131072bytes, SHA a9493e2a256c8dd3f465d43edf99fc18c470111115fa3d5a84f2a07e6c6b70e6. `run_full.py` executes all32 CTAs (16 groups×2z) at N128:

- All four warps reach originalret in every CTA.
- **98304 real FP8 MMA calls**, independently checked;3072 perCTA.
- **65536 RSQRT calls** use the already pinned native positive-finite-half-input measurement LUT; out-of-domain inputs refuse.
- All786432 temp bytes are produced by originalz0 stores before use.
- All131072 bytes of each Q/K/V output are produced exactly once.
- CPU execution took136seconds; no GPU was launched.

Outputs:

| output | SHA256 |
|---|---|
|Q|cc1acb0e930fc316680702a71800e235c9885edcdab7a08e9ab414d0658fd504|
|K|46581f1fbded6f184e77e00ea0332c21b455895514a04b6d2e7d26c50d6f1c66|
|V|0c4af456939ba79562b0047928fd73bc274ea4a2c8ff03e7af1fb91b1f5f2f8e|

## Numeric/state limits and tests

The only sqrt instruction takes literal32 and is immediately converted to half. It currently uses an explicit **RN-f32 sqrt32 reference**, not an invented identity callback and not a claim that its F32 bits match native sqrt.approx. The measured RSQRT domain does not prove unrelated approximate instructions, native MMA accumulation, PTX→SASS contraction or all other intermediate bits. Fresh counter initialization and relaxed-load/native visibility remain conditional, as before.

Six Main tests PASS: ownABI/static launch/vtable; source prefix placement; measured-RSQRT input-domain refusal and sqrt-reference boundary; all32 saved execution identities/support; actual original z1-before-z0 wait rejection; and stale-ready counter with missing-temp rejection. See `TESTS.log`, `FULL_GRID.json`, `IDENTITY.json`, `HOST_XREFS.json` and `VTABLE.json`.

This is complete bounded QKV **original-instruction CPU reference progress** after the FFN. It is not a finished NN-facing QKV tensor lift, attention/projection, the entire ViT block, real-game binding, native GPU parity or a complete equivalent network. The4h226/8192 gap remains open. NoGPU/PE execution, Wine, installed/config/network changes.
