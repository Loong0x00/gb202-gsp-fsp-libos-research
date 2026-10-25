# NVIDIA GPU 固件公开信息基线核查

**核查方式：**公开网页检索，检索截止日按本次任务记录为 2026-09-27。本文只记录公开资料，不包含利用开发或未公开信息。日期以来源页面/会议/公告显示日期为准；GitHub、文档页面未显示明确发布日期时标注“日期未见”。

## 1. Blackwell FSP_RUN、Falcon v6 descriptor、app 0x24/target 0x0f

**检索词：**

- `NVIDIA FSP_RUN firmware`
- `GB202 FSP falcon v6 descriptor`
- `NVIDIA FSP firmware reverse engineering Blackwell`
- `nvidia falcon ucode v6 decryption`
- `FSP_RUN NVIDIA`
- `app 0x24 NVIDIA FSP`
- `Falcon v6 NVIDIA firmware reverse engineering`

**结论：未找到**针对 GB202/GB203/GB100 的公开、可复核的 FSP_RUN 逆向报告、Falcon v6 descriptor 完整语义说明、解密方法或 FSP 明文转储。找到的是外围/格式和启动路径资料：

- **[找到] Linux Nouveau `gb202.c`** — 日期未见；<https://codebrowser.dev/linux/linux/drivers/gpu/drm/nouveau/nvkm/subdev/fsp/gb202.c.html>。公开了 GB202 FSP secure-boot 完成状态、Chain-of-Trust 参数及等待逻辑，但没有公开 FSP 明文 payload 或 `app=0x24,target=0x0f` 的语义。
- **[找到] Linux Nova Hopper/Blackwell firmware 支持补丁** — 2026-02-10 版本页面；<https://patchew.org/linux/20260210024601.593248-1-jhubbard%40nvidia.com/20260210024601.593248-21-jhubbard%40nvidia.com/>。公开了 FSP/FMC、Falcon EMEM/mailbox 等宿主侧启动与通信接口，但不是 FSP 固件逆向。
- **[找到] NVIDIA open-gpu-kernel-modules 固件提取脚本** — 日期未见；<https://github.com/NVIDIA/open-gpu-kernel-modules/blob/main/nouveau/extract-firmware-nouveau.py>。能帮助识别/提取公开分发的 firmware container；不提供 descriptor 的完整解释，也不提供密钥或明文解密。
- **[找到] NVIDIA Falcon Security 文档** — 日期未见；<https://download.nvidia.com/open-gpu-doc/Falcon-Security/1/Falcon-Security.html>。说明 Falcon NS/LS/HS 安全模式及签名限制，支持“生产 HS 固件不能由普通宿主直接读取/替换”的外部基线。
- **[找到] Blackwell 相关社区/代码讨论** — 日期未见；<https://github.com/ilya-zlobintsev/LACT/issues/1128>。讨论近期 NVIDIA 固件可能包含加密区域，但没有 GB202 FSP_RUN 或指定 descriptor 的逆向成果。

**对本研究的意义：**公开世界已有启动框架、容器解析、签名/CoT 元数据和部分 mailbox 代码，但 `FSP_RUN`、指定 descriptor 字段及 GB202 FSP 明文/解密仍是明显空白。研究中应将“公开的 wrapper/loader 观察”与“未公开的 payload 语义”严格区分，不能把 Falcon v6 泛称直接等同于 Blackwell FSP 内部实现。

## 2. GSP-RM/RISC-V 内存破坏漏洞、CVE、PSIRT 与 fuzzing

**检索词：**

- `NVIDIA GSP firmware vulnerability CVE`
- `nvidia gsp rpc overflow`
- `NVIDIA GPU firmware fuzzing`
- `nvidia gsp rm rpc memory corruption`
- `CVE nvidia gsp 2025`
- `NVIDIA GSP firmware CVE 2024 2025 proprietary firmware`

**结论：部分找到，但“专有 GSP 固件自身 CVE”未找到。**公开资料里有宿主 Nouveau GSP-RM RPC 漏洞和 NVIDIA 会议中的 GSP fuzzing 方向；尚未找到 NVIDIA PSIRT 明确把 CVE 归因于专有 RISC-V GSP-RM blob 内部内存破坏。

