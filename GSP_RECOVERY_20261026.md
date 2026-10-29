# GSP 恢复复核与启动修复 — 2026-10-26 03:29–03:42 +08

## 当前结论

**RTX 5090 / GB202 的 GSP 正常，GPU 已可查询并执行 CUDA。没有刷写、GPU 复位或整机重启。**

此前 `SESSION_20261025_NIGHT_FULL_REPORT.md` 所称「GSP 永久锁死、需要 SPI 编程器」不成立：当时的失败日志不能证明持久锁死，更不能保证刷 SPI 一定可修。本次在现有启动周期，仅用官方工具补回缺失的 `/dev/nvidia0`，白名单内的 `nvidia-smi` 就立即成功。

**本次修复并未解释 10-25 最初事故的全部原因，也未验证修复后再次冷启动。** 当前软件入口问题、历史 COT 启动失败、原有 stale-WPR2 问题应分开记录。

**后续 GLM-5.3 原始会话复核更正：旧记录中的最初卡死和若干复位后失败确实属实，不能被本次补节点成功否定。** 同时查到 00:11 那次重启后，00:12–00:25 的授权水冷服务已多次成功查询 GPU 实时数据；GLM 普通终端的 sudo 查询仍受 guard 限制，漏判了这一恢复阶段。之后继续复位又发生真实初始化失败，最后一次重启后则剩下节点/错误绑定检查问题。详见 [GSP_GLM53_CONTEXT_AUDIT_20261026.md](GSP_GLM53_CONTEXT_AUDIT_20261026.md)。此前本助手将整晚故障说成纯软件入口问题，表述过头，以该分阶段复核为准。

## 1. 实测，不靠推测

证据目录：
`/home/user/rt_5090_project/gsp-recovery-20261026-2jdEH6/`

- 当前内核：`7.2.11-arch1-1`。
- GPU：`0000:01:00.0`，ASUS RTX 5090，VBIOS `98.02.2E.40.E0`。
- 起止 boot ID 相同：`ff7e30be-843c-45ab-9167-b3938e5b56f0`。
- AMD 桌面 framebuffer 起止均为 `0 amdgpudrmfb`。
- 修复前只有 `/dev/nvidiactl`，**没有 `/dev/nvidia0`**。
- `sudo gpu-allowlist run gpu-status` 返回 `No devices were found`，退出码 6，内核无新增报错。
- `sudo nvidia-modprobe -c 0` 创建 minor 0；随后刷新既有 guard。
- 再次运行同一个 `gpu-status` 入口立即退出 0，GPU 30°C、32607 MiB、600 W 上限、零计算进程。
- 完整 `nvidia-smi -q`：**GSP Firmware Version 615.78.08**，GPU Recovery Action **None**。
- CUDA 13.4 / `sm_120` 功能测试：明确核对 PCI 位置，分配 1 MiB，执行真实 CUDA kernel，回读逐元素校验；**三轮全部 PASS**。
- 最后又连续三次 `gpu-status`，全部成功。
- 修复/验证窗口无新增 NVRM/Xid 错误。
- 水冷服务恢复 active/enabled；GPU 30°C、热点 34°C、泵约 2030 RPM、冷排约 899 RPM，`failures=0/0`。

关键原始文件：
- `gpu-status.initial.log` / `.exit`
- `node-create.exit`、`nodes.after-create`
- `gpu-status.after-node.log` / `.exit`
- `nvidia-smi-q.verified.txt`
- `cuda_smoke.cu`、`cuda-smoke.result`
- `gpu-status.final-{1,2,3}.log`
- `kernel-repair-window.log`、`cooling.final.log`

## 2. 找到的启动配置问题

### 2.1 实验黑名单未撤销

`/etc/modprobe.d/zz-cot-tmp.conf`，mtime 10-23 19:35，仍然包含：

```text
blacklist nvidia
blacklist nvidia_uvm
blacklist nvidia_drm
blacklist nvidia_modeset
```

本次开机的 `systemd-modules-load` 明确记录：

```text
Module 'nvidia_drm' is deny-listed (by kmod)
```

