#!/usr/bin/env bash
# Diagnostic handler-level create -> release -> release experiment.
#
# This is NOT a normal syscall-dispatch boot path.  At the third kernel init
# entry it directly enters the real t0=23 and t0=4 handler bodies with a
# scratch stack, then checks the real table/object state.  It proves the
# handler contract, not that a user syscall or a completed GSP-RM lifecycle
# occurred.
set -euo pipefail
ulimit -c 0
base=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
"$base/scripts/prepare-kernel-fixture.sh"
fixture="$base/firmware/kernel-610.57.04"
qemu="$base/build/qemu-system-riscv64"
fmc="$base/firmware/610.57.04/nvidia/gb202/gsp/fmc-610.57.04.bin"
boot="$base/firmware/610.57.04/nvidia/gb202/gsp/bootloader-610.57.04.bin"
scratch=$(mktemp -d /tmp/gsp-lab-release-XXXXXX)
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
commands 1
silent
set \$n = \$n + 1
if \$n == 3
  printf "LAB_RELEASE_SETUP global=%#lx sscratch=%#lx\n", *(unsigned long*)0xffffffffa3008010, \$sscratch
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
  set \$state0 = *(unsigned int*)(\$obj+120)
  printf "LAB_RELEASE_CREATE a0=%#lx slot=%#lx obj=%#lx meta=%#lx refcnt=%#lx state=%#lx\n", \$a0, \$slot, \$obj, \$meta, \$ref0, \$state0
  if \$a0 != 0 || \$slot == 0 || \$meta != 0x800000000000000c
    printf "LAB_RELEASE_CREATE_BAD\n"
    quit 1
  end
  set \$phase = 2
  set \$a0 = \$slot
  set \$sp = \$scratch
  set \$ra = 0xffffffff93004412
  set \$pc = 0xffffffff930008cc
  continue
end
if \$phase == 2
  set \$meta1 = *(unsigned long*)(\$t1 + (\$slot+1)*16 + 16)
  set \$ref1 = *(unsigned long*)(\$obj-8)
  set \$state1 = *(unsigned int*)(\$obj+120)
  printf "LAB_RELEASE_RESULT a0=%#lx slot=%#lx obj=%#lx meta=%#lx refcnt=%#lx state=%#lx header=%#lx\n", \$a0, \$slot, \$obj, \$meta1, \$ref1, \$state1, *(unsigned long*)\$t1
  if \$a0 != 0 || \$meta1 != 0x800000000000000c
    printf "LAB_RELEASE_BAD\n"
    quit 1
  end
  if \$state0 != 0 || \$state1 != 1
    printf "LAB_RELEASE_STATE_UNEXPECTED\n"
    quit 1
  end
  set \$phase = 3
  set \$a0 = \$slot
  set \$sp = \$scratch
  set \$ra = 0xffffffff93004412
  set \$pc = 0xffffffff930008cc
  continue
end
if \$phase == 3
  set \$meta2 = *(unsigned long*)(\$t1 + (\$slot+1)*16 + 16)
  set \$ref2 = *(unsigned long*)(\$obj-8)
  set \$state2 = *(unsigned int*)(\$obj+120)
  printf "LAB_RELEASE_SECOND a0=%#lx slot=%#lx obj=%#lx meta=%#lx refcnt=%#lx state=%#lx header=%#lx\n", \$a0, \$slot, \$obj, \$meta2, \$ref2, \$state2, *(unsigned long*)\$t1
  if \$a0 != 0 || \$meta2 != 0x800000000000000c || \$state2 != 1
    printf "LAB_RELEASE_SECOND_BAD\n"
    quit 1
  end
  if \$ref2 <= \$ref1
    printf "LAB_RELEASE_SECOND_REFCOUNT_UNEXPECTED\n"
    quit 1
  end
  set \$phase = 4
  monitor stop
  disconnect
  quit 0
end
continue
end
continue
EOF

(ulimit -f 65536; exec timeout --kill-after=5s 70s "$qemu" \
  -M "nvidia-gsp-lab,bootstrap=$base/firmware/gsp-bootstrap-610.57.04.bin,libos=$fixture/kernel-load-segments.elf,image=$base/firmware/gsp-fwimage-610.57.04.bin,fmc=$fmc,bootloader=$boot" \
  -m 32M -display none -serial none -monitor none -nic none -S \
  -gdb "unix:$scratch/gdb.sock,server=on,wait=off" \
  > "$base/logs/lab-release.qemu.log" 2>&1) &
pid=$!
for ((i = 0; i < 200; i++)); do
  [[ -S "$scratch/gdb.sock" ]] && break
  kill -0 "$pid"
  sleep 0.05
done
rc=0
timeout --kill-after=2s 65s riscv64-linux-gnu-gdb -q -nx -batch \
  -x "$scratch/probe.gdb" > "$base/logs/lab-release.gdb.log" 2>&1 || rc=$?
if grep -q 'LAB_RELEASE_CREATE_BAD\|LAB_RELEASE_BAD\|LAB_RELEASE_STATE_UNEXPECTED\|LAB_RELEASE_SECOND_BAD\|LAB_RELEASE_SECOND_REFCOUNT_UNEXPECTED' \
    "$base/logs/lab-release.gdb.log"; then
  cat "$base/logs/lab-release.gdb.log"
  echo 'FAIL handler-level create/release experiment'
  exit 1
fi
if ! grep -q 'LAB_RELEASE_SECOND' "$base/logs/lab-release.gdb.log"; then
  cat "$base/logs/lab-release.gdb.log"
  echo "FAIL release checkpoint not reached (gdb exit=$rc)"
  tail -20 "$base/logs/lab-release.qemu.log"
  exit 1
fi
grep -E 'LAB_RELEASE_SETUP|LAB_RELEASE_CREATE|LAB_RELEASE_RESULT|LAB_RELEASE_SECOND' \
  "$base/logs/lab-release.gdb.log"
echo 'PASS handler-level t0=23 create -> t0=4 release path (direct handler bodies)'
echo 'NOTE: first release marks state=1; second release increments refcount while keeping the type-12 table entry/meta. This is NOT object destruction or a completed user syscall lifecycle.'