- **[找到] CVE-2025-38187** — 2025-07-04 变更记录；<https://nvd.nist.gov/vuln/detail/CVE-2025-38187/change-record?changeRecordedOn=07%2F04%2F2025T10%3A15%3A25.640-0400>。Linux Nouveau `r535_gsp_rpc_push()` 的大 RPC 分片路径存在 use-after-free；这是宿主驱动漏洞，不是证实 GSP 固件 blob 有漏洞。
- **[找到] CVE-2024-58018 / CVE-2024-58019** — 2025 年公开记录（NVD 页面日期各自可见）；<https://nvd.nist.gov/vuln/detail/CVE-2024-58018>、<https://nvd.nist.gov/vuln/detail/CVE-2024-58019>。涉及 Nouveau GSP 通信/队列处理，仍应按宿主内核驱动漏洞理解，而非专有 GSP-RM RISC-V 代码漏洞。
- **[找到] Nouveau 大 RPC 修复讨论** — 2024 年页面；<https://www.spinics.net/lists/nouveau/msg15193.html>。公开了大消息返回/分片处理的修复背景，但不是 NVIDIA 固件披露。
- **[找到] NVIDIA/Black Hat 2025 演讲幻灯片** — Black Hat USA 2025；<https://i.blackhat.com/BH-USA-25/Presentations/USA-25-Zabrocki-Mitic-How-to-Secure-Unique-Ecosystem-Thursday.pdf>。NVIDIA 演讲公开提到 fuzzing RM、RTOS firmware 以及 Partition OS 下的 GSP firmware fuzzing；属于研究方向/方法披露，不是 CVE 或漏洞细节。
- **[找到] Moneta** — NDSS 2025；<https://dev.ndss-symposium.org/wp-content/uploads/2025-218-paper.pdf>。目标主要是 NVIDIA GPU driver 行为的 ex-vivo fuzzing，并非 GSP 固件内存破坏。
- **[找到] NVIDIA GSP 固件说明** — 版本 580.65.06 文档，日期随驱动版本；<https://download.nvidia.com/XFree86/Linux-x86_64/580.65.06/README/gsp.html>。确认 GSP 是随驱动发布的专有 firmware blob，但不公开其源码。
- **[未找到]** 截至检索截止日，未找到 NVIDIA PSIRT 公告明确给出“专有 GSP-RM RISC-V 固件内存破坏”CVE，也未找到公开论文完整描述针对该 blob 的漏洞触发链。

**对本研究的意义：**“GSP RPC 可达面”和“宿主驱动 RPC 内存安全”已经有公开基线；但不能把 CVE-2024-58018/19 或 CVE-2025-38187 直接写成 GSP 固件漏洞。真正针对 GSP-RM blob 内部 parser/handler 的公开基线目前较弱，属于可重点核查的差异区。

## 3. FSP 的 MCTP/NVDM over EMEM/MNOC 通道

**检索词：**

- `NVIDIA NVDM MCTP FSP EMEM security`
- `nvidia fsp mailbox mnoc`
- `FSP MCTP EMEM MNOC NVIDIA GPU`
- `NVDM FSP security research`

**结论：未找到专门的公开安全研究；找到公开实现/接口描述。**

- **[找到] Nova Hopper/Blackwell FSP 支持补丁** — 2026-02-10 页面；<https://patchew.org/linux/20260210024601.593248-1-jhubbard%40nvidia.com/20260210024601.593248-21-jhubbard%40nvidia.com/>。公开说明 MCTP 消息、EMEM mailbox/队列等宿主侧接口。
- **[找到] NVIDIA open-gpu-kernel-modules registry 差异** — 日期未见；<https://fossies.org/diffs/NVIDIA-open-gpu-kernel-modules/610.57.04_vs_615.71.09/src/nvidia/interface/nvrm_registry.h-diff.html>。公开出现 FSP/MNOC/CPU mailbox 等配置线索，但不是安全审计或漏洞报告。
- **[找到] NVIDIA GPU admin tools FSP RPC 资料** — 日期未见；<https://deepwiki.com/NVIDIA/gpu-admin-tools/4.1-fsp-rpc-framework>。概括 MCTP、EMEM/MNOC 与 FSP RPC 框架，但属于代码/文档整理，不是独立安全研究。
- **[找到] Linux Nova FSP 文档** — 日期未见；<https://dri.freedesktop.org/docs/drm/gpu/nova/core/fsp.html>。公开 FSP secure boot 与宿主驱动接口背景。
- **[未找到]** 没有找到公开论文、会议报告或独立博客，专门对 NVDM/MCTP 在 EMEM/MNOC 上的边界检查、状态机、重放、权限或内存破坏进行安全分析。