这阻断了原有 `/etc/modules-load.d/70-nvidia-graphics.conf` 的加载请求，也跳过发行版以 `nvidia_drm` 模块事件触发的节点准备链。不过，**不能把黑名单单独认定为 `/dev/nvidia0` 缺失的直接原因**：后续核对匹配版本 `nvidia-modprobe` 源码，发行版规则中的 `-c0 -u` 走 UVM 分支，只创建 `/dev/nvidia-uvm` 和 `nvidia-uvm-tools`，并不创建基础 `/dev/nvidia0`。

更直接的机制是：内核 core 模块通过 `register_chrdev_region` / `cdev_add` 注册设备号，并不在该路径自动创建 `/dev/nvidia0`；`/dev` 是 devtmpfs，节点不会跨重启保留，需要用户态特权工具补建。GPU 状态任务启用了 `NoNewPrivileges=yes`，其中的普通用户不能靠 setuid `nvidia-modprobe` 提权执行 `mknod`。桌面使用 AMD 且 NVIDIA 被隔离，水冷特权服务又已被禁用，原有补建路径不能可靠兜底。故新增固定 root 预检，而不是取消 `NoNewPrivileges` 或白名单。

后续查到 GLM 原会话 JSONL 第 1114 行：10-25 23:52 恢复过程中明确执行过删除 nvidia0 等节点，随后只用 `nvidia-modprobe -c 0 -u` 补 UVM。不过它在 00:07–08 又执行过手工 mknod，00:12 列表也明确有 nvidia0；之后还经历多次重启。因此这个历史删除不能单独解释最后一次开机的缺节点，不能声称它跨重启一直未恢复。详见原会话复核报告。匹配版本源码证据保存在 `gsp-recovery-20261026-2jdEH6/node-creation-followup/`，来自 NVIDIA 官方 `nvidia-modprobe` 仓库的 `615.78.08` 标签。

将该文件保留但停用为：
`/etc/modprobe.d/zz-cot-tmp.conf.disabled-gsp-recovery-20261026`

没有删除其他黑名单、VFIO 配置或修改模块参数。

### 2.2 今日重装导致源码与正在使用的模块不一致

pacman 日志显示 00:20 把此前本地包 `615.78.08-1.1` 降回官方 `615.78.08-1`，之后重复重装。安装源码恢复成原版 WPR2 早期拒绝逻辑，但磁盘与内存中的 core 模块仍是原有 WPR2-only 基线，srcversion：

`4200B1C66D4D12038311105`

DKMS 当时仅显示 `built`，安装日志报已有同版本模块、需要 `--force`，退出 6。继续这样使用会导致下一次重建丢失既有 WPR2 修复。

已恢复原先已知的本地包：
`/home/user/nvidia-615.78.08-wpr2-only-20261022-190702-Z3vTcf/package-build/nvidia-open-dkms-615.78.08-1.1-x86_64.pkg.tar.zst`

恢复前验证 `kernel_gsp.c` 相对当前官方源码**仅有既有的一行 WPR2 host guard 修改**。这是保留历史工作基线，不是本次发现的新固件修复。该修改不清除硬件 WPR2，也不修改签名固件。

- 使用本次事务私有 hook 目录，避免全局自动重建无关的 `7.1.5-dirty` 内核。
- 仅为当前 `7.2.11-arch1-1` 强制重新构建、签名并安装五个 NVIDIA 模块。
- 重建 core 模块 srcversion 与正在运行的已验证基线一致。
- `dkms status` 当前内核为 `installed (Original modules exist)`；后者是强制安装保留的原模块归档提示。
- `pacman -Qkk nvidia-open-dkms`：4643 个文件，0 变化。
- `depmod` 与 `mkinitcpio -p linux` 成功；initramfs 中不再有活动 COT 临时黑名单。
- 没有卸载/重载正在运行的 core 模块。重建件已安装到磁盘，但未通过再次启动加载验证。

## 3. 防止状态/水冷入口再次因缺节点而失败

新增固定 root helper：
`/usr/local/libexec/gpu-allowlist-nvidia-node-prepare`

