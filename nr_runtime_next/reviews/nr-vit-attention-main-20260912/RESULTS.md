# Main complete bounded ViT attention CPU forward

Exact original `cc_vit_1d_attention_fp8`:64-byte ABI, not QKV80 or FFN72. Main static ctor/vtable proof gives BBAA0,+8forward72440,+38init73510. Init supplies CTA(32,4,1); host forward supplies grid(32,ceil(N/256),1),64-byte record. At N128 this is32x1x1. The four original pointer loads read Q/K/V/output and geometry is at56/60; the2-byte serialized layer payload is not read by this plain PTX entry. No live flag route/allocation claim follows from that unused field.

`literal_reference.py` consumes the three complete sealed QKV buffers, unchanged, and executes every original operation with real independently checked FP8 MMA and the pinned native normalizer-half-input reciprocal LUT. No exp/attention placeholder, identity RCP or padding of unknown inputs is used. Original source-defined invalid-query/padding branches remain.

`run_full.py`: all32 CTAs/four warps reach originalret, **16384 independently checked MMAs**, **8192 measured-domain RCP calls**, all131072 output bytes produced once. Output:
`7f93c03037ec60bfa9093cf9bdf38686754a868a275d953ea1fedb2f8349ab98`.

## Interpreter changes were required, not kernel changes

The inherited generic VM stopped on missing integer/F32 forms and later on a partial election rendezvous. Failures are retained. Main added explicit signed16 conversion/shift/multiply, unsigned-to-F32 RN, finite F32 multiply with source FTZ on input/output, and half subtraction through exact signed half addition; unsupported nonfinite/overflow remains refused.

More importantly,31 nonissuer lanes can reach the next loop iteration's full-mask election while the elected issuer is still finishing its previous iteration. Simply treating those31 as a complete warp is wrong. The new private VM **holds them at the collective PC until the lagging lane joins**. Full-warp election, shuffle, MMA and movmatrix forms are executed only after that rendezvous. Different static collective-PC rendezvous remains fail-closed. Per-thread mbarrier arrival/wait can progress independently, while original128-thread counts and transaction completion remain enforced. No election/poll/barrier was deleted to pass.

Seven Main tests PASS: genuine two-iteration election/backedge rendezvous; mixed-site refusal; added signed/F32/FTZ/half-subtraction forms; own static host64ABI/grid; measured reciprocal domain; actual original stream rejection of the final missing K byte; and complete saved grid identity. `BEFORE_OPCODE_SUPPORT.log`, `BEFORE_ELECT_DIAGNOSTIC.log`, `ELECT_DIAGNOSTIC.log` preserve the earlier boundaries.

This is a bounded original-instruction CPU reference after QKV, not an NN-facing attention tensor lift, a live graph proof, native MMA/SASS/approximation equivalence or whole-model equivalence. In particular it inherits the stated QKV sqrt32 reference limitation. NoGPU/PE/Wine/installed/config/network changes.
