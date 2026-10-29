# Main pc4 integration finding — 2026-09-10

The first actual Wine fake-runtime/factory harness crashed before any game/GPU
NR test. `NATIVE_PC4_BUILD.log` captures a write fault in the owned host at
`lock cmpxchgq`, targeting Wine DXGI's read-only factory vtable.

Root cause is exact: both new factory and IAT helpers used
`compare_exchange(slot, nullptr, nullptr)` as a read **before VirtualProtect**.
CMPXCHG is a read-modify-write instruction and needs writable memory even when
the compare does not match. Writable CPU fixtures missed this condition.

Main corrected both production helper contracts to use an acquire-only
`__atomic_load_n` for the target read. Actual replacement still uses CAS after
successful writable protection; owned predecessor/state publication is unchanged.
CPU mocks now require write permission for every target CAS, including read-like
ones, and initialize their tracked read-only slots before installation.

The repeated actual Wine factory/fake-runtime harness now passes, and does not
publish production capabilities. Backup (including failed host DLL) is under
`backups/pc4-readonly-cas-20260910-084437/`; successful build log is
`NATIVE_PC4_READONLY_FIX_BUILD.log`. No game was deployed during this failure.

This is unrelated to any claim about the earlier REDEngine startup crash; that
older initiating fault is still unproven. pc4 game regressions are subsequent
and must be recorded separately.
