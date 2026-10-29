# Progress — static task complete

## Scope / read ledger
- Read `PACKET.json` first, then only its exact absolute input targets: supplied host report, conditional DS4 contract, both PTXs, and own61760-byte slab.
- **18/32 primary units used**: packet1 + reports2 + inpview7×≤2000 lines + ordinary7×≤2000 lines + slab1 binary unit. **14 unused.**
- Subsequent analysis/checks read only own harvested/generated `out/` artifacts; `verify.py` adds0 primary reads.
- Own DLL was supplied but **never opened**, loaded or scanned. No outside discovery, recursive scan, network/native/GPU/Wine, deployment/gate changes, or delegation.
- Packet requests `openai-codex/gpt-6-astra`, `xhigh`; no model/API reconfiguration or nested agent was invoked.

## Completed
- [x] SHA256 match for both original PTX harvests and slab; source-indexed instruction counts5459/4845,304 MMA each.
- [x] Actual88-byte ABI, +80/+84 effective dimensions, unread ABI ranges; no1h72/76 assumptions.
- [x] Four-plane planar16 C64 ingress, canonical pi64 basis, singleton guards, output geometry and ordinary source comparison.
- [x] Nine typed canonical fields, exact byte-offset tables/raw payloads,61704 referenced bytes and56 unread bytes.
- [x] All MMA D/A/B/C tuples, stage/head/loop indices, predecessor operands and loop-carried residual C.
- [x] Q/K shuffles, V transpose, PV reduction-token layout, output neuron packing and residual decode forks.
- [x] Actual two-iteration math loop, two-warp role changes,4096-byte shared epochs, six barriers.
- [x] Common core4615 exact alpha instructions; one commuted add and18 explicit recomputations separately justified; CFG targets retained.
- [x] Source-only checker: **59 aggregate checks;557056 field operands;538197 layout/guard/bit/transport checks PASS**.
- [x] `REPORT.md`, typed `FIELD_MAP.json`, source/index/operand/layout proofs, `READ_LEDGER.json`, preserved failures.

## Preserved failures / qualifications
- Initial diagnostic output was2041 lines and tool-truncated, exceeding the requested2000-line display bound. Spill not read. Primary text chunks themselves were≤2000 lines; do not describe the entire run as perfectly bound-compliant.
- Preliminary lexical parsers rejected; corrected parser verifies the reported counts.
- Initial PV grouping assumption failed16384 checks; actual C chains corrected the K-interleaved schedule. Rejection preserved.
- Strict whole-suffix alpha equality is false; commutation/recomputation exceptions are explicit, not silently normalized away.
- Layout interpreter never computes floating activations or MMA products. Fresh opaque neuron labels are not identity MMAs. Finite exponent-bit carry lemma is not neural accuracy/native acceptance.

## Waiting for Main / intentionally not attempted
- Actual block3→4 source/activations and Main's first numerical freeze.
- Live producer/consumer dimensions, particularly DS4 HD/WD versus block5 effective EH/EW; producer padding and odd-size obligations.
- Live allocation extent, alias/lifetime, weight-slab binding, exact launch/FP8 dispatch, completion/visibility and numerical precision.

**No full-NN prediction or original numerical run performed.** Supplied DS4 output contract remains conditional static evidence, not a live allocation.