**对本研究的意义：**通道名称、部分队列/邮箱实现已公开，但“协议安全性质”和“可从宿主触发的 FSP parser 边界”基本没有公开基线。该方向较可能产生新发现；报告时应把代码推断标为推断，不把 NVDM/MCTP 名称本身当作已证实漏洞。

## 4. 2024–2026 宿主可触发 GPU 固件相关漏洞/公告清单

**检索词：**

- `nvidia psirt gpu firmware advisory 2025`
- `nvidia gpu display driver CVE firmware 2025`
- `NVIDIA SEC2 Falcon CVE 2024 2025 firmware`
- `NVIDIA GSP firmware CVE 2024 2025`

**结论：找到公告，但多数是驱动/vGPU；明确标为 FSP 的公开公告主要是 HGX/DGX 平台固件。**

### 公开 PSIRT/安全公告

- **[找到] 2024-02-28 GPU Display Driver** — 2024-02-28；<https://nvidia.custhelp.com/app/answers/detail/a_id/5520/kw/analog>。列出 CVE-2024-0071、0073–0079、及相关驱动漏洞；公开分类是 display driver/vGPU，不是 SEC2/Falcon/FSP 固件。
- **[找到] 2024-10-22 GPU Display Driver** — 2024-10-22；<https://nvidia.custhelp.com/app/answers/detail/a_id/5586/>。列出 CVE-2024-0117–0121、0126–0128 等，仍未明确归因于 SEC2/Falcon/FSP。
- **[找到] 2025-01-22 GPU Display Driver** — 2025-01-22；NVIDIA 安全索引：<https://www.nvidia.com/en-us/security/>。列出 CVE-2024-0131、0146、0147、0149、0150、53869、53881 等，主要是驱动/vGPU。
- **[找到] 2025-04-24 GPU Display Driver** — 2025-04-24；<https://nvidia.custhelp.com/app/answers/detail/a_id/5630/>。列出 CVE-2025-23244、23245、23246，公开组件为显示驱动相关软件。
- **[找到] 2025-07-24 GPU Display Driver** — 2025-07-24；<https://nvidia.custhelp.com/app/answers/detail/a_id/5670/>。列出 CVE-2025-23276–23290 中的多项，公开组件仍为显示驱动/vGPU。
- **[找到] 2025-09-02 HGX/DGX VBIOS 与 LS10** — 2025-09-02；<https://nvidia.custhelp.com/app/answers/detail/a_id/5674/>。CVE-2025-23301、CVE-2025-23302；公告明确涉及 VBIOS/LS10 中的 FSP code，影响需要特权/FSP 访问，修复建议为相应平台固件 1.8.1 或更高版本。
- **[找到] 2025-10-09 GPU Display Driver** — 2025-10-09；<https://nvidia.custhelp.com/app/answers/detail/a_id/5703/>。列出 CVE-2025-23280、23282、23300、23309、23330、23332、23345、23347、23352 等，公开分类仍为驱动/vGPU。
- **[找到] Linux Nouveau GSP RPC CVE** — 2024–2025 公开记录；<https://nvd.nist.gov/vuln/detail/CVE-2024-58018>、<https://nvd.nist.gov/vuln/detail/CVE-2024-58019>、<https://nvd.nist.gov/vuln/detail/CVE-2025-38187>。这是宿主开源 Nouveau RPC/内存管理路径，不能等同于 NVIDIA 专有 GSP/FSP 固件漏洞。

