#!/usr/bin/env bash
# Scoped bootstrap: never reset or discard an existing source tree.
set -euo pipefail
base=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
expected=4fc49f46dc95d4a27de2509e7fceb2931e91faeb
patch="$base/patches/0001-nvidia-gsp-boot-foundation.patch"
if [[ ! -e "$base/qemu" ]]; then
  git clone --depth 1 --branch v11.1.2 https://github.com/qemu/qemu.git "$base/qemu"
fi
actual=$(git -C "$base/qemu" rev-parse HEAD)
[[ $actual = "$expected" ]] || { echo 'Wrong QEMU revision; existing work was not changed' >&2; exit 1; }
if git -C "$base/qemu" apply --reverse --check "$patch" >/dev/null 2>&1; then
  echo 'GSP boot foundation patch already present'
else
  git -C "$base/qemu" apply --check "$patch"
  git -C "$base/qemu" apply "$patch"
fi
