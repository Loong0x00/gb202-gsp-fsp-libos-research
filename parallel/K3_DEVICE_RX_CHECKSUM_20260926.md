# K3 设备侧固件逆向确认:gsp61057_rx_full.bin 接收拷贝/校验逻辑与 0x1b8ffbc 崩溃路径(2026-09-26)

纯静态、离线、只读。对象:`/home/user/rt_5090_project/power_governor_reverse/gsp61057_rx_full.bin`
(RV64GC,基址 0x1000000,文件大小 0xE96C00;**VA = 文件偏移 + 0x1000000**,全文同此换算)。
宿主侧参照:`driver_gpio_internal_610.43.03/src/nvidia/src/kernel/gpu/gsp/message_queue_cpu.c`
(`GspMsgQueueReceiveStatus`,行 640-847)与 `inc/kernel/gpu/gsp/message_queue_priv.h`
(`GSP_MSG_QUEUE_ELEMENT` 行 51-68、`_checkSum32` 行 197-209)。

置信度:A=指令级直接证据;B=结构级;C=推断。

## 0 方法与可重跑工具

工具脚本(全部留在 `/home/user/rt_5090_project/parallel/k3_device_work/`):
- `rvlib.py`:capstone `CS_MODE_RISCV64|CS_MODE_RISCVC`、`skipdata=True`,`dump(va,len)` 输出带原始字节的反汇编。
- `scan_calls.py`:全镜像线性扫描 `auipc+jalr ra` / `jal` 直接调用边(auipc 立即数按 20 位符号扩展后左移 12),产出 `edges.pkl`(177440 条边)。
- `scan_refs3.py`:`auipc→addi` 常量传播,找对给定 VA 区间的 load/store 引用。
- 证据反汇编文本:`ev_*.asm`(与本报告引用一一对应)。

复核任意片段的最小命令:
```bash
cd /home/user/rt_5090_project/parallel/k3_device_work
python3 -c "from rvlib import *; print(dump(0x1016104, 0x430))"   # recv 全函数
python3 -c "from rvlib import *; print(dump(0x1b8ffb0, 0x10))"    # 故障指令
```

---

## Q1 设备侧"元素拷贝 + 校验"函数:A 级确认

**函数:VA 0x1016104 - 0x101652c(文件偏移 0x16104 - 0x1652c,约 0x428 字节)。**
起点为 `c.addi16sp sp,-0x80` 标准序言;0x101652a 为最后一次跳回共享尾声(0x10161e0),0x1016530 起是下一函数序言。该函数前 192 字节与 610.45 的同名函数逐字节相同(K3 既有结论,本轮在 610.57 镜像上独立重反汇编确认)。

关键区段(证据 `ev_recv_0x1016104.asm`):

**(a) 4096 字节元素拷贝循环 0x101614a - 0x10161d6**
```asm
0x0101612e  ld   s5, 0x198(s11)     ; s11=MQI 全局 0x41914d0;s5 = MQI+0x198 = staging 基址
0x0101617e  lw   a2, 0x178(s11)     ; a2 = MQI+0x178 = queueElementSizeMin = 4096
0x0101618e  auipc ra, 0xffff7
0x01016192  jalr  ra, ra, -0x1f2    ; -> 0x100cf9c 每元素拷贝助手(msgq 传输层:页表解槽位+拷贝,3 次重试)
0x0101619e  ld   a5, 0x178(s11)
0x010161a2  add  s3, a5             ; staging 写指针 += 4096,循环内【无任何容量比较】
```
循环上界 s2 的计算在**第一个元素拷完之后**(i==0 分支):
```asm
0x010161a8  lbu  a4, 0x1f1(s11)     ; bEncryptionEnabled(CC 标志)
0x010161ac  lw   a2, 0x170(s11)     ; hdrSize = 16
0x010161b0  addi a3, a5, -1         ; 4095
0x010161b4  beqz a4, -> 0x101622c   ; 非 CC 分支
  ; CC 分支:
0x010161b6  lw   s2, 0x10(s5)       ; staging+0x10 = CC tag.encryptedSize
  ; 非 CC 分支:
0x0101622c  lw   s2, 0x18(s5)       ; staging+0x18 = payload(rpc 头)+8 = rpc->length ★宿主控制
0x010161ba  addw s2, s2, a2         ; + hdrSize
0x010161c4  add  s2, a3             ; + 4095
0x010161c6  divu s2, s2, a5         ; nElements = ceil((hdrSize+length)/4096) = gspMsgQueueBytesToElements
0x010161ce  bgeu s4, s2, exit       ; 已拷个数 vs nElements
```
与宿主源码 `message_queue_cpu.c:660-705`(先 `portMemCopy` 搬元素,i==0 时再从已拷入的 staging 算 `nElements` 调整循环条件)逐行对应。

