#!/usr/bin/env bash
# Diagnostic t0=17 handler experiment.
#
# GLM claimed t0=17 passes the user a0 directly to 0x93005B26.  The real
# handler 0x93001AE0 saves user a0 in s2, allocates a NEW object (s1),
# registers it, stores the user a0 at newobj+40, and calls
# 0x93005B26(s1) -- the new object, not the user input.
#
# The handler also requires a1 = slot of [0xffffffffa301a1c8] (slot 12 in
# this profile) and a successful service call 0x93008C26.  The service
# returns 2 in this lab context, so this diagnostic forces its result to 0
# to reach the allocation path.  This is NOT a natural U-mode call.
set -euo pipefail
ulimit -c 0
base=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
"$base/scripts/prepare-kernel-fixture.sh"
fixture="$base/firmware/kernel-610.57.04"
qemu="$base/build/qemu-system-riscv64"
fmc="$base/firmware/610.57.04/nvidia/gb202/gsp/fmc-610.57.04.bin"
boot="$base/firmware/610.57.04/nvidia/gb202/gsp/bootloader-610.57.04.bin"
scratch=$(mktemp -d /tmp/gsp-lab-t017-XXXXXX)
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
set \$newobj = 0
hbreak *0xffffffff93001ec6
hbreak *0xffffffff93004412
hbreak *0xffffffff93001b18
hbreak *0xffffffff93001b42
hbreak *0xffffffff93001b62
hbreak *0xffffffff93001b64
hbreak *0xffffffff93005b40
hbreak *0xffffffff93005b5e
disable 3 4 5 6 7 8
commands 1
silent
set \$n = \$n + 1
if \$n == 3
  set \$global = *(unsigned long*)0xffffffffa3008010
  set \$t1 = *(unsigned long*)(\$global+0x450)
  set \$target = *(unsigned long*)0xffffffffa301a1c8
  printf "LAB_T017_SETUP global=%#lx t1=%#lx target=%#lx t1slot12=%#lx\\n", \$global, \$t1, \$target, *(unsigned long*)(\$t1+13*16+8)
  if *(unsigned long*)(\$t1+13*16+8) != \$target
    printf "LAB_T017_SLOT12_MISMATCH\\n"
    quit 1
  end
  set \$scratch = 0xffffffffa3004000
  enable 3 4 5 6 7 8
  set \$phase = 1
  set \$a0 = 0x41
  set \$a1 = 12
  set \$sp = \$scratch
  set \$ra = 0xffffffff93004412
  set \$pc = 0xffffffff93001ae0
  continue
end
continue
end
commands 2
silent
if \$phase == 1
  printf "LAB_T017_RET a0=%#lx newobj=%#lx newref=%#lx userbyte=%#lx\\n", \$a0, \$newobj, *(unsigned long*)(\$newobj-8), *(unsigned char*)(\$newobj+40)
  if \$a0 != 0 || *(unsigned long*)(\$newobj-8) != 1 || *(unsigned char*)(\$newobj+40) != 0x41
    printf "LAB_T017_RET_BAD\\n"
    quit 1
  end
  set \$phase = 2
  monitor stop
  disconnect
  quit 0
end
continue
end
commands 3
silent
printf "LAB_T017_SERVICE_RET a0=%#lx s2(user)=%#lx (forcing success)\\n", \$a0, \$s2
set \$a0 = 0
set *(unsigned char*)(\$sp+16) = 0
continue
end
commands 4
silent
set \$newobj = \$s1
printf "LAB_T017_ALLOC s1(new)=%#lx s2(user)=%#lx newref=%#lx\\n", \$s1, \$s2, *(unsigned long*)(\$s1-8)
if \$s1 == \$s2 || \$s2 != 0x41 || *(unsigned long*)(\$s1-8) != 1
  printf "LAB_T017_ALLOC_BAD\\n"
  quit 1
end
continue
end
commands 5
silent
printf "LAB_T017_PRE_RELEASE s1(new)=%#lx s2(user)=%#lx newref=%#lx\\n", \$s1, \$s2, *(unsigned long*)(\$s1-8)
if \$s1 != \$newobj || \$s2 != 0x41 || *(unsigned long*)(\$s1-8) != 2
  printf "LAB_T017_PRE_RELEASE_BAD\\n"
  quit 1
end
continue
end
commands 6
silent
printf "LAB_T017_CALL_05B26 a0=%#lx s1(new)=%#lx s2(user)=%#lx\\n", \$a0, \$s1, \$s2
if \$a0 != \$newobj || \$a0 == \$s2
  printf "LAB_T017_CALL_BAD\\n"
  quit 1
end
continue
end
commands 7
silent
printf "LAB_T017_UNEXPECTED_ZERO s1=%#lx ref=%#lx\\n", \$s1, *(unsigned long*)(\$s1-8)
quit 1
end
commands 8
silent
printf "LAB_T017_UNEXPECTED_DTOR dtor=%#lx obj=%#lx\\n", \$a5, \$s1
quit 1
end
continue
EOF

(ulimit -f 65536; exec timeout --kill-after=5s 70s "$qemu" \
  -M "nvidia-gsp-lab,bootstrap=$base/firmware/gsp-bootstrap-610.57.04.bin,libos=$fixture/kernel-load-segments.elf,image=$base/firmware/gsp-fwimage-610.57.04.bin,fmc=$fmc,bootloader=$boot" \
  -m 32M -display none -serial none -monitor none -nic none -S \
  -gdb "unix:$scratch/gdb.sock,server=on,wait=off" \
  > "$base/logs/lab-t017.qemu.log" 2>&1) &
pid=$!
for ((i = 0; i < 200; i++)); do
  [[ -S "$scratch/gdb.sock" ]] && break
  kill -0 "$pid"
  sleep 0.05
done
rc=0
timeout --kill-after=2s 65s riscv64-linux-gnu-gdb -q -nx -batch \
  -x "$scratch/probe.gdb" > "$base/logs/lab-t017.gdb.log" 2>&1 || rc=$?
if grep -q 'LAB_T017_SLOT12_MISMATCH\|LAB_T017_ALLOC_BAD\|LAB_T017_PRE_RELEASE_BAD\|LAB_T017_CALL_BAD\|LAB_T017_RET_BAD\|LAB_T017_UNEXPECTED_ZERO\|LAB_T017_UNEXPECTED_DTOR' \
    "$base/logs/lab-t017.gdb.log"; then
  cat "$base/logs/lab-t017.gdb.log"
  echo 'FAIL t0=17 diagnostic'
  exit 1
fi
if ! grep -q 'LAB_T017_RET' "$base/logs/lab-t017.gdb.log"; then
  cat "$base/logs/lab-t017.gdb.log"
  echo "FAIL t0=17 checkpoint not reached (gdb exit=$rc)"
  tail -20 "$base/logs/lab-t017.qemu.log"
  exit 1
fi
grep -E 'LAB_T017_SETUP|LAB_T017_SERVICE_RET|LAB_T017_ALLOC|LAB_T017_PRE_RELEASE|LAB_T017_CALL_05B26|LAB_T017_RET' \
  "$base/logs/lab-t017.gdb.log"
echo 'PASS t0=17 handler releases the newly allocated object s1, NOT user a0 s2'
echo 'NOTE: service result was forced to 0 and a1=12 is the target global slot; this is a diagnostic, not a natural U-mode call.'
