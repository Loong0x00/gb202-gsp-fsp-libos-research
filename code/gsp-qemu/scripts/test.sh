#!/usr/bin/env bash
set -euo pipefail
ulimit -c 0
base=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
qemu="$base/build/qemu-system-riscv64"
fmc="$base/firmware/610.57.04/nvidia/gb202/gsp/fmc-610.57.04.bin"
boot="$base/firmware/610.57.04/nvidia/gb202/gsp/bootloader-610.57.04.bin"
key=$(cat "$base/docs/sources/610.57.04-official-prod-key.sha256")
cc -std=c11 -O1 -g -Wall -Wextra -Werror -fsanitize=address,undefined \
  -fno-omit-frame-pointer -I "$base/qemu/hw/riscv" \
  "$base/tests/test_boot.c" "$base/qemu/hw/riscv/nvidia_gsp_boot.c" \
  -o "$base/tests/test-boot" $(pkg-config --cflags --libs openssl zlib)
"$base/tests/test-boot" "$fmc" "$boot" "$key" | tee "$base/logs/test-boot.log"

riscv64-linux-gnu-as -march=rv64imac_zicsr -mabi=lp64 \
  "$base/tests/rv64-isa.S" -o "$base/tests/rv64-isa.o"
riscv64-linux-gnu-ld -Ttext=0x80000000 --entry=_start --no-relax \
  "$base/tests/rv64-isa.o" -o "$base/tests/rv64-isa.elf"
timeout --kill-after=2s 10s "$qemu" -machine virt -accel tcg -m 128M \
  -display none -serial none -monitor none -nic none -bios none \
  -device "loader,file=$base/tests/rv64-isa.elf,cpu-num=0" \
  > "$base/logs/test-rv64-isa.log" 2>&1
echo 'PASS QEMU RV64 ISA edge cases (synthetic test only, not LibOS boot)'

expect_rejection() {
  local name=$1 pattern=$2; shift 2
  local rc=0
  timeout --kill-after=2s 10s "$qemu" "$@" -accel tcg -display none \
    -serial none -monitor none -nic none > "$base/logs/$name.log" 2>&1 || rc=$?
  [[ $rc = 1 ]] || { cat "$base/logs/$name.log"; echo "Unexpected exit=$rc"; exit 1; }
  grep -q -- "$pattern" "$base/logs/$name.log"
  echo "PASS $name (explicit rejection before CPU handoff)"
}
expect_rejection qemu-production-gate 'stage=BOOTROM_REQUIRED' \
  -machine "nvidia-gsp,fmc=$fmc,bootloader=$boot"
grep -q 'stage=SIGNED_PACKET_VERIFIED' "$base/logs/qemu-production-gate.log"
expect_rejection qemu-wrong-key 'stage=REJECTED' \
  -machine "nvidia-gsp,fmc=$fmc,bootloader=$boot,trusted-key-sha256=0000000000000000000000000000000000000000000000000000000000000000"
if grep -q 'stage=SIGNED_PACKET_VERIFIED' "$base/logs/qemu-wrong-key.log"; then
  echo 'FAIL rejected key reached SIGNED_PACKET_VERIFIED'
  exit 1
fi
expect_rejection qemu-no-kernel-shortcut 'forbids -kernel' \
  -machine "nvidia-gsp,fmc=$fmc,bootloader=$boot" -kernel "$base/tests/rv64-isa.elf"
expect_rejection qemu-missing-packet 'input required/read failed' -machine nvidia-gsp
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
truncate -s 129M "$scratch/oversized.bin"
expect_rejection qemu-oversized-packet 'input length/type invalid' \
  -machine "nvidia-gsp,fmc=$scratch/oversized.bin,bootloader=$boot"
mkfifo "$scratch/not-a-file"
expect_rejection qemu-special-file 'input length/type invalid' \
  -machine "nvidia-gsp,fmc=$scratch/not-a-file,bootloader=$boot"

# Synthetic 4-byte WFI image ONLY tests ROM mapping and reset-PC plumbing.
# CPU stays paused (-S); it is NOT an NVIDIA ROM or a LibOS boot substitute.
printf '\x73\x00\x50\x10' > "$scratch/mapping-test.bin"
rom_key=$(sha256sum "$scratch/mapping-test.bin" | cut -d' ' -f1)
printf '%s\n' '{"execute":"qmp_capabilities"}' \
  '{"execute":"human-monitor-command","arguments":{"command-line":"info registers"}}' \
  '{"execute":"human-monitor-command","arguments":{"command-line":"xp /1wx 0x1000"}}' \
  '{"execute":"system_reset"}' \
  '{"execute":"human-monitor-command","arguments":{"command-line":"info registers"}}' \
  '{"execute":"query-status"}' '{"execute":"quit"}' | \
  timeout --kill-after=2s 10s "$qemu" -S -accel tcg -display none \
    -serial none -monitor none -nic none -qmp stdio -bios "$scratch/mapping-test.bin" \
    -machine "nvidia-gsp,fmc=$fmc,bootloader=$boot,rom-base=0x1000,rom-sha256=$rom_key" \
    > "$base/logs/qemu-rom-mapping-only.log" 2>&1
grep -q 'stage=SUPPLIED_ROM_READY pc=0x1000' "$base/logs/qemu-rom-mapping-only.log"
[[ $(grep -c ' pc            0000000000001000' "$base/logs/qemu-rom-mapping-only.log") = 2 ]]
grep -q '0x10500073' "$base/logs/qemu-rom-mapping-only.log"
grep -q '"running": false' "$base/logs/qemu-rom-mapping-only.log"
if grep -q '"error"' "$base/logs/qemu-rom-mapping-only.log"; then
  cat "$base/logs/qemu-rom-mapping-only.log"
  exit 1
fi
echo 'PASS synthetic ROM mapping/reset-PC plumbing with CPU paused (NOT GSP boot)'
expect_rejection qemu-wrong-rom-key 'ROM differs from pinned SHA256' \
  -machine "nvidia-gsp,fmc=$fmc,bootloader=$boot,rom-base=0x1000,rom-sha256=0000000000000000000000000000000000000000000000000000000000000000" \
  -bios "$scratch/mapping-test.bin"

"$base/scripts/test-mpu.sh"
"$base/scripts/test-kernel-boot.sh"
"$base/scripts/test-lab-isolation.sh"
"$base/scripts/test-lab-walk.sh"
echo 'PASS packet, CPU/MPU, original-kernel, isolation and lab walk-table regressions; full GSP boot remains incomplete'
