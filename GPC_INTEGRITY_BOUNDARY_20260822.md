# GB202 GPC data-integrity boundary follow-up — 2026-08-22

## Acceptance rule

A control point fails if any checked numerical result, XBAR/L2/VRAM/atomic
result, deterministic rendered image, CUDA/Vulkan process, RM query, GSP health
event, or kernel health check fails.  A surviving GSP is not evidence of data
correctness.  Conversely, a requested or compiled clock is not evidence that
the physical GPC clock was granted.

## Validator changes

- Four deterministic 1920x1080 Vulkan outputs were generated three times at a
  healthy baseline.  Their decoded-pixel signatures were identical across all
  three runs.
- `workload_arbiter_model/combo_load.py` now compares decoded pixels against
  those signatures instead of accepting any freshly-created JPEG.
- `vulkan_repeat_checked.py` can collect and verify multiple independent
  rendered images during one V/F holder transaction.  It now writes and
  fsyncs a progress receipt before each render and after each validation, so a
  fatal second render cannot erase the completed first-render evidence.
- The RT-query sample's internal 200-frame cap was removed from the test path.
  `rt_query_long` executes and validates 1600 actual accumulated frames; the
  old nominal multi-second rows below only issued 200 frames each.
- `held_point_workload.py` can request a nonzero voltage window, but the tests
  below showed that NVVDD VMIN/MAX writes alter the GPC policy trajectory.
  Rail setters are therefore not treated as transparent point selectors.
- `xbar_vf_point_demo.isolate` adds `--bank-isolate-hold`.  It raises one GPC
  point and asks all higher points to remain one 15 MHz bin lower.  GSP enforces
  monotonicity and materializes the higher tail at the same frequency as the
  target, producing a flat tail.  The entire CONTROL bank is restored
  byte-identically after each successful transaction.

## Important control discrimination

P93 +465 with no rail setter naturally selected up to 1035 mV and reproduced
the high-clock trajectory.  The same point with a 1030--1035 mV VMIN/MAX
window made the physical rail high while policy telemetry observed only about
1015 mV and reduced the final GPC clock.  A MAX-only 1035 mV write also changed
the selected trajectory.  This reproduces the distinction between physical
rail target, logical policy voltage, and final clock; the rail-controlled runs
must not be used as per-point frequency limits.

## P88 / 1000 mV isolated-tail evidence

The isolated flat tail made the physical rail select 995--1000 mV under the
checked workloads.

### Seven-way mixed confirmation

Control: P88 +330 MHz user delta, compiled GPC 3157 MHz, 600 W limit,
continuous FP32 + FP8 + raster + RT pipeline + RT query + raster/RT hybrid +
checked XBAR/L2/VRAM/atomic workload for 2 seconds.

- Physical GPC min/median/p95/max in the active rail window:
  2621.714 / 3101.226 / 3151.969 / 3159.615 MHz.
- FP32 sampled result correct and finite.
- FP8 sampled result exactly matched.
- XBAR mixed kernel reported zero data, compute, and atomic-count errors.
- All four final Vulkan images matched their decoded-pixel baselines.
- Zero Xid/GSP/AER event; strict post-run health passed.

### RT-query boundary sweep

Each passing row produced two independently rendered images with exact pixel
signatures and no kernel alert.  Durations were short boundary probes, not
daily-stability qualifications.

| P88 user delta | Compiled MHz | Physical GPC median MHz | Physical max MHz | Result |
|---:|---:|---:|---:|---|
| +345 | 3172 | 3155.267 | 3175.866 | pass, 2/2 images exact |
| +360 | 3187 | 3174.757 | 3192.177 | pass, 2/2 images exact |
| +375 | 3202 | 3188.632 | 3204.584 | pass, 2/2 images exact |
| +390 | 3217 | 3189.969 | 3222.175 | pass, 2/2 images exact |
| +405 | 3232 | 3222.848 | 3230.246 | pass, 2/2 images exact |
| +420 | 3247 | 3224.992 | 3259.862 | pass, 2/2 images exact |
| +435 | 3262 | 3214.847 | 3259.852 | pass, 2/2 images exact |
| +450 | 3277 | 3248.266 | 3277.551 | pass, 2/2 images exact |
| +465 | 3292 | 3224.910 | 3295.141 | pass, 2/2 images exact |
| +480 | 3307 requested | unavailable | unavailable | fail: Xid 109 then GPU/GSP loss |

The +480 run failed before producing a valid rendered sample.  The sequence was
RT-query `Xid 109 CTX SWITCH TIMEOUT`, followed by `Xid 79`, GSP RPC/heartbeat
timeout, and `Xid 154` with OS reboot recovery action.  Thus the observed
15 MHz boundary of the old 200-frame probe was +465 pass / +480 fail.  The last
short-probe physical sample reached 3295.141 MHz at no more than 1000 mV; it is
not a stable-point qualification.