**未找到：**截至检索截止日，没有找到 NVIDIA PSIRT 以“SEC2 Falcon firmware memory corruption”或“consumer RTX 5090 FSP parser”标题公开发布的独立 CVE 公告。2026 年公开索引/代码变更存在，但本次没有发现可明确归因于目标固件组件的新 PSIRT CVE。

**对本研究的意义：**外部基线应把漏洞分为三层：宿主驱动（已有多项）、平台固件/FSP（已有 HGX/DGX CVE）、专有 GSP/FSP payload（未见明确公开 CVE）。对 RTX 5090 研究，不能直接把服务器 HGX/DGX FSP CVE 外推为消费卡同一受影响范围。

## 5. Falcon 逆向工具链

**检索词：**

- `ghidra falcon processor module nvidia`
- `envytools falcon disassembly`
- `NVIDIA Falcon disassembler`

**结论：找到成熟度有限但可用的公开工具链。**

- **[找到] envytools / envydis Falcon 文档** — 日期未见；<https://envytools.readthedocs.io/en/latest/hw/falcon/intro.html>。支持 Falcon 指令集族及 `fuc0`–`fuc6` 等版本选择，可用于公开可见/raw Falcon code 的反汇编。
- **[找到] envytools 源码** — 日期未见；<https://github.com/envytools/envytools>。提供 Nouveau/Falcon 硬件文档和相关工具；版本选择必须匹配具体 GPU/engine。
- **[找到] Ghidra Falcon processor module** — 仓库页面日期未见，搜索结果显示 2026-03-28 归档；<https://github.com/marysaka/ghidra_falcon>。提供 Ghidra Falcon 语言/处理器模块，但项目成熟度和新 Falcon 变体覆盖有限，需用 envydis 交叉验证。
- **[找到] CAmadeus/falcon-tools** — 日期未见；<https://github.com/CAmadeus/falcon-tools>。面向 NVIDIA Falcon/TSEC 固件提取与研究，可作为分析辅助工具；不等于 Blackwell FSP 明文解密工具。
- **[找到] Falcon Security 文档** — 日期未见；<https://download.nvidia.com/open-gpu-doc/Falcon-Security/1/Falcon-Security.html>。说明 HS 模式的签名与访问限制。

**对本研究的意义：**对未加密、NS/调试或合法取得的 Falcon 代码，envydis + Ghidra 模块已经构成公开基线；对 Blackwell FSP/RISC-V/加密 HS payload，则不能假定 Falcon v6 工具链足够。工具链空白主要在新一代 FSP/RISC-V 语义、专用 descriptor 和加密 payload，而不是基础 Falcon 反汇编。

## 总体判断：公开世界已有工作与空白

### 已有人做过/已有公开基线

1. **Falcon 基础逆向和反汇编：**envytools/envydis、Ghidra Falcon module、Falcon 安全模式文档。
2. **宿主侧 GSP/FSP 启动和通信：**Linux Nouveau/Nova、NVIDIA open-gpu-kernel-modules、FSP CoT/EMEM/mailbox/MNOC 相关代码。
3. **GSP/RM fuzzing 方向：**Black Hat USA 2025 NVIDIA 演讲公开提及 RM、RTOS、GSP fuzzing；Moneta 等工作覆盖 GPU driver fuzzing。
4. **宿主驱动 RPC 内存安全漏洞：**CVE-2024-58018、CVE-2024-58019、CVE-2025-38187 等，但它们不应误标为专有 GSP 固件漏洞。
5. **平台 FSP 固件安全公告：**CVE-2025-23301/23302 明确涉及 HGX/DGX VBIOS/LS10 中的 FSP code。

### 截至本次公开检索仍属空白或弱覆盖

1. **GB202/GB203/GB100 FSP_RUN 的完整语义和 `app=0x24,target=0x0f` descriptor 解析。**
2. **Blackwell FSP 明文转储、生产加密 payload 的公开解密研究。**公开资料主要停留在容器、签名、CoT 和宿主加载器层。
3. **针对 FSP 的 NVDM/MCTP over EMEM/MNOC 独立安全审计。**协议和通道实现有公开线索，但没有找到公开的边界/状态机/权限漏洞报告。
4. **专有 GSP-RM RISC-V blob 内部的、可由宿主触发的内存破坏 CVE。**现有 CVE 主要落在宿主 Nouveau 或通用显示驱动层。
5. **面向 Blackwell FSP/RISC-V 新变体的完整反汇编、反编译与语义恢复工具链。**

