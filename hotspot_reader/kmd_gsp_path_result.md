# Host KMD / GSP hotspot path audit (driver 610.43.03)

Scope: RTX 5090 / GB202 at `0000:01:00.0`, Arch Linux, NVIDIA open KMD
610.43.03.  All live probes were GET/read-only operations.  No module was
rebuilt, unloaded, or replaced.

## Result

There is no current junction/hotspot numeric value in the Host RM paths found
in this driver.  Therefore a small procfs/sysfs patch at this layer would have
no verified value to expose.  Patching was intentionally skipped instead of
exporting edge, memory, a threshold, or an unverified register under a hotspot
name.

This is a **VERIFIED negative** for the interfaces and shared-memory fields
below, not proof that the on-die value does not exist inside GSP/PMU or the
hardware thermal controller.

## Public Thermal System path

The interface is defined in
`src/common/sdk/nvidia/inc/ctrl/ctrl2080/ctrl2080thermal.h`:

* API version/revision: 1/0 (lines 38--39)
* Host command: `NV2080_CTRL_CMD_THERMAL_SYSTEM_EXECUTE_V2 = 0x20800513`
* physical/GSP command: `0x20808513` (lines 135--137)
* available-sensors opcode: `0x500` (line 227)
* current-reading opcode: `0x1500` (line 271)
* maximum instruction count: 32 (line 404)

The live read-only probe reported `availableSensors = 1`.  Sensor 0 equalled
the `nvidia-smi` GPU/edge reading.  Every operation on indices 1 through 31
returned instruction result `0x0000ffff`.  In particular, index 1 is not just
rejected by a Host cache: the Host handler forwards a cache miss to command
`0x20808513`, so this also exercises the physical GSP handler.  Full output is
in `thermal_execute_v2_result.md`.

The Host implementation at
`src/nvidia/src/kernel/gpu/subdevice/subdevice_ctrl_gpu_kernel.c:4264` maps a
sensor only to these shared-data types: GPU, MEMORY, POWER_SUPPLY, BOARD.  It
reads `temperatures[type]` at line 4306; cache misses and unsupported types are
forwarded to GSP at lines 4341--4345.

## RUSD shared telemetry

`src/common/sdk/nvidia/inc/class/cl00de.h:234` defines only these public sensor
identities: GPU, MEMORY, BOARD, POWER_SUPPLY.  The shared temperature type enum
at line 244 additionally contains HBM.  Each value is a timestamp plus
`NvTemp`; the array is declared at line 465.  There is no HOTSPOT or JUNCTION
entry.

The exact in-memory slots were also tested through the read-only RUSD copy path
inside `/usr/lib/libnvidia-ml.so.610.43.03`:

| shared offset | type | live result |
|---:|---|---|
| `0x908` | GPU | valid, 42.754 C while public edge was 43 C |
| `0x918` | MEMORY | valid, 56.0 C |
| `0x928` | BOARD | `NVML_ERROR_TIMEOUT` (10), no value |
| `0x938` | POWER_SUPPLY | `NVML_ERROR_TIMEOUT` (10), no value |
| `0x948` | HBM | `NVML_ERROR_TIMEOUT` (10), no value |

The five slots are 16 bytes apart.  For binary auditing, library-relative VA
`0xe73f0` is the generic RUSD copy helper, `0xe77a0` is
`cDeviceGetRusdTemperature` (accepts only GPU and reads `0x908`), and `0xe76a0`
is `cDeviceGetRusdTemperatureHbm` (reads `0x948`).  These addresses apply only
to this exact library build.

The valid MEMORY value agrees with the separately enumerated private
`primary MEMORY`/VRAM channel.  It must not be called GPU hotspot merely because
it exceeds edge at idle.

## Throttle and RPC paths

The RUSD throttle record exposes reason bits, not the temperature that tripped
them.  In `cl00de.h:91`, bit 5 is software thermal slowdown and bit 6 is
hardware thermal slowdown.  No junction numeric field accompanies either bit.

The physical-control path is the generic `rpcRmApiControl_GSP` selected at
`src/nvidia/src/kernel/rmapi/rpc_common.c:76`.  Its implementation begins at
`src/nvidia/src/kernel/vgpu/rpc.c:10659` and generically copies returned control
parameters at lines 10870--10911.  No thermal-current event or persistent Host
field was found in this RPC layer.

The build configuration supports that division:
`src/nvidia/generated/rmconfig.h:732--733` sets `RMCFG_MODULE_THERM=0` and
`RMCFG_MODULE_KERNEL_THERM=1`.  The complete thermal policy/implementation is
not in Host RM; the open side is the kernel-facing wrapper and cache.

Consequently the observed 107 C protection may be implemented by a GSP/PMU or
hardware comparator while Host KMD receives only a throttle-reason bit.  That
explanation is **INFERRED**; the exact private comparator path remains
**UNKNOWN**.

## Other plausible Host leaks checked

* `nvmlDeviceGetTemperatureV` version 1 (12-byte parameter struct) accepts only
  sensor type 0.  Types 1 and above return `NVML_ERROR_INVALID_ARGUMENT` (2).
  An incorrect structure version returns 25; that is a version error, not a
  hidden sensor result.
* Generated protobuf metadata declares repeated `GpuInfo.junction_temp` field
  6 at `src/nvidia/generated/g_nvdebug_pb.h:164`, but the only system-info
  writer in `src/nvidia/src/kernel/diagnostics/journal.c:1470` writes GPU ID,
  UUID, PCI device ID, PMCBOOT0, and subdevice ID, never junction temperature.
* A correctly allocated read-only NVD dump for component
  `NVDUMP_COMPONENT_ENG_THERMAL` (enum value 7 in
  `src/common/sdk/nvidia/inc/nvdump.h:50`) returned only the generic GPU/GSP
  header.  It was byte-identical to FAN, VOLT, and GSP component dumps and did
  not change while edge moved from 61 to 64 C.
* The platform-request TGPU block initializes/samples ACPI thermal **limit** and
  period fields; it has no current-TGPU sample producer.

## Patch decision and recovery

No patch was produced or installed, so there is nothing to recover.  Once a
GB202 current-junction BAR0 register or GSP control is independently verified,
the minimal KMD change would be a read-only procfs/sysfs wrapper around that
source.  Until then, such a patch can only mislabel another quantity.

