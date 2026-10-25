# FSP 侧攻击面——本轮(2026-09-27)静态新增发现与实验规格修订

作者:主 agent(静态分析;所有"新增"均为本轮从源码/头文件新钉死的事实,与 FSP_LINE_COMPLETE.md §9 的开放清单对照)

## A. 新钉死的事实

### A1. EMEM 命令队列的完整寄存器协议(宿主视角,源码级)
来源:`kern_fsp_gh100.c`(GB202 复用,GB202 无自己的 EMEM HAL ⇒ 走 GH100 实现)+ `dev_fsp_pri.h`(gh100/ls10 发布版,地址与实测一致)。

- 发送(宿主→FSP):`EMEMC(0)=0|AINCW` → 写 N 个 `EMEMD` → `QUEUE_TAIL = paddedSize-4`(=最后写到的 dword 序号,**dword 单位**)→ `QUEUE_HEAD = 0`(**敲门铃,写 HEAD 触发 FSP 中断**)。
- FSP 消费(由宿主侧 canSend 逻辑反推):**FSP 读 [QUEUE_HEAD .. QUEUE_TAIL] 区间,读完后把 QUEUE_HEAD 置回 = TAIL**("FSP will set QUEUE_HEAD = TAIL after each packet is received",kern_fsp_gh100.c 注释)。
- 回包(FSP→宿主):FSP 把响应写进通道 EMEM(**偏移 0 起**——宿主读端恒从 0 读,协议为"单包驻留"而非环形),写 `MSGQ_TAIL`(最后 dword 序号);宿主算 `packetSize=(TAIL-HEAD)+4`,从 EMEMD 连读,然后**宿主写 TAIL=HEAD** 确认。
- 通道容量 1KB;`EMEMC` 的 BLK(15:8)×OFFS(7:2) 可寻址 256 块×64 dword = **64KB EMEM 地址空间**(8 个通道,每通道一对 EMEMC/EMEMD/QUEUE/MSGQ 寄存器,`__SIZE_1=8`)。
- **PFSP 块 = BAR0 0x8f0000-0x8f3fff(16KB PRI 窗口)**,内含:Falcon common(scratch@0x8f0320 族)、MNOC(0x8f1e00 族)、EMEM(0x8f2ac0)、QUEUE(0x8f2c00)、MSGQ(0x8f2c80)。

### A2. MNOC 硬件语义(发布头文件 dev_mnoc_pri_zb.h,GB100)
- `RECEIVEMBOX`(宿主→FSP 方向,4 端口):`INFO=0x184+port*0xC`、`WDATA=0x188+port*0xC`;
  **MESSAGE_SIZE bits19:0 为 RW**(宿主自声明,上限 1MiB)、TRIGGER bit20(只写)、RECEIVE_READY bit24、ERR bit25、CREDIT bit26。
- `SENDMBOX`(FSP→宿主,4 端口):`INFO=0x104+port*0xC` SIZE 只读(FSP 写),`RDATA=0x108`。
- **驱动软件侧才有 min/max 检查;寄存器本身无长度强制**(与 MNOC_OVERDECLARE_EXPERIMENT_SPEC §1 一致,本轮从寄存器位定义再次确认:SIZE 字段就是 20 位 RW,无其它约束位)。
- 每个端口有独立 PRIV_LEVEL_MASK(端口 2/3 实测读出 0xbadf5720 = PRI 特权拒绝,与 PLM 存在互证)。

### A3. SEC2(PSEC)是第二个同型通道面(昨日 DS_SEC2_INTERFACE 已有配方,本轮补充定位)
- PSEC 块 = BAR0 **0x840000-0x843fff**;EMEMC(0)=**0x840AC0**、QUEUE_HEAD(0)=**0x840C00**、MSGQ(0)=**0x840C80**;协议与 PFSP 完全同型(每通道 1KB,RM 用 ch0)。
- **GB202 上 Kernel RM 从不经 EMEM 与 SEC2 通信**(GB202 落 default 桩)⇒ 该通道在正常系统里**静默**,但寄存器在、SEC2 固件很可能仍实现服务端(同 IP 家族行为)。
- 开源树里宿主→SEC2 唯一已知消息 = **COT(0x14,860B 载荷)**;INFOROM→SEID=1、HULK→SEID=0 的路由表痕迹存在(无调用点)。
- ⇒ 未经探测的**第二 FSP 同族攻击面**(SEC2 固件同样加密,但 COT 解析器在验签前消费字段——GSP 侧 COT 已证有 parse-before-verify 形态,见 PARSE_BEFORE_VERIFY_MAP_20260925.md)。

