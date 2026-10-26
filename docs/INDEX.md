# GSP/FSP/LibOS 文档索引（INDEX）

> 初始生成日期：2026-10-18（第一步产物，仅登记，未移动/删除/覆盖任何原文档）。
> 初始范围：`/home/user/gsp_libos_clean` 下 **230** 份 `.md`。该主体表保持历史快照；2026-10-25 至 10-27 新增的 25 份公开研究文档列在“零、后索引新增文档”中，没有重新生成全部旧条目。
> 已排除固件、Ghidra 工程、构建目录和缓存等大体量/专有材料。

## 图例

**状态**

- `权威`：当前应作为该主题的基准引用（可带限定，如“仅限 FMC”“模拟器”）
- `权威(⚠…)`：内容重要，但存在证据等级混写或结论强于证据，引用时必须带限定
- `被取代`：结论被同主题更新文档覆盖，保留作历史依据
- `重复`：与另一份内容实质相同（含字节相同）
- `一次性`：会话记录、交接、单次实验、草稿；不应作为结论来源
- `参考`：第三方或厂商资料，不是本项目实验证据

**证据类别**

- `真机`：在物理 RTX 5090 上执行/观测（含宿主直连）
- `真机VM`：物理卡直通给 VM，在客体内执行（仍是真机行为，但环境不同）
- `静态`：只读反汇编、源码/头文件、VBIOS/固件文件分析
- `模拟器`：QEMU lab 或 `rv64_emu.py` 中执行（**不是**硬件行为）
- `综合`：基于既有文档的复盘、清单、汇辑（二手）
- `公开`：网页/第三方资料
- `源码`：厂商开源代码
- `元`：项目约定/清单

## 统计

| 区域 | 数量 |
|---|---:|
| 一、项目元文档（2） | 2 |
| 二、GSP LibOS 提权与对象生命周期（根目录，24） | 24 |
| 三、FSP 线：信任链 / TOCTOU / 通道 / PRC（根目录，24） | 24 |
| 四、gsp_qemu 模拟器主线（6） | 6 |
| 五、FSP/GSP 静态战役（fsp_ace_static + fsp_code，13） | 13 |
| 六、时钟 / 电压 / 功耗（root + power_governor_reverse，78） | 78 |
| 七、风扇 / L2 / SM / ISA（17） | 17 |
| 八、会话交接 / 复盘 / 事故恢复 / 取证（23） | 23 |
| 九、对外投稿与 issue 草稿（18） | 18 |
| 十、VM / VFIO 实验环境（17） | 17 |
| 十一、厂商源码（8） | 8 |
| **合计（2026-10-18 主体表）** | **230** |

## 零、后索引新增文档（25，2026-10-25 至 2026-10-27）

| 路径 | 状态 | 证据类别 | 一句话摘要 |
|---|---|---|---|
| `BLACKWELL_UNBOUNDED_COPY_SURFACE_20261025.md` | 权威(静态边界) | 静态+综合 | 对 Ampere→Blackwell 无界拷贝攻击面做结构审计：旧 SEC2 booter 入口消失，FSP 本体仍是密文黑盒，明文 RISC-V GSP 层保留多处 count 类缺陷。 |
| `SESSION_20261025_NIGHT_FULL_REPORT.md` | 历史事故记录(⚠以更正表为准) | 真机+综合 | 10-25/26 FSP 明文攻击及 GPU 事故记录；“永久 BADF/SPI”结论已被 C-19 修正。 |
| `parallel/fsp_attack_20261026/FSP_PLAINTEXT_ASSAULT_20261026.md` | 历史搜索记录(⚠非空间穷尽证明) | 静态+计算 | 大规模候选搜索与 FSP 明文攻击记录；旧过滤/模型局限见 C-23。 |
| `parallel/fsp_attack_20261026/GSP_RM_DERIVEHWKEY_RE_20261026.md` | 权威(静态限定) | 静态 | GSP-RM hardware-key/kslot 路径逆向，证明可见的是运行期 aperture/keyslot consumer，不是目标 root/data-key producer。 |
| `parallel/fsp_attack_20261026/astra_srand32_report.md` | 参考 | 静态+计算 | Astra srand32 候选生成与阴性结果记录。 |
| `vbios_diff/dell_8d_payload/DELL_VERIFIER_RE_20261026.md` | 权威(更正后) | 静态 | Dell payload verifier 逆向；`0xad4933` 为 OpenSSL XTS 路径而非 FSP CMAC verifier。 |
| `GSP_GLM53_CONTEXT_AUDIT_20261026.md` | 权威 | 日志取证 | 分阶段复核 10-25/26 事故：真实 GSP 故障、恢复失败、权限/设备节点误判必须分开。 |
| `GSP_RECOVERY_20261026.md` | 权威(短时恢复) | 真机 | 补回设备节点、修复 DKMS/黑名单残留并验证 `nvidia-smi`/CUDA；不解释全部历史根因。 |
| `HARDWARE_DO_NOT_TOUCH_RISK_SUMMARY_20261027.md` | 权威(风险收束) | 综合 | 汇总真机 FSP/GSP/WPR2/PCIe/PMU/内核风险，明确停止现有 RTX 5090 的固件实验。 |
| `vm_mods_lab/MODS570215_DIAGNOSTIC_SUMMARY_20260825.md` | 权威(既有实验摘要) | 真机VM | MODS 570.215 诊断汇总：18001 MHz 导致 PMU halt；600W 配置下遥测峰值超过 657W。 |
| `fsp_plaintext_audit_20261027/FINAL_STATUS_AND_RESUME_GUIDE_20261027.md` | 权威(专项最终状态) | 综合 | GB202 FSP 明文专项最终状态：未取得明文；仅在新工件或独立硬件授权出现时恢复。 |
| `fsp_plaintext_audit_20261027/REPORT.md` | 权威 | 综合 | 离线密码、FuseRework、FieldDiag 580、制造包和公网搜索的主报告。 |
| `fsp_plaintext_audit_20261027/FUSEREWORK_ABI.md` | 权威 | 静态 | FuseRework `0x0f` 请求 ABI、固定认证材料尺寸及 4-byte ACK。 |
| `fsp_plaintext_audit_20261027/FSP_SENDER_CALLSITE_AUDIT.md` | 权威 | 静态 | MODS 570 sender 的七个直接调用点；无 bulk plaintext response。 |
| `fsp_plaintext_audit_20261027/FUSEREWORK_CALLCHAIN_DIFF.md` | 权威 | 静态 | 570.151/215/278 FuseRework 文件加载与调用链差分。 |
| `fsp_plaintext_audit_20261027/V6_CRYPTO_KDF_CONSUMER_AUDIT.md` | 权威 | 静态 | 闭合 AES-256-GCM host consumer ABI；未找到目标 key/KDF/root producer。 |
| `fsp_plaintext_audit_20261027/GB202_MFG_HIDDEN_REWORK_AUDIT.md` | 权威 | 静态 | GB202 制造包隐藏返修审计；未找到目标四件套或工程 helper。 |
| `fsp_plaintext_audit_20261027/DGX_SPARK_FIELDDIAG_AUDIT.md` | 权威 | 静态 | 公开 DGX Spark FieldDiag/MODS 580 包审计；无目标 `FSP_RUN` 明文或 FuseRework 四件套。 |
| `fsp_plaintext_audit_20261027/FIELDDIAG580_AARCH64_FSP_SENDER_AUDIT.md` | 权威 | 静态 | AArch64 FieldDiag 580 sender 七个调用点，响应仅 4/12/24 bytes。 |
| `fsp_plaintext_audit_20261027/FIELDDIAG580_PRIVATE_GFW_ATTRIBUTION.md` | 权威 | 静态 | 29 个 type-4 GFW 的公开/私有归属；不应误标为 FuseRework。 |
| `fsp_plaintext_audit_20261027/WEB_HUNT_ENGLISH.md` | 公开搜索记录 | 公开 | 英语论坛、官方条目及网盘搜索；无可验证目标文件。 |
| `fsp_plaintext_audit_20261027/WEB_HUNT_CHINESE.md` | 公开搜索记录 | 公开 | 中文论坛、B 站及网盘线索搜索；无可验证目标文件。 |
| `fsp_plaintext_audit_20261027/WEB_HUNT_RU_REPAIR.md` | 公开搜索记录 | 公开 | 俄语/东欧维修社区与镜像搜索；无可验证目标文件。 |
| `fsp_plaintext_audit_20261027/WEB_HUNT_INDEX_ARCHIVES.md` | 公开搜索记录 | 公开 | 代码托管、归档和 NVIDIA 公共索引搜索。 |
| `fsp_plaintext_audit_20261027/WEB_HUNT_MEISTER_V6.md` | 权威(远程目录取证) | 公开+静态 | 用 Range/7z/Btrfs metadata 重建 22.38GB 社区镜像当前文件树，确认无目标文件。 |

## 一、项目元文档（2）

| 路径 | 标题 | 日期 | 主题 | 状态 | 证据类别 | 一句话摘要 |
|---|---|---|---|---|---|---|
| `AGENTS.md` | LibOS / GSP 模拟任务约定 | ~2026-10-18 | 项目约定 | 权威 | 元 | LibOS/GSP 模拟工作约定：只走 gsp_qemu 主线、不伪造启动成功、开工先读三份 QEMU 文档。 |
| `COPY_MANIFEST.md` | GSP/FSP/LibOS Clean Copy — Manifest | ~2026-10-18 | 拷贝清单 | 权威 | 元 | 说明本目录拷贝了哪些资料、哪些镜像/二进制被排除，用途仅限文档整理。 |

## 二、GSP LibOS 提权与对象生命周期（根目录，24）

