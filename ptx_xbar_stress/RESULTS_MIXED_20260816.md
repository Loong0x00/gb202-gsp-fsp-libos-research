# GB202 PTX XBAR mixed-workload sweep — 2026-08-16

## Purpose

The original `all` mode ran compute, L2, VRAM, and atomic tests sequentially.
This follow-up adds mixed kernels that interleave operations inside every warp.
While one warp is executing integer MAD instructions, other resident warps can
have L2/VRAM loads or global atomics outstanding. This tests simultaneous path
pressure rather than merely launching the isolated tests one after another.

Mixed modes:

- `mix-cl`: compute + L2
- `mix-la`: L2 + global atomics
- `mix-cla`: compute + L2 + global atomics
- `mix-lv`: L2 + VRAM
- `mix-clva`: compute + L2 + VRAM + global atomics

Every L2/VRAM load is checked against a CPU-defined deterministic pattern,
compute results are checked against a CPU closed-form result, atomic operation
counts must be exact, and every run must cover all 170 SMs.

## Test identity and controls

- GPU: NVIDIA GeForce RTX 5090, PCI `0000:01:00.0`
- Driver: `610.57.04`
- VBIOS: `98.02.2E.80.50`
- GPC request: 3000 MHz
- Propagation ratio: 1.000
- Dynamic NVVDD maximum: 980 mV
- Dynamic MSVDD maximum: 1065 mV
- Board power limit: 800 W
- Requested memory-clock lock: 15001 MHz
- Binary SHA-256: `485efd578c7102b083113ccd2de04260c0a42292c477e661c9d6c042eecd7934`
- Source SHA-256: `e8a93d1d8fc2dd459d16be2b750010e51643a24f95add25b70bb5349fb531c16`
- Sweep log root: `/home/user/rt_5090_project/benchmark_logs/ptx_xbar_mixed_sweep_20260816_090608`

GDM, LACT, and `nvidia-persistenced` were stopped before applying controls;
no NVIDIA device holder remained. Quill kernel/App Server, both sing-box
processes, and the water-loop controller remained active.

## XBAR +430 MHz

| Mode | Duration | XBAR min/avg/max MHz | Checked-load result | Atomic result |
|---|---:|---:|---|---|
| mix-cl | 3 s | 2942.9 / 2977.9 / 2996.9 | 0 errors | n/a |
| mix-la | 3 s | 2959.0 / 2980.6 / 3000.6 | 0 errors | exact |
| mix-cla | 3 s | 2922.4 / 2975.7 / 2999.6 | 0 errors | exact |
| mix-lv | 3 s | 2989.6 / 2992.0 / 3000.9 | 0 errors | n/a |
| mix-clva | 5 s | 2986.3 / 2991.9 / 3003.1 | 0 errors | exact |

All modes passed, covered all 170 SMs, and produced no kernel alert. The mixed
L2+VRAM paths held XBAR around 2992 MHz, materially above the earlier isolated
L2/VRAM averages of about 2973–2974 MHz.

## XBAR +440 MHz

| Mode | Duration | XBAR min/avg/max MHz | Checked-load result | Atomic result |
|---|---:|---:|---|---|
| mix-clva | 5 s | 2986.6 / 2995.9 / 3009.5 | 0 errors | exact |
| mix-lv | 3 s | 2994.9 / 2997.0 / 3005.1 | 0 errors | n/a |
| mix-cla | 3 s | 2935.6 / 2987.9 / 3008.6 | 0 errors | exact |
| mix-la | 3 s | 2962.0 / 2991.0 / 3004.1 | 0 errors | exact |
| mix-cl | 3 s | 2947.0 / 2987.5 / 3004.4 | 0 errors | n/a |
| isolated L2 | 10 s | 2976.5 / 2990.6 / 3004.0 | 0 / 1,412,515,758,080 errors | n/a |
| mix-clva | 15 s | 2986.3 / 2996.2 / 3003.9 | 0 / 409,993,216,000 errors | exact, 12,812,288,000 ops |

Across the +440 mixed runs and the 10-second isolated-L2 repeat, a total of
3,225,755,320,320 checked loads completed without a mismatch. All runs covered
all 170 SMs and the kernel logged zero Xid, AER, GSP-health, or PCIe events.

## Interpretation

The earlier +440 isolated-L2 run's one mismatch in 423,540,817,920 loads is a
real recorded observation, but it did not reproduce. The same control point
subsequently passed 1.41 trillion isolated L2 loads and 3.23 trillion checked
loads across the expanded matrix. It is therefore not justified to label +440
as deterministically data-unstable from the first single event alone. The
remaining possibilities include a rare non-stationary controller state, a
transient soft error, or an error condition not recreated by the later clock
trajectory.

The controller still does not sustain an average above 3 GHz. The closest
tested combinations were `mix-lv` at 2997.0 MHz and the 15-second `mix-clva`
run at 2996.2 MHz; both crossed 3 GHz in samples but settled just below it.
Increasing the offset from +430 to +440 raised those averages by only about
4–5 MHz, demonstrating controller compression near the boundary.

## Restoration

No SBR or reboot was needed. XBAR offset was restored to zero, the propagation
ratio to 0.899902, clock locks were reset, and the voltage-control preimage was
restored. GDM, LACT, `nvidia-persistenced`, water-loop control, both sing-box
processes, and Quill kernel/App Server were active afterward. The complete
sweep contained zero kernel alerts.