**核查结论：**若自有 RTX 5090 研究发现涉及上述五个空白点，尤其是 FSP descriptor 语义、FSP 通道边界或 Blackwell 专有 payload 行为，那么从公开信息基线看，尚不能认为已经被公开充分研究；但应先排除“其实是宿主驱动 RPC 已知问题”以及“仅为可靠性/启动失败而非安全漏洞”的情况。

## 6. 追查:CVE-2025-23301/23302 细节

**检索词：**

- `CVE-2025-23301 NVIDIA HGX DGX VBIOS FSP`
- `CVE-2025-23302 NVIDIA LS10 FSP`
- `CVE-2025-23301 CVSS vector NVD`
- `CVE-2025-23302 technical analysis ZDI mailing list`
- `NVIDIA HGX DGX VBIOS LS10 September 2025 1.8.1 changelog`

**核查日期：**2026-09-27。以下区分 NVIDIA 公告、NVD 状态、NVIDIA 固件文档和第三方数据库；未提供利用开发内容。

### 官方公告与 CVE 记录

- **[找到] NVIDIA Security Bulletin 5674（2025-09-02）** — <https://nvidia.custhelp.com/app/answers/detail/a_id/5674/>。标题为 *Security Bulletin: NVIDIA HGX and DGX VBIOS and LS10 - September 2025*。公告将两项问题都描述为不安全的 debug-access 配置/级别：
  - **CVE-2025-23301：**VBIOS misconfiguration may allow an attacker to set an unsafe debug access level，可能导致 denial of service；组件是 HGX/DGX Hopper 与 Blackwell **VBIOS**。
  - **CVE-2025-23302：**LS10 misconfiguration may allow an attacker to set an unsafe debug access level，可能导致 denial of service；组件是 HGX/DGX Hopper 与 Blackwell **LS10 NVSwitch firmware**。
  公告给出的严重性均为 **Medium，CVSS 4.2**；Hopper 受影响版本为 VBIOS/LS10 `<=1.7.1`，Blackwell 为 `<=1.2.0`。公告页同一安全公告表中只有这两个 CVE，未见另外的 FSP/VBIOS CVE。
- **[找到] CVSS/CWE（公开 CVE 镜像转录，日期未见）** — <https://app.opencve.io/cve/CVE-2025-23301>、<https://opencve.alliance.unm.edu/cve/CVE-2025-23302>。两条记录均转录为 **CWE-1244: Internal Asset Exposed to Unsafe Debug Access Level or State**，CVSS v3.1 `AV:L/AC:H/PR:L/UI:N/S:C/C:N/I:L/A:L`，分数 4.2。含义是：本地攻击、高复杂度、低权限、无需用户交互；**Scope changed**；无机密性影响，完整性和可用性影响均为低。它不是缓冲区溢出、越界读写或整数溢出的公开分类，也没有公开信息泄漏影响。
- **[未找到] NVD 条目** — <https://nvd.nist.gov/vuln/detail/CVE-2025-23301>、<https://nvd.nist.gov/vuln/detail/CVE-2025-23302>（检索日 2026-09-27）。检索结果未显示可核验的 NVD CVE 页面/描述或 NVD CVSS 数据；因此不能把上述 OpenCVE 镜像内容称为“NVD 原文”。当前可复核的权威描述仍是 NVIDIA 公告及其 DGX 文档。

### FSP 代码和权限语境

- **[找到] NVIDIA DGX H100/H200 Firmware Changes 文档（页面日期未见，内容对应 2025 固件更新）** — <https://docs.nvidia.com/dgx/dgxh100-fw-update-guide/firmware-changes.html>。文档明确把 CVE-2025-23301/23302 归因到 VBIOS 与 LS10 中的 **FSP code**，并说明攻击者若取得对 FSP 的 root/特权访问，可修改寄存器数据，可能造成 DoS。这里的“root access to the FSP”是 FSP 访问语境；不要不加限定地等同为任意普通操作系统 root。它提供了比公告更多的“修改寄存器/DoS”线索，但没有寄存器名称、触发条件、代码位置或 PoC。
- **[找到] 向量细节** — `AV:L` 排除远程/网络向量；`AC:H` 表示需要特定条件或较高复杂度；`PR:L` 是 CVSS 模型的低权限门槛；`S:C` 表示影响跨越到另一安全权限域。公告/文档没有公开更具体的 FSP API、寄存器或攻击序列。

