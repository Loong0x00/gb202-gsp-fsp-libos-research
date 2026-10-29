# LACT Phase 8 composite MSVDD -50/+50 mV receipt

Date: 2026-08-17

Contract: NVIDIA R610.57.04 / VBIOS 98.02.2E.80.50 with the complete LACT Blackwell private-API contract fingerprint pinned by the branch.

## Result

- The restored live test applied `-50000 uV` and `+50000 uV` sequentially to the XBAR, SYS and NVD rail-1 offset slots in the complete `0x83c` domain control block.
- Both endpoints passed SET, complete control-block readback, semantic validation of all 127 STATUS points in each of the three domains, and restoration.
- A fresh read-only smoke test after both transactions reported XBAR/SYS/NVD voltage offsets at `0 uV`; GPC/NVVDD remained unchanged.
- Baseline and applied aggregate MSVDD target were both `880000 uV` at idle. This proves control/STATUS adoption, not a physical rail-target change or loaded stability.
- No Xid, reset-required, GSP, AER or PCIe bus error was found in the test window.

## Test output

```text
composite MSVDD -50000 uV: target 880000->880000 uV; measured XBAR/SYS/NVD [1452698, 1460076, 1401157]->[1679443, 1662036, 1567741] kHz
composite MSVDD +50000 uV: target 880000->880000 uV; measured XBAR/SYS/NVD [2033198, 2022790, 1886456]->[2034421, 2018860, 1912074] kHz
test result: ok. 1 passed; 0 failed
```

The idle clock samples are recorded for completeness and are not treated as a causal voltage-adoption measurement.

## Control-block hashes

```text
original/restored/final:
2caf4cd0ab7bcf18400926dbf37d787f3a0d3cda95db32c7865eeb05a7ea9b0b

-50000 uV applied:
1db59e898d2e188c3e00ae3bd4a8ab90ec2e65cd9dfd643a220a2afc241ce34d

+50000 uV applied:
b821244cad58bfbe840d37c1253a7f827d1e0e7919dd42ec85638e0b61c62e17
```

Only the signed fields beginning at offsets `0x90`, `0x110` and `0x150` differed in the applied control blocks. All three restored blocks and the final block were byte-identical to the original.

## Boundary

This authorizes LACT's exact-contract experimental composite envelope of `-50..+50 mV` for control/STATUS adoption and exact restoration on this contract. It is not a vendor-published safe range and does not establish loaded stability or direct physical VRM VOUT movement.
