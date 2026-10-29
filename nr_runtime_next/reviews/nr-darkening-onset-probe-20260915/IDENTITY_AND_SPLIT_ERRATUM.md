# Source-identity and pre-output split erratum

## Pre-output split revision

Two dataset freezes are intentionally retained. The first global-hash split (`*_FIRST_HASH_SPLIT_UNBALANCED.json`) was written at 2026-09-15 22:18:53 +08 and was found, before any NR execution, to have poor category balance. It was replaced by the deterministic category-stratified group split at 22:20:14. The first recorded NR failure did not occur until 22:29:12; the first successful receipt for that case was later. Thus the 65 split changes were pre-output design correction, not target-driven resplitting. The original candidate remains preserved rather than silently removed.

## Post-result identity audit correction

A later manual title/image audit found that `commons-011` (train) and `commons-012` (test) are two views from the same artwork/subject series, **“The Gobblin Child” (HK7155-10002-1/-2)**. File hashes and dHash did not detect semantic identity. Their separate group labels violate the intended identity rule.

The frozen dataset and first predictions are not rewritten. Instead, all corrected confirmatory probe fits and test scores exclude **both** cases. This rule is metadata/image-identity based, not target based. Pre-correction results remain archived under `results/PRE_IDENTITY_AUDIT/`. Corrected predictions are newly frozen before their corrected test scoring.

Consequences:

- Corrected analysis: 48 train cases / 38 groups, 17 validation / 14 groups, 18 test / 14 groups.
- `commons-012` is removed from causal acceptance. It is replaced by the next lexicographic eligible real test identity, `commons-016`, under a frozen replacement plan.
- The conclusion must be phrased as “block22 is the first sampled checkpoint satisfying the registered gate; block14 did not qualify.” Failure at block14 is not evidence of absence, and no exact appearance interval is claimed.
