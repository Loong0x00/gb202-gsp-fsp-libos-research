#!/usr/bin/env bash
# Diagnostic state-condition experiment for the t0=4 slow handler.
#
# GLM's newest plan is: write gadget changes refcount, then trigger t0=4
# slow path.  This test shows the actual condition on the slow handler
# 0x930008CC:
#   state=1, ref=0 -> handler increments ref to 1 and SKIPS 0x93005B26;
#                     no dtor.
#   state=0, ref=0 -> handler increments ref to 1, calls 0x93005B26,
#                     ref -> 0, S-mode dtor 0x93008130.
#
# The refcount/state writes are diagnostic; the handler is called directly.
# It does NOT show that the normal U-mode t0=4 fast path reaches this
# handler: the fast path intercepts state=0 and only sets state=1.
set -euo pipefail
ulimit -c 0
base=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
"$base/scripts/prepare-kernel-fixture.sh"
fixture="$base/firmware/kernel-610.57.04"
qemu="$base/build/qemu-system-riscv64"
fmc="$base/firmware/610.57.04/nvidia/gb202/gsp/fmc-610.57.04.bin"
boot="$base/firmware/610.57.04/nvidia/gb202/gsp/bootloader-610.57.04.bin"
scratch=$(mktemp -d /tmp/gsp-lab-statecond-XXXXXX)
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
  printf "LAB_STATECOND_OBJ slot=%#lx obj=%#lx meta=%#lx ref=%#lx state=%#lx\\n", \$slot, \$obj, *(unsigned long*)(\$t1+(\$slot+1)*16+16), *(unsigned long*)(\$obj-8), *(unsigned int*)(\$obj+120)
  set *(unsigned long*)(\$obj-8) = 0
  set *(unsigned int*)(\$obj+120) = 1
  printf "LAB_STATECOND_SET state=1 ref=0\\n"
  set \$phase = 2
  set \$a0 = \$slot
  set \$sp = \$scratch
  set \$ra = 0xffffffff93004412
  set \$pc = 0xffffffff930008cc
  continue
end
if \$phase == 2
  printf "LAB_STATECOND_STATE1_RET a0=%#lx ref=%#lx state=%#lx\\n", \$a0, *(unsigned long*)(\$obj-8), *(unsigned int*)(\$obj+120)
  if \$a0 != 0 || *(unsigned long*)(\$obj-8) != 1 || *(unsigned int*)(\$obj+120) != 1
    printf "LAB_STATECOND_STATE1_BAD\\n"
    quit 1
  end
  set *(unsigned long*)(\$obj-8) = 0
  set *(unsigned int*)(\$obj+120) = 0
  printf "LAB_STATECOND_SET state=0 ref=0\\n"
  enable 3 4 5
  set \$phase = 3
  set \$a0 = \$slot
  set \$sp = \$scratch
  set \$ra = 0xffffffff93004412
  set \$pc = 0xffffffff930008cc
  continue
end
if \$phase == 3
  printf "LAB_STATECOND_STATE0_RET a0=%#lx ref=%#lx state=%#lx\\n", \$a0, *(unsigned long*)(\$obj-8), *(unsigned int*)(\$obj+120)
  set \$phase = 4
  monitor stop
  disconnect
  quit 0
end
continue
end
commands 3
silent
printf "LAB_STATECOND_REF_ZERO obj=%#lx ref=%#lx\\n", \$s1, *(unsigned long*)(\$s1-8)
if \$s1 != \$obj || *(unsigned long*)(\$s1-8) != 0
  printf "LAB_STATECOND_REF_BAD\\n"
  quit 1
end
continue
end
commands 4
silent
printf "LAB_STATECOND_DTOR_CALL dtor=%#lx priv=%d obj=%#lx\\n", \$a5, \$priv, \$s1
if \$a5 != 0xffffffff93008130 || \$priv != 1
  printf "LAB_STATECOND_DTOR_BAD\\n"
  quit 1
end
continue
end
commands 5
silent
printf "LAB_STATECOND_DTOR_ENTRY pc=%#lx priv=%d obj=%#lx\\n", \$pc, \$priv, \$a0
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
  > "$base/logs/lab-statecond.qemu.log" 2>&1) &
pid=$!
for ((i = 0; i < 200; i++)); do
  [[ -S "$scratch/gdb.sock" ]] && break
  kill -0 "$pid"
  sleep 0.05
done
rc=0
timeout --kill-after=2s 65s riscv64-linux-gnu-gdb -q -nx -batch \
  -x "$scratch/probe.gdb" > "$base/logs/lab-statecond.gdb.log" 2>&1 || rc=$?
if grep -q 'LAB_STATECOND_STATE1_BAD\|LAB_STATECOND_REF_BAD\|LAB_STATECOND_DTOR_BAD' \
    "$base/logs/lab-statecond.gdb.log"; then
  cat "$base/logs/lab-statecond.gdb.log"
  echo 'FAIL state-condition experiment'
  exit 1
fi
if ! grep -q 'LAB_STATECOND_DTOR_ENTRY' "$base/logs/lab-statecond.gdb.log"; then
  cat "$base/logs/lab-statecond.gdb.log"
  echo "FAIL state-condition dtor not reached (gdb exit=$rc)"
  tail -20 "$base/logs/lab-statecond.qemu.log"
  exit 1
fi
grep -E 'LAB_STATECOND_OBJ|LAB_STATECOND_SET|LAB_STATECOND_STATE1_RET|LAB_STATECOND_REF_ZERO|LAB_STATECOND_DTOR_CALL|LAB_STATECOND_DTOR_ENTRY' \
  "$base/logs/lab-statecond.gdb.log"
echo 'PASS slow handler condition: state=1/ref=0 skips dtor; state=0/ref=0 reaches S-mode dtor'
echo 'NOTE: normal U-mode t0=4 fast path intercepts state=0 and does NOT call this handler; a direct slow-handler invocation is required.'
