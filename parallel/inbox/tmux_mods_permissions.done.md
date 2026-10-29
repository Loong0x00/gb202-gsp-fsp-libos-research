# GB202 MODS permission/sequencing worker completion

STATUS: COMPLETE

Report: `/home/user/rt_5090_project/parallel/tmux_mods_permissions.md`

Headline findings:

1. MODS security level `>3` is a process-local host gate, not a GPU/FSP authorization result (`parallel/tmux_mods_permissions.md:21-30`).
2. Host-visible preparation is optional PRC -> FSP task 2/subobject 1 -> optional host floorsweep apply. Intended `d0/dc` preparation is a strong inference but actual GB202 firmware action remains unproved; even intended `f8` coverage, plus all lifetime/restore behavior, is unknown (`parallel/tmux_mods_permissions.md:45-66`).
3. Direct application is attempted latch set -> raw write -> readback; latch/write results are not checked directly, and special read value `0xbadf510c` logs without setting an error (`parallel/tmux_mods_permissions.md:24-29`).
4. Writer error takes cleanup with no host rollback, latch clear, or reset; writer success enters the coupling-selected reset/reinit chain, with no successful no-reset variant in the inspected entry (`parallel/tmux_mods_permissions.md:33-40`, `parallel/tmux_mods_permissions.md:74-79`).
5. Current GB20x resense does issue the decoded clear operation, contradicting a blanket no-latch-clear claim, but it is not writer rollback and coupling/clear preparation is not fail-closed; TU/GA/GH and older PMU/certificate findings cannot be generalized without a GB202 binding (`parallel/tmux_mods_permissions.md:70-79`, `parallel/tmux_mods_permissions.md:102-110`).

Unresolved questions: the private GB202 task-2 consumer and PLM lifetime/restore; live `d0/dc/f8` and latch state; the direct-shadow effect of `0x8212ac.bit0`; PRC `0x1d` value/self-clear semantics (ID corrected by `parallel/prc_knob_metadata.md`); GB202 HULK validation/task effects; and any undocumented firmware rollback or alternate private entry (`parallel/tmux_mods_permissions.md:112-119`).

No live GPU operation, MODS execution, device-node access, PCI/BAR/MMIO/debugfs/internal-RM access, reset/rebind/module action, or firmware/system-configuration change occurred.
