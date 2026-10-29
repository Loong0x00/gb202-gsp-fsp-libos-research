# Final production-path point CONTROL endpoint validation

Date: 2026-08-17

The rebuilt production compiler was invoked through the ignored live transaction test, without a test-only range override. Native point 96 was tested and restored at both endpoints for each writable bank:

- XBAR `-1000000 kHz`: CONTROL exact; effective `2550000 -> 2535000 kHz`
- XBAR `+1000000 kHz`: CONTROL exact; effective `2550000 -> 3502000 kHz`
- SYS `-1000000 kHz`: CONTROL exact; effective `2535000 -> 2527000 kHz`
- SYS `+1000000 kHz`: CONTROL exact; effective `2535000 -> 3532000 kHz`

All four transactions passed. All four per-transaction restored V/F CONTROL blocks compare byte-identical to the original. Final hashes:

- V/F original/final: `f78ccf3c19d1876b18cb0c723f4d5eeb77f53f6ff920a0154b77d9382acc25d5`
- Domain original/final: `2caf4cd0ab7bcf18400926dbf37d787f3a0d3cda95db32c7865eeb05a7ea9b0b`

No Xid, GSP, AER, or PCIe error appeared in the kernel log. This is CONTROL adoption/restore evidence, not workload-stability evidence.
