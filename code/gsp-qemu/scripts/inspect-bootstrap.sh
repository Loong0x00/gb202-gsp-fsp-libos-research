#!/usr/bin/env bash
# Static analysis only. No Python interpreter or firmware instructions execute.
set -euo pipefail
base=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
"$base/scripts/prepare-kernel-fixture.sh"
image="$base/firmware/gsp-bootstrap-610.57.04.bin"
riscv64-linux-gnu-objdump -D -b binary -m riscv:rv64 --stop-address=0x1200 \
  "$image" > "$base/logs/bootstrap-first.asm"
riscv64-linux-gnu-objdump -D -b binary -m riscv:rv64 \
  --start-address=0x1e0a --stop-address=0x2450 "$image" \
  > "$base/logs/bootstrap-main.asm"
riscv64-linux-gnu-objdump -D -b binary -m riscv:rv64 \
  --start-address=0x1200 --stop-address=0x1e0a "$image" \
  > "$base/logs/bootstrap-services.asm"
{
  riscv64-linux-gnu-objdump -D -b binary -m riscv:rv64 \
    --start-address=0x45e --stop-address=0x52a "$image"
  riscv64-linux-gnu-objdump -D -b binary -m riscv:rv64 \
    --start-address=0x3a70 --stop-address=0x3aa0 "$image"
} > "$base/logs/bootstrap-sbi-abi.asm"
echo 'Static production init/SBI client disassembly saved under logs/bootstrap-*.asm'
