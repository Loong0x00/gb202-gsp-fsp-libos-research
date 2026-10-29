# K3 设备侧:staging 64KB 的分配者、堆邻接布局与瞄准型载荷设计(2026-09-26)

纯静态、离线、只读。承接 `K3_DEVICE_RX_CHECKSUM_20260926.md`(下称"上份报告")。
对象:`/home/user/rt_5090_project/power_governor_reverse/gsp61057_rx_full.bin`(RV64GC,基址 0x1000000,**VA = 文件偏移 + 0x1000000**)。
宿主侧交叉参照:`driver_gpio_internal_610.43.03/src/nvidia/{src,inc}/libraries/msgq/msgq.{c,h}`、`inc/libraries/msgq/msgq_priv.h`、`src/nvidia/src/kernel/gpu/gsp/message_queue_cpu.c`。

置信度:A=指令级直接证据且多源交叉一致;B=结构级;C=推断。

## 0 方法与新增工具

新增脚本(均在 `/home/user/rt_5090_project/parallel/k3_device_work/`):
- `auipc_resolve.py`:线性常量传播,解析函数内全部 `auipc+addi` 地址、`ld/st` 目标与 `auipc+jalr` 调用目标(已修正负立即数符号扩展 bug,并用 3 个已知地址——canary 0x418ff68、MQI 0x41914d0、init 调用目标 0x1a98924——回归验证)。
- `scan_indirect.py`:扫描 `ld rd, off(rs)` 后跟 `jalr rd` 的间接调用(off 可指定)。
- 新证据文件:`ev_init_0x1a98924.asm`(全函数 0x1700 字节)、`ev_alloc_wrapper_0x18c3c54.asm`、`ev_alloc_core_0x18c3704.asm`、`ev_msgq_rxrefresh_0x1004c6c.asm`、`ev_msgq_markconsumed_0x1004cdc.asm`、`ev_recv_mainline_0x1016232.asm`、`ev_lookup_mask_0x101dc08.asm`、`ev_crashfn_lookup_site.asm`、`init_resolved.txt`。

复核命令:
```bash
cd /home/user/rt_5090_project/parallel/k3_device_work
python3 auipc_resolve.py 0x1a98924 0x1700        # init 全函数地址解析
python3 -c "from rvlib import *; print(dump(0x1a9901e, 0x60))"   # staging 分配点
```

---

## Q1 【最重要】staging 是谁分配的、正后方是什么 —— A 级,已完全钉死

### 1.1 分配点:init 0x1a98924 内,**一次性分配 2*sizeMax+0xe8 = 0x200e8 字节**

证据(`ev_init_0x1a98924.asm` + `init_resolved.txt`):

```asm
; s5 = 0x4191620 = MQI(0x41914d0)+0x150 = 队列信息结构(auipc 0x26f8/+0x6d2 @0x1a98f4e-52)
0x01a98ff0  slliw a1, a1, 1        ; a1 = sizeMax(0x10000, 来自布局描述符 s1+0x1b0) * 2
0x01a98ff8  addiw a1, a1, 0xe8     ; a1 = 2*sizeMax + 0xe8 = 0x200e8  ★分配尺寸
0x01a99002  slli/srli a2           ; a2 = zeroext(0x200e8)
0x01a9900e  c.mv  a0, a2
0x01a99012  sd    a2, -0x200(s0)
0x01a9901e  auipc ra, 0xffe2b
0x01a99022  jalr  ra, ra, -0x3ca   ; -> 0x18c3c54 = 分配器包装(见 1.3)
0x01a9902a  c.mv  s4, a0           ; s4 = P = 分配结果(为 NULL 则跳错误路径 0x1b00)
0x01a99026  ld    a2, -0x200(s0)   ; a2 = 0x200e8
0x01a99032  c.li  a1, 0
0x01a99038  jalr  -> 0x1be41ec     ; memset(P, 0, 0x200e8)
```

### 1.2 块内布局(同一分配,三块)——A 级

