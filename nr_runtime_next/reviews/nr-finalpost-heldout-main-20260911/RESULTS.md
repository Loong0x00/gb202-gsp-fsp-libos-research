# Held-out original finalpost validation

Before GPU execution, Main verified the one-shot frozen manifest **bda48252f1823a25dde42284e7b24285064932d5cdd90442ab56b372008317c2**, reran13 CPU tests/frozen recomputation, and saved PRE_GPU_SPEC/FROZEN/RECEIPT/APPROVALS here. No inputs, seeds, policies or predictions were changed after native results.

Two independently seeded, signed finite E4M3 fixtures deliberately contain non-power-of-two mantissas. Both use the original no-texture finalpost CUBIN, real slab/blend and16×16 RGBA32F output, one32-thread CTA. Main fresh guarded runs182307(SHA256-counter) and182353(SplitMix64) both exit0/Guardian0 with full sync/readback/context cleanup and untouched original ELF/input bytes. No original game/NR-pool activation was read.

All three preregistered predictions were compared across all256 written F32 components:

| Fixture | Separate RN mismatches | Q/K fusion only | Merge+Q/K source-proved fusion |
|---|---:|---:|---:|
| SHA256-counter |124|124|**0**|
| SplitMix64 |126|122|**0**|

Maxabs for the winning source-backed policy is0 in both cases. Native tile hashes match the pre-GPU predictions exactly: d0eee18f… and030f3461… . `COMPARISON.json` retains every competing-policy residual, not only the matching policy.

This strengthens the original SASS-based rounding-boundary recovery beyond the old power-of-two fixture, where merge fusion did not activate. It is **not universal Tensor Core/intermediate equivalence, texture/history behavior, full model execution, an image test, or a fix applied to installed games**. Known general HMMA discrepancies remain separate.

Worker freeze/reference artifacts and all prior references remain unchanged. The new host clones differ only in Main authorization and selected frozen header/root; no original kernel patch or PTX downgrade.
