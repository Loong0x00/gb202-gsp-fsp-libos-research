STATUS: COMPLETE

REPORT: /home/user/rt_5090_project/parallel/tmux_prc1d_consumer_refresh.md

HEADLINE FINDINGS:

1. Knob 0x1d is exactly PRC_KNOB_ID_FLOORSWEEPING_ALLOW_INB_ONE_SHOT. Its device-side allowed values remain unknown; 0..65535 is only the necessary post-normalization host round-trip envelope. The task-13 vector is ID16/value16 plus a fixed zero16 tail.
2. ONE_SHOT is established only by the name. The host immediately reads back after writing and performs no post-task-2 read, clear, or rearm; consumption and self-clear timing remain unknown.
3. Task 13/submessage 2 and task 2/subobject 1 are separate PRC transactions. QCAP 0x13 presence and zero command status are protocol facts, not proof that d0/dc/f8 changed.
4. Private MODS logs detailed PRC/floorsweep firmware errors but maps parsed application errors to 0x12d; task-12 length mismatch is 0x12e and write readback mismatch is 0x12f. Public R580/R610 special-case only invalid knob ID 0x1e3.
5. Hopper sibling code strongly supports task 2 as d0/dc permission preparation, but no readable GB202 consumer proves the writes. f8 has no comparable task-2 evidence and remains unknown.

UNRESOLVED QUESTIONS:

- Exact accepted/default values for 0x1d and the meaning of its fixed zero16 tail.
- Consume, self-clear, failed-attempt, and rearm behavior for the one-shot state.
- GB202 task-2 option validation and actual d0/dc/f8 writes, duration, and restore behavior.
- The private GB202 FSP task-2/subobject-1 consumer is not available as readable plaintext in the permitted local artifacts.

NO LIVE GPU OPERATION OCCURRED. No MODS or firmware was executed; no GPU/device node, MMIO/BAR, PCI configuration, debugfs, reset, rebind, unload, firmware operation, credential bypass, or cryptographic cracking was used.
