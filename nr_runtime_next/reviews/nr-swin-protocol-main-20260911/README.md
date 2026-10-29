# Main acceptance: completion protocol, not native visibility

Main reran all **18 CPU/static tests** and artifact checksums from `../nr-swin-sync-protocol-20260911/`; logs retained here.

Accepted static corrections:
- Consumer polls +40 with `ld.relaxed.gpu...s32`, **not acquire**. Negative values sleep/retry; all nonnegative values pass.
- +48/+52 carry predecessor origin. A shifted consumer can need four upstream tile flags, not just its own flattened index.
- Actual host descriptor/table routing connects block1's outgoing completion slot to block2's incoming suffix. This is separate from ordinary feature-data routing.
- Conditional `cc_cb_clear` writes **-1** before the block loop when the recovered full-range/start-zero conditions hold. Creation is not submission; this is not proof of a reset on either captured frame.
- The producer's 1344-word write footprint is **5376 bytes**; its conditional host-reserved slot is **5632 bytes**, including 256 padding bytes. Do not conflate the publication footprint with reserved storage.

`verify_composition.py` cross-checks producer publication addresses, miniature host routing and both original wait/chained symbolic consumers. Its miniature table and shifted consumer arguments are **explicit fixtures**, not new native captures. Unknown observations remain unknown, negative polling emits sleep intents, and negative→zero supplies the expected four dependencies. Every case retains `memory_visibility_proven=false` and `native_completed=false`. `COMPOSITION.json` records results.

A stale zero passes the same sign predicate as a fresh zero. The actual reset/reuse/order path therefore matters; this observation does not prove the original runtime has a stale-flag bug. A CTA barrier or cache modifier is not automatically a GPU-scope acquire. Native machine-code ordering and backend API dependencies require separate evidence.

Two CPU/static tasks continue:
1. `nr-swin-sync-native-order-20260911`: original SASS and backend ordering checks; no GPU experiment.
2. `nr-swin1h-chain-reference-20260911`: standard/shifted block2 arithmetic and a strict synthetic block1→block2 packed-data composition.

Actual consumer/reset launches, flag contents, lifetime and native visibility remain unobserved. No GPU/Wine, installed file, original PTX or prior worker source was modified by this Main review.
