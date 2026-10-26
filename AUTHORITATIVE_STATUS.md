# GSP / LibOS 研究权威总览

> **文件**：`/home/user/gsp_libos_clean/AUTHORITATIVE_STATUS.md`
> **版本**：2026-10-27（r3：补入 FSP 明文离线审计收束、事故复核与真机停止决定）
> **定位**：GSP/LibOS 主线权威进度。FSP 明文专项的最终入口是 `fsp_plaintext_audit_20261027/FINAL_STATUS_AND_RESUME_GUIDE_20261027.md`；硬件风险见 `HARDWARE_DO_NOT_TOUCH_RISK_SUMMARY_20261027.md`。
> **原始资料**：2026-10-18 的 230 份索引语料仍保留；10-25 至 10-27 的新增文档通过 `docs/INDEX.md` 附录登记。原始大体量实验材料仍不纳入公开仓库。
> **证据分级**：E0–E6，定义见 `docs/EVIDENCE.md`。本文件所有结论都带级别；没有级别的“已验证/实锤”不作数。

---

## 0. 读法与硬规则

### 0.1 先读哪几页

| 目的 | 读法 |
|---|---|
| 5 分钟了解现状 | 本文件 §1、§3 |
| 接手继续做 | 本文件 §11 → `OPEN_QUESTIONS.md` → `NEXT_STEPS.md` |
| 查某结论是否可信 | 本文件 §3/§4/§5 → `FINDINGS.md` 的 ID → 原始 `file:line` |
| 写对外材料 | 本文件 §10（坑）→ `FINDINGS.md` §J（引用限定）→ `CORRECTIONS.md` |
| 找旧文档 | `docs/INDEX.md`、`docs/ARCHIVE_INDEX.md` |

### 0.2 五条硬规则

1. **模拟器结论不得写成真机结论。** QEMU/`rv64_emu.py` 的结果必须标 E3/E4，并注明“受控实验/本 profile”。
2. **真机与模拟器冲突时拆成两条 claim。** 典型：t0=4 fast path 的 lab 语义（E3）与真机 U-mode 可达性（未证）。
3. **后续文档只是“声称”而没有证据时，标 unresolved。** 只有“后续 + 证据”才能进 `CORRECTIONS.md` 的“已裁决”。
4. **地址必须带版本。** 610.57.04 / 615.71.09 / MODS 570.215 的 VA 不可互套。
5. **原则上不改历史原文。** 发现错误先登记到 `CORRECTIONS.md`；若错误会直接误导密码学归因或硬件安全判断，公开副本可加醒目更正横幅并改写错误段落，同时保留更正记录。

---

## 1. 一句话现状

**QEMU 模拟器支线**：生产 LibOS 已能自然 boot 到 init、穿过 384B 启动区域表并发布 walk 表（E3）；完整 FSP/FMC/LibOS/GSP-RM 启动链**未完成**，下一处缺项是 handoff init 参数 blob 与内核日志窗口。

**真机 GSP 支线**：RPC 队列溢出、B8 回调劫持、读原语、清零原语已成立（E1）；“U-mode 可达的提权链”**仍未闭合**。

**FSP 支线**：离线审计恢复了 AES-256-GCM 软件 consumer ABI（32-byte caller key、12-byte IV、16-byte tag、空 AAD），但没有获得 GB202 `FSP_RUN` 明文、data key、KDF root 或 bulk plaintext export。公开 MODS/FieldDiag/FuseRework 搜索亦未得到关键四件套。

**结论**：目前没有一条从 U-mode 到 S-mode 代码执行的端到端、真机可复现链条，也没有 GB202 FSP 明文。由于已有 FSP/GSP/WPR2/PCIe/内核级事故链，现有 RTX 5090 的真机实验明确停止；后续仅保留离线静态、模拟器或独立可牺牲样品路线。

---

## 2. 目标、环境、版本

### 2.1 目标

在 RTX 5090（GB202）的 GSP 芯片（RISC-V）上，把 RM 任务从 U-mode 提升到 LibOS 内核的 S-mode，最终取得 GPU 完全控制。

### 2.2 目标卡与环境

- 目标卡：ASUS RTX 5090 Astral（GB202，`10de:2b85 / 1043:89e3`），双 BIOS（XOC / 原版）。
- 当前可工作状态：宿主直跑，`nvidia-smi`/CUDA 正常，使用 WPR2-bypass 补丁模块（`REVIVAL_FINAL.md:3-8`）。
- 实验环境分三类：
  - **E0**：宿主直跑物理卡（FSP/时钟/部分 GSP 实验）。
  - **E1**：GPU 整 IOMMU 组直通 VM（`vm_mods_lab`、`vfio_production_lab`；多数 GSP 溢出/B8 实验）。
  - **E3**：QEMU `nvidia-gsp-lab` 纯 TCG 模拟（`gsp_qemu`）。
- 驱动/固件版本必须逐条标注：
  - **610.57.04**：GSP/QEMU 主线。
  - **615.71.09**：K3-1/原版槽观察。
  - **MODS 570.215**：MCLK 故障。
  - 三者地址不可互套（`CORRECTIONS.md` C-12 类问题）。

### 2.3 安全前提

- **当前决定：不再对现有 RTX 5090 执行 FSP/GSP 消息、BAR/MMIO 扫描、reset、MODS 极限测试、FuseRework、flash 或 fuse 操作。**
- 历史记录证明“只读”和“恢复”也不天然安全：宽范围扫描、畸形消息、bind/rescan/SBR 曾造成 Xid、WPR2 stale、掉总线以及不可杀的内核 R/D 状态。
- 离线模拟继续遵守 `AGENTS.md`：不伪造启动成功、不改原厂固件；任何未来真机工作须使用独立可牺牲样品并重新取得明确授权。

---

## 3. 攻击面与利用方式总表

> 这张表覆盖所有主要漏洞/原语。详细证据见 `FINDINGS.md` 对应 ID；状态里的“可用/受限/未闭合”指**当前证据**，不是自评。

