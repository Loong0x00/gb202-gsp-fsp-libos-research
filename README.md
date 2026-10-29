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

Personal reverse-engineering research notes on the NVIDIA RTX 5090 (GB202) GPU firmware stack — **14,407 tracked files, including 14,347 Markdown research documents and self-authored tooling source code**. Topics: GSP (RISC-V security processor) firmware RE, LibOS kernel emulation, FSP chain-of-trust analysis, plus clock/voltage/power governance, L2/SM/ISA, fan control and other side quests.

Methods: Ghidra static disassembly + a self-built QEMU emulation lab + experiments on a physical RTX 5090 (bare metal and VFIO passthrough).

**Not affiliated with NVIDIA. Research/educational use only. No guarantee of correctness — read the disclaimer.**

## Three research lines

| Line | Topic | Status (as of 2026-10-27) |
|---|---|---|
| **GSP privilege escalation** | GSP-RM RPC queue overflow, B8 callback hijack, heap object lifecycle, U-mode→S-mode chain | RPC overflow / read primitive / zero primitive verified on real hardware (E1); end-to-end chain **not closed**; no further live-card experiments planned |
| **FSP chain of trust / plaintext** | COT/WPR trust chain, PRC/MNOC/EMEM, encrypted `FSP_RUN`, FieldDiag/FuseRework | Offline audit identifies an AES-256-GCM software consumer model, but no target plaintext, data key, KDF root, or supported export path; live-card work stopped |
| **LibOS emulation** | Running production FMC/LibOS in mainline QEMU to recover the GSP boot chain | Production LibOS boots to init and walks the 384B boot-region table (E3); full chain incomplete |

### 2026-10-25/26 correction and recovery update

- The original heartbeat/RPC/watchdog failures and several post-reset initialization failures were real. A later final-state check was additionally confused by a missing `/dev/nvidia0`, cgroup permissions and an incorrect driver-binding check. See [`GSP_GLM53_CONTEXT_AUDIT_20261026.md`](GSP_GLM53_CONTEXT_AUDIT_20261026.md) and [`GSP_RECOVERY_20261026.md`](GSP_RECOVERY_20261026.md).
- The historical ~`1.2×10^12` candidate search did not yield a key, but later review found first-block filtering and model limitations; it is **not** a valid proof that the key space was exhausted.
- `0xad4933` in the Dell updater is OpenSSL `bsaes_xts_decrypt`, not an FSP AES-CMAC verifier.
- The strongest recovered host software ABI is AES-256-GCM with a 32-byte caller-supplied key, 12-byte IV, 16-byte tag and empty AAD. This does not reveal the target FSP key or prove the device-side KDF.

### 2026-10-27 update: offline FSP plaintext audit closed

- 58 valid local `FSP_RUN` records were inventoried, including six unique GB202 payload/descriptor objects; ordinary RTX 5090 retail VBIOSes mostly reuse one object.
- MODS 570.151/570.215/570.278 and public FieldDiag/MODS 580 packages were audited. No plaintext, bulk decrypt-to-host API, Blackwell `fuserework.bin`, or its three RSA-3072 sidecars was found.
- Public English/Chinese/Russian forum, archive and cloud-drive searches found no verifiable target bundle. A 22.38 GB community image was inventoried remotely through 7z/Btrfs metadata without downloading it in full; its current tree contains only known 540/570 packages.
- Final status: [`fsp_plaintext_audit_20261027/FINAL_STATUS_AND_RESUME_GUIDE_20261027.md`](fsp_plaintext_audit_20261027/FINAL_STATUS_AND_RESUME_GUIDE_20261027.md).
- Live hardware experimentation is explicitly stopped because malformed messages, broad MMIO reads and recovery operations have produced FSP/GSP/WPR2/PCIe/kernel failure chains. See [`HARDWARE_DO_NOT_TOUCH_RISK_SUMMARY_20261027.md`](HARDWARE_DO_NOT_TOUCH_RISK_SUMMARY_20261027.md).

### 2026-10-29 update: 87-version corpus, NVDM inventory and crypto-path boundary

- Collected and byte-verified all **87/87** GB202 GSP outer images and main RV64 inner ELFs. The corpus is intentionally not republished here.
- Recovered **1,456 direct GSP→FSP NVDM call sites** across the corpus. Found six uses of undocumented type `0x24`, first seen in 610.43.02, with 4-byte lifecycle commands and 17-byte status responses rather than address or plaintext output.
- ROMREAD (`0x1a`) has no direct sender call and its candidate getter is not installed; other channels such as `0x21` are used indirectly through vtables, so public host APIs alone are not a complete inventory.
- Traced NVCBA2 / MODS SecureCopy from method streams to a software AES-256-GCM branch. It is a generic secure-copy/memory-compare framework with a 32-byte key at `object+0x44`, not a demonstrated `FSP_RUN` consumer or KDF source.
- Current boundary: no BootROM/FSP first-stage implementation, real KDF input/root key, engineering/debug plaintext bundle, or supported decryption oracle was found. This is a material-evidence limitation, not a claim that such consumers cannot exist elsewhere.
- New reports live in [`gsp-target-20261029/`](gsp-target-20261029/): `FSP_NVDM_INVENTORY_20261029.md`, `SECOND_PASS_CRYPTO_AND_DYNAMIC.md`, and `THIRD_PASS_MODS_SECURECOPY.md`. The 16.1 GB batch decompilation corpus and Ghidra projects are excluded from publication.

