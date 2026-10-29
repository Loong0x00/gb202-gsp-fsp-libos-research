# RTX 5090 sub-1 V V/F +15 MHz stability run

Date: 2026-07-29

## Configuration under test

- Active LACT config SHA-256: `72c89a17b3f2467e474e38173992467f2622fecfa29c94fffe2e86ada9c34b9f`
- Core clock request range during tests: `0,3030 MHz` (upper bound only in practice)
- Memory clock locks: reset / absent
- Modified V/F points:
  - 935 mV: 2915 MHz
  - 940 mV: 2920 MHz
  - 945 mV: 2925 MHz
  - 950 mV: 2930 MHz
  - 960 mV: 2950 MHz
  - 965 mV: 2960 MHz
  - 970 mV: 2970 MHz
  - 975 mV: 2980 MHz
  - 985 mV: 3000 MHz
  - 990 mV: 3010 MHz
  - 995 mV: 3020 MHz
  - 1000 mV: 3030 MHz

## Cyberpunk 2077

- 10/10 benchmark rounds completed with exit code 0.
- Resolution: 6144x3456.
- Path tracing enabled.
- 972 frames per round.
- Average FPS: mean 11.7911, range 11.7422--11.8862, sample SD 0.0388.
- Minimum FPS: mean 10.2436, range 10.2045--10.2880.
- Maximum FPS: mean 13.6587, range 13.5524--13.7830.
- Average GPU clock: mean 2897.57 MHz, per-round range 2895.2--2901.1 MHz, sample SD 1.82 MHz.
- Average GPU voltage: mean 973.07 mV, per-round range 972.1--975.2 mV.
- Average one-second board power: mean 555.28 W, per-round range 554.2--557.6 W, sample SD 0.98 W.
- No progressive clock/power drift and no late-round application failure were observed.

## FurMark Vulkan

- Requested render duration: 900 seconds at 3840x2160.
- The render workload reached the requested end time without watchdog intervention.
- Full-load NVML samples (GPU utilization >=90%): 16,564.
- GPU utilization during stable samples: 99.9% average.
- GPU clock: 2197--2475 MHz, 2370.3 MHz average.
- Instantaneous board power: 508.4--598.9 W, 576.9 W average.
- One-second average board power: 576.3 W.
- GPU voltage: 850--970 mV, 859.5 mV average in stable LACT samples.
- Only the software power-cap reason was active; no hardware, thermal, power-brake, or software-thermal slowdown was reported.
- FurMark exited with its known post-duration segmentation fault (`rc=139`) during teardown. This occurred after the requested render interval and is not evidence of a GPU workload failure.

## Safety and validity notes

- No NVIDIA Xid, GPU-lost, or reset-required message occurred during the suite.
- The thermal watchdog did not trigger.
- The case side panel was removed partway through FurMark. Therefore FurMark temperature trends are not a controlled comparison and are not used for the V/F stability conclusion.
- Graphics and memory clock locks were reset after the suite.
- Passing this suite establishes stability for this approximately 35-minute mixed workload, not unconditional stability for every game or arbitrarily long runtime.

## Conclusion

The tested +15 MHz sub-1 V curve passed 10 consecutive Cyberpunk 2077 path-tracing benchmark rounds and a 15-minute Vulkan FurMark render interval without a workload crash, Xid, reset, watchdog event, or progressive telemetry drift.
