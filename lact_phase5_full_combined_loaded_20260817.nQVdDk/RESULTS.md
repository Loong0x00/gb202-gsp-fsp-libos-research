# LACT Phase 5 full point/domain/MSVDD combined receipt

Date: 2026-08-17

Workload: `ptx_xbar_stress --mode l2 --seconds 8 --l2-mib 32 --vram-mib 1024`

## Transaction

- XBAR domain offset: `+15000 kHz`
- SYS domain offset: `+15000 kHz`
- XBAR point 0: `+15000 kHz`
- SYS point 0: `-15000 kHz`
- XBAR/SYS/NVD rail-1 offset: `+1000 uV`

## Confirmed

- The domain block and V/F block both returned exact submitted controls.
- XBAR point 0 composed to `+30000 kHz` effective movement (domain plus point); its other 126 points moved `+15000 kHz`.
- SYS point 0 composed to `0 kHz` effective movement (`+15000-15000`); its other 126 points moved `+15000 kHz`.
- Every XBAR/SYS/NVD point moved its effective voltage and total voltage offset by exactly `+1000 uV`. NVD frequency and all GPC/NVVDD state remained unchanged.
- Loaded physical samples were XBAR `2412050 -> 2422480 kHz` and SYS `2404621 -> 2405382 kHz`. Exact STATUS composition, not a single dynamic physical sample, is the hard semantic criterion.
- Aggregate MSVDD target remained `995000 uV`; the 1 mV shift did not cross the current 5 mV aggregate step/winner boundary.
- The L2 workload completed 1243 rounds, covered 170/170 SMs, reported 0 errors, and produced digest `9bb63410bb2493f9` across 3301.719 GiB of checked traffic.
- No Xid, GSP failure, AER, PCIe bus error or reset-required event appeared.

## Hashes

```text
domain original/final:
2caf4cd0ab7bcf18400926dbf37d787f3a0d3cda95db32c7865eeb05a7ea9b0b

V/F original/final:
f78ccf3c19d1876b18cb0c723f4d5eeb77f53f6ff920a0154b77d9382acc25d5

domain applied:
cd71f0ea93fa14af9e38bc409ffe7ee3d5c373ff0d7a3facf529692c00a166e3

V/F applied:
67ab632638ab79038d8c19f8f166b669db9f38f3b51b70b25b93bb2e42f2bb85
```

## Boundary

The two private RM objects cannot be committed by one native SET. LACT treats them as one recoverable transaction: capture both preimages, apply domain then V/F, verify both, and restore V/F then domain on reset or any failure. This validates XBAR/SYS point/domain/MSVDD composition on the pinned contract; propagation and NVD frequency/point controls remain separate gates.