**(b) 内联 `_checkSum32`(两份,CC/非 CC 各一),形状=8 字节字 xor 循环 + 高低 32 位折叠 + 与 0 比较**
```asm
; 非 CC 版 0x1016314-0x101633a(CC 版 0x101623c-0x1016262 同构)
0x01016314  lw   a2, 0x18(s5)       ; length
0x01016318  addw a2, a4             ; + hdrSize
0x0101631e  add  a2, s5             ; end = staging + hdrSize + length
0x01016320  bgeu s5, a2, ok         ; len==0 跳过
0x01016328  ld   a3, 0(a5)          ; ┐ 8 字节字
0x0101632a  addi a5, 8              ; │ xor 循环
0x0101632c  xor  a4, a3             ; │
0x0101632e  bltu a5, a2, -6         ; ┘
0x01016332  srli a5, a4, 0x20       ; ┐ 高低 32 位折叠(NvU64_HI32^LO32)
0x01016336  xor  a5, a4             ; ┘
0x01016338  sext.w a5
0x0101633a  beqz a5, ok             ; checkSum==0 才通过
```
与 `message_queue_priv.h:197-209` 的 `_checkSum32` 完全同形。

**(c) 后续头校验(全部在拷贝与 checksum 之后)**
- MCTP version:`0x1016264 lw a1,0(s5); andi 0xf; bne a1,1 -> 0x101636c`(mctpHeader 低 4 位==1)
- NVDM vendorId:`0x1016268 lw a5,4(s5); srliw 8; 与 0x10de 比较(lui a2,1; addi a2,0xde); bne -> 0x1016384`
- seqNum:`0x1016286 lw a2,0xc(s5); bne a2,s10 -> 0x101639c`(s10 = MQI+0x1b4 = rxSeqNum)
- msgLen:`0x10162b0 bltu a1,a4`(msgLen<hdrSize)与 `0x10162b4 ld a5,0x180(s11); 0x10162b8 bltu a5,a1`(msgLen>sizeMax=0x10000)→ 0x1016354

元素布局与宿主头文件逐字段对上(`GSP_MSG_QUEUE_ELEMENT`:+0 mctpHeader,+4 nvdmHeader,+8 checkSum,+0xc seqNum,+0x10 payload;`rpc_message_header_v03_00.length` 在 rpc 头 +8 → staging+0x18)。

---

## Q2 "先信任长度、后校验":A 级确认

是。指令时序:
1. `0x101614a` 起循环拷贝,每轮 `add s3,a5`(staging+=4096),**循环体内不存在 s2 与 16(=sizeMax/4096)或任何常量的上界比较**;
2. `nElements`(`s2`)在 i==0 元素已拷入后,由 `staging+0x18`(非 CC,= 宿主写的 rpc->length)经 `divu` 算出(`0x10161b6-0x10161ca`);
3. 全部校验(checksum `0x101633a`、MCTP `0x101626e`、vendor `0x1016282`、seqNum `0x101628a`、msgLen≤0x10000 `0x10162b8`)都排在 `0x10161ce` 循环出口**之后**。

即:宿主声明多大的 length,接收端就往 64KB staging 往后线性拷多少个 4KB 元素,校验时溢出已成事实。与宿主侧"先拷后验"源码语义一致(同一共享源码算法,设备侧为 RISC-V 编译产物)。

---

## Q3 失败路径去向与 NULL 解引用链条:A 级(路径)/ B 级(因果)

**recv 的全部失败分支只做"记日志 + 置状态码 + (重试≤3 次) + 返回",调用深度≤2,不存在任何深调用链:**