```asm
0x01a9903c  ld   a5, 0x30(s5)      ; a5 = sizeMax = 0x10000
0x01a99046  slli s3, a5, 1
0x01a9904a  c.add s3, s4           ; s3 = P + 0x20000
0x01a9904c  c.add a5, s4           ; a5 = P + 0x10000
0x01a9904e  sd   s4, 0x40(s5)      ; MQI+0x190 = P            (RX staging)
0x01a99052  sd   s4, 0x48(s5)      ; MQI+0x198 = P            (RX staging, recv 0x101612e 读的就是它)
0x01a99056  sd   a5, 0x50(s5)      ; MQI+0x1a0 = P + 0x10000  (TX staging)
0x01a9905a  sd   s3, 0x70(s5)      ; MQI+0x1c0 = P + 0x20000
0x01a99066  a2=0xe8; a1=0; a0=s3
0x01a99072  jalr -> 0x1be41ec      ; memset(P+0x20000, 0, 0xe8)
0x01a99080/90  auipc+addi a5       ; 0x100cf9c / 0x1004c5c
0x01a9908c  sd   a5, 0xe0(s3)      ; meta+0xe0 = 0x1004c5c (fence 函数)
0x01a99098  sd   a5, 0xb8(s3)      ; meta+0xb8 = 0x100cf9c (每元素拷贝助手!)
0x01a9909c  sd   s3, 0x58(s5)      ; MQI+0x1a8 (hQueue) = P + 0x20000
0x01a990a0  sd   s5, 0xc0(s3)      ; meta+0xc0 = 0x4191620 (backendRwArg)
```

即:

| 偏移(相对 P) | 尺寸 | 身份 | 证据 |
|---|---|---|---|
| +0x00000 | 0x10000 | **RX staging**(recv 拷贝目的地) | MQI+0x190/+0x198;recv 0x101612e |
| +0x10000 | 0x10000 | **TX staging** ← **K=17 越界窗口命中的就是它** | MQI+0x1a0;TX 函数 0x1016790 @0x10167c6 `ld s2, 0x1a0(s10)` 并读其 +0x18 长度做 ≤sizeMax 检查 |
| +0x20000 | 0xe8 | **msgqMetadata(= hQueue, MQI+0x1a8)** | memset 0xe8;+0xb8/+0xe0 函数指针;+0xc0 回指 |

**结论:staging 正后方的 4KB 是 TX staging 的开头——一个纯数据工作缓冲区,其中没有任何在崩溃前会被当作指针解引用的字段。** 这直接解释了三次实验的内容无关性(0xDD 与全零同址同陷阱):该窗口的字节根本不参与指针解引用。

### 1.3 msgqMetadata 字段逐一对上宿主 msgq 库(A 级,交叉验证)

宿主 `msgq_priv.h` 的 `msgqMetadata`(64 位指针)与设备侧用法逐字段吻合:

| off | 宿主字段 | 设备侧证据 |
|---|---|---|
| +0x28 | pTheirEntries | recv 0x1016170 `ld a1, 0x28(s1)`(RX 元素源基址) |
| +0x30 | pReadIncoming | 0x1b597c0 `ld a0, 0x30(s8)`(作 fcnInvalidate 参数) |
| +0x38 | pWriteIncoming | 0x1004c8e `ld a1, 0x38(a0)` |
| +0x40 | pReadOutgoing | MarkConsumed 0x1004d12 `ld a0, 0x40(s1)`(写 readPtr 的目的地) |
| +0x5c | tx.msgCount | 0x1b597ba `lw s3, 0x5c(s8)` |
| +0x78 | txLinked | 0x1b59856 `lbu a4, 0x78(s8)`;init 0x1a99088 读 |
| +0x84 | rx.msgSize=0x1000 | recv 0x101616c `lw a5, 0x84(s1)`(乘算元素尺寸) |
| +0x88 | rx.msgCount=64 | recv 0x101615e `lw a3, 0x88(s1)`(环形回绕模数) |
| +0x8c | rx.writePtr | 0x1004ca2 `lw a5, 0x8c(s1)` |
| +0x9c | rxReadPtr | recv 0x101615a;MarkConsumed 0x1004cfc 读+0x1004d08 写 |
| +0xa0 | rxAvail | recv 0x1016152 `lw a5, 0xa0(s1)`(可拷元素数上界!) |
| +0xa4 | rxLinked | recv 0x101614c;0x1004c78;0x1004cea(必须非零才工作) |
| +0xa5 | rxSwapped | MarkConsumed 0x1004d14 `lbu a3, 0xa5(s1)` → snez<<8 \|1 |
| +0xb8 | **fcnBackendRw = 0x100cf9c(拷贝助手)** | init 写入;0x1004c8c / 0x1004d10 `ld a5,0xb8; jalr a5` ★间接调用 |
| +0xc0 | fcnBackendRwArg = 0x4191620 | init 0x1a990a0;拷贝助手 a4 实参(recv 0x1016182 处 a4=0x4191620 ✓) |
| +0xc8 | fcnInvalidate | 0x1b597b6 `ld a4, 0xc8(s8); jalr a4`(a0=+0x30, a1=4) |
| +0xd0 | fcnFlush | MarkConsumed 0x1004d3a `ld a4, 0xd0(s1)` |
| +0xe0 | fcnBarrier = 0x1004c5c | init 写入;0x1004c5c 函数体 = `fence; ret` ✓ |

