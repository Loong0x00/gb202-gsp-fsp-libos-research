# Reserved generated final QC result

The six prompts/seeds were frozen and images remained ungenerated until after V3 checkpoint `8999a8b7…` was frozen. The same pre-existing objective source QC was then applied.

- Accepted: `ideo-reserved-final-002/003/004/005`.
- Rejected without replacement: `000/001`, because YuNet face boxes began at y=-0.27 and y=-1.81 respectively, violating the preregistered fully-inside-frame criterion.

The extraction script’s cohort-level minimum had been set to5, so `RESERVED_ASSET_EXTRACTION.json` honestly reports `FAIL_GENERATED_ASSET_EXTRACTION` with4/6 accepted. That threshold is not rewritten. The four individually accepted generated identities may be scored as the surviving generated final cohort, alongside the independently frozen four Fluent identities. No NR or adapter output was inspected before this decision.
