@amrit1711 I reran the public repro and can reproduce it deterministically. I also enabled persistence mode for the test, as in your additional runs.

Fresh environment:

- Arch Linux, kernel `7.1.6-arch1-1`
- NVIDIA Open kernel module / GSP-RM `610.57.04`
- RTX 5090, current VBIOS `98.02.2E.C0.0F`, subsystem `1462:530B`
- identical 127-point V/F curve, `+2000 MHz` memory offset and `600 W` power limit in every state
- unlocked state: `sudo nvidia-smi --reset-memory-clocks`
- locked state: `sudo nvidia-smi --lock-memory-clocks=15000,16000`
- test order alternated `U1/L1/U2/L2` for Cyberpunk and `U1/L1/U2/L2/U3/L3` for FurMark

The custom V/F curve is part of the reproducer. The adapted LACT configuration used in all fresh runs has SHA-256:

```text
f44bd358f5df03a971d969c41c5a538bbd8d626fe4236a7f25f53dcb0dbc3e09
```

Cyberpunk 2077 2.31, `6144x3456`, path tracing enabled, no frame generation:

| Pair | State | avg FPS | min/max FPS | physical MCLK | XBAR avg | SYS avg | reported GPU avg | voltage avg | 1 s board power avg | GPU util |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | unlocked | 11.7215 | 10.2244 / 13.6559 | 15001 MHz | 2429.9 MHz | 2269.4 MHz | 2832.8 MHz | 972.2 mV | 600.0 W | 96.6% |
| 1 | 15000-16000 | 10.3288 | 9.4683 / 11.7779 | 15001 MHz | 1628.8 MHz | 1486.0 MHz | 2956.8 MHz | 1018.2 mV | 571.2 W | 98.6% |
| 2 | unlocked | 11.6946 | 10.1917 / 13.7253 | 15001 MHz | 2423.2 MHz | 2266.1 MHz | 2830.6 MHz | 971.4 mV | 599.7 W | 97.2% |
| 2 | 15000-16000 | 10.3784 | 9.4928 / 11.8559 | 15001 MHz | 1628.8 MHz | 1486.0 MHz | 2956.9 MHz | 1017.4 mV | 572.6 W | 97.0% |

Cyberpunk reproduction frequency is **2/2 pairs**. Mean unlocked/locked FPS is `11.7080 / 10.3536`, a **11.57% loss**. The physical memory clock remains approximately 15001 MHz, so the requested maximum is non-binding. The finite range nevertheless moves XBAR/SYS to the lower state. In this fresh run the reported GPU clock increases while rendered performance decreases.

I also repeated the original FurMark control using FurMark 2.10.2 Vulkan at `3840x2160`, with its fixed warm-up followed by a 10-second scored interval:

| Pair | State | Score | min/avg/max FPS | physical MCLK | XBAR avg | SYS avg | reported GPU avg |
|---|---|---:|---:|---:|---:|---:|---:|
| 1 | unlocked | 2412 | 236 / 242 / 248 | 15001 MHz | 2300.3 MHz | 2138.5 MHz | 2411.4 MHz |
| 1 | 15000-16000 | 1911 | 186 / 190 / 194 | 15001 MHz | 1628.6 MHz | 1486.1 MHz | 2918.7 MHz |
| 2 | unlocked | 2404 | 236 / 241 / 244 | 15001 MHz | 2303.0 MHz | 2144.1 MHz | 2417.3 MHz |
| 2 | 15000-16000 | 1915 | 155 / 189 / 194 | 15001 MHz | 1628.4 MHz | 1485.8 MHz | 2915.5 MHz |
| 3 | unlocked | 2404 | 231 / 240 / 244 | 15001 MHz | 2302.5 MHz | 2143.4 MHz | 2401.6 MHz |
| 3 | 15000-16000 | 1916 | 174 / 190 / 197 | 15001 MHz | 1628.1 MHz | 1485.6 MHz | 2919.5 MHz |

FurMark reproduction frequency is **3/3 pairs**. Mean unlocked/locked FPS is `241.00 / 189.67`, a **21.30% loss**. Again, MCLK does not change, XBAR/SYS collapse, and the reported GPU clock rises by about 500 MHz while useful throughput falls.

Across all five formal A/B pairs:

- there was no thermal slowdown, hardware slowdown, power-brake slowdown or software thermal slowdown;
- the private RM PERF-limit query reported zero active limits;
- no new NVIDIA Xid appeared in the kernel log;
- the exact pre-test LACT configuration was restored byte-for-byte afterward, and the public MCLK range was reset.

The original report was captured on the exact issue configuration (`610.43.03`, kernel `7.1.4`, VBIOS `98.02.2E.40.E0`, subsystem `1043:89e3`). The attached bundle contains that original full `nvidia-bug-report` plus fresh full unlocked, locked and recovered reports from `610.57.04`. It retains all 836 files from the local raw archive (885 archive entries): per-run native benchmark output, 30-50 ms telemetry, XBAR/SYS measurements, PMU policy data, PMGR channels, every pre/post state capture, kernel logs, configurations, scripts and SHA-256 manifests. It also contains the generated report, CSV/JSON aggregates and an independent verifier that recomputes the claims from the raw files.

For public disclosure, only non-diagnostic identity values were replaced: username/home path, hostname, MAC addresses, machine/filesystem/GPU UUIDs, DMI/PCIe/USB/storage serial numbers and credential-like desktop environment values. No diagnostic section was removed. The included privacy audit reports zero findings, and the included independent evidence verifier reports `PASS`.

Attached public evidence bundle SHA-256:

```text
19390dac72556647e524119a5bd6759e4ed9f669e95bf44fed894e6ad0f80d78  issue1266-public-evidence-20260810.zip
```