`sizeof(msgqMetadata) = 0xe8` = 宿主 `msgqGetMetaSize()` ✓。宿主 `message_queue_cpu.c:152` 的 `queueElementSizeMax + msgqGetMetaSize()` 与设备侧 `2*sizeMax + 0xe8`(RX+TX 两块工作区 + 元数据)同一算法。

### 1.4 分配器与堆(B 级)

- 分配调用 → 包装 0x18c3c54:`a0 = heapDesc = 0x4190db0`(BSS,MQI 附近),尾跳核心 **0x18c3704(heapDesc, size)**(`ev_alloc_wrapper_0x18c3c54.asm`)。
- 核心 0x18c3704:size 8 字节对齐后 `a1 = size+0x10`,经 `*(heapDesc)` 虚表取原始块,块头 0x10 字节(+0=对齐后尺寸,+8=分配计数 id),**返回 原始块+0x10**(`ev_alloc_core_0x18c3704.asm` 0x18c3970 `addi a0, s6, 0x10`)。即 P 前 0x10 字节是本块堆头(越界写方向向前,打不到)。
- 堆池本体位置不在镜像内(heapDesc 是 BSS,运行时初始化),**静态无法钉 P 的具体 VA**;崩溃寄存器中也没有堆地址(见 Q2)。
- 分配顺序(task3 init 内):① 页表类分配(@0x1a98e4c,存 s2+0x1d8)→ ② **staging 块 0x200e8**(@0x1a99022)→ ③ **MQI+0x1e8 对象**(@0x1a9924e,尺寸 = 运行时全局 *(0x41C4000),静态无命中;对象 +8 被写入 heapDesc 指针,疑似 RPC 侧分配器/内存池对象,C 级)。拆除路径 0x1a9a908-0x1a9a96c 按 ③→② 的顺序 free(③ @0x1a9a926 → 0x18c7d74;② @0x1a9a948),并清零 MQI+0x190/+0x198/+0x1a8 等——与分配顺序互证。
- 推论:若堆为简单序进分配,**紧邻 staging 块之后的是 ③ MQI+0x1e8 对象**(而非任何注册表)。③ 的身份/尺寸未钉死(C 级)。

---

## Q2 数值可行性核查:旧假设"溢出清零表计数"被**双重否定** —— A 级

### 2.1 崩溃现场寄存器的地址性质重判(修正上份报告的暗示)

- `s2=0x418ff68` = **栈金丝雀全局**,不是堆对象:lookup 0x101dcb4 自己就用它(0x101dcc0 `auipc s2,0x3172` + `addi 0x2a8` → 0x418ff68,`ld a5,0(s2)` 取 canary);init、崩溃函数 0x1b8feec(0x1b8ff0a auipc 0x2600 + 0x5e → 0x418ff68)同。A 级。
- `s4=0x41d4170` = **BSS 簿记簇指针**:init 在 0x1a98a04-0x1a98a36 向 0x41d40b8/0xc0/0xc8/0xd0/0xd8 写队列布局信息,崩溃函数在 0x1b8ff3e 附近计算的 s4(0x41d4570)也在该簇;均 BSS。A 级(簇性质)/ B(具体语义)。
- MQI=0x41914d0、队列信息结构=**0x4191620**(注意:上份报告写"0x4181620"是笔误,正确为 0x4191620 = MQI+0x150;`init_resolved.txt` 0x1a98f52)、注册表全局=0x41d3f38、分配器所见另一注册表全局=0x41b3f38(0x18c374c auipc 0x2910 + ld 0x7ec)——**全部位于 0x418xxxx-0x41dxxxx BSS 区**。
- 注册表表体 = `*(*(0x41D3F38)+0x1a8)`,是堆分配对象,**其 VA 静态不可知**;崩溃寄存器中没有任何落在堆区的值可用来定位它(s10=0x6f7c000、s11=0xfeb57c000 在 RPC 循环上下文,疑似共享队列/栈相关 VA,C 级,与表无关)。

### 2.2 结构性不可能证明(A 级)

