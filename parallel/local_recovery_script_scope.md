# Local `nvidia-reset.sh` recovery-scope audit

Status: **final, source-read only**
Date: 2026-07-21

## Scope

Inspected `/home/user/hw_configs/nvidia-reset.sh` as text only. The script was
not executed, sourced, syntax-traced, or passed to a shell. No process, service,
driver, PCI device, GPU, or display state was changed.

Artifact:

- path: `/home/user/hw_configs/nvidia-reset.sh`
- size: 3,297 bytes
- SHA-256: `672d1fa39e3f7e70bff8729e0c6355dda673644bbcdba944faf9d31fa480f296`
- fixed GPU BDF: `0000:01:00.0`
- fixed upstream bridge BDF: `00:01.1`

## Direct result

This is a forceful whole-device SBR/reload recovery procedure, not a software-
shadow rollback. It may be useful for the dirty GSP/RM conditions for which the
user originally wrote it, but the source contains no latch/raw/effective-mask
read, no saved old raw plan, no `0x404f0000` clear-coded request, and no fuse
resense operation. Therefore it does not prove that a partial L2 shadow change
would be cleared.

It is also categorically unsuitable while the desktop is on the RTX 5090. The
script's own prerequisite says GNOME must not hold NVIDIA DRM, then it kills all
holders, unloads all NVIDIA modules, asserts Secondary Bus Reset on the upstream
bridge, rescans PCI, reloads the modules, and runs `nvidia-smi`.

## FACT

The source-visible sequence is:

1. stop `lactd`;
2. enumerate `/dev/nvidia*` and NVIDIA DRI/render nodes;
3. send TERM, then KILL, to every holder and abort if any remains;
4. unload `nvidia_drm`, `nvidia_uvm`, `nvidia_modeset`, and `nvidia`;
5. toggle bridge-control bit `0x40` through `setpci` on `00:01.1` (SBR);
6. request a global PCI rescan and check that `01:00.0` is present;
7. reload all NVIDIA modules;
8. validate only that `nvidia-smi` succeeds, then restart `lactd`.

The no-argument guard is fail-safe against an accidental `--help` invocation,
but a genuine no-argument invocation proceeds directly into this sequence.

The verification step does not compare:

- pre/post raw shadow (`0x8234e0 + 4*FBP`);
- override latch (`0x820040.bit0`);
- current/effective mask (`0x822900 + 4*FBP`);
- fuse-status view (`0x820d70 + 4*FBP`);
- L2 size/count or per-FBP active topology.

## INFERENCE

- Module unload plus SBR plus module reload is capable of rebuilding host RM/GSP
  state when all device users have been removed; this matches the script's
  stated dirty-state recovery purpose.
- In the MODS reset taxonomy, SBR is closest to the `hot` reset class. Current
  static evidence does not define whether the override latch/raw shadow are
  retained, cleared, or consumed by that reset domain.

## UNKNOWN

1. Whether this motherboard's BDFs remain correct after firmware/slot changes.
2. Whether the bridge hosts any other function affected by SBR.
3. Whether SBR clears an accepted or partially accepted software-shadow plan.
4. Whether a malformed effective topology can prevent GSP/module reload before
   the script reaches its `nvidia-smi` check.
5. Whether a cold power cycle, fuse reset, or explicit resense would be required
   instead; none is established here as a safe rollback.

## Minimal conclusion

Keep this script as a lab recovery tool only after the display and all GPU users
have moved away from the 5090. Do not count it as the missing rollback proof for
an L2 shadow experiment, and do not run it on the current desktop configuration.
