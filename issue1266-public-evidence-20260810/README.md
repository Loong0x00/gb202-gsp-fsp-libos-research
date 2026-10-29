# NVIDIA/open-gpu-kernel-modules issue 1266 evidence bundle

This is the complete public evidence bundle for the 2026-08-10 reproduction.
It retains every file from the local raw archive: all benchmark-native output,
30-50 ms telemetry, clock/power-policy/PMGR captures, pre/post state, kernel
logs, scripts, configurations, and all four full `nvidia-bug-report` archives.
The `summary/` directory adds the generated report, machine-readable aggregate,
CSV table, exact LACT configuration, and a second independent verifier result.

For public disclosure only non-diagnostic identity data was replaced in place:
the local username/path, hostname, MAC addresses, machine/filesystem/GPU UUIDs,
DMI/PCIe/USB/storage serial numbers, and credential-like desktop environment
values. No diagnostic section was removed. Driver/GSP version, VBIOS, PCI IDs,
clock/power/performance data, commands, errors, kernel messages and file layout
are retained. `REDACTION_MANIFEST.json` records which files differ from their
local originals without disclosing the replaced values.

Key files:

- `summary/REPRODUCTION_REPORT.md`
- `summary/VERIFICATION.md` (`Result: PASS`)
- `summary/summary.csv`
- `summary/reproduction-results.json`
- `issue1266_fresh_repro_20260810_205741/nvidia-bug-report-unlocked.log.gz`
- `issue1266_fresh_repro_20260810_205741/nvidia-bug-report-locked.log.gz`
- `issue1266_fresh_repro_20260810_205741/nvidia-bug-report-recovered.log.gz`
- `issue1266_fresh_repro_20260810_205741/system/nvidia-bug-report-memory-lock-20260728.log.gz`

The failed Cyberpunk `U3` launcher attempt remains in the raw tree as a harness
diagnostic and is intentionally excluded from performance statistics.
