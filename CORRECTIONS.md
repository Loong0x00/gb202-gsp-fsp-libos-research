# CORRECTIONS — 旧文档更正表

> 更新：2026-10-27。
> **更正策略**：历史文档原则上保留并由本表提供补丁层；对会直接误导密码学归因或硬件安全判断的严重错误，公开副本可在原文顶部加更正横幅并改写错误段落，但必须同时在本表登记。私有原始工作副本不因此改写。
> 每条 = 旧文档:行 → 旧表述 → 更正后表述 → 依据 → 状态。
> 状态：`已裁决`（有后续证据）/ `部分裁决`（版本已分清、残留未决）/ `未决`（进 `OPEN_QUESTIONS.md`）。

| ID | 旧文档:行 | 旧表述 | 更正后表述 | 依据 | 状态 |
|---|---|---|---|---|---|
| C-01 | `★V5_STATUS_20261016.md:784` | “t0=4 fast path(0x930042F8): 真正的U-mode路径” | **模拟器受控入口，不是 U-mode 路径。** 受控 `t0=4,stval=0` 注入只做 state 0→1、ref 不变、不调 handler/`0x93005b26`；自然 boot 未命中 t0=4；U-mode 可达性**未证明**。 | `gsp_qemu/docs/LAB_BOOT.md:606-631`（“受控 fast-path 入口，不是 U-mode trap”）；`gsp_qemu/README.md:86`（“明确不是真实 U-mode trap”）；`gsp_qemu/PROGRESS.md:109`（自然 boot 命中 t0=0/1/0x16） | 已裁决 |
| C-02 | `★V5_STATUS_20261016.md:743`（及 `:778-789`） | 标题“20.1 已证明的核心事实(全部有实验证据)”，下方把 lab 的对象生命周期结论与真机溢出平台并列 | 按 E0–E6 拆分：`:745-766`（溢出平台、B8 执行域、读写原语）为 **E1**；`:778-790`（t0=23/t0=4/`0x93005b26`/dtor/gadget）为 **E3（QEMU lab）**；`:793-800`（syscall 表）为 **E2**。父标题应改为“核心事实（级别见条目）”。 | `FINDINGS.md` Q-05/Q-06/OBJ-04/OBJ-05/OBJ-07；`gsp_qemu/README.md:83-88` 的逐测试限定 | 已裁决 |
| C-03 | `KERNEL_PRIVESC_C1_C2_PROOF_20261008.md:14,25,122` | “entry=40B, dtor在+0x28”；`slot = base + type×40 + 0x28`；“+0x28 dtor” | **GB20X：entry stride `0x28`(40B)，dtor 指针在 `entry+8`**；`+0x28` 是 **GB10Y 旧内核** 的 dtor 偏移。原文把 stride 当成了偏移。 | `GSP_PRIVESC_FINAL_PLAN_20261008.md:346`（“dtor在entry+8 — GB10Y是+0x28”）、`:2484`（“dtor在entry+8 (GB20X与GB10Y不同!)”）；`C2_ENTRY_AUDIT_20261010.md:16-19`（`+8`，静态+模拟器）；`★V5_STATUS_20261016.md:787`（`+type*0x28+8`） | 已裁决（2026-10-18 静态反汇编：`ld a5,8(a5)` @0x93005b5a；残留 OQ-02R） |
| C-04 | `KERNEL_PRIVESC_C1_C2_PROOF_20261008.md:21`；`GSP_PRIVESC_FINAL_PLAN_20261008.md:2441` | RELEASE = `0x930060f2`（“dtor@+0x28,实证”） | **GB20X RELEASE = `0x93005b26`**（jalr 在 `0x93005b60`）；`0x930060f2`/`+0x28` 属 **GB10Y 旧内核**，不得混用。 | `GSP_PRIVESC_FINAL_PLAN_20261008.md:2481`（“那是GB10Y旧内核!”）；`C2_ENTRY_AUDIT_20261010.md:16-19`；`★V5_STATUS_20261016.md:786`；`gsp_qemu/README.md:84`；2026-10-18 静态复核：`0x930060f2` 是链表初始化（`sd a0,0/8/16(a0)`），RELEASE 入口为 `0x93005b26`（见 `OPEN_QUESTIONS.md` §3） | 已裁决 |
| C-05 | `KERNEL_PRIVESC_C1_C2_PROOF_20261008.md:18-20` | TYPECALC 以 `0xffffffffa300a020` 为基线：`type=(desc−a300a020)>>3×0xCCCCCCCD` | 基线应为 `0xffffffffa300a000`；`0x20` 之差不可能同时成立，`a300a020` 视为旧值/笔误。2026-10-18 反汇编确认 `addi a4,a4,-1390` 即 `0xffffffffa300a000`。 | `C2_ENTRY_AUDIT_20261010.md:12-15`（`a300a000`） vs `KERNEL_PRIVESC_C1_C2_PROOF_20261008.md:18-20`（`a300a020`） | 已裁决（2026-10-18 静态反汇编：`addi a4,a4,-1390`→`0xffffffffa300a000`；见 OQ-03） |
| C-06 | `power_governor_reverse/MODS570215_MCLK_3999_4000_STATIC_FINDINGS_20260903.md:15` | “后续 MCLK command-0 请求发现 mailbox busy → PMU 执行 ebreak” | 本案日志 marker 是 **`0x25728` = completion wait 超时**；`0x256c8` 才对应 busy。失败序列应写为“等待 completion 预算耗尽 → PMU 主动断言停机”，“mailbox busy”降级为**未决假说**。 | `power_governor_reverse/mclk4000_root_hunt_20261009/notification_failure/REPORT.md:17`；`power_governor_reverse/mclk4000_root_hunt_20261009/REPORT.md:7,32` | 已裁决（busy 假说见 OQ-08） |
| C-07 | `GSP_TOCTOU_SUCCESS.md:1,7` | “GSP 方向 TOCTOU 攻击 — 成功证明”“成功写入固件，绕过签名验证” | 只成立“**FMC 副本写入到达物理内存且发生在 boot 期间**”（`fw[0x10000] d564→0902`，GPU 仍工作）。FMC 已在 I-Cache，写入点可能是死代码，**执行未证明**；不能称“绕过签名验证”。 | 同文 `:9,47-55`（作者自评 B 级；“为什么 GPU 不崩”）；`ELF_TOCTOU_BREAKTHROUGH.md:5-12`（ELF 窗口才证明“被读取”） | 已裁决 |
| C-08 | `TOCTOU_FINAL_REPORT.md:44` | “没有‘漏检’窗口”（标题与结论未限定对象） | 该结论**只对 FMC（290KB）成立**；GSP ELF（27MB）存在读取窗口（`sendAndRead` 后 100ms 仍被读）。标题应加“（FMC 方向）”。 | `ELF_TOCTOU_BREAKTHROUGH.md:5-12,22`；`SESSION_20260929_TOCTOU.md:3-5` | 已裁决 |
| C-09 | `FSP_BUG_INVENTORY.md:4` | “永久损伤 7”“单条 ROMREAD → FSP runtime dispatcher 永久死亡” | 现象是“一段畸形 NVDM/传输序列后 FSP runtime 服务持续不可用”；**最小充分触发未知**，期间未逐步恢复并复验健康。分类计数应保留，因果表述必须降级。 | `PSIRT_DRAFT_1_GB202_FSP_RUNTIME_DOS.md:5`（内部注记明确撤回单条说法） | 已裁决（触发序列见 OQ-06） |
| C-10 | `GSP_PRIVESC_FINAL_PLAN_20261008.md:327` | “在 GB20X REAL 真内核上重证完成” | 应为“**在模拟器加载的真实 GB20X 内核镜像**（`kernel_gb20x_REAL.elf`，由 `rv64_emu.py` 执行）上重证”。不是真机。 | 同文 `:331-348`（`emu_test_c2_gb20x.py`）；`KERNEL_PRIVESC_C1_C2_PROOF_20261008.md:1-3` | 已裁决 |
| C-11 | `★AUTHORITATIVE_PROGRESS_v2_20261013.md:87` | 标题“四、内存布局 (从模拟器PMP窗口+实测)” | 模拟器拓扑与真机可写区必须分成两张表；真机部分只保留有 E0/E1 证据的项（如 `0x0C20xxxx` 可写、`0x9300xxxx` 不可执行）。 | `★V5_STATUS_20261016.md:757-761`（真机可执行域）；`C2_ENTRY_AUDIT_20261010.md:3`（模拟器部分） | 已裁决 |
| C-12 | `CC_FINAL_REPORT.md`（全文恢复方案段） | “切槽 + `prc_rw w 8 0`”可恢复 CC 锁死 | 该方案**已于 2026-09-29 05:17 实测失败**；恢复程序以 v2 为准。 | `BIOS_SLOT_CC_LOCK_RECOVERY.md:1-5`（“v1 基于过时状态 … 已实测失败 … 本文按完整记录重写”） | 已裁决 |
| C-13 | `gsp_qemu/README.md:93,115`；`gsp_qemu/docs/LAB_BOOT.md:86` | `cd /home/user/rt_5090_project/gsp_qemu`；输入默认 `/home/user/rt_5090_project/gspkm` | 本副本应使用 `/home/user/gsp_libos_clean/gsp_qemu` 与 `/home/user/gsp_libos_clean/gspkm`。命令会因旧路径失败。 | `COPY_MANIFEST.md`（Source/Destination） | 已裁决（尚未改原文，见 OQ-15） |
| C-14 | `C2_ENTRY_AUDIT_20261010.md:3,5` | “对象: `kernel_gb20x_REAL.elf`(GB20X真内核)”；“A=真内核指令级/模拟器互证” | “真内核”是**真机固件里的内核镜像**，不是真机执行。应写“真实内核镜像（静态 + 模拟器）”。 | `docs/EVIDENCE.md` §2（E4 定义）；`KERNEL_PRIVESC_C1_C2_PROOF_20261008.md:1-3` | 已裁决 |
| C-15 | `FSP_COMPLETE_TRUST_CHAIN.md:5-10`；`FSP_TRUST_CHAIN_MODEL.md:8-16` | 信任链的“实验确认版/完整矩阵”分散在两份，均未标注版本适用范围 | 结论以 `FSP_ULTIMATE_FINDINGS.md` 为准；矩阵保留为附录。所有 FSP 结论需标注固件版本（610.57.04 / 615.71.09）。 | `FSP_ULTIMATE_FINDINGS.md:1,7-16`；`ORIGINAL_BIOS_SLOT_FORENSICS_20261013.md:10`（615.71.09 观察） | 已裁决 |
| C-16 | `HANDOFF_K31.md:3-6` | “K3-1 在裸机上 crash 在 0x1b8ffbc，VM 环境需要重建” | 页首自注已更正：① 任意读/写原语已于 9-26 在 VM 实测打通；② `0x1b8ffbc` 已有静态解释（有效通道集合变空），裸机 K=33 失败是回调路径未触发。结论以 `K31_FINAL_REPORT.md` 为准。 | `HANDOFF_K31.md:7-10`（自注）；`K31_FINAL_REPORT.md:5-9` | 已裁决 |
| C-18 | `COT_INJECTION_FINDINGS.md:5-10` | 不同 `gspFmcSysmemOffset` 得到不同响应，推断 FSP 会按内容处理 COT | COT（NVDM 0x14）只在 FSP **boot-phase** dispatcher 有 handler；runtime dispatcher **静默丢弃**（无响应、无错误、通道不受影响）。初版观察不能作为 runtime 行为。 | `COT_FINAL_VERDICT.md:8,14-15`；`FINDINGS.md` FSP-04 | 已裁决 |
| C-17 | `FSP_LINE_COMPLETE_20260926.md:1-10` | 早期“FSP 线完整记录/结论速览” | 作为历史总览保留，但其中的 FSP 结论应替换为 `FSP_ULTIMATE_FINDINGS.md` 与 `PSIRT_DRAFT_1` 的措辞。 | `FSP_ULTIMATE_FINDINGS.md:7-16`；`PSIRT_DRAFT_1_GB202_FSP_RUNTIME_DOS.md:5` | 已裁决 |
| C-19 | `SESSION_20261025_NIGHT_FULL_REPORT.md:3-6,202-237` | “GSP BADF 不可恢复、需 SPI 编程器”；把整晚状态归因于永久 FSP/InfoROM/fuse 锁 | 最初 heartbeat/RPC/watchdog 故障和若干复位后失败确实发生；但 00:11 重启后授权服务已成功读取 GPU，最后阶段又混入缺失 `/dev/nvidia0`、cgroup 权限和错误绑定检查。不能推出永久 fuse/InfoROM 锁或 SPI 必然修复。 | `GSP_GLM53_CONTEXT_AUDIT_20261026.md`；`GSP_RECOVERY_20261026.md` | 已裁决 |
| C-20 | `FSP_INFOROM_PERSISTENCE_20260928.md:13-34`；`FINAL_STATUS_20260928.md:21,42-52` | PRC 状态已被证明写入每槽 InfoROM flash，并形成固定不可逆毒记录 | 确实观察到跨驱动周期、reset domain 乃至部分冷启动复现的状态；但物理 flash 记录、位置和唯一触发未被证明。SBR 恢复、槽位取证和后续复核要求把“固定 flash poison record”降级为假说。 | `SBR_RECOVERY_DISCOVERY.md:61-75`；`PSIRT_DRAFT_2_GB202_WPR2_PERSISTENT_STATE.md:1-13,53-61,267-279`；`ORIGINAL_BIOS_SLOT_FORENSICS_20261013.md:1-25` | 已裁决（存储机制仍未决） |
| C-21 | `AUTHORITATIVE_STATUS.md` 旧版 FSP-ENCRYPT；早期明文搜索笔记 | 仅写“AES-GCM/芯片内密钥”，或把 host software decrypt 与目标 `FSP_RUN` 解密链混为一谈 | MODS 570/FieldDiag 580 的 host helper 证明的是 **AES-256-GCM consumer ABI**：32B caller-supplied key、12B IV、16B tag、空 AAD。没有建立该 helper 到目标 `FSP_RUN`、片内 KDF/root producer 或明文导出的数据流。 | `fsp_plaintext_audit_20261027/V6_CRYPTO_KDF_CONSUMER_AUDIT.md`；`fsp_plaintext_audit_20261027/FINAL_STATUS_AND_RESUME_GUIDE_20261027.md` | 已裁决 |
| C-22 | `README.md` 旧 2026-10-25/26 更新；`SESSION_20261025_NIGHT_FULL_REPORT.md` 的 Dell 段 | Dell updater `0xad4933` 是 FSP AES-CMAC/DMOVERAES128 verifier | `0xad4933` 实际是 OpenSSL `bsaes_xts_decrypt` 路径；没有证明它是 FSP verifier。 | `fsp_plaintext_audit_20261027/FINAL_STATUS_AND_RESUME_GUIDE_20261027.md`；`vbios_diff/dell_8d_payload/DELL_VERIFIER_RE_20261026.md` | 已裁决 |
| C-23 | `README.md` 旧 2026-10-25/26 更新；`parallel/fsp_attack_20261026/FSP_PLAINTEXT_ASSAULT_20261026.md` | 约 `1.2×10^12` 候选全阴性等于 key space exhaustion | 后续审计发现旧 CUDA 搜索器的首块过滤会漏真 key，且主要模型包含 AES-128/错误布局/有限 AAD 假设；该运行只能记录为“未命中”，不能证明空间穷尽。当前验收标准是 AES-256-GCM tag。 | `fsp_plaintext_audit_20261027/REPORT.md`；`fsp_plaintext_audit_20261027/FINAL_STATUS_AND_RESUME_GUIDE_20261027.md` | 已裁决 |

