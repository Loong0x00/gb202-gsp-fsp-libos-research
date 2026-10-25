# FAN NOPTRS RegOps Route - 2026-07-28

Goal: test whether the GSP-only `NV2080_CTRL_CMD_GPU_EXEC_REG_OPS_NOPTRS`
path can read GB202 GPIO3 output-control register `0x0002120c`.

Known baseline:

- User-space direct call to `0x2080019d` on the currently loaded driver returns
  `NV_ERR_NOT_SUPPORTED` (`0x56`).
- The params buffer is untouched:
  `reg_status=0xa5`, `value=0xa5a5a5a5`.
- This matches the CPU-RM generated Subdevice table missing `0x2080019d`.

Local source change:

- Added `subdeviceCtrlCmdGpuExecRegOpsNoptrs_IMPL()` in
  `src/nvidia/src/kernel/gpu/subdevice/subdevice_ctrl_gpu_regops.c`.
- The wrapper does not run CPU-side RegOps validation/execution. It forwards
  the inline params command to `GPU_GET_PHYSICAL_RMAPI(pGpu)->Control(...)`
  using `pGpu->hInternalClient` and `pGpu->hInternalSubdevice`.
- Added a local generated-method row for `0x2080019d` in
  `src/nvidia/generated/g_subdevice_nvoc.c` with flags `0x10008` and params
  size `sizeof(NV2080_CTRL_GPU_EXEC_REG_OPS_NOPTRS_PARAMS)`.
- Added matching declarations in `src/nvidia/generated/g_subdevice_nvoc.h`.

Build result:

- `make -C driver_gpio_internal_610.43.03/src/nvidia` succeeded.
- `make -C driver_gpio_internal_610.43.03 modules NV_KERNEL_MODULES=nvidia`
  succeeded.
- Built module:
  `driver_gpio_internal_610.43.03/kernel-open/nvidia.ko`
- SHA-256:
  `b5248b730a475aae90083d22b073e02cfe70842fb8f3013f780600e69caa5eb8`
- `nm` confirms:
  `subdeviceCtrlCmdGpuExecRegOpsNoptrs_IMPL`
  and `subdeviceCtrlCmdGpuExecRegOpsNoptrs__EXPORT`.

Runtime state:

- The patched module has not been installed or loaded.
- Running `/home/user/4.sh --probe-only` still tests the old live module and
  therefore still returns `0x56`.

Prepared test entry:

- `/home/user/run-noptrs-regops-module-test.sh`
- Short alias: `/home/user/4.sh`

Modes:

- `bash ~/4.sh` installs the patched `nvidia.ko.zst` with a timestamped backup,
  then runs `depmod -a`. It does not unload the GPU driver and does not reboot.
- `bash ~/4.sh --probe-only` runs the fixed read-only probe and logs output.
- `bash ~/4.sh --rollback` restores the newest saved backup and runs
  `depmod -a`.

Important boundary:

Installing the module only changes the file used for the next driver load.
The live driver remains unchanged until a reboot or NVIDIA driver reload.
