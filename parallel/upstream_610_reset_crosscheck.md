# NVIDIA 官方 610 开源快照的 reset/FSP 交叉检查

日期：2026-07-21  
状态：完成；仅浏览 NVIDIA 官方 GitHub 源码/发布页

## 范围与安全边界

本轮只查看 NVIDIA 官方 `open-gpu-kernel-modules` 仓库和 610.43.02 tag，目的
是确认本地 610.43.03 源码是否已被更晚的公开 610 快照淘汰，以及公开 upstream
是否新增了 GB202 L2 shadow 的 reset-domain 说明。

没有下载或运行驱动，没有访问 `/dev/nvidia*`、GPU、PCI/BAR/MMIO，没有执行
reset、模块或固件操作。网页搜索只采用 NVIDIA 官方仓库这一手来源。

## FACT

1. NVIDIA 官方仓库首页在本次检查时标注源码版本为 `610.43.02`，release 页面
   也把 `610.43.02` 标为该仓库当前 latest release：
   - <https://github.com/NVIDIA/open-gpu-kernel-modules>
   - <https://github.com/NVIDIA/open-gpu-kernel-modules/releases>
2. 官方 `610.43.02` tag 的 `ctrl0080bif.h` 与本地 610.43.03 关键定义一致：
   `SBR=2`、`FUNDAMENTAL=3`、`BOOT_DEVICE_FUSE=4`、`BOOT_DEVICE=5`、
   `BASE=8`，并明确注明 Blackwell 起不支持 fundamental，应改用两种 boot
   reset：
   <https://github.com/NVIDIA/open-gpu-kernel-modules/blob/610.43.02/src/common/sdk/nvidia/inc/ctrl/ctrl0080/ctrl0080bif.h>
3. 官方 tag 公开了与本地相同类别的 GB202 FSP/BIF 文件，但没有在上述 control
   schema 中公开 latch/raw/status/effective 的 reset-retention 字段：
   - <https://github.com/NVIDIA/open-gpu-kernel-modules/blob/610.43.02/src/nvidia/src/kernel/gpu/fsp/arch/blackwell/kern_fsp_gb202.c>
   - <https://github.com/NVIDIA/open-gpu-kernel-modules/blob/610.43.02/src/nvidia/src/kernel/gpu/bif/arch/blackwell/kernel_bif_gb202.c>
   - <https://github.com/NVIDIA/open-gpu-kernel-modules/blob/610.43.02/src/nvidia/src/kernel/gpu/bif/arch/hopper/kernel_bif_gh100.c>

## INFERENCE

- 截至本次检查，没有一个比本地 610.43.03 更晚的**公开 Linux 610 源码快照**
  可用来补齐 reset-domain 语义；本地源码仍是当前主线的合适公开基线。
- 本地另有 610.74 Windows/GSP artifact 的交叉检查，但它不是一个更晚的官方
  Linux OpenRM 源码树，不能替代缺失的 FSP/hardware consumer。

## UNKNOWN / 限制

- “官方仓库当前没有更晚源码”不表示 NVIDIA 内部 610 分支、Windows 包、FSP
  固件或未来 release 没有更完整实现。
- GitHub 网页与仓库搜索不能证明私有 firmware consumer 不存在。
- 本轮只确认公开版本边界和关键 schema 一致，没有把 negative search 升级成
  硅级 reset 行为证明。

## 最小结论

截至 2026-07-21，NVIDIA 官方公开的 610 Linux 源码最新快照仍为 610.43.02；
它与本地 610.43.03 在相关 reset taxonomy 上一致，也没有公开 GB202 四组 L2
shadow/status 状态的 reset-domain 合同。因此继续等待“更高版本公开源码自然给出
答案”目前没有现成材料；核心缺口仍在未公开的 FSP/GFW/hardware consumer。
