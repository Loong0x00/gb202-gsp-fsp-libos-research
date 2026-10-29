# MODS 570.215 GB202 CONFIG0..5 read probe — design only

`gb202_config0_5_readonly.js` is a bounded MODS JavaScript probe, but it is **NOT a working GB202 read path**: it reached `Gpu.Initialize invalid object property` both in the no-GPU rehearsal and when invoked in a GPU passthrough guest; it never read a CONFIG register. The later **successful** one-line interactive read used MODS' own `mods.js` with `-skip_azalia_init -null_display -no_vga -no_gold -no_test` and `RegRd32(0x9a0290, 6)` at the MODS prompt. See `VFIO_ATTEMPT_20260924.md`. Do not rerun the broken standalone probe on a real GPU.

## Probe definition

- API: decoded MODS scripts use `GpuSubdevice.RegRd32(address)`; enumeration uses `GpuDevMgr.GetFirstGpu()` / `GetNextGpu()` (`mods_audit/static/decoded/all/gpuargs.js`, `mods.js`). Probe checks for exactly one subdevice, calls `Platform.Initialize()` / `Gpu.Initialize()`, reads with `subdev.RegRd32()` and calls `Gpu.ShutDown()`. GPU initialization/shutdown can modify hardware state even though no timing register write is requested.
- Addresses: 8 FBPA windows, `0x900290 + 0x4000*i` for `i=0..7`; within each, CONFIG0..5 at `+0,+4,+8,+0xc,+0x10,+0x14` (48 partition reads). Then six separate broadcast reads at `0x9a0290..0x9a02a4` (54 total). Broadcast output is explicitly labeled and must not be treated as an average of partitions. Address pattern is independently documented in `../write/REPORT.md` / this directory's `REPORT.md` as mVolt+ request evidence; CONFIG2..5 behavior on GB202 remains unvalidated.
- The script contains only `RegRd32` calls and formatted output. No register-write API, timing/clock control, stress test, looped polling, or retry is present. A run should take only a few dozen reads.

## Image and guest prerequisites (not performed)

已安装 Ubuntu 客体的底盘是只读 `/home/user/rt_5090_project/vm_mods_lab/base.qcow2`；曾经跑通 MODS 570.215 的独立客体写层位于 `vm_mods_lab/run-mods570215-diagnostic-20260825/overlay.qcow2`，其自身还有上一层 backing。`MOD570_215.img` 经 `file`/`fdisk` 证实是**带 MBR 的 3.8 GiB FAT32 镜像**，不能未经检验当作已安装 Ubuntu VM 的启动盘。不要直接改写任何现有磁盘；应先校验 backing 链，并在已经验证过的客体写层上另建一次性写层。既有 diagnostic 日志在 `vm_mods_lab/mods570215-diagnostic-20260825-logs/`。目标 GPU 只可在 host 已独占交给 VFIO 后提供给该客体。 Keep the guest NVIDIA proprietary driver absent and ensure its MODS kernel module/tooling and MODS 570.215 binary are available.

The checked-in `user-data` disables guest networking and explicitly says `ssh.install-server: false`; thus the image recipe does **not** provide SSH. Initial access needs the VM's serial console (the image is configured for ttyS0) or a separately reviewed offline guest setup for SSH server/keys. Do not assume host SSH service implies guest SSH reachability. For later SSH attach, first verify the guest has an SSH daemon, an authorized key, and a reachable isolated management interface; do not expose it to an untrusted network. Host linger/SSH checks at preparation time are reported by the parent task, not prerequisites for a GPU read.

Probe 从只读 ISO 拷入隔离客体，由串口交互运行。在**无 GPU** 的 MODS 570.215 VM 中，`-s` 成功载入此纯文本 `.js` 并执行到 `Gpu.Initialize()`，随后报 `Gpu.Initialize invalid object property`；真卡实验复现相同错误，说明**该独立脚本的初始化/生命周期方式不适用**。它的寄存器访问和清理逻辑从未成功执行；不能把无卡编译/入口成功当成 GPU 已验证。下面的超时包装仅在无卡 VM 测过启动流程，真卡执行仍需完整预检：

```sh
sudo timeout --signal=INT --kill-after=10s 90s ./mods -nc \
  -s ./gb202_config0_5_readonly.js
```

Capture stdout and exit status to a guest-local log, then copy the log out after shutdown. Do not append `gputest.jse`, `-pstate`, clock, voltage, stress, or write options. If this MODS build rejects the standalone `-s` script or enumerates unexpected devices, stop; do not substitute a test workload. Validate output has exactly 8 x 6 partition rows and 6 broadcast rows per intended GPU subdevice, addresses match the formulas, values are 32-bit hex, and the command exits before the 90 s timeout. An incomplete log, API exception, timeout, or anything beyond the expected subdevice set is not a valid readback.

## Safety / initialization caveat

This is read-only at the script/API-call level, **not a guarantee of zero GPU writes**. Static decoded helpers show that direct `RegRd32` delegates to the subdevice API, but that only establishes the requested read operation. Starting MODS and creating/initializing its device/subdevice (and its kernel driver/RM bring-up) may initialize the GPU and perform setup writes before this JSE runs. JSE import/startup/driver initialization side effects cannot be ruled out from the decoded API snippet. The exact guest MODS 570.215 execution path must be audited before claiming “no GPU writes”; use a disposable, isolated VFIO guest and accept that initialization is not strictly write-free. This is not a host-side raw MMIO probe and is not safe to run against the desktop-bound GPU.

The read-only script will still be subject to a wall-clock watchdog (`timeout`) and a VM-level recovery path. Before any later execution, confirm a recoverable guest snapshot, GPU exclusively bound to VFIO, host recovery/rebind path, guest serial console, and that no other GPU workload is active. This document does not authorize that later launch.
