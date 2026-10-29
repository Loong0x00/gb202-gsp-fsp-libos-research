# GSP multi-callback breakthrough and current AES boundary — 2026-10-28

## Verified: a real second callback exists

The following single injected message produced two distinct indirect calls:

- `B8 = 0x0100dcba` (ret0)
- `+0xe0 = 0xdeadbeef` (fcnBarrier)

Crash evidence:

- `sepc = stval = 0xdeadbeee`, `scause = 0xc`
- `ra = 0x01004d52`
- PC trace: `0xdeadbeee → 0x01004d50 → 0x0100dcbc → 0x01004d30 → 0x010162c4`

This is not a second RPC and not a timeout interpreted as success. It is the post-B8 callback after the first callback returned zero. Evidence files:

- `notify-second-run.log`
- `notify-second-dmesg.log`

The previous `FAIL_OR_UNPROVEN` text was only a script acceptance bug: it required `0xdeadbeef`, while jalr clears bit 0 to `0xdeadbeee`.

## Transport findings

- A 128-slot command queue allows two full injected messages to be submitted, but that alone does not prove a second callback. Queue capacity and callback execution are separate.
- `meta_only=1` still copies 33 complete 4 KiB elements into a `2*64 KiB+0xe8` allocation, so trailing heap corruption remains possible.
- `metadata+0x110/+0x118` self-repair avoided the specific allocator crash at `0x1a98380`, but it is not a valid callback/readback mechanism and must not be confused with success.
- `seq=0` and `seq=previous` did not produce the required path. Real sequence numbers plus valid checksums are the useful path.

## AES selector/token findings

- Selector table at `0x1e8ef70` contains masks `0x5061`, `0x102`, `0x804`, `0x400020`; direct B8 calls with `a2=4` do not match a descriptor.
- Runtime selector index at `0x41d40b4` is `0`, and token table index 0 is `0`, while AES code requires `C+0x68 != 0`. Thus the natural backend token is unavailable in the current environment.
- `C+0x68=0x1f` (table index 1) was tested with the AES-128-GCM zero vector and heap repair. It produced no expected ciphertext/tag and ended in RPC timeout. It is not an oracle.
- Remaining table tokens must not be enumerated blindly. No `FSP_RUN` input was used.

## Current boundary

The multi-callback mechanism is now demonstrated, but there is still no validated natural AES context, backend token/address mapping, or objective AES output readback. Next work must recover those objects from current disassembly/runtime evidence, not try more queue addresses or tokens.

## Environment

- Host NVIDIA and GDM restored.
- No research VM is active.
- Task overlays were removed; immutable base remains mode `0444`.

## Erratum / later evidence

The statements that selector/token values prove the natural backend is unavailable and that `0x1f` was a meaningful token candidate are superseded. Later disassembly and runtime reads showed that the small integer table is not a token enumeration, `C+0` is a selector-table object, and `C+0x68` is used as a 16-byte finalization buffer. Current staging addresses also changed with the enlarged queue. See `AES_BACKEND_FAULT_ANALYSIS_20261028.md` for the corrected context and the actual SE0 backend fault.
