Source fact: ordinary is the 4,845-op `cc_tinlayout_fused_swin_2h_64_2_fp8` source; it loads P0/P8/P16, uses static `.shared ...[4096]`, and its MMA spelling is `mma.sync.aligned.m16n8k32.row.col.f16.e4m3.e4m3.f16` (not an inferred f32 form).

Reviewed the eight authorized inputs only. Scope remains ordinary blocks 63/64 source analysis; block 65 OUTVIEW (5,301 ops) is excluded. Main block 62 provenance remains the supplied 16-CTA/13,824-MMA source result, not ordinary acceptance.
