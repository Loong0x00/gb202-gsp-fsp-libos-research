#!/usr/bin/env bash
# Diagnostic direct-destroy experiment.
#
# Create a real type-12 object via the t0=23 handler, then call the real
# 0x93005B26 decref path directly.  When the refcount reaches zero, the
# kernel calls the type-10 destructor 0x93008130 in S-mode.  This proves
# the destroy path and the dtor target; it does NOT prove a U-mode user
# can reach 0x93005B26 with a controlled refcount/object.
set -euo pipefail
ulimit -c 0
base=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
"$base/scripts/prepare-kernel-fixture.sh"
fixture="$base/firmware/kernel-610.57.04"
qemu="$base/build/qemu-system-riscv64"
fmc="$base/firmware/610.57.04/nvidia/gb202/gsp/fmc-610.57.04.bin"
boot="$base/firmware/610.57.04/nvidia/gb202/gsp/bootloader-610.57.04.bin"
scratch=$(mktemp -d /tmp/gsp-lab-destroy-XXXXXX)
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
  printf "LAB_DESTROY_SETUP global=%#lx sscratch=%#lx\\n", *(unsigned long*)0xffffffffa3008010, \$sscratch
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
  set \$ref0 = *(unsigned long*)(\$obj-8)
  printf "LAB_DESTROY_CREATE a0=%#lx slot=%#lx obj=%#lx meta=%#lx refcnt=%#lx state=%#lx\\n", \$a0, \$slot, \$obj, \$meta, \$ref0, *(unsigned int*)(\$obj+120)
  if \$a0 != 0 || \$slot == 0 || \$meta != 0x800000000000000c || \$ref0 != 1
    printf "LAB_DESTROY_CREATE_BAD\\n"
    quit 1
  end
  enable 3 4
  set \$phase = 2
  set \$a0 = \$obj
  set \$sp = \$scratch
  set \$ra = 0xffffffff93004412
  set \$pc = 0xffffffff93005b26
  continue
end
continue
end
commands 3
silent
printf "LAB_DESTROY_REF_ZERO obj=%#lx refcnt=%#lx\\n", \$s1, *(unsigned long*)(\$s1-8)
if \$s1 != \$obj || *(unsigned long*)(\$s1-8) != 0
  printf "LAB_DESTROY_REF_BAD\\n"
  quit 1
end
continue
end
commands 4
silent
printf "LAB_DESTROY_DTOR_CALL dtor=%#lx priv=%d pc=%#lx obj=%#lx satp=%#lx\\n", \$a5, \$priv, \$pc, \$s1, \$satp
if \$a5 != 0xffffffff93008130 || \$priv != 1
  printf "LAB_DESTROY_DTOR_BAD\\n"
  quit 1
end
enable 5
continue
end
commands 5
silent
printf "LAB_DESTROY_DTOR_ENTRY pc=%#lx priv=%d obj=%#lx satp=%#lx\\n", \$pc, \$priv, \$a0, \$satp
if \$pc != 0xffffffff93008130 || \$priv != 1
  printf "LAB_DESTROY_DTOR_ENTRY_BAD\\n"
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
  > "$base/logs/lab-destroy.qemu.log" 2>&1) &
pid=$!
for ((i = 0; i < 200; i++)); do
  [[ -S "$scratch/gdb.sock" ]] && break
  kill -0 "$pid"
  sleep 0.05
done
rc=0
timeout --kill-after=2s 65s riscv64-linux-gnu-gdb -q -nx -batch \
  -x "$scratch/probe.gdb" > "$base/logs/lab-destroy.gdb.log" 2>&1 || rc=$?
if grep -q 'LAB_DESTROY_CREATE_BAD\|LAB_DESTROY_REF_BAD\|LAB_DESTROY_DTOR_BAD\|LAB_DESTROY_DTOR_ENTRY_BAD' \
    "$base/logs/lab-destroy.gdb.log"; then
  cat "$base/logs/lab-destroy.gdb.log"
  echo 'FAIL direct-destroy experiment'
  exit 1
fi
if ! grep -q 'LAB_DESTROY_DTOR_ENTRY' "$base/logs/lab-destroy.gdb.log"; then
  cat "$base/logs/lab-destroy.gdb.log"
  echo "FAIL destroy checkpoint not reached (gdb exit=$rc)"
  tail -20 "$base/logs/lab-destroy.qemu.log"
  exit 1
fi
grep -E 'LAB_DESTROY_SETUP|LAB_DESTROY_CREATE|LAB_DESTROY_REF_ZERO|LAB_DESTROY_DTOR_CALL|LAB_DESTROY_DTOR_ENTRY' \
  "$base/logs/lab-destroy.gdb.log"
echo 'PASS direct 0x93005B26 on a type-12 object: ref 1->0, dtor 0x93008130 entered with priv=1'
echo 'NOTE: this is a diagnostic direct call. It proves the decref->TYPECALC->dtor path, NOT that a U-mode syscall can reach it with a controlled refcount/object.'