表对象关键字段全部在其**尾部**:分配位掩码 `表+0xf95c`(0x101dc08: `lui a5,1; add a5,t0; lw t1,-0x6a4(a5)` → t0+0xf95c)、条目 `表+0x441f0`(32 项 × 0x10,{对象指针, u32 键})、计数 `表+0x443f0`。表 ≥ 0x44400 字节(≈278KB)。staging 块总共 0x200f8 字节,越界只能**向前**写。

设表基址为 T:
- 若 T+0x44400 ≤ P(表整个在 staging 之前):计数 T+0x443f0 < P,**越界写永远打不到**(方向向前)。
- 若 T ≥ P+0x200f8(表在 staging 之后,且两活块不重叠):计数 ≥ P+0x200f8+0x443f0 = **P+0x644e8**,需要 K ≥ ⌈0x644f0/0x1000⌉ = **101** 个元素;掩码 T+0xf95c ≥ P+0x2fa54,需要 **K ≥ 48**;条目需 K ≥ 101。
- 任何使计数/条目落在 [P, P+0x200f8) 内的 T 都意味着两个活堆块重叠,不可能。

而实验只用 K=17/19(覆盖 ≤ P+0x13000)就崩了。**∴ K=17/19 的崩溃不可能由打中表计数/条目/掩码引起。**

### 2.3 实验侧证伪(A 级逻辑)

若溢出改写的是计数 `表+0x443f0`:填 0xDD 时计数 = 0xDDDDDDDD,lookup 的条目扫描上界 = 表+0x441f0 + 0xDDDDDDDD×0x10,循环会读越界数 GB → 必然产生与全零填充**不同**的崩溃(stval ≠ 0x4fe6 的野生读)。实测 0xDD 与全零**完全同址同陷阱** ⇒ 被改写的不是计数(也不是任何会被 lookup 读作长度的字段)。

### 2.4 替代解释(按优先级)

崩溃链上 lookup 返回 NULL 的**全部**条件(0x101dc08 + 0x101dcb4,A 级):有效通道掩码 = (表+0xf95c 分配掩码) ∩ (有登记条目的位) == 0,或首个命中条目的对象指针为 NULL。**不需要表被破坏,只需要"已注册通道集合变空"。** 据此:

- **H1(B):消息不可消费 → 错误升级 → 通道被拆除。** 已证(A 级):K≥17 的消息永远不可能被正常消费——checksum 失败 → 重试3次 → 返回 0x25;就算宿主重算 checksum 使其通过,`msgLen = 16+length > sizeMax=0x10000` 在 0x10162b8 必然失败(返回 0x3a)。两条路都到不了正常消费点(0x10162c4 的 MarkConsumed)。泵/RPC 侧对持续接收失败的升级处理(RPC 循环内自带拆除段 0x1b90306-0x1b90354:free staging、清零 MQI;配套 0x1a9a8xx)若注销了唯一通道 → 掩码变空 → 下一轮循环顶 lookup 返回 NULL → 0x1b8ffbc。内容无关 ✓、K=17 足够 ✓。
- **H2(B-):TX staging 里有一条在途/待回复文。** K=17 恰好砸烂 TX staging 第 0 页;若回复据此发出畸形内容(或 TX 失败),宿主以关闭通道回应 → 同样掩码变空。K=19"死得更早、PC Trace 变 15 条"与"砸烂的回复页更多"相容。
- **H3(C):泵任务与 RPC 任务共享 TX staging 的竞态**;无更多静态证据。

H1/H2 都收敛于"通道状态改变使掩码变空",而非"表被溢出改写"。区分方法见 Q3 判读标准与 Q4。

---

## Q3 瞄准型载荷规格(可直接执行)

核心新事实:K=33 时第 33 个元素(元素索引 32)的目的地 = **P+0x20000 = msgqMetadata 本体**(同一块分配内,无任何堆布局假设,必然命中)。其中 **meta+0xb8 = fcnBackendRw** 会被 msgq 层以 `ld a5,0xb8(handle); jalr a5` 间接调用(0x1004c9c 与 0x1004d30 两处,A 级)。把 +0xb8 换成标记值 ⇒ **我们的字节变成被执行的指针**。

