# Task #465 — 610.57.04 AES0/kslot oracle experiment

Date: 2026-10-28

## Result

**No AES0/kslot oracle was established.** No known-input/known-output AES operation completed, and no valid GCM tag or ciphertext was obtained. `FSP_RUN` was never supplied to AES0.

The work also does **not** prove that AES0, a particular keyslot, or every possible B8/multi-call design is unusable. The current blocker is the lack of a validated natural runtime AES context and an objective return-status/readback path. Old B8/metadata documents were used only as leads; they are not treated as authoritative ABI evidence.

## What was built and verified

- Built `nvidia.ko` 610.57.04 for Guest kernel `7.1.9-arch1-2`.
- Final module SHA-256:
  `43abd93735a27ead943c47110aaa69a84d5354a557a5847ad70ce422f8492666`
- Included WPR2 fail-early bypass, a 2-second RPC timeout, v23 K3/XDIG changes, and diagnostic QPTE/queue readback.
- Initially, direct Kbuild linked the prebuilt `nv-kernel.o_binary`, so RM-source changes were absent. That module was not counted as a valid K3 experiment. Rebuilding the RM core from source fixed this; an inert (`xdig_k=0`) load then produced real XDIG metadata/RPC logs and a healthy `NVIDIA GeForce RTX 5090` NVML response.
- 610.57.04 GSP firmware SHA-256:
  `c0156954f3e048d56011524e0c2ae2881bb6db8173b53f9b2f4eb94197f02999`

## Current 610.57 static facts used

- AES0 table entry: `0x1e8efd0`, name `AES0 engine [AES/RNG]`.
- AES0 engine descriptor pointer: `0x1e8f090`.
- The crypto request entry tested was `0x1bf4208`.
- Current disassembly, not old documents, establishes:
  - `C+0x30` is key width in bits (128/256 accepted paths).
  - `C+0x34` is a slot index and must be <= 15.
- The first payload incorrectly used `0x100/16` (256-bit key + slot 16). This was corrected to `128/0` (AES-128 + slot 0). Even after that correction and enabling firmware logs, the result remained an RPC timeout with all-zero output.

## Hardware evidence summary

| Experiment | Evidence | Interpretation |
|---|---|---|
| Inert source-built module | XDIG metadata and RPC sequence present; NVML healthy | Build/boot path validated, no overflow |
| Context selector `0x1bf26b0` | `sepc=0x1bf26fc`, `scause=6`, AES1 table entry in registers | Function reached; unaligned 64-bit store at `a0=...0e9c`, not AES evidence |
| `meta_only=0` AES payload | Allocator crash at `0x1a98380` | Rejected: copy exceeded the staging+metadata block and corrupted adjacent heap state |
| `meta_only=1` AES payload | Bounded RPC timeout, all-zero QOUT | No known-answer operation |
| Shared DMA context/state | QIV host write visible; QCTX/QSTATE unchanged | Raw QPTE PA is not a valid substitute for the GSP CPU context address |
| Shared DMA write canary | No canary; allocator crash | Readback/callback chain not validated; not called a success |
| Corrected AES-128 slot 0 + firmware logs | RPC timeout and all-zero QOUT; no useful AES stage log | Still no oracle; current state is not distinguishable from early rejection or another unmet runtime prerequisite |

No ciphertext matching `0388dace60b6a392f328c2b971b2fe78` and no tag matching `ab6e47d42cec13bdf53a67b21257bddf` was observed.

## B8 / old-document caution

The old files contain useful but conflicting B8 recipes. Current 610.57 disassembly confirms that B8 has signature
`(pVal, pAddr, size, flags, arg)` and participates in queue availability/data I/O. A custom callback can therefore trigger once yet leave the queue protocol degraded. A timeout alone was not used as proof of AES success.

A B8 repair or multi-call mechanism must be revalidated against current disassembly and a minimal canary before it is used for AES. No such repaired multi-call chain was validated here.

## Cleanup and host restoration

- QEMU was stopped with QMP `quit`, not `system_reset`.
- VFIO recovery used the bounded existing flow; no repeated reset loop was used.
- All nine task-created qcow2/OVMF run directories were removed.
- Immutable base remains mode `0444` and was not modified.
- Host functions are bound to `nvidia` and `snd_hda_intel`.
- Host NVIDIA is healthy through the existing authorized status task: driver `615.78.08`, RTX 5090, 27°C, 0 MiB used, no processes.
- Display restoration was not requested from the VFIO script; the host did not switch display ownership to the NVIDIA DRM stack.

## If this line is resumed

1. Obtain a natural runtime AES operation context, including the fields that the high-level client requires, rather than another synthetic object tree.
2. Establish an objective callback return-status channel and a minimal write/read canary before another AES attempt.
3. Only then run the AES-128 zero-vector test again. Do not feed `FSP_RUN` until ciphertext and tag match a software reference.
4. Separately establish slot ownership and AES-256 support; the experiments here did not answer either question.
