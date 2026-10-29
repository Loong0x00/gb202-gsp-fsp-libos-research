# Failures and corrections (not hidden or waived)

## 1. Initial instruction parser omitted unsuffixed `bra`

First `python out/source_suffix_proof.py` failed `assert len(ops)==5982` with5931. Local search in the self-generated source snapshot counted51 plain predicated `bra` instructions. The initial regex admitted dotted opcodes and `ret`, but not unsuffixed `bra`. Added `bra` explicitly; corrected parser produces5982 ops and264 MMA. No original input was changed. Initial traceback is retained in tool transcript; this file records its exact count/cause.

## 2. Uniform pool child order was incorrect

`test_run_01.log` failed the exhaustive ordered-tree assertion at lane8, A-register%r4441 byte0, m2,k0. Actual source tree was `(F[0,5,0]+F[0,4,0])+(F[1,5,0]+F[1,4,0])`, not always TL,TR,BL,BR.

Further enumeration of all16 spatial rows established column reversal for local pooled x>=2 and row reversal for odd local pooled y. Candidate now implements `pool_pair_coordinates()` and the independent test closed form retains these ordered children. All512 source scalar trees pass exactly, without using commutativity to discard order. REPORT.md highlights this substantive source-derived correction over the prior prose's simplified pool expression.

## 3. High-writer test window omitted one address prerequisite

`test_run_02.log` passed source/pool/weights, then the high-writer checker failed with missing%r4345. Bottom high suffix began13463, omitting `add.s32 %r4345,%r3,1` at13462. Moved the test start to13461 (blank line before the prerequisite), leaving the original source and candidate mapping unchanged. All eight high/low coordinate cases then pass.

## Passing runs and strengthened checks

`test_run_03.log`: all five sections PASS after these corrections.
`test_run_04.log`: all five PASS after adding the explicit bounded raw-vs-clipped FFN witness, ordered numeric half-rounding witness, high-prequantization counterexample, and conservative size-product admission bounds.

No unhandled test failure remains. Numeric/native/host/allocation obligations listed in REPORT.md are intentionally unverified, not silently labeled PASS. No model prediction or native run was performed to resolve them.