触发路径(已走通指令级推演,A 级):
1. recv 第一遍:以**未被破坏的** meta 拷完 33 个元素(元素 32 落地即完成破坏);checksum 失败(宿主无需重算)→ 0x101633c → 重试计数 s6=1 < 3;
2. 重试第 1 遍 0x1016144 起:s1 = MQI+0x1a8(指针本身在 MQI,未坏)→ `lbu +0xa4` 需非零 → `lw +0xa0`(rxAvail)== 0 → 判队列空 → 0x1016200 调 **0x1004c6c**(rxAvail 刷新)→ `lbu +0xa4` 非零 → **0x1004c8c `ld a5, 0xb8(a0)`;0x1004c9c `jalr a5`** → 取指 fault。
3. 前提:宿主在共享队列里**实际投递 ≥33 个元素**(recv 拷贝上界 = min(nElements, rxAvail))。宿主源码 commandQueueSize=0x40000 = **64 槽**(硅片配置,`message_queue_cpu.c:71/96`),K=33 可行 ✓;K=64 以内均可。

### 枪 A(主枪,无需重算 checksum)

- rpc->length = 33×4096−16 = **0x20FF0**(nElements=33);元素 0 头部同前几枪;checkSum 任意(让它失败);元素 1..31 全零;**元素 32(队列槽位 (head+32)%64)4KB 全零,仅两处例外**:

| 元素32内偏移 | 写入值(小端 8/1 字节) | 含义 |
|---|---|---|
| 0x0a4 | `01` | rxLinked=1(通过 recv/0x1004c6c 的非零检查) |
| 0x0b8 | `ef be ad de 00 00 00 00`(=0x00000000DEADBEEF) | fcnBackendRw 标记 |

- **预测可观测**:**sepc = stval = 0xDEADBEEF,scause=0xc**(取指页fault),PC Trace 含 0x1004c9c / 0x1016206 / recv 帧;**不再是** 0x1b8ffbc/stval=0x4fe6。崩溃发生在泵任务上下文(不一定是 task3)。
- 判读:
  - 出现 0xDEADBEEF ⇒ 成功:字节进入被解引用(执行)的指针,Q1 布局结论得到动态确认;
  - 仍是 0x1b8ffbc/0x4fe6 ⇒ 重试路径未走 0x1004c6c:检查宿主是否真的投了 33 个元素(否则元素 32 根本没拷,meta 未坏),或 pump 调用路径与推演不符;
  - 完全不崩、RPC 静默 ⇒ rxAvail=0 使 pump 永远判空(消息不可消费 + 元数据已坏):这本身也是"字节已落地并改变行为"的证据(与枪 B 对照)。

### 枪 B(对照枪)

同枪 A,但元素 32 **全零**(连 +0xa4 也是 0)。预测:重试第 1 遍 `lbu +0xa4 == 0` → recv 直接返回 0x10006(队列空)→ **不会出现 0xDEADBEEF**;后续为挂起或旧式崩溃。与枪 A 成对 ⇒ 证明是"我们写入的字节"而非"越界这个动作"在起作用。

### 枪 C(备用触发,需要宿主重算 checkSum + 把 seqNum 填成 期望值−1)

走 seqNum 间隙路径(A 级:checksum→MCTP→vendor→seqNum 检查在 msgLen 之前,seqNum 不符且 gap 收敛时 0x10163f8 调 **msgqRxMarkConsumed(handle, 33)**,其内 0x1004d10-0x1004d30 同样 `ld a5,0xb8; jalr a5`)。元素 32 规格:

| 偏移 | 值 | 含义 |
|---|---|---|
| 0x0a4 | `01` | rxLinked |
| 0xa0 | `40 00 00 00` | rxAvail=64 ≥ 33(过 0x1004cf8 的 bltu 检查) |
| 0x9c | `00 00 00 00` | rxReadPtr=0 |
| 0x88 | `40 00 00 00` | rx.msgCount=64(0+33 < 64,走直接路径到 +0xb8 调用) |
| 0xb8 | `ef be ad de 00 00 00 00` | 标记 |

预测同枪 A(sepc=stval=0xDEADBEEF,scause=0xc,但调用点为 0x1004d30)。

### 枪 D(可选,"完好重写"阴性对照)

meta 的函数指针都是**静态已知代码地址**,可以原样写回:+0xb8 = `9c cf 00 01 00 00 00 00`(0x100cf9c)、+0xe0 = `5c 4c 00 01 00 00 00 00`(0x1004c5c)、+0xc0 = `20 16 19 04 00 00 00 00`(0x4191620)、+0xa4=1、+0xa0=0,其余零。预测:**不崩**,recv 表现为"队列空"。证明 4KB 重写精确落地且只有被改字段改变行为;随后再打一枪 A 可分离"落地"与"崩溃"。

### 优先级与顺序

**A → B → (必要时)C → D**。枪 A/B 一对即可给出结论性证据;C 覆盖"重试路径与推演不符"的情形;D 用于精细区分。

