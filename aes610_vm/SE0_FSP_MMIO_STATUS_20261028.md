# SE0 and direct FSP-MMIO status — 2026-10-28

## SE0 boundary

The Xid register state closes the address-translation description without further table reads:

- logical base `0x01500000`
- size `0x00040000`
- paired base `0x16400000`
- AES0 input `0x015010f8` becomes `0x164010f8` and faults at `0x1a97582`, `scause=5`.

Thus the firmware's mapping is understood; the target is inaccessible. Host `GPU_EXEC_REG_OPS` also returns `0xbadf1100` for the paired address. No alternate GB202 mapping was found in 610.57, 615, Windows 610.88, public headers, or public OP-TEE examples. AES0/AES1 still provide no known-answer output or oracle, and no further alias/token experiment is justified.

## Objective B8 status result

See `B8_STATUS_BREAKTHROUGH_20261028.md`. A strict ret0-controlled experiment proves that the real B8 backend can return zero and reach the success-only second callback. General B8 data read/write remains unproven.

## Direct FSP-MMIO attempts

- `0x1a97540` does not cover `0x8f2ac0` in its registered window table and goes to the error path `0x1aa3410`.
- A raw `lwu` of `0x8f2ac0` faults in the injected task, so the host BAR0 address is not directly mapped there.
- `0x41904e0 = 0x820000`, but this is the FUSE base. Treating it as a universal MMIO base and reading `0x1112ac0` returned a random-looking qword, not the known EMEMC value; that interpretation is rejected.
- `0x41d4140+0xb98 = 0`, so this is not the natural FSP client object/mapping base.
- A callback chain that returns MMIO values through a fault address is feasible in principle, but no valid FSP effective address has been established. No result is being inferred from unrelated faults.

## Current boundary

- No `FSP_RUN` plaintext, no AES oracle, no SM/L2 unlock.
- The remaining direct-GSP route requires the natural FSP client object and its private mapping, not more address arithmetic guesses. Static recovery is in progress.
- Host EMEM protocol telemetry and the already verified GSP RAM read-gadget remain separate capabilities; they do not prove access to FSP IMEM/DMEM.
