# LACT loaded XBAR +450 MHz / composite MSVDD +20 mV A-B-A

Date: 2026-08-17

Workload: `ptx_xbar_stress --mode l2 --seconds 25 --l2-mib 32 --vram-mib 1024`

Control B: XBAR domain `+450000 kHz`, SYS domain `0 kHz`, XBAR/SYS/NVD rail-1 offsets `+20000 uV`, no point controls.

Each A1/B/A2 phase contains 30 physical samples over 3 seconds. B is compared with the mean of A1 and A2.

| Signal | A1 mean | B mean | A2 mean | B - mean(A1,A2) |
|---|---:|---:|---:|---:|
| GPC | 3175.316 MHz | 3173.726 MHz | 3175.532 MHz | -1.699 MHz (-0.053%) |
| XBAR | 2412.587 MHz | 2820.043 MHz | 2412.282 MHz | +407.608 MHz (+16.896%) |
| SYS | 2400.356 MHz | 2354.545 MHz | 2401.472 MHz | -46.369 MHz (-1.931%) |
| NVD | 2273.348 MHz | 2226.405 MHz | 2270.877 MHz | -45.708 MHz (-2.012%) |
| MSVDD target | 995.000 mV | 995.000 mV | 995.667 mV | -0.333 mV |

The workload completed 3977 rounds, covered 170/170 SMs, reported 0 errors and produced digest `e2c1814e7399b113`. The whole-run 422.501 GiB/s value crosses all three phases and is not a per-phase performance comparison.

Domain original/restored/final SHA-256: `2caf4cd0ab7bcf18400926dbf37d787f3a0d3cda95db32c7865eeb05a7ea9b0b`.

V/F original/final SHA-256: `f78ccf3c19d1876b18cb0c723f4d5eeb77f53f6ff920a0154b77d9382acc25d5`.

No Xid, reset-required, GSP, AER or PCIe bus error was found. This reproduces the old ~2.4 -> ~2.8 GHz physical XBAR result, but the composite three-domain voltage shift also lowers SYS/NVD under this load; it is not semantically identical to the old XBAR-only voltage-slot test.