| 失败类型 | 分支点 | 去向 | 状态码(s1) | 源码对应 |
|---|---|---|---|---|
| 队列空(i==0) | 0x10161d8 | 直接返回 | 0x10006 = NV_WARN_NOTHING_TO_DO | mqcpu.c:668 |
| 读不完整 | 0x101620c | log(0x1a9e5ec)→重试 | 0x55 = NV_ERR_NOT_READY | :671-675 |
| checksum≠0 | 0x1016262 / 0x101633a | 0x101633c log→重试 | 0x25 = NV_ERR_INVALID_DATA | :729-734 |
| MCTP ver≠1 | 0x101626e | 0x101636c log→重试 | 0x25 | :740-748 |
| vendorId≠0x10de | 0x1016282 | 0x1016384 log→重试 | 0x25 | :750-758 |
| seqNum 不匹配 | 0x101628a | 0x101639c log;若 seq<期望且 gap 收敛:0x10163f8 `msgqRxMarkConsumed`(0x1004cdc)跳过旧包、`s7++`(nMaxRetries++) | 0x25 | :762-795 |
| msgLen 越界 | 0x10162b0/0x10162b8 | 0x1016354 log | 0x3a = NV_ERR_INVALID_PARAM_STRUCT | :827-836 |
| MarkConsumed 失败 | 0x10162c8 | 0x1016486 log | 0xffff = NV_ERR_GENERIC | :840-845 |
| CC 解密失败 | 0x1016458 | 0x10164b6 log + 错误注入钩子 0x143b8f4 | s4 | :809-823 |

(状态码数值已与 `nvstatuscodes.h:28/66/87/114/178` 一一核对。日志函数 0x1a9e5ec 为变参 printf 型——tp+0x88 取每任务日志配置;格式串地址在 0x20a9xxxx,**超出本镜像范围**(文件最大 VA 0x1E96C00),这就是"镜像里没有日志字符串"的原因:字符串段不在 rx_full.bin 内。)

**故障指令序列与 NULL 的来源(A 级):**
```asm
; 函数 0x1b8feec 内(文件偏移 0xb8ffb0):
0x01b8ffb0  auipc ra, 0xff48e
0x01b8ffb4  jalr  ra, ra, -0x2fc   ; -> 0x101dcb4  注册表查找:按 tag 找对象指针
0x01b8ffb8  lui   a5, 5            ; a5 = 0x5000
0x01b8ffba  add   a5, a0           ; a5 = 返回值 + 0x5000
0x01b8ffbc  lbu   a5, -0x1a(a5)    ; ★ sepc:读 [ret+0x4fe6],ret==NULL → stval=0x4fe6,scause=0xd
```
被调函数 `0x101dcb4`(文件偏移 0x1dcb4,证据 `ev_lookup_0x101dcb4.asm`)语义:
- 经全局 `*(0x41d3f38)` 取注册表,`ld a5,0x1a8(a5)`;表计数在 `表+0x443f0`,条目在 `表+0x441f0`、步长 0x10、键在条目+8;
- **未命中路径(0x101dd0e-0x101dd4a)**:打两条日志 → 调 0x1b4da14(0, 调用者ra)(断言/断点钩子,调试标志置位时 `ebreak`)→ `0x101dd4a li a0,0` → **返回 NULL**;
- 调用点 0x1b8ffb8 **不做 NULL 检查**直接 +0x5000 取字节。

**从失败分支到 0x1b8ffbc 的推理(B 级,数据因果而非控制流因果):**
篡改 length(K×4096-16)的消息在 recv 拷贝循环阶段就已把 (K-16)×4KB 的填充字节(实验 pat=0,即全零)写到 staging 之后;随后 checksum 校验才失败,recv 仅返回 0x25。溢出清零了 staging 后方堆上的注册表/对象(计数 `表+0x443f0` 或条目指针变 0)。此后 RPC 服务任务(见 Q4:task 3 = 函数 0x1aa8c92 → 服务循环 0x1b8feec)在下一轮循环调用 0x101dcb4 查找对象 → 未命中 → 返回 NULL → 0x1b8ffbc 解引用 NULL+0x4fe6。**失败分支本身不含 NULL 解引用序列;崩溃发生在"之后的 RPC 处理路径"上,根因是校验前拷贝造成的堆破坏。** 这同时解释了为何触发条件"没有重算 checkSum"仍能看到崩溃:checksum 失败只是让 recv 拒绝该消息,崩溃由溢出残留破坏独立引发。

---

## Q4 0x1b8ffbc 的位置判定:**不在接收函数内**,在独立的 RPC 服务任务中(A 级)

崩溃栈四帧逐一落实:

