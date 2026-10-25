#!/usr/bin/env bash
# Uses NVIDIA's official host-side extractor. It does not emulate a CPU.
set -euo pipefail
base=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source_dir=${NVIDIA_SOURCE_DIR:-/home/user/rt_5090_project/gspkm}
expected_key=af870e5dde972840588bfb94a87f94b19ad6659dae6e1343dd0d22f16074ba39
if ! grep -qx 'NVIDIA_VERSION = 610.57.04' "$source_dir/version.mk"; then
  echo 'Expected unmodified NVIDIA 610.57.04 source for this profile' >&2
  exit 1
fi
python3 -B "$source_dir/nouveau/extract-firmware-nouveau.py" \
  -i "$source_dir" -o "$base/firmware/610.57.04"
fmc="$base/firmware/610.57.04/nvidia/gb202/gsp/fmc-610.57.04.bin"
boot="$base/firmware/610.57.04/nvidia/gb202/gsp/bootloader-610.57.04.bin"
objcopy -I elf32-little --dump-section \
  "publickey=$base/firmware/gb202-610.57.04-gfw-publickey.bin" "$fmc" /dev/null
actual=$(sha256sum "$base/firmware/gb202-610.57.04-gfw-publickey.bin" | cut -d' ' -f1)
[[ $actual = "$expected_key" ]] || { echo 'Production key differs from pinned official release' >&2; exit 1; }
"$base/tools/nvfw-verify" "$fmc" "$boot" "$expected_key"
sha256sum "$fmc" "$boot" \
  "$source_dir/src/nvidia/generated/g_bindata_kgspGetBinArchiveGspRmBoot_GB202.c" \
  "$source_dir/src/nvidia/generated/g_bindata_kgspGetBinArchiveGspRmFmcGfwProdSigned_GB202.c" \
  > "$base/firmware/610.57.04/provenance.sha256"
