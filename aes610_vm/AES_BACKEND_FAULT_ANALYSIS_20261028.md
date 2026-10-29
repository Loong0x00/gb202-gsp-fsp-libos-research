# AES natural-context recovery and SE0 backend fault — 2026-10-28

## Result

The GSP multi-callback path works, and a natural-layout AES context can now be injected and read back. However, no AES known-answer operation or decryption oracle has been established. AES0 reaches the SE0 backend and faults before producing output. AES1 times out without output. No `FSP_RUN` input was used.

## Verified address/context corrections

The queue-size change moved the historical staging addresses. A full Xid register dump in the current 128-slot-queue configuration gave:

- current metadata base: `0x0fe4791010`
- C at metadata+0x400: `0x0fe4791410`
- sidecar at metadata+0x500: `0x0fe4791510`
- heap self-link used by the diagnostic map: metadata+0x100 = `0x0fe4791110`

A read-gadget read of `C+0x10` returned `0x0030100300001009` (reported PC `0x0030100300001008` after jalr bit clearing), exactly matching the injected mode/flags. This closes the C address/content loop; it is not a host-staging assumption.

The last injected queue element is now saved by the host driver and dumped as `SCTX`, providing direct `C+0x70/+0x74/+0x78` readback. The final queue log also prints actual a1/B8/C fields.

## AES object correction

`0x1bf26b0` returns a 48-byte selector-table object pointer, not the descriptor pointer alone. Therefore `C+0` must be the table object, not `0x1e8f090` directly:

- AES0 object: `0x1e8efd0` (`"AES0 engine [AES/RNG]"`)
- AES1 object: `0x1e8efa0` (`"AES1 engine"`)
- shared descriptor: `0x1e8f090` (`"SE0"`)

The previous small integer table at `0x1e140c8` is not a set of backend tokens to enumerate. The earlier `0x1f` experiment is not valid evidence about a real token. `C+0x68` is used by finalization as a 16-byte address/buffer; it must not be interpreted as that old token table's value.

## AES0 fault evidence

With the corrected C, AES-128-GCM zero-vector input and readback, AES0 produced:

- `sepc = 0x1a97582`
- `stval = 0x164010f8`
- `scause = 5` (load access fault)
- PC chain includes `0x1bf3f56 -> 0x1bf67c0 -> 0x1a97582`

The descriptor supplies SE0 base `0x01500000`; AES0's operation reads logical offset `0x10f8`. The active address window translates this to `0x0164010f8`, which faults before phase/readback progress or ciphertext/tag output. This is a backend access failure, not evidence of an AES key or GCM test failure.

A separate read of identity address `0x015010f8` returned qword `0x0693865a10079c62` rather than a load fault. That only proves the address is readable; it does not prove it is the correct SE0 register alias. Changing the window alias to identity would be unjustified and was not done.

AES1 (`0x1e8efa0`) did not produce the same fault but timed out with no output and no phase progress. It is not an oracle either.

Evidence files include:

- `aes0-current-base-kat-run.log`
- `aes0-current-base-kat-full-dmesg.log`
- `aes1-current-base-kat-run.log`
- `aes0-read-c10-current-run.log`
- `fault_1a97582.objdump.txt`
- `aes0-read-mmio-identity-run.log`

## Public corroboration

Public NVIDIA OP-TEE logs contain the same family of messages, including `SE0 err_status register 0x10f8` and `AES0 engine [AES/RNG]`. This confirms that `0x10f8` belongs to the SE0 error-status path. It does not supply a GB202 address mapping or prove that SE0 is available on RTX 5090.

## Boundary and next actions

- Do not feed `FSP_RUN` to this path.
- Do not enumerate the old small integer table as tokens.
- Do not blindly replace the SE0 alias with identity or keep changing AES parameters.
- A future AES attempt needs new evidence of a valid GB202 SE0/GSP backend mapping and a known-answer output readback.
- Current host NVIDIA/GDM were restored. Research overlays were removed; the immutable guest base remains unchanged.