1. **pc=0x1b8ffbc** ∈ 函数 **0x1b8feec**(序言 `c.addi16sp sp,-0x190` @0x1b8feec,文件偏移 0xb8feec;函数体约 0x1566 字节,唯一正常 ret @0x1b8ff9c,栈金丝雀失败尾部 @0x1b91444 调 0x1aa340c 后 `lbu a5,0x688(zero)`+`ebreak` 主动踩页)。该函数是被调两次的大型循环:0x1aa8dea(本栈)与 0x1aa425a;它调用发送侧 0x1016790(与 recv 共用 MQI 全局 0x41914d0 的 TX/回包函数)@0x1b90292 ⇒ 是 **RPC 服务/分发循环**,**不是**接收函数 0x1016104(两者相距 0xb7KB,recv 全体 0x428 字节内不含 0x1b8ffbc)。
2. **ra=0x1aa8dee** ∈ 函数 **0x1aa8c92**(序言 @0x1aa8c92,与提示一致;`0x1aa8de6 auipc ra,0xe7; 0x1aa8dea jalr ra,ra,0x106 → 0x1b8feec`,返回地址恰为 0x1aa8dee ✓)。此函数开头调用队列初始化函数 **0x1a98924**(@0x1aa8da8,该 init 内有 MQI 字段建立/拆除,见 Q5)⇒ 是**任务主函数**:先初始化消息队列,再进 RPC 服务循环。
3. **ra=0x1c0530c**:不是普通调用返回地址,而是**任务栈切换蹦床 0x1c052fe 内的恢复点**:
   ```asm
   0x01c052fe  c.addi sp, -0x18
   0x1c05300/02/04  sdsp ra/s0/s1
   0x01c05306  c.mv   s1, sp
   0x01c05308  c.mv   sp, a6        ; 切到新任务栈
   0x01c0530a  c.jalr a7            ; 在新栈上起任务函数 → 压入的 ra = 0x1c0530c
   0x01c0530c  c.mv   sp, s1        ; ← 任务函数返回后的恢复点
   ```
   旁证:任务启动代码 `0x1abd0ae: auipc a7,0xfffec; addi a7,a7,-0x41c` ⇒ **a7 = 0x1aa8c92**,随即 `0x1abd0c2 auipc ra,0x148; jalr 0x23c → 0x1c052fe`(@0x1abd0c6,证据 `ev_taskspawn_0x1abd0a0.asm`)。即 0x1aa8c92 正是 Xid 报的 **task 3 入口**。
   蹦床前的紧邻函数(0x1c05276-0x1c052f8)确为错误码映射形状:与 0x1002/0x100d/0x1014/0x1009 等比较,返回 0xf0/0xf2/0xf4/0xf7/**0xf9**/0xfc/0xff(`0x1c052f4 addi a0,zero,0xf9`),与提示相符。
4. **0x1a9e486 = 非代码栈值(陈旧数据)**,确认:其前一条指令 `0x1a9e482 jalr zero,t1,-0x22` 是**尾跳转**(rd=zero,不产生返回地址),故 0x1a9e486 不可能是任何调用的返回地址——它是任务栈上蹦床帧之下的历史残留(该处恰好是一个 t0=0x26 的系统调用桩入口)。

结论:崩溃链 = **task3 主函数 0x1aa8c92 → RPC 服务循环 0x1b8feec → 注册表查找 0x101dcb4 返回 NULL → 0x1b8ffbc NULL+0x4fe6 解引用**。与接收函数 0x1016104 的失败分支无控制流交集(recv 的两个调用者是消息泵函数 0x1a8b374 内 @0x1a8b3d4 与 @0x1a92356 所在函数;均不在崩溃栈上)。

---

## Q5(可选)staging 分配点与堆邻接线索:B 级(部分完成)

- **MQI 全局 = 0x41914d0**(与 610.45 同址)。字段由 recv/TX 的使用反推并被 init/teardown 写回证实:+0x170 hdrSize(16)、+0x178 elemMin(4096)、+0x180 sizeMax(0x10000=64KB)、+0x190/+0x198 staging 相关指针、+0x1a8 队列句柄、+0x1b4 rxSeqNum、+0x1f1 CC 标志。
- **初始化函数 0x1a98924**(栈帧 0x230,由 task3 主函数 @0x1aa8da8 调用):内有对 MQI+0x1a8(hQueue,@0x1a9909c)、+0x1e8、+1f0 的建立写;以及从参数结构(s1+0x190/0x198/0x1a0...)向**第二个队列信息结构 0x4181620** 拷贝 staging 指针/尺寸(@0x1a98f68-0x1a98fb8)。
- **拆除路径两处**把 MQI+0x198(staging)等字段清零:0x1a9a954-0x1a9a96c(配套 `free` 调用 @0x1a9a926/0x1a9a948)与 RPC 服务循环内的 0x1b90306-0x1b90354(已按对齐反汇编核实)。
- **未钉死**:staging 指针写入 MQI+0x198 的"赋值点"(64KB alloc 返回值 → MQI+0x198)。常量传播扫描未命中,说明写入经由从内存加载的基址寄存器(非常量);0x10000 大小的分配调用亦未唯一锁定(全镜像 `lui x,0x10`+call 候选 497 处,噪声大)。
- **打击目标线索**:崩溃链涉及(a) 注册表对象:全局指针 `*(0x41d3f38)`,表基在 `对象+0x1a8`,计数 `+0x443f0`、条目 `+0x441f0`(步长 0x10,{指针, tag});(b) 被查得的客户端对象:字段读至 `+0x4f80/+0x4f88`(指针对)与 `+0x4fe6`(标志字节)⇒ 对象尺寸 >20KB 或 +0x5000 处为嵌入子结构。溢出(pat=0 全零)把计数/指针清零即足以触发本次 NULL 解引用;若换成可控填充,条目指针可被劫持 → 潜在任意对象伪造(待堆风水证实,C 级)。

