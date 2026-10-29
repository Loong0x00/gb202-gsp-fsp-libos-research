# Source/operand evidence index

- `DS_SOURCE_INDEX.json`: all5823 exact normalized statements with original line spans and labels, independently raw-source checked.
- `ORDINARY_SOURCE_INDEX.json`:4845 corrected operand-complete canonical statements/labels; see ordinary second-parser caveat.
- `ds.source.snapshot.ptx`: own exact DS source snapshot; original input untouched.
- `SOURCE_CHECKS.json`, `EXACT_SOURCE_CHECKS.json`: hashes, counts, ABI, exact-source/parser, math-policy and dtype witnesses.
- `ALPHA_CFG_CHECKS.json`: every paired instruction, injective map, strict failures, accepted exception proofs, paired branches.
- `CFG.json`: full basic-block edges including out-of-line padding loops.
- `MMA_CHECKS.json`, `MMA_OPERANDS.json`: all static sites, dynamic visits and per-lane source operand groups; no numerical MMA.
- `MMA_FIELD_COORDINATES.json`:188416 B scalar and8192 bias C half mappings to own fields.
- `FIELD_MAP.json`, `FIELD_OPERAND_CHECKS.json`, `ADDRESS_OPERANDS.json`: every field scalar formula/table and every whole slab/shared/data access in the interior trace.
- `POOLING_OPERAND_TREES.json`:1024 ordered half-operation dependency trees on abstract neuron coordinates, not activations.
- `DOWN_A_MAP.json`:1024 byte-level native-K to pooled-neuron tags.
- `DOWN_OUTPUT_NEURON_MAP.json`, `SKIP_OUTPUT_NEURON_MAP.json`:2048/4096 exact output neuron-byte maps.
- `OUTPUT_CONTRACT.md/json`, `OUTPUT_ADDRESS_CHECKS.json`: both guards/layouts, extents as formulas, null caveat and padding hazards; six finite geometry cases.
- `SHARED_EPOCHS.json`: epochs, barrier cohorts and same-epoch ownership checks under conditional(32,2,1).
- `VERIFICATION.json`, `FAILURES.json`, `READ_LEDGER.json`: result, preserved rejected candidates and budget/gaps.

Source navigation (DS original lines): ABI12–18; ingress19–354; input gain/residual355–967; FF loop970–4174; FF quant/shared4176–4326; QKV4328–5184; normalization/K/V routing5186–8047; top QK/PV8048–9665; top residual/output9667–10418; bottom QK/PV10420–11999; bottom residual/output12000–12734; ordered unquantized pooling12738–13100; pool quant/shared/barriers13103–13141; learned projection loop13163–13450; padding13451–13970. Exact source index takes precedence over these coarse section boundaries.
