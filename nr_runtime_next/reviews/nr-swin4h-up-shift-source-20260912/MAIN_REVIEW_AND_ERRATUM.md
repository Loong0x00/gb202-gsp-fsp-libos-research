# Main shifted-prefix review and source-report errata

Main has now verified the separate shifted NN and the exact original6-CTA program. See ../nr-swin4h-up-shift-main-20260912/RESULTS.md. OriginalPTX, zero-baseline first model and shifted first prediction are unchanged.

Accepted from actual operands: P0 raw literal zero vs real E4M3 bytes; P24 original F32zero→half→FP8 initialization, then its normal FP8 decode; all256→128 K32 accumulators; per-high-coordinate late skip; original96 three-select chains perCTA; and actual shared checkpoint. Every shifted CTA, not just representative edges, received this provenance proof.

Corrections to worker notation/claims:

1. The source signed-bias/right-shift division is **truncation toward zero**, not ceil. Current admitted origins are multiples4, so the quotient values used for this6-CTA case are the same; that does not make ceil a valid general equation. No arithmetic or geometry was changed to fit.
2. P24 is the HIGH-resolution16x16x128 skip in4x4 canonical-C tiles. A source granule is4x4 high pixels; describing it via a2x2 low-coordinate footprint must not be read as a low-resolution skip tensor or nearest-replicated skip. Main independently checks every actual high-pixel skip operand and byte address.
3. Late high-coordinate selects are independent original instructions and remain implemented/proved. However, the worker's assertion that they necessarily change the numerical result for the stated edge case is not established. All six baseline shifted CTAs had **zero changed half bits** when comparing pre-mask late-add values to selected values, although the X predicates actively select zero. This is only an observed redundancy on that fixture, not permission to remove the instructions or an all-domain theorem. The negative test rejects omitting the real predicate/select path, rather than claiming a fabricated pixel difference.

Source-only workers did not run tests. Main's CPU/NN evidence supplies acceptance in the explicitly bounded16x16 static configuration; native/live/full-NR/standalone gaps remain.