### A4. FSP 响应队列(MSGQ)指针操纵的价值评估(阴性,降级)
- 协议为"单包驻留":FSP 恒从 EMEM 偏移 0 写响应(宿主读端恒从 0 读)⇒ **MSGQ_TAIL 不是 FSP 的写位置指针**,只是"响应长度/存在"标志。
- 宿主乱写 MSGQ_TAIL/HEAD 的效果限于:让 FSP 以为有未消费响应(阻塞发送)或以为已消费(可能丢包)——**流控操纵,非内存破坏原语**。
- 与 K3_FULL_REVIEW F1c 的低优先级判断一致,本轮给出结构性理由(源码级)。

## A5. 【本轮新发现,指令级】GSP 侧 FSP 传输栈定位与 MNOC 端口归属

证据(gsp61057_rx_full.bin,逐指令):
- **EMEM 写助手 @ 0x15015c8..0x15017a0**:`lui a4,0x8f3` + `基址(对象缓存,即 PRI 窗口 W)` → `sw/lw ±(0x8f3000-0x540/-0x53c)` = **EMEMC(0)/EMEMD(0)(通道 0!)**;含 OFFS/BLK 位域解析(`srli 8&0xff`=BLK、`srli 2&0x3f`=OFFS)、 dword 循环写、尾部奇字节路径、以及写后 EMEMC 回读自检(与宿主侧 _kfspWriteToEmem_GH100 同构)。
- **MNOC 发送包装器 @ 0x150a3b0**:`lui a5,0x8f2; addi a5,a5,-0x200` = **0x8F1E00(MNOC 基址)**;栈参:`0(sp)=0(port=0!)`、`8(sp)=0x8f1e00`、`0x10(sp)=0x200`;调 0x1951660 助手。
- **RmFspUseMnoc 消费者 @ 0x1509426**;传输分发 @ 0x150c170。⇒ GSP 的 FSP 传输模块 = 0x14f6000-0x150c000 区域。

**端口归属表(修正:GSP 端口号为假设,待 B7a 实证)**:
| MNOC port | 归属 | 证据/置信 |
|---|---|---|
| 0 | **假设:GSP→FSP**(0x150a3b0 的 aperture 参数 base=0x8f1e00/span=0x200 含全部 4 端口信箱;端口号在更下层助手内,未定位)| B(需 B7a 嗅探实证) |
| 1 | 宿主直连(实测 task2/PRC/CAPS 受理) | FSP_LINE 实测,A |
| 2 | CPU-RM(GB100 语义;GB202 上驱动不用) | kern_fsp_gb100.c KERNEL_FSP_MBOX_PORT=2;实测特权毒 |
| 3 | 未知/特权 | 实测特权毒 |
注:B7a 嗅探实验(轮询读 4 个端口的 SEND INFO/RDATA)本身就是端口归属的实证判据——哪个端口有流量,哪个就是活跃通道。

**两个新攻击面推论(待黑盒验证)**:
1. **H-PORT-INJECT**:宿主直写某个活跃 GSP 端口的 RECEIVEMBOX(INFO=0x8f1e00+0x184+port*0xc、WDATA=+0x188+port*0xc)⇒ 以"GSP 身份"向 FSP 发消息。候选高价值目标:`FSP_GSP_COMM(0x21)`(uproc↔uproc 通道类型,port 1 上实测不支持 0x153——若 GSP 端口受理即证实按端口分源);以及 0x21 之外只在 uproc 语境出现的 task 面。端口归属由 B7a 先定。
2. **H-PORT-SNIFF**:宿主可读各端口 SENDMBOX(RDATA=0x8f1e00+0x108+port*0xc)⇒ **被动嗅探 FSP→GSP 流量**(GSP 启动期的 COT 交互、运行期 kfsp 事务部可见)。
3. 注意:若驱动在跑,GSP 自己在用其端口——注入会与真流量交错(需无驱动环境;或先嗅探确认静默)。