| ID | 攻击面 / 原语 | 利用方式（简） | 证据 | 状态 / 限制 |
|---|---|---|---|---|
| GSP-OVF | RPC 消息队列溢出 | 声明 33 元素 → 泵全读 → metadata 溢出；v21 MAP 精确控制元素 32；v22 `xdig_meta_only` 只溢出 232B metadata；v25.3 两步法（33 → 等 50ms → 续传凭证）保持泵存活 | E1 | 可用；`B8=0xDEADBEEF` → `sepc=0xdeadbeee`；`B8=ret0` → Xid120=0 |
| GSP-B8 | metadata+0xB8 回调劫持 | 覆盖 `fcnBackendRw` 函数指针；`a1` 完全可控（MAP 0x10038→[s1+0xA0]），`a0` 可控（MAP 0x10030，GSP-16）；支持 46 连发与 MAP 轮换 | E1 | 可用；**B8 在 U-mode 执行**（GSP-17 修正，原"S-mode"为误判；泵=RM task=U-mode） |
| GSP-READ | 读原语 | `B8=0x01020A30`（`ld a5,0x168(a1); jalr a5`） | E1 | 数十次验证；可读任意已映射地址 |
| GSP-ZERO | 清零原语 | `B8=0x01B52246`（`c.sw a4,0(a1)`），回调路径 `a4` 恒 0 | E1 | 只能写 0；写任意可写地址 |
| GSP-NONZERO | 非零写入 | a4/a0/a5/s4 均不可控；358 个 `sw a0` 无一有相邻 `ld` | E1/E2 | **未找到**；攻击链根缺口 |
| GSP-WALK2 | walk(2) 触发 | 三明治 gadget `0x1E1E62E` → `sepc=0x1e1e648` | E1 | 单次记录；t0=2 表位置未知 |
| SYSCALL-DISPATCH | t0=N syscall 注入 | B8→RM stub(`li t0,N;…;unimp`)+a0/a1 双控（metadata+0x30/0x38）→ 内核上下文执行 handler；t0=4 分发已在真机确证（GSP-14）。**内核对象经 walk 表门控（meta bit63+type）**；不查 walk 的 handler（t0=7/15 等）a0 直接指针（伪对象候选）。t0=22 = type3+type8 成对 region 操作（0x93006fcc），RM 活跃对象入口 | E1/E2 | OBJ-10..14、GSP-14..16；k61_t4probe/readprobe/win0probe |
| GSP-K31 | K3-1 staging 溢出 | 溢出区含关键堆结构，任何写入都在回调前崩；crash 固定 `pc=0x1b8ffbc`、`stval=0x4fe6` | E1 | 存在但无法精确利用 |
| GSP-LEAK | K3-1 泄漏读 | 崩溃 PC 等于读出值，`*(0x04191678)=0x0FE4790E10`，与 metadata 指针匹配 | E1 | 可用读；精确利用未闭合 |
| OBJ-CREATE | t0=23 CREATE | 创建 type12 对象，`ref=1`、`state=0`；`a0=0`，slot 在 `[sp+0xC]`，不返回给用户 | E3 | QEMU lab；真机 ABI 未验证 |
| OBJ-DEREF | t0=4 慢 handler | `walk → meta&0xC → TYPECALC → +1 ref → state`；state=0 时置 state=1 并调 `0x93005B26`；state=1 时只 +1 | E3 | QEMU lab；不是 destroy |
| OBJ-FASTPATH | t0=4 fast path | 受控 `t0=4,stval=0` 进入 `0x930042F8`：只 state 0→1、ref 不变、不调 handler/`0x93005B26` | E3 | **不是 U-mode 路径**；自然 boot 只命中 t0=0/1/0x16 |
| OBJ-DESTROY | 真正 decref/destroy | `0x93005B26`：ref-- → 0 → TYPECALC → dtor 表 `0xA300A000+type*0x28+8` → `jalr@0x93005B60`，S-mode | E2/E3 | 直接调用可到 dtor；U-mode 可达性未证 |
| OBJ-GADGET | `mv a0,a1; jal 0x93005B26` | `0x930035D2`；受控 PC/a1 下 ref 1→0 → dtor `0x93008130`，priv=1 | E3 | 内核空间；B8 不可达 |
| OBJ-T017 | t0=17 | 曾被认为是 direct destroy；实测是 create/register：`0x93005B26` 收到新分配 s1，不是用户 s2 | E3/E2 | **负结果**；RM 无 t0=17 stub |
| OBJ-TYPECALC | TYPECALC 公式 | `desc=[(obj&~0xFFF)+0x20]`；type=低32位((diff>>3)×0xCCCCCCCD)，基线 `0xffffffffa300a000` | E2/E4 | 静态+旧模拟器复核；GB20X |
| OBJ-TYPEBITMAP | t0=10 / 0x491 位图 | 位图位 0/4/7/10 + type5 特判；type12 在更早的 `meta&2` 被拒 | E3 | QEMU lab |
| C1/C2 | 旧 Python 模拟器链条 | 真实内核镜像 + `rv64_emu.py` 闭合 | E4 | **不是真机**；真机未验证 |
| FSP-COT | COT 信任链 | 860B 中 816B（95%）验证字段被忽略：hash384 全 0xFF、publicKey 任意值，固件未改仍启动 | E0 | 可用；但改固件 1 字节会被拒 |
| FSP-WPR | WPR 元数据签名 | 签名验证真实；COT 层不是 | E0 | 两层必须分开表述 |
| FSP-DOS | FSP runtime 不可用 | 一段畸形 NVDM/传输序列后，PRC/FWUP/caps/InfoROM/clock boost 持续不可用，跨完整断电；GSP 启动与计算仍正常 | E0/E5 | 现象成立；**最小充分触发未知** |
| FSP-PRC | PRC knobs | 47 个 knob 地图及真实写路径；观察到跨会话/复位域状态，但早期“必然写入 InfoROM flash”的归因已降级 | E0/E6 | 生命周期与存储机制未完全证明；禁止继续真机写入 |
| FSP-MNOC | MNOC port 0 | 协议完整闭合，脏卡验证通过；旧“硬件级来源验证”结论错误 | E0 | 可用 |
| FSP-EMEM | EMEM 队列 | `QUEUE_HEAD` 宿主可写，`QUEUE_TAIL` dword 单位，单包驻留；PSEC 块同型 | E2 | 静态；可作通道 |
| FSP-ENCRYPT | FSP_RUN 加密 | MODS host helper 证明 AES-256-GCM 软件 consumer ABI：32B caller key、12B IV、16B tag、空 AAD；目标 key/KDF/root 未找到，无明文 | E4 | 不能把 host consumer 等同于 FSP 片内 producer；专项已收束 |
| TOC-FMC | FMC TOCTOU | 验证期写入→干净拒绝；加载期写入→FSP 锁死；加载后写入→无效 | E0 | **没有可用于 FMC 的漏检窗口** |
| TOC-ELF | GSP ELF TOCTOU | 27MB ELF 在 `sendAndRead` 返回后 100ms 仍被读；写起始 4 字节即挂死 | E0 | 读到 ≠ 执行 |
| TOC-GSP | GSP FMC 写入 | `fw[0x10000]` 写入到达物理内存（d564→0902），GPU 仍工作 | E0 | **未证明执行**；可能在 I-Cache/死代码 |
| WPR2 | WPR2 事故/恢复 | 卸载驱动→COT 基线→size fuzz→version fuzz→PRC handler 死亡；WPR2-bypass 补丁恢复 | E0 | 高风险；Power cycle ≠ SBR |
| CC-BIOS | CC 锁/双 BIOS | 双槽失败 ≠ 两颗 flash 同时损坏；共享 GPU/FSP 状态可让两槽同时失败；旧切槽方案失败 | E0/E5 | 恢复以 v2 为准 |
| CLK-MCLK | 显存频率 | +3999（18000MHz）通过；+4000（18001MHz）失败于 completion wait 超时，marker `0x25728`（不是 `0x256c8` busy） | E0/E2 | 设备侧首因未定位 |
| CLK-XBAR | XBAR 独立时钟域 | 独立 PMU 对象/时钟源/VF 点；改变它改变实测时钟与吞吐 | E0+E2 | 可作性能/功耗原语 |
| HW-FAN/L2 | 风扇/L2 | Fan0/1 映射；Lightning 800W VBIOS 只声明一个 FAN_COOLERS；L2 96→128MiB 无安全工具 | E0/E2 | 风扇映射可用；L2 负结论 |

### 3.1 哪些能用 / 哪些不能用

| 状态 | 项 |
|---|---|
| **真机可用（E1）** | RPC 溢出、B8 劫持、读原语（限回调 MPU=RM 空间，GSP-15）、清零原语（同限）、多 fire/MAP 轮换、K3-1 泄漏读、B8 注入的 a0/a1 双控（GSP-16）、t0=4 syscall 分发存活（GSP-14） |
| **真机可用但有条件（E0）** | FSP COT 字段忽略、PRC flash 持久化、MNOC port0、FMC/ELF TOCTOU 读 |
| **仅 QEMU lab（E3）** | t0=23 create、t0=4 slow/fast、0x93005B26 destroy、dtor、gadget 0x930035D2 |
| **未成立** | 非零写入、U-mode 净 -1 destroy、B8→内核 05B26、端到端 U-mode→S-mode |
| **旧模拟器（E4）** | C1/C2 链条；不可当真机 |

### 3.2 可组合链条

- **Chain R1（真机，可用）**：RPC overflow → B8 → read/zero write → leak/control。
- **Chain R2（真机，未闭合）**：RPC overflow → B8 → RM read → object pointer → RM trigger → 05B26 → dtor。缺口：非零写、U-mode 可达 trigger、对象指针。
- **Chain Q1（QEMU，受控）**：t0=23 create → t0=4 release → 0x93005B26 → dtor → S-mode。仅 E3；B8 不可达内核 gadget。
- **Chain F1（FSP，E0/E6）**：malformed NVDM → runtime DoS；PRC write → 跨状态域变化。早期“确定 flash persistence”归因已降级；不是提权链。
- **Chain T1（TOCTOU，部分）**：GSP ELF read window；execution unproven；FMC 无窗口。

---

## 4. 真机 GSP 利用链（E1）

### 4.1 RPC 队列溢出

- 机制：RPC 消息队列声明 33 个元素，实际只给 1 个；泵把 33 个全读进 staging，导致 metadata 及其后相邻堆溢出。
- v21 MAP：可以精确控制元素 32 内的每 4 字节。
- v22 `xdig_meta_only=1`：只溢出 metadata 232B，不碰相邻堆，降低崩溃概率。
- v25.3 两步法（当前可用配方）：
  1. Phase 1：写 33 个元素 → submit → 泵全部读进 staging → 溢出。
  2. 等 50ms。
  3. Phase 2：写 32 个续传凭证 → submit → RM 收到 → 泵不挂。
- 铁证：
  - `B8=0xDEADBEEF` → `sepc=0xdeadbeee`（溢出确认）。
  - `B8=0x01E1E62E` → `sepc=0x1e1e648`（walk(2) 执行）。
  - `B8=ret0` → `Xid120=0`（泵活着）。
