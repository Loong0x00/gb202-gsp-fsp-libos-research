# DS 会话恢复 — K3-1 完整上下文与战略收敛（2026-09-29 晚）

本文档从 DS(deepseek) 主会话原始记录中恢复 HANDOFF_K31.md 未保留的增量信息。
战略重点（本次确认）：**① 搞到 FSP 代码（解密后）；② 或在 FSP 上瞎猫碰死耗子找到漏洞**。

---

## 0. 原始会话位置（可回溯）

```
主会话(35MB, 2556行): /home/user/.pi/agent/sessions/--home-user--/
  2026-09-24T23-29-33-185Z_01a0d5c0-bc00-72e5-8e94-42e50d5963af.jsonl
  模型: deepseek-flash(2139) + deepseek-reasoner(452) + kimi-k3(264)
  时段: 09-24 23:30 → 09-26 18:16 (本地), 覆盖全部 DS_*/K3_* 文件产出期
副会话(FSP路线): 2026-09-26T10-17-18-077Z_01a0dd38-*.jsonl (1.6MB, deepseek-flash)
```

提取方法：python 逐行解析 jsonl，`message.content[].text` 按 line 号引用（下文 L# 即该会话行号）。
K3 = Kimi-K3 静态分析子 agent 代号；DS_ 前缀文件 = DeepSeek 子 agent 产物。

关键行号索引：L911(方向判定) L1230/1255(K17/19裸崩实测) L1346(K3布局发现)
L1350(枪A命中) L1354(K256/33) L1370-1378(msgqMetadata结构) L1468-1494(canary写+leak读实测)
L1537-1596(任意读写总结+floorsweep判定) L1875(192KB上限+FSP不可达) L1889(缺陷总账) L1981(战役总结)

---

## 1. 状态修正：K3-1 实际进度比 HANDOFF 记载的更远

HANDOFF 说"IP 控制确认"。**实际 9月26日凌晨在 VM 里已实测打通任意读 + 任意写**：

### 任意写（L1468/L1478, 09-26 08:28-08:42 本地）
```
gadget: 0x1b52246  c.sw a4,0(a1); li a0,0; ret   (经 rxrefresh: a1=*(meta+0x38), a4=*(meta+0xc0))
目标:   栈金丝雀全局 0x418ff68, 值 0xDEAD0041
结果:   sepc=0x1aa3410, scause=0x8(ECALL主动陷阱), stval=0
        PC Trace: 0x1aa3410 ← 0x1a925e8 ← 0x10161fe ← 0x1004c8a ← 0x1b5224a(gadget ret) ← 0x1004c9c
判定:   store 执行 + 干净返回 + canary 校验失败踩陷阱 = 写落地可观测 ✓
```
⇒ K3_IP_CONTROL_NEXT_20260926.md 里的枪 E4-canary 实际已 fired 且成功。

### 任意读（L1492/L1494, 09-26 08:52-08:54 本地）
```
gadget: 0x1020a30  ld a5,0x168(a1); c.mv a0,s3; c.jalr a5   (6104 个 ld+jalr 候选中选的)
用法:   meta+0x38 = 目标地址 - 0x168 → 读出 8 字节并跳过去 → 取指失败 → stval = 读到的值
实测:   读 0x41904E0 → stval=0x08200000 = W (BAR0/PRI 窗口在 GSP 地址空间的基址)
        证据: 固件自身 3 万余处以 W+0x11152c (NV_FALCON2_GSP_BASE+RV_IRQDEST) 访问中断路由
```
⇒ 这是 HANDOFF 未收录的第二把实测武器（读原语）。**0x41904E0 是静态对象 0x41904D0 的 +0x10 字段**（DS_GSP_OBJECT_ACCESS 纠正：不是 pGpu）。

### 其余实测结论（L1537 汇总）
- 堆区不可执行（指向自己的字节 = 指令取指故障）⇒ 必须走 gadget 路线（E1 枪结论提前有了）
- fuse 寄存器 GSP 侧正确地址 = **W + 0x8200d0 = 0x08A200D0**（之前 0x082000D0 是 PMC 块，读出毒值是因为特权过滤而非地址错）

---

