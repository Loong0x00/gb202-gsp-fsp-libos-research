#!/usr/bin/env bash
set -euo pipefail
base=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
mkdir -p "$base/build" "$base/logs"
if [[ ! -f "$base/build/build.ninja" ]]; then
  (cd "$base/build" && ../qemu/configure --target-list=riscv64-softmmu \
    --without-default-features --enable-tcg --disable-docs --disable-werror \
    --disable-tools) > "$base/logs/configure.log" 2>&1
fi
ninja -C "$base/build" -j "${JOBS:-8}" qemu-system-riscv64
cc -std=c11 -O2 -g -Wall -Wextra -Werror -I "$base/qemu/hw/riscv" \
  "$base/tools/nvfw-verify.c" "$base/qemu/hw/riscv/nvidia_gsp_boot.c" \
  -o "$base/tools/nvfw-verify" $(pkg-config --cflags --libs openssl zlib)