## 1. 更正后的“标准表述”（可直接复制）

- **t0=4 fast path**：受控 lab 实验中，`t0=4/stval=0` 进入 `0x930042f8` 只做 state 0→1、ref 不变、不调 `0x93005b26`/handler；自然 boot 未命中 t0=4；**U-mode 可达性未证明**（E3）。
- **对象销毁**：GB20X `RELEASE=0x93005b26`，`slot=0xffffffffa300a000+type*40+8`，`jalr@0x93005b60`（E2/E4）；GB10Y 旧内核为 `0x930060f2`、`+0x28`。
- **FSP TOCTOU**：FMC 无漏检窗口（E0）；GSP ELF 有读取窗口（E0）；写入→执行未证明。
- **FSP runtime DoS**：畸形序列后 runtime 服务持续不可用（E0）；最小充分触发未知（E5）。
- **MCLK**：18000MHz/+3999 通过（E0）；18001MHz/+4000 失败于 completion wait 超时（E0），marker `0x25728`，不是 `0x256c8`。
- **C1/C2**：仅在旧 Python 模拟器 + 真实 GB20X 内核镜像上闭合（E4），真机未验证。
- **FSP v6 密码模型**：host software consumer 为 AES-256-GCM、32B caller key、12B IV、16B tag、空 AAD（E4）；data key、KDF/root 和目标明文仍未知。
- **硬件状态**：最初 GSP/FSP 故障真实存在，但“永久 fuse/InfoROM 锁、必须 SPI”不成立；恢复记录必须按阶段读取。当前决定是不再对现有卡做真机固件实验。

## 2. 未写入本表的“自我更正”

以下文档已在原文内部自我更正，无需再补丁，但引用时要注意版本：

- `GSP_PRIVESC_FINAL_PLAN_20261008.md:2481-2484`：明确 `0x930060f2/+0x28` 是 GB10Y。
- `HANDOFF_K31.md:7-10`：页首自注两处过时。
- `BIOS_SLOT_CC_LOCK_RECOVERY.md:1-5`：明确 v1 方案失败。
- `PSIRT_DRAFT_1/2` 的内部 review note：明确撤回单条 DoS 与双 flash 损坏的说法。
- `docs/DEDUP_PLAN.md` §3：本表的来源分析。
