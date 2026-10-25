#!/usr/bin/env bash
# Synthetic regressions only: NO NVIDIA firmware runs in this machine.
set -euo pipefail
ulimit -c 0
base=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
mkdir -p "$base/logs"
for variant in 0 1 2 3 4; do
  name="nv-lab-isolation-$variant"
  riscv64-linux-gnu-as -march=rv64imac_zicsr -mabi=lp64 \
    --defsym "VARIANT=$variant" "$base/tests/nv-lab-isolation.S" -o "$base/tests/$name.o"
  riscv64-linux-gnu-ld --no-relax -T "$base/tests/nv-lab-isolation.ld" \
    "$base/tests/$name.o" -o "$base/tests/$name.elf"
  rc=0
  timeout --kill-after=2s 10s "$base/build/qemu-system-riscv64" \
    -M nvidia-gsp-isolation-test -accel tcg -display none -serial none \
    -monitor none -nic none -kernel "$base/tests/$name.elf" \
    > "$base/logs/$name.log" 2>&1 || rc=$?
  if [[ $variant = 0 ]]; then
    [[ $rc = 0 ]] && grep -q 'SYNTHETIC_ISOLATION_TEST PASS' "$base/logs/$name.log" || {
      cat "$base/logs/$name.log"; echo "FAIL isolation run exit=$rc"; exit 1;
    }
    echo 'PASS synthetic Bare isolation: register/CSR/LRSC cleanup, Sv39 WARL denial, cross-context TLB, RO/subpage/span/X restrictions and native FID9 revocation'
  else
    pattern='invalid entry registration'
    [[ $variant != 4 ]] || pattern='invalid memory grant request'
    [[ $rc = 1 ]] && grep -q "$pattern" "$base/logs/$name.log" || {
      cat "$base/logs/$name.log"; echo "FAIL negative variant=$variant exit=$rc"; exit 1;
    }
    echo "PASS synthetic rejected registration/grant variant=$variant"
  fi
done