- 限制：回调劫持破坏泵协议；多数操作只能做一次，之后通信退化。真 backend `0x0100CF9C` 能正确处理但无法同时做自己的事。

### 4.2 B8 回调劫持

- `metadata+0xB8` 是 `fcnBackendRw` 函数指针；覆盖它 = 执行任意 RM 固件地址。
- 回调路径：
  - `a1` = `[metadata+0x38]`，通过 MAP 0x10038 → `[s1+0xA0]` 完全可控。
  - `a0` 恒 0。
  - `B8` 在 S-mode 执行。
- 多 fire：46 连发验证，MAP 轮换（fire0/1/2 各不同 map）。
- 关键稳定地址（E1）：
  - `s1`（session）= `0x0FE4790E10`
  - `sp`（内核栈）= `0x0FEB80FCD0`
  - `s0`（帧指针）= `0x0FEB80FCF0`
  - `global handle` = `0x0303000000307c70`
  - `hubclient` 内核 fn 槽 = `[0x0C200EB8]` = `0xFFFFFFFF930019B8`
  - 队列页表 `[0x80]` = `0x10B080000`（GSP VA 0x20880000 映射）

### 4.3 B8 可执行域与读写原语

- 可执行：
  - RM 代码空间 `0x01xxxxxx–0x0F9B000`：所有 gadget 成功。
  - 读原语 `B8=0x01020A30`：`ld a5,0x168(a1); jalr a5`。
  - 写原语 `B8=0x01B52246`：`c.sw a4,0(a1)`，但 `a4` 恒 0。
- 不可执行：
  - 内核代码空间 `0x9300xxxx`：fetch fault（MMU 不映射）。
  - staging/队列/对象目录：NX fetch fault。
- 非零写入：未找到。a4/a0/a5/s4 均为 0；358 个 `sw a0` gadget 无一有相邻 `ld`；ld+sw 紧邻/带间隔/32 位 mv/条件跳全部 0 处。
- 结论：**B8 路径目前只能写 0 到任意可写地址**。清零 hubclient 指针已验证可杀死 GSP；没有“写非零”的原语。

### 4.4 K3-1 staging 溢出与泄漏

- K3-1 staging 溢出存在，但溢出区含关键堆结构；任何写入都在回调前崩，crash 固定 `pc=0x1b8ffbc`、`stval=0x4fe6`。
- 泄漏读成功：崩溃 PC 等于读出值，`*(0x04191678)=0x0FE4790E10`，与 metadata 指针精确匹配。
- 当前判断：K3-1 是“可读、不可精确写”的通道；路径 C（泄漏 + 写回相邻堆）未闭合。

### 4.5 当前真机链条与缺口

已成立：

```text
U-mode RM → RPC 队列溢出 → metadata+0xB8 劫持 → S-mode 执行（限 RM 空间）
          → 读原语 / 清零原语 / 多 fire + MAP 轮换
```

未成立：

```text
① 非零写入原语（造负数/有效 meta）
② 从 RM 空间调用内核 0x93005B26 的路径
③ 获取受控对象的指针/slot
④ U-mode 可达的净 -1 destroy 路径
```

最接近的真机路径（均未闭合）：

- **路径 A**：B8 → RM 空间 read gadget → 读对象指针 → B8 轮换 → RM 空间 trigger（t0=4 slow path）→ 05B26。但 t0=4 是 lookup，不是 destroy；需要 state/refcount 操纵。
- **路径 B**：清零 hubclient 指针 → hub 事件 → 内核 `jalr` 到 `0xFFFFFF...` → S-mode crash。这是“有控制的间接证明”，不是代码执行。
- **路径 C**：清零 refcount → 后续 release → `ref-1=-1` ≠ 0 → 不触发 dtor。**逻辑错误，不可行**；需要从 1 减到 0，不能从 0 减到 -1。

---

## 5. 对象生命周期 / syscall / 提权链

### 5.1 syscall 分发表

- handler 表：`0xffffffffa3008280`，每项 8 字节，32 位 handler 指针。
- 分发：`t0*8 + 表基 → lw → jalr`，**不经过** `[global+0x450]`。
- 34 个 handler（t0=0–35；16、29 为空）。
- RM 实际使用带 stub 的 syscall：0,1,2,3,4(124 处),5,6,8,9,11,12,15,18,21,22,23,27,29,31。
- RM 不使用（无 stub）：7,10,13,14,16,17,19,20,24,25,26,28,30。
- `t0=17` 无 stub → U-mode 不可达（E2）。
- 关键纠正：`0x93003902` 在 `t0=9` handler `0x930038fe` 内，不是全局 syscall dispatcher；`[global+0x450]` 是对象/handle 表，不是分发表。

### 5.2 t0=23 CREATE

- handler `0x93006300`。
- 创建 type12 对象，`ref=1`、`state=0`。
- `a0=0`；slot 写在 `[sp+0xC]`，不直接返回给用户。
- 自动 free-list 分配，slot 不保证固定。
- QEMU lab 观察（E3）；真机 ABI 未验证。

### 5.3 t0=4：慢 handler vs fast path

**慢 handler `0x930008CC`（E3）**：

```text
walk(t1, a0) -> obj/meta
meta & 0xC == 0xC
TYPECALC(obj) == 10
obj-8 (refcount) += 1
state = lw obj+120
if state == 0:
    state = 1
    obj+128 = global
    call 0x93005B26(obj)   # refcount -= 1
else:
    use [global+48], type 9 queue, ...
```

- state=0：先 +1 再 -1，净 0。
- state=1：只 +1，跳过 -1，净 +1。
- 这解释了第一次/第二次 release 的数据。

**fast path `0x930042F8`（E3）**：

- 受控 `t0=4, stval=0` 注入：只做 state 0→1、refcount 保持 1、不调 `0x93005B26`、不调 handler。
- 自然 boot 命中：t0=0/1/0x16；**从未命中 t0=4/23**。
- 结论：fast path 是**模拟器受控入口，不是真机 U-mode 路径**；真机 U-mode 可达性未证明（OQ-01）。

### 5.4 真正 decref/destroy：0x93005B26

- `0x93005B26` 是真正的 decref/destroy：
  - ref-- → 0
  - TYPECALC
  - dtor 表：`0xffffffffa300a000 + type*0x28 + 8`
  - `dtor=[slot]`；非零 → `c.jalr dtor`（`@0x93005B60`，a0=obj，S-mode）
- type10 dtor = `0x93008130`：
  ```text
  0x93008130: addi a0,a0,40
  0x9300813c: jal 0x93000e12
  0x93008148: j 0x930069b6
  ```
- QEMU lab 实测：
  ```text
  LAB_DESTROY_REF_ZERO obj=... refcnt=0
  LAB_DESTROY_DTOR_CALL dtor=0xffffffff93008130 priv=1
  LAB_DESTROY_DTOR_ENTRY pc=0xffffffff93008130 priv=1
  ```
- 注意：直接调用 `0x93005B26` 是**诊断路径**，不是 U-mode 可达 syscall。

### 5.5 gadget 0x930035D2

- 静态：
  ```text
  0x930035d2: mv a0,a1
  0x930035d4: jal 0xffffffff93005b26
  0x930035d8: mv a0,s0
  0x930035da: jal 0xffffffff93005b26
  ```
- 受控实验（E3）：
  ```text
  pc   = 0x930035d2
  a1   = 0x8000000008245030   # type-12 object
  s0   = 0
  sp   = scratch
  ```
  结果：`mv a0,a1` → `jal 0x93005B26` → ref 1→0 → dtor `0x93008130` → priv=1。
- 限制：gadget 在内核空间 `0x93xxxxxx`；B8 只能执行 RM 空间 `0x01xxxxxx`，**B8 不可达**。需要 RM 空间等价 gadget，或 syscall 间接触发。

### 5.6 t0=17 负结果

- 曾被认为是“直接 U-mode destroy 入口”。
- 实测：`0x93001B64` 的 `a0` 是新分配对象 `s1`，不是用户输入 `s2`。
- `s2` 只被存成新对象 `+40` 的一个字节；`0x93005B26` 收到的是 `s1`。
- 注册后新对象 ref=2，释放后 ref=1；没有 ref→0，没有 dtor。
- t0=17 是 create/register，不是 destroy 用户指针。
- RM 固件中 `li t0,17` 有 80 处，但没有一处紧跟 `unimp`；全量 syscall stub 167 处，t0=17 为 0。

### 5.7 当前提权链状态