| 路径 | 标题 | 日期 | 主题 | 状态 | 证据类别 | 一句话摘要 |
|---|---|---|---|---|---|---|
| `C2_ENTRY_AUDIT_20260926.md` | (无 H1) | 2026-09-26 | C2 入口审计 | 一次性(文件名与内容不符) | 真机 | 只剩“二十四、根因发现 4096 字节写入摧毁相邻堆对象(2026-10-11)”一节残片，无标题，与文件名日期矛盾。 |
| `C2_ENTRY_AUDIT_20261010.md` | C2 入口审计 + 精确算术闭合 — 2026-10-10 深夜 session | 2026-10-10 | C2 入口审计 | 权威 | 静态+模拟器 | C2 入口审计与精确算术闭合：TYPECALC/RELEASE 逐值复现、staging 队列现场；明确标注纯静态+模拟器。 |
| `DS_SESSION_K31_RECOVERY_20260929.md` | DS 会话恢复 — K3-1 完整上下文与战略收敛（2026-09-29 晚） | 2026-09-29 | K3-1 交接 | 一次性 | 综合 | 从 DeepSeek 主会话恢复的 K3-1 增量上下文与战略收敛；含会话文件路径，属过程记录。 |
| `ELF_TOCTOU_BREAKTHROUGH.md` | 🔥 GSP ELF TOCTOU 窗口确认 — 2026-09-29 14:10 | ~2026-09-29 | TOCTOU | 权威 | 真机 | GSP ELF(27MB) 读取窗口确认：sendAndRead 后 100ms 写 ELF 头即致 GSP 挂死；证明被读到，未证明被执行。 |
| `FN73_PARSER_HUNT.md` | fn73 解析器静态追踪 — 进度与交接 (2026-10-01) | ~2026-10-01 | fn73 静态 | 一次性 | 静态 | fn73(SET_REGISTRY) 解析器指令级链路追踪进度与交接。 |
| `GSP_61571_ADDR_MAP.md` | GSP 615.71.09 关键地址定位 — 2026-09-29 | ~2026-09-29 | 615.71 地址 | 被取代 | 静态 | 615.71.09 三个关键函数地址初版（tdispmgr 0x01ab7e04 等）；被 FINAL_ADDR_MAP 取代。 |
| `GSP_61571_FINAL_ADDR_MAP.md` | GSP 615.71.09 完整地址映射 — 2026-09-29 最终版 | ~2026-09-29 | 615.71 地址 | 权威 | 静态 | 615.71.09 完整地址映射最终版（K3-1 所需函数与偏移）；仅对该固件版本有效。 |
| `GSP_PRIVESC_FINAL_PLAN_202601008.md` | 🎯 FN=76完整链验证 + C2尝试 | ~2026-10-09 | 提权方案 | 一次性(文件名日期笔误) | 真机 | 短篇 FN=76 链验证（Xid 120 @0x18c09c8）；与 20261008 方案同族但更早。 |
| `GSP_PRIVESC_FINAL_PLAN_20261008.md` | 🎯 GSP 真机提权最终方案 (2026-10-08 定稿) | 2026-10-08 | 提权方案 | 权威(计划) | 真机+静态+模拟器 | 120KB 真机提权总方案：武器库按真机/模拟器/静态逐项标注，含三别名写入矩阵与 Phase1/2 分支；“真内核”指真机 ELF，易误读为真机验证。 |
| `GSP_TOCTOU_SUCCESS.md` | GSP 方向 TOCTOU 攻击 — 成功证明 | ~2026-09-29 | TOCTOU | 被取代(结论过强) | 真机 | 声称“写入固件、绕过签名验证”，实际只证明 FMC 副本在 boot 期被改且 GPU 仍工作；作者自评 B 级，标题强于证据。 |
| `HANDOFF_K31.md` | 交接文档 — GSP 代码执行攻击 (K3-1) | ~2026-09-29 | K3-1 交接 | 一次性(页首已自更正) | 真机 | K3-1 交接：裸机 crash @0x1b8ffbc、VM 需重建；页首自注两处已过时（读/写原语已通、crash 有静态解释）。 |
| `HOT_SWAP_GSP_ANALYSIS.md` | ★ 热切换 GSP 运行时代码 — K3-1 变态用法分析 | ~2026-09-29 | K3-1 构想 | 一次性 | 真机 | 热切换 GSP 运行时代码的用法分析（干净写原语改行为不重启）；属构想，未验证成链。 |
| `K31_FINAL_REPORT.md` | K3-1 实机测试最终报告 — 2026-09-29 深夜 | ~2026-09-29 | K3-1 结论 | 权威(结论) | 真机 | K3-1 实机最终判定：溢出漏洞存在但无法精确利用，溢出区含关键堆结构，任何写入都在回调前崩。 |
| `K31_INJECTION_SETUP.md` | K3-1 注入环境搭建记录 (2026-09-30 傍晚) | ~2026-09-30 | K3-1 环境 | 一次性 | 真机VM | 610.57 注入环境搭建记录：基础设施就绪，缺用户态库未触发。 |
| `KERNEL_PRIVESC_C1_C2_PROOF_20261008.md` | LibOS 内核提权漏洞 C1/C2 — 模拟器实证 (2026-10-08) | 2026-10-08 | C1/C2 证明 | 权威(模拟器) | 模拟器 | rv64_emu + GB20X 真内核 ELF 证明 C1 双释放、C2 页头投毒→S-mode jalr；标题 “PROOF” 必须始终带“模拟器”限定。 |
| `MCTPSUBMIT_CHAIN.md` | mctpSubmit 解引用链 — 静态追踪成果 (2026-10-01 深夜) | ~2026-10-02 | 静态链 | 权威 | 静态 | mctpSubmit 解引用链静态成果：从 K3-1 tdispmgr 劫持到 session/queue 的对象图谱。 |
| `PRIMITIVE_CROSS_ANALYSIS.md` | 原语交叉分析 — 组合攻击面 | ~2026-09-29 | 原语交叉 | 综合 | 综合 | 把 K3-1 溢出写、读/写 gadget、FSP 通道等原语组合成攻击面的交叉分析；多为推断。 |
| `REGISTRY_INJECTION_SURFACE.md` | 宿主→GSP 注册表注入攻击面 — 普查报告 (2026-10-01 凌晨) | ~2026-10-01 | 注册表注入 | 权威 | 真机 | 宿主 root 经 fn73 把任意注册表键送进 GSP-RM，GSP 侧无认证消费；含可复现路径。 |
| `VULN_INVENTORY.md` | RTX 5090 (GB202) 安全研究 — 漏洞与攻击面总目录 | ~2026-10-01 | 漏洞目录 | 权威(目录) | 综合 | 截至 2026-10-01 的 GB202 漏洞与攻击面总目录，按已证实/部分/理论/已排除分级。 |
| `★AUTHORITATIVE_PROGRESS_20261011.md` | GSP LibOS 提权研究 — 权威进度文件 | 2026-10-11 | 提权总档 | 被取代 | 真机+静态+模拟器 | 第一版权威档：K3-1 溢出、C1/C2、t0=2 walk 与内存布局；自述被后续版本覆盖。 |
| `★AUTHORITATIVE_PROGRESS_v2_20261013.md` | GSP LibOS 提权研究 — 权威进度文件 v2 | 2026-10-13 | 提权总档 | 被取代 | 真机+静态+模拟器 | v2 累计档（62 小时）：内存布局与 C2 设计；同一节标题内混用“模拟器 PMP 窗口+实测”。 |
| `★AUTHORITATIVE_PROGRESS_v3_20261015.md` | GSP LibOS 提权研究 — 权威进度文件 v3 | 2026-10-15 | 提权总档 | 被取代 | 真机+静态 | v3 精简档，声明覆盖 v2；主要保留状态与下一步，细节少于 v2。 |
| `★V4_PROGRESS_20261016.md` | GSP LibOS 提权研究 — 进度文件 V4 | 2026-10-16 | 提权总档 | 被取代 | 真机+静态 | V4 单页状态：v25.1 平台、backend 0x0100CF9C 解码、msgq 协议、walk(t0=2)；自述覆盖 v2/v3。 |
| `★V5_STATUS_20261016.md` | GSP提权研究 — 状态快照 V5 | 2026-10-16 | 提权总档 | 权威(⚠证据混写) | 真机+静态+模拟器 | 最新最全状态档（写到 10-18）：v25.3 两步溢出、B8 回调劫持、t0=2 walk、20 条归档结论；第 784 行把 lab 的 t0=4 fast path 写成“真正的 U-mode 路径”。 |

## 三、FSP 线：信任链 / TOCTOU / 通道 / PRC（根目录，24）

