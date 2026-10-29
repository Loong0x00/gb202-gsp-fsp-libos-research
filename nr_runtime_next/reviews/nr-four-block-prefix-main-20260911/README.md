# Bounded synthetic image prefix through block3

Extends the preserved three-block Main reference using actual155526 argument metadata and real block3 weights. No old source/output was replaced.

Sixteen preblock CTAs produce sparse downstream data. Four block1 CTAs consume it. Two block2 CTAs, (1,0) and(1,1), produce disjoint patches of1024 and2048 bytes; the first is clipped only by original input/output predicates. Block3 CTA(1,0), actual origin(-4,0), reads1024 bytes from each of those producers and emits2048 bytes.

Captured ordinary output/input pointers and predecessor flags agree. The block3 required polling addresses match the two block2 publication intents. These are **intents and CPU byte dependencies**, not acquired native visibility. Deleting one required block3 byte raises an error. No sparse holes are zero-filled.

Run `python3 -B consume_blocks.py --synthetic`; `RESULT.json`, `BLOCK3_TILE.bin` and `RUN.log` record results. `produce_preblock.py --synthetic` can regenerate the input patch file separately, avoiding sibling import-name collisions. Source/input pins are checked before imports of the experimental references.

This is synthetic sampled image→internal feature computation for blocks0–3, not a full image-to-image model, real activation capture, native numeric parity or all branches. Literal reference rounding remains explicit; the separate source-proved finalpost Q/K correction is NOT blindly transplanted into these other kernels.
