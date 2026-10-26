#!/bin/bash
# run windows family over full local corpus via allowlist task
FILES=(
/home/user/rt_5090_project/mods_audit/static/extracted_inner/mods
/home/user/rt_5090_project/ghidra_static/gsp_inner_570144_main.elf
/home/user/rt_5090_project/ghidra_static/gsp_inner_19f040_a.elf
/home/user/rt_5090_project/power_governor_reverse/gb202_r570215_runtime_pmu.elf
/home/user/rt_5090_project/power_governor_reverse/gb202_r570215_clear_pmu.elf
/usr/lib/firmware/nvidia/615.78.08/gsp_ga10x.bin
/usr/lib/firmware/nvidia/615.78.08/gsp_tu10x.bin
/usr/lib/firmware/nvidia/615.78.08/ucodes_ga10x.bin
/home/user/rt_5090_project/vbios_diff/unverified_TPU_276859_RTX5090_FE_98.02.2E.00.03.rom
/home/user/rt_5090_project/vbios_diff/dell_8d_payload/RTXPRO6000_GB202_GPU_98.02.8D.00.01.nvfw
/home/user/rt_5090_project/vbios_diff/hpe_scexe_payload/RTXPRO6000_GB202_GPU_98.02.9E.00.01.nvfw
/home/user/rt_5090_project/parallel/fsp_attack_20261026/clone_prod.bin
/home/user/rt_5090_project/parallel/fsp_attack_20261026/clone_dbg.bin
/home/user/rt_5090_project/parallel/fsp_attack_20261026/gfw_clone.bin
/home/user/rt_5090_project/mods_audit/static/extracted_inner/cask_sm120.bin
/home/user/rt_5090_project/mods_audit/static/extracted_inner/cuda.bin
/home/user/rt_5090_project/mods_audit/static/extracted_inner/fub_ga100.bin
/home/user/rt_5090_project/mods_audit/static/extracted_inner/frb_ga100.bin
)
for f in "${FILES[@]}"; do
  [ -f "$f" ] || continue
  echo "windows $f" > /tmp/fsp_grind_task.args
  echo "== $f"
  sudo gpu-allowlist run fsp-grind 2>&1 | grep -E "done|HIT"
done
