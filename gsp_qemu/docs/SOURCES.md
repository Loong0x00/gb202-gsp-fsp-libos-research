# 来源、信任边界与审查记录

> 更新：不再把“缺原始 ROM/公开手册”作为整个项目的门槛。已从匹配生产固件恢复并实现实验性 MPU/CSR，QEMU 可执行未修改的 LibOS boot 并自然进入 init。证据、模型边界和下一处输入表见 [MPU_MODEL.md](MPU_MODEL.md)；下面的包验证记录是前一阶段，不代表当前仍只有门禁。

## 固定版本

- QEMU `v11.1.2`: `4fc49f46dc95d4a27de2509e7fceb2931e91faeb`
  - <https://github.com/qemu/qemu/tree/4fc49f46dc95d4a27de2509e7fceb2931e91faeb>
- NVIDIA `610.57.04`: `e4a5faa2567f28c8eabe0ebb6422b6d0abcf37eb`
  - 注意：`8d9087246664ad54dab9af48657a62d5c1d82d6a` 是 annotated tag 对象，不是该 release 的 commit。

## 一手源码证据

全部以固定 NVIDIA commit 为依据，不能将不同版本文档或镜像混用。

1. [`kernel_gsp_gh100.c`](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/e4a5faa2567f28c8eabe0ebb6422b6d0abcf37eb/src/nvidia/src/kernel/gpu/gsp/arch/hopper/kernel_gsp_gh100.c)
   - `kgspSetupGspFmcArgs_GH100`：FMC 参数来自独立的结构、WPR 元数据和 LibOS 内存区域参数，不是任意 global 指针。
   - `_kgspBootstrapGspFmc_GH100`：mailbox 参数、code/data/manifest DMA 地址、256-byte 编码、DMA target/lock 和 CPU 启动。
   - 此 HAL 是共享实现的一部分；不能仅凭 GH100 文件名声称整个 GB202 硬件相同。
2. [`rmRiscvUcode.h`](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/e4a5faa2567f28c8eabe0ebb6422b6d0abcf37eb/src/nvidia/arch/nvalloc/common/inc/rmRiscvUcode.h)
   - `RM_RISCV_UCODE_DESC` 的 ROM 输入范围和字段布局。
3. [`gspifpub.h`](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/e4a5faa2567f28c8eabe0ebb6422b6d0abcf37eb/src/nvidia/arch/nvalloc/common/inc/gsp/gspifpub.h)
   - `GSP_FMC_BOOT_PARAMS`、DMA target、GSP-RM 入口参数。
4. [`gsp_fw_wpr_meta.h`](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/e4a5faa2567f28c8eabe0ebb6422b6d0abcf37eb/src/nvidia/arch/nvalloc/common/inc/gsp/gsp_fw_wpr_meta.h)
   - WPR 元数据和 `verified` 状态由真实启动流程建立；本实现**没有**直接写入 `GSP_FW_WPR_META_VERIFIED`。
5. [`libos_init_args.h`](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/e4a5faa2567f28c8eabe0ebb6422b6d0abcf37eb/src/common/uproc/os/common/include/libos_init_args.h)
   - `LibosMemoryRegionInitArgument` 格式；不是 Linux DTB/OpenSBI 参数接口。
6. [`extract-firmware-nouveau.py`](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/e4a5faa2567f28c8eabe0ebb6422b6d0abcf37eb/nouveau/extract-firmware-nouveau.py)
   - `gsp_bootloader()`、`fmc()` 定义 nvfw/ELF32 容器、CRC、分段和生产/调试选择。
   - 仅使用它进行主机侧数据提取，没有运行 Python CPU 模拟器。
7. [`g_bindata_kgspGetBinArchiveGspRmFmcGfwProdSigned_GB202.c`](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/e4a5faa2567f28c8eabe0ebb6422b6d0abcf37eb/src/nvidia/generated/g_bindata_kgspGetBinArchiveGspRmFmcGfwProdSigned_GB202.c)
   - 官方生产 GFW 镜像、哈希、签名、公钥。已实际下载并与本地生成源码逐字节核对。
   - 源文件 SHA256: `bdca34c507d1b6a81acbb974cffda6dbd37c8bb1f9ce91e4578a6ec53f59a94b`。
   - 公钥 SHA256: `af870e5dde972840588bfb94a87f94b19ad6659dae6e1343dd0d22f16074ba39`。