Side quests: runtime MCLK/XBAR control, VF curve governance, power budget, fan routing, L2 slices, SM120 cache/register ISA, dual-BIOS-slot forensics, and more.

## Quick navigation

- [`AUTHORITATIVE_STATUS.md`](AUTHORITATIVE_STATUS.md) — the authoritative status overview (start here)
- [`FINDINGS.md`](FINDINGS.md) — all conclusions with E0–E6 evidence grades
- [`docs/INDEX.md`](docs/INDEX.md) — categorized 2026-10-18 index plus a post-index addendum
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
├── fsp_plaintext_audit_20261027/ # final offline crypto/FieldDiag/FuseRework/web-hunt reports
├── gsp_qemu/docs/            # QEMU GSP emulation lab docs
├── power_governor_reverse/   # clock/voltage/power governance RE (78 docs)
├── vm_mods_lab/              # VM/VFIO/MODS experiment notes (docs only, no MODS sources)
├── vfio_production_lab/      # production VM passthrough environment
├── driver-diffs/             # 610→615 driver LibOS public-source diff analysis
├── web-research/             # public-source survey (FSP/InfoROM/PRC recovery)
├── code/                     # self-authored tooling: QEMU GSP patch/scripts/tests, rv64_emu.py, FSP probes
└── *.md                      # mainline research and risk/recovery documents at repo root
```

The original ~6.8 GB experiment project (logs, binaries, Ghidra projects) is not included; aside from the small `code/` directory this repo publishes documentation only.

## License

Text: [CC BY-NC-SA 4.0](LICENSE), except quoted third-party material. The QEMU patch and kernel modules in `code/` are GPL-2.0 (upstream/`MODULE_LICENSE`).

---

<a id="中文部分"></a>

# 中文部分

个人对 NVIDIA RTX 5090(GB202)GPU 固件层的逆向工程研究资料库，共 **14,407 个受 Git 跟踪的文件，其中 14,347 份为 Markdown 研究文档**，另含自研配套源码。内容涵盖 GSP(RISC-V 安全处理器)固件逆向、LibOS 内核模拟执行、FSP 信任链与明文获取审计，以及时钟/电压/功耗治理、L2/SM/ISA、风扇控制等周边逆向成果。

研究方法:Ghidra 静态反汇编 + QEMU 自建模拟环境 + 物理 RTX 5090 真机/VFIO 直通实验。

**与 NVIDIA 无任何关联;仅供研究学习;不保证内容完全正确(见下方免责声明)。**

## 三条研究主线

| 支线 | 内容 | 截至 2026-10-27 状态 |
|---|---|---|
| **GSP 提权** | GSP-RM RPC 消息队列溢出、B8 回调劫持、堆对象生命周期、U-mode→S-mode 提权链 | RPC 溢出/读原语/清零原语已真机成立(E1);端到端提权链**未闭合**；不再继续现有真卡实验 |
| **FSP 信任链/明文** | COT/WPR、PRC/MNOC/EMEM、加密 `FSP_RUN`、FieldDiag/FuseRework | 已恢复 AES-256-GCM 软件 consumer 模型，但没有目标明文、data key、KDF root 或受支持的导出路径；真机路线停止 |
| **LibOS 模拟** | 用主线 QEMU 执行生产 FMC/LibOS,恢复 GSP 启动链 | 生产 LibOS 已 boot 到 init、穿过 384B 启动区域表(E3);完整启动链未完成 |

### 2026-10-25/26 更正与恢复更新

- 最初的 heartbeat/RPC/watchdog 故障及若干复位后初始化失败确实发生；但最后阶段又混入 `/dev/nvidia0` 缺失、cgroup 权限及错误驱动绑定检查。详见 [`GSP_GLM53_CONTEXT_AUDIT_20261026.md`](GSP_GLM53_CONTEXT_AUDIT_20261026.md) 和 [`GSP_RECOVERY_20261026.md`](GSP_RECOVERY_20261026.md)。
- 历史约 `1.2×10^12` 候选搜索没有命中，但后来发现首块过滤和模型局限，不能把它当作“密钥空间已穷尽”的证明。
- Dell updater 的 `0xad4933` 是 OpenSSL `bsaes_xts_decrypt`，不是 FSP AES-CMAC verifier。
- 当前最强 host 软件 ABI 是 AES-256-GCM：调用者提供 32 字节 key、12 字节 IV、16 字节 tag，AAD 为空；它不泄露目标 FSP key，也不能证明片内 KDF。

### 2026-10-27 更新：FSP 明文离线审计收束

- 本地盘点得到 58 条有效 `FSP_RUN` 记录和 6 个唯一 GB202 payload/descriptor；普通 RTX 5090 零售 VBIOS 基本复用同一个对象。
- 审计 MODS 570.151/570.215/570.278 及公开 FieldDiag/MODS 580 后，没有发现明文、bulk decrypt-to-host API、Blackwell `fuserework.bin` 或三个 RSA-3072 sidecar。
- 中英俄论坛、公开归档及网盘搜索没有找到可验证目标包。一个 22.38GB 社区镜像通过 7z/Btrfs 元数据远程列出当前文件树，无需完整下载，确认只含已知 540/570 包。
- 最终状态：[`fsp_plaintext_audit_20261027/FINAL_STATUS_AND_RESUME_GUIDE_20261027.md`](fsp_plaintext_audit_20261027/FINAL_STATUS_AND_RESUME_GUIDE_20261027.md)。
- 因畸形消息、广泛 MMIO 读取及恢复操作曾形成 FSP/GSP/WPR2/PCIe/内核级故障链，明确停止真机路线。风险清单见 [`HARDWARE_DO_NOT_TOUCH_RISK_SUMMARY_20261027.md`](HARDWARE_DO_NOT_TOUCH_RISK_SUMMARY_20261027.md)。

### 2026-10-29 更新：87 版固件清单、NVDM 通信面与 crypto 路径边界

- 完成 **87/87** 个 GB202 GSP outer 与主 RV64 inner ELF 的收集及逐字节校验；固件本体不纳入仓库。
- 恢复 **1,456 个 GSP→FSP NVDM 直接调用点**。发现 6 处未公开 `0x24` 类型，最早见 610.43.02；其形态为 4 字节生命周期命令和 17 字节状态响应，不含地址或明文输出。
- `ROMREAD(0x1a)` 没有直接 sender 调用，候选 getter 未安装；`0x21` 等通道则经 vtable 间接使用，因此公开 host API 不能代表完整通信面。
- 追通 NVCBA2 / MODS SecureCopy 方法流到软件 AES-256-GCM 分支。它是通用 secure-copy/内存比较框架，`object+0x44` 为 32 字节 key 字段，但尚不是已证实的 `FSP_RUN` 消费者或 KDF 来源。
- 当前证据边界：没有 BootROM/FSP 第一阶段实现、真实 KDF 输入/root key、工程/debug 明文包或受支持的解密 oracle。这是材料限制，不排除其他消费者存在。
- 新报告位于 [`gsp-target-20261029/`](gsp-target-20261029/)：`FSP_NVDM_INVENTORY_20261029.md`、`SECOND_PASS_CRYPTO_AND_DYNAMIC.md`、`THIRD_PASS_MODS_SECURECOPY.md`。16.1 GB 批量反编译结果与 Ghidra 项目不发布。

另有：时钟/MCLK/XBAR 运行时控制、VF 曲线治理、功耗预算、风扇路由、L2 切片、SM120 cache/寄存器 ISA、VBIOS 双槽取证等大量支线文档。

## 快速导航

**5 分钟了解现状**:
1. [`AUTHORITATIVE_STATUS.md`](AUTHORITATIVE_STATUS.md) — 唯一权威进度总览(先读这个)
2. [`FINDINGS.md`](FINDINGS.md) — 全部结论清单,带 E0–E6 证据分级
3. [`docs/INDEX.md`](docs/INDEX.md) — 2026-10-18 分类索引及后续新增文档附录
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
├── fsp_plaintext_audit_20261027/ # FSP 离线密码/FieldDiag/FuseRework/公网搜索报告
├── gsp_qemu/docs/            # QEMU 模拟 GSP 实验室文档
├── power_governor_reverse/   # 时钟/电压/功耗治理逆向(78 份)
├── vm_mods_lab/              # VM/VFIO/MODS 实验笔记(仅文档,无 MODS 源文件)
├── vfio_production_lab/      # 生产 VM 直通环境
├── driver-diffs/             # 610→615 驱动 LibOS 公开源码差异分析
├── web-research/             # 公开资料调研(FSP/InfoROM/PRC 恢复)
├── code/                     # 自研配套源码:QEMU GSP 补丁/脚本/测试、rv64_emu.py、FSP 探测模块
└── *.md                      # 根目录主线研究、风险与恢复记录
```

原始实验项目(含日志、二进制、Ghidra 工程约 6.8GB)未收录;除 `code/` 少量自研源码外仅发布文档层。

## License

除引用的第三方内容外,文本采用 [CC BY-NC-SA 4.0](LICENSE);`code/` 中 QEMU 补丁与内核模块为 GPL-2.0(随上游/`MODULE_LICENSE`)。
