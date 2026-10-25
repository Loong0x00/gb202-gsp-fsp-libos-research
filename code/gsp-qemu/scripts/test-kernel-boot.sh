#!/usr/bin/env bash
# Executes original LibOS boot bytes as a CPU/MPU regression, not full GSP boot.
set -euo pipefail
ulimit -c 0
base=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
"$base/scripts/prepare-kernel-fixture.sh"
fixture="$base/firmware/kernel-610.57.04"
qemu="$base/build/qemu-system-riscv64"
scratch=$(mktemp -d /tmp/gsp-probe-XXXXXX)
pid=
cleanup() {
  if [[ -n $pid ]]; then
    if jobs -pr | grep -qx -- "$pid"; then
      kill "$pid" 2>/dev/null || true
    fi
    wait "$pid" 2>/dev/null || true
  fi
  rm -rf -- "$scratch"
}
trap cleanup EXIT
riscv64-linux-gnu-as -march=rv64imac_zicsr -mabi=lp64 \
  "$base/tests/kernel-boot-driver.S" -o "$base/tests/kernel-boot-driver.o"
riscv64-linux-gnu-ld -Ttext=0x80000000 --entry=_start --no-relax \
  "$base/tests/kernel-boot-driver.o" -o "$base/tests/kernel-boot-driver.elf"
trap_pc=$(riscv64-linux-gnu-nm "$base/tests/kernel-boot-driver.elf" | awk '$3=="m_trap" {print "0x"$1}')
cat > "$scratch/probe.gdb" <<EOF
set pagination off
set confirm off
set remotetimeout 3
target remote $scratch/gdb.sock
hbreak *0xffffffff93001ec6
hbreak *$trap_pc
continue
printf "ORIGINAL_BOOT_REACHED_INIT pc=%#lx sp=%#lx satp=%#lx a0=%#lx a7=%#lx\\n", \$pc, \$sp, \$satp, \$a0, \$a7
if \$pc != 0xffffffff93001ec6
  quit 1
end
if \$sp != 0xffffffffa3008000
  quit 1
end
if \$satp != 0xf000000000000000
  quit 1
end
if \$a0 != 0x30
  quit 1
end
delete 1
continue
printf "NEXT_UNMODELED_INPUT mcause=%#lx mepc=%#lx mtval=%#lx\\n", \$mcause, \$mepc, \$mtval
if \$mcause != 13
  quit 1
end
if \$mtval != 0x0c00000000000200
  quit 1
end
monitor stop
disconnect
quit
EOF
cp "$scratch/probe.gdb" "$base/logs/kernel-boot-probe.gdb"
(ulimit -f 16384; exec "$qemu" -M virt -cpu nvidia-gsp -accel tcg -m 1G \
  -display none -serial none -monitor none -nic none -bios none -S \
  -gdb "unix:$scratch/gdb.sock,server=on,wait=off" \
  -device "loader,file=$base/tests/kernel-boot-driver.elf,cpu-num=0" \
  -device "loader,file=$fixture/code.bin,addr=0x92fff000,force-raw=on" \
  -device "loader,file=$fixture/data.bin,addr=0xa3000000,force-raw=on" \
  -d in_asm,int,mmu,unimp -D "$base/logs/kernel-boot.trace.log") \
  > "$base/logs/kernel-boot.qemu.log" 2>&1 &
pid=$!
for ((i=0;i<100;i++)); do
  [[ -S "$scratch/gdb.sock" ]] && break
  kill -0 "$pid"
  sleep 0.02
done
timeout --kill-after=2s 25s riscv64-linux-gnu-gdb -q -nx -batch \
  -x "$scratch/probe.gdb" > "$base/logs/kernel-boot.gdb.log" 2>&1
grep -q 'ORIGINAL_BOOT_REACHED_INIT' "$base/logs/kernel-boot.gdb.log"
grep -q 'NEXT_UNMODELED_INPUT' "$base/logs/kernel-boot.gdb.log"
echo 'PASS original production LibOS boot -> init, without NOP/branch patches'
grep -E 'ORIGINAL_BOOT_REACHED_INIT|NEXT_UNMODELED_INPUT' "$base/logs/kernel-boot.gdb.log"
echo 'This is a subsystem test, NOT a completed BootROM/FMC/GSP boot chain.'
