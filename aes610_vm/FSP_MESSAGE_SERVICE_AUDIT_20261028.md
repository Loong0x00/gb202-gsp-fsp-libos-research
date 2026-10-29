# Route 1: FSP message services for plaintext export — 2026-10-28

## Result

No demonstrated runtime service exports `FSP_RUN` plaintext. EMEM is a transport, not plaintext storage. No new hardware request was sent in this audit.

## Service-by-service findings

- `INFOROM (0x17)`: live data service for board information such as PPID. It does not provide FSP firmware memory or a decrypted image.
- `ROMREAD (0x1a)`: runtime requests are not accepted; current evidence classifies it as a UEFI-phase service. It addresses ROM content, not demonstrated access to the FSP's decrypted internal image. It is not a runtime plaintext-export route.
- `UEFI_RM (0x1c)` and `UEFI_XTL_DEBUG_INTR (0x1d)`: response/error activity exists, but no local plaintext source supplies a memory-read/export schema. No GSP wrapper or message-header constant for these types exists in the 610.57 image.
- `0x1b`: CAPS proves presence of a service, but its name and schema are unknown and requests remain silent. It is not evidence of a decrypt or export service and must not be fed `FSP_RUN` by speculation.
- `PRC Read (0x0c)`: small configuration/object reads only; no firmware-image export.
- `COT`, `FWUP`, `HULK`, `CAPS`, `CLOCK_BOOST`: no plaintext-export evidence.
- MODS 570.215 and FieldDiag 580 sender audits found only small status/ACK/telemetry responses, no bulk decrypt-to-host response.

## Consequence

Stop using EMEM buffer scanning as a plaintext strategy. Route 1 is closed unless a new schema or engineering artifact appears. Move to route 2: evaluate the natural FSP client's private mapping only with a positive control, and do not repeat the already-poisoned formal GSP-PRI reads.

## References

- `FSP_SENDER_CALLSITE_AUDIT.md`
- `FIELDDIAG580_AARCH64_FSP_SENDER_AUDIT.md`
- `FSP_BAR0_READ_SESSION_20261027.md`
- `NVDM_DEMUX_AND_ENTRIES_AUDIT.md`
- `fsp_romdump_mod.c` (ROMREAD request format, UEFI-only service)