| 链 | 内容 | 状态 |
|---|---|---|
| A | B8 → RM read gadget → 对象指针 → RM trigger(t0=4 slow path) → 05B26 | 未闭合；t0=4 是 lookup，不是 destroy；无非零写 |
| B | 清零 hubclient → hub 事件 → 内核 jalr → S-mode crash | 有控制的崩溃证明；不是代码执行 |
| C | 清零 refcount → release → -1 | 逻辑错误；不可行 |
| QEMU | 受控 PC/a1 → 0x930035D2 → 05B26 → dtor | 受控实验成立；B8 不可达内核 gadget |

**根缺口**：U-mode 可达的净 -1 destroy 路径；非零写入；对象指针/slot 获取；B8 到内核 05B26 的桥。

---

## 6. QEMU / LibOS 模拟器

### 6.1 它是什么

`gsp_qemu` 是独立 QEMU 11.1.2 开发构建，新增 `-machine nvidia-gsp-lab` / `nvidia-gsp` 启动链开发入口。它执行生产 FMC/LibOS 原始镜像，目标是恢复 GSP 启动链、验证 syscall/对象布局，回答真机黑箱答不了的问题。

### 6.2 已实现（E3）

- 生产 FMC 包在宿主侧通过 SHA384 + ECDSA-P384 验证；错误信任锚在 CPU 启动前被拒绝（宿主侧实现，不等于芯片熔断/BOOTROM 认证）。
- 原始 610.57.04 生产 LibOS 从 boot 执行到 init：`pc=0xffffffff93001ec6`。
- 384B 启动区域表：**生产者已实测**（原始 SBI server；`make probe-lab-table`）。契约 `source=(a5<<58)+a6+0x200`（64 位回绕）、16×24B、`size==0` 跳过；本 profile 4 个非空项（FB WPR heap / WPR meta / 整段 FB aperture / SYS）。`a5=3` 是把 FB 物理地址折回 `0x8000…` VA 窗口的回绕常量（Q-11）。
- init 消费者契约：逐项校验 `[base,base+size)` 在 `0x9300c918` 的 8 个 aperture 内，然后写 9×24B 记录到 `0xffffffffa3008e28`（`+8` 是滚动累加值，不是地址）（Q-12）。
- 审计分支 `handoff=fixture` 已穿过该检查点：`BOOT_REGION_TABLE_ACCEPTED pc=0xffffffff93002052`；新停点为 handoff init 参数 blob（`line 220`）与日志窗口 `0xffffffff60000000`（`mcause=5`）（Q-13）。
- trap 入口的 `CSR 0x5c0`（trap scratch，静态仅 `0x9300395e` 写 / `0x930039e2` 读）与 `time (0xc01)` 已建成硬件输入（Q-14）。
- lab profile 执行到 `0xffffffff93007324`（`sd s7,0x450(s0)`），发布 walk 表：
  - `global=0xffffffffa3013030` → `[global+0x450]=0x800000000803a000`
  - `global=0xffffffffa30134d0` → `[global+0x450]=0x8000000008046000`
- walk 表回读：4096B、116 项、SHA256 稳定；`meta=[entry+16]` 的 bit63=1。
- lab 测试：
  - `t0=23 create` → `t0=4 release`（handler 级）
  - 直接 `0x93005B26` → ref 0 → dtor `0x93008130` → priv=1
  - `t0=4 fast path` 受控入口
  - gadget `0x930035D2` 受控验证
  - t0=17 反例

### 6.3 未实现 / 未完成

- handoff init 参数 blob（入口 `a1`/`a2`，生产 lab 为 `FB+0x801c000`/`0x7e4000`）与内核日志窗口 `0xffffffff60000000`。
- 自定义 MMU（CSR 1482–1487）的 handle 翻译。
- RM task 完整启动（需要第三个 map 成功）。
- FSP/FMC/LibOS/GSP-RM 完整启动链。
- 从 QEMU 读取真机 walk 表地址（lab 地址不是真机地址）。
- `0x800000000803a000` 只属本 profile；真机探针必须使用真机布局。

### 6.4 常用命令

```sh
cd /home/user/gsp_libos_clean/gsp_qemu
make build          # 独立构建，不覆盖系统 QEMU
make test           # 包验证 / ISA / MPU / 原始内核 / lab 回归
make test-lab       # 签名 FMC + 原始 LibOS → walk 表检查点
make probe-kernel   # 原始 boot → init → 区域表接受，记录下一处缺项
make probe-lab-table # 原始 SBI server 生成的 384B 区域表 + init 解析记录
make test-lab-fastpath
make test-lab-statecond
make test-lab-release
make test-lab-destroy
make test-lab-gadget
make test-lab-t017
```

> 注意：`gsp_qemu/README.md` 与 `docs/LAB_BOOT.md` 中的 `cd /home/user/rt_5090_project/...` 是拷贝前旧路径；在本副本中改为 `/home/user/gsp_libos_clean/...`（`CORRECTIONS.md` C-13）。

### 6.5 关键文件

- `gsp_qemu/README.md` — 当前能力、边界、测试。
- `gsp_qemu/PROGRESS.md` — 进度检查点、下一处缺项。
- `gsp_qemu/docs/LAB_BOOT.md` — syscall/对象生命周期/lab 实验的详细记录。
- `gsp_qemu/docs/MPU_MODEL.md` — MPU/CSR/handle 模型。
- `gsp_qemu/docs/SOURCES.md` — 固件来源与哈希。
- `gsp_qemu/Makefile`、`scripts/`、`firmware/`、`patches/`、`qemu/`。

---

## 7. FSP / 信任链 / TOCTOU

### 7.1 COT 与 WPR

- COT（860B）：816B（95%）验证字段被忽略；hash384 全 0xFF、publicKey 任意值，固件未改仍能启动（E0）。
- 但“hash 全 0xFF + 改固件 1 字节”会被 FSP 拒绝，说明固件本体仍被校验（E0）。
- WPR 元数据层签名验证真实；COT 层不是。两层必须分开表述（E0）。
- COT（NVDM type 0x14）只在 FSP boot-phase dispatcher 有 handler；runtime dispatcher 静默丢弃（无响应、无错误、通道不受影响）。

### 7.2 FSP runtime DoS

- 现象：一段畸形 NVDM/传输序列后，FSP runtime 服务（PRC、FWUP、caps、InfoROM、clock boost）持续不可用，跨完整断电；GSP 启动与计算仍正常（E0）。
- 最小充分触发未知：序列含多次操作，期间未恢复并复验 FSP 健康（E5）。
- 对外稿件必须写“畸形序列后 runtime 服务持续不可用”，**不能**写“单条 ROMREAD 即永久 DoS”。

### 7.3 PRC / MNOC / EMEM

- 47 个 PRC knob 地图及真实写路径已恢复；曾观察到跨驱动周期/reset-domain 状态，但物理 flash/InfoROM 存储机制未证明，早期“固定毒记录”说法已降级。
- MNOC port 0 协议完整闭合，并在脏卡上验证通过；旧“硬件级来源验证”结论错误。
- EMEM 命令队列：`QUEUE_HEAD` 是 FSP 读区间起点且宿主可写；`QUEUE_TAIL` 为 dword 单位；单包驻留；PSEC 块 `0x840000–0x843fff` 同型。
- MODS 570/FieldDiag 580 的 host helper 证明 AES-256-GCM consumer ABI（32B caller key、12B IV、16B tag、空 AAD）；没有建立它到目标 `FSP_RUN` 或片内 KDF/root producer 的数据流。
- 本地 58 条有效 `FSP_RUN` 记录仅形成 6 个唯一 GB202 对象；公开 MODS/FieldDiag/FuseRework 与网盘搜索仍未取得明文或关键四件套。

### 7.4 TOCTOU（三个对象，禁止互套）

- **FMC**：验证期写入 → 干净拒绝；加载期（10–45ms）写入 → FSP 锁死（`MBOX=badf4100`）；加载完成后写入 → 无效。**没有可用于 FMC 的漏检窗口**。
- **GSP ELF（27MB）**：`sendAndRead` 返回后 100ms 仍被 FMC 读取；写 ELF 起始 4 字节即致 GSP 挂死。**读到 ≠ 执行**。
- **GSP FMC**：`fw[0x10000]` 写入到达物理内存（`d564→0902`，clflush+mfence 后），GPU 仍工作。**未证明执行**；FMC 可能在 I-Cache，`0x10000` 可能是死代码。

### 7.5 WPR2 / CC / 双 BIOS

