# Black Myth: Wukong 480p fixed-cost probe — 2026-08-01

## Question

The prior native-resolution sweep fitted:

`GPU frame time (ms) = 6.1543 + 5.5908 * megapixels`

This probe asks whether the approximately 6.15 ms resolution-independent term is CPU work that leaves the GPU waiting, or graphics-driver/GPU-side backpressure.

## Setup

- 854x480 virtual display
- Full ray tracing level 3
- Native 100% sampling, frame generation off, cinematic settings
- RTX 5090, Ryzen 9 9950X3D
- 10.031187-second mid-benchmark capture
- Nsight Systems 2026.1.3 injected through the Steam launch command into the Proton process tree
- CPU call-stack sampling disabled because Nsight's Wine/Proton DWARF path crashed its protobuf collector
- Vulkan API/GPU workload events were requested but were not collected through the D3D12 -> vkd3d-proton boundary

## Confirmed observations

During the instrumented run, the frame cadence was about 10 ms. This is slower than the uninstrumented 109.7 FPS run and must not be used as a clean performance result.

| Thread | Observation over 10.031 s |
|---|---:|
| RenderThread 1 | 19,594 ioctl calls; 6,013.159 ms total inside ioctl |
| RHIThread | 12,972 ioctl calls; 4,503.672 ms total inside ioctl |
| RenderThread long calls | 975 calls >= 4 ms; mean 5.196 ms; mean start spacing 10.269 ms |
| RHIThread long calls | 1,001 calls >= 2 ms; mean 3.472 ms; mean start spacing 10.002 ms |
| RHISubmissionThread | 9,309.21 ms total inside ioctl |
| RHIInterruptThread | 9,600.83 ms total inside ioctl |

The RenderThread and RHIThread each enter a long driver call approximately once per instrumented frame. They are not spending the entire fixed interval running CPU instructions to construct the next frame. They are blocked inside the graphics-driver path for substantial, periodic portions of the frame.

## Interpretation

### High-confidence inference

The approximately 6.15 ms fitted intercept is not primarily a conventional CPU-compute bottleneck that starves an otherwise idle GPU. The rendering pipeline shows strong driver/GPU queue backpressure: UE's RenderThread and RHIThread reach the graphics path and then block there.

This is consistent with resolution-independent GPU work and synchronization such as fixed scene/geometry processing, RT acceleration-structure work, fixed dispatch/pass overhead, queue/fence dependencies, or driver serialization.

The 5.196 ms RenderThread wait must not be added to the reported GPU time. CPU and GPU work overlap; the periodic wait is evidence of backpressure, not an independently additive cost bucket.

### Still unknown

This capture does not identify which GPU pass consumes the fixed work or measure literal GPU queue-empty bubbles. Nsight successfully captured the Proton process tree and OS-runtime calls but did not collect Vulkan events from vkd3d-proton. Kernel scheduling data was also unavailable because `kernel.perf_event_paranoid=2`, and NVIDIA GPU hardware counters require profiling privilege (`RmProfilingAdminOnly=1`).

The remaining exact split is:

1. resolution-independent commands actively executing on the GPU;
2. GPU queue idle gaps caused by driver/queue synchronization;
3. present/frame-latency pacing.

## Artifacts

- `wukong_480p_timeline_nostack_20260801.nsys-rep`
- `wukong_480p_timeline_nostack_20260801.sqlite`
- `wukong_resolution_sweep_20260801.md`

The temporary Steam launch option was removed after capture. The original game INI and save hashes were preserved, and no new NVIDIA Xid was observed.
