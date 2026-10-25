#!/usr/bin/env bash
# Failure at BOOTROM_REQUIRED is intentional until that stage is implemented.
# Do not translate it to success or provide a synthetic ROM to bypass it.
set -euo pipefail
ulimit -c 0
base=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
exec "$base/build/qemu-system-riscv64" -accel tcg \
  -machine "nvidia-gsp,fmc=$base/firmware/610.57.04/nvidia/gb202/gsp/fmc-610.57.04.bin,bootloader=$base/firmware/610.57.04/nvidia/gb202/gsp/bootloader-610.57.04.bin" \
  -display none -serial none -monitor none -nic none