## A6. 【已由 Track F1 指令级证实】宿主可向 GSP 注入伪造的"FSP 响应"(内容控制原语,非溢出)

F1 审计证实(FSP_TRANSPORT_AUDIT.md §4.1):GSP 的 EMEM FSP→GSP 收包函数 **0x14FB74C** 逐指令:
- 读 `0x8f2c80/0x8f2c84`(MSGQ_HEAD/TAIL —— **均为宿主可写寄存器**,FSP_LINE 实测);算可用字节 = TAIL-HEAD+4;
- 与调用者容量比较(先验后拷,无溢出);
- 从 `0x8f2ac4`(EMEMD,同样宿主可写)读内容进调用者缓冲。
⇒ **注入机制成立**:宿主预填 EMEM 通道内容 + 写 MSGQ_TAIL ⇒ GSP 把任意宿主字节当作"FSP 响应"收进 mctpSubmit 的回包处理链(deliver_cb 0x18B4DDC 固定 0x78 拷贝 → 调用者解析)。
**影响定位**:内容全控但拷贝有界 ⇒ 不是内存溢出,而是 **GSP 侧 FSP-响应状态机注入原语**(伪 COT/证书查询/TNVL/ECC 响应可欺骗 GSP 逻辑;具体可欺骗面取决于 24 个 mctpSubmit 调用者中在跑的那些)。需 GSP 正在等待 FSP 响应时窗口命中(或主动触发 GSP 发 FSP 请求)。
**附带价值**:FSP 侧实验若把 FSP 打挂,此通道也是区分"FSP 死"还是"回程断"的诊断手段。



## B. 修订后的 FSP 侧实验清单(黑盒;静态推导升级)

按"同族证据强度 × 未测状态"排序。全部沿用既有纪律(客体无驱动优先、每命令 ≤120s、挂死即复位、断电兜底)。

### B1.【升到首位】F2′ 多包重组溢出(EMEM 版,精确化)
**为什么最优先**:GSP 侧同族代码已被实锤"先拷后验"(K3-1:元素计数直接做拷贝上界,校验全后置,五个构建一致)。FSP 必须支持多包重组(MCTP SOM/EOM/SEQ;`kfspNvdmToSeid_GH100` 注释:"SEIDs are only needed for use-cases that send multi-packet RM->FSP messages"——多包是协议一等公民)。FSP 重组缓冲大小未知。
**构造**(EMEM ch0,复用 fsp_probe2):
- 包1:MCTP `SOM=1,EOM=0,SEQ=0` + NVDM(合法类型,如 0x13 PRC)+ 载荷 A(≤1KB);
- 包2..N:`SOM=0,EOM=0,SEQ=1..N-1` + 纯载荷(每包 ≤1KB);
- 包N+1:`SOM=0,EOM=1,SEQ=N` 收尾。
- 总载荷阶梯:2KB → 8KB → 32KB → 64KB(远超任何已知 task 缓冲;COT 才 860B)。
**判据**:回 errorCode(安全)/ 回包里出现非常量非 0xff 字节(泄漏!)/ MSGQ 不更新(挂)/ Xid `_FSP_WDT`/`_FSP_UNCORRECTABLE_ERROR`(命中)。
**新增强化**:对照 GSP K3-1 的具体形态——GSP 用**元素计数**做上界;MCTP 重组这边对应的是"累计已收字节数"。若 FSP 侧重组缓冲按**消息类型**预分配(COT=860B?INFOROM=?),则载荷超过该类型缓冲即溢出 ⇒ **优先用该类型本身的合法 NVDM 头 + 超长重组**打(COT 0x14 首选:它已知要 860B,打到 2KB 就可能越界;PRC 0x13 其次)。
**风险**:中;挂死需复位。

