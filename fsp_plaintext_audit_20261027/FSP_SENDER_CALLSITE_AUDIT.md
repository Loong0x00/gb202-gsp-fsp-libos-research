# MODS 570.215 direct FSP sender callsite audit

Goal: find a private FSP decrypt request that could return `FSP_RUN` plaintext to a host vector.

Method: static `objdump` enumeration of every direct `call 0x18a0d40` in the MODS ELF, followed by local disassembly/decompilation. No command was sent to hardware.

## Result

Only seven direct callsites exist:

| Callsite | Outer command | Visible response shape | Classification |
|---:|---:|---:|---|
| `0x00e241c7` | low byte `0x82` | 4-byte bit/status result | small feature/status request; 7-byte request |
| `0x0173b1fe` | `0x0f` | exact 4-byte `0x0000000f` | FuseRework |
| `0x018a0e47` | `0x0c` | exact 4 bytes | internal two-byte request wrapper |
| `0x01f11d4c` | `0x0e` | exact 12 bytes | telemetry/clock-style response |
| `0x01f4b9f3` | `0x0e` | exact 24 bytes | telemetry/clock-style response |
| `0x01f542fb` | `0x0e` | exact 24 bytes | telemetry/clock-style response |
| `0x01f5468d` | `0x0e` | exact 24 bytes | telemetry/clock-style response |

No direct callsite has the shape expected for bulk decryption to a host response vector: no request carrying an FSP v6 crypto descriptor followed by a response sized like the `0x29400–0x37000` encrypted payloads.

This does not prove the FSP firmware lacks a decrypt service; `NON_FSP_DECRYPTION_DEV_NOT_ALLOWED` remains evidence of an internal policy/error path. It does show that this MODS build has no obvious direct host wrapper around `FspSendRequestCandidate` that returns a full decrypted image.

Evidence:

- `fsp_sender_callsites.txt`
- `ghidra_all_fsp_sender_callers.c`
- `ghidra_fsp_sender_18a0d40.c`
- `ghidra_fsp_sender_helpers.c`