- WPR2 事故序列：卸载驱动 → COT 基线 → size fuzz（静默消费）→ version fuzz（PRC handler 死亡、MT=0 不响应）。
- Power Cycle ≠ SBR：SBR 清除特定 reset domain 并让 FSP 走另一条初始化路径；断电不一定达到同样效果。
- “一次操作后两个 BIOS 槽都无法启动”不是两颗 SPI flash 同时永久损坏；共享 GPU/FSP 状态可让两槽同时表现失败。
- 原版槽最后一个无争议健康点：2026-09-28T12:32Z。
- CC 锁恢复：旧“切槽 + `prc_rw w 8 0`”方案已于 2026-09-29 实测失败；恢复程序以 v2 为准。

---

## 8. 时钟 / 电压 / 功耗 / 风扇 / L2

> 这条线不是 GSP 提权链的一部分，但属于同一张卡的研究面。用作性能/功耗原语时，必须与 GSP 结论分开引用。

- **MCLK**：
  - 18000MHz（relation offset 3999000 kHz，+3999）通过；硬件实测约 17982MHz（≈请求×1000/1001）。
  - 18001MHz（+4000）在显存测试开始前失败；PMU 在 `SEPC=0x205d1a2c` 断言停机，host 等 `CHANGE_SEQ_PMU` 后返回 `NV_ERR_TIMEOUT(0x65)`。
  - 失败 marker 是 `0x25728` = completion wait 超时；`0x256c8` 才对应 busy。两者不可混称。
  - 设备侧首因未定位；不能定性为 FSP 拦截、36Gbps 硬限制或显存训练失败。
- **XBAR**：独立物理时钟域，有独立 PMU 对象、时钟源、VF 点、硬件测频与运行时控制；改变它改变实测时钟与渲染吞吐。
- **显存锁频**：`min=max=15000` 在不变 V/F 曲线与 +2000 offset 下，CP2077 PT 平均 FPS 下降 16.43%、GPU 时钟降 118.1MHz。
- **显存上限**：有限 MCLK 上限会静默约束 XBAR/SYS；路径追踪下板功耗降约 146W 而性能降约 15.5%；FurMark 下报告核心频率上升但渲染吞吐降约 32%。
- **VF 点**：`CLK_VF_POINTS` INFO `0x20809021`/`0x8208`B；STATUS `0x20809022`/`0x98208`B。
- **风扇**：逻辑 Fan0/controller0 驱动物理风扇 1 与 3；Fan1/controller1 驱动 2 与 4。Lightning 800W VBIOS 只声明一个 `FAN_COOLERS` 活动槽（`00 ff ff ff`），导致 fan1/PWM11/GPIO3 运行时对象缺失。
- **L2**：目前不能安全写出把 L2 96→128MiB 的工具；已排除 `fbp_l2slice_enable` 等两条直接路径（E2 负结论）。
- **SM120**：SASS 缓存控制与特殊寄存器访问已单独整理；不含普通算术 ISA。

---

## 9. 工具、脚本、项目地址

### 9.1 目录

所有路径相对 `/home/user/gsp_libos_clean`；原件在 `/home/user/rt_5090_project`。

| 路径 | 用途 |
|---|---|
| `gsp_qemu/` | QEMU GSP/LibOS 模拟器主线；源码、固件、脚本、测试 |
| `gspkm/` | NVIDIA open kernel modules 610.57.04 源码 |
| `driver_gpio_internal_610.43.03/` | 610.43.03 + GPIO internal 补丁源码 |
| `power_governor_reverse/` | GSP 时钟/功耗 governor 逆向；静态为主，含 Ghidra 数据库 |
| `ghidra_static/` | GSP/PMU Ghidra 工程（`gb202_gsp570144`、`gb202_gsp61057`、`gb202_gsp610`、`gb202_pmu570215`）；勿按文本扫描 `.rep` |
| `ghidra_scripts/` | 反编译/函数创建/指针扫描脚本 |
| `fsp_code/` | FSP 明文代码摘录/反汇编 |
| `fsp_ace_static_20260927/` | FSP ACE 静态战役报告、artifacts、notes |
| `gsp_fsp_iface/` | GSP-FSP 接口笔记（可能为空） |
| `vm_mods_lab/` | 隔离 MODS VM / GPU 直通实验记录；本副本只含文档/配置，不含 qcow2/img/iso |
| `vfio_production_lab/` | VFIO 生产测试 lab 文档；本副本不含 guest 镜像 |
| `docs/` | 索引、证据分级、去重方案、归档索引 |

### 9.2 关键脚本

- GSP/QEMU：
  - `gsp_qemu/scripts/test-lab-*.sh`（release/destroy/gadget/fastpath/t017/statecond）
  - `gsp_qemu/scripts/` 下的构建、探针、回归脚本
  - `gsp_qemu/Makefile`
- 真机溢出/B8：
  - `k3_*.sh`（`k3_a4chain.sh`、`k3_cmdscan.sh`、`k3_disc_run.sh`、`k3_fire_v21.sh`、`k3_fn76*.sh`、`k3_gold.sh`、`k3_loadgadget.sh`、`k3_meta_dump.sh`、`k3_revive.sh`、`k3_spy.sh`、`k3_t15clean.sh`、`k3_t27*.sh`、`k3_t3shot.sh`、`k3_txpost.sh`、`k3_txrev.sh`）
  - `k61_*.sh`（`k61_fast_shot.sh`、`k61_scan.sh`、`k61_serial_init.sh`、`k61_shot.sh`、`k61_start.sh`）
  - `auto_fire*.sh`、`AUTO_FIRE.sh`
  - `scan_*.sh`（`scan_ghost_n.sh`、`scan_high_n.sh`）
  - `tbl_scan*.sh`、`leak_*.sh`（`leak_ptr.sh`、`leak_tbl.sh`）
  - `t0_probe.sh`、`alias_matrix.sh`、`bar0rw.c`、`bar0rw`
- VM/恢复：
  - `vm_launch.sh`、`vm_stop.sh`、`vm_cycle.sh`、`vm_fire.sh`
  - `GPU_REVIVE.sh`、`GPU_REVIVE_V2.sh`、`k3_revive.sh`
- 时钟/功耗：
  - `power_cap_limit_probe*`、`xbar_clock_demo*`、`xbar_vf_point_demo*`、`prc_*`、`mnoc_prc*`、`reset_coupling_probe.py`、`statestore_search.py`、`y2z_search.py`
- 3DMark/issue1266（非 GSP 主线）：
  - `scripts/3dmark-live-monitor.sh`、`scripts/analyze-issue1266-*.py`、`scripts/audit-issue1266-*.py`

### 9.3 固件/关键二进制

- `rm_fw_plaintext.bin` — 明文 RM 固件（15,298,560 bytes，加载基址 `0x1000000`）。**所有 gadget 搜索必须用它**；`gsp_ga10x.bin` 是加密签名容器，不能直接反汇编。
- `golden_gunv2.ko` — 驱动模块（20MB）。
- `nvflash_5877_text_disasm.asm` — NVFlash 文本反汇编（115MB）。
- `gsp_qemu/firmware/` — `gsp-bootstrap`、`kernel-610.57.04/kernel-load-segments.elf`、`gsp-fwimage`、`fmc-610.57.04.bin`、`bootloader-610.57.04.bin`。
- `power_governor_reverse/` 下的 PMU/GSP ELF、`.objdump.txt`、`.c` 反编译。
- `ghidra_static/*.rep` — Ghidra 工程，不是文本。

### 9.4 构建/运行入口

```sh
# QEMU 主线
cd /home/user/gsp_libos_clean/gsp_qemu
make build
make test
make test-lab
make probe-kernel

# 真机实验前
nvidia-smi
# 按 AGENTS.md 确认恢复路径；不要伪造启动成功
```

### 9.5 原始路径

- 原件：`/home/user/rt_5090_project`
- 清理副本：`/home/user/gsp_libos_clean`
- 旧文档中的 `cd /home/user/rt_5090_project/...` 需改为 `cd /home/user/gsp_libos_clean/...`（`CORRECTIONS.md` C-13）。历史命令保留原路径，不要批量改历史记录。

---

## 10. 已知的坑

### 10.1 证据/文档坑

| # | 坑 | 正确处理 |
|---|---|---|
| 1 | **V5:784** 把“t0=4 fast path”写成“真正的 U-mode 路径” | 这是 E3 受控入口；`LAB_BOOT:606-631` 原文是“不是 U-mode trap”；自然 boot 未命中 t0=4（C-01） |
| 2 | **V5:743** 标题“已证明的核心事实（全部有实验证据）”把真机、静态、QEMU lab 并列 | 按 E0–E6 拆条；`FINDINGS.md` 已拆（C-02） |
| 3 | “真机/硅晶验证” | 多数是直通 VM（E1），少数是宿主直跑（E0）；引用标 E0/E1 |
| 4 | “真内核” | 指真机固件里的 `kernel_gb20x.elf`，仍由模拟器执行（E4），不是真机 |
| 5 | “A 级/实锤/已证明” | 作者自评；忽略，改看 E 级别与置信度 |
| 6 | 同名不同物 | `C2_ENTRY_AUDIT_20260926.md` 是 10-11 的残片；见 `docs/INDEX.md` |
| 7 | 旧权威档 | V5 > V4 > v3 > v2 > v1；旧档已归档副本，原件仍在 |
| 8 | 旧路径 | 49 份文档引用 `rt_5090_project`；命令类在副本中改路径，历史路径保留 |