### B2.【新增】F1b′ QUEUE_HEAD≠0(起点偏移/长度下溢)
**为什么**:`QUEUE_HEAD` 是宿主可写寄存器,且它是 FSP 读区间的**起点**。宿主协议恒写 0,但寄存器本身接受任意值;FSP 侧若直接 `len = TAIL-HEAD` 算长度:
- `HEAD>TAIL`(如 HEAD=200,TAIL=3)⇒ 无符号下溢 ⇒ 巨大长度(若进拷贝循环即 OOB 读+可能的 WDT);
- `HEAD=k≠0` ⇒ 读窗口平移 k*4 字节(若 FSP 不 clamp,读到通道外 EMEM——**其他通道/私有数据**,回包可能带出 ⇒ 信息泄漏)。
**构造**:正常 12B PRC 读放进 EMEMD;`QUEUE_TAIL=2`(正常);`QUEUE_HEAD` 分别 ∈ {0(对照),1, 5, 100, 250, 0xFFFF}。单独一轮一档。
**判据**:同 B1;特别注意"回包第 5 字起出现非 DEADBEEF 的未知字节" = 越界读泄漏。
**风险**:中低(F1 主实验已证明 FSP 对越界声明有 0x20c 防线,但该防线是查 TAIL 上限还是查区间,未分离——本实验正好分离)。

### B3.(维持)F6 MNOC 声明长度 1MiB(V1/V3/V2)
规格见 MNOC_OVERDECLARE_EXPERIMENT_SPEC(不变)。本轮补充:**CREDIT bit26 的存在意味着 FSP 是边收边排空**(宿主每 64B 等一次 credit)⇒ V2(声明 1MiB+实际推 1MiB)在硬件上可行——FSP 只要在持续给 credit,我们就能把 1MiB 全推进它的 RX 路径。**若 FSP 的接收循环按声明长度排空 FIFO 到固定缓冲,这就是 K3-1 的完美同型。**
**新增变体 V4**:声明 size=0x400(1KB,= EMEM 通道容量,刚好"合法"量级)但 MCTP 头声明多包(SOM=1,EOM=0)⇒ 分离"传输层长度"与"重组层长度"两个信任面。

### B4.【新增】COT(0x14)解析器直接探测——最大结构化宿主载荷 + 验签前消费字段
**为什么**:COT 是宿主可发、FSP 受理的**最大结构化载荷(860B)**,且其字段在验签前被消费(必须先解析才能知道验什么)。载荷结构(开源头 kern_fsp_cot_payload.h,逐字段):
```
u16 version;              // 选择器;驱动侧值 = cotPayloadVersion(开源树零初始化 ⇒ 0 也是"合法")
u16 size;                 // ← 驱动恒填 sizeof(payload)=860;FSP 侧用途未证(此前 PARSE_BEFORE_VERIFY_MAP 已标"未检长度候选")
u64 gspFmcSysmemOffset;   // ← FSP 将从该 sysmem 物理地址读取 GSP-FMC 镜像(287KB)做哈希 ⇒ "FSP 任意地址读"原语候选
u64 frtsSysmemOffset; u32 frtsSysmemSize;   // FRTS 区域(FSP 据此设置 WPR2/FRTS 保护)
u64 frtsVidmemOffset; u32 frtsVidmemSize;
u32 hash384[12]; u32 publicKey[96]; u32 signature[96];   // 48B/384B/384B 固定数组
u64 gspBootArgsSysmemOffset;
```
**未测字段空间**(DYN_IMAGE 轮只动过 hash/sig/pkey 内容与镜像字节,拿到 0x33/0x377/0x1db;version/size/四个地址字段从未直接 fuzz):
1. `size` ∈ {0, 1, 859, 861, 0x400, 0x1000, 0xFFFF}(其余字段全合法)——若 FSP 用它做拷贝上界 ⇒ 860B 定长缓冲溢出(载荷内容大部分可控:通道内 1KB 全是我们的字节);
2. `version` ∈ {0,1,2,3,0xFFFF}——选择器型解析器分发的经典缺陷面(错误码指纹可映射内部分支);
3. `gspFmcSysmemOffset` = 宿主自选物理地址(合法其余字段)——FSP 会从该地址 DMA 读 287KB:错误码/时延差异 = **FSP 侧任意物理读 oracle**(即使验签必败,读已发生);地址设为显存/不可映射区可分离行为;
4. `frtsSysmemSize/VidmemSize` 超大值——FSP 据此设置 FRTS/WPR2 保护窗口,尺寸信任缺陷可能直接改写保护寄存器语义(高危字段!但也在"不写熔丝"红线边缘——只观察错误码,不做后续写)。
**通道**:MNOC port 1(与 task2 同路)或 EMEM ch0;860B+8B 头 = 868B < 1KB 单包可容。
**风险**:中(畸形 COT 可能触发 fuse error 检查路径——该路径会 gpuMarkDeviceForReset;先在可复位环境跑)。

