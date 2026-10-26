# GB202(RTX 5090)GSP / LibOS / FSP 逆向研究笔记 · Reverse-Engineering Research Notes

> ### 🎯 Why this repo exists / 这个仓库为什么存在
>
> **EN:** I originally just wanted to enable more L2 (cache slices) and SM units for higher ray-tracing framerates in games. That's how all of this started. **If you know a way, please tell me — thanks!** (feel free to open an issue)
>
> **中文:** 我原本只是想要更多的 L2 和 SM 单元,实现更高的光追游戏帧率——这一切就是这么开始的。**谁有方法的话告诉我,谢谢!**(欢迎开 issue)

**Language:** [English ↓](#english) · [跳转到中文部分](#中文部分)

---

<a id="english"></a>

# English

Personal reverse-engineering research notes on the NVIDIA RTX 5090 (GB202) GPU firmware stack — **357 files: 306 markdown research docs + self-authored tooling source code**. Topics: GSP (RISC-V security processor) firmware RE, LibOS kernel emulation, FSP chain-of-trust analysis, plus clock/voltage/power governance, L2/SM/ISA, fan control and other side quests.

Methods: Ghidra static disassembly + a self-built QEMU emulation lab + experiments on a physical RTX 5090 (bare metal and VFIO passthrough).

**Not affiliated with NVIDIA. Research/educational use only. No guarantee of correctness — read the disclaimer.**

## Three research lines

| Line | Topic | Status (as of 2026-10-18) |
|---|---|---|
| **GSP privilege escalation** | GSP-RM RPC queue overflow, B8 callback hijack, heap object lifecycle, U-mode→S-mode chain | RPC overflow / read primitive / zero primitive verified on real hardware (E1); end-to-end chain **not closed** |
| **FSP chain of trust** | COT/WPR trust chain, PRC/MNOC/EMEM channels, NVDM message layer, runtime/persistent DoS | Many black-box E0 findings; ~95% of the 860-byte COT verification fields are ignored by FSP |
| **LibOS emulation** | Running production FMC/LibOS in mainline QEMU to recover the GSP boot chain | Production LibOS boots to init and walks the 384B boot-region table (E3); full chain incomplete |

### 2026-10-25/26 update: FSP plaintext assault

- **GPU recovered** from BADF lockdown (missing /dev/nvidia0, not permanent brick)
- **FSP_RUN v6 envelope fully mapped** (descriptor fields, IV/tag/AAD layout)
- **GPU key-space search: ~1.2×10^12 candidates, all negative** (lrand48/MSVC rand/glibc random/composite strings/anchored streams across 3 builds × corpus windows × CC labels)
- **Thor T264 PSC cousin architecture extracted** (container spec, KDF chain, tegraopenssl tool) — shipped images use NVIDIA internal SBK, not public OEM keys
- **GSP-RM kslot tracing closed**: key material never passes through firmware memory (hardware window direct)
- **Dell updater AES-CMAC (DMOVERAES128) located** at 0xad4933; final verification on GPU side
- **PRC knob full 16-bit scan**: 44 alive knobs (0x0000-0x002B), read-only; write path closed with all flags
- **FSP memory windows (0x8f0000/2000/3000): all PLM-locked** (different BADF codes per block)
- **HULK verification code in plaintext GSP-RM** (3AES signature vs GPU fuse) — future RE target

Side quests: runtime MCLK/XBAR control, VF curve governance, power budget, fan routing, L2 slices, SM120 cache/register ISA, dual-BIOS-slot forensics, and more.

## Quick navigation

- [`AUTHORITATIVE_STATUS.md`](AUTHORITATIVE_STATUS.md) — the authoritative status overview (start here)
- [`FINDINGS.md`](FINDINGS.md) — all conclusions with E0–E6 evidence grades
- [`docs/INDEX.md`](docs/INDEX.md) — categorized index of 230 source docs (status / evidence class / one-line summary)
- [`docs/EVIDENCE.md`](docs/EVIDENCE.md) — evidence grading definitions
- [`code/`](code/README.md) — self-authored tooling: the QEMU GSP machine patch, `rv64_emu.py`, FSP probe kernel modules
- Vulnerability inventory & reports: `VULN_INVENTORY.md`, `FSP_BUG_INVENTORY.md`, `PSIRT_DRAFT_1_GB202_FSP_RUNTIME_DOS.md`, `PSIRT_DRAFT_2_GB202_WPR2_PERSISTENT_STATE.md`, `SUBMISSION_RECORD_20261013.md`

Evidence grading (E0–E6): E0 direct real-hardware observation, E1 real-hardware causal experiment, E2 real-hardware VM passthrough, E3 emulator (QEMU/rv64_emu) controlled experiment, E4 static disassembly, E5 public material, E6 hypothesis. Hard rules: emulator results must never be written up as hardware results; addresses are pinned to specific driver branches (610.57.04 / 615.71.09 / MODS 570.215 are not interchangeable).

## ⚠️ Disclaimer (must read)

1. **No guarantee of correctness.** These are personal research notes, not authoritative documentation. They may contain errors, outdated conclusions, under-evidenced speculation, or results later overturned. Known corrections live in [`CORRECTIONS.md`](CORRECTIONS.md) but may be incomplete. All conclusions are pinned to specific driver/firmware/VBIOS versions. Verify the original evidence chain before relying on anything.
2. **Research/educational use only.** Provided AS-IS, no warranty of any kind. Use at your own risk.
3. **Disclosure status.** The two `PSIRT_DRAFT_*.md` reports were privately submitted to NVIDIA PSIRT on 2026-10-13 (see `SUBMISSION_RECORD_20261013.md`); public issue: [NVIDIA/open-gpu-kernel-modules#1442](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1442). No fix received as of publication; the material is published here as-is.
4. **No NVIDIA proprietary assets.** Mostly markdown notes plus a small amount of self-authored tooling source in `code/`: no MODS source files, no driver source trees, no firmware binaries / Ghidra projects / bulk disassembly output. Quoted open-source snippets come from the MIT/GPL dual-licensed [open-gpu-kernel-modules](https://github.com/NVIDIA/open-gpu-kernel-modules). The FSP probe code in `code/` sends malformed packets to the GPU and **may permanently damage it**.
5. **Privacy.** Personal information (emails, tokens, real IPs, hardware serials, hostnames) was scanned for and removed before publishing. Addresses like `10.0.2.x` / `52:54:00:*` are QEMU-internal defaults. Reporter fields in report drafts are placeholders. If anything slipped through, please open an issue and it will be handled.
6. NVIDIA, RTX, GeForce trademarks belong to NVIDIA Corporation; this research is not affiliated with, authorized, or endorsed by NVIDIA.

## Repo layout

```text
.
├── AUTHORITATIVE_STATUS.md   # authoritative status overview (entry point)
├── FINDINGS.md / STATUS.md / CORRECTIONS.md / OPEN_QUESTIONS.md / NEXT_STEPS.md
├── docs/                     # indexes, evidence grading, dedup plan, 54 archived copies
├── fsp_code/                 # FSP firmware static-analysis notes
├── fsp_ace_static_20260927/  # FSP static campaign (AUDIT/VERDICT/RUNBOOK)
├── gsp_qemu/docs/            # QEMU GSP emulation lab docs
├── power_governor_reverse/   # clock/voltage/power governance RE (78 docs)
├── vm_mods_lab/              # VM/VFIO/MODS experiment notes (docs only, no MODS sources)
├── vfio_production_lab/      # production VM passthrough environment
├── driver-diffs/             # 610→615 driver LibOS public-source diff analysis
├── web-research/             # public-source survey (FSP/InfoROM/PRC recovery)
├── code/                     # self-authored tooling: QEMU GSP patch/scripts/tests, rv64_emu.py, FSP probes
└── *.md                      # 137 mainline research docs at repo root
```

The original ~6.8 GB experiment project (logs, binaries, Ghidra projects) is not included; aside from the small `code/` directory this repo publishes documentation only.

## License

Text: [CC BY-NC-SA 4.0](LICENSE), except quoted third-party material. The QEMU patch and kernel modules in `code/` are GPL-2.0 (upstream/`MODULE_LICENSE`).

---

<a id="中文部分"></a>

# 中文部分

个人对 NVIDIA RTX 5090(GB202)GPU 固件层的逆向工程研究资料库,共 **342 个文件**(293 份研究文档 + 自研配套源码)。内容涵盖 GSP(RISC-V 安全处理器)固件逆向、LibOS 内核模拟执行、FSP 信任链分析,以及时钟/电压/功耗治理、L2/SM/ISA、风扇控制等周边逆向成果。

研究方法:Ghidra 静态反汇编 + QEMU 自建模拟环境 + 物理 RTX 5090 真机/VFIO 直通实验。

**与 NVIDIA 无任何关联;仅供研究学习;不保证内容完全正确(见下方免责声明)。**

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
- LibOS 模拟:`gsp_qemu/docs/`(`MPU_MODEL.md`、`LAB_BOOT.md`)、`code/`(QEMU GSP 补丁与 `rv64_emu.py`)、`driver-diffs/`(610.57.04→615.78.08 LibOS 公开源码 diff)
- 时钟/电压/功耗:`power_governor_reverse/`(78 份)
- VM/VFIO 实验环境:`vm_mods_lab/`、`vfio_production_lab/`
- 历史归档:`docs/archive/`(54 份被取代文档,字节级副本)、`docs/ARCHIVE_INDEX.md`

## 证据分级(E0–E6,摘录)

研究文档全部带证据级别,没有级别的"已验证/实锤"不作数:

- **E0** 真机直接观测 / **E1** 真机因果实验 / **E2** 真机 VM 直通
- **E3** 模拟器受控实验(QEMU/rv64_emu)/ **E4** 静态反汇编
- **E5** 公开资料 / **E6** 推理假设

**硬规则**:模拟器结论不得写成真机结论;地址必须绑定驱动版本(610.57.04 / 615.71.09 / MODS 570.215 不可互套);真机与模拟器冲突时拆成两条 claim。

## ⚠️ 免责声明(必读)

1. **不保证完全正确。** 本仓库是个人研究笔记,不是权威文档,可能包含错误、过时结论、证据不足的推测,甚至已被后续实验推翻的内容。已知勘误见 [`CORRECTIONS.md`](CORRECTIONS.md),但勘误未必齐全。所有结论均绑定特定驱动/固件/VBIOS 版本,换版本不保证成立。引用前请自行核验原始证据链。
2. **仅供研究与学习。** 仓库内容为个人安全研究记录,按原样(AS-IS)提供,不构成任何形式的保证。使用者自行承担一切后果。
3. **漏洞披露状态。** `PSIRT_DRAFT_*.md` 两份报告已于 2026-10-13 私密提交 NVIDIA PSIRT(见 `SUBMISSION_RECORD_20261013.md`),另有公开 issue [NVIDIA/open-gpu-kernel-modules#1442](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1442)。截至发布时未收到修复;相关内容在此按原样公开,谁愿意看谁看。
4. **不含 NVIDIA 专有资产。** 仓库以 Markdown 研究笔记为主,另附少量**本人编写的**配套源码(`code/`,QEMU 补丁、模拟器、FSP 探测模块):不含 MODS 源文件、不含驱动源码树、不含固件二进制/Ghidra 工程/反汇编全量产物。引用的开源代码片段来自 MIT/GPL 双许可的 [open-gpu-kernel-modules](https://github.com/NVIDIA/open-gpu-kernel-modules)。`code/` 中的 FSP 探测代码会向 GPU 发送畸形报文,**可能造成永久损坏**,自担风险。
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
├── code/                     # 自研配套源码:QEMU GSP 补丁/脚本/测试、rv64_emu.py、FSP 探测模块
└── *.md                      # 根目录 137 份主线研究文档
```

原始实验项目(含日志、二进制、Ghidra 工程约 6.8GB)未收录;除 `code/` 少量自研源码外仅发布文档层。

## License

除引用的第三方内容外,文本采用 [CC BY-NC-SA 4.0](LICENSE);`code/` 中 QEMU 补丁与内核模块为 GPL-2.0(随上游/`MODULE_LICENSE`)。
