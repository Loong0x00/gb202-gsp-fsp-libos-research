# GSP/FSP/LibOS Clean Copy — Manifest

Source: `/home/user/rt_5090_project`
Destination: `/home/user/gsp_libos_clean`
Created: 2026-10-18

## Copied

- `gsp_qemu/` — GSP/LibOS QEMU lab (full tree)
- `gspkm/` — NVIDIA open kernel module source 610.57.04
- `driver_gpio_internal_610.43.03/` — older open kernel module source + GPIO patch
- `fsp_code/` — FSP code dumps / disassembly
- `fsp_ace_static_20260927/` — FSP ACE static analysis
- `gsp_fsp_iface/` — interface notes (may be empty)
- `ghidra_scripts/` — Ghidra scripts
- `ghidra_static/` — Ghidra projects (GSP/PMU)
- `power_governor_reverse/` — GSP clock/power governor reverse engineering
- `vm_mods_lab/` — **docs/configs/scripts only**; qcow2/img/iso/downloads/runs excluded
- `vfio_production_lab/` — **docs/configs/scripts only**; guest images/runs excluded
- Root `*.md`, `*.sh`, `*.py`, `*.c`, `*.h`, `*.yaml`, `*.json`
- `rm_fw_plaintext.bin`, `golden_gunv2.ko`, `nvflash_5877_text_disasm.asm`

## Excluded on purpose

- VM images: `*.qcow2`, `*.img`, `*.iso`
- VM run directories, downloads, raw capture archives
- `capture_archives/` (deleted separately)
- raw `.rgba*`, `.pkl`, old one-off experiment folders
- Ghidra `.rep` internals are included only as part of `ghidra_static/`; do not scan them as text

## Note

This copy is for document classification / dedup / canonicalization only.
The original `/home/user/rt_5090_project` is untouched.