### 10.2 技术坑

| # | 坑 | 正确处理 |
|---|---|---|
| 9 | **t0=4 fast path ≠ U-mode** | 受控 lab 只做 state 0→1；自然 boot 只命中 t0=0/1/0x16；真机可达性未证（OQ-01） |
| 10 | **t0=17 不是 destroy** | 它释放新分配 s1，不是用户 s2；RM 无 t0=17 stub（Q-08/OBJ-08） |
| 11 | **dtor 偏移** | GB20X：stride `0x28`，dtor 在 `entry+8`；`+0x28` 是 GB10Y 旧内核。原文把 stride 当偏移（C-03） |
| 12 | **RELEASE 地址** | GB20X = `0x93005B26`（jalr `0x93005B60`）；`0x930060F2` 是 GB10Y/链表初始化（C-04） |
| 13 | **TYPECALC 基线** | `0xFFFFFFFFA300A000`，不是 `A300A020`；`addi a4,a4,-1390` 已验证（C-05） |
| 14 | **MCLK marker** | 本案失败是 `0x25728` completion wait 超时；`0x256c8` 才是 busy（C-06） |
| 15 | **B8 执行域** | B8 只能执行 RM 空间 `0x01xxxxxx`；内核 `0x9300xxxx` fetch fault；gadget `0x930035D2` 在内核空间，B8 不可达 |
| 16 | **非零写入** | 当前只有清零原语（a4=0）；没有“写非零”的原语；不要假设能造负数 |
| 17 | **直接调 05B26 不是 U-mode 可达** | 它是诊断路径；U-mode 净 -1 destroy 路径未证明 |
| 18 | **lab 地址不是真机地址** | `0x800000000803a000` 只属 QEMU profile；真机必须用真机布局 |
| 19 | **`rv64_emu.py` 不是 QEMU** | E4 旧 Python 模拟器，按 `AGENTS.md` 仅作历史参考；不能与 E3 混用 |
| 20 | **FSP DoS 因果** | 现象是“畸形序列后 runtime 服务持续不可用”；最小触发未知；不要写“单条 ROMREAD 即永久 DoS” |
| 21 | **TOCTOU 三个对象** | FMC 无窗口；GSP ELF 读到 ≠ 执行；GSP FMC 写到内存 ≠ 执行；禁止互套 |
| 22 | **版本串味** | 610.57 / 615.71 / 570.215 地址不可互套；所有 VA 带版本 |
| 23 | **C1/C2 “PROOF”** | 仅在旧 Python 模拟器 + 真实内核镜像上闭合（E4）；真机未验证 |
| 24 | **双 BIOS 同时失败** | 不等于两颗 flash 同时损坏；共享 GPU/FSP 状态可让两槽同时失败 |
| 25 | **Power cycle ≠ SBR** | SBR 清特定 reset domain，走另一条 FSP 初始化路径 |

### 10.3 工程/协作坑

| # | 坑 | 正确处理 |
|---|---|---|
| 26 | 193G 根目录、787 个顶层条目、230 份 md | 用 `gsp_libos_clean` 副本；先读 `AUTHORITATIVE_STATUS.md`/`STATUS.md`，不要全树 `find` |
| 27 | btrfs 每 10 分钟快照，删除文件不立即回空间 | 本项目不依赖快照删除；需要回收时单独处理，勿边写边删 |
| 28 | 两个 agent 互转导致“甩锅/任务转发” | 只转“已验证发现 + 文件路径 + 明确问题”；不要每轮转发整段总结 |
| 29 | 上下文接近 1M 后变短、变自信 | 到里程碑写 handoff，开新会话；不要硬撑 |
| 30 | 外部“总控任务书”被 agent 正确拒绝 | 只转对方原文；不要注入未授权的目标/验收格式 |

---

## 11. 未决问题与下一步

### 11.1 P0（阻断主线）

- **OQ-01**：t0=4 fast path 在真机 U-mode 是否可达（最优先重跑）。
- **OQ-04**：t0=2 的 walk 查找表在真机/内核堆的哪里。
- **OQ-05**：是否存在非零写入原语。
- **OQ-18**：QEMU 384B 启动区域表 —— **已达成 2026-10-18**（Q-11/Q-12/Q-13）；后续是 init 参数 blob + 日志窗口（NS-Q2）。

### 11.2 P1（决定结论能否成立）

- **OQ-06**：FSP runtime DoS 最小触发。
- **OQ-07**：K3-1 路径 C（泄漏 + 写回）。
- **OQ-08**：MCLK completion wait 的设备侧首因。
- **OQ-09**：C1/C2 真机触发（把 E4 抬到 E1）。
- **OQ-10**：GSP ELF TOCTOU 的“执行”验证。

### 11.3 P2/P3

- OQ-11：TOCTOU 时间线 4×2 矩阵。
- OQ-12：WPR2 槽位归属。
- OQ-13：`MCLK_MAX_CAPABILITY` 消费者。
- OQ-14：FSP runtime 恢复路径。
- OQ-16：615.71 → 610.57 重定位表。
- OQ-17：实验环境出处（E0/E1 逐条补全）。
- OQ-02R：旧模拟器 dtor `+0x28` 残留解释（P3）。
- OQ-15：更正落地与链接检查（P3）。

### 11.4 重跑顺序（按“必须重跑”）

| 顺序 | 实验 | 原因 |
|---:|---|---|
| 1 | t0=4 真机 U-mode A/B | 当前最重要的未证明假设 |
| 2 | 静态 RELEASE/TYPECALC 跨版本（610.57→615.71） | 地址是否可移植 |
| 3 | RM store gadget 穷尽扫描 | 决定是否有非零写 |
| 4 | t0=2 表定位 | 攻击链关键缺口 |
| 5 | K3-1 路径 C | 决定 K3-1 可利用性 |
| 6 | FSP DoS 最小触发 | 对外稿件因果 |
| 7 | ELF TOCTOU arm/disarm | 决定 TOCTOU 是否成立 |
| 8 | C1/C2 真机 | 把 E4 抬到 E1 |
| 9 | MCLK 两条 marker 分支 | 修正“mailbox busy” |
| 10 | QEMU 384B 启动表 | **已达成**（2026-10-18，Q-11/Q-12/Q-13）；下一步是 init 参数 blob + 日志窗口 |

### 11.5 暂不做（除非明确授权）

- 任何会写 VBIOS / InfoROM / OTP / 熔丝的步骤。
- 任何未经 arm/disarm 的 ELF 注入。
- 任何在“未确认卡已恢复”的状态下重跑 WPR2 相关实验。
- 把 t0=4、C1/C2、lab 地址直接写进对外材料。

---

## 12. 文档地图与维护规则

### 12.1 本目录

| 文件 | 作用 |
|---|---|
| `AUTHORITATIVE_STATUS.md` | **本文件**：唯一权威总览；覆盖 GSP/LibOS 研究 + 模拟器 + 工具/脚本 + 坑 |
| `STATUS.md` | 一页现状（短版） |
| `FINDINGS.md` | 77 条结论库，每条带 E 级别 / source / date / confidence |
| `OPEN_QUESTIONS.md` | 18 条未决问题 + 最小复现实验 |
| `NEXT_STEPS.md` | 真机 / QEMU / 静态三线优先级 |
| `CORRECTIONS.md` | 18 条旧文档更正（旧文档:行 → 更正 → 依据） |
| `README.md` | 资料库入口、结构、规则 |
| `COPY_MANIFEST.md` | 拷贝范围说明 |
| `docs/INDEX.md` | 230 份原始 `.md` 逐条登记 |
| `docs/DEDUP_PLAN.md` | 重复组、冲突点、混写审查、归档建议 |
| `docs/EVIDENCE.md` | E0–E6 定义与引用格式（唯一权威） |
| `docs/ARCHIVE_INDEX.md` | 被取代文档的原路径/副本/取代者/哈希 |
| `docs/archive/` | 54 份旧文档副本；原件仍在原位 |

### 12.2 维护规则