## 2. 0x1b8ffbc 完整模型（裸机破局的钥匙）

### 事实链（全部实测/静态互证）
1. **VM 里 K=17/19 也崩 0x1b8ffbc**（L1230/L1255, guest_full_dmesg_K17ck1_*.txt）：
   `stval=0x4fe6 (=NULL+0x4fe6), a0=0, a5=0x5000, s3=0x10000(queueElementSizeMax),
    s2=0x418ff68, s4=0x41d4170, PC Trace 含 0x101dd4c/dd50/dd64`。内容无关（全零/0xDD标签/混合崩得一模一样）。
2. K=16 + ck=1 存活 ⇒ 校验通过，K=17 与 K=16 唯一差别 = 多拷 1 元素（4KB 越界）。
3. K3 静态结论（L1346）：NULL 来源 = **"有效通道集合变空"（0x101dc08 掩码机制）**；
   旧假设（注册表计数被改写）被双重否定（表体在 ≥0x44400 字节堆对象 +0x443f0，K≥101 才够得着）。
4. 两条路径模型：
```
K=17..32: msgqMetadata 完好 → 消息正常分发 → 越界数据打坏"有效通道集合"
          → 服务循环查找返回 NULL → lbu a5,-0x1a(a0+0x5000), a0=NULL → 0x1b8ffbc
K=33:     元素32 覆盖 meta → ck 失败重试 → rxrefresh 走伪造 meta
          → rxLinked(+0xa4)=1 → jalr [+0xb8] → 回调路径（可控）
```
5. **裸机 K=33 崩 0x1b8ffbc 的解释**：回调路径未触发 ⇒ 大概率裸机堆布局漂移，
   元素 32 落点不是 msgqMetadata（P+0x20000 处是别的东西），越界先把"有效通道集合"打空。

### 修复方向（比"堆风水碰运气"具体）
- 反汇编现成：`parallel/k3_device_work/ev_crashfn_head_0x1b8feec.asm`（0x1b8ffbc 所在函数）
  + 0x101dc08 掩码机制 → 钉死"有效通道集合"结构体身份/偏移/内容 → **载荷里保真它**（不写坏）
- 裸机已知安全点：nelem=18 不崩（K31_FINAL_REPORT）⇒ 结构大致在 P+0x12000 之后
- 9月29 裸机矩阵的非单调性（17崩/18活/19崩）⇒ count 值本身可能被派生消费，值得对 0x1b8feec 函数核对

---

## 3. 能力边界（已实验划定，别再撞）

| 路径 | 结果 | 证据 |
|------|------|------|
| 宿主直写 BAR0 floorsweep | ✗ | 校验和全程不变 |
| GSP RM 官方 API 写 | ✗ | 接受但丢弃 |
| **K3-1 任意写 → W+0x8200d0** | ✗ | L1594: 写后裸读 0x8200d0=0xfffffb8f 原值 |
| task2 开 PLM + 宿主写 | ✗ | 结构性不可能（task2 扣 WPR2，复位又清 task2）|
| RM registry 换 devinit 执行者 | floorsweep 不变 | L1889: RmDevinitBySecureBoot=0+PMU=1 能跑但掩码分毫不动 |

- `0xBADFFFFE` = **Falcon 特权访问错误码**（硬件按引擎身份过滤，不是地址不存在）
- **结论：floorsweep/L2 解锁走 GSP 是死路（硬件门），K3-1 的价值 = GSP 身份 → FSP**。
  这就是 HANDOFF 目标收敛为"dump FSP 代码"的原因，现在补上了因果。

---

## 4. 战略：两条主线（本次确认）

### 主线 A：搞到 FSP 代码（确定性高，链路各环节都有实证）
```
K3-1 任意写(已实测)
  → Shot 0: 翻 RmFspUseMnoc (GSP侧 ctx+0x1df, 一个字节)
  → GSP 的 FSP 流量自动走 MNOC port 0 (GSP 车道)
  → FSP 信任 GSP 端口消息 (宿主注入被无视, GSP 身份被信任 — DS_FSP_MNOC_ACCESS)
  → 探测 GSP-only 服务 (NVDM 0x21 FSP_GSP_COMM 等, 0x21+ 服务集)
  → 找"读 FSP 内部 EMEM/SRAM"的命令 (ROMREAD 原语已知存在于通道地图)
  → dump 解密后 FSP 代码 → 静态分析
```
支撑资产：
- MNOC 信箱配方全闭合（DS_FSP_MNOC_ACCESS）：基址常量 0x8f1e00，端口步长 0x0c，
  host 侧 port 1 armed（port 2/3 从未 armed，RECV_INFO=0x04000000 是指纹）
