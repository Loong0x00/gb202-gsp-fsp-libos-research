# LACT Phase 5 combined frequency/MSVDD receipt

Date: 2026-08-17

Workload: `ptx_xbar_stress --mode l2 --seconds 8 --l2-mib 32 --vram-mib 1024`

Transaction: one complete `0x83c` control block containing XBAR `+15000 kHz`, SYS `+15000 kHz`, and XBAR/SYS/NVD rail-1 `+1000 uV` relative controls.

## Confirmed

- The applied block differed from the original only in the XBAR/SYS domain frequency fields and the three XBAR/SYS/NVD rail-1 fields.
- XBAR and SYS control readback adopted `+15000 kHz`; each domain's 127/127 effective-frequency and total-frequency STATUS fields moved by exactly `+15000 kHz`.
- XBAR, SYS and NVD control readback adopted `+1000 uV`; all three domains' 127/127 effective-voltage and total-voltage-offset STATUS fields moved by exactly `+1000 uV`.
- NVD frequency fields remained unchanged. The GPC/NVVDD domain and all GPC points remained unchanged.
- Physical samples during the loaded transaction were XBAR `2411900 -> 2422204 kHz` (`+10304 kHz`) and SYS `2401415 -> 2409168 kHz` (`+7753 kHz`). They are workload/quantization governed and are not expected to equal the requested delta exactly.
- Aggregate MSVDD target was `995000 uV` before and after the combined SET. The 1 mV per-domain shift did not cross the current 5 mV aggregate target step or change the winning request.
- L2 validation completed 1244 rounds, covered 170/170 SMs, reported 0 errors, and produced digest `b594c791e0922cb4` across 3304.375 GiB of checked traffic.
- The kernel window contained no Xid, GSP failure, AER, PCIe bus error or reset-required event.

## Control-block hashes

```text
original/restored/final:
2caf4cd0ab7bcf18400926dbf37d787f3a0d3cda95db32c7865eeb05a7ea9b0b

combined applied:
cd71f0ea93fa14af9e38bc409ffe7ee3d5c373ff0d7a3facf529692c00a166e3
```

## Boundary

This proves that domain-wide frequency movement and composite MSVDD curve movement coexist in one restored transaction on the pinned contract. It does not yet prove per-point curve setters, a wider voltage-offset envelope, a changed aggregate-rail winner, propagation-ratio writes, or the NVD frequency consumer.