---

## 置信度汇总

| 结论 | 置信度 |
|---|---|
| recv=0x1016104-0x101652c,拷贝循环/nElements/checksum/头校验位置与顺序 | A |
| nElements 由宿主 length 在拷贝前(循环中)推出、无容量上界检查 | A |
| 失败分支仅 log+状态码+返回,无深调用、无 NULL 解引用 | A |
| 0x1b8ffbc 在 RPC 服务循环 0x1b8feec 内,不在 recv 内 | A |
| 0x101dcb4 未命中返回 NULL 且调用点不检查 | A |
| task3 入口=0x1aa8c92、0x1c0530c=栈切换蹦床、0x1a9e486=陈旧栈值 | A |
| 溢出清零注册表 → lookup NULL → 崩溃 的因果链 | B(静态自洽,与 stval=0x4fe6/pat=0 实验事实一致) |
| staging 64KB 分配点、堆邻接对象身份 | 未钉死(C/B-) |

## 下一步该看哪里

1. 在 init 0x1a98924 内以"写 MQI+0x198 的基址寄存器来源"为目标做数据流回溯(建议进 ghidra 工程 `gb202_gsp61057.rep` 只对 0x1a98924/0x1a9a8xx 两函数反编译),钉 staging=64KB 分配调用与紧邻堆对象类型,把 Q5 升 A。
2. 反编译 0x1b8feec 全函数(0x1566 字节):确认它是哪类 RPC 服务器循环、0x101dcb4 查的是什么对象表(tag 来源),评估"可控填充"下条目指针劫持的利用面。
3. 核对 0x1aa425a 所在函数(0x1b8feec 的另一调用者,序言候选 0x1aa40f0)与 recv 两个泵调用者(0x1a8b374、0x1a92356 所在函数)的关系,补全"队列→泵→服务任务"全图。
4. 格式串在镜像外(0x20a9xxxx):若需要日志文本佐证各失败分支语义,需找包含该段的配套镜像(本 rx_full.bin 不含)。

## 总结(10 行以内)

在 610.57 镜像上以指令级独立复现了宿主侧"先按 rpc->length 拷贝、后校验"的接收逻辑:recv@0x1016104 的 4096B 拷贝循环上界由已拷入的 staging+0x18(rpc->length)经 divu 推出,循环内无容量检查,`_checkSum32`(8B xor+折叠)、MCTP/vendor/seqNum/msgLen 校验全部在拷贝之后。所有失败分支(checksum→0x25 等,状态码与 nvstatuscodes.h 全对上)只记日志、重试≤3 次并返回,不含深调用或 NULL 解引用。崩溃点 0x1b8ffbc 不在 recv 内,而在 task3(入口 0x1aa8c92,经栈切换蹦床 0x1c052fe 启动,与崩溃栈逐帧吻合)的 RPC 服务循环 0x1b8feec 中:注册表查找 0x101dcb4 未命中返回 NULL,调用点不检查即 `lbu +0x4fe6`(stval=0x4fe6 完全吻合)。因果链为:校验前的溢出清零 staging 后方注册表 → 后续查找返回 NULL → 崩溃;0x1a9e486 确认为非代码陈旧栈值。不确定项:staging 的 64KB 分配点与堆邻接对象身份未钉死;lookup→NULL 的确切被破坏字段(计数 vs 条目指针)需设备侧带标签填充实验或 ghidra 反编译进一步区分。
