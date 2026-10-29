# Task #466 continuation — B8/AES feasibility results

## Outcome

No B8 read/write canary and no AES known-answer operation were established. No `FSP_RUN` data was used.

## New evidence

1. Rebuilt the 610.57.04 RM core from source and confirmed an inert, healthy NVML boot before experiments.
2. Current disassembly and Ghidra decompilation confirmed:
   - `C+0x30` is key width in bits; `C+0x34` is a slot index (`<=15`).
   - `C+0x70` is a natural completion-length readback, not an error code.
   - B8 backend `0x0100cf9c` uses bit 0 for read/write direction and bit 8 for window selection.
3. Corrected the synthetic AES context from `0x100/16` to `128/0`. With this correction and firmware logging enabled, the result remained RPC timeout and all-zero output. No AES plaintext/ciphertext/tag was proven.
4. Direct 32-bit writes to candidate shared-queue GSP VAs did not produce a host-visible canary. An early 250 ms host-RAM readback was also zero, so the result is not just delayed cleanup erasing the value.
5. Synthetic B8 backend descriptors and candidate natural descriptors `0x041914d0` and `0x04191620` did not produce an availability-read/consume-write canary.
6. A direct read-gadget probe of the current `metadata+0xc0` produced `sepc=0`, `stval=0`, `scause=0xc`: **the current backend argument is NULL**, not the old documented `0x04191620`. This is a concrete reason the old backend recipe cannot be reused unchanged.
7. The previous staging layout bug was corrected to `meta_only=1`. A full 33-element copy is not used for subsequent experiments.

## Interpretation limits

- A timeout alone is not treated as AES execution or B8 success.
- Old B8 documents contain conflicting values and are not authoritative for the current runtime.
- These failures do not prove that every B8 repair or every AES0/kslot design is impossible. They show that the current synthetic context and readback path are not validated.

## Cleanup

Eight task-created VM overlays from this continuation were removed. The immutable base remains mode `0444`. Host GPU is restored to `nvidia`/`snd_hda_intel` and verified healthy through the authorized status task (615.78.08, 0 MiB used, no processes).

## Next work that is justified

- Recover a naturally initialized B8 window/backend context or the actual v25.x two-step source, rather than more candidate-address guessing.
- Establish a separate, minimal return-status/readback channel before another AES attempt.
- Do not feed `FSP_RUN` unless a software-reference AES known-answer test first succeeds.
