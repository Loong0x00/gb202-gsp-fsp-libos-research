# Main resumed split16 route and partial-block review

## Static route conflict resolved, without inventing larger weights

Main read the completed route report and reran9 tests. The packaged manager calls the catalog; catalog calls factory(0), copies its pre-rewrite graph, then rewrites all152 layer names with `_fp8` before returning to the manager. Layer23/0's rewritten name therefore selects the FP8 entry whose exact524288-byte slab fits. The old factory(0) dump is an intermediate state, not the final catalog selector.

This closes the **tracked static catalog-path** F16/slab mismatch. It does not prove a live block23 descriptor/flag/handle or a base-versus-tilesync submission. The inpview selector can attempt an uninitialized slot and fall back to base; it is not always tilesync. Captured preblock+192=1 is not treated as that selector/global mode. Historical reports and the pre-resume archive remain intact.

## Projection layers1/3 accepted in bounded CPU scope

Main reran4 own tests. Each projection consumes its own real263168-byte slab: first262144E4M3 matrix bytes plus1024half coefficient bytes. For8x8, two channel CTAs cover all32768 output bytes and the entire slab; each layer has4096 checked MMAs and independently checked residual seed/half/quantization/output computations. Layer1 uses4warps perCTA; layer3 uses8. These are separate original72-byte ABIs and source-derived grids, not borrowed layer0 metadata.

Current tests certify the supplied finite8x8 scope, not all native interleavings, actual game bindings or numerical parity. Frozen worker docs retain their earlier conditional route language; the separate static route proof above must not be confused with live selection.

## Connected real CPU data, preserving the residual

`connect_layer1.py` uses the **previously computed** DS22 V0 bytes and original conditional layer0 F bytes (not fresh native activations):

- V0 SHA `808983e0442179682cedd5a1610f94970ffc2f342b19d7f22749cc8c4085e45a`.
- F SHA `1382b2fb50200a88ef1d09f5f6a0db2286f3a427d3cf6bc448e99b4a23da0359`.
- Complete layer1 P SHA **`247fa40fc373b2591a1236dcdeae85a14d228bba0e92a4ee3409bc68ea163a44`**,32768bytes.

Both CTAs execute full original FP8 layer1 with independent proofs; no repack/holes, both source and skip remain unchanged, each missing-source/skip case rejects. The API receives **src=F and skip=V0**, not a serial chain that discards the residual. No A or final Y is fabricated, and layer3 is not claimed connected before real layer2 CPU output exists.

## Attention boundary retained

Main reran the confined static attention audit:3360 instructions/source/slab/56ABI/XY/ownCTA anchors pass. The old partial VM stops at signed32-to64 conversion before bulk async execution; neither QKV grid.z nor full attention output is accepted from that partial. New `nr-split16h-attention-execution-20260912` continues with separately validated bulk/mbarrier semantics and host-grid lineage. Completion remains unaccepted until delivered/reviewed.

All this review is CPU/static; no installed changes. Separately, original4h native experiment now has226/8192 byte differences under literal-reference numerics (`nr-original-swin4h-main-20260912`), so the CPU compositions here are not advertised as native bit-exact whole-model execution.

## Attention execution delivery: mock-versus-numerical distinction

The new execution worker reachedret under structural callbacks: MMA returnedC, RCP/RSQRT returnedtheirinput. That delivery alone is **control/storage coverage, not numerical attention restoration**. Main inspected the test source and did not connect its output to layer3.

Main `qkv_real_policies.py` then independently ran non-placeholder RN-half FP8 dot+C (checked with a separate forwardISA oracle) and explicit referenceRN-FP32 RCP/RSQRT policies on previously computed P. Four conditionalz slices retire with13312 checked MMAs,16384 RSQRTcalls and2048RCPcalls;917568 real slab bytes and32768 output bytes covered. OutputSHA6de6b9a0431740353cdc39eec9f36fdcf02328a376ea8f76405ff8fb78193fc9. Saved file deliberately says **UNVALIDATED-layout**: independent logicalP->QKV->layer3 mappings and exacthostgrid.z are still pending; no fullblock/native/approx-oracle claim. New attention-layout worker closes those independent proofs without altering prior mocks or Main data.
