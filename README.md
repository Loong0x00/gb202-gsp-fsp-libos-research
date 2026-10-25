# GB202(RTX 5090)GSP / LibOS / FSP 逆向研究笔记

个人对 NVIDIA RTX 5090(GB202)GPU 固件层的逆向工程研究资料库,共 **291 份研究文档**。内容涵盖 GSP(RISC-V 安全处理器)固件逆向、LibOS 内核模拟执行、FSP 信任链分析,以及时钟/电压/功耗治理、L2/SM/ISA、风扇控制等周边逆向成果。

研究方法:Ghidra 静态反汇编 + QEMU 自建模拟环境 + 物理 RTX 5090 真机/VFIO 直通实验。

**与 NVIDIA 无任何关联;仅供研究学习;不保证内容完全正确(见下方免责声明)。**

---

## 三条研究主线

| 支线 | 内容 | 截至 2026-10-18 状态 |
|---|---|---|
| **GSP 提权** | GSP-RM RPC 消息队列溢出、B8 回调劫持、堆对象生命周期、U-mode→S-mode 提权链 | RPC 溢出/读原语/清零原语已真机成立(E1);端到端提权链**未闭合** |
| **FSP 信任链** | COT/WPR 信任链、PRC/MNOC/EMEM 通道、NVDM 消息层、runtime/persistent DoS | 大量黑盒 E0 结论;COT 860 字节中约 95% 验证字段被 FSP 忽略 |
| **LibOS 模拟** | 用主线 QEMU 执行生产 FMC/LibOS,恢复 GSP 启动链 | 生产 LibOS 已 boot 到 init、穿过 384B 启动区域表(E3);完整启动链未完成 |

另有:时钟/MCLK/XBAR 运行时控制、VF 曲线治理、功耗预算、风扇路由、L2 切片、SM120 cache/寄存器 ISA、VBIOS 双槽取证等大量支线文档。

## 快速导航

**5 分钟了解现状**:
1. [`AUTHORITATIVE_STATUS.md`](AUTHORITATIVE_STATUS.md) — 唯一权威进度总览(先读这个)
2. [`FINDINGS.md`](FINDINGS.md) — 全部结论清单,带 E0–E6 证据分级
3. [`docs/INDEX.md`](docs/INDEX.md) — 230 份原始文档的分类索引(状态/证据类别/一句话摘要)
4. [`docs/EVIDENCE.md`](docs/EVIDENCE.md) — 证据分级定义

**按主题深入**:

- GSP 提权与对象生命周期:`KERNEL_PRIVESC_C1_C2_PROOF_20261008.md`、`C2_ENTRY_AUDIT_20261010.md`、`K31_FINAL_REPORT.md`、`GSP_61571_FINAL_ADDR_MAP.md`、`ELF_TOCTOU_BREAKTHROUGH.md`
- FSP 信任链:`FSP_ULTIMATE_FINDINGS.md`、`FSP_TRUST_CHAIN_MODEL.md`、`FSP_COMPLETE_TRUST_CHAIN.md`、`COT_*` 系列、`fsp_ace_static_20260927/`、`fsp_code/`
- 漏洞清单与对外报告:`VULN_INVENTORY.md`、`FSP_BUG_INVENTORY.md`、`PSIRT_DRAFT_1_GB202_FSP_RUNTIME_DOS.md`、`PSIRT_DRAFT_2_GB202_WPR2_PERSISTENT_STATE.md`、`SUBMISSION_RECORD_20261013.md`
- LibOS 模拟:`gsp_qemu/docs/`(`MPU_MODEL.md`、`LAB_BOOT.md`)、`driver-diffs/`(610.57.04→615.78.08 LibOS 公开源码 diff)
- 时钟/电压/功耗:`power_governor_reverse/`(78 份)
- VM/VFIO 实验环境:`vm_mods_lab/`、`vfio_production_lab/`
- 历史归档:`docs/archive/`(54 份被取代文档,字节级副本)、`docs/ARCHIVE_INDEX.md`

## 证据分级(E0–E6,摘录)

研究文档全部带证据级别,没有级别的"已验证/实锤"不作数:

- **E0** 真机直接观测 / **E1** 真机因果实验 / **E2** 真机 VM 直通
- **E3** 模拟器受控实验(QEMU/rv64_emu)/ **E4** 静态反汇编
- **E5** 公开资料 / **E6** 推理假设