| 路径 | 标题 | 日期 | 主题 | 状态 | 证据类别 | 一句话摘要 |
|---|---|---|---|---|---|---|
| `B4_B5_B7_RESULTS.md` | B4/B5/B7 实验结果 — 2026-09-29 05:15 | ~2026-09-29 | FSP 实验 | 一次性 | 真机 | B4/B5/B7 三个 FSP 黑盒实验：COT gspFmcSysmemOffset oracle 等均不可行，runtime 关闭 boot 级消息。 |
| `CC_ATTEMPT3_RESULT.md` | CC 模式尝试 #3 — 结果与分析 | ~2026-09-28 | CC 模式 | 一次性 | 真机 | CC 模式第三次尝试：knob 6/8 写入成功并 flash 持久化，未达成目标。 |
| `CC_FINAL_REPORT.md` | CC 模式研究 — 最终报告 | ~2026-09-28 | CC 模式 | 被取代 | 真机 | CC 模式最终报告与四层攻击面地图；“切槽+prc_rw 恢复”方案已被 9-29 实测推翻。 |
| `COT_FINAL_VERDICT.md` | COT 注入攻击 — 最终定论 | ~2026-09-28 | COT 注入 | 权威 | 真机 | COT(NVDM 0x14) 只在 FSP boot-phase dispatcher 有 handler，runtime 静默丢弃；推翻早前“按内容响应”。 |
| `COT_INJECTION_FINDINGS.md` | COT Payload 注入 — 初步实验结果 | ~2026-09-28 | COT 注入 | 被取代 | 真机 | COT payload 初步实验，据不同响应推断 FSP 会处理内容；被 COT_FINAL_VERDICT 否定。 |
| `COT_SIGNATURE_FINDINGS.md` | COT 注入实验 — 重大安全发现 | ~2026-09-28 | COT 签名 | 权威(并入信任链) | 真机 | COT hash384 全 0xFF 仍能启动的 A 级证据，是 FSP 信任链模型的核心实验。 |
| `FSP_BUG_INVENTORY.md` | FSP Bug/异常行为完整清单 — 截至 2026-10-02 | ~2026-10-07 | FSP 缺陷清单 | 权威(归因需降级) | 真机 | 截至 10-02 的 32 项 FSP 黑盒异常（永久损伤 7）；“单条 ROMREAD 即永久 DoS”已被 PSIRT DRAFT 1 撤回。 |
| `FSP_CHANNEL_AUDIT_20261002.md` | FSP通道审计终极结论 — 2026-10-02 会话 | 2026-10-02 | 通道审计 | 权威 | 真机 | MNOC 端口矩阵、ROMREAD 全端口失败与 FSP runtime 死亡的当日结论。 |
| `FSP_COMPLETE_TRUST_CHAIN.md` | NVIDIA RTX 5090 FSP 完整信任链 — 实验性安全模型 | ~2026-09-29 | 信任链 | 被取代 | 真机 | FSP 信任链实验模型第一版（COT 字段失效、WPR 签名真实）。 |
| `FSP_INFOROM_PERSISTENCE_20260928.md` | 2026-09-28 完整研究记录 —— FSP InfoROM 持久化 + 双 BIOS 差异 + nvflash 拦截 | 2026-09-28 | InfoROM | 一次性 | 真机 | 9-28 全天记录：InfoROM 持久化、双 BIOS 差异与 nvflash 拦截。 |
| `FSP_LINE_COMPLETE_20260926.md` | FSP 线完整记录 —— RTX 5090 (GB202, ASUS Astral) | 2026-09-26 | FSP 线总览 | 部分被取代 | 综合 | FSP 线第一份完整记录（来源 RESUME_BRIEF 与实测日志），可独立阅读；后被信任链文档细化。 |
| `FSP_MSG_LAYER_AUDIT.md` | FSP 消息层攻击面审计 — 2026-09-28 深夜 | ~2026-09-28 | 消息层审计 | 权威 | 真机 | FSP 消息层测试矩阵（PRC/NVLink/firmware-update 等）逐项结果。 |
| `FSP_STAGE0_RECON_20260926.md` | FSP 顶级漏洞研究 — 阶段 0（无害只读侦察）结果 | 2026-09-26 | 阶段0侦察 | 权威 | 真机 | 阶段 0 只读侦察：工具、寄存器前后对照、无 Xid；后续所有 FSP 实验的基线。 |
| `FSP_TRUST_CHAIN_MODEL.md` | FSP 信任链完整安全模型 — 实验确认版 | ~2026-09-28 | 信任链 | 被取代 | 真机 | 信任链实验矩阵版（hash/key/signature 逐项破坏）；被 FSP_ULTIMATE_FINDINGS 汇总。 |
| `FSP_ULTIMATE_FINDINGS.md` | FSP 信任链完整逆向 — 最终研究成果 | ~2026-09-29 | 信任链 | 权威 | 真机 | FSP 信任链最终成果：95% COT 验证字段被忽略、WPR 层签名真实。 |
| `GSP_FSP_IFACE_20261006.md` | GSP↔FSP 通信接口逆向 + 泄漏读验证 — 2026-10-06 深夜 | 2026-10-06 | GSP↔FSP 接口 | 权威 | 静态+真机VM | 73KB 的 GSP↔FSP 接口逆向（EMEM/MNOC/方法槽）加泄漏读验证；地址仅对 610.57.04。 |
| `INFOROM_QUERY_STATUS_20260928.md` | InfoROM 查询 — 最后一步状态 (2026-09-28 深夜) | 2026-09-28 | InfoROM 查询 | 一次性 | 真机 | InfoROM 查询补丁 95% 完成：函数已编译进驱动，缺最后一步。 |
| `MNOC_PORT0_PROTOCOL.md` | MNOC port 0 完整协议手册 — 从发现到验证 | ~2026-09-30 | MNOC 协议 | 权威 | 真机 | MNOC port 0 完整协议手册，在脏卡上闭合验证；纠正 B7b 旧结论。 |
| `PRC_COMPLETE_LOGIC.md` | PRC 完整运行逻辑 — 从 gpu-admin-tools 逆向 | ~2026-09-28 | PRC | 权威 | 综合 | 从 gpu-admin-tools 源码逆向的 PRC 协议栈与运行逻辑。 |
| `PRC_KNOB_MAP.md` | PRC Knob 完整地图与持久化机制 — 实验确认 | ~2026-09-28 | PRC | 权威 | 真机 | 47 个 PRC knob 完整地图与 flash 持久化机制，全部实测。 |
| `SESSION_20260929_TOCTOU.md` | 2026-09-29 凌晨 — TOCTOU 攻击完整实验 + FSP 最终防御模型 | 2026-09-29 | TOCTOU | 权威 | 真机 | FSP 全阶段完整性检查：验证期写入→0xFFFF，加载期写入→FSP 锁死；含热重载方法。 |
| `TOCTOU_FINAL_REPORT.md` | TOCTOU 攻击完整实验报告 — 最终结论 | ~2026-09-29 | TOCTOU | 权威(仅限 FMC) | 真机 | FMC 方向 TOCTOU 结论：验证与加载间无漏检窗口；该结论不适用于 GSP ELF。 |
| `UCODES_ANALYSIS.md` | ucodes_ga10x.bin 分析结果 — 2026-09-29 14:45 | ~2026-09-29 | 固件格式 | 一次性 | 静态 | ucodes_ga10x.bin(55.5MB) 的 NVUC 容器结构解析。 |
| `V3_KEY_STATIC_ANALYSIS_20261002.md` | V3 注册表安全键 — GSP 固件消费点静态分析 (2026-10-02) | 2026-10-02 | 注册表键静态 | 权威 | 静态 | V3 注册表安全键在 GSP 固件中的消费点静态表。 |

## 四、gsp_qemu 模拟器主线（6）

| 路径 | 标题 | 日期 | 主题 | 状态 | 证据类别 | 一句话摘要 |
|---|---|---|---|---|---|---|
| `gsp_qemu/PROGRESS.md` | 进度记录 | ~2026-10-18 | 进度记录 | 权威 | 模拟器 | 按日期记录的 lab 进度：walk 表检查点与 GLM 假设验证（含 t0=4 fast path 受控实验）。 |
| `gsp_qemu/README.md` | QEMU-only NVIDIA GSP/LibOS 启动链开发 | ~2026-10-18 | 模拟器主线 | 权威 | 模拟器 | QEMU 主线总说明：生产 FMC 签名验证、MPU 模型、原始 LibOS→init、walk 表发布；明确列出未完成项与各 lab 测试边界。 |
| `gsp_qemu/docs/LAB_BOOT.md` | `nvidia-gsp-lab` 原始 LibOS walk 表发布检查点 | ~2026-10-18 | lab 启动 | 权威 | 模拟器 | walk 表发布检查点完整记录；明确 t0=4 fast path 是受控入口、不是 U-mode trap，并列出与真机布局差异。 |
| `gsp_qemu/docs/MPU_MODEL.md` | 固件驱动的 GSP MPU 模型与真实启动进展 | ~2026-10-18 | MPU 模型 | 权威 | 模拟器 | 固件驱动的 GSP MPU/CSR 模型与真实启动进展：原始 boot 到 init 的 PC/寄存器与下一处缺失的启动区域表。 |
| `gsp_qemu/docs/SOURCES.md` | 来源、信任边界与审查记录 | ~2026-10-18 | 来源与审查 | 权威 | 元+公开 | 固定 QEMU/NVIDIA 版本、一手源码证据、公开架构资料、同模型审查记录与认证结论边界。 |
| `gsp_qemu/docs/sources/open-iov-device-model.md` | 36 — GSP device model (in development) | ~2026-10-18 | 第三方参考 | 参考(非本项目证据) | 公开 | Open-IOV 项目 “GSP device model” 文档本地副本，仅作检索线索；本项目未采用其 Python 模型。 |

## 五、FSP/GSP 静态战役（fsp_ace_static + fsp_code，13）

| 路径 | 标题 | 日期 | 主题 | 状态 | 证据类别 | 一句话摘要 |
|---|---|---|---|---|---|---|
| `fsp_ace_static_20260927/CONTINUATION.md` | 会话延续状态 v3 —— SPDM/CC 突破后(2026-09-28 09:05) | ~2026-09-28 | 会话状态 | 一次性 | 静态 | SPDM/CC 突破后的会话延续状态 v3，含机器状态与规则。 |
| `fsp_ace_static_20260927/F1_FINAL_VERDICT.md` | F-1 最终定级:GSP-RM GPU_EXEC_REG_OPS 无界 regOpCount 栈下溢 —— A 级实锤 | ~2026-09-27 | 漏洞定级 | 权威 | 静态+真机 | F-1 定级：GPU_EXEC_REG_OPS 无界 regOpCount 栈下溢，静态预言与 dmesg 崩溃 PC 逐点对上（A 级）。 |
| `fsp_ace_static_20260927/FSP_TRANSPORT_AUDIT.md` | GSP 侧 FSP 通信栈 / MCTP 纯静态审计 | ~2026-09-27 | 传输栈审计 | 权威 | 静态 | GSP 侧 FSP 通信栈与 MCTP 的纯静态审计。 |
| `fsp_ace_static_20260927/GSP_EXEC_RUNBOOK.md` | GSP-exec → FSP GSP-lane 探测器 —— 工程 Runbook(kickoff 2026-09-27) | ~2026-09-27 | 工程 Runbook | 一次性 | 静态 | 用假对象树走 tdispmgr 包装器，让被劫持 GSP 以自身身份向 FSP 发 NVDM 探测的施工单。 |
| `fsp_ace_static_20260927/NVDM_DEMUX_AND_ENTRIES_AUDIT.md` | GSP 610.57 NVDM 解复用与宿主入口静态审计 | ~2026-09-27 | NVDM 审计 | 权威 | 静态 | 610.57 NVDM 解复用与宿主入口静态审计：收包路径不校验 NVDM type。 |
| `fsp_ace_static_20260927/RPC_LAYER_AUDIT.md` | GSP-RM RPC 分发层（E3）纯静态审计 | ~2026-09-27 | RPC 审计 | 权威 | 静态 | GSP-RM RPC 分发层（E3）纯静态审计。 |
| `fsp_ace_static_20260927/SUMMARY.md` | FSP-ACE 静态分析战役总报告(2026-09-27) | ~2026-09-27 | 静态战役总报告 | 权威 | 静态 | FSP-ACE 战役总报告：FSP runtime 为 AES-GCM 加密故静态不可直接达成；保底交付三个 B 级 GSP 溢出候选（最强 GPU_EXEC_REG_OPS）。 |
| `fsp_ace_static_20260927/artifacts/GADGET_INVENTORY.md` | GSP 610.57 Gadget 库存(为 GSP-exec ROP 链) | ~2026-09-27 | gadget 清单 | 一次性 | 静态 | GSP 610.57 gadget 库存，为 GSP-exec ROP 链准备。 |
| `fsp_ace_static_20260927/artifacts/LIVE_SESSION_LOG_20260927.md` | 实弹会话记录 2026-09-27 07:00-07:45 —— 低→高风险阶梯执行 | 2026-09-27 | 实弹日志 | 一次性 | 真机 | 2026-09-27 07:00-07:45 低→高风险阶梯执行的原始会话记录。 |
| `fsp_ace_static_20260927/notes/CONTEXT_BRIEF.md` | FSP-ACE 静态分析战役 2026-09-27 — 共享上下文 | ~2026-09-27 | 共享上下文 | 一次性 | 静态 | 战役共享上下文：目标、硬约束（纯静态）与既有战果。 |
| `fsp_ace_static_20260927/notes/FSP_SURFACE_REVISIONS.md` | FSP 侧攻击面——本轮(2026-09-27)静态新增发现与实验规格修订 | ~2026-09-27 | 攻击面修订 | 权威 | 静态 | 本轮新钉死的 FSP 攻击面事实（EMEM 队列协议、MNOC 语义、SEC2/PSEC 通道）与实验规格修订。 |
| `fsp_ace_static_20260927/notes/PUBLIC_BASELINE_CHECK.md` | NVIDIA GPU 固件公开信息基线核查 | ~2026-09-27 | 公开基线 | 权威 | 公开 | NVIDIA GPU 固件公开信息基线核查（检索截止 2026-09-27），确认公开世界无 FSP 明文/通道研究。 |
| `fsp_code/INDEX.md` | FSP 相关【明文】代码摘录(来自 GSP-RM 固件) | ~2026-09-26 | FSP 代码索引 | 权威 | 静态 | 从 GSP-RM 固件提取的 FSP 相关明文代码摘录索引与 VA 映射方法。 |

