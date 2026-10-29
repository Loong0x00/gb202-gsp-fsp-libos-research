# RM_HOST_IFACE_BUGHUNT_K3 — GSP-RM 宿主→设备入口静态盘点(2026-09-25)

纯静态。分析对象:
- `ghidra_static/gsp_inner_19f040_a.elf`(r610.45,含少量 assert 串,作主分析)
- `ghidra_static/gsp_inner_570144_main.elf`(570.144,本机卡在用具象)
- `driver_archive/572_xbar_compare/{572.42,572.47,572.60}/gsp_rm_inner.elf`(差分)
- 源码参照:`driver_gpio_internal_610.43.03/src`(开源 RM;设备侧队列解析不在公开树内,以二进制为准)

置信度:A=指令级;B=结构级;C=推断。

## 1 摘要(最值得追的 1-3 个候选)

**K3-1(首选):GSP-RM 侧 RM_RPC 接收函数把"宿主可控的元素计数"直接用作 4KB 拷贝循环上界,全部校验(checksum/MCTP/vendor/seqNum/长度上限)都在循环之后。**
在 570.144、572.42/47/60、610.45 五个构建中逐一核实,形状一致。后果:宿主把最长 (msgCount-1)×4096 = 63×4096 ≈ 252KB 的可控字节线性写进 GSP 侧 64KB staging 区及其后方 GSP 堆(溢出 ≈192KB),且被覆盖区首件就是队列元数据缓存(`rxAvail` 等),而覆盖内容本身可控 → 可塑性强的 GSP-RM 上下文越界写。这正是任务立足点所需的"宿主可控数据→设备侧写"原语;RM 特权级足以降 PLM 后改 floorsweep 寄存器(驱动注释已证 GSP 能降 PLM)。
与既有 §5.5 C3-1(宿主侧 RX、device→host)互为镜像,但本候选在**设备侧**、且覆盖数据全程可控,利用条件更好。

次级:
- **K3-2**(K3-1 的 570.144/572.x 形态细节):元素计数字段(staging+0x28)与字节长度字段(+0x38)是**两个独立字段**,后置检查只查字节长度(≤0xffd0),从不交叉核对计数 ⇒ 无需任何 race 即可"小长度+大计数"通过全部后置检查并完成溢出(错误也不报)。A 级。
- **K3-3**(观察):610.45 接收路径只校验 NVDM vendor=0x10de,**不校验 NVDM type 字节**(0x1016272-0x1016282);该队列专属 RM_RPC,实际影响有限,C 级记录。

## 2 宿主→设备入口枚举

| # | 入口 | VA(镜像) | 分发手段 | 宿主可控字段到达层 |
|---|---|---|---|---|
| E1 | GSP 命令队列接收,NVDM 0x25 RM_RPC | recv:`0x1016104`(610.45);`0x1014380`(570.144);`0x10141c4`(572.60);572.42/47 同型(checksum 折叠序列 `@0x1013eb8/0x1013f24`) | 由消息泵循环直接调用(610.45 调用点 `0x1a88cfc`、`0x1a8fc7e`);非跳转表 | 元素计数/RPC length、seqNum、payload 全部字节 → 直接进入 RM 上下文(校验在拷贝后,见 §3) |
| E2 | GSP→host 状态队列发送(对照,fail-closed) | 610.45 含 `0x2510de7e` 内联构造 `@0x1016816`;570.144 经辅助函数 `0x14cc850` | — | 长度先检后用(`0x10167dc-0x10167ec` wrap+max 检查在写头之前),与源码 TX 一致 |
| E3 | RPC function 分发(staging 校验通过之后) | UNKNOWN(本轮未钉 VA) | payload+0xc `function` 字段 → 推断为函数表/序列化分发 | NV2080_CTRL/rmapi 参数块(长度已限 ≤64KB) |
| E4 | 其他 NVDM 类型解复用(SMBPBI 0x18、FSP_GSP_COMM 0x21 等) | 570.144:`0x102e45c`、`0x1034038`、`0x1034214`(vendor 0x10de + type 比较链) | 类型比较链(if-else),非表 | 各自 payload;本轮未深挖 |
| E5 | 设备侧 msgq 库层(`libraries/msgq/msgq.c`,共享源码) | 内联于 E1 调用链 | — | 队列头 `writePtr` 经 `writePtr<msgCount` 校验(`msgq.c:660`)= fail-closed;`msgqRxLink` 对 `entryOff/msgCount` 有界(`msgq.c:382,400-407`) |
| E6 | GSP 日志/事件队列 | 方向为 device→host,宿主侧解析缺陷即既有 C3-1(§5.5),不在本任务范围 | — | — |
| E7 | 类引擎方法/method dispatch | UNKNOWN(经 RPC 转入 RM,未单独钉表) | 运行时构建的方法表(可用 `gsp_rv_method_stores.py` 续查) | — |

