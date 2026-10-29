# v25.3 source recovery and port

## Source found

`/home/user/rt_5090_project/driver_mods_backup/` contains the actual v25.x implementation, including:

- real RPC sequence preservation;
- EOM=0 while firing and proper continuation headers;
- Phase1 submission, 50 ms delay, and a separate Phase2 continuation batch;
- LARGE-path metadata injection at `pBig+0x20000`;
- map/map2/map3 rotation and `xdig_ovlen`.

## Ported into the current worktree

Preserved the current kernel compatibility changes, WPR2 bypass, 2-second RPC timeout, and QOUT diagnostics. Added those protocol behaviors and LARGE injection to the current source rather than replacing the whole driver.

Final module:

- version: `610.57.04`
- vermagic: `7.1.9-arch1-2 SMP preempt mod_unload`
- SHA-256: `bf6c1d1ebbb8c01f09f015b44c707c4201e82ec63f67349df07c91b5ffbb6f2f`

The module was compiled and inspected only. It has not been loaded.

## Prepared next experiment

`guest_v25_canary.sh` performs one bounded canary using the v25.3 path and the existing second queue page. Acceptance requires `0xdeadbeef` to appear in QOUT; a timeout or crash alone is not success.

No VM or GPU ownership transition was started during this work.
