# Reboot required before continuing GPU work

At 2026-08-22 15:48 local time, XBAR point 88 with a `+615000 kHz`
point delta and the seven-workload mixed case produced:

- Xid 109: `CTX SWITCH TIMEOUT`, process `17_ray_query_sc`
- Xid 79: GPU fallen off the bus
- Xid 154: recovery action `OS Reboot`

The watchdog began an SBR, but the experiment wrapper stopped the watchdog
mid-recovery.  Manual FLR, repeated bridge SBR, driver unbind, sibling-audio
unbind/removal, and GPU-function removal could not release
`nvidia-modeset/kthread_q`; the GPU remove callback remains in uninterruptible
sleep.  A host reboot is therefore required.  Do not issue more RM/GPU
commands in this boot.

The wrapper has been patched so future fatal events wait for watchdog recovery
instead of stopping it, and power/clock restoration failures no longer abort
evidence writing.

## Boundary evidence obtained before the crash

- GPC p93, source 1035 mV:
  - `+465 MHz`, compiled 3382 MHz: RT pipeline passed 5 seconds.
  - `+480 MHz`, compiled 3397 MHz: 1 second passed, but both 3-second runs
    caused an RM/nvidia-smi query timeout at roughly 2 seconds; no Xid and the
    GPU recovered immediately after workload termination.
- XBAR p88, source 1000 mV, seven-workload mixed case at 600 W:
  - `+540`, `+555`, `+570`, `+585`, and `+600 MHz` completed for 2 seconds.
  - `+600 MHz` compiled 3045 MHz and physically measured up to 3006.320 MHz.
  - `+615 MHz` is the hard-fail point above.

## Continue after reboot

1. Verify GPU, GSP, services, daily LACT curve, Throne/TUN, and HTTPS.
2. Return to displayless 600 W state and capture fresh GPC/XBAR preimages.
3. Confirm XBAR p88 `+600 MHz` for 5 seconds; retain `+615 MHz` as the first
   hard non-pass without rerunning it.
4. Continue the lower-risk single-unit and mixed boundary validation.

All experiment artifacts were synced before this note was written.

## Second-boot controlled MSVDD result

After reboot, the p88 interpretation was corrected by adding a temporary,
nonzero `990..1000 mV` MSVDD window with exact voltage-control preimage
restoration and by separating the XBAR curve delta from the propagation-root
GPC lock.

- Isolated `mix-clva` passed all four combinations of XBAR delta
  `+600/+615 MHz` and GPC lock `3037/3052 MHz` at MSVDD 995..1000 mV.
- The `+600 MHz` point passed both 2 seconds and 5 seconds; in the 5-second
  run the compiled p88 clock was 3037 MHz and the measured XBAR maximum was
  2977.154 MHz, with checked data/compute/atomic output.
- Seven-workload mixed cases at fixed MSVDD passed for:
  - XBAR `+600`, GPC 3037
  - XBAR `+600`, GPC 3052
- Seven-workload mixed XBAR `+615`, GPC 3037, MSVDD 990..1000 mV failed with
  Xid 109 in `17_ray_query_screenspace`, followed by Xid 79, GSP heartbeat
  timeout, and Xid 154 `OS Reboot`.

This isolates the failure from both a 15 MHz GPC propagation-root increase
and an MSVDD voltage drop.  The +615 curve itself is stable under isolated
XBAR traffic, but not under the full mixed raster/RT/FP32/FP8/XBAR workload.
The exact all-mixed boundary is therefore workload-dependent and lies between
the tested +600 pass and +615 hard failure for this boot's p88 table.
