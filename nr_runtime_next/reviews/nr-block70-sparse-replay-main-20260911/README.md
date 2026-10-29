# Sparse CPU block70 prefix replay

`run_sparse_prefix` connects the exact predicated/coalesced input readset to the existing PTX prefix interpreter without allocating or fabricating the holes between observed spans. Original interpreter `Memory` already supports disjoint byte regions; no new memory model was invented.

For the captured 184-byte first postblock arguments and CTA (1,1), ten main/skip spans contain 2,560 bytes. The separately supplied slab must match the pinned original 21,808-byte block70 payload. Stages merge, qkv and prehead retain the existing exact-dot/RN-half reference policy and require an explicit rsqrt policy for prehead. Missing, extra, reordered or shortened regions fail before execution; an unmapped load fails, never returns zeros. No native image sampler/output/temporal behavior is added.

Run `python3 -B test_sparse_reference.py`: 7 tests pass. Synthetic nonzero finite FP8 data produces identical registers to contiguous replay through prehead. The dense comparator's unused holes deliberately contain NaN poison bytes; these are fixture bytes, not observations. Sparse replay contains no such holes. This test does not establish native numeric equivalence.

**No GPU activation payload has been captured.** This adapter consumes caller-provided bytes and does not certify their provenance. Real capture remains blocked as documented in `../nr-block70-sparse-capture-20260911/REVIEW.md`. No GPU API, Wine, installed DLL, original PTX or prior reference source was changed.
