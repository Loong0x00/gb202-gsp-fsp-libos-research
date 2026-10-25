#!/usr/bin/env bash
# Extract unchanged PT_LOAD bytes from the pinned installed production image.
# This is data preparation, not firmware authentication or CPU emulation.
set -euo pipefail
base=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
original=${NVIDIA_GSP_IMAGE:-/usr/lib/firmware/nvidia/610.57.04/gsp_ga10x.bin}
out="$base/firmware/kernel-610.57.04"
mkdir -p "$out"
# Match the production catalog's name, then derive its payload offset. The
# catalog pointers are relative to fwimage+0x6d000, not the outer ELF file.
printf 'kernel_gb20x.elf\0' | cmp -n 17 -i 0:$((0x40+0x6d2b0)) - "$original"
read -r blob_relative < <(od -An -tu8 --endian=little \
  -j $((0x40+0x6d2e0)) -N8 "$original")
read -r code_size < <(od -An -tu8 --endian=little \
  -j $((0x40+0x6d2e8)) -N8 "$original")
read -r data_size < <(od -An -tu8 --endian=little \
  -j $((0x40+0x6d320)) -N8 "$original")
[[ $blob_relative = 655360 && $code_size = 57344 && $data_size = 110592 ]] || \
  { echo 'Unexpected GB20X catalog layout' >&2; exit 1; }
kernel_offset=$((0x40+0x6d000+blob_relative))
dd if="$original" of="$out/kernel-load-segments.elf" bs=65536 \
  iflag=skip_bytes,count_bytes skip="$kernel_offset" \
  count="$((code_size+data_size))" status=none
expected=d556e44f4b542ed801b43d31a0d4c5e1cbbf030b2871adb16f2b582b7aa9db44
actual=$(sha256sum "$out/kernel-load-segments.elf" | cut -d' ' -f1)
[[ $actual = "$expected" ]] || { echo 'Pinned production kernel mismatch' >&2; exit 1; }
dd if="$out/kernel-load-segments.elf" of="$out/code.bin" bs=65536 \
  iflag=count_bytes count=$((0xe000)) status=none
dd if="$out/kernel-load-segments.elf" of="$out/data.bin" bs=65536 \
  iflag=skip_bytes,count_bytes skip=$((0xe000)) count=$((0x1b000)) status=none
dd if="$original" of="$base/firmware/gsp-bootstrap-610.57.04.bin" bs=65536 \
  iflag=skip_bytes,count_bytes skip=64 count=$((0x6e000)) status=none
printf '%s\n' 'Verified unchanged production kernel load segments extracted'