- EMEM 通道配方全闭合（会话 L1545）：EMEMC(0)=0x8f2ac0 / EMEMD(0)=0x8f2ac4 写自增，
  QUEUE_HEAD/TAIL=0x8f2c00 系，RM channel 0，容量 1KB，写 HEAD 才是投递动作
- FSP 密文信封已导出 3 份（parallel/k3_device_work/fsp/，熵 7.999，descriptor flags bit2=ENCRYPTED）
- 假对象树 + tdispmgr trampoline 设计（GSP_EXEC_RUNBOOK，待钉 mctpSubmit 解引用链）

### 主线 B：瞎猫碰死耗子找 FSP 漏洞（便宜，可并行）

#### B-已扫完的区域（全部阴性或仅 DoS，别重复扫）
来源：FSP_MSG_LAYER_AUDIT / FSP_ULTIMATE_FINDINGS / B4_B5_B7_RESULTS（9月28-29 实测矩阵）

| 向量 | 结果 | 备注 |
|------|------|------|
| PRC knob 溢出 | ✗ 47 个全设防 | prc_rw/prc_fuzz 工具在 |
| NVDM 消息 fuzzing | ✗ 仅临时 DoS | 0x20 空 payload/0x21 任意/0x17 InfoROM → 通道卡死 ~10s 自愈 |
| MCTP 重组攻击 | ✗ 仅临时 DoS | 双 SOM/SEQ 跳跃卡死；2KB/16KB 洪水有界限保护不溢出 |
| EMEM 越界写 | ✗ 主动毒化 dead5ed0 | FSP 用后即毒，写越界即刻恢复 |
| COT runtime 注入 | ✗ 0xD7 拒绝 | FSP 有 boot/runtime 状态机（B4 全地址扫描实测）|
| MNOC port0 宿主注入 | ✗ 接受写入但不响应 | CREDIT 消耗了（硬件收了），FSP 不处理宿主消息 ⇒ 需真 GSP 身份或 boot 相 |
| SMBPBI(0x18) | ✓ 自锁死 bug | 已知健壮性缺陷，可复现 |
| SEC2 EMEM 通道 | 死 | QH 永不动；但 MAILBOX0=0xe99b3000 是真实值待查 |
| CC 模式六层 | 第 6 层硬件锁死 | 软件/协议/固件层全绕过，硬件层拒绝 |
| 信任链元数据 | COT 95% 字段装饰品；WPR 签名只盖地址字段，7 个可改字段全是死代码 | 架构缺陷存档 |

#### B-★ 已识别但从未执行的高价值实验（LOGICAL_INCONSISTENCIES_DEEP_ANALYSIS 9月29 05:19）
这份分析发现了跨研究线矛盾，组合起来就是漏洞 — **当天下午被 TOCTOU/K3-1 裸机测试挤掉，至今未做**：

1. **Limbo COT Oracle（标价最高）**：CC-mode 热重载制造 limbo → 发 COT(gspFmcSysmemOffset=任意物理地址)
   → 错误码随地址变化（已证明：limbo 中 0xDEAD0000→0xffff7044, 0x944480000→0x62340000）
   ⇒ **FSP 视角读 oracle**。指向 FSP 内部 SRAM ⇒ 直接读 FSP 代码！
   工具全在（热重载 + COT 构造器 + dma_buf.ko）。
   ⚠ 风险：CC limbo 历史 brick 过一次（交叉分析标"不建议"）— 但那次是 knob 写入事故，oracle 法只需 limbo 状态本身
2. **GSP ELF TOCTOU 短延迟（0/25/50/75ms）**：UCODES_ANALYSIS 修正后确认 27MB ELF 加载窗口
   在 50-100ms 之间，100ms 已太晚（那次命中是 ucodes）。短延迟写 ELF 代码段从未测过。
   命中 ⇒ GSP 读到修改的 ELF = 完整代码执行（比 K3-1 更直接）