它只做以下工作：
1. 拒绝非 root 或额外参数。
2. 若 `0000:01:00.0` 不归 NVIDIA 驱动持有，直接跳过，不从 VFIO 抢卡。
3. 核对目标在 `/proc/driver/nvidia/.../information` 中的 minor 为 0。
4. 用官方 `nvidia-modprobe -c 0` 补基础设备节点，并刷新现有 guard。
5. 核对两个字符设备存在。

不手写 MMIO、不复位、不松开白名单、不加载 DRM/UVM 或运行负载。

限定接入点：
- `/etc/systemd/system/gpu-allowlist-task-gpu-status-.service.d/20-device-nodes.conf`
- `/etc/systemd/system/waterloop-fan-control.service.d/97-nvidia-device-nodes.conf`

状态任务获得固定特权预检，主进程依旧是普通用户且 `NoNewPrivileges=yes`。水冷预检使用忽略失败前缀，**预检失败不能阻止原有散热/故障保护启动**。水冷主脚本、曲线和失败保护未修改。

验证：shell 语法、正常幂等执行、额外参数拒绝、独立 mount namespace 模拟未绑定目标时安全跳过、`systemd-analyze verify`、实际状态任务执行预检成功。没有通过删除正在使用的真实设备节点来测试。

## 4. 保留的边界

以下文件 SHA256 起止一致：
- `/etc/gpu-allowlist/tasks.json`（保留全部六个既有任务）
- `/usr/local/sbin/waterloop-fan-control`
- `/etc/pacman.conf`

Guard 仍 attached；普通会话打开 `/dev/nvidia0` 仍被拒绝。设备节点最终为 `root:gpu-allowlist 0660`。CUDA 与完整固件查询使用短命、普通用户的固定诊断 service，位于已有授权 slice；没有增加永久任务权限，结束无残留诊断 service。

没有进行：GPU reset/FLR/SBR、PCI unbind/remove、原始寄存器扫描、PRC/COT/HULK 写入、EEPROM/SPI 刷写、温控策略修改、桌面/GDM 重启、整机重启。没有停止其他计算任务。

本次是短时功能验证，不是长时间压力测试，也不是冷启动验证。此前真正的最初崩溃触发原因与原有 WPR2 状态来源仍未解决。

## 5. 历史错误不应混为一谈

保留了 boot 0/-1/-2/-3 的完整 kernel journal。前两次恢复尝试确有：
- COT command `0x14` 返回 `0x177`；
- `unexpected WPR2 already up`；
- PBI/osInitNvMapping 失败；
- 手工复位后 temporary fallen-off-bus。

这些是历史不同阶段的真实错误，但**不能推出目前仍不能启动，更不能推出 fuse 永久锁死**。

匹配版本官方 `kern_fsp_retval.h` 不包含 `0x177` 的符号释义，不能自行把它解码成永久封锁。额外查到 QubesOS #10036 的其他 Blackwell 用户也遇到 `0x177`，部分配置调整后可恢复；那是虚拟化案例，不直接证明本机历史故障原因。

联网原文存于证据目录 `upstream/`：
- https://raw.githubusercontent.com/NVIDIA/open-gpu-kernel-modules/615.78.08/src/nvidia/inc/kernel/gpu/fsp/kern_fsp_retval.h
- https://docs.kernel.org/gpu/nova/core/fsp.html
- https://github.com/QubesOS/qubes-issues/issues/10036

## 6. 备份与后续查询

root-only 修复前备份：
`/var/tmp/nvidia-gsp-recovery-20261026-MhDPyA/`

包括五个原模块、原 initramfs、临时黑名单、任务配置、原源码/DKMS 树。`hooks/` 只用于本次 pacman 命令，不是全局 hook 配置。不要将备份整体覆盖正在运行的系统；如需回滚应逐项审查。

日常检查使用原来的授权入口：

```sh
sudo gpu-allowlist run gpu-status
```

普通 `nvidia-smi` / `sudo nvidia-smi` 仍可能被既有 cgroup 白名单拦截；那不是 GSP 启动故障。无需为当前可用状态重启。将来用户方便重启后，可用以上入口和水冷日志进行冷启动复核。
