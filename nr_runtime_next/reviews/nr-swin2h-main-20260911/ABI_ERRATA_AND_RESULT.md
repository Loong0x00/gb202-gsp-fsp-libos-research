# Main 2h acceptance and ABI erratum

Main reran12 tests and worker artifact checksums from `nr-swin2h-reference-20260911`; all pass.

**Correction to the preceding DS report and Main's follow-on task description:** the original 88-byte 2h inpview ABI is **input+0, output+8, slab+16**, not slab+8/output+16. Original PTX parameter loads, coefficient-load chains and output stores prove those roles. The earlier DS ingress-only boundary stopped before learned loads/stores and could not establish them. Its packed DS→2h input-layout result remains scoped to input+0; its output/slab labels must not be used for execution.

The new reference explicitly requires `abi='original-verified-output8-slab16'`; wrong/omitted acknowledgement rejects. No original PTX swap or hidden caller repair is used. No native2h probe was run with the wrong labels.

Completed bounded CPU work: actual block5 slab, both32-lane warps,832 dynamically executed FP8 MMAs,4096 shared bytes, six64-thread barriers, original two-pass learned loop and both terminal returns. Tests include reverse warp scheduling, byte ownership, missing-data/race/deadlock rejection, and DS-produced synthetic input. Output is4096 packed bytes for a full interior tile.

Native selection, numerical parity, concurrent GPU visibility and complete image-to-image model remain unproved. Original source and sibling reports were preserved; this separate erratum prevents silently rewriting historical evidence.