E1 关键布局(610.45,MQI 全局 `0x41914d0`):`+0x170`=hdrSize(16),`+0x178`=elemMin(4096),`+0x180`=sizeMax(65536),`+0x198`=staging 指针,`+0x1a8`=命令队列 msgq 句柄,`+0x1b4`=期望 seqNum。570.144/572.x 布局不同(元素头含 16B CC tag:计数在 staging+0x28、seq 在 +0x24、字节长度在 +0x38)。

## 3 候选缺陷表

| ID | VA / 函数 | 可控字段 | 缺失校验 | 后果 | 可达性前提 | 置信度 |
|---|---|---|---|---|---|---|
| K3-1a | `0x1016104`(610.45):拷贝循环 `0x101614a-0x10161d6`;计数计算 `0x101622c`(非CC: `lw s2,0x18(staging)`=RPC length)+`0x10161b6-0x10161ca`(bytesToElements, `divu @0x10161c6`);检查 `0x10162b0/0x10162b8` | RPC `length`(payload+8)/CC `encryptedSize` | nElements 未与 staging 容量(16 元素)比较即进循环;max 检查在循环后 | GSP 侧线性越界写,≤63×4096B(≈192KB 溢出),数据全程可控 | 宿主写命令队列(改驱动/内核内存,同 C3-1 的 (b) 类前提) | A(顺序)/B(staging=64KB 及元数据相邻) |
| K3-1b | `0x1014380`(570.144)、`0x10141c4`(572.60)、572.42/47 同型:计数 `lw s2,0x28(s4) @0x101443c/@0x1014280`;循环出口 `bgeu s10,s2 @0x1014442/@0x1014286`;后置检查 `0x101450c-0x101451a/@0x1014350-0x101435e` | staging+0x28 元素计数字段(直接当上界,连 divu 都没有) | 计数字段**从不**被校验;后置检查查的是另一字段(+0x38 字节长度 ≤0xffd0) | 同上;且"小长度+大计数"可静默通过全部后置检查 | 同 K3-1a | A |
| K3-2 | 见 K3-1b 行(计数与长度两字段无交叉核对) | 同上 | 计数↔长度一致性 | 溢出且不误报,消息照常分发 | 同上 | A(字段分离)/C(分发后行为) |
| K3-3 | `0x1016272-0x1016282`(610.45) | NVDM type 字节 | 只查 vendor 0x10de,不查 type=0x25 | 轻微:非 0x25 类型也进 RPC 解析;该队列专属 RM_RPC,影响有限 | 同 K3-1a | A(无比较)/C(影响) |
| K3-4 | `0x1a88ca0-0x1a88d58`(610.45,continuation 重组循环,含 `bltu a5,a4 @0x1a88d48`) | 续传记录数/总长度 | **已审计:有剩余空间检查,fail-closed(负结果)** | — | — | A(负) |
| K3-5 | `msgq.c:329-407`(msgqRxLink,设备侧链接宿主 TX 队列) | 宿主队列头 `rxHdrOff` | `rxHdrOff` 只有下界检查(`msgq.c:400`),无上界 | `pTheirRxHdr=pBackingStore+rxHdrOff` 越界;但写目标(readPtr=0)经 backend 落回**宿主内存** → 自伤,对本目标价值低 | 初始化期一次 | B(源码)/C(影响) |

量化(全部本地可复算):命令队列 256KB ⇒ msgCount=64 ⇒ rxAvail≤63(`message_queue_cpu.c:70,96`;`msgq.c:660-670`);staging=sizeMax=64KB(`0x180` 字段及 `0x10162b8` 比较);溢出起点=第 17 个元素;寄存器只能放大 status 队列,不能放大 command 队列(`message_queue_cpu.c:108-113`)。
诚实限制:① staging 之后紧邻对象的精确身份(device 侧 msgqMetadata / 堆邻接)未在二进制中钉死分配点(B);② 循环上界同时受 `rxAvail` 缓存(`*(0xa0(句柄))`,每迭代重读)约束,溢出会改写它——但改写内容可控,可塑性反而更好(C);③ 溢出落点在 GSP 堆,能否精确打到 floorsweep 相关对象需后续堆风水分析(C)。

## 4 版本差分线索

