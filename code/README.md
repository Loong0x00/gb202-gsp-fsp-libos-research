# code/ — 自研源码(研究配套代码)

这里收录**本人编写的**、与文档结论配套的核心源码。全部只含源文件:不含 `.ko`/`.o` 等编译产物,不含固件二进制,不含 NVIDIA 专有源码(MODS/驱动树均未收录)。

## gsp-qemu/ — QEMU GSP 模拟实验室

对应文档:`../gsp_qemu/docs/`(`LAB_BOOT.md`、`MPU_MODEL.md`)与 `AUTHORITATIVE_STATUS.md` 的 QEMU 支线。

| 内容 | 说明 |
|---|---|
| `patches/0001-nvidia-gsp-boot-foundation.patch` | **核心成果**:给主线 QEMU 打的补丁,新增 `nvidia_gsp` RISC-V 机器模型(boot ROM/IMEM/DMEM 映射)与 NV 自定义 CSR 支持,使生产 FMC/LibOS 固件能在 QEMU 里跑。仅含源码 diff,无固件。许可随上游 QEMU(GPL-2.0) |
| `scripts/*.sh` | 实验室脚本:QEMU 引导/构建、生产固件提取、内核 fixture 准备、17 个测试入口(lab-fastpath / walk / mpu / isolation / t017 等) |
| `tools/nvfw-verify.c`、`tools/check-nvidia-host-abi.c` | 固件格式校验与宿主 ABI 检查小工具 |
| `tests/*.S` | 自编 RV64 测试内核源码(MPU、feature gate、isolation、ISA 冒烟) |

## rv64_emu.py — 独立 RV64 全系统模拟器

525 行 Python(依赖 capstone)。文档中大量 E3 级"模拟器"结论的实际载体之一:跑 GSP LibOS 内核 boot+init,dump 页表/任务/PMP 状态。用法见文件头。

## fsp-probe/ 与 fsp-recon/ — FSP 探测内核模块及用户态工具

对应文档:`../FSP_ULTIMATE_FINDINGS.md`、`../FSP_BUG_INVENTORY.md`、`../MNOC_PORT0_PROTOCOL.md` 等 FSP 线结论的取证工具。

- 内核模块(均为 `MODULE_LICENSE("GPL")`,GPL-2.0):`fsp_lie_mod` / `fsp_od_mod` / `fsp_emem_mod` / `fsp_probe2` / `b3_mod` / `drain_mod` / `fsp_tx_mod` / `fsp_romdump_mod` 等 —— BAR0/MMIO 探测、NVDM/EMEM/MNOC 通道实验
- 用户态工具:`fsp_any.c` / `fsp_od.c` / `fsp_raw.c`(各约 950 行)、`emem_cli.c`、`fsp_sniff.c`、`fsp_lie_probe.c`

⚠️ **警告**:这些工具会向 GPU 发送畸形报文,`FSP_BUG_INVENTORY.md` 中的"永久损伤"类 bug 正是这样触发的。在你的显卡上运行 = 自担风险。仅限你拥有且可报废的硬件。

## 未收录(仍在本机原始项目中)

- 编译产物(`.ko`/`.o`/`.cmd`/`.mod.c`)
- 一次性逆向分析脚本(Ghidra/radare 辅助 `gsp_*.py` 等,数量大、粘路径,价值低)
- 固件提取物、Ghidra 工程、VBIOS 二进制
- MODS 相关源文件、驱动源码树