### 修复版本与 changelog

- **[找到] NVIDIA 公告（2025-09-02）** — <https://nvidia.custhelp.com/app/answers/detail/a_id/5674/>。Hopper 修复版本为 **1.8.0**，Blackwell 修复版本为 **1.2.1**（分别适用于 VBIOS/LS10 的对应固件线）。
- **[找到] DGX H100/H200 Firmware Changes（页面日期未见）** — <https://docs.nvidia.com/dgx/dgxh100-fw-update-guide/firmware-changes.html>。实际 DGX H100/H200 更新指南使用 GPU Tray Firmware **1.8.1**；该页可见的额外 1.8.1 变更是 **CC/PPCIe mode 启用 ECC counters**，没有进一步公开 CVE 修复机制。故“1.8.1”是相关 Hopper DGX 固件包/目标更新版本；不能替代公告中 Hopper 1.8.0、Blackwell 1.2.1 的组件修复版本表述。

### 第三方分析、邮件列表与社交资料

- **[找到，但仅为数据库整理] GPU VulnDB：CVE-2025-23301** — 日期未见；<https://gpuvulndb.org/vuln/CVE-2025-23301>。重复 NVIDIA 的 unsafe debug-access/CWE-1244 元数据，并讨论共享/机密计算 GPU 节点的运营影响；页面标注为机器辅助/未经独立验证，未给出 FSP 内部技术细节。
- **[找到，但仅为数据库整理] GPU VulnDB：CVE-2025-23302** — 日期未见；<https://gpuvulndb.org/vuln/CVE-2025-23302>。补充 NVLink fabric/GPU partitioning 受中断的运维影响；未给出可复核的寄存器、代码路径或触发条件。
- **[找到，但信息增量很小] CVETodo / OffSeq** — 日期未见；<https://cvetodo.com/cve/CVE-2025-23301>、<https://radar.offseq.com/threat/cve-2025-23302-cwe-1244-internal-asset-exposed-to--264217c2>。主要是公告和 CVSS/CWE 的自动化或半自动化汇总，未发现独立逆向分析。
- **[未找到]** 截至检索日，未找到专门的 ZDI advisory、实质性公开邮件列表分析、公开 PoC/exploit 或社交平台上的可复核 FSP 技术拆解。搜索到的邮件列表结果主要是同编号近似项或无关 CVE；不能算这两项漏洞的技术分析。

### 同公告页面的其它披露

- **[找到]** 直接公告页 <https://nvidia.custhelp.com/app/answers/detail/a_id/5674/> 的 CVE 表仅包含 **CVE-2025-23301**（VBIOS）和 **CVE-2025-23302**（LS10）；未发现第三个 FSP/VBIOS CVE。
- **[找到，但不是同一公告]** NVIDIA 2025-09 附近的其它安全公告另有 BlueField/ConnectX/DOCA/DPDK、NVDebug Tool 及 DGX/HGX HMC/BMC 相关 CVE；这些不应并入 5674 的 VBIOS/LS10/FSP 漏洞范围。NVIDIA 产品安全索引：<https://www.nvidia.com/en-us/security/>（页面日期/归档日期按各公告显示）。

**结论：**两项 CVE 的公开本质是 FSP 中不安全 debug-access 状态/配置（CWE-1244），影响是潜在 DoS；公开资料不支持将其归类为缓冲溢出、越界、整数溢出或信息泄漏。CVSS 共同为 4.2，`AV:L/AC:H/PR:L/UI:N/S:C/C:N/I:L/A:L`。NVIDIA 公告和 DGX 更新文档提供了“特权 FSP 访问→修改寄存器→DoS”的最高技术细节；截至核查日未找到独立的漏洞触发细节或利用代码。
