# Progress / parent handoff

**Completed:** current-byte conditional factory/host proof, not live/native acceptance.

- Blocks1/2/3/4 origins (X,Y): **(0,0), (−4,−4), (−4,0), (0,−4)**.
- Factory late auxiliary wiring recovered, separate from primary exported ports.
- Descriptor L+70/+74 → runtime C+78/+7c →1H96 ABI Y+36/X+32.
- Block4 **primaryO0→ABI64, dimensions72/76**; **secondaryO1→ABI8, dimensions24/28**.
- Current explicit [65,4]/[0,1] gather plus upsample L+a8=[0,1] closes **block4port1→block66 skip ABI80**.
- Primary cache and first-layer default gather close **block4port0→block5 I0**. Block5 is2H inpview: current host launch is **88 bytes**, not96.
- Signed rounding/division tested;1H ordinary/DS H/W are raw incoming values, not universally ceil8 or exactly twice DS primary dimensions.
- Supplied inpview PTX's optional dimension pair+72/+76 is not host override tail+88/+92. Do not erase this distinction.
- Base/FP8/tilesync/wait/chained registration and dispatch predicates distinguished. Vtable slot0 verified destructor.

## Verification state

`verify.py`: **104 checks PASS**. Two699,904-byte text scans and all **32/32** permitted windows consumed;30,436 window bytes. No further PE decoding is authorized under this run's remaining budget. All selected witnesses require the second scan's boundary match;22 clipped/misaligned decodes explicitly excluded.

Preserved failures:
1. Initial combined projection2,124 lines exceeded the2,000-line constraint and was tool-truncated; automatic spill file not read. Subsequent projections bounded. This run is **not** perfectly line-budget compliant.
2. Malformed slice CLI argument failed before reading a new slice; traceback retained in `slice_failure.txt`.

## Remaining independent work / non-acceptance gaps

No live allocation slots/extents, lifetime/reuse/non-alias proof, S+0 slab binding, graph/name mutation capture, actual kernel handles/G flag, complete auxiliary-table handle setup, full shape/H/W provenance or GPU completion/visibility evidence. Source basis stays independent. Supplied FP8 PTX is not evidence that unmutated non-FP8 factory names dispatch it. No full NN/native execution or numerical acceptance was performed.

## Deliverables

Primary: `HOST_PROOF.json`, `REPORT.md`, this file.

Reproducibility/audit: `recover.py`, `verify.py`, `assemble.py`, `decode_ledger.json`, `VERIFICATION.json`, `ASSEMBLY_CHECK.json`; bounded batch/rdata projections and failure logs retained in this same out directory. **Do not rerun verify.py against the current ledger:** the two-scan budget is exhausted; the script enforces that guard.