### B5.【新增】SEC2/PSEC EMEM 通道指纹 + COT 解析器探测(第二战场)
- 第一步只读:0x840320-32C(scratch)、0x840C80/84(MSGQ)、0x840040(MAILBOX0)——确认 SEC2 通道"活着"与否(DS_SEC2_INTERFACE §0-6 的配方)。
- 第二步(若活):发**合法形状、超长重组**的 COT(0x14)——COT 载荷正常 860B;重组到 2KB/8KB。SEC2 的 COT 解析器在验签前消费字段(同族已证 parse-before-verify 形态)⇒ 长度信任缺陷概率不低。
- 风险:中(SEC2 挂 ⇒ 大概率整机复位;COT 是启动链消息,畸形版可能触发 fuse error 检查——**先在已知可复位环境**)。

### B7.【新增,本轮指令级依据】MNOC GSP 端口双实验:"以 GSP 身份"注入 + FSP↔GSP 流量嗅探
**依据**(A5):GSP 的 FSP 传输用 MNOC(对象 aperture base=0x8f1e00/span=0x200,覆盖全 4 端口信箱);具体端口号静态未定(B)。
**B7a 嗅探(零风险,先做,兼定端口)**:轮询读 4 个端口的 SENDMBOX(INFO=0x8f1e00+0x104+port*0xc、RDATA=+0x108+port*0xc)⇒ 被动观测 FSP→GSP 流量(驱动加载/GSP 启动期可看 COT 交互与运行期 kfsp 事务)+ **哪个端口有活动 = GSP 的端口(实证)**。
**B7b 注入(中风险)**:无驱动环境(GSP 静默)下,宿主向 B7a 确定的 GSP 端口 RECEIVEMBOX(INFO=0x8f1e00+0x184+port*0xc、WDATA=+0x188+port*0xc)发:`FSP_GSP_COMM(0x21)` 最小合法报文 + CAPS_QUERY(0x16)。若 0x21 在 GSP 端口受理(port 1 上是 0x153 拒)⇒ **证实 FSP 按端口分源/分权** ⇒ 宿主获得"GSP 身份"发送面(后续用 GSP 专属 task 面扫指1象)。判据同 B1。
**风险**:中(若 GSP 活着会撞车;先 B7a 确认静默)。

### B6.(记录,低)MNOC port 0 归属判定
port 0 实测 ready+credit 但从未确认服务者。发一条最小 CAPS_QUERY(0x16)到 port 0:若有回包 ⇒ port 0 也通向 FSP(或另一个 uproc)⇒ 攻击面翻倍;无回包 ⇒ 记录。零风险(只读式探测)。

## C. 与用户目标的映射(诚实评估)
- **FSP ACE(理想目标)**:静态不可直接证明(FSP 密文)。本轮路线 = "同族静态证据 + 精确黑盒触发规格"。B1/B3 若黑盒命中内存破坏,下一步需要 FSP 内存布局情报(可能的获取途径:EMEM 越界读泄漏(B2)、FSP 崩溃转储观测、或 GSP 侧已有原语经 0x21 通道以 GSP 身份探测)。
- **GSP 新溢出(保底目标)**:worker 正在审计 RPC 分发层(E3)与 NVDM 解复用(E4),结果待合并。