3. **Limbo 中的 MNOC port 0**：若 port0 处理器只在 boot 相活跃，limbo 态可能响应 ⇒ GSP 身份通信
4. **race_v3 写 0xF200 @400ms**：区分"处理已完成"与"写到死代码"（矛盾 #1 裁决，便宜）

另待办（B4_B5_B7 尾巴）：boot 期间 MNOC 嗅探（SBR+实时捕获 FSP↔GSP）、SEC2 MAILBOX0 分析。

#### B-密码学侧记（备用情报）
- FSP 固件 = AES 家族（CTR 一族：ENCRYPT/DECRYPT_IV_CTR_OVERFLOW 字符串）、密钥在 SEC2 keyslot
- **密文确定性 + 跨厂商字节一致**（FE/ASUS/旧版 36 样本完全相同，无 per-device key/nonce）
  ⇒ 全家族一把钥匙一个 IV ⇒ 任何一台设备泄漏 = 全家族裸（这是 FSP 侧漏洞的高价值理由）
- 签名（COT: SHA-384+ECDSA P-384）与加密分离；ucodes 55MB 容器**无签名验证**（TOCTOU 已证）

---

## 5. 下一步行动（按序）

### 主线 A（K3-1 → FSP dump）
1. **修 VM 交互**（前置，方法已验证）：start-vm.sh 的 `-serial file:` 改可交互后端
   （chardev socket + expect，或 `-serial mon:stdio`），账号 mods/mods-lab（user-data 明文）；
   再按 VFIO_SSH_HOST_ONLY_20260924 的三件套 .deb（openssh-server 8.9p1-3ubuntu0.10
   +sftp-server+libwrap0，ubuntu-22.04.5-mods-lab.iso 里有）离线装 sshd → 永久化。
   注意 9月24 的 SSH 装在 /tmp 一次性 overlay 里，机器 09-29 重启 5 次后已随 tmpfs 蒸发。
2. **VM 里复现 9月26 状态**：K=33 P1 → 任意读(0x1020a30) + 任意写(0x1b52246) 复测。
3. **Shot 0**：任意写翻 ctx+0x1df（需先从 0x1509338 init 回溯 ctx 运行时地址）。
4. **并行（零硬件）**：0x1b8feec 函数 + 0x101dc08 掩码机制静态分析（裸机破局钥匙，
   ev_crashfn_head_0x1b8feec.asm 现成）；mctpSubmit 解引用链（假对象树最后一环）。
5. Shot 0 成功后：GSP 车道扫 0x21+ 服务 → 找 FSP 内部读命令 → dump。

### 主线 B（FSP 漏洞瞎碰，实验全在设计好未执行状态）
6. **race_v3 写 0xF200 @400ms**（最便宜，裁决矛盾 #1，无新风险）
7. **GSP ELF TOCTOU 短延迟扫描 0/25/50/75ms**（命中 = 直接代码执行；注意与 ucodes 窗口区分判读）
8. **Limbo COT Oracle**（CC 热重载 + 任意地址 COT；⚠ 有 brick 史，先做 6/7 再碰这个）
9. **Limbo MNOC port 0**（与 8 同一状态，可同枪带测）
10. 尾巴：boot 期 MNOC 嗅探、SEC2 MAILBOX0=0xe99b3000、ucodes 1293 条目表审计

## 6. 本次恢复的教训

- 重要会话结论要**当场落盘**（DS 会话 9月26 的实测结论只活在 jsonl 里，HANDOFF 漏记了任意读写）
- `/tmp` = tmpfs，重启即清：一次性 VM/密钥/报告不要放 /tmp（9月24 SSH 之失）
- 文档间的矛盾要标注裁决（ELF_TOCTOU_BREAKTHROUGH 14:10 vs UCODES_ANALYSIS 14:34 修正，
  TOCTOU_FINAL_REPORT 凌晨已判死 FMC/ELF 轴 —— 以最后写的 UCODES_ANALYSIS 为准：只有 ucodes 轴活着）
