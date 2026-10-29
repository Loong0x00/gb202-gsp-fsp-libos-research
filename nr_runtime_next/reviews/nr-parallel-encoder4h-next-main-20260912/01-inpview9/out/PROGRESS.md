# Progress / bounded stop

- Complete: exact supplied4H source/ABI counts; own slab typed maps and unread gaps; input/output byte contracts; source/operand/CFG/core-alpha maps; raw/decode/reencode artifacts; loop/shared/thread/residual recovery; symbolic/address checker.
- Deliberate stop: no DLL inspection and no additional host provenance acquisition. Actual4H HH/override setup and runtime producer compatibility remain open.
- Numeric status: **ordinary4H native/CPU226-of8192 mismatch OPEN**. Main owns first numeric freeze. Static field/layout/CFG matching is not acceptance.
- Reproducible generation: `python -B out/recover.py`; `python -B out/analyze.py`; `python -B out/address_check.py`; `python -B out/fields.py`; `python -B out/checker.py`.
- Artifacts: REPORT.md; FIELD_MAP.md/json + FIELD_ELEMENTS.json + TYPED_SLAB.json; INGRESS_CONTRACT.md; OUTPUT_CONTRACT.md; ABI_MAP.json; exact PTX copies; both SOURCE/OPERAND/CFG maps; CORE_ALPHA_VERIFIED.json; MATH_MAP.json; SHARED_MAP.json; CONSTANT_MAP.json; SLAB_READ_MAP.json; ADDRESS_TRACE.json; raw/reencoded slab; checker and verification logs; READ_LEDGER.json; FAILURES.json.
- Failed parses and failed-first verification retained, not reclassified as passes. Read-budget accounting caveat retained in ledger. Final verification result is authoritative in VERIFY_RESULTS.json.

Final regenerated checker: **735/735 checks passed**. These are static/source/layout/codec checks only; native gap remains OPEN.
