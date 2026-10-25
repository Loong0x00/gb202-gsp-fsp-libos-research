#!/usr/bin/env bash
# Diagnostic t0=4 fast-path experiment.
#
# Create a real type-12 object (state=0), then enter the real t0=4 special
# branch at 0x930042f8 with t0=4, stval=0, a0=slot and sscratch=global.
# Stop after the state store at 0x93004382 and verify:
#   - state changes 0 -> 1
#   - refcount stays 1
#   - handler 0x930008cc is NOT called
#   - 0x93005B26 is NOT called
# This is a controlled fast-path entry, not a U-mode trap.
set -euo pipefail
ulimit -c 0
base=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
"$base/scripts/prepare-kernel-fixture.sh"
fixture="$base/firmware/kernel-610.57.04"
qemu="$base/build/qemu-system-riscv64"
fmc="$base/firmware/610.57.04/nvidia/gb202/gsp/fmc-610.57.04.bin"
boot="$base/firmware/610.57.04/nvidia/gb202/gsp/bootloader-610.57.04.bin"
scratch=$(mktemp -d /tmp/gsp-lab-fastpath-XXXXXX)
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

cat > "$scratch/probe.gdb" <<EOF
set pagination off
set confirm off
set remotetimeout 3
target remote $scratch/gdb.sock
set \$n = 0
set \$phase = 0
hbreak *0xffffffff93001ec6
hbreak *0xffffffff93004412
hbreak *0xffffffff93004382
hbreak *0xffffffff930008cc
hbreak *0xffffffff93005b40
disable 3 4 5
commands 1
silent
set \$n = \$n + 1
if \$n == 3
  printf "LAB_FASTPATH_SETUP global=%#lx sscratch=%#lx\\n", *(unsigned long*)0xffffffffa3008010, \$sscratch
  set \$scratch = 0xffffffffa3007000
  set \$sp = \$scratch
  set \$ra = 0xffffffff93004412
  set \$pc = 0xffffffff93006300
  set \$phase = 1
  continue
end
continue
end
commands 2
silent
if \$phase == 1
  set \$slot = *(unsigned int*)(\$sp-36)
  set \$global = *(unsigned long*)0xffffffffa3008010
  set \$t1 = *(unsigned long*)(\$global+0x450)
  set \$obj = *(unsigned long*)(\$t1 + (\$slot+1)*16 + 8)
  set \$meta = *(unsigned long*)(\$t1 + (\$slot+1)*16 + 16)
  printf "LAB_FASTPATH_CREATE slot=%#lx obj=%#lx meta=%#lx ref=%#lx state=%#lx\\n", \$slot, \$obj, \$meta, *(unsigned long*)(\$obj-8), *(unsigned int*)(\$obj+120)
  if \$meta != 0x800000000000000c || *(unsigned long*)(\$obj-8) != 1 || *(unsigned int*)(\$obj+120) != 0
    printf "LAB_FASTPATH_CREATE_BAD\\n"
    quit 1
  end
  enable 3 4 5
  set \$phase = 2
  set \$t0 = 4
  set \$a0 = \$slot
  set \$stval = 0
  set \$sscratch = \$global
  set \$sepc = 0xffffffff93004412
  set \$sstatus = \$sstatus | 0x100
  set \$sp = \$scratch
  set \$pc = 0xffffffff930042f8
  continue
end
if \$phase == 2
  printf "LAB_FASTPATH_RETURN_MARKER\\n"
  monitor stop
  disconnect
  quit 0
end
continue
end
commands 3
silent
printf "LAB_FASTPATH_STATE pc=%#lx a0=%#lx ref=%#lx state=%#lx meta=%#lx\\n", \$pc, \$a0, *(unsigned long*)(\$obj-8), *(unsigned int*)(\$obj+120), \$meta
if \$a0 != \$slot || *(unsigned long*)(\$obj-8) != 1 || *(unsigned int*)(\$obj+120) != 1
  printf "LAB_FASTPATH_STATE_BAD\\n"
  quit 1
end
set \$phase = 3
monitor stop
disconnect
quit 0
end
commands 4
silent
printf "LAB_FASTPATH_HANDLER4_UNEXPECTED a0=%#lx\\n", \$a0
quit 1
end
commands 5
silent
printf "LAB_FASTPATH_DECREF_UNEXPECTED obj=%#lx\\n", \$s1
quit 1
end
continue
EOF

(ulimit -f 65536; exec timeout --kill-after=5s 70s "$qemu" \
  -M "nvidia-gsp-lab,bootstrap=$base/firmware/gsp-bootstrap-610.57.04.bin,libos=$fixture/kernel-load-segments.elf,image=$base/firmware/gsp-fwimage-610.57.04.bin,fmc=$fmc,bootloader=$boot" \
  -m 32M -display none -serial none -monitor none -nic none -S \
  -gdb "unix:$scratch/gdb.sock,server=on,wait=off" \
  > "$base/logs/lab-fastpath.qemu.log" 2>&1) &
pid=$!
for ((i = 0; i < 200; i++)); do
  [[ -S "$scratch/gdb.sock" ]] && break
  kill -0 "$pid"
  sleep 0.05
done
rc=0
timeout --kill-after=2s 65s riscv64-linux-gnu-gdb -q -nx -batch \
  -x "$scratch/probe.gdb" > "$base/logs/lab-fastpath.gdb.log" 2>&1 || rc=$?
if grep -q 'LAB_FASTPATH_CREATE_BAD\|LAB_FASTPATH_STATE_BAD\|LAB_FASTPATH_HANDLER4_UNEXPECTED\|LAB_FASTPATH_DECREF_UNEXPECTED' \
    "$base/logs/lab-fastpath.gdb.log"; then
  cat "$base/logs/lab-fastpath.gdb.log"
  echo 'FAIL t0=4 fast-path experiment'
  exit 1
fi
if ! grep -q 'LAB_FASTPATH_STATE' "$base/logs/lab-fastpath.gdb.log"; then
  cat "$base/logs/lab-fastpath.gdb.log"
  echo "FAIL fast-path checkpoint not reached (gdb exit=$rc)"
  tail -20 "$base/logs/lab-fastpath.qemu.log"
  exit 1
fi
grep -E 'LAB_FASTPATH_SETUP|LAB_FASTPATH_CREATE|LAB_FASTPATH_STATE' \
  "$base/logs/lab-fastpath.gdb.log"
echo 'PASS t0=4 fast path: state 0->1, refcount 1, no 0x93005B26, no handler 0x930008cc'
echo 'NOTE: this is a controlled fast-path entry, not a real U-mode trap.'
