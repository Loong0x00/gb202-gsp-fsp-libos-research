# Retained failure records

`callback-contract-all_live.json` is retained verbatim from the first oracle run.
It exposed three source-reading errors in the five-tap B path: the half-shifted
base/center bounds, the `-1` point-0 offset, and the cross-first TEX order.

It is **resolved, not deleted**: after those PTX instruction boundaries were
restored, `../ORACLE_COMPARISON.json` records a fresh all-live pass with exact
callback-coordinate multiset equality and pixelwise equality against the same
original CPU VM callback fixture.  This record is not evidence of native GPU
sampler parity.