- 570.144 / 572.42 / 572.47 / 572.60 / 610.45 **五个构建全部存在**"拷贝先于校验",无一版本修过 ⇒ 差分给出的是**一致性证据**(该形态是长期 shipping 行为),而不是"某版新增的修复"型线索。
- 形态差异:570.144/572.x 用"计数字段直接当上界"(K3-2,更糙);610.45 重构为"length→bytesToElements"(仍后置检查)。572.42 与 572.47 的 checksum 折叠序列地址完全相同(`0x1013eb8/0x1013f24`),两者该函数逐字节同构;572.60 平移到 `0x101432c/0x1014398`。
- 570.144 把 NVDM 头构造收到辅助函数 `0x14cc850`(无直接调用点,疑似经间接调用/死代码);610.45 为内联 `0x2510de7e`。

## 5 建议的下一步验证

1. (静态)钉 device 侧 staging/工作区分配点:在 610.45 找写 MQI `+0x198` 的初始化函数,确认分配大小=64KB+元数据相邻 → 把 K3-1 的 B 升 A。工具:`gsp_rv_method_stores.py`/`gsp_rv_const_refs.py 0x10000`。
2. (静态)从 staging 消费点反推 RPC function 分发表(E3):跟踪 `0x10162c0→0x1004cdc` 之后读 payload+0xc 的代码,枚举 function 表 → 得到第二层宿主可控攻击面清单。
3. (静态)用 `radiff_functions_deep_t90.txt` 既有差分复查 572.42↔572.60 中 `0x1013d94`/`0x10141c4` 附近有无其他校验差异(本轮只核了主形态)。
4. (静态)SMBPBI 解复用(`0x102e45c` 等)的 payload 长度处理,同法过一遍。
5. (静态)610.45 `gspPluginHeapLength/gspUncachedHeapBase` 符号周边,评估溢出可达的堆对象类型(为堆风水做图)。
6. (必须上设备,本轮不做)任何触发/观测类验证一律不在本任务范围。

## 6 UNKNOWN

- E3 RPC function 分发表的 VA 与表结构(未钉)。
- E7 类引擎方法分发表(未查;`gsp_rv_method_stores.py` 可续)。
- `power_governor_reverse/gsp61057_rx_full.bin`(裸 bin)本轮未分析;未知其基址与是否同型。
- 570.144 中 `0x14cc850` 的调用方(无直接 auipc+jalr 引用;可能死代码或经函数指针)。
- staging 后方对象的精确身份与溢出后的可利用布局(需分配点 + 堆图)。
- device 侧是否存在 CC(on)模式下不同的计数语义(本机 CC=off,610.45 CC 分支 `0x10161b6` 读 encryptedSize 仅指令级确认)。

---

# 【独立复核:610.57(本机在用构建)指令级确认】

**结论:K3-1 在本机匹配构建中成立(我自己的字节级/指令级证据,不是转述)。**

1. 跨构建同构性:把 610.45(`ghidra_static/gsp_inner_19f040_a.elf` VA `0x1016104`)的前 **192 字节**在
   `power_governor_reverse/gsp61057_rx_full.bin` 中检索 → **逐字节命中 @ 文件偏移 0x16104 ⇒ 基址 = 0x1000000**
   ⇒ **610.57 同一函数位于 VA 0x1016104,且与 610.45 逐字节相同**(570.144 形态未命中,属另一构建)。
2. 指令级读法(VA 0x1016104,capstone RV64+RVC):
   ```
   0x101612e  ld  s5, 0x198(s11)   ; s5 = MQI+0x198 = staging 基址(MQI 全局 0x41914d0,与 K3 一致)
   0x101614a  <循环>               ; 每轮调辅助函数搬 1 个 4096B 元素
   0x10161a2  add s3, a5           ; staging 运行指针 += 4096 ← 无容量比较
   0x10161b6  lw  s2, 0x10(s5)     ; ★ 读【已拷贝进来的宿主数据】staging+0x10
   0x10161ba  addw s2, s2, a2      ;   + hdrSize(16)
   0x10161c4  add s2, a3           ;   + (4096-1)
   0x10161c6  divu s2, s2, a5      ; ★ nElements = 字段 / 4096  ← 循环上界来自宿主
   0x10161ce  bgeu s4, s2, exit    ;   copied vs nElements
   ```
3. **控制字段定位**:`GSP_MSG_QUEUE_ELEMENT.payload` 以 `rpc_message_header_v` 开头
   (`inc/kernel/gpu/gsp/message_queue_priv.h:139`),宿主侧 `gspMsgQueueGetPayloadSize()` 直接返回
   `pRpc->length`(:150)⇒ 设备读的 `staging+0x10` = **RPC 头 length 字段**(payload+0)。
4. 另一路界:循环内每轮还检查队列句柄的 `+0xa0`(可用元素数),所以**触发的必要条件是宿主把足够多的 4KB 分片真的放进命令队列**
   (队列 256KB ⇒ 至多 63 片)。
5. 后置检查仍在循环之后(K3 已标 `0x10162b0/0x10162b8`),即**溢出先发生、错误后报**。

---

