#!/usr/bin/env bash
# Original production LibOS reaches the walk-table publication site.
# Capture both the initial free-list and the populated table: the first
# sd s7,0x450(s0) is too early, the second publication follows population.
set -euo pipefail
ulimit -c 0
base=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
"$base/scripts/prepare-kernel-fixture.sh"
fixture="$base/firmware/kernel-610.57.04"
qemu="$base/build/qemu-system-riscv64"
fmc="$base/firmware/610.57.04/nvidia/gb202/gsp/fmc-610.57.04.bin"
boot="$base/firmware/610.57.04/nvidia/gb202/gsp/bootloader-610.57.04.bin"
scratch=$(mktemp -d /tmp/gsp-lab-walk-XXXXXX)
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
set \$hit = 0
hbreak *0xffffffff93007324
hbreak *0xffffffff93007328
commands 1
silent
set \$hit = \$hit + 1
printf "LAB_WALK_WRITE_BEFORE hit=%d global=%#lx table=%#lx\n", \$hit, \$s0, \$s7
if \$hit == 1
  set \$walkglob = \$s0
  set \$walktab = \$s7
end
continue
end
commands 2
silent
if \$hit == 1
  printf "LAB_WALK_INITIAL global=%#lx table=%#lx stored=%#lx\n", \$walkglob, \$walktab, *(unsigned long*)(\$walkglob+0x450)
  if *(unsigned long*)(\$walkglob+0x450) != \$walktab
    printf "LAB_WALK_STORE_MISMATCH\n"
    quit 1
  end
  dump binary memory $scratch/walk_initial.bin \$walktab \$walktab+0x1000
end
if \$hit == 2
  printf "LAB_WALK_POPULATED global=%#lx table=%#lx\n", \$walkglob, \$walktab
  dump binary memory $scratch/walk_populated.bin \$walktab \$walktab+0x1000
  printf "LAB_WALK_TABLE_ADDRESS=%#lx\n", \$walktab
  printf "LAB_WALK_GLOBAL=%#lx\n", \$walkglob
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
  > "$base/logs/lab-walk.qemu.log" 2>&1) &
pid=$!
for ((i = 0; i < 200; i++)); do
  [[ -S "$scratch/gdb.sock" ]] && break
  kill -0 "$pid"
  sleep 0.05
done
rc=0
timeout --kill-after=2s 65s riscv64-linux-gnu-gdb -q -nx -batch \
  -x "$scratch/probe.gdb" > "$base/logs/lab-walk.gdb.log" 2>&1 || rc=$?
if grep -q 'LAB_WALK_STORE_MISMATCH' "$base/logs/lab-walk.gdb.log"; then
  cat "$base/logs/lab-walk.gdb.log"
  echo 'FAIL walk-table publication checkpoint'
  exit 1
fi
if ! grep -q 'LAB_WALK_TABLE_ADDRESS=' "$base/logs/lab-walk.gdb.log"; then
  cat "$base/logs/lab-walk.gdb.log"
  echo "FAIL walk-table checkpoint not reached (gdb exit=$rc)"
  tail -20 "$base/logs/lab-walk.qemu.log"
  exit 1
fi
grep -E 'LAB_WALK_WRITE_BEFORE|LAB_WALK_INITIAL|LAB_WALK_POPULATED|LAB_WALK_TABLE_ADDRESS|LAB_WALK_GLOBAL' \
  "$base/logs/lab-walk.gdb.log"
cp "$scratch/walk_initial.bin" "$base/logs/lab-walk-table-initial.bin"
cp "$scratch/walk_populated.bin" "$base/logs/lab-walk-table.bin"

python3 - "$base/logs/lab-walk-table-initial.bin" \
  "$base/logs/lab-walk-table.bin" <<'PY'
import hashlib, struct, sys

