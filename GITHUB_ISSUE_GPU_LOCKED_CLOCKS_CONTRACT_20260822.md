## NVIDIA Open GPU Kernel Modules Version

`610.57.04`; public source also checked at commit
[`e4a5faa2567f28c8eabe0ebb6422b6d0abcf37eb`](https://github.com/NVIDIA/open-gpu-kernel-modules/commit/e4a5faa2567f28c8eabe0ebb6422b6d0abcf37eb).

## Proprietary-driver comparison

Not applicable on this hardware. The GPU is Blackwell/GB202 and the R610 stack
uses the open kernel modules with GSP-RM.

## Operating System and Version

Arch Linux

## Kernel Release

`7.1.8-arch1-3` (stable Arch release kernel)

## Hardware: GPU

NVIDIA GeForce RTX 5090 (GB202, PCI ID `10de:2b85`)

## Describe the bug

`nvmlDeviceSetGpuLockedClocks(device, min, max)` and
`nvidia-smi --lock-gpu-clocks=min,max` expose a *locked range*, including an
explicit minimum. However, the published Blackwell/GSP call path has no
contract or return path that distinguishes these two outcomes:

1. the final clock is constrained to the installed range; or
2. GSP accepted a perf-limit request which a later arbitration stage may
   override below the requested minimum.

The current API returns `NVML_SUCCESS` for request installation. It does not
return or expose whether the final post-arbitration clock can obey the minimum.
That makes `min == max` observably different in semantics from a physical
clock lock, while the API name and its success result provide no way for a
caller to discover that distinction.

This report is based on the static call chain, not on a workload, an
overclock, or runtime telemetry.

## Static call chain

### 1. NVML's public entry point ends at a private backend

The exported R610.57.04 `nvmlDeviceSetGpuLockedClocks` symbol validates the
device and forwards the supplied `minGpuClockMHz` and `maxGpuClockMHz`
unchanged through a private backend vtable. That backend is not present in
this repository, so the public source begins at the RM ioctl boundary.

### 2. Linux RM accepts a generic control request

[`escape.c` accepts `NV_ESC_RM_CONTROL`](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/e4a5faa2567f28c8eabe0ebb6422b6d0abcf37eb/src/nvidia/arch/nvalloc/unix/src/escape.c#L793-L820).
The request contains only an object, command, parameter buffer and one status
field.

[`_nv04ControlWithSecInfo()` forwards the command and stores one returned
status](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/e4a5faa2567f28c8eabe0ebb6422b6d0abcf37eb/src/nvidia/src/kernel/rmapi/entry_points.c#L491-L512).
[`_rmapiRmControl()` validates and dispatches that generic command](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/e4a5faa2567f28c8eabe0ebb6422b6d0abcf37eb/src/nvidia/src/kernel/rmapi/control.c#L345-L430).
There is no host-side postcondition which checks an effective or physical
clock against the requested minimum.

### 3. Blackwell/GSP replaces the physical RM control handler

For a GSP client,
[`rpcRmApiSetup()` replaces `pRmApi->Control` with
`rpcRmApiControl_GSP`](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/e4a5faa2567f28c8eabe0ebb6422b6d0abcf37eb/src/nvidia/src/kernel/rmapi/rpc_common.c#L55-L80).

[`rpcRmApiControl_GSP()` serializes the opaque control command and parameters,
sends them to GSP, and waits](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/e4a5faa2567f28c8eabe0ebb6422b6d0abcf37eb/src/nvidia/src/kernel/vgpu/rpc.c#L10659-L10867).
When the RPC completes, CPU-RM
[`returns the single status reported by the GSP control handler`](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/e4a5faa2567f28c8eabe0ebb6422b6d0abcf37eb/src/nvidia/src/kernel/vgpu/rpc.c#L10868-L10942).

That status says whether the control handler accepted the request. The
published ABI has no second result describing whether subsequent policy,
power, reliability, thermal, or clock-stretching arbitration still satisfies
the requested minimum.

### 4. The relevant dGPU perf-limit implementation is missing

The published SDK comments direct dGPU perf-limit users to
`NV2080_CTRL_CMD_PERF_LIMITS_SET_STATUS_V2`, but its public declaration and
handler are absent. The tree contains only
[`CTRL_PERF_LIMITS_SET_STATUS_V2` as GSP RPC function 172](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/e4a5faa2567f28c8eabe0ebb6422b6d0abcf37eb/src/nvidia/inc/kernel/vgpu/rpc_global_enums.h#L175-L183).

Consequently, the only code that can define whether a locked-clock minimum is
a hard post-arbitration floor or merely one input client lives in the
unpublished userspace/GSP implementation. The public host code only reports
that the GSP request was accepted.

## Why this is an API bug

[NVIDIA's NVML/nvidia-smi documentation](https://docs.nvidia.com/deploy/nvidia-smi/index.html)
calls the pair a "desired locked GPU clock speed", while
[NVIDIA profiling documentation](https://docs.nvidia.com/cupti/12.9/special-configurations/special-configurations.html)
describes equal endpoints as a fixed frequency used to remove clock-rate
variability. The nvidia-smi document separately says that SW Power Cap can
reduce clocks below requested clocks, confirming that a later stage may
override the request, but it does not define what the locked minimum then
guarantees or how a caller can query that violation. Neither contract defines
`NVML_SUCCESS` as merely "a perf-limit client was installed, even if the
effective minimum may later be violated."

A range minimum that is not a post-arbitration lower bound is not usable as a
minimum. Returning success without an effective-range query also prevents
callers, profilers and control panels from distinguishing a satisfied lock
from an overridden request.

## Expected behavior

One of the following should be implemented and documented:

1. Enforce `minGpuClockMHz` after all clock arbitration whenever the call
   returns `NVML_SUCCESS`, returning a specific error when that postcondition
   cannot be guaranteed; or
2. Define the API as an advisory perf-policy request rather than a lock, and
   expose a supported query containing:
   - requested minimum and maximum;
   - effective post-arbitration minimum and maximum;
   - final granted clock;
   - whether either requested endpoint is currently violated;
   - the overriding limit/client and reason.

At minimum, successful request installation and successful enforcement must
not be represented by the same undifferentiated status.

## To reproduce by static inspection

1. Inspect the exported `nvmlDeviceSetGpuLockedClocks` API signature in the
   R610 NVML headers/library.
2. Follow `NV_ESC_RM_CONTROL` through the linked public source locations above.
3. Select the GSP client path in `rpcRmApiSetup()`.
4. Observe that `rpcRmApiControl_GSP()` returns only the GSP handler's request
   status.
5. Search the public tree for `CTRL_PERF_LIMITS_SET_STATUS_V2`: only the RPC
   enumeration and references from other SDK comments are published; there is
   no handler or post-arbitration minimum-enforcement contract to inspect.

## Bug incidence

Always. This is an unconditional property of the published API and GSP call
path, not a timing-dependent runtime report.

## nvidia-bug-report.log.gz

Not applicable to this static interface-contract report. No runtime failure or
machine state is used as evidence.