**硬规则**:模拟器结论不得写成真机结论;地址必须绑定驱动版本(610.57.04 / 615.71.09 / MODS 570.215 不可互套);真机与模拟器冲突时拆成两条 claim。

---

## ⚠️ 免责声明(必读)

1. **不保证完全正确。** 本仓库是个人研究笔记,不是权威文档,可能包含错误、过时结论、证据不足的推测,甚至已被后续实验推翻的内容。已知勘误见 [`CORRECTIONS.md`](CORRECTIONS.md),但勘误未必齐全。所有结论均绑定特定驱动/固件/VBIOS 版本,换版本不保证成立。引用前请自行核验原始证据链。
2. **仅供研究与学习。** 仓库内容为个人安全研究记录,按原样(AS-IS)提供,不构成任何形式的保证。使用者自行承担一切后果。
3. **漏洞披露状态。** `PSIRT_DRAFT_*.md` 两份报告已于 2026-10-13 私密提交 NVIDIA PSIRT(见 `SUBMISSION_RECORD_20261013.md`),另有公开 issue [NVIDIA/open-gpu-kernel-modules#1442](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1442)。截至发布时未收到修复;相关内容在此按原样公开,谁愿意看谁看。
4. **不含 NVIDIA 专有资产。** 仓库只收录 Markdown 研究笔记:不含 MODS 源文件、不含驱动源码树、不含固件二进制/Ghidra 工程/反汇编全量产物。引用的开源代码片段来自 MIT/GPL 双许可的 [open-gpu-kernel-modules](https://github.com/NVIDIA/open-gpu-kernel-modules)。
5. **隐私处理。** 发布前已扫描并清理个人隐私信息(邮箱、token、真实 IP、硬件序列号、主机名等);文中出现的 `10.0.2.x`/`52:54:00:*` 等地址均为 QEMU 虚拟化内部默认值,非真实网络信息。报告草稿中的报告人字段为占位符。如仍发现疏漏,请开 issue,将及时处理。
6. 文中 NVIDIA、RTX、GeForce 等商标归 NVIDIA Corporation 所有;本研究与 NVIDIA 无关联、未获其授权或认可。

## 仓库结构

```text
.
├── AUTHORITATIVE_STATUS.md   # 权威进度总览(入口)
├── FINDINGS.md / STATUS.md / CORRECTIONS.md / OPEN_QUESTIONS.md / NEXT_STEPS.md
├── docs/                     # INDEX 索引、证据分级、去重计划、54 份归档副本
├── fsp_code/                 # FSP 固件静态分析笔记
├── fsp_ace_static_20260927/  # FSP 静态战役(AUDIT/VERDICT/RUNBOOK)
├── gsp_qemu/docs/            # QEMU 模拟 GSP 实验室文档
├── power_governor_reverse/   # 时钟/电压/功耗治理逆向(78 份)
├── vm_mods_lab/              # VM/VFIO/MODS 实验笔记(仅文档,无 MODS 源文件)
├── vfio_production_lab/      # 生产 VM 直通环境
├── driver-diffs/             # 610→615 驱动 LibOS 公开源码差异分析
├── web-research/             # 公开资料调研(FSP/InfoROM/PRC 恢复)
└── *.md                      # 根目录 137 份主线研究文档
```

原始实验项目(含脚本、日志、二进制、Ghidra 工程约 6.8GB)未收录,本仓库只发布文档层。

## License

除引用的第三方内容外,文本采用 [CC BY-NC-SA 4.0](LICENSE)。

## English TL;DR

Personal reverse-engineering research notes (291 markdown docs) on the NVIDIA RTX 5090 (GB202) firmware stack: GSP (RISC-V security processor) privilege-escalation research, FSP (Falcon Security Processor) chain-of-trust analysis (COT/WPR), and LibOS kernel emulation with mainline QEMU, plus clock/voltage/power/fan/L2/SM side quests. Evidence-graded E0–E6, version-pinned to specific driver branches. **Not affiliated with NVIDIA. Provided as-is with no guarantee of correctness — verify before relying on anything.** No NVIDIA proprietary sources or firmware binaries included (no MODS source files, no driver trees); notes only. Vulnerability reports were privately submitted to NVIDIA PSIRT on 2026-10-13 and are published here as-is.
