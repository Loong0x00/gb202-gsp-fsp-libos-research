# Main static review / worker erratum

Keep REPORT.md unchanged. Useful accepted leads: own88 aggregate; P24 actually read by the upsample prefix; additional FP8 MMA with slab+360960; prefix packs into shared before the core; late slab shifts688704→820256 and623680→755232 are131552 bytes. None alone proves tensor coordinates or live bindings.

Corrections from explicit regular-file source checks:

- The original upsample entry has15499 splitlines (15498 newline characters), not33000+. Worker citations33339/33375/33411 etc exceed file length. The first prefix shared store is original line3345; `mov.b64 %rd386,%rd11` is3378. Original numbered views and worker report are preserved.
- Activation coefficient raw bits are -1117454336 =0xbd650000 (NOT worker0xbd660000),1055195136=0x3ee50000,1063583744=0x3f650000. Source standard lines1665–1723 does min(x,+4), then max(...,-4), abs, FMA(0xbd650000,abs,0x3ee50000), then FMA(clamped,t,0x3f650000), then multiply original x. Worker swapped the two positive FMA addends and also reversed the written clamp order. Do not implement its compact activation formula.
- Whole named upsample entry contains zero `mbarrier` strings/instructions and eight `bar.sync` occurrences. This is now a complete-entry static absence/count, not a scan of only the inspected regions; it still says nothing about native visibility outside this entry.
- Current retyped factory graph has block48 input exports[(47,0),(22,1)]. Do not call block22 export1 “downstream” or “ordinary” until its HOST output-to-PTX binding is followed; PTX destination ordering alone is not host vector ordering.

Main is resolving the exact host launch and constructing an independent original-instruction CPU executor. No worker numerical/native execution or tensor equivalence is accepted; no original kernel/weights were changed.

Further Main source qualification: sign-bias plus arithmetic shifts at original lines26–39 implement truncation toward zero for division by4/2, not unconditional floor for negative coordinates. The executed plain-upsample host branch uses zero X/Y; Main CPU tests admit only positive bounded dimensions. The first weight loads also include -512 relative to360960, so the full projection matrix begins at360448, not360960. The prefix has no activation between this projection and the skip add. Full Main execution/operand checks and errata are in ../nr-swin8h-up-main-20260912/RESULTS_AND_ERRATA.md.