---

## Q4(可选)lookup 的 "tag" 从哪来 —— A 级

**不来自调用点 a0,也不来自报文内容。** 调用点 0x1b8ffb0 前的 a0 是日志函数 0x1a9e5ec(0x1b8ffac 调用,a0=1 为日志级别)的残留返回值;而 lookup 0x101dcb4 在 0x101dcc8-0x101dccc 用栈地址**覆盖** a0/a1 后才调内部函数,入口 a0 从未被使用。

tag 的真实来源 = **0x101dc08 计算的有效通道掩码的第一个置位位号**(0..31):
- 0x101dc08:经同一注册表全局 0x41d3f38 取表,读 `表+0xf95c` 的 32 位分配掩码,逐位过滤"条目区(表+0x441f0, 计数 表+0x443f0)里有键==位号且对象指针非空"的位,输出有效掩码与计数;
- 0x101dcb4:取掩码第一个置位位号 a4,在条目区找 `键==a4`,返回其对象指针(条目+0);未命中 → 日志 + 0x1b4da14 钩子 → 返回 NULL。

即被查的"tag"= 通道号,键集合由**设备侧通道注册状态**决定,与报文字节无关 ⇒ **不存在"构造报文让 lookup 成功"的路线**;反过来,凡是让"已注册通道集合变空"的事件(通道拆除/关闭,H1/H2)都必然产生本次崩溃形态。

---

## 置信度汇总

| 结论 | 置信度 |
|---|---|
| staging = init 0x1a98924 @0x1a99022 分配,尺寸 2*sizeMax+0xe8=0x200e8,memset 清零 | A |
| 布局:[P,+0x10000)=RX staging;[P+0x10000,+0x20000)=TX staging;[P+0x20000,+0x200e8)=msgqMetadata(hQueue) | A(指令级 + 宿主 msgq 库逐字段交叉) |
| K=17 越界窗口 = TX staging 第 0 页,纯数据缓冲区 ⇒ 内容无关性 | A |
| meta+0xb8=fcnBackendRw=0x100cf9c,经 0x1004c6c/0x1004cdc 间接调用;meta+0xe0=0x1004c5c(fence) | A |
| K=17/19 打中表计数/条目/掩码结构上不可能;计数清零假设被实验(0xDD vs 0)证伪 | A |
| tag = 有效通道掩码首置位;调用点 a0 未被使用;与报文无关 | A |
| 分配器 0x18c3c54→0x18c3704,块头 0x10,heapDesc=0x4190db0;staging 之后是 MQI+0x1e8 对象 | A(机制)/ B(序邻接) |
| 表体 VA、堆池位置、MQI+0x1e8 对象身份/尺寸 | 未钉死(C) |
| 崩溃的确切动态因果(H1 错误升级拆除通道 / H2 在途回复被砸) | B-/C,需枪 A/B 结果配合宿主侧观察区分 |

## 总结

staging 的 64KB 不是独立分配:init 0x1a98924 一次性分配 0x200e8 字节并清零,前 64KB 是 RX staging(越界源),紧接的 64KB 是 TX staging——**K=17/19 的越界窗口命中的就是这个纯数据工作缓冲区**,所以填充内容无关;再往后 0xe8 字节是 msgqMetadata(hQueue, MQI+0x1a8),与宿主 msgq 库逐字段吻合。注册表关键字段(掩码 +0xf95c、条目 +0x441f0、计数 +0x443f0)位于一个 ≥278KB 堆对象的尾部:若表在 staging 之前则方向打不到,若在其后则计数至少要求 K≥101、掩码至少 K≥48,且两块不能重叠——**K=17 打中表在结构上不可能**;0xDD 与全零同陷阱又从实验上证伪了"清零计数"假设。lookup 的 tag 实为"有效通道掩码首置位",与报文无关;崩溃更可能是消息不可消费(checksum 必败,即便过 checksum,msgLen>sizeMax 也必败)引发通道拆除/掩码变空所致(H1/H2)。下一枪用 K=33:第 33 个元素恰好覆盖 msgqMetadata,在其 +0xb8(fcnBackendRw)写入 0xDEADBEEF、+0xa4 置 1,recv 重试时 msgq 层会 jalr 到该指针 ⇒ 预测 sepc=stval=0xDEADBEEF、scause=0xc,即可证明我们的字节进入了被执行的指针;配全零对照枪与备用 seqNum 间隙路径枪,判读标准已逐枪给出。
