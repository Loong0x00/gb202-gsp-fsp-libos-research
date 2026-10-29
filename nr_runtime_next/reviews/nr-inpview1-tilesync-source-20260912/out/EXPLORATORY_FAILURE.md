# Preserved exploratory parsing failure — NOT proof

The second cache-only exploratory CPU script used a provisional line-oriented parser. It emitted `parsed.json`, which is deliberately retained unchanged and is **INVALID**. It reported base5531 / tilesync5557, not actual executable instruction counts.

Cause: it treated some `{ .reg ...;` local declarations as executable statements, and treated multi-instruction inline `mov.b128; st.global...;` lines as a single operation. The net count error is +26 in each source. Its provisional shape diff still suggested +26 between sources, but neither its PCs nor its instruction counts are accepted evidence.

The strict semicolon-aware parser in `static_checker.py` excludes all56 declarations and splits inline instructions. It independently counts base5505 / tilesync5531. Authoritative parsing is `PARSED_PTX.json`, with exact original source lines and lexical scopes.

Two subsequent strict-checker failures are separately preserved in `CHECKER_FAILURES.log`:

1. The first parser accepted `.reg ` but rejected the actual local `.reg.b16 hl, hu;` at base source line8329. It now recognizes both declaration spellings without treating them as executable instructions. This is lexical source recovery, not an assembler/native syntax-validation claim.
2. The first lexical-scope-gap check mapped base frontier5504 using the instruction-ret mapping to tilesync5530. The final common local scope instead closes at tilesync5516, **before the new barrier**. The correction explicitly distinguishes between-instruction frontier gaps from corresponding return instructions; it does not erase the barrier or signal store.

All exploratory and retry reads were generated-cache reads; none caused primary source rereads beyond the exact22 units retained in `INPUT_READS.json`.