### Corrected 1600-frame result

One independent P88 +465 run completed 1600 actual RT-query frames with the
exact decoded-pixel signature.  In the active 995--1000 mV window its physical
GPC min/median/p95/max was
3062.147 / 3177.359 / 3231.281 / 3270.815 MHz.

A following two-sample transaction saved and re-verified exact sample 1 at
17:49:47, then sample 2's `16_ray_query` hit `Xid 109 CTX SWITCH TIMEOUT` at
17:49:55.  This was followed by `Xid 79`, loss from the PCIe bus, GSP and LibOS
heartbeat timeouts, and `Xid 154`.  The run peaked at only 556.11 W and 60 C;
its point readback was 1000 mV / 3292 MHz compiled and the last physical GPC
samples were about 3.26--3.30 GHz.  Power and temperature limits therefore do
not explain the failure.

P88 +465 is a hard repeatability failure.  P88 +450 is now only the highest
passing 200-frame probe at this stage of the chronology.

After reboot and the modeset exclusion fix, P88 +450 passed two corrected
1600-frame RT-query renders at 600 W.  Both decoded-pixel signatures were exact;
strict health passed with zero kernel alert.  In the 995--1000 mV active window,
physical GPC min/median/p95/max was
2963.684 / 3168.837 / 3222.659 / 3266.243 MHz.

The same point then passed `all_long` at 600 W: two independently checked
images for each Vulkan class plus concurrent raster, RT pipeline, 1600-frame
RT query, raster/RT hybrid, FP32, FP8, and checked XBAR/L2/VRAM/atomic work.
Every numerical and decoded-pixel check passed, with zero kernel alert.  A
short 800 W repeat of all seven classes also passed; actual power exceeded
600 W for about 1.46 s, peaked at 668.52 W instantaneous, and reached 63 C.
Its physical GPC median/p95/max was
3172.781 / 3246.913 / 3270.252 MHz.  The power limit was immediately restored
and read back at 600 W.

The corrected P88 boundary is therefore +450 pass / +465 fail, one 15 MHz
control bin apart.  This qualification is workload-specific evidence, not a
claim that an arbitrarily long or previously unseen workload is impossible to
fail.

## P93 / 1035 mV evidence

P93 +465 without any rail setter completed the seven-way checked workload.
One 5-second run measured physical GPC median/p95/max
3165.644 / 3335.247 / 3360.686 MHz.  A later 2-second discrimination run
measured 3201.941 / 3366.087 / 3372.851 MHz.  FP32, FP8, XBAR checked results
and all four deterministic final images were correct.  The separately known
P93 +480 RT repeat made RM telemetry hang and is a failed neighbor, not a
passing point.

## Recovery state

The watchdog performed preliminary bridge resets and released userspace/UVM
references, but `modprobe -r` entered `nvidia_drm` module state `Unloading` and
spun in `nvidia_modeset!nvEvoWaitForCoreNotifier` while disabling the display
pipeline.  A further bridge SBR and PCI FLR completed but could not release the
already-running `delete_module` path.  Linux provides no supported operation
to cancel a module after it has entered GOING/Unloading; this boot requires a
reboot before any further GPU experiment.

GDM was already stopped before testing.  Throne/sing-box and Quill kernel
remained active independently of the display manager.

The corrected long-test failure exposed a second recovery path.  GDM and
`nvidia_drm` were absent, but starting the headless Vulkan workload reloaded
`nvidia_modeset` at 17:48:37.  After Xid 109/79, the killed process retained a
live `cuda-EvtHandlr` thread and UVM refcount 2; the modeset kthread blocked in
`nvEvoRestoreConsole` on a semaphore last held by that CUDA thread.  Watchdog
SBR, manual PCI FLR, a driver unbind, and a later SBR could not make either
thread leave the NVIDIA callback.  Thus excluding `nvidia_drm` alone is
insufficient: future risky tests need a preflight that proves
`nvidia_modeset` remains absent after a real headless Vulkan launch, or the
reset path can still be pinned.  The host was rebooted at 17:56 and the new
boot read back healthy with no Xid.

The autoload source was then reproduced directly at stock.  A headless
one-frame RT-query execs the setuid helper as
`/usr/bin/nvidia-modprobe -m`; an ordinary run loaded and retained
`nvidia_modeset`.  Running the identical command under
`setpriv --no-new-privs` left modeset absent, returned zero, and produced a
byte-identical JPEG with the same decoded-pixel signature.  All checked Vulkan
children now inherit no-new-privs, while base NVIDIA and UVM modules are
prepared before the workload.  The risky point holder also rejects a run if
`nvidia_drm` or `nvidia_modeset` exists at preflight or after the workload.