def load(path):
    b = open(path, 'rb').read()
    if len(b) != 4096:
        raise SystemExit(f'FAIL {path} size {len(b)}')
    return b, [struct.unpack_from('<Q', b, i)[0] for i in range(0, len(b), 8)]

initial, iq = load(sys.argv[1])
populated, pq = load(sys.argv[2])
print(f'WALK_TABLE_INITIAL_SHA256={hashlib.sha256(initial).hexdigest()}')
print(f'WALK_TABLE_SHA256={hashlib.sha256(populated).hexdigest()}')
print(f'WALK_TABLE_INITIAL_HEADER={iq[0]:#x},{iq[1]:#x},{iq[2]:#x}')
print(f'WALK_TABLE_HEADER={pq[0]:#x},{pq[1]:#x},{pq[2]:#x}')

# Initial free-list: first free slot 0xb, count 0x80, 0xc..0x7f free.
if iq[0] != 0xb or iq[1] != 0x80 or iq[2] != 0x2:
    raise SystemExit('FAIL unexpected initial walk-table header')
free = [(i * 8, iq[i]) for i in range(25, len(iq), 2) if iq[i]]
if len(free) != 116 or free[0][1] != 0xc or free[-1][1] != 0x7f:
    raise SystemExit('FAIL unexpected initial free-list')

# Populated table: 0xe free, 0x80 slots, level 1; valid metas have bit63.
if pq[0] != 0xe or pq[1] != 0x80 or pq[2] != 0x1:
    raise SystemExit('FAIL unexpected populated walk-table header')
entries = []
for idx in range(0x80):
    off = 0x10 + idx * 0x10
    field0 = struct.unpack_from('<Q', populated, off)[0]
    obj = struct.unpack_from('<Q', populated, off + 8)[0]
    meta = struct.unpack_from('<Q', populated, off + 16)[0]
    if meta & (1 << 63):
        entries.append((idx, obj, meta))
print('WALK_TABLE_ALLOCATED=' + ' '.join(
    f'{idx:#x}:{obj:#x}:{meta:#x}' for idx, obj, meta in entries))
expected = [
    (0x01, 0x8000000008028088, 0x8000000000000001),
    (0x08, 0xffffffffa300f030, 0x8000000000000001),
    (0x09, 0xffffffffa3015060, 0x8000000000000002),
    (0x0b, 0x800000000802a0d8, 0x8000000000000001),
    (0x0c, 0xffffffffa3015090, 0x8000000000000000),
    (0x0d, 0xffffffffa3015030, 0x8000000000000002),
]
if entries != expected:
    raise SystemExit('FAIL unexpected allocated walk-table entries')
PY

echo 'PASS walk-table initial free-list and populated entries are stable'
echo 'PASS original production LibOS reaches 0xffffffff93007324 and publishes [global+0x450]'

# Negative gate: no verified bit without the pinned production trust anchor.
rc=0
timeout --kill-after=2s 20s "$qemu" \
  -M "nvidia-gsp-lab,bootstrap=$base/firmware/gsp-bootstrap-610.57.04.bin,libos=$fixture/kernel-load-segments.elf,image=$base/firmware/gsp-fwimage-610.57.04.bin,fmc=$fmc,bootloader=$boot,trusted-key-sha256=0000000000000000000000000000000000000000000000000000000000000000" \
  -m 32M -display none -serial none -monitor none -nic none \
  > "$base/logs/lab-walk-wrong-key.log" 2>&1 || rc=$?
if [[ $rc != 1 ]] || ! grep -q 'BOOTER_PACKET_REJECTED' \
    "$base/logs/lab-walk-wrong-key.log"; then
  cat "$base/logs/lab-walk-wrong-key.log"
  echo "FAIL wrong lab trust anchor was not rejected (exit=$rc)"
  exit 1
fi
echo 'PASS lab rejects a wrong FMC trust anchor before CPU handoff'
echo 'This is a QEMU functional-profile checkpoint, NOT real-silicon boot or authentication evidence.'
