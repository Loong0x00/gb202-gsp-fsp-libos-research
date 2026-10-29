# LACT loaded composite MSVDD +20 mV A-B-A

Date: 2026-08-17

Workload: `ptx_xbar_stress --mode l2 --seconds 25 --l2-mib 32 --vram-mib 1024`

Control B: XBAR/SYS frequency offsets `0 kHz`, XBAR/SYS/NVD rail-1 offsets `+20000 uV`, no point controls.

| Signal | A1 mean | B mean | A2 mean | B - mean(A1,A2) |
|---|---:|---:|---:|---:|
| GPC | 3176.083 MHz | 3175.866 MHz | 3172.895 MHz | +1.377 MHz (+0.043%) |
| XBAR | 2412.874 MHz | 2369.772 MHz | 2412.777 MHz | -43.053 MHz (-1.784%) |
| SYS | 2401.055 MHz | 2354.400 MHz | 2400.973 MHz | -46.614 MHz (-1.941%) |
| NVD | 2274.015 MHz | 2223.832 MHz | 2278.622 MHz | -52.487 MHz (-2.306%) |
| MSVDD target | 995.000 mV | 995.833 mV | 995.000 mV | +0.833 mV |

The workload completed 3887 rounds, covered 170/170 SMs, reported 0 errors and produced digest `ca81a5e74b11ff55`. All domain and V/F preimages restored byte-identically; no Xid/GSP/AER was found.

At an effectively unchanged shared target, moving all three local curves +20 mV selects lower physical clocks. The composite slider is therefore not a direct physical VOUT increase.