# 【实验日志:宿主→RM 溢出触发 已实测,含宿主侧事故与恢复纪律】

## 结果(2026-09-25 14:1x,自主客体 VFIO lab)
补丁(宿主侧 kMD,仅客体):`rpc_ovf_patch.py` → `message_queue_cpu.c` 的 `GspMsgQueueSendCommand`:
覆写 RPC `length`(=K×4096−16)并把 `nElements` 提到 K;循环内对 i≥真实元素数的槽**填充我们的字节**
(填充经 `msgqTxGetWriteBuffer` 拿槽、随 `msgqTxSubmitBuffers` 一次提交 ⇒ 设备侧线性写在 staging 之外)。

**实测(ramp 版 K=17,21):**
```
XDIG OVF step=0 realElems=1 K=17 declaredLen=0x10ff0 msgLen=0x3e8 pat=0x00000000
XDIG OVF step=1 realElems=1 K=21 declaredLen=0x14ff0 msgLen=0x603 pat=0x00000000
Xid (PCI:0000:00:02): 120, GSP task exception: load access page fault (cause:0xd) @ pc:0x1b8ffbc, task:3
→ unexpected WPR2 already up / RmInitAdapter failed! (0x62:0x40:2119)
```
故障点定位(镜像偏移 0xb8ffbc):
```asm
0x1b8ffb4 jalr ra,ra,-0x2fc   ; 调用返回基址在 a0
0x1b8ffb8 c.lui a5,5          ; a5 = 0x5000
0x1b8ffba c.add a5,a0
0x1b8ffbc lbu  a5,-0x1a(a5)   ; ★ 页错误:指向被清零/打歪的指针
```
⇒ 与"零填充溢出破坏 staging 之后的活动数据"一致;**溢出发生在任何校验之前**。

## 参数化(免重编)
`rpc_ovf_patch.py` v2 读注册表:`RmXdigOvfK`(元素数,0=关)、`RmXdigOvfPat`(0=零;1=**带标签** `0xDD000000|(i<<12)|byteoff`;其它=常量)。
配合 `NVreg_RegistryDwords="RmXdigOvfK=17,RmXdigOvfPat=1"` ⇒ 免重编逐 K 迭代。

## ⚠ 宿主侧事故与恢复纪律(**必须遵守**)
1. 触发后设备处于"WPR2 立着 + RM 已死"⇒**绝对不能直接让宿主驱动去绑它**:会得到
   `Unable to determine the device handle ... Unknown Error` + `nvidia-modeset/kthread_q` **D 状态挂死**,
   随后 `modprobe -r nvidia*` 失败。
2. **绝不要再 `rmmod -f`**(会在核心里阻塞,`rmmod` 变 D 状态,只能重启)。本日已踩一次。
3. **正确顺序(固定下来)**:实验结束 → `qmp-quit` → 杀 VM 进程 → **在 vfio 绑定状态下先做 SBR/设备复位**
   (`setpci -s 0000:00:01.1 BRIDGE_CONTROL.w=0040:0040` → 清位 → `echo 1 > /sys/bus/pci/rescan`),
   确认设备复位成功**再** `leave-live`(回 nvidia);否则会出现上面第 1 条。
4. 若已挂死:重启宿主是唯一干净解法(D 状态进程不可杀)。

## 下一步(重启后继续)
- 矩阵:K=16(对照,应不越界)/ 17(最小越界)/ 18,20,24…,**每台 VM 一枪**,`RmXdigOvfPat=1` 带标签;
  用 Xid/日志里出现的 `0xDD00xxxx` 值反推**被覆盖的是第几号元素的第几字节** ⇒ 堆布局地图。
- 目标:找到"可控"的落点(msgq 元数据 / 对象 vtable / RegHal 描述符),把"崩"变成"可控寄存器写",
  最终用**驱动侧读回 `0x8200d0/dc/f8`** 作为解锁成功的判据。

## 更正(2026-09-25 15:0x):SBR 优先,重启是最后手段
上一节把"重启"写成唯一解法,顺序错了。正确顺序:
1. 实验结束 → `qmp-quit` → 杀 VM 进程;
2. **在 vfio 绑定状态下**执行 `sudo rtx5090-vfio-sbr`(新脚本:桥 `0000:00:01.1` 的 SBR 位 → 保持 2s → 清位 → rescan);
3. 确认设备可再初始化(必要时 `nvidia-smi`)后再 `leave-live`(回 nvidia)+ 起 `nvidia-persistenced lactd waterloop-fan-control gdm`;
4. 只有 SBR 也救不回时,才考虑重启 —— 且**重启前必须确认 gdm/sshd/网络会自启**,并告知用户会发生什么。
**禁止**:`rmmod -f`(会阻塞成 D 状态,只能重启)。
