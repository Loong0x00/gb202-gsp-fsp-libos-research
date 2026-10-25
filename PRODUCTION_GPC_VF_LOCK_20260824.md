# GB202 production-driver GPC/NVVDD lock (2026-08-24)

## Result

The consumer NVIDIA `610.57.04` driver with its normal production GSP can hold
GPC frequency and NVVDD simultaneously.  MODS is not loaded or used.

The working composition is:

1. Set the retail NVVDD reliability maximum and VMIN to the same 5 mV-aligned
   value and wait for the physical target to converge.
2. Apply the GPC domain frequency offset through `0x2080d01c`.
3. Activate `PERF_SET_FORCE_PSTATE_EX` (`0x2080a071`, words `1,0,2`).
4. On exit or signal, restore the full D01C preimage, clear A071, and only then
   restore the full voltage-control preimage.

The production wrapper is:

```text
power_governor_reverse/bug_inverse/voltage_61057/production_gpc_vf_lock.py
```

Example:

```bash
sudo -n python3 \
  /home/user/rt_5090_project/power_governor_reverse/bug_inverse/voltage_61057/production_gpc_vf_lock.py \
  --gpc-mhz 3100 --nvvdd-mv 1050 --seconds 60 --power-limit-w 600
```

Wait for the `LOCKED` line, then launch a workload from another terminal.
`Ctrl-C`, `SIGINT`, and `SIGTERM` use the same ordered restore path.

## Physical validation

All tests below ran headless on the production driver/GSP with a 600 W cap.

| Request | Idle | Checked workload | Post-load | Result |
|---|---|---|---|---|
| 915 mV / 2220 MHz | 2212/2220 MHz, 915000 uV | 9888 compute rounds, 170/170 SM, 0 errors | 2212/2220 MHz, 915000 uV | pass |
| 1050 mV / 3100 MHz | 3097 MHz, 1050000 uV | mixed compute/L2/VRAM/atomics, 3090/3097 MHz, peak 267 W, 0 errors | 3097 MHz, 1050000 uV | pass |
| 915 mV / 2220 MHz, `Ctrl-C` | 2212/2220 MHz, 915000 uV | interrupted after lock | D01C byte-identical, A071 clear, voltage preimage restored | pass |

The nominal 3100 MHz request lands on the GB202 clock grid at 3090/3097 MHz;
the 1050 mV rail target is exact.  NVVDD VMIN/MAX adoption is asynchronous:
the control readback changes first and the physical target follows about half a
second later.  The wrapper explicitly waits for that convergence.

Evidence is under:

```text
/home/user/rt_5090_project/production_vf_lock_probe_20260824/
```

## Boundary

This proves a production-stack hard clamp, not direct public access to GSP's
ten voltage-request slots.  The wrapper is pinned to `610.57.04`; it refuses a
different driver.  Current validation is headless.  GNOME/display-active use
has not been revalidated after the earlier display-active Xid, so the wrapper
does not claim that boundary yet.  It never resets the GPU.
