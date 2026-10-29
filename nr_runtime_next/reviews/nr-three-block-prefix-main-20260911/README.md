# First three neural blocks connected from a synthetic sampler

Main reran 14 full-preblock tests and worker checksums, plus eight standard-variant certificate tests/checksums in `nr-swin-chain-main-20260911`. This integration then executes:

**synthetic sampled image → 16 complete preblock CTAs → 4 block1 CTAs → 1 block2 CTA**

All stages use actual first-frame aggregate metadata from native run155526 and their original pinned block0/1/2 weight payloads. Actual dimensions, pointer relationships and block2 (-4,-4) shift are preserved. No geometry is rescaled to16×16 and no intermediate tensor reshape or pointer rebasing is introduced.

- Preblock produces 32768 sparse skip bytes and 8192 sparse downstream bytes.
- Each block1 CTA consumes exactly512 bytes from each of four preblock CTAs, and emits2048 bytes. All missing regions remain absent.
- Block2 CTA(1,1) consumes512 bytes from each of four block1 CTAs and emits a complete2048-byte feature tile.
- Supplying only the required2048 block2 input bytes reproduces its output; deleting one byte fails.
- Output tile SHA256: `cea3e20c644a8402235da2d14e3ed401d230dbe3ef02f25df8eed36c722f9985`.

Reproduce, CPU only:

```sh
python3 -B produce_preblock.py --synthetic
python3 -B consume_blocks.py --synthetic
```

Separate Python processes avoid collisions between legacy sibling module namespaces. `PREBLOCK_PATCHES.json` contains only computed sparse patches, not allocation-sized zero backing. `RESULT.json` retains producer ownership, actual store records and the final hash.

Block1 tilesync and block2 chained **common computation** are reused only under checked exact-source equivalence certificates (5504 and4901 shared non-return instructions). Their publication intents and block2 required polling addresses remain explicit. The expected four flag addresses match the four producer publication intents, but **no native polling observation, release, barrier or visibility is executed or inferred**.

The sampler and all resulting activations are explicitly synthetic. Policies remain libm ingress approximations, exact-dot/RN-half MMAs and RN-f32 learned-normalization approximations. This is a bounded **image-to-internal-feature prefix**, NOT native numeric parity, physical sampler fidelity, full-frame forwarding, temporal recurrence, or an image-to-image model. The copied argument pointers are opaque CPU-model keys, never GPU/host dereferences.

No GPU/Wine or installed-file operation occurred in this integration. No sibling reference, original PTX or frozen ABI was modified.
