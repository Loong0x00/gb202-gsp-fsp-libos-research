# Context-gated V5 strict final result

Low-noise exact feature extraction completed79/79 with zero failures at2026-09-17T11:47:58+08:00. V5’s formula and all gates were frozen before the10 generated final images and two Fluent identities were created. One generated source failed source-only frame QC, leaving9 generated plus2 Fluent final identities.

Result: `CONTEXT_GATE_V5_FAILED_STRICT_FINAL`,9/11 identities passed.

- `fluent-023`: worst danger improvement+0.04609EV, below the fixed+0.05EV gate.
- `ideo-v5-final-006`: close change0.03859EV, above the fixed0.03EV gate.

All other identities passed. Background-only RGB MAE was0.000227; all outside-person MAEs were below0.00056. This is a narrow but real failure and no threshold is relaxed.

V4 eliminated close drift but had danger false negatives; V5’s fixed0.5 gate floor restored danger strength but reintroduced close drift for one unseen identity. Per the preregistered plan, block70-only correction now stops. The next research scope is a representation-level repair at block48/38; V5 is not promoted or deployed.
