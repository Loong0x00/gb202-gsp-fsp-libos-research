# XBAR/SYS point CONTROL range probe

Date: 2026-08-17 07:55 +08:00

Contract:

- Driver: `610.57.04`
- VBIOS: `98.02.2E.80.50`
- Live VBIOS ROM SHA-256: `f9a4bcf866c216f633ca322d14ff9de02e8238aeee93ebe7de0a20ab9c5f77cf`
- Target: native point 96 (about 1.05 V) in the separate XBAR and SYS 127-point banks

## Result

Both XBAR and SYS accepted and exactly read back every requested point CONTROL value:

`-30, +30, -60, +60, -120, +120, -240, +240, -480, +480, -1000, +1000 MHz`

Only the selected point's CONTROL field changed. All non-target CONTROL fields and both domain-control preimages remained byte-identical. This establishes an exact-contract CONTROL envelope of at least `-1000..+1000 MHz`; it is not a stability or safe-clock claim.

STATUS materialization is constrained rather than point-independent:

- XBAR point 96 `+30 MHz` read back as CONTROL `+30000 kHz`; points 97 and 98 were raised to the same `2580000 kHz` effective value while their CONTROL remained zero.
- XBAR point 96 `+480 MHz` read back as CONTROL `+480000 kHz` and `3022000 kHz` effective. Point 95 became `2632000 kHz`, exactly 390 MHz below it, while following points flattened to `3022000 kHz` until the native curve caught up.
- XBAR point 96 `+1000 MHz` read back as CONTROL `+1000000 kHz` and about `3487000 kHz` effective. Point 95 was `3097000 kHz`, again 390 MHz below it, and following points flattened.
- SYS point 96 `+1000 MHz` read back as CONTROL `+1000000 kHz` and about `3532000 kHz` effective, with the same backward 390 MHz step and forward flattening.
- Negative requests read back exactly in CONTROL, but effective STATUS was floored by the preceding monotonic curve. XBAR point 96 at `-1000 MHz` had CONTROL `-1000000 kHz` but effective `2535000 kHz`.

The selected point was not the active operating point, so physical XBAR/SYS counters stayed near their existing clocks. These transactions prove CONTROL acceptance, STATUS constraint behavior, and exact restore—not workload stability at the materialized candidate clocks.

## Restore proof

- V/F original/final SHA-256: `f78ccf3c19d1876b18cb0c723f4d5eeb77f53f6ff920a0154b77d9382acc25d5`
- Domain original/final SHA-256: `2caf4cd0ab7bcf18400926dbf37d787f3a0d3cda95db32c7865eeb05a7ea9b0b`
- All 24 per-transaction restored V/F CONTROL blocks compare byte-identical to the original.
- No Xid, GSP, AER, or PCIe error appeared in the test-window kernel log.

Dynamic source-base and total-offset STATUS fields shifted by a few MHz between fresh reads. Exact CONTROL bytes and complete preimage restoration, rather than byte-stable STATUS, are therefore the adoption boundary.
