#!/usr/bin/env bash
set -euo pipefail
ulimit -c 0
base=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
qemu="$base/build/qemu-system-riscv64"
assemble() {
  local name=$1; shift
  riscv64-linux-gnu-as -march=rv64imac_zicsr -mabi=lp64 "$@" \
    "$base/tests/nv-mpu.S" -o "$base/tests/$name.o"
  riscv64-linux-gnu-ld --no-relax -T "$base/tests/nv-mpu.ld" \
    "$base/tests/$name.o" -o "$base/tests/$name.elf"
}
run_case() {
  local name=$1
  (ulimit -f 16384; exec timeout --kill-after=2s 15s "$qemu" \
    -M virt -cpu nvidia-gsp -accel tcg -m 256M -display none \
    -serial none -monitor none -nic none -bios none \
    -device "loader,file=$base/tests/$name.elf,cpu-num=0" \
    -d int,mmu,unimp -D "$base/logs/$name.trace.log") \
    > "$base/logs/$name.log" 2>&1
}
for cpu in rv64 nvidia-gsp; do
  extra=()
  [[ $cpu = nvidia-gsp ]] && extra=(--defsym NV_ENABLED=1)
  riscv64-linux-gnu-as -march=rv64imac_zicsr -mabi=lp64 "${extra[@]}" \
    "$base/tests/nv-feature-gate.S" -o "$base/tests/nv-feature-$cpu.o"
  riscv64-linux-gnu-ld --no-relax -Ttext=0x80000000 --entry=_start \
    "$base/tests/nv-feature-$cpu.o" -o "$base/tests/nv-feature-$cpu.elf"
  timeout --kill-after=2s 10s "$qemu" -M virt -cpu "$cpu" -accel tcg -m 128M \
    -display none -serial none -monitor none -nic none -bios none \
    -device "loader,file=$base/tests/nv-feature-$cpu.elf,cpu-num=0" \
    > "$base/logs/nv-feature-$cpu.log" 2>&1
  echo "PASS reserved-mode / proprietary-CSR feature gating for $cpu"
done
assemble nv-mpu
run_case nv-mpu
echo 'PASS 17 MPU S/U execution, permission, CSR, invalidation and sub-page cases'
for mode in 1 2; do
  name="nv-mpu-overlap-$mode"
  assemble "$name" --defsym "OVERLAP_TEST=$mode"
  rc=0; run_case "$name" || rc=$?
  [[ $rc = 1 ]] || { echo "FAIL $name unexpected exit=$rc"; exit 1; }
  if [[ $mode = 1 ]]; then pattern='unresolved overlapping MPU priority';
  else pattern='access crosses unresolved MPU boundary'; fi
  grep -q "$pattern" "$base/logs/$name.log"
  echo "PASS $name refuses unresolved priority after TLB warmup / crossing"
done
