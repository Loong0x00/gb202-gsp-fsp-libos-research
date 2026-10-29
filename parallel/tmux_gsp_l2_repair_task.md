# GB202 worker task: current GSP L2 repair-path audit

You are an independent interactive Codex worker operating inside
`/home/user/rt_5090_project` on hardware owned by the user.

Read `/home/user/rt_5090_project/GB202_PARALLEL_WORK.md` completely before
doing anything.  Its safety and resource limits are mandatory.

## Scope

Use only current 610.43.03 source and the already extracted static GSP ELF to
investigate these strings and the code/data that references them:

- `Marking LTS ... along with its pair for repair`
- `Repairing LTS failed as there are no more spare L2 slices`
- `pending LTS swap`

Determine, as far as bounded static evidence permits:

1. The enclosing function(s), callers, and chip/HAL gating.
2. Whether this is runtime row-remapping, one-time manufacturing repair,
   InfoROM persistence, next-reset activation, or some combination.
3. Whether GB202 is actually bound to these methods in current firmware.
4. Whether this repair/spare map is demonstrably separate from SKU LTS
   floorsweeping, or whether separation remains only an inference.
5. What non-invasive observability, if any, current open RM exposes.

Useful inputs include:

- `/tmp/gsp_inner_19f040_a.elf`
- `/usr/src/nvidia-610.43.03/src`
- `/home/user/rt_5090_project/L2_REENABLE_STATIC_FINDINGS.md`
- existing small Capstone helpers under the project

## Hard limits

- Static analysis only.  Do not access the live GPU or `/dev/nvidia*`.
- No MODS execution, MMIO/BAR/debugfs/internal RM, resets, rebinds, driver
  unloads, firmware operations, clock/power changes, or VBIOS changes.
- No root/sudo.
- No Ghidra or whole-file decompilation.  Use bounded windows and streaming
  scans; keep memory modest.
- Do not spawn additional agents.
- Do not edit the main findings document.

## Output

Write evidence incrementally to:

`/home/user/rt_5090_project/parallel/tmux_gsp_l2_repair.md`

For every claim cite a source path and line or ELF file/virtual address.
Clearly separate `PROVED`, `INFERENCE`, and `UNKNOWN`.  End with a short
plain-language summary and then remain in the interactive session.

## Completion report to the coordinator

When the task is genuinely complete, also create:

`/home/user/rt_5090_project/parallel/inbox/tmux_gsp_l2_repair.done.md`

That completion file must contain: `STATUS: COMPLETE`, report path, five or
fewer headline findings, unresolved questions, and a statement that no live
GPU operation occurred.  Do not create the completion file early.  If
blocked, create the same filename with `STATUS: BLOCKED` and the precise
blocker.  The coordinator polls this per-worker inbox file.
