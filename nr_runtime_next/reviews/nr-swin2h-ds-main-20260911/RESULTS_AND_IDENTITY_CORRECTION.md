# Main acceptance: full bounded2h DS and block-index correction

Main reran14 CPU tests and package checksums; all pass. Full plain2h DS executes both warps,864 MMAs, eight64-thread barriers, source-order half pooling, learned projection and both outputs. Independent checks cover shared epochs/byte ownership, reverse warp scheduling, loops, typed weights and64→128 downstream layout. Four synthetic DS CTAs also feed the original4h ingress prefix without repacking; no4h learned arithmetic is claimed yet.

**Correct historical identity is block8=2hDS, block9=4h inpview.** Main's task referred to a presumed block9 DS and required original verification; the original factory/resource/checkpoint evidence refutes that presumption. The new reference uses block8's69936-byte slab (SHA687d906b…), rejects block9's197184-byte slab as DS, and preserves both separately. No silent weight substitution or wrong native probe occurred.

Own DS88 ABI is input0/output8/slab16; downstream72, dimensions32/36, origin40/44, padding80/84. Downstream physical bytes are [8,H/2,W/2,16], not ordinary packed128-channel tiles. Oversized padding and unproved execution variants fail explicitly.

Full4h block9 arithmetic is now an independent CPU task. Native DS selection, wait/dependencies, actual arguments/activation bytes, full model/history and numerical equivalence remain open. All work here is tests/documentation only; no GPU or installed-file changes.