8. [`dev_riscv_pri.h` (shared Hopper definitions)](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/e4a5faa2567f28c8eabe0ebb6422b6d0abcf37eb/src/common/inc/swref/published/hopper/gh100/dev_riscv_pri.h)
   - BCR DMA 地址 HI 为 11:0、LO 为 31:0，地址编码左移回 8 位，故放置范围需检查 52 位边界。
   - 这是主机 MMIO 定义，**不是处理器内部 CSR/MPU 规范**。

## 已获取的架构资料

- NVIDIA 演讲 [RISC-V at NVIDIA, 2024](https://static.sched.com/hosted_files/riscvsummit2024/fe/Keynote_2024.pdf)
  - 区分 NV MPU、PMP、BootROM、Separation Kernel、S-mode runtime、U-mode 分区。
- NVIDIA 演讲 [How to Secure Unique Ecosystem Shipping 1 Billion Cores, Black Hat USA 2025](https://i.blackhat.com/BH-USA-25/Presentations/USA-25-Zabrocki-Mitic-How-to-Secure-Unique-Ecosystem-Thursday.pdf)
  - BootROM/manifest/分区策略/Separation Kernel 和 SBI 架构。

这些资料没有给出足以直接实现完整 GB202 BootROM 解码/解密或全部专有 CSR 的编程规范。本地保存的 PDF/文本是原文，不以搜索摘要代替证据。

第三方 Open-IOV 文档仅作检索线索；其 Python 模拟模型未采用、未执行，也不作为本项目硬件语义依据。搜索结果提到的 `published/riscv64/rv64-csr.h` 实际获取为 404，未用作依据。

## 必要的同模型审查

当前父 agent 与两次委派均指定 `openai-codex/gpt-6.1-sol`。

- 架构来源审查：API 请求失败，未得到审查结论，**不计为已完成审查**。
- C 解析/签名/QEMU 门禁审查：managed job `sa_a573496deb4241cc` 完成，只读。
  - Medium：`! grep` 不受 Bash `set -e` 保护，会让负向测试假通过。已改为显式 `if ...; then exit 1; fi`。
  - Low：输入大小上限在 `g_file_get_contents()` 后检查。已改为预先 `open/fstat` 检查正规文件和长度，再执行有界读取并检查文件变化。
  - 新增超大稀疏文件、FIFO 拒绝路径并重跑通过。
  - 审查未发现当前调用路径中可达的签名绕过或缺 ROM 放行 CPU；明确 foundation 不等于 GSP 已启动。
- CPU/MPU 必要同模型审查：job `sa_5485b86d55d947d2`，发现一个 High：整页 TLB 可能掩盖页内冲突窗口。已检查整页内所有窗口边界、完整访问区间，修复并补充“外侧预热→内侧冲突”和跨边界非对齐访问两项回归，均通过。
- CPU 专有能力隔离、17 项 S/U MPU 执行以及原始 kernel boot→init 回归均已通过；不是完整安全启动链验收。
- 后续新增的 DMA 编码 helper 为源代码直接对应的纯地址计算，已补充对齐、52 位边界、溢出和高位不截断测试；尚未将其假称为已工作的 DMA 硬件。
- 正向合成 ROM 映射测试额外捕获了 QEMU ROM owner 使用 Machine 而非 Device 的运行时断言；已参照 virt 板改为无 Device owner 的 ROM 注册，并补充 CPU reset 回调。QMP 验证前后两次 PC=0x1000、ROM 内容=0x10500073、CPU 始终未运行；这只验证装载基础，不是 NVIDIA BootROM 测试。

## 对当前认证结果的准确解释

已验证：包的签名/内容一致性，在显式 pin 的官方 release 公钥下成立。

未验证/未实现：芯片熔丝信任根和撤销策略、FSP 本身的安全启动、BootROM 原始执行/载荷处理、完整 M-mode runtime/SBI、init 后续启动表及 RM 任务启动。部分设备窗口权限和 S/U MPU 已由原始固件逆向实现并通过子系统测试；不能据此声称全链完成。

不透明载荷不能直接 disassemble 成合理指令是观测；具体加密算法、密钥来源和可获得性没有被本轮证实，不据此编造解密模型。
