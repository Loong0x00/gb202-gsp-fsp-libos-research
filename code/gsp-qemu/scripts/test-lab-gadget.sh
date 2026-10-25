#!/usr/bin/env bash
# Diagnostic gadget experiment.
#
# Create a real type-12 object, verify the t0=10 handler rejects it
# (meta bit1 clear), then enter the real instruction sequence at
# 0x930035d2 (mv a0,a1; jal 0x93005B26) with a1 = the object and s0 = 0.
# The gadget drives refcount 1 -> 0 and enters the type-10 S-mode dtor.
#
# This is a controlled PC/a1 test, NOT a U-mode reachability proof.
set -euo pipefail
ulimit -c 0
base=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
"$base/scripts/prepare-kernel-fixture.sh"
fixture="$base/firmware/kernel-610.57.04"
qemu="$base/build/qemu-system-riscv64"
fmc="$base/firmware/610.57.04/nvidia/gb202/gsp/fmc-610.57.04.bin"
boot="$base/firmware/610.57.04/nvidia/gb202/gsp/bootloader-610.57.04.bin"
scratch=$(mktemp -d /tmp/gsp-lab-gadget-XXXXXX)
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
hbreak *0xffffffff93005b40
hbreak *0xffffffff93005b5e
hbreak *0xffffffff93008130
disable 3 4 5
commands 1
silent
set \$n = \$n + 1
if \$n == 3
  printf "LAB_GADGET_SETUP global=%#lx sscratch=%#lx\\n", *(unsigned long*)0xffffffffa3008010, \$sscratch
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
  printf "LAB_GADGET_CREATE a0=%#lx slot=%#lx obj=%#lx meta=%#lx ref=%#lx\\n", \$a0, \$slot, \$obj, \$meta, *(unsigned long*)(\$obj-8)
  if \$a0 != 0 || \$slot == 0 || \$meta != 0x800000000000000c
    printf "LAB_GADGET_CREATE_BAD\\n"
    quit 1
  end
  set \$phase = 2
  set \$a0 = \$slot
  set \$sp = \$scratch
  set \$ra = 0xffffffff93004412
  set \$pc = 0xffffffff93000bde
  continue
end
if \$phase == 2
  printf "LAB_GADGET_T0_10 a0=%#lx slot=%#lx meta=%#lx\\n", \$a0, \$slot, \$meta
  if \$a0 != 2
    printf "LAB_GADGET_T0_10_UNEXPECTED\\n"
    quit 1
  end
  set \$phase = 3
  enable 3 4
  set \$a1 = \$obj
  set \$s0 = 0
  set \$sp = \$scratch
  set \$ra = 0xffffffff93004412
  set \$pc = 0xffffffff930035d2
  continue
end
if \$phase == 3
  printf "LAB_GADGET_RET a0=%#lx obj=%#lx ref=%#lx\\n", \$a0, \$obj, *(unsigned long*)(\$obj-8)
  set \$phase = 4
  monitor stop
  disconnect
  quit 0
end
continue
end
commands 3
silent
printf "LAB_GADGET_REF_ZERO obj=%#lx ref=%#lx\\n", \$s1, *(unsigned long*)(\$s1-8)
if \$s1 != \$obj || *(unsigned long*)(\$s1-8) != 0
  printf "LAB_GADGET_REF_BAD\\n"
  quit 1
end
continue
end
commands 4
silent
printf "LAB_GADGET_DTOR_CALL dtor=%#lx priv=%d pc=%#lx obj=%#lx satp=%#lx\\n", \$a5, \$priv, \$pc, \$s1, \$satp
if \$a5 != 0xffffffff93008130 || \$priv != 1
  printf "LAB_GADGET_DTOR_BAD\\n"
  quit 1
end
enable 5
continue
end
commands 5
silent
printf "LAB_GADGET_DTOR_ENTRY pc=%#lx priv=%d obj=%#lx\\n", \$pc, \$priv, \$a0
if \$pc != 0xffffffff93008130 || \$priv != 1
  printf "LAB_GADGET_DTOR_ENTRY_BAD\\n"
  quit 1
end
monitor stop
disconnect
quit 0
end
continue
EOF

(ulimit -f 65536; exec timeout --kill-after=5s 70s "$qemu" \
  -M "nvidia-gsp-lab,bootstrap=$base/firmware/gsp-bootstrap-610.57.04.bin,libos=$fixture/kernel-load-segments.elf,image=$base/firmware/gsp-fwimage-610.57.04.bin,fmc=$fmc,bootloader=$boot" \
  -m 32M -display none -serial none -monitor none -nic none -S \
  -gdb "unix:$scratch/gdb.sock,server=on,wait=off" \
  > "$base/logs/lab-gadget.qemu.log" 2>&1) &
pid=$!
for ((i = 0; i < 200; i++)); do
  [[ -S "$scratch/gdb.sock" ]] && break
  kill -0 "$pid"
  sleep 0.05
done
rc=0
timeout --kill-after=2s 65s riscv64-linux-gnu-gdb -q -nx -batch \
  -x "$scratch/probe.gdb" > "$base/logs/lab-gadget.gdb.log" 2>&1 || rc=$?
if grep -q 'LAB_GADGET_CREATE_BAD\|LAB_GADGET_T0_10_UNEXPECTED\|LAB_GADGET_REF_BAD\|LAB_GADGET_DTOR_BAD\|LAB_GADGET_DTOR_ENTRY_BAD' \
    "$base/logs/lab-gadget.gdb.log"; then
  cat "$base/logs/lab-gadget.gdb.log"
  echo 'FAIL gadget experiment'
  exit 1
fi
if ! grep -q 'LAB_GADGET_DTOR_ENTRY' "$base/logs/lab-gadget.gdb.log"; then
  cat "$base/logs/lab-gadget.gdb.log"
  echo "FAIL gadget checkpoint not reached (gdb exit=$rc)"
  tail -20 "$base/logs/lab-gadget.qemu.log"
  exit 1
fi
grep -E 'LAB_GADGET_SETUP|LAB_GADGET_CREATE|LAB_GADGET_T0_10|LAB_GADGET_REF_ZERO|LAB_GADGET_DTOR_CALL|LAB_GADGET_DTOR_ENTRY' \
  "$base/logs/lab-gadget.gdb.log"
echo 'PASS controlled 0x930035d2 gadget: mv a0,a1 -> 0x93005B26 -> ref 0 -> S-mode dtor'
echo 'NOTE: PC/a1 are set by the diagnostic. U-mode reachability of the gadget and control of a1 are NOT proven.'
