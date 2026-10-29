STATUS: COMPLETE

REPORT: `/home/user/rt_5090_project/parallel/tmux_gsp_l2_repair.md`

HEADLINE FINDINGS

- The repair slots belong to `OBJINFOROM`; substantive marking functions are at GSP VAs `0x0156e394` and `0x01581374`, and the shared no-spare handler is at `0x0157b570`.
- On supported chip indices the path stages an in-field LTS-pair swap through an InfoROM-managed request and requires a later bus reset or OS reboot for activation; it is distinct from DRAM row remapping.
- GB202 (`ChipHal` index 65) binds the substantive repair, marking, and apparent commit slots to zero-return stubs, so the shared strings do not establish active GB202 support.
- Static evidence proves distinct InfoROM repair bookkeeping but does not prove a physical repair/spare map separate from SKU floorsweeping.
- Open RM exposes active LTS/LTC/PAC masks and counts plus coarse ECC/other-repair status, but no demonstrated pending-LTS-swap, spare-count, or repair-provenance query.

UNRESOLVED QUESTIONS

- The exact consumer and semantic type of the pointer table containing `pending LTS swap`.
- Whether a distinct physical LTS spare/repair map exists and how it combines with fuse/SKU/software floorsweep state at boot.
- The precise backing-store opcode and whether the supported-chip request guarantees a successful nonvolatile InfoROM write.
- Whether the generic active-topology queries succeed on a live GB202; static declarations permit unsupported results, and live verification was prohibited.

SAFETY: No live GPU operation occurred. The audit did not access `/dev/nvidia*`, MMIO/BAR, debugfs, MODS, reset/rebind/unload paths, firmware operations, clocks/power controls, or VBIOS.
