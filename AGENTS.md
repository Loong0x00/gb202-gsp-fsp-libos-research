# LibOS / GSP 模拟任务约定

以下约定仅针对本项目的 LibOS/GSP 模拟工作，不改变其他研究目录的任务范围。

- 后续 CPU/固件执行一律使用 `gsp_qemu/` 中的 QEMU 主线。不运行 `rv64_emu.py` 或旧 bench 的 Python CPU 模拟器；旧文件只作历史参考。
- 原始生产固件保持不变。禁止通过 NOP、强制分支、直接跳 init、伪造 SBI 成功或填写 boot verified 标志来冒充启动进展。
- 依据匹配版本的官方源码、原始固件逆向及 QEMU 回归恢复启动行为。允许可验证的 BootROM/硬件行为模型，不要求逐字节执行原始 ROM；缺公开手册不是停止条件。未建模的 FSP、CSR、DMA、权限或服务必须明确暴露缺口，不能静默假成功。
- 开始工作先读 `gsp_qemu/README.md`、`gsp_qemu/docs/SOURCES.md`、`gsp_qemu/docs/MPU_MODEL.md`。当前已有实验性 NVIDIA MPU/CSR 模型，未修改的 LibOS 可在子系统测试中从 boot 自然进入 init；完整 FSP/FMC/LibOS/GSP 启动链仍未完成。子系统进展与包验签不能冒充完整启动成功。
- 独立构建 QEMU，不覆盖系统安装。纯模拟验证不应附带操作真实 GPU 或已有 VFIO VM。
- 子 agent 仅在必要审查处调用，并显式选择与父 agent 当前相同的模型；不依赖工具默认模型。