## 六、时钟 / 电压 / 功耗（root + power_governor_reverse，78）

| 路径 | 标题 | 日期 | 主题 | 状态 | 证据类别 | 一句话摘要 |
|---|---|---|---|---|---|---|
| `BLACKWELL_CONTROL_LOGIC_EXTRACTION_20260725.md` | GB202 运行时功耗/时钟控制逻辑拆解工作底稿 | 2026-07-25 | 控制逻辑底稿 | 被取代 | 真机+静态 | GB202 运行时功耗/时钟控制链拆解工作底稿（85KB），后续被 power_governor_reverse 系列细化。 |
| `BLACKWELL_VF_RUNTIME_GOVERNANCE_FINDINGS_20260724.md` | RTX 5090 / Blackwell V/F 运行时控制发现 | 2026-07-24 | V/F 治理 | 被取代 | 真机 | RTX 5090 V/F 运行时治理发现：LACT 只写 freq_offset、真实路径由 GSP/RM 仲裁。 |
| `BUG_AWARE_INVERSE_GOVERNOR_TASK_BOARD_20260814.md` | Bug-aware inverse governor：信息补全与求解任务板 | 2026-08-14 | 逆求解任务板 | 权威(已停) | 静态+只读 | 把固件行为当作带延迟/错序的被控对象做逆求解的任务板；只读建模阶段。 |
| `GPC_INTEGRITY_BOUNDARY_20260822.md` | GB202 GPC data-integrity boundary follow-up — 2026-08-22 | 2026-08-22 | 完整性边界 | 权威 | 真机 | GB202 GPC 数据完整性验收规则与边界跟进：GSP 存活不等于数据正确。 |
| `LIGHTNING_MATRIX_VF_POWER_DIFF_20260725.md` | RTX 5090 Lightning / Matrix VBIOS V/F 与功耗策略差分 | 2026-07-25 | VBIOS 差分 | 权威 | 静态 | Lightning/Matrix VBIOS 的 V/F 与功耗策略只读差分。 |
| `LIGHTNING_VBIOS_POWER_TELEMETRY_20260726.md` | Lightning VBIOS on ASUS Astral: power telemetry mismatch | 2026-07-26 | 功耗遥测 | 权威 | 真机 | Astral 板 + Lightning VBIOS 的功耗遥测不一致（外接测量对照）。 |
| `LOW_VOLTAGE_PT_RESULT_20260729.md` | RTX 5090 low-voltage path-tracing result (2026-07-29) | 2026-07-29 | 低压 PT | 一次性 | 真机 | 低压 path tracing 可行性实验（973mV/2900MHz 是否为必需）。 |
| `MODS_SUL5_PATCH_SPEC.md` | MODS SUL=5 补丁技术规格 | ~2026-09-30 | MODS 补丁 | 一次性 | 静态 | MODS 570.215 的 SecurityUnlockLevel=5 补丁技术规格。 |
| `PRODUCTION_GPC_VF_LOCK_20260824.md` | GB202 production-driver GPC/NVVDD lock (2026-08-24) | 2026-08-24 | GPC/NVVDD 锁 | 权威 | 真机 | 生产驱动 + 正常 GSP 下同时锁 GPC 频率与 NVVDD 的组合，不用 MODS。 |
| `RAIL_DOMAIN_ADOPTION_MATRIX_20260816.md` | GB202 rail-by-clock-domain adoption matrix | 2026-08-16 | rail 采纳矩阵 | 权威 | 真机 | 时钟域与供电 rail 的采纳矩阵。 |
| `RT_MEMORY_LOCK_AB_TEST_20260728.md` | RTX 5090 VRAM locked-clock controlled test (2026-07-28) | 2026-07-28 | 显存锁频 A/B | 权威 | 真机 | VRAM 锁频对照：仅加 min/max memory clock 即掉 16.43% FPS。 |
| `RT_POWER_BUDGET_CURRENT_FOCUS_20260727.md` | RTX 5090: RT workload cannot use the advertised board-power ceiling | 2026-07-27 | 功耗预算 | 权威 | 真机 | 800W 上限下 RT 负载只能用约 500W 的现场观察。 |
| `SYS_CLOCK_RUNTIME_AB_20260811.md` | GB202 SYS clock runtime control and A/B result — 2026-08-11 | 2026-08-11 | SYS 时钟 | 权威 | 真机 | SYS 作为 client-domain index 3 的运行时控制与 A/B。 |
| `VF_ALL_POINT_NEGATIVE_SHIFT_20260816.md` | GB202 four-bank all-point negative-shift experiment | 2026-08-16 | V/F 全点负移 | 权威 | 真机 | 四 bank 全点负移实验（带安全门）。 |
| `VF_POINT_BANK_INVENTORY_20260816.md` | GB202 global VF-point and clock-offset inventory — 2026-08-16 | 2026-08-16 | V/F 点清单 | 权威 | 真机 | 全局 VF point 与 clock offset 清单（INFO/STATUS 命令与大小）。 |
| `XBAR2400_MCLKMAX16000_CP2077_AB_20260811.md` | GB202 XBAR 2400 MHz override under a non-binding MCLK maximum | 2026-08-11 | XBAR A/B | 权威 | 真机 | 非约束性 MCLK 上限下 XBAR 2400MHz 的 CP2077 A/B。 |
| `XBAR_PHYSICAL_HARDWARE_DRAFT_ZH.md` | NVIDIA Blackwell GPU 中的 XBAR：一个被公开工具忽略的物理时钟域 | ~2026-08-13 | XBAR 长文 | 权威(草稿) | 真机+静态 | 中文长文：把 XBAR 论证为被公开工具忽略的物理时钟域；明确标注推断与未知。 |
| `XBAR_VF_POINTS_RUNTIME_20260812.md` | GB202 XBAR live VF-point status (R610.43.03) | 2026-08-12 | XBAR VF 点 | 权威 | 真机 | R610.43.03 下 XBAR 活动 VF 点状态，只记录可逆 A/B 区分出的字段。 |
| `gsp_heap_runtime_20260726.md` | GB202 / 610.43.03 GSP-RM heap runtime result | 2026-07-26 | 堆运行时 | 一次性 | 真机 | 单次只读 RM 查询得到的 GSP-RM heap 运行时结果。 |
| `lightning_vbios_mclk_max_ab_20260803.md` | RTX 5090 Lightning VBIOS MCLK max-only A/B test | 2026-08-03 | MCLK A/B | 权威 | 真机 | Lightning VBIOS 下 MCLK 上限约束回归是否复现的 A/B。 |
| `msi_afterburner_467b3_voltage_path_20260811.md` | MSI Afterburner 4.6.7 Beta 3 build 17352 voltage-path audit | 2026-08-11 | Afterburner 审计 | 权威 | 静态 | MSI Afterburner 4.6.7b3 电压路径静态审计（安装包哈希与调用链）。 |
| `power_governor_reverse/CONTROL_LOGIC_STATUS_20260728.md` | GB202 WORKLOAD_COMBINED_2X 控制逻辑复原状态（2026-07-28） | 2026-07-28 | 控制逻辑状态 | 权威 | 真机+静态 | GB202 WORKLOAD_COMBINED_2X 控制逻辑复原状态（7-28）。 |
| `power_governor_reverse/DG0_VF_FEEDBACK_BRIDGE_PT_20260729.md` | DG0 to V/F feedback bridge: PT experiment (2026-07-29) | 2026-07-29 | DG0 反馈桥 | 权威 | 真机 | DG0→V/F 反馈桥的 PT 实验（7-29）。 |
| `power_governor_reverse/GB202_CONTROL_MODEL_STATUS_20260817.md` | GB202 multi-domain control model status | 2026-08-17 | 多域模型状态 | 权威 | 静态 | GB202 多域控制模型状态汇总。 |
| `power_governor_reverse/GSP_61057_CLK_CONTROL_COMMIT_20260817.md` | GB202 clock-domain CONTROL commit path | 2026-08-17 | CLK 提交路径 | 权威 | 静态 | 区分写控制记录/应用 BoardObj 组/装载 PS3.0 状态三步的静态证据。 |
| `power_governor_reverse/GSP_61057_CLK_DOMAIN_PMU_TRANSFER_20260816.md` | R610.57 clock-domain GSP/PMU transfer boundary | 2026-08-16 | GSP/PMU 边界 | 权威 | 静态 | R610.57 时钟域 GSP→PMU 传输边界。 |
| `power_governor_reverse/GSP_61057_CLK_DOMAIN_READBACK_20260816.md` | R610.57.04 CLK domain 列表与对象导出证据 — 2026-08-16 | 2026-08-16 | CLK 域回读 | 权威 | 真机 | R610.57.04 CLK domain 列表与对象导出证据。 |
| `power_governor_reverse/GSP_61057_CONTROL_LOGIC_REVERSE_20260816.md` | R610.57.04 GSP 时钟/电压控制逻辑拆解 — 2026-08-16 | 2026-08-16 | 控制逻辑拆解 | 权威 | 静态 | R610.57.04 GSP 时钟/电压控制逻辑拆解主文（42KB）。 |
| `power_governor_reverse/GSP_61057_PERF_CHILD_OBJECT_WALK_20260817.md` | R610.57 Perf BoardObjGroup transfer and child-object status import | 2026-08-17 | 子对象遍历 | 权威 | 静态 | Perf BoardObjGroup 传输与子对象状态导入。 |
| `power_governor_reverse/GSP_61057_PERF_EVENT_PROTOCOL_20260817.md` | R610.57 Perf event protocol and the no-op `Perf+0x560` slot | 2026-08-17 | Perf 事件协议 | 权威 | 静态 | Perf 事件协议与 Perf+0x560 no-op 槽位。 |
| `power_governor_reverse/GSP_61057_Q12_SCALE_READBACK_20260816.md` | R610.57.04 `clkUpScale` / `clkDownScale` proof chain | 2026-08-16 | Q12 比例 | 权威 | 静态 | clkUpScale/clkDownScale 的 Q12 证明链。 |
| `power_governor_reverse/GSP_61057_VFE_TUPLE_MODEL_20260816.md` | R610.57.04 GSP VFE / VF-tuple / VF-relation reconstruction | 2026-08-16 | VFE 元组模型 | 权威 | 静态 | GSP VFE/VF-tuple/VF-relation 重建（17KB）。 |
| `power_governor_reverse/M40_HISTORICAL_CONTROL_LINEAGE_20260729.md` | NVIDIA performance-control lineage: Fermi to Blackwell | 2026-07-29 | 历史脉络 | 一次性 | 综合 | Fermi→Blackwell 性能控制血统，历史背景用。 |
| `power_governor_reverse/MEMORY_MAX_FEEDBACK_CLOSURE_20260728.md` | GB202 finite DRAM-MAX feedback closure (2026-07-28) | 2026-07-28 | DRAM 上限闭环 | 权威 | 真机+静态 | 有限 DRAM-MAX 反馈闭环（7-28）。 |
| `power_governor_reverse/MODS570215_MCLK_3999_4000_STATIC_FINDINGS_20260903.md` | MODS 570.215：MCLK `+3999 / +4000 MHz` 边界的静态结论 | 2026-09-03 | MCLK 边界静态 | 权威 | 静态 | MODS 570.215 的 +3999/+4000 边界静态结论：故障顺序闭合到 PMU mailbox 重入断言。 |
| `power_governor_reverse/PHASE9_QUANTITATIVE_IDENTIFICATION_STATUS_20260817.md` | Phase-9 quantitative identification status | 2026-08-17 | 定量识别状态 | 权威 | 综合 | Phase-9 定量识别状态（20KB）。 |
| `power_governor_reverse/R570_PMU_CLK_GROUP_CROSS_PROFILE_20260817.md` | R570 MODS clear-PMU CLK group cross-profile audit | 2026-08-17 | 跨 profile 审计 | 权威 | 静态 | R570 MODS clear-PMU CLK 组的跨 profile 审计。 |
| `power_governor_reverse/R570_PMU_DOMAIN_ADJUSTMENT_20260816.md` | GB202 R570 post-selection domain-frequency adjustment | 2026-08-16 | 域频率调整 | 权威 | 静态 | GB202 R570 选择后域频率调整。 |
| `power_governor_reverse/R570_PMU_PERF_TASK_AND_SOLVER_WALK_20260817.md` | GB202 R570 PMU PERF task and periodic solver walk | 2026-08-17 | PERF 任务 | 权威 | 静态 | R570 PMU PERF 任务与周期 solver 遍历。 |
| `power_governor_reverse/R570_PMU_VF_RELATION_SEARCH_20260816.md` | GB202 R570 clear-PMU V/F relation search reconstruction | 2026-08-16 | VF 关系检索 | 权威 | 静态 | clear-PMU V/F relation 检索重建。 |
| `power_governor_reverse/RTX5090D_SM_ISSUE_THROTTLE_REVERSE_20260923.md` | RTX 5090D SM issue-throttle 静态逆向结论 — 2026-09-23 | 2026-09-23 | SM issue 节流 | 权威 | 静态 | RTX 5090D SM issue-throttle 静态逆向。 |
| `power_governor_reverse/SOLVER_LIVE_VALIDATION_20260817.md` | GB202 solver live validation | 2026-08-17 | solver 实机验证 | 权威 | 真机 | GB202 solver 的有界 P0 实机验证。 |
| `power_governor_reverse/VBIOS_CLOCK_TABLE_GRAPH_20260817.md` | GB202 VBIOS clock-domain to relationship graph | 2026-08-17 | VBIOS 时钟图 | 权威 | 静态 | VBIOS 时钟域到关系的图。 |
| `power_governor_reverse/VOLTAGE_REQUEST_AND_REGULATOR_PATH_20260729.md` | GB202 voltage request, arbitration, and regulator path (2026-07-29) | 2026-07-29 | 电压仲裁路径 | 权威 | 真机+静态 | 电压请求、仲裁与稳压器路径（7-29）。 |
| `power_governor_reverse/bug_inverse/DG0_IDENTIFIABILITY_20260816.md` | DG0 filter 可辨识性审计 — 2026-08-16 | 2026-08-16 | 可辨识性审计 | 权威 | 静态 | DG0 filter 可辨识性审计。 |
| `power_governor_reverse/bug_inverse/EXECUTION_BOARD_20260814.md` | `F_bug` 数据与算法执行板 | 2026-08-14 | 执行板 | 一次性 | 只读 | F_bug 数据与算法执行板。 |
| `power_governor_reverse/bug_inverse/MULTIDOMAIN_DIGITAL_TWIN_20260816.md` | GB202 多域控制逻辑数字孪生 — 2026-08-16 | 2026-08-16 | 数字孪生 | 权威 | 综合 | GB202 多域控制逻辑数字孪生（20KB）。 |
| `power_governor_reverse/bug_inverse/README.md` | Bug-aware inverse governor prototype | ~2026-08-16 | 逆向原型 | 权威 | 综合 | bug-aware inverse governor 原型三部分索引（数据/算法/电压审计）。 |
| `power_governor_reverse/bug_inverse/algorithm/README.md` | Bug-aware inverse governor — data/model/solver prototype | ~2026-08-17 | 算法原型 | 权威 | 代码/离线 | 无依赖 Python 原型：历史数据规范化、四类竞争模型、约束离散逆求解；不写 GPU 状态。 |
| `power_governor_reverse/bug_inverse/algorithm/SMOKE_REPORT_20260814.md` | Algorithm/data smoke report — 2026-08-14 | 2026-08-14 | 冒烟报告 | 一次性 | 代码/离线 | 算法与数据冒烟报告。 |
| `power_governor_reverse/bug_inverse/data_pipeline/README.md` | Bug-inverse read-only data pipeline | ~2026-08-14 | 数据管线 | 权威 | 只读 | 只读数据管线说明。 |
| `power_governor_reverse/bug_inverse/data_pipeline/TASKS.md` | Data pipeline task board | ~2026-08-14 | 数据任务板 | 一次性 | 只读 | 数据管线任务板。 |
| `power_governor_reverse/bug_inverse/voltage_61057/REPORT.md` | R610.57.04 voltage and clock observation audit | ~2026-08-14 | 电压审计 | 权威 | 静态+只读 | R610.57.04 电压与时钟观测审计（无 SET/无写）。 |
| `power_governor_reverse/gsp_mclk4000_review_20261010/REPORT.md` | 本地GSP代码核查：MCLK控制、动态范围与PMU提交 | ~2026-10-11 | MCLK 复核 | 权威 | 静态 | 本地 GSP 代码核查：MCLK 控制、动态范围与 PMU 提交。 |
| `power_governor_reverse/gsp_mclk4000_review_20261010/cross_build/REPORT.md` | GSP 570.144 / R610.57 与 MODS 570.215 的 MCLK +3999/+4000 静态交叉复核 | ~2026-10-11 | 跨版本复核 | 权威 | 静态 | GSP 570.144/R610.57 与 MODS 570.215 的 MCLK ±3999/4000 静态交叉复核。 |
| `power_governor_reverse/gsp_mclk4000_review_20261010/parent_capability/NOTES.md` | Parent：本地GSP身份、能力限值名字与误命中排除 | ~2026-10-11 | 父线索笔记 | 重复 | 静态 | 父 agent 的 GSP 身份/能力限值命名与误命中排除笔记；与 producers/max_capability/NOTES.md 字节相同。 |
| `power_governor_reverse/gsp_mclk4000_review_20261010/validators/REVIEW.md` | R610.57.04 GB202 GSP-RM VF-relation SET / MCLK offset validator | ~2026-10-11 | validator 复核 | 权威 | 静态 | VF-relation SET / MCLK offset validator 复核。 |
| `power_governor_reverse/gsp_mclk_producers_20261011/REPORT.md` | MCLK +3999/+4000：GSP 限幅源与 Pstate 输入生产链阶段报告 | ~2026-10-11 | MCLK 生产链 | 权威 | 静态 | MCLK +3999/4000 限幅源与 Pstate 输入生产链阶段报告；明确 MCLK_MAX_CAPABILITY 未被当作已找到的硬上限。 |
| `power_governor_reverse/gsp_mclk_producers_20261011/capability_producer/REPORT.md` | Capability producer follow-up — bounded static result | ~2026-10-11 | 能力生产者 | 权威 | 静态 | capability producer 的有界静态跟进的结论。 |
| `power_governor_reverse/gsp_mclk_producers_20261011/max_capability/NOTES.md` | Parent：本地GSP身份、能力限值名字与误命中排除 | ~2026-10-11 | 父线索笔记 | 重复 | 静态 | 与 gsp_mclk4000_review/parent_capability/NOTES.md 完全相同的副本。 |
| `power_governor_reverse/gsp_mclk_producers_20261011/max_capability/REPORT.md` | MCLK_MAX_CAPABILITY producer hunt (bounded pass) | ~2026-10-11 | 上限生产者 | 权威 | 静态 | MCLK_MAX_CAPABILITY 生产者的有界搜索结论。 |
| `power_governor_reverse/gsp_mclk_producers_20261011/pstate_descriptor/REPORT.md` | GSP Pstate descriptor selector and range producers (static-only) | ~2026-10-11 | Pstate 描述符 | 权威 | 静态 | GSP Pstate 描述符选择器与范围生产者（纯静态）。 |
| `power_governor_reverse/gsp_mclk_producers_20261011/pstate_writers/REPORT.md` | R610.57.04 GSP Pstate slot-548 producer trace (static-only) | ~2026-10-11 | Pstate 写入者 | 权威 | 静态 | Pstate slot-548 生产者追踪（纯静态）。 |
| `power_governor_reverse/gsp_mclk_producers_20261011/table_activation/REPORT.md` | GSP capability-table activation: object/flag producer trace (static-… | ~2026-10-11 | 表激活 | 权威 | 静态 | capability 表激活的对象/标志生产者追踪（纯静态）。 |
| `power_governor_reverse/mclk4000_public_cases_20261010/REPORT.md` | 网上类似案例：5090 +3999 / +4000附近 | ~2026-10-10 | 公开案例 | 权威 | 公开 | 网上类似 +3999/+4000 案例汇总报告。 |
| `power_governor_reverse/mclk4000_public_cases_20261010/exact_cases.md` | RTX 5090 `dramclk 18000/18001` / +3999/+4000 / PMU halt：公开案例检索 | ~2026-10-10 | 公开案例 | 权威 | 公开 | dramclk 18000/18001 与 PMU halt 的公开案例检索（逐条来源）。 |
| `power_governor_reverse/mclk4000_public_cases_20261010/limits_cases.md` | RTX 50 系列 GDDR7 超频边界：公开案例核验 | ~2026-10-10 | 公开边界 | 权威 | 公开 | RTX 50 系 GDDR7 超频边界的公开案例核验。 |
| `power_governor_reverse/mclk4000_readonly_review_20261009/REVIEW.md` | MODS 570.215：+3999 / +4000 MCLK 故障只读复核 | ~2026-10-09 | 只读复核 | 权威 | 静态 | MODS 570.215 +3999/4000 故障的只读复核。 |
| `power_governor_reverse/mclk4000_reverse_followup_20261009/REPORT.md` | GB202 PMU MCLK 继续逆向：发送、通知与外置参考时钟 | ~2026-10-09 | 继续逆向 | 权威 | 静态 | GB202 PMU MCLK 发送/通知/外置参考时钟继续逆向。 |
| `power_governor_reverse/mclk4000_reverse_followup_20261009/completion_path/REPORT.md` | MCLK command-0 completion path follow-up (static) | ~2026-10-09 | 完成路径 | 权威 | 静态 | MCLK command-0 完成路径跟进（静态）。 |
| `power_governor_reverse/mclk4000_reverse_followup_20261009/endpoint_identity/REPORT.md` | taskC / MCLK notification endpoint identity — static follow-up | ~2026-10-09 | 端点身份 | 权威 | 静态 | taskC / MCLK 通知端点身份静态跟进。 |
| `power_governor_reverse/mclk4000_reverse_followup_20261009/send_path/REPORT.md` | MODS 570.215 +4000：PMU command-0 发送路径独立复核 | ~2026-10-09 | 发送路径 | 权威 | 静态 | PMU command-0 发送路径独立复核。 |
| `power_governor_reverse/mclk4000_reverse_followup_20261009/web_sources/VERIFIED_SOURCES.md` | 浏览器核验的公开来源 | ~2026-10-09 | 核验来源 | 权威 | 公开 | 浏览器核验过的公开来源清单。 |
| `power_governor_reverse/mclk4000_root_hunt_20261009/REPORT.md` | PMU +3999/+4000 首因追踪：目前不是已证明的主动拦截 | ~2026-10-10 | 首因追踪 | 权威 | 静态 | PMU +3999/4000 首因追踪：目前不是已证明的主动拦截。 |
| `power_governor_reverse/mclk4000_root_hunt_20261009/consumer_identity/REPORT.md` | PMU command-0 请求：设备消费者 / 寄存器身份追踪 | ~2026-10-10 | 消费者身份 | 权威 | 静态 | PMU command-0 请求的设备消费者/寄存器身份追踪。 |
| `power_governor_reverse/mclk4000_root_hunt_20261009/notification_failure/REPORT.md` | PMU completion-notification 超时：静态机制与日志证据 | ~2026-10-10 | 通知失败 | 权威 | 静态+日志 | PMU completion-notification 超时的静态机制与日志证据。 |
| `power_governor_reverse/mclk4000_root_hunt_20261009/parent_scan/IRQ_COMPLETION.md` | Parent 新增：从 supervisor external trap 到 MCLK completion event | ~2026-10-10 | 中断完成 | 权威 | 静态 | 从 supervisor external trap 到 MCLK completion event。 |
| `power_governor_reverse/mclk4000_root_hunt_20261009/target_path/REPORT.md` | GB202 R570.215 MCLK target → object+0x68 → command-0 DATA / metadata | ~2026-10-10 | 目标路径 | 权威 | 静态 | R570.215 MCLK target→object+0x68→command-0 DATA/metadata。 |

## 七、风扇 / L2 / SM / ISA（17）

| 路径 | 标题 | 日期 | 主题 | 状态 | 证据类别 | 一句话摘要 |
|---|---|---|---|---|---|---|
| `ASTRAL_STOCK_FAN_BASELINE_20260727.md` | ASUS Astral stock BIOS fan baseline — 2026-07-27 | 2026-07-27 | 风扇基线 | 一次性 | 真机 | Astral 原厂 BIOS 风扇基线（设备/驱动/VBIOS/基线目录）。 |
| `ASUS_GPUTWEAK_IT8915_EXTERNAL_FAN_RE_20260728.md` | ASUS GPU Tweak III / MSI Afterburner fan-control static audit | 2026-07-28 | 外部风扇静态审计 | 权威 | 静态 | GPU Tweak III / Afterburner 风扇控制静态审计，未碰实时 I2C/MMIO。 |
| `COMPILER_RE_BRIEF.md` | sm_120 SASS ISA 逆向任务(聚焦:缓存控制 + 寄存器读写) | ~2026-07-13 | ISA 任务书 | 一次性 | 静态 | sm_120 SASS ISA 逆向任务书（缓存控制+寄存器读写）。 |
| `FAN_CONTROL_DO_NOT_REPEAT_20260727.md` | FAN control current anchor — do not repeat the same discovery | 2026-07-27 | 风扇锚点 | 权威 | 真机 | 风扇控制当前锚点与“不要重复的发现”：Lightning BIOS 只启用一路 cooler。 |
| `FAN_NOPTRS_REGOPS_ROUTE_20260728.md` | FAN NOPTRS RegOps Route - 2026-07-28 | 2026-07-28 | RegOps 路线 | 一次性 | 真机 | NV2080_CTRL_CMD_GPU_EXEC_REG_OPS_NOPTRS 读 GPIO3 的路线测试。 |
| `FAN_ROUTE1_STAGE_20260727.md` | RTX 5090 / Lightning BIOS Fan1 Route 1 阶段表 | 2026-07-27 | Route1 阶段表 | 权威 | 静态+真机 | Lightning BIOS 下补 fan1/PWM11/GPIO3 运行时对象的 Route1 阶段表（79KB）。 |
| `FAN_RUNTIME_ROUTE_FINDINGS_20260727.md` | GB202 fan runtime route findings — 2026-07-27 | 2026-07-27 | 运行时路线 | 权威 | 静态+真机 | GB202 风扇运行时路线发现：RM GPIO ABI 只暴露四个内部方法。 |
| `FAN_STATIC_AUDIT_FOLLOWUP_20260728.md` | FAN static audit follow-up, 2026-07-28 | 2026-07-28 | 静态跟进 | 一次性 | 静态 | GPT Pro 第二轮答复后的静态审计跟进，修正字段语义并收窄未知。 |
| `GB202_PARALLEL_WORK.md` | GB202 L2 re-enable: parallel work contract | ~2026-07-22 | 并行工作契约 | 一次性 | 静态 | L2 重启用的并行工作契约与归档 NCU 证据。 |
| `L2_REENABLE_STATIC_FINDINGS.md` | RTX 5090 / GB202 L2 重新启用：静态逆向结论 | ~2026-07-22 | L2 静态结论 | 权威 | 静态 | L2 重启用静态结论：目前不能安全写出 96→128MiB 工具，已排除两条直接路径。 |
| `L2_SLICE_MAP_FINDINGS.md` | GB202 L2 slice / memory-partition findings | ~2026-07-13 | L2 slice 映射 | 权威 | 静态 | GB202 L2 slice/内存分区 findings，物理索引仍是明确观测边界。 |
| `L2_SLICE_RE_BRIEF.md` | RTX 5090 (GB202) L2 Slice / Memory-Partition 逆向任务 | ~2026-07-13 | L2 任务书 | 一次性 | 静态 | L2 slice/内存分区逆向任务书与动机。 |
| `SM120_CACHE_AND_REGISTER_ISA.md` | sm_120 SASS ISA: cache control and special-register access | ~2026-07-13 | SASS ISA | 权威 | 静态 | sm_120 SASS 缓存控制与特殊寄存器访问（仅两族）。 |
| `WATERLOOP_AM5_FAN_AUDIT_20260917.md` | AM5 water-loop fan audit — 2026-09-17 | 2026-09-17 | 水冷风扇审计 | 一次性 | 真机 | AM5 水冷/风扇策略审计（CPU 侧，与 GPU 无关）。 |
| `fan_runtime_mapping_20260724.md` | ASUS RTX 5090 Astral runtime fan mapping (2026-07-24) | 2026-07-24 | 物理映射 | 权威 | 真机 | 逻辑 Fan0→物理 1/3、Fan1→2/4 的运行时风扇映射。 |
| `gptpro_fan_route_followup_static_closure_20260727.md` | GPT Pro follow-up static closure, 2026-07-27 | 2026-07-27 | 静态收口 | 一次性 | 静态 | GPT Pro 建议的静态收口：先窄验证 live gpio_object。 |
| `handoff_fan0_runtime_address_prompt_20260726.md` | RTX 5090 / GB202: find the live Fan0 GSP address without scanning pr… | 2026-07-26 | 交接提示词 | 一次性 | 静态 | 给接手 agent 的 Fan0 运行时地址查找任务书（含证据分级要求）。 |

## 八、会话交接 / 复盘 / 事故恢复 / 取证（23）

| 路径 | 标题 | 日期 | 主题 | 状态 | 证据类别 | 一句话摘要 |
|---|---|---|---|---|---|---|
| `BIOS_SLOT_CC_LOCK_RECOVERY.md` | 原版 BIOS 槽位 CC 锁死 — 状态记录与恢复程序（v2 修正版） | ~2026-09-30 | 恢复程序 | 权威 | 真机 | 原版 BIOS 槽 CC 锁死状态记录与恢复程序 v2（自注 v1 已过时）。 |
| `DUAL_BIOS_CROSS_SLOT_FORENSICS_20261012.md` | 双 BIOS 槽位同时异常取证 — 历史会话复核 | 2026-10-12 | 取证 | 权威 | 真机 | 双 BIOS 槽同时异常的历史会话复核：并非两颗 flash 同时永久损坏。 |
| `EXPERIMENT_LOG_20260929_30.md` | 2026-09-29/30 GPU WPR2 死锁战役 — 完整实验记录 | 2026-09-29 | 战役记录 | 权威 | 真机 | 9-29/30 WPR2 死锁战役 22 小时完整实验记录与时间线。 |
| `FINAL_SESSION_20261002.md` | 会话总结 — 2026-10-02 全天 (逻辑遗漏审计 + FSP通道彻底审计 + 重大发现) | 2026-10-02 | 会话总结 | 一次性 | 真机 | 10-02 全天总结：FSP runtime dispatcher 永久 DoS 等现象。 |
| `FINAL_STATUS_20260928.md` | 2026-09-28 超长马拉松 — 完整记录与最终状态 | 2026-09-28 | 状态记录 | 一次性 | 真机 | 9-28 马拉松完整记录与最终状态（GPU 不可用、FSP 安全锁定）。 |
| `FULL_REREAD_FINDINGS_20261002.md` | 全量研究重读 — 未探索线索 + 可能错误结论 (2026-10-02) | 2026-10-02 | 全量重读 | 权威 | 综合 | 通读约 40 份文档后的未探索线索与可能错误结论清单。 |
| `GPU_REVIVE_MANUAL.md` | GPU 复活操作手册 (MODS CPU-RM 方法) | ~2026-09-30 | 操作手册 | 权威 | 真机VM | MODS CPU-RM 方法的复活操作手册（每次冷启动需重跑）。 |
| `HANDOFF_20261001.md` | 会话交接索引 — 2026-10-02 更新 | 2026-10-01 | 交接 | 一次性 | 综合 | 会话交接索引：宿主侧 FSP 通道全封闭，下一步转 GSP 侧泄漏读或改固件。 |
| `HANDOFF_20261006.md` | 会话入口 — 2026-10-06 收工 | 2026-10-06 | 交接 | 一次性 | 综合 | FSP boot dispatcher 只在 boot 窗口活跃；唯一路径 T76 读 flash→清死亡标志。 |
| `HANDOFF_CURRENT.md` | 下次Session入口 — 2026-10-07 23:15 | ~2026-10-07 | 交接 | 一次性 | 综合 | 最短交接：最高优先=模拟宿主 RPC 让 RM 自然启动。 |
| `LOGICAL_GAPS_AUDIT_20261002.md` | 逻辑遗漏审计 — 2026-10-02 深度回顾 | 2026-10-02 | 遗漏审计 | 权威 | 综合 | 逻辑遗漏审计：EMEM 只在 boot 阶段工作等“想当然未验证”的点。 |
| `LOGICAL_INCONSISTENCIES_DEEP_ANALYSIS.md` | 跨研究线逻辑分析 — 发现的矛盾与被忽略的攻击面 | ~2026-09-29 | 矛盾清单 | 权威 | 综合 | 跨研究线矛盾分析：TOCTOU 时间线冲突、“sysmem 死亡”只适用 FMC、被忽略的 ELF 面。 |
| `NVFLASH_VM_EXPERIMENTS.md` | nvflash 5.877 VM 实验完整记录 | ~2026-09-30 | nvflash 实验 | 一次性 | 真机+VM | nvflash 5.877 在 VM 的完整实验：读路径活、写路径死锁且原因已定位。 |
| `ORIGINAL_BIOS_SLOT_FORENSICS_20261013.md` | 原版 BIOS 槽位故障取证 — `98.02.2E.40.E0` | 2026-10-13 | 取证 | 权威 | 真机 | 原版槽 98.02.2E.40.E0 故障链只读取证：把混在一起的事件拆开。 |
| `POST_REBOOT_QUEUE_20260926.md` | 重启/断电前的状态与待办(2026-09-26 傍晚) | 2026-09-26 | 待办 | 一次性 | 真机 | 断电前状态与待办（MNOC port1 读死、SBR 无效）。 |
| `POST_RESET_TODO_20260926.md` | 复位后待办清单(2026-09-26 晚,写给重启后的自己) | 2026-09-26 | 待办 | 一次性 | 真机 | 复位后待办清单（写给重启后的自己）。 |
| `RESUME_BRIEF.md` | 复活简报(GB202 / RTX 5090 解锁研究)— 会话丢失时把本文件交给新 agent | ~2026-09-26 | 复活简报 | 被取代(体量过大) | 综合 | 97KB 复活简报（§1-§43）：目标、铁律、宿主操作事故与全部战果；适合作为历史总集，不宜当索引。 |
| `REVIVAL_FINAL.md` | 🏆 RTX 5090 复活 — 最终状态 (2026-09-30 深夜) | ~2026-09-30 | 恢复结论 | 权威 | 真机 | 卡已完全可用（宿主直跑、开机即工作）的最终状态与一行补丁。 |
| `SBR_RECOVERY_DISCOVERY.md` | SBR 恢复发现 — Power Cycle ≠ SBR (Reset-Domain 分析) | ~2026-09-28 | 恢复发现 | 权威 | 真机 | Power Cycle ≠ SBR：复位域分析与恢复条件。 |
| `SESSION_SUMMARY_20260930.md` | 2026-09-29/30 战役总结 — 供下次会话恢复用 | 2026-09-30 | 会话总结 | 一次性 | 综合 | 9-29/30 战役总结：卡状态与“flash 里有毒”的恢复路径。 |
| `SESSION_SUMMARY_20261002.md` | 会话总结 — 2026-10-02 全天 (GSP权限探索 + FSP通道审计 + 内存布局) | 2026-10-02 | 会话总结 | 一次性 | 真机 | 10-02 总结：GSP 内存权限图、FSP 通道审计与内存布局。 |
| `WPR2_INCIDENT.md` | WPR2 事故记录(2026-09-28) | ~2026-09-28 | 事故记录 | 权威 | 真机 | WPR2 事故触发序列（COT size/version fuzz 后 PRC handler 死亡）。 |
| `WRAPUP_20260926.md` | 收尾总结:ASUS Astral RTX 5090(GB202)资源解锁研究 | 2026-09-26 | 收尾总结 | 被取代 | 综合 | 9-26 收尾：资源解锁目标未达成（32MiB L2 与 22 SM），并说明卡已出局需断电恢复。 |

## 九、对外投稿与 issue 草稿（18）

| 路径 | 标题 | 日期 | 主题 | 状态 | 证据类别 | 一句话摘要 |
|---|---|---|---|---|---|---|
| `GITHUB_ISSUE_1080_COMMENT_PREVIEW.md` | (无 H1) | ~2026-10-13 | 投稿草稿 | 一次性 | 真机 | issue #1080 评论预览：第二个 WPR2-up 恢复失败模式。 |
| `GITHUB_ISSUE_GPU_LOCKED_CLOCKS_CONTRACT_20260822.md` | (无 H1) | 2026-08-22 | 投稿草稿 | 一次性 | 真机 | GPU locked-clocks 契约类 issue 草稿。 |
| `GITHUB_NEW_ISSUE_WPR2_RECOVERY_BODY.md` | (无 H1) | ~2026-10-13 | 投稿草稿 | 重复 | 真机 | 新 issue 正文；与 PREVIEW 的 Body 部分同源。 |
| `GITHUB_NEW_ISSUE_WPR2_RECOVERY_PREVIEW.md` | Title | ~2026-10-13 | 投稿草稿 | 重复 | 真机 | 新 issue 完整预览（Title+Body），与 BODY 文件重复。 |
| `LACT_1045_HARD_PSTATE_LINK_COMMENT_20260828.md` | (无 H1) | 2026-08-28 | 投稿回复 | 一次性 | 真机 | LACT #1045 机制更正：rail 窗口 ≠ Afterburner L ≠ 硬 P-state。 |
| `LACT_ISSUE_BLACKWELL_MEMORY_LOCK_PERF_DRAFT.md` | Suggestion: clarify NVIDIA memory locked-clock behavior on Blackwell | ~2026-07-28 | 投稿草稿 | 一次性 | 真机 | LACT 文档/UX 建议草稿：显存锁频导致大幅性能回退。 |
| `LACT_ISSUE_VF_CURVE_SILENT_CLEAR.md` | (无 H1) | ~2026-08-08 | 投稿草稿 | 一次性 | 真机 | LACT bug 报告：无关设置会静默清掉已保存 V/F 曲线。 |
| `LACT_NVIDIA_HARD_PSTATE_LOCK_ISSUE_20260828.md` | (无 H1) | 2026-08-28 | 投稿草稿 | 一次性 | 真机 | LACT 硬 P-state 锁模式提案，含 MODS 路径与生产驱动验证。 |
| `LACT_XBAR_EXPERIMENTAL_ISSUE.md` | (无 H1) | ~2026-08-11 | 投稿草稿 | 一次性 | 真机 | LACT XBAR 时钟/电压偏移实验性 issue，附 demo 链接。 |
| `NVIDIA_ISSUE_1268_UPDATE_20260821.md` | (无 H1) | 2026-08-21 | 投稿更新 | 一次性 | 真机 | NVIDIA issue #1268 更新：610.57.04 上复现终频/电压不匹配。 |
| `NVIDIA_ISSUE_BLACKWELL_MEMORY_LOCK_PERF.md` | RTX 5090: a finite memory-clock maximum silently constrains XBAR/SYS… | ~2026-07-28 | 主报告 | 权威 | 真机 | 主报告：有限显存上限会静默约束 XBAR/SYS，性能变化达 32%。 |
| `NVIDIA_ISSUE_FINAL_CLOCK_VOLTAGE_REEVALUATION.md` | (无 H1) | ~2026-07-29 | 投稿草稿 | 一次性 | 真机 | 终频/电压再评估稿（610.43.03）。 |
| `PSIRT_DRAFT_1_GB202_FSP_RUNTIME_DOS.md` | DRAFT 1 — NVIDIA PSIRT Submission | ~2026-10-13 | PSIRT 投稿 | 权威 | 真机 | PSIRT 稿 1：FSP runtime 服务不可用；内部注记明确撤回“单条 ROMREAD 即永久 DoS”，最小触发未知。 |
| `PSIRT_DRAFT_2_GB202_WPR2_PERSISTENT_STATE.md` | DRAFT 2 — NVIDIA PSIRT Submission | ~2026-10-13 | PSIRT 投稿 | 权威 | 真机 | PSIRT 稿 2：WPR2 持久态；内部注记承认槽位归属不确定。 |
| `SUBMISSION_RECORD_20261013.md` | Submission record — 2026-10-13 | 2026-10-13 | 投稿记录 | 权威 | 真机 | 2026-10-13 两封 PSIRT 邮件的发送记录与哈希。 |
| `issue1147_ingame_reply_20260812.md` | (无 H1) | 2026-08-12 | 投稿回复 | 一次性 | 真机 | issue #1147 的游戏内 A-B-A 回复（XBAR +450MHz）。 |
| `issue1159_vf_banks_comment_20260816.md` | (无 H1) | 2026-08-16 | 投稿回复 | 一次性 | 真机 | issue #1159 VF bank 评论：纠正权限负结果（0x1b=权限不足）。 |
| `lact_800w_high_tail_ab_20260803.md` | RTX 5090 Lightning VBIOS: LACT high-frequency-tail A/B | 2026-08-03 | LACT A/B | 一次性 | 真机 | Lightning VBIOS 下 LACT 高频尾 A/B（800W 固定条件）。 |

## 十、VM / VFIO 实验环境（17）

| 路径 | 标题 | 日期 | 主题 | 状态 | 证据类别 | 一句话摘要 |
|---|---|---|---|---|---|---|
| `vfio_production_lab/README.md` | RTX 5090 VFIO production test lab | ~2026-08-24 | 生产 VFIO lab | 权威 | 真机VM | 把宿主 NVIDIA 栈移出故障路径的 VFIO 生产测试 lab 说明。 |
| `vm_mods_lab/README.md` | Isolated MODS VM | ~2026-09-24 | 隔离 VM | 权威 | 真机VM | 隔离 MODS VM 的设计：整 IOMMU 组直通、无 NIC、干净基盘+一次性 overlay。 |
| `vm_mods_lab/VFIO_QUIET_COOLING_20260924.md` | VFIO 低噪声冷却（2026-09-24，当前临时客体） | 2026-09-24 | 静音冷却 | 一次性 | 真机 | VFIO 低噪声冷却的临时 service 与守护/回退条件。 |
| `vm_mods_lab/VFIO_QUIET_COOLING_20260925.md` | VFIO 静音冷却（2026-09-25，宿主-only 窗口） | 2026-09-25 | 静音冷却 | 一次性 | 真机 | 宿主-only 窗口的静音冷却：800RPM 达不到是硬件下限。 |
| `vm_mods_lab/VFIO_SSH_HOST_ONLY_20260924.md` | 2026-09-24：当前 MODS/VFIO 客体的离线 SSH 管理接口 | 2026-09-24 | 离线 SSH | 一次性 | 真机 | 当前 MODS/VFIO 客体的离线 SSH 管理接口配置。 |
| `vm_mods_lab/VM_USAGE.md` | VM 实验环境使用指南 | ~2026-09-29 | 使用指南 | 权威 | 真机VM | VM 实验环境使用指南（首次设置与运行流程）。 |
| `vm_mods_lab/bar0_write_probe_20260722.md` | GB202 BAR0 write probe result — 2026-07-22 | 2026-07-22 | BAR0 写探针 | 一次性 | 真机VM | BAR0 写探针结果（限定范围内的只读/写边界）。 |
| `vm_mods_lab/f8_e0f4_race_probe_20260723.md` | GB202 `0x8200f8` + `0x8200e0/0x8200f4` bounded race probe — 2026-07-23 | 2026-07-23 | 竞态探针 | 一次性 | 真机VM | 0x8200f8 + 0x8200e0/e4 有界竞态探针。 |
| `vm_mods_lab/f8_lowbyte_superset_sweep_20260723.md` | GB202 `0x8200f8` low-byte superset sweep — 2026-07-23 | 2026-07-23 | 低字节扫描 | 一次性 | 真机VM | 0x8200f8 低字节超集扫描。 |
| `vm_mods_lab/f8_write_status_probe_20260722.md` | GB202 `0x8200f8` direct-write status probe — 2026-07-22 | 2026-07-22 | 0x8200f8 探针 | 一次性 | 真机VM | 0x8200f8 直写状态探针结果。 |
| `vm_mods_lab/f8_write_status_rerun_20260723.md` | GB202 `0x8200f8` direct-write rerun — 2026-07-23 | 2026-07-23 | 0x8200f8 复跑 | 一次性 | 真机VM | 0x8200f8 直写复跑。 |
| `vm_mods_lab/fsp_caps_query_result_20260722.md` | GB202 FSP/MNOC caps-query result — 2026-07-22 | 2026-07-22 | FSP caps | 一次性 | 真机VM | 经 MNOC mailbox 的 FSP caps-query 直连结果。 |
| `vm_mods_lab/fsp_prc_read_direct_result_20260722.md` | GB202 FSP/MNOC PRC direct-read result — 2026-07-22 | 2026-07-22 | PRC 读 | 一次性 | 真机VM | 非 MODS 的 FSP/MNOC PRC 直读结果。 |
| `vm_mods_lab/fsp_prc_write_noop_result_20260722.md` | GB202 FSP/MNOC PRC write-noop result — 2026-07-22 | 2026-07-22 | PRC 写 | 一次性 | 真机VM | 受约束的 PRC 写 noop 被 FSP 拒绝的结果。 |
| `vm_mods_lab/fsp_task2_zero_result_20260722.md` | GB202 FSP task2/subobject1 zero-payload runtime result — 2026-07-22 | 2026-07-22 | FSP task2 | 一次性 | 真机VM | MODS 派生 FSP task2/subobject1 零载荷运行时探针。 |
| `vm_mods_lab/mods570215-diagnostic-20260825-logs/SUMMARY.md` | RTX 5090 MODS 570.215 diagnostic summary | ~2026-08-25 | MODS 诊断 | 一次性 | 真机VM | MODS 570.215 诊断汇总。 |
| `vm_mods_lab/mods_gspfw_5708616_result_20260722.md` | MODS gspfw 570.86.16 result - 2026-07-22 | 2026-07-22 | MODS gspfw | 一次性 | 真机VM | MODS gspfw 570.86.16 结果（客体内无 NVIDIA 驱动）。 |

## 十一、厂商源码（8）

| 路径 | 标题 | 日期 | 主题 | 状态 | 证据类别 | 一句话摘要 |
|---|---|---|---|---|---|---|
| `driver_gpio_internal_610.43.03/CODE_OF_CONDUCT.md` | Contributor Covenant Code of Conduct | ~2026-07-14 | 厂商源码 | 重复 | 源码 | 与 gspkm 副本字节相同。 |
| `driver_gpio_internal_610.43.03/CONTRIBUTING.md` | (无 H1) | ~2026-07-14 | 厂商源码 | 重复 | 源码 | 与 gspkm 副本字节相同。 |
| `driver_gpio_internal_610.43.03/README.md` | NVIDIA Linux Open GPU Kernel Module Source | ~2026-07-14 | 厂商源码 | 参考 | 源码 | 610.43.03 官方 README（与 610.57.04 版仅版本号等少量差异）。 |
| `driver_gpio_internal_610.43.03/SECURITY.md` | Report a Security Vulnerability | ~2026-07-14 | 厂商源码 | 重复 | 源码 | 与 gspkm 副本字节相同。 |
| `gspkm/CODE_OF_CONDUCT.md` | Contributor Covenant Code of Conduct | ~2026-10-17 | 厂商源码 | 重复 | 源码 | Contributor Covenant 行为准则，与 610.43.03 副本字节相同。 |
| `gspkm/CONTRIBUTING.md` | (无 H1) | ~2026-10-17 | 厂商源码 | 参考 | 源码 | 官方贡献指南。 |
| `gspkm/README.md` | NVIDIA Linux Open GPU Kernel Module Source | ~2026-10-17 | 厂商源码 | 参考 | 源码 | NVIDIA open kernel modules 610.57.04 官方 README（随仓库自带）。 |
| `gspkm/SECURITY.md` | Report a Security Vulnerability | ~2026-10-17 | 厂商源码 | 参考 | 源码 | 官方安全漏洞报告流程。 |

## 未纳入索引的内容

- 二进制/镜像/固件：`rm_fw_plaintext.bin`、`golden_gunv2.ko`、`nvflash_5877_text_disasm.asm`（120MB 反汇编文本）、`*.yaml`/`*.json` 配置与日志、`ghidra_static/*.rep` 工程内部。
- 源码树：`gspkm/kernel-open`、`driver_gpio_internal_610.43.03/kernel-open`、`gsp_qemu/qemu`（仅 `docs/` 与 README/PROGRESS 入索引）。
- 说明：`gsp_fsp_iface/` 为空目录，无文档可登记。
- 本次产物 `docs/INDEX.md`、`docs/DEDUP_PLAN.md` 不登记自身；上表 230 份为生成前的原始文档数。

## 阅读入口建议

| 想了解 | 先读 |
|---|---|
| 模拟器/启动链现状 | `gsp_qemu/README.md` → `gsp_qemu/docs/MPU_MODEL.md` → `gsp_qemu/docs/LAB_BOOT.md` |
| GSP 提权现状 | `★V5_STATUS_20261016.md`（带证据限定）→ `★V4_PROGRESS_20261016.md` → `K31_FINAL_REPORT.md` |
| 哪些结论互相冲突 | `docs/DEDUP_PLAN.md` §3、`LOGICAL_INCONSISTENCIES_DEEP_ANALYSIS.md` |
| FSP 侧结论 | `FSP_ULTIMATE_FINDINGS.md` → `PRC_KNOB_MAP.md` → `MNOC_PORT0_PROTOCOL.md` |
| 时钟/电压/功耗 | `power_governor_reverse/GSP_61057_CONTROL_LOGIC_REVERSE_20260816.md` → `mclk4000_root_hunt_20261009/REPORT.md` |
| 对外投稿状态 | `SUBMISSION_RECORD_20261013.md` → `PSIRT_DRAFT_1_GB202_FSP_RUNTIME_DOS.md` |

