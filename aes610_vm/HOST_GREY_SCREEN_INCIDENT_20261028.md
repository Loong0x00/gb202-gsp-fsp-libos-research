# 2026-10-28 灰屏/卡死事件取证

## 结论

现有日志不支持直接定性为“guest 内 GSP payload 导致主机内核 panic”。上一轮内核日志在强制重启前没有 `Kernel panic`、`Oops`、`hung task`、RCU stall 或 watchdog lockup 记录。已证实存在 VFIO handoff 失败恢复与 QEMU 启动竞争：主机显示/NVIDIA 客户端和 guest 同时尝试使用同一块 RTX 5090，随后出现反复 NVIDIA probe、VFIO reset 与显示异常。该竞态足以解释灰屏和卡死；不能排除无日志的内核 hang，但没有证据证明它。

## 时间线（boot -1）

- `06:12:20.264`：`sudo .../rtx5090-vfio-enter-live` 开始。
- `06:12:20.371`：GDM 停止。
- `06:12:23.60`：`systemd-logind` 重启。
- `06:12:25.742`：GDM 被重新启动。
- `06:12:26.466`：NVIDIA 模块卸载。
- `06:12:26.571`：GPU/audio 绑定 `vfio-pci`。
- `06:12:26.670`：`rtx5090-vfio-prepare-run`。
- `06:12:26.829`：QEMU `aes610-vm` 启动，run id `20261028_061226`。
- `06:12:28` 至强制重启前：持续出现 `NVRM: GPU ... is already bound to vfio-pci`、模块加载/卸载及多次 `vfio-pci ... resetting/reset done`。

关键矛盾：GDM 在 QEMU 启动前约 1 秒已被恢复，但 VM 仍继续启动。失败恢复与 VM 启动没有互斥。

本次没有取得 guest 内执行 `guest_fullctx_meta_rotation.sh` 的证据；事故发生在 VM 启动及宿主恢复竞态阶段，不能把原因归给该 payload。

## 当前状态（重启后）

- 无 `aes610-vm` / `rtx5090-vfio-lab` 活动 VM。
- GPU `0000:01:00.0` 已回到 `nvidia`；音频已回到 `snd_hda_intel`。
- GDM active。
- `20261028_061226` overlay（8.5 MiB，serial.log=0）已取证并删除；无本次 overlay 残留。
- immutable base `/home/user/rt_5090_project/vfio_production_lab/guest/arch-gpu-base.qcow2` mode `0444`。
- 当前启动未发现同类 panic/Oops/hung-task。

## 已加入的防护（未做硬件测试）

1. `host/rtx5090-vfio-enter-live`：一旦 handoff 已 armed 或 QEMU 已存在，失败恢复不再自动重启 host GPU 客户端；保留 armed 状态，要求显式 `leave-live` 恢复。
2. `host/rtx5090-vfio-preflight`：`gdm.service`、`lactd.service`、`nvidia-persistenced.service`、`waterloop-fan-control.service` 任一仍 active 时拒绝启动 guest。

所有 GPU/VM 实验已暂停；上述修改只做了 Bash 语法检查，未再次执行 VFIO 切换。
