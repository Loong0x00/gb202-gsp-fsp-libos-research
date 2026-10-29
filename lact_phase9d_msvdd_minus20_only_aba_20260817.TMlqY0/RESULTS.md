# LACT loaded composite MSVDD -20 mV A-B-A

Date: 2026-08-17

Workload: `ptx_xbar_stress --mode l2 --seconds 25 --l2-mib 32 --vram-mib 1024`

Control B: XBAR/SYS frequency offsets `0 kHz`, XBAR/SYS/NVD rail-1 offsets `-20000 uV`, no point controls.

| Signal | A1 mean | B mean | A2 mean | B - mean(A1,A2) |
|---|---:|---:|---:|---:|
| GPC | 3175.184 MHz | 3174.075 MHz | 3173.796 MHz | -0.415 MHz (-0.013%) |
| XBAR | 2413.313 MHz | 2415.965 MHz | 2412.192 MHz | +3.212 MHz (+0.133%) |
| SYS | 2400.049 MHz | 2405.425 MHz | 2399.486 MHz | +5.658 MHz (+0.236%) |
| NVD | 2263.001 MHz | 2275.329 MHz | 2265.395 MHz | +11.131 MHz (+0.492%) |
| MSVDD target | 995.000 mV | 995.000 mV | 995.667 mV | -0.333 mV |

The workload completed 3897 rounds, covered 170/170 SMs, reported 0 errors and produced digest `cd3368f2c159f6a3`. All domain and V/F preimages restored byte-identically; no Xid/GSP/AER was found.

The negative direction is physically much smaller than the positive direction and is not a linear mirror, consistent with discrete bins, shared arbitration and other active constraints.