- 新结论 → `FINDINGS.md`，分配新 ID（区段前缀 + 序号），必须带 E 级别、`file:line`、日期、置信度。
- 未决 → `OPEN_QUESTIONS.md`，附最小复现实验（命令 + 预期输出 + 判据）。
- 发现旧文档错误 → 追加 `CORRECTIONS.md`，不编辑原文。
- 归档 = 复制，不是移动；在 `docs/ARCHIVE_INDEX.md` 登记哈希与取代者。
- 地址必须带版本；不新增“A 级/实锤/已证明”自评词。
- 本文件是总览；细节以 `FINDINGS.md` 的 ID 和原始 `file:line` 为准。

---

## 附录 A：77 条 FINDINGS 完整索引

> 完整表格见 `FINDINGS.md`。下表仅列 ID、claim 摘要、E 级别，确保本文件覆盖全部结论；引用时请回到 `FINDINGS.md` 查 source/date/confidence。

| ID | Claim（摘要） | E |
|---|---|---|
| Q-01 | 生产 FMC 包在宿主侧通过 SHA384 + ECDSA-P384 验证；错误信任锚在 CPU 启动前被拒绝。这是**宿主侧实现**的验证，不等于芯片熔断/BOOTROM 认证。 | E3 |
| Q-02 | 未修改的 610.57.04 生产 LibOS 在 QEMU 中从 boot 执行到 init：`pc=0xffffffff93001ec6`，下一处未建模输入为 `mcause=0xd/mtval=0x0c00000000000200`（384B 启动区域表）。 | E3 |
| Q-03 | `nvidia-gsp-lab` profile 执行到 `0xffffffff93007324`（`sd s7,0x450(s0)`）并发布 walk 表；`[global+0x450]=s7` 断言通过。 | E3 |
| Q-04 | walk 表地址 `0x800000000803a000` **只属本 profile**；真机探针必须使用真机布局的地址，不能照搬。 | E3 |
| Q-05 | 受控 `t0=4, stval=0` 注入进入 `0x930042f8`：只做 state 0→1、refcount 保持 1、不调 `0x93005b26`、不调 handler `0x930008cc`。 | E3 |
| Q-06 | 自然 boot 中 `0x930042f8` 的命中为 `t0=0/1/0x16`；**未观察到 t0=4 或 t0=23**。 | E3 |
| Q-07 | 第二次发布后 walk 表被填充有效项：`meta=[entry+16]` 的 bit63=1，回读 4096 字节、116 项、SHA256 稳定。 | E3 |
| Q-08 | `t0=17` 释放的是新分配对象 s1，不是用户传入的 a0/s2；它是 create/register，不是 destroy。 | E3 |
| Q-09 | QEMU 侧回归覆盖：42 项 C 正/负检查、5000 个有界畸形输入、17 项 S/U MPU、2 项页内冲突/跨界拒绝。 | E3 |
| Q-10 | 完整 FSP/FMC/LibOS/GSP-RM 启动链**尚未完成**；当前只到 LibOS init + walk 表检查点。 | E3 |
| Q-11 | 384B 启动区域表的生产者已实测：`(a5<<58)+a6+0x200` 回绕契约、16×24B、本 profile 4 个非空项（FB WPR heap / WPR meta / 整段 FB aperture / SYS）；`a5=3` 是回绕常量。 | E3 |
| Q-12 | init 消费者契约：8 aperture 校验后写 9×24B 记录到 `0xa3008e28`；`+8` 是滚动累加值，不是地址。 | E3 |
| Q-13 | 审计分支 `handoff=fixture` 通过区域表检查点 `0x93002052`；新停点 = handoff init 参数 blob（line 220）+ 日志窗口 `0xffffffff60000000`。 | E3 |
| Q-14 | `CSR 0x5c0` 是内核 trap scratch（仅 trap 入口/出口两处），`time (0xc01)` 需时间源；两者都是硬件输入。 | E2/E3 |
| GSP-01 | RPC 消息队列可溢出：声明 33 元素 → 泵全读 → metadata 溢出；`B8=0xDEADBEEF` 时 `sepc=0xdeadbeee`，为溢出确认铁证。 | E1 |
| GSP-02 | `B8`（metadata+0xB8）回调函数指针可劫持，在 S-mode 执行；`a1` 完全可控（MAP 0x10038→[s1+0xA0]）；`a0` 恒 0；支持 46 连发与 MAP 轮换。 | E1 |
| GSP-03 | B8 可执行域只有 RM 代码空间 `0x01xxxxxx–0x0F9B000`；内核 `0x9300xxxx`、staging/队列/对象目录均 fetch fault（NX）。 | E1 |
| GSP-04 | 读原语：`B8=0x01020A30`（`ld a5,0x168(a1); jalr a5`），数十次验证。 | E1 |
| GSP-05 | 写原语：`B8=0x01B52246`（`c.sw a4,0(a1)`），但回调路径上 `a4` 恒 0，等价于“清零原语”。 | E1 |
| GSP-06 | 非零写入原语经穷尽排除未找到：a4/a0/a5/s4 均 0；358 个 `sw a0` gadget 无一有相邻 `ld`。 | E1 |
| GSP-07 | 三明治 gadget `0x1E1E62E` 可触发 walk(2)：`sepc=0x1e1e648`。 | E1 |
| GSP-08 | `B8=ret0` 时零崩：`Xid120=0`，泵仍存活。 | E1 |
| GSP-09 | 关键指针跨 boot 稳定：`s1=0x0FE4790E10`、`sp=0x0FEB80FCD0`、`global handle=0x0303000000307c70`。 | E1 |
| GSP-10 | K3-1 staging 溢出**存在但无法精确利用**：溢出区含关键堆结构，任何写入都在回调前崩；crash 固定 `pc=0x1b8ffbc`、`stval=0x4fe6`。 | E1 |
| GSP-11 | K3-1 泄漏读成功：崩溃 PC 等于读出值，`*(0x04191678)=0x0FE4790E10`，与 metadata 指针精确匹配。 | E1 |
| GSP-12 | v25.3 两步法（先 33 个 → 等 50ms → 再发续传凭证）确认溢出并保持泵存活；v25.2 一次性发 65 个**无溢出**（泵改变路径）。 | E1 |
| GSP-13 | t0=2 的 walk 查找表位置**未知**，可能不在已扫描的堆区（扫 60+ 地址未见负数 meta）。 | E1 |
| OBJ-01 | TYPECALC(`0x93004568`)：`desc=[(obj&~0xFFF)+0x20]`；`type=低32位((diff>>3)×0xCCCCCCCD)`，diff 以 `0xffffffffa300a000` 为基线。 | E2/E4 |
| OBJ-02 | RELEASE(`0x93005b26`)：`slot=(0xffffffffa300a000 + type_u32×40 + 8) mod 2^64`；`dtor=[slot]`，非零则 `c.jalr dtor`（`@0x93005b60`，a0=obj，S-mode）。 | E2/E4 |
| OBJ-03 | GB10Y 旧内核使用 `RELEASE=0x930060f2` 且 dtor 在 `+0x28`；**不可用于 GB20X**。 | E4 |
| OBJ-04 | dtor 表静态为 BSS 0；运行时 type10 dtor 为 `0x93008130`，dtor 表基 `0xA300A000`、stride `0x28`、函数指针在 `entry+8`。 | E3 |
| OBJ-05 | 慢 handler 条件：`state=1/ref=0` → ref 0→1、不 dtor；`state=0/ref=0` → ref 0→1 后调 `0x93005b26` → ref 0 → dtor（priv=1，S-mode）。 | E3 |
| OBJ-06 | `t0=23`（CREATE）创建 type12 对象，`ref=1`、`state=0`；create 返回 a0=0，slot 在栈上不返回。 | E3 |
| OBJ-07 | syscall handler 表 `0xA3008280`，每项 8B、32 位 handler 指针；分发 `t0×8+表基 → lw → jalr`，不走 walk 表。共 34 个 handler（16、29 为空）。 | E2 |
| OBJ-08 | RM 实际使用带 stub 的 syscall：0,1,2,3,4(124 处),5,6,8,9,11,12,15,18,21,22,23,27,29,31；`t0=17` 无 stub → U-mode 不可达。 | E2 |
| OBJ-09 | 普通 U-mode `t0=4` fast path 在 state=0 时只置 state=1，不进入 slow handler，因此 `li t0,4; unimp` **不能**到达 dtor。 | E3 |
| FSP-01 | COT（860B）中 816B（95%）验证字段被忽略：hash384 全 0xFF、publicKey 任意值，只要固件未改仍能启动。 | E0 |
| FSP-02 | 但“hash 全 0xFF + 改固件 1 字节”会被 FSP 拒绝（`✗ FSP 拒绝`），说明固件本体仍被校验。 | E0 |
| FSP-03 | WPR 元数据层的签名验证是真实的；COT 层不是。两层必须分开表述。 | E0 |
| FSP-04 | COT（NVDM type 0x14）只在 FSP boot-phase dispatcher 有 handler；runtime dispatcher 静默丢弃，无响应、无错误、通道不受影响。 | E0 |
| FSP-05 | 47 个 PRC knob 地图及真实写路径已恢复；跨状态域现象存在，但 flash/InfoROM 存储机制未证明。 | E0/E6 |
| FSP-06 | MNOC port 0 协议完整闭合，并在“脏卡”上验证通过；旧 B7b 的“硬件级来源验证”结论错误。 | E0 |
| FSP-07 | 一段畸形 NVDM/传输序列后，FSP runtime 服务（PRC、FWUP、caps、InfoROM、clock boost）持续不可用，且跨完整断电；GSP 启动与计算仍正常。 | E0 |
| FSP-08 | 该不可用状态的**最小充分触发未知**：序列含多次操作，期间未恢复并复验 FSP 健康。 | E5 |
| FSP-09 | host software decrypt consumer 为 AES-256-GCM：32B caller key、12B IV、16B tag、空 AAD；目标 key/KDF/root 与明文未知。 | E4 |
| FSP-10 | EMEM 命令队列寄存器协议：`QUEUE_HEAD` 是 FSP 读区间起点且宿主可写，`QUEUE_TAIL` 为 dword 单位，单包驻留；PSEC 块 `0x840000-0x843fff` 同型。 | E2 |
| FSP-11 | GSP 侧 FSP 传输栈：EMEM 后端 `0x15015c8/0x14fb74c`、MNOC aperture `0x150a3b0`（base `0x8f1e00`、span `0x200`）、方法槽 `+0x158/+0x1c8/+0x1d0`。 | E2 |
| FSP-12 | FSP 黑盒异常清单共 32 项：永久损伤 7、系统级死锁 4、临时 DoS 6、信息泄露 3、设计缺陷 3、行为异常 9；因果归属须应用 C-09/C-19/C-20。 | E0 |
| FSP-13 | 消息层：PRC read/write 正常；NVLink mask 全 1 被接受且无范围校验（GB202 无 NVLink，无实际影响）。 | E0 |
| FSP-14 | 58 条有效 `FSP_RUN` 记录形成 6 个唯一 GB202 对象；普通 RTX 5090 零售 BIOS 高度复用。 | E4 |
| FSP-15 | FuseRework 需要 main binary 与 48/384/384B sidecars；`0x0f` 仅回 4-byte ACK，不是明文导出。 | E4 |
| FSP-16 | 公开 FieldDiag/MODS 580 没有目标 envelope、四件套或 bulk decrypt-to-host。 | E4 |
| FSP-17 | 公开论坛、归档和网盘搜索未找到可验证目标工件。 | E5 |
| FSP-18 | FSP 明文专项最终状态：Stopped without plaintext。 | E4/E5 |
| TOC-01 | FMC 方向：验证期写入 → `0xFFFF` 干净拒绝；加载期（10–45ms）写入 → FSP 锁死（`MBOX=badf4100`）；加载完成后写入 → 无效。**没有可用于 FMC 的漏检窗口。** | E0 |
| TOC-02 | GSP ELF（27MB）在 `sendAndRead` 返回后 100ms 仍被 FMC 读取：写 ELF 起始 4 字节即致 GSP 挂死。**读到 ≠ 执行。** | E0 |
| TOC-03 | GSP 方向 FMC `fw[0x10000]` 写入到达物理内存（`d564→0902`，clflush+mfence 后），且 GPU 仍工作。 | E0 |
| TOC-04 | 上述写入**未证明被执行**：FMC 在 GSP 启动前已进 I-Cache，`0x10000` 可能是死代码；作者自评 B 级。 | E0（负结果） |
| TOC-05 | FSP 对 sysmem 数据做“全阶段”校验：`sendAndRead` 返回 0x0 只代表验证通过，后台加载仍在继续。 | E0 |
| CLK-01 | MCLK 18000MHz（relation offset `3999000 kHz`，即 +3999）通过；硬件实测约 17982MHz（≈请求×1000/1001）。 | E0 |
| CLK-02 | MCLK 18001MHz（offset `4000000 kHz`，即 +4000）在显存测试开始前失败；PMU 在 `SEPC=0x205d1a2c` 断言停机，host 等 `CHANGE_SEQ_PMU` 后返回 `NV_ERR_TIMEOUT(0x65)`。 | E0 |
| CLK-03 | 本案失败 marker 是 **`0x25728` = completion wait 超时**；`0x256c8` 才对应 busy 失败。两者不可混称。 | E2 |
| CLK-04 | 已恢复的发送段未发现对 +4000/18001 的主动频率拒绝：频率按 32 位原样发送，metadata 恒 0；失败发生在等待 completion 预算耗尽后。 | E2 |
| CLK-05 | “为何没有正常 completion”的设备侧首因未定位；不能定性为 FSP 拦截、36Gbps 硬限制或显存训练失败。 | E2（负结果） |
| CLK-06 | `MCLK_MAX_CAPABILITY` 不能当作已找到的 18000MHz 硬上限；它只是可加载的源描述，是否参与限幅未闭合。 | E2 |
| CLK-07 | 显存锁频（`min=max=15000`）在不变 V/F 曲线与 +2000 offset 下，使 CP2077 PT 平均 FPS 下降 16.43%、GPU 时钟降 118.1MHz。 | E0 |
| CLK-08 | 有限的显存时钟上限会静默约束 XBAR/SYS：路径追踪下板功耗降约 146W 而性能降约 15.5%；FurMark 下报告核心频率上升但渲染吞吐降约 32%。 | E0 |
| CLK-09 | 800W 板功耗上限下，RT 负载实际只获得约 500W 有效预算，控制器允许约 2955MHz。 | E0 |
| CLK-10 | XBAR 是独立物理时钟域：有独立 PMU 对象、时钟源、V/F 点、硬件测频与运行时控制；改变它改变实测时钟与渲染吞吐。 | E0+E2 |
| CLK-11 | 生产 610.57.04 驱动 + 原厂 GSP（不用 MODS）可同时保持 GPC 频率与 NVVDD。 | E0 |
| CLK-12 | `CLK_VF_POINTS`：INFO `0x20809021`/`0x8208`B；STATUS `0x20809022`/`0x98208`B。 | E0 |
| HW-01 | 逻辑 Fan0/controller0 驱动物理风扇 1 与 3；Fan1/controller1 驱动 2 与 4（30% vs 100% 实测）。 | E0 |
| HW-02 | Lightning 800W VBIOS 只声明一个 `FAN_COOLERS` 活动槽（`00 ff ff ff`），导致 fan1/PWM11/GPIO3 运行时对象缺失。 | E0 |
| HW-03 | 目前**不能**安全写出把 L2 96→128MiB 的工具；已排除 `fbp_l2slice_enable` 等两条直接路径。 | E2 |
| HW-04 | sm_120 SASS 的缓存控制与特殊寄存器访问已单独整理（不含普通算术 ISA）。 | E2 |
| REC-01 | 卡已完全可用（宿主直跑）：`nvidia-smi` 正常、CUDA 可用、32GB 显存；恢复机制是 WPR2-bypass 补丁模块（一行改动）。 | E0 |
| REC-02 | WPR2 事故触发序列：卸载驱动 → COT 基线 → size fuzz（全部静默消费）→ version fuzz（PRC handler 死亡、MT=0 不响应）。 | E0 |
| REC-03 | Power Cycle ≠ SBR：SBR 清除特定 reset domain 并让 FSP 走另一条初始化路径；断电不一定达到同样效果。 | E0 |
| REC-04 | “一次操作后两个 BIOS 槽都无法启动”**不是**两颗 SPI flash 同时永久损坏：共享 GPU/FSP 状态可让两槽同时表现失败。 | E5 |
| REC-05 | 原版槽最后一个无争议健康点是 2026-09-28T12:32Z；后续失败不能唯一归因于单槽或单次 COT 请求。 | E5 |
| SUB-01 | 两封 NVIDIA PSIRT 邮件已于 2026-10-13 通过已登录 Gmail 发出（显示 `Message sent`），附源文件与 SHA-256。 | E5 |
| SUB-02 | 投稿稿 1 明确**不**主张“单条合法 ROMREAD 即永久禁用 FSP”，只报告“畸形序列后 runtime 服务持续不可用”。 | E5 |
