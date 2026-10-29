# Main standard2h/4h/8h review — input-layout erratum

Main reran the delivered four tests and published hashes. Raw original-PTX CPU forwards pass:832/2816/10240 MMAs, realblock6/10/16 slabs, original barriers/ret. This does not establish native equality.

## Incorrect helper/claim rejected

Worker `reference.input_offset()` and README describe **inpview-style channel planes**, but these are plain standard entries. The original vector-read equations address **packed4x4 microtiles**, not that plane layout. The legacy tests only compared complete byte sets and checked loaded data against the same recorded offsets. Both layouts are bijections over the same range, so those tests could pass despite the wrong logical helper.

Concrete example in all three families: logical(row0,col0,channel2) is packed byte16; the legacy plane helper returns byte2. **Do not use that helper to format a standard-layer input.** The raw interpreter never calls it, so the recorded raw-fixture outputs are not silently recomputed or relabeled. Original worker artifacts remain unchanged.

## Own-family address proof and correction

`check_layouts.py` adds18 CPU cases: each family gets the canonical8x8 case, three additional finite address-tag digits, a12x16 negative-base/nonzeroCTA case, and a clipped8x8 negative-X case. Every original MMA is also compared to the independent forward-fragment reference oracle.

The expected per-PC/warp/lane16-byte read address is solved independently from source. 4h/8h distribute channel groups across warps and four spatial tiles across load sites. **2h instead distributes tile rows across its two warps; its four sites alternate channel halves and tile columns.** Both use the same physical packed-C format, but not the same warp assignment.

Main's initial hypothesis incorrectly generalized the4h/8h warp assignment to2h and was rejected by its own per-site check. That failed CPU-only test/source are retained as `LAYOUT_CHECK.initial-failure.log` and `check_layouts.initial-hypothesis.py.txt`; the corrected2h equations came from original r8=tid.y+tile_row and source load offsets0/512, not changing fixture data to make the test pass.

All18 corrected cases pass with input/slab provenance, independentMMA checks, exact reached input tuples and output byte support. `packed_layout.py` supplies the corrected pure address helper. OOB branches are distinguished from missing produced bytes; output holes are not filled or called full-image output.

## Remaining limits

These are bounded reference-policy raw forwards plus corrected standard ingress contracts, not complete standalone model or GPU equivalence. The helper's mathematical byte map is not an assertion of every internal activation's semantics, all output-C logical provenance, native shifts/selectedwait-chained variants, flag readiness, arbitrary dimensions or temporal behavior. Original4h226/8192 numerical gap remains unresolved. No installed games, original PTX, weights, GPU settings or network changed.
