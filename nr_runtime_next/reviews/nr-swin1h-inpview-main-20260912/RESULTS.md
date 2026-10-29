# Block1 base INPVIEW — bounded transparent CPU component accepted

## Identity / first prediction

Current canonical `cc_tinlayout_fused_swin_1h_32_1_inpview_fp8`: **5505 instructions, 96-byte ABI, no shared/barrier/backedge**. Source SHA `e36a534b79b5361f853f1e8baf4cd63f80d85bd73259e46de36a31321568ce13`. Own checkpoint block1 range21696..42368,20672B, SHA `0270fb8f406d3d0a916953ddaf6ec5d29328fe95b9d6cb408ca0c25c91108e3a`.

Input is actual verified pre0primaryA, SHA `56ee903cb43a4dd89ae177ea7b9a783ff30f7e06bfb95080e0c4af56eb2c2c4a`. First complete NN ran without I/O; six numerical files froze before any original1 execution and remain unchanged.

**ALL64 original CTAs /16384 unique FP8 MMA /131072 C32 output bytes match** first prediction:

`eca8190cd280da7b70cfe1553e77913ce733aa237fae530174ca378495e04af4`

Actual stores—not prediction-filled buffers—produced ORIGINAL_OUTPUT.bin. Default is64x64,origin0,source override72/76zero.

## Structural and operation-level proofs

- Main re-extracted current module bytes, independently checked4721 ordinary↔INPVIEW common instructions,5087-symbol bijection,4724 projected CFG edges and all256MMA operands. Exceptions are source ingress and rescheduled geometry, not deleted computation.
- ALL64 every MMA A/B/C/D, actual slab/B/bias origin, every K32 carry, unquantized FFN final seed; actual20612 unique slab bytes per CTA,60 gaps not read.
- ALL64 source rawFP8→EXP, separate decoded-half→early residual, full cubic clamps/coefficients/ordered half operations/FP8, four contract carries.
- ALL64 normalization tree/RSQRT/scale/transpose/QKV lineage: **65536 RSQRT calls**. ALL64 attention map/ordered denominator/RCP/probability/PV/final seed/FP8/store lineage: **8192 RCP calls**,131072 final store bytes.
- Core observers use a checked alpha-coordinate adapter ONLY on trace callbacks. All actual5505 original instructions, operands, active masks and memory accesses still execute unchanged. This adapter is never used by the NN. Negative/unmapped observer coordinates retain their actual instruction events; they are not deleted from execution.
- Independent ingress worker has equation-only raw64x32 physical-A candidate and separately written prefix-only interpreter. Main reran all **593 cases /1214464 bytes**,769/769 prefix PCs,48/48 branch outcomes, exact load addresses/guards, singleton/fallback/wrap and missing-byte cases. Its full integer address domain does not enlarge the NN/native pointer domain.
- Main then cross-checked its independent integer results against the **actual full original on ALL64**: **1531904 prefix scalar results**,32768 actual32-bit loads,131072 source bytes, all active taken branches and full prefix register handoffs. Independent physical-A bytes mapped to every frozen NN ingress tensor exactly. Actual190 positive-zero and179 negative-zero input codes stay distinct; loaded zero is not predicate-zero.

`ALL_CORE_PROOFS.json` pins256 core reports; `ALL_INGRESS_PROOFS.json` covers64 additional ingress reports. Repeated observer replays do not multiply the unique16384MMA workload.

## Heldout, interface, composition

- Independent heldout is an explicit61x63 crop of pre0's **other original CPU input**, fed to logical64x64 with positive72/76 overrides and origin(-4,-4). Frozen first, then **81 original CTAs /20736MMA** and full output matched SHA `91b8bfe8dc74a0eeaab6880d6e8c1468dc431d817009a1cd1b79ffc7fb71081d`.42912 predicate-zero ingress bytes exercised. This is a diagnostic geometry, not claimed live block1 launch, and not a second all-scalar campaign.
- `model.Inpview1hReference`: eight immutable **canonical-neuron** weights (input K permutations explicitly inverted), canonical logical tensor and exact packed-planarA interfaces, immutable named probes, explicit measured half-domain policies. Base only; tilesync rejects explicitly. Finite E4M3 domain and bounded geometry/resource sizes reject unsupported inputs.
- **12 tests PASS** including immutable weights/probes, canonical input mapping, heldout, singleton1x1 broadcast across four negative-origin8x8 CTAs, real missing-byte failure, ignored fields, wrong quantized-final seed/probability order, bad domains and tilesync rejection.
- `chain.Prefix0to1Reference`: first actually coupled0→1 forward with **all I/O prohibited after construction**, three immutable boundary probes, all0primary/0skip/1output boundaries match saved originals. Prior originals are reused, not claimed rerun. Explicit pre0 procedural sampler/nonnative ingress policy remains.

## Current host and separate tilesync source

Main rehashed installed DLL and independently disassembled/rechecked **313 witness occurrences,311 distinct instruction sites,32 windows/30436B**. Factory1 origin0; common1H ABI base=RBP-0x90, size96; source72/76 are nonDSzero, host positive overrides88/92 are ignored by this source. INPVIEW alternate S+38 is selected only under recorded handle/supplementary-output gates; these are conditional static facts, not live selection.

Tilesync source has5531 instructions SHA `0d852d65e676316dfa9c26264820b691299d59d7cc9daf9d8b88870f23e1491c`. Main independently verified all5505 common instructions,5810-symbol bijection,5523 common-frontier CFG edges and all26 additions;2724 further signed/overflow address cases passed.

It adds CTA barrier0, then unique thread(0,0,0) publishes a **GPU-scope release store of zero** through ABI56. No wait, polling load, atom/RMW or ABI40/48 use. In positive nonoverflow geometry the signal index is `cy*ceil((W-min(X,0))/8)+cx`; full signed narrowing/truncation is preserved separately. It is NOT an arrival-counter decrement, not grid-wide synchronization, and not CPU/system visibility. The shared arithmetic result does not erase the barrier/signal or close initialization, consumer acquire, generation reuse, aliases or native visibility.

## Scope limits

Accepted evidence is this bounded transparent **base CPU reference**, not native/fullNR/standalone release. Real producer textures/history/temporal recurrence, native FP8/F16/FTZ details beyond measured primitive domains, actual allocations/aliases/lifetimes/counter epochs and dispatch remain open. No DLL/PE/Wine/GPU/network execution, deployment or safety-gate change occurred. Later encoder2/3 first grids/proofs are in a separate in-progress directory;4 and other upstream producers remain unfinished.

All failures/annotation caveats are retained in ERRATA.md. Sealing inventories freeze these artifacts; no silent re-freeze of numerical code is permitted.
