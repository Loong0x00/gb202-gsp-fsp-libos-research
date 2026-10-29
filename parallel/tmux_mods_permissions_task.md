# GB202 worker task: MODS permission and sequencing audit

You are an independent interactive Codex worker operating inside
`/home/user/rt_5090_project` on hardware owned by the user.

Read `/home/user/rt_5090_project/GB202_PARALLEL_WORK.md` completely before
doing anything.  Its safety and resource limits are mandatory.

## Scope

Perform bounded, static-only analysis of the locally stored MODS binary and
existing project evidence.  Concentrate on the current GB202 path around
`NewFuse.SetSwFuses`, its permission checks, the order of latch/register/FSP
operations, failure handling, and reset/reinitialization behavior.  Check
whether existing claims in `L2_REENABLE_STATIC_FINDINGS.md` are directly
proved, inferred, or contradicted.

Important questions:

1. Which checks are only host-side MODS policy, and which evidence points to
   enforcement by FSP/PLM or another GPU component?
2. What is the exact ordering of permission lowering, latch setting, raw-plan
   application, readback, and reset/reinit?
3. Is there any current-architecture evidence of a rollback, latch-clear, or
   no-reset path?  Report absence carefully; do not infer impossibility merely
   from a failed search.
4. Which older TU/GA/GH findings must not be generalized to GB202?

## Hard limits

- Never execute MODS or any bundled binary/script.
- Do not access `/dev/nvidia*`, PCI BARs, MMIO, debugfs, internal RM controls,
  or the live GPU in any way.
- Do not reset/rebind/unload a device or driver, and do not alter firmware,
  clocks, power, VBIOS, or system configuration.
- No root/sudo.
- No Ghidra, no whole-binary disassembly, and no unbounded recursive scans.
  Use small `strings`, `rg`, `readelf`, and bounded objdump/Capstone windows.
- Keep peak working memory modest; do not retain a full disassembly in RAM.
- Do not spawn additional agents.
- Do not edit the main findings document.

## Output

Write evidence incrementally to:

`/home/user/rt_5090_project/parallel/tmux_mods_permissions.md`

Every material claim must include a file path plus address/offset or line
number.  Clearly label `PROVED`, `INFERENCE`, and `UNKNOWN`.  End with a short
plain-language summary and then remain in the interactive session.

## Completion report to the coordinator

When the task is genuinely complete, also create:

`/home/user/rt_5090_project/parallel/inbox/tmux_mods_permissions.done.md`

That completion file must contain: `STATUS: COMPLETE`, report path, five or
fewer headline findings, unresolved questions, and a statement that no live
GPU operation or MODS execution occurred.  Do not create the completion file
early.  If blocked, create the same filename with `STATUS: BLOCKED` and the
precise blocker.  The coordinator polls this per-worker inbox file.
