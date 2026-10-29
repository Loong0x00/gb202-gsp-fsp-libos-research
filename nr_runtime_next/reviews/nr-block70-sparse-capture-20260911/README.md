# One-tile sparse input capture: review package

**CPU-only design/code; no runtime integration, GPU execution or experiment approval.**

Start with [REVIEW.md](REVIEW.md): exact readset, barriers, cookie/list/fence bridge proposal, isolated debug flush contract and blocking risks.

- `src/sparse_policy.py`: executable CPU admission/range/lifecycle/forwarding model (not a GPU API).
- `src/sparse_copy.cu`: OWN GLOBAL memcpy kernel; `build/sparse_copy.sm120.cubin` is CPU-compiled sm_120, not loaded.
- `src/evidence_plan.py`, `evidence/READSET.json`: pinned captured-host-ABI readset, no activation payload.
- `tests/`: CPU negative tests and compiled-shader ABI/access checks.
- `evidence/SOURCE_PINS.json`: selected worker 0fef provenance; records current Main 5ca2 mismatch.
- `build/verification.log`: 14 model test groups, 41 unmodified observer mock modes and shader inspection pass.

Default proposed payload: **2,560 input bytes + 21,808 weights = 24,368 bytes**, optional blend adds 4 (only first 2 semantically valid). No output/P1 capture.

Reproduce CPU checks only:

```sh
make -B -C reviews/nr-block70-sparse-capture-20260911 all
```

Remaining blockers: actual recording→Pending/list/cookie→Submitted fence integration, source bound-memory/queue lifetime proof, and NVX GLOBAL synchronization/state/driver compatibility. The existing trace cannot supply these proofs. Gate is defined only in the model/proposal, so setting it cannot enable any runtime capture.
