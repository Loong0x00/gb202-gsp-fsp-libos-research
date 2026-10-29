Concrete fact: the ordinary entry’s only `ld.param` instructions read offsets 0, 8, 16, 24, and 32 of its 96-byte parameter object.

# ordinary1h67/68 source-only progress

- Scope is the ordinary `cc_tinlayout_fused_swin_1h_32_1_fp8` source (packet: 4,902 instructions, 96-byte ABI), with the two named F16 slabs 67 and 68, each 20,672 bytes. Block 69 OUTVIEW is excluded.
- Source tracing completed for ingress/OOB zeroing, slab accesses, FFN, raw QKV/norm/QK, movmatrix, private PV, residual seeds, stores, and synchronization absence.
- No numeric/native/full-NR acceptance was performed. No live producer, host, or launch origin is asserted; packet graph context only says 67 consumes 66 and 68 consumes 67.
- Upstream material was not used to transplant offsets or synchronization conclusions.

See `REPORT.md` for source evidence and bounded conclusions.
