# MODS 570.151 无 GPU 动态审计

日期：2026-07-14

## 结论

本阶段只证明了 MODS 的最早启动行为，不能证明完整测试路径安全。

- **VERIFIED**：即使参数只是 `-h`，`mods` 也会先探测 NVIDIA/MODS 驱动；它不是纯离线的 help 路径。
- **VERIFIED**：隐藏 `/proc/modules` 且提供假的 `/dev/mods` 后，第一个设备请求是只读性质的 API-version ioctl，随后因 `ENOTTY` 停止。
- **VERIFIED（到停止点为止）**：没有出现 `socket`、`connect`、子进程或文件写入；payload 挂载为只读，network namespace 也没有外部接口。
- **UNKNOWN**：通过首个 ioctl 后的行为、真实 thermal JSE 路径以及连接真实 GPU 后的副作用。本次故意没有让程序走到这些路径。
- **未做**：没有把真实 `/dev/mods`、`/dev/nvidia*`、`/dev/mem` 或 `/sys` 暴露给程序；没有加载模块、卸载 NVIDIA 驱动或执行任何 GPU 命令。

因此，这项动态检查不会把静态审计的 `NOT CLEARED` 改成“安全”。

## 隔离边界

实际使用的关键边界：

- bubblewrap `--unshare-all`：独立 user/pid/net/ipc/uts 等 namespace；
- `--cap-drop ALL`，无宿主 root 权限；
- 仅把 `/usr` 和 MODS payload 只读挂入；
- 新的空 `/dev`，只把 `/dev/null` 伪装成 `/dev/mods`；
- `/proc/modules` 被不可读的只读占位覆盖；
- 无 `/sys`、无 `/home`、无 NVIDIA 设备节点；
- `/tmp` 为 tmpfs，只有 `/out` 可写；
- 15 秒硬超时，`strace` 只记录 file/network/process/ioctl。

复现实验命令：

```sh
timeout --signal=KILL 15s bwrap \
  --unshare-all --die-with-parent --new-session --cap-drop ALL --clearenv \
  --ro-bind /usr /usr \
  --symlink usr/bin /bin --symlink usr/lib /lib --symlink usr/lib /lib64 \
  --proc /proc --dev /dev \
  --dev-bind /dev/null /dev/mods \
  --ro-bind /dev/null /proc/modules \
  --tmpfs /tmp \
  --ro-bind /home/user/rt_5090_project/mods_audit/static/extracted_inner /payload \
  --bind /home/user/rt_5090_project/mods_audit/containment/sandbox-out /out \
  --chdir /payload --setenv HOME /tmp --setenv PATH /usr/bin \
  --setenv LD_LIBRARY_PATH /payload \
  /usr/bin/strace -ff -qq -s 256 \
    -o /out/mods_help.strace \
    -e trace=%file,%network,process,ioctl \
    /payload/mods -h
```

## 观测结果

标准输出/错误：

```text
MODS arguments : -h
WARNING: Failed to open /dev/kmsg
ERROR: Can't get MODS kernel module API version
MODS end  : Tue Jul 14 11:00:02 2026  [0.193 seconds (00:00:00.193 h:m:s)]
```

决定性系统调用：

```text
openat(..., "/proc/modules", O_RDONLY) = -1 EACCES
stat("/dev/mods", {st_mode=S_IFCHR|0666, st_rdev=makedev(1, 3), ...}) = 0
access("/dev/mods", R_OK|W_OK) = 0
openat(..., "/dev/mods", O_RDWR|O_CLOEXEC) = 4
ioctl(4, _IOC(_IOC_READ|_IOC_WRITE, 0x78, 0x11, 0x8), ...) = -1 ENOTTY
```

`type=0x78 ('x'), nr=0x11, size=8` 对应公开 v4.29 驱动的
`MODS_ESC_GET_API_VERSION`。这说明程序在显示 help 之前就要求 MODS 驱动 ABI。

日志：

- `containment/sandbox-out/mods_help.strace.4`，SHA-256
  `fa885c2544630f0d48734462a37a69ca266b92b57d20a9fb728bb561b6186f7f`
- `containment/sandbox-out/mods_help.strace.5`，SHA-256
  `0b128f8c1f1c1ace4205f115669fac32a9c5126f83b7d4b256029be296c1fb61`

第二个 44-byte 文件只是辅助线程退出记录。

## 早期分支的补充观测

在同一类无 GPU sandbox 中曾分别验证：

1. 若让 `/proc/modules` 可见，MODS 发现宿主 `nvidia` 模块后要求先卸载它并停止。
2. 隐藏 `/proc/modules` 且完全没有 `/dev/mods` 时，MODS 会尝试执行
   `sh /payload/install_module.sh --insert`；当 sandbox 不提供 `/bin/sh` 时安全失败。
3. 提供假的 `/dev/mods` 后，程序进入上述 API-version ioctl，并在首个请求失败处停止。

这些行为与合法诊断工具的自动安装流程相符，但也再次说明：不能把 `-h`、
`-no_net` 或某个 thermal 参数视为天然的无副作用安全边界。
