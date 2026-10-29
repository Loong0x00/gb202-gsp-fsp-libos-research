# Main conditional split16 layer0 review

Main reran nine tests plus frozen artifact checksums, then reran nine tests under the confined test wrapper with original proof bytes and timestamps unchanged. Legacy CLI proof-file writes are disclosed in `../nr-reference-test-write-audit-main-20260911/ERRATUM.md`.

The source/host-derived launch is four warps per CTA, grid.z2, **not one sixteen-warp fused CTA**. Four separate graph layers preserve original input skip into layer1 and layer1 output skip into layer3, alongside distinct completion handles. This is static host routing evidence, not a live launch capture.

Accepted arithmetic: conditional FP8 non-tilesync layer0, both z slices,8192 independently checked MMAs and786432 checked scalar half operations, original async-copy/commit/wait/mbarrier/poll operations, full524288-byte real layer0 slab and32768-byte output. CPU phase tokens are explicitly symbolic, not invented native state bits; bounded modeled scheduling is not all native interleavings.

**Route blocker remains important:** under the captured historical factory(0) spelling, host initialization selects F16, whose second stage reads beyond that serialized slab. This does NOT prove the running original model uses the conflicting route or has an OOB bug. Runtime graph selection/rewrite/conversion is being traced separately. The API rejects that historical spelling and requires an explicit conditional FP8 acknowledgement.

Wholeblock23 is NOT restored: remaining projections and attention are separate, no fabricated activation or adjacent-slab extension. Main separately composed DS22 bytes with this conditional entry, recorded in `../nr-ds22-split16-conditional-main-20260911/`; this adds no native/default-route or complete-block acceptance.
