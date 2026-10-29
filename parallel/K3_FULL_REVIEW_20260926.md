# K3 全量审阅:GSP/FSP 线现有结论审计 + 下一步实验方案(2026-09-26)

范围:**纯分析**。只读本机既有材料(RESUME_BRIEF §21–§25、parallel/ 下 K3/DS 报告、
L2_REENABLE_STATIC_FINDINGS.md(3346 行)、guest_dmesg_* 证据、fsp_probe/ rm_probe/
rpc_ovf_patch_v11.py/ run8.sh/ unpatch_xdig.py 工具链)。**未做任何硬件实验,未修改任何既有文件。**

材料交叉基线:本报告所有"实测"表述均可回溯到 `guest_dmesg_*` 原文;"静态"表述可回溯到
`parallel/k3_device_work/`、`parallel/ds_work/` 的反汇编产物与公开 610 源码。

---

# ① 结论审计:"终局判定"有没有漏洞

判定原文(RESUME_BRIEF §25):宿主写 ✗、GSP-RM 官方 API 写 ✗(接受但丢弃)、GSP 内代码执行写 ✗
⇒ 门在硬件/引擎特权层,只有 FSP 能写。

**总评:骨架成立,但有三处必须收窄/补枪,其中一处直接影响路线判断(见审计结论 L1)。**

## 1(a) GSP 侧地址 `W + 0x8200d0` 是否真的对 —— 大概率对(A-),选择器没有算错

问题分解:`W = *(0x41904E0) = 0x08200000` 是不是"PRI 偏移 0"窗口?`0x8200d0` 是不是
"selector(0x820000) + offset(0xd0)"?有没有把选择器算重或算漏?

证据链:

1. **W 的角色(A 级)**:`DS_GSP_OBJECT_ACCESS_20260926.md` 用 30,828 处 `auipc+ld` 读点证明
   `*(0x41904E0)` 被固件当"基址 + 绝对 PRI 偏移"直接 `lw/sw`;其中 30,741 处读 `W+0x11152c`
   = `NV_FALCON2_GSP_BASE(0x111000) + NV_PRISCV_RISCV_IRQDEST(0x52c)`(本地已发布
   `dev_riscv_pri.h` 逐字对上),且紧跟 `or 0x400000 / sw` 的 RMW——固件 3 万次用它给自己的
   RISC-V 中断路由编程 ⇒ **W 只能是"PRI 偏移 0 窗口"的 GSP VA 基址**。运行期泄漏读
   (`guest_dmesg_leak_winptr_0853.txt`:a1=0x4190378,+0x168 ⇒ 读 0x41904E0,sepc=stval=
   **0x08200000**)给出数值。
2. **选择器没有算错**:`DS_GSP_MMIO_WINDOW_20260926.md` 的 5 个消费者点(0x13585FC 等)全部
   用同一公式 `aperture + (*(pGpu+0x318))() + K`,getter 返回常量 `0x820000`(lui a0,0x820; ret,
   由 OBJGPU 构造簇装进 +0x318 槽)。也就是说 **0x8200d0 这个数字本身已经 = selector(0x820000)
   + offset(0xd0)**;我们写 `W + 0x8200d0` 正是"aperture + selector + offset",既没有把
   0x820000 加两次,也没有漏掉它。旁证:驱动侧 RegHal 表(`gb202_reghal_offline.py` 实测查询)
   domain 5 offset 0xd0 的 `fixed_selector_bar0 = 0x008200d0`,与宿主裸读 BAR0 0x8200d0
   得到合理 PLM 值、且 2026-07 task2 改动的正是宿主可见的 0x8200d0 —— 三方一致。
3. **`0xBF0000` 第二选择器载荷不构成分叉**:它是同一 aperture 上另一个 PRI 块基址(驱动表
   `id 0x10EF4000, domain 0, offset 0xBF0000`),与 fuse 域无关;没有任何代码用
   "aperture + 0xBF0000 + fuse_offset" 的形式访问 floorsweep 寄存器。
4. **之前写错的版本已被否定并修正**:`0x082000D0`(=W+0xd0,BAR0 0xd0,PMC 块)的泄漏读
   (`guest_dmesg_leak_reg_0948.txt`)返回 `0xFFFFFFFFBADFFFFE`(PRI 读错误族,flcnretval.h
   `FLCN_CSB_PRIV_PRI_ERROR_CODE=0xBADF0000`)⇒ 那才是"差一层"的地址;§25 写枪用的
   `0x08A200D0` 是修正后的正确形态。

残留风险(必须明说,按概率排序):

- **R-a1(唯一实质性残留)**:W 与 `*(pGpu+0xB98)`(attach-args 灌入的 deviceMappings[0].
  gpuNvAddr)**数值相等只是强推断**——角色相同已证,数值从未对比(pGpu 不在任何 BSS 全局,
  DS 已证拿不到)。若它们是同一 BAR0 的两张映射,写哪个都到同一物理寄存器,无害;若 W 是
  另一张不同物理孔径,我们就写错了地方。
- **R-a2**:0x08A200D0 **从未从 GSP 侧读过**(只有"写枪干净返回 + 宿主回读未变"两个观测)。
  这是 (b) 的主题。
- **R-a3**:64-bit `ld` 对 PRI 窗口是否被桥拆成两个 32-bit 事务,未验证;只影响"读验证枪"
  的数值解释,不影响地址正确性。

## 1(b) "写被丢弃" vs "写到别处/写进别名" —— 目前不可区分,这是终局判定唯一的软肋

§21(A) 自己的反面数据:把写目标设成 `0xdead0000`(未映射)时,表现同样是"安静超时、无陷阱"
⇒ **"gadget 干净返回 + 宿主回读未变"这个签名,同时兼容以下三种情形**:

- H-drop:写到达物理 PLM 寄存器,被目标处的写权限过滤丢弃(判定原文的解释);
- H-hole:W 窗口在该偏移处对 GSP 是个洞/别名,写根本没到达目标;
- H-map:libos 把该窗口页对 RM 分区映成只读,store 被静默吞(不触发 fault 的那种)。

判别工具与约束:读 gadget `0x1020a30` = `ld a5,0x168(a1); c.mv a0,s3; c.jalr a5`
(8 字节对齐硬约束——0x0831152C 的 misaligned 读给了 scause=0x4;"跳到读出的值"必崩
⇒ **一个 GSP 启动只能打一枪**);写 gadget `0x1b52246` = `c.sw a4,0(a1); li a0,0; ret`
(32-bit,与固件窗口访问宽度一致)。

**判别枪 R1(首选,只读、零副作用、一枪定案)**:泄漏读 `0x08A200D0`。
载荷:K=33/ck=0,元素 32 仅 `+0xa4=01`、`+0xb8=0x1020a30`、`+0x38 = 0x08A200D0-0x168
= 0x08A1FF68`。(与 leak_reg_0948 的 `a1=0x081fff68 ⇒ 读 0x082000D0` 同一构造法。)

- **预测 A**:sepc/stval 低 dword = `0xFFFFFB8E`(=0xfffffb8f 被 jalr 清 bit0;高 dword =
  `0x8200d4` 的内容)⇒ GSP 在该 VA 读到的就是宿主那个 PLM ⇒ 地址、窗口活性、GSP 读权限
  三重坐实。PRI 译码按地址:读能到,写必到同一物理寄存器 ⇒ 写死只能死在**目标的写过滤**
  ⇒ H-drop 成铁案,H-hole/H-map 死。
- **预测 B**:读出 `0xBADFxxxx` ⇒ GSP 对该偏移连读都被滤(整块 source-isolate)⇒ 终局结论
  ("GSP 写不动")不变,但机制改写为"读也滤",且 GSP 侧此后连观测都做不到,一切只能靠宿主
  回读。注意 d0 的读 nibble = 0b1111(全 level 开),所以预测 B 成立意味着存在**比 PLM 读位
  更外层的 source 隔离**,这本身是重要新信息。
- 注意 dc 的对齐:`0x08A200DC` 不是 8 字节对齐,若将来要读 dc,读 `0x08A200D8`
  (低 dword=0x8200d8,高 dword=dc)。

**正控制(写入类)评估——结论是都不值得抢在 R1 前面**:

- W+0x11152c(IRQDEST):固件 3 万次 RMW ⇒ GSP 必可写,但它管 GSP 自己的中断路由,写错值
  可能打断 GSP⇔宿主中断;写同值又不可观测 ⇒ 两头不靠,**不推荐**。
- `0x820040`(latch request):固件在 0x108C774 里对它 `ori 1` RMW。若 GSP 写 1 后宿主读到 1
  ⇒ 证明 GSP 有 f8 写 nibble(0b1000=L3)级别的权限 ⇒ 会与"d0 写不动"直接矛盾(两只 PLM
  写 nibble 相同)⇒ 该枪**预期阴性**,作正控制价值低;但它其实是 E3 组合枪的免费副产品
  (见 ④-E3),不必单独花开机。
- 结论:**R1 一枪已足够**;正控制类要么危险要么预期阴性。

## 1(c) 宽度/对齐/权限位过滤;有没有"先给 GSP 提权再写"的解锁位

- **宽度**:写枪是 32-bit `c.sw`,与固件对窗口的全部访问(lw/sw)一致 ⇒ 不存在"宽度不对
  被滤"的疑问。读 gadget 的 64-bit `ld` 是唯一非原生宽度,只影响读验证(见 R-a3)。
- **权限位(公开头 `ls10/dev_falcon_v4.h:27-73`,PLM 标准布局)**:
  `[3:0]`=L0..L3 读使能,`[7:4]`=L0..L3 写使能,bit8/9=violation 报告,bit10/11=source
  读/写过滤,`[31:12]`=source enable 向量。冷态 `0xfffffb8f` 分解:
  读 nibble=0b1111(全开)、**写 nibble=0b1000(仅 L3)**、bit8/9=1、bit10=0、bit11=1、
  source 向量=0xfffff(全使能)。MODS 公式的 L0/source0 全 RMW 条件
  `bit0 & bit4 & (!bit10|bit12) & (!bit11|bit12)` 在 fb8f 下因 bit4=0 而失败。
  ⇒ **d0/dc/f8 三只 PLM 按自身位就是"仅 L3 可写"**;这同时解释了宿主写 ✗(L0)、
  EXEC_REG_OPS ✗(GSP-RM 官方路径)、GSP 劫持写 ✗ —— 三者全都不是 L3。
- **"GSP 自提权"路径:不存在已知可行者。** ① 引擎的 PLM level 是其硬件/分区身份(FMC 验签
  的启动链决定),不是一个 GSP 能自己写的寄存器——若存在,PLM 模型自相矛盾。② K3 已证
  (csr_scan)整个 RM 镜像**没有任何真实 CSR/PMP/satp 指令**(9 处候选全是数据区误解码),
  特权操作在镜像外的 libos 内核,RM 任务上下文里没有特权面。③ 已知的合法降 PLM 事件只有
  FSP task2/sub1(降 d0/dc 的写 nibble);f8 的降低者未知(见 ②-B1)。
- **其余"使能/解锁位"现状**:`0x820040` latch request(被 f8 门,host/GSP-API 均写不进);
  `0x8212ac` disable_sw_override=1(读 PLM=0x8200fc;**在项目禁止清单内,只读不写**);
  PLM 自写:RegHal 表无 self-access metadata,且按位义就是 L3-only ⇒ 自举降权不可能。

## 审计结论(三条必须记录的收窄)

- **L1【最重要——措辞过度推广】**:写枪只打过 `0x8200d0` —— 一只**按自身位就是 L3-only 的
  PLM**,即整个 fuse 域里保护最强的一类目标。严格说,"GSP 内代码执行 ✗"目前只证明了
  "**GSP 写不动 PLM**",**从未证明"GSP 写不动 floorsweep 目标寄存器"**(`0x8234e0` raw /
  `0x820040` latch / `0x822900` effective)——那些寄存器的门是 dc/f8,而 dc **可以被 FSP
  task2 合法打开**(2026-07 实测)。把"GSP 写不动 d0"外推为"GSP 侧 floorsweep 线全死"
  在逻辑上不成立。**真正被三方向穷尽的只是"改 PLM"这一条。** ⇒ ④-E3 组合枪是补这个洞的
  决定性实验,也是整条 GSP 线剩余收益所在。
- **L2【机制归属未闭合】**:写被拒 vs 写进洞,当前不可区分(见 1(b))⇒ 需 R1 读枪。
- **L3【归因未分离,承接 `K3_ANALYSIS_20260925.md` §2-3】**:即使未来"GSP 写 raw 也失败",
  raw 写失败仍有三个同等充分的候选门:f8 latch 关、`0x8212ac=1`、BSI/SEC2 互斥仲裁——
  从未被分离实验区分。"只有 FSP 能写"对 PLM 成立;对 raw floorsweep 的完整因果链未闭合。
- **站得住、不需要动的部分**:宿主写 ✗(2026-07 多次 + 相位采样)、EXEC_REG_OPS ✗(§16
  接受但丢弃)、PLM 位语义、地址推导、task2 的净效果、"FSP(task2)是目前唯一实测改动了
  d0/dc 的写入者"。另注意一条边界:说"FSP 唯一能改"也只覆盖 **d0/dc**;**f8 从未被任何
  已知交易改动过**(包括 FSP 的已试交易)。
- 附:§25 说写枪"无 Xid"不精确——`guest_dmesg_regwrite4_1052.txt` 有 Xid 119(RPC 超时)
  与 `unexpected WPR2 already up`;正确表述是"无 GSP 崩溃(无 Xid 120/CrashCat)"。

---

# ② B1 线索重审:FSP task2/sub1(6 字节全零)与复现方案

## 2.1 那次确切发的是什么 —— 已在原件中逐字节核实

来源:`vm_mods_lab/fsp_task2_zero_result_20260722.md` + 工具源码
`vm_mods_lab/prc-read-tools/gb202_fsp_prc_read.c:713 do_task2_zero()`。

- **时间/环境**:2026-07-22,VFIO 隔离 VM,GPU 直通;工具直接 `mmap resource0`(用户态,
  **不依赖 nvidia 驱动**;同轮 MODS tracer 只走到 "GSP-disabled setup" 就崩,设备处于
  无 RM/GSP 的驱动缺失状态)。
- **接口**:**MNOC 信箱 port 1**(`--port 1`;不是 EMEM,不是 GSP 转发)。
- **报文(16 字节)**:`010000c0 7ede1013 02010000 00000000`
  = MCTP dword `0xC0000001`(SOM=1/EOM=1,版本 1)+ NVDM dword(type **0x13=PRC**,
  vendor 0x10de)+ payload `02 01 00 00 00 00 00 00`(**task=2, subobject=1**, 6 字节零)。
- **响应(20 字节)**:`000000c0 7ede1015 01000000 13000000 00000000` ⇒ task_id=1,
  command_nvdm_type=0x13,**error_code=0**(TASK2_ZERO_OK)。
- 该交易在 MODS 里的出处:GB20x `0x106c4e0`(doFsp=1 时)→ 通用 sender `0x185e890`;
  发送前查 FSP QCAP key `0x13` presence;MODS 默认 GB202 初始化成功路径会发它
  (send-before-host-apply)。6 字节 payload 的 builder 本应从 NVLINK/NVLC_LINK 状态构造,
  零售 5090 无 NVLink ⇒ 全零是最强有界默认(零 payload 语义 = 未完全解码,见 ⑤-8)。
- **payload 语义**:零payload的语义没有被完全理解 —— 我们只能确定它在没有NVLink的情况下是合法且被接受的。

## 2.2 净效果 —— 实测逐条(全部出自该次记录的 before/after 快照)

| 项 | 变化 | 含义 |
|---|---|---|
| `0x8200d0` | `0xfffffb8f` → `0xfffffbff` | **写 nibble [7:4]:0b1000(仅 L3)→ 0b1111(L0..L3 全开)**;读 nibble/violation/source 位不变 |
| `0x8200dc` | 同上 | 同上(八只 FBP 的 raw 写共用这只 PLM,RegHal 已证) |
| `0x8200f8` | 不变(`0xfffffb8f`) | latch 的独立 PLM,仍 L3-only |
| `0x820040` latch request | 不变,且写 1 不吃 | f8 未开 ⇒ latch 仍锁 |
| `0x8200e0`/`0x8200f4` | 写 nibble-open 值不吃 | sibling PLM 也不被 task2 覆盖 |
| raw/eff/sw FBP0..7 | 全不变(0x12/0x12/0) | **功能效果 = 零**:PLM 只是许可,不改数据 |
| 持久性 | 会话内多次后续快照(跨多个后续探针)保持 fbff;**未观察到 FSP 收回**;重启/冷态回 fb8f(§1 六相位恒定) | **会话内持久、复位清除**(高置信);驱动重载/GSP reload 边界未测(⑤-5) |

关键推断边界(避免过度解读):

- task2 之后 dc 已开,**宿主 BAR0 写 raw `0x8234e0` 仍不保持**(clear-then-restore 探针,
  0x10→读回 0x12)⇒ dc 不是 raw 写的唯一门;剩余候选 = f8 latch / `0x8212ac=1` / BSI 互斥,
  三者未分离(=审计结论 L3)。
- "FSP 何时/为何收回"不可见(consumer 加密);host 侧无配对 close/undo 调用
  (task2_lifecycle_audit 已证)⇒ 收回机制若存在,只能在 FSP/硬件内部(ack 后自动、首写
  消费、timer、reset…)。

## 2.3 能不能被我们的驱动主动重复 —— 能;现在有两条通道,首选 EMEM

通道现状(2026-09-26):

- **MNOC port 1**:2026-07 的成功条件是"客体无驱动"。2026-09 的全部 MNOC 失败已被 DS 归因
  为 ①用了 port 2 ②`fsp_lie_mod.c` 双重基址 bug(`ioremap(base+0x8f1e00)` 后偏移里又含
  0x8f1e00 ⇒ 实际访问在映射窗口外)——**那批 0/BADF 不是硬件证据,port 1 当前 armed 状态
  未验证**。驱动把 `gpuMnocMbox*` 置 NOT_SUPPORTED 桩只说明 RM 在 GB202 上不走 MNOC,
  不证明硬件 MNOC 消失(2026-07 刚用过)。注意 `guest_dmesg_fsp_ladder4_0942.txt` 里
  正控制读(BAR0+0=0x1b2000a1=chipId ✓、0x8f0334=0x44c=ucode ✓)是好的,而四端口全
  BADF——这批读数同样出自有 bug 的模块,不能定案。
- **EMEM channel 0**(FSP_EMEM_CHANNEL_RM,容量 1KB):2026-09-26 已在客体(带 610.57.04
  驱动)实测收发成功:PRC 读 → `MSGQ_TAIL` 0→0x10,回包 20 字节,NVDM type 0x15
  (FSP_RESPONSE),两次独立运行一致,零 Xid。已知瑕疵:①knob=0 的响应第 5 dword =
  `0x00000202`,形如错误码 ⇒ **EMEM 上还没复现过"成功读值"形态**(2026-07 成功 PRC 读
  是 22 字节、dword4=0、尾带 2 字节值);②带驱动时用 ch0 = 与 RM 自己的 kfsp 流量同队列,
  理论撞车风险(实测无事);③256/2048 两档被 `&0xff` 截断,那两档数据无效。

**复现方案(客体 VM;一步一命令,每步 ≤120s 硬超时;判定看退出码,不看文本)**:

0. preflight:确认无子 agent 在飞(parallel/ 下在飞任务是否落盘);客体状态明确;
   宿主侧 `fuser -v /dev/nvidia* /dev/dri/*`(注意区分用户三个探测服务
   hsr-path-probe / wuwa-path-probe / xid-watch 的周期性 nvidia-smi,它们是噪声不是 holder)。
   **首选环境:客体无 nvidia 驱动**(复刻 2026-07 条件,且避开 EMEM 与 RM 撞车)。
1. `insmod bar0_read_mod.ko` ⇒ dmesg 记基线(期望 d0/dc/f8=`0xfffffb8f`,raw=0x12)。
   (该模块按设计返回 -EINVAL ⇒ 用 dmesg 行作判据。)
2. **正控制**:经 EMEM 发 PRC 读 **knob=0x1d, numbytes=2**(2026-07 已证该 knob=1)
   ⇒ 期望 22 字节响应、dword4(error)=0、尾 2 字节 `01 00`。
   失败 ⇒ 说明 EMEM≠MNOC 的受理面,转 MNOC 修正配方(DS_FSP_MNOC §4:P0 正控制读 →
   扫 port 0..3 取 RECEIVE_READY=1 → 再发)。
3. **发 task2-zero**(EMEM ch0):16 字节 = `C0000001 / 1310de7e / 02 01 + 6×00`;
   发送三步:`EMEMC(0)=(1<<24)`(offset0+AINCW)→ 4 dword 写 `EMEMD(0)` →
   `QUEUE_TAIL(0)=3` → `QUEUE_HEAD(0)=0`(投递)。等 ~300–500ms。
4. 读回包:读 `MSGQ_HEAD/TAIL(0)`,`EMEMC(0)=(1<<25)`(AINCR)后连读 `EMEMD(0)` 5 dword
   ⇒ 期望 `task_id=1, cmd=0x13, error=0`;然后 `MSGQ_HEAD=tail` 确认。
5. `insmod bar0_read_mod.ko` ⇒ **判定:d0==0xfffffbff 且 dc==0xfffffbff = 复现成功**;
   error≠0 或 PLM 不变 = FSP 在 EMEM 上不受理 task2(阴性,转 MNOC 路线重试一次即可定案)。
6. (可选,顺手)生命周期探针:之后每隔几分钟再读;若后续实验要加载驱动,加载后再读一次
   —— 顺带闭合"驱动加载是否收回 fbff"(⑤-5)。

**风险:低。** 该交易 2026-07 已实测无 Xid、无挂死、mailbox err=0;最坏已知后果 = FSP 返回
错误码。**不需要断电重启。** 唯一新风险点是"带驱动操作 EMEM 队列"⇒ 首选无驱动环境即规避。

## 2.4 B1 之后的真问题(复现成功只是入场券)

task2-zero 只开 d0/dc。通往解锁还缺三件,按可动性排序:

1. **raw 写失败归因分离**(f8 vs 0x8212ac vs BSI)——④-E3 的 GSP 写 raw 枪顺带提供
   一个全新数据点(GSP 与宿主可能不同 source/level)。
2. **f8 的合法开启者**:未知。候选:HULK(0x11,需 NVIDIA 签发的 GB202/2b85 绑定证书,
  本地 6 份样本全是他设备 ID,死路除非有新料)、task13/sub2 二阶段变体(0x00→0x06,
  SMSKED_MESSAGE 上下文,语义未解码)、task4(reset coupling 邻近)、task2 其它
  subobject/非零 payload。**(task,sub) 零 payload 全空间扫描 + task2 payload 变体**
  是合法、低风险、未穷举的方向(④-E6/E7)。
3. **raw→effective 传播**:即便 raw 写进,大概率要 reset 边沿才进 effective(公开树无
  A→B copier;采纳点收敛到 hardware sense/rollup)⇒ 复位语义基准(④ 备注;
  公开轶事称 Blackwell FSP 跨 FLR/SBR 保持锁态 ⇒ 可能只有上电复位清,做之前先测边界)。

---

# ③ FSP 漏洞面:探针优先级清单(判"FSP 是否也先拷贝后校验")

静态前提:FSP 指令体加密(v6 descriptor encrypted bit + 7.999 bit/B 熵)⇒ 只能黑盒。
攻击面定量:MNOC 声明长度上限 1 MiB(bits19:0,发送方自声明);EMEM ch0 容量 1KB;
合法 task payload ≤ 几十字节 ⇒ 长度信任面 4–5 个数量级。可见的参照实现(host 收端
kfspReadMessage / gpuMnocMboxRecv)都是先验后拷,但方向相反,不证明 FSP 收端同型安全
(K3_FSP_MSGPATH 已闭合此点)。

统一判定:**回错误码 = 安全实现;WDT/挂死/响应里出现非常量非 0xff 字节 = 命中。**
统一纪律:全部在客体、首选无驱动;每档一条命令 ≤120s;有挂死风险的档位(F1 大档、F2)
**必须等无子 agent 在飞**;挂死按 §20 常备授权处理(先落盘、sync、重启)。

**F1【最高优先级】EMEM 队列长度(QTAIL)过申报扫描** —— 与 GSP bug 最直接的同型:
QTAIL 是我们写的"dword 数",FSP 出队循环若信任它而不按 1KB 容量截断 ⇒ FSP 侧越界读/拷。
- 构造:正常 12B PRC 读(knob=0x1d)放进 EMEMD,但 `QTAIL(0)` 分别写
  {2(正常), 15, 63, 255(恰 1KB), 256, 1024, 0xFFFF};`QHEAD(0)=0` 投递。每档单独一次。
- 可观测:①错误码响应(安全)②响应内容含泄露字节(高价值:FSP 内存经 MSGQ 回读通道
  外泄)③MSGQ 永不更新(队列状态机挂死)④FSP WDT(SEC_FAULT 类 Xid,GSP-RM 字符串已证
  存在该报错路径)。
- 风险:中(大档可能 WDT/挂死 ⇒ 可能要复位/重启)。先小档后大档。
- 变体 F1b:QTAIL 正常但 QHEAD 非 0(起点错位);F1c:MSGQ 侧把 `MSGQ_HEAD` 往回写
  (让 FSP 以为响应队列满/空)——后者只影响响应投递,优先级低。

**F2【高】多包重组(SOM/EOM/SEQ)溢出**
- 构造:dword0 置 SOM=1,EOM=0,SEQ 递增连发多包(每包 ≤1KB),总长 8KB..64KB 远超任何
  task 缓冲,最后一包 EOM=1;NVDM type 用合法的 PRC。
- 可观测:同 F1;安全实现应在重组缓冲满时返回错误或在 SEQ 错乱时报 protocol violation。
- 风险:中;挂死可能:有。

**F3【高,零风险,先做】CAPS_QUERY 全类型枚举(0x00..0x3F)** —— 侦察,不是攻击。
- 构造:NVDM 0x16,payload = 单 dword 类型号,逐个发(0x11/0x13 已证在,v1)。
- 收益:确定 FSP 实装服务表(INFOROM/ROMREAD/TNVL/CLOCK_BOOST/SMBPBI/UEFI_* 是否在)
  ⇒ 给 F4–F7 选目标。风险:极低(合法查询)。

**F4【中高】PRC/COT/HULK 畸形 payload(解析器面)**
- PRC:cmd 空间(0x0c 读/0x0d 写之外)、knob 全空间只读枚举(0x00..0xFF)——0x1e4
  (persistence 拒绝)已证 PRC 写路径有"形态→选项→值→持久化"分层 ⇒ 错误码指纹能映射
  FSP 内部状态机。风险:低。
- COT(0x14):`PARSE_BEFORE_VERIFY_MAP_20260925.md` 已指出版本字段是"验签前被消费的
  选择器"、`size` 是未检长度候选。构造:合法 version + 超大 size / 截断证书链。
  预期:验签失败错误码(安全)vs WDT(命中)。风险:低-中。
- HULK(0x11):无合法证书也能打解析器(bug 在验签前,与 GSP 那条同理);发畸形 cert
  blob,看错误码指纹(对照自签拒收的 0x33/0x1db/0x377 风格)。风险:低-中。

**F5【中】INFOROM(0x17)/ROMREAD(0x1A)只读服务** —— 情报价值(EEPROM/ROM 内容可能
含 fuse/配置线索),顺带测其长度字段处理。风险:低。**纪律:只读;绝不碰
FIRMWARE_UPDATE(0x12)与 RESET(0x4)的 payload 游戏。**

**F6【低,备】MNOC port 1 复核 + MNOC 声明长度(1 MiB)游戏**
- 先用 DS 修正配方复核 port 1 是否还 arm(P0 正控制 → 扫 port);若 arm,MNOC 的声明
  size 域是最大长度信任面:declared >> pushed / declared << pushed / SOM 无 EOM。
- 风险:中(信箱 desync 可能要复位);排在 EMEM 路线之后(EMEM 已验证可用)。

**F7【低】SMBPBI(0x18)/TNVL(0x1F)/CLOCK_BOOST(0x20)/UEFI_RM(0x1C)/
UEFI_XTL_DEBUG_INTR(0x1D)** —— schema 全未知;先等 F3 的 CAPS 结果决定哪些实装,
再"小 payload 看错误码"逐个点名。XTL_DEBUG 名字像调试口,理论上校验弱,但证据为零 ⇒ 最后。

---

# ④ 下一步实验清单(按 收益/风险/成本 排序)

**E1【收益★★★ / 风险极低 / 成本极低】B1 复现:EMEM task2-zero**
目标/载荷/判定/风险:见 ②-2.3。失败后果:无(错误码),不需重启。
这是后续 E3 的前提,也顺带闭合"task2 在今天/EMEM/当前驱动态可重复"。

**E2【收益★★★ / 风险低 / 成本低(一开机一枪)】判别枪 R1:GSP 泄漏读 `0x08A200D0`**
- 载荷:K=33/ck=0,元素 32:`+0xa4=01`、`+0xb8=0x1020a30`、`+0x38=0x08A1FF68`。
- 判定:sepc/stval 低 dword = `0xFFFFFB8E` ⇒ 审计漏洞 L2 闭合,H-drop 成铁案;
  `0xBADFxxxx` ⇒ 机制改写为"GSP 连读都被滤"。
- 失败后果:GSP 崩(Xid 120)⇒ 该次 GSP 启动作废,客体 VM 重启即可,宿主无感。
  **需无子 agent 在飞。**

**E3【收益★★★★ / 风险中 / 成本中】"task2(EMEM) + GSP 写 raw"组合枪 —— 全线最高价值**
直接检验审计结论 L1 指出的未证命题:**dc 降后,GSP 代码能不能写 `0x8234e0`。**
- 顺序(客体,同一 GSP boot 内):
  ① 无驱动 → `bar0_read_mod` 基线 → `fsp_emem_mod` 发 task2-zero → `bar0_read_mod`
     确认 dc=fbff(若此步失败,E3 中止,退回 E1 排查);
  ② `modprobe` 打补丁驱动(run8.sh 管线,K=33/ck=0;元素 32:`+0xa4=01`,
     `+0xb8=0x1b52246`,`+0x38=0x08A234E0`(=W+0x8234e0),`+0xc0=0x00000010`)
     ⇒ 写枪不崩 GSP(gadget 干净返回);
  ③ `insmod bar0_read_mod.ko` 回读 raw 与 dc。
- 判定(三分支,全有信息量):
  raw=0x10 ⇒ **GSP 写 raw 成功 ⇒ 路线 B 复活**(下一步:f8/latch 与 reset 传播);
  raw=0x12 且 dc=fbff ⇒ GSP 写 raw 也被拒 ⇒ raw 的门不是 dc(f8/0x8212ac/BSI 之一),
  路线 B 对 raw 也死,回到归因分离;
  raw=0x12 且 dc 已回 fb8f ⇒ **驱动加载会收回 task2 效果**(生命周期边界,同样重要;
  此时改打"带驱动经 EMEM 发 task2 → 用晚发 fn 触发写枪"的变体,补丁支持按 fn 过滤)。
- 安全:写 raw 有先例(2026-07 单 bit clear-then-restore,带恢复);本枪同样写后即恢复
  (补一枪写回 0x12,或直接靠复位)。**需无子 agent 在飞**;失败后果:最多 RM init 失败,
  VM 重启;不需断电。

**E4【收益★★ / 风险低 / 成本低】CAPS 全类型枚举 + PRC knob 全空间只读枚举**
纯侦察,喂给 ③-F4/F7 与"f8 开启者"搜索。判定:类型/knob 表落盘。失败:无。

**E5【收益★★ / 风险中 / 成本中】FSP F1:EMEM QTAIL 过申报扫描**
判 FSP 是否先拷后验的最直接探针(见 ③-F1)。**可能挂死 ⇒ 必须无子 agent;
接受按 §20 直接重启的预案(重启前落盘+sync)。**

**E6【收益★★ / 风险中 / 成本高】(task,subobject) 零 payload 全空间扫描**
找 f8 开启者/其它"被接受"组合;零 payload + 错误码指纹,不带 payload 不触发写型动作
(2026-07 各 task 返回互异的"不支持"码 ⇒ 校验表存在)。每条交易一条命令,~数百次。

**E7【收益★ / 风险低 / 成本高】task2 非零 payload 变体 + task13/sub2 二阶段解码**
MODS payload builder 语义未知 ⇒ 逐字节单变量小步,每步前后全快照(d0/dc/f8/e0/f4/40/
fc/12ac + raw/eff/sw)。

**E8【收益★ / 风险高 / 成本高】GSP→FSP(0x21)以 GSP 身份发 task2**
需要多 gadget 链调 GSP 内嵌 kfsp 客户端(E1 枪已证堆 XN:scause=0xc ⇒ 无 shellcode 路),
工程量大;且 E1 若成功说明 host 身份已够 ⇒ 仅当"host 发 task2 被 FSP 按来源拒绝"
的假设成立时才值得做。当前证据不支持该假设(task2 从 host MNOC 已被接受)⇒ 最低优先级。

**全线纪律(写进每一步)**:一步一命令、每步 ≤120s;动设备前 `fuser` 验证 holder
(三个探测服务的 nvidia-smi 是噪声);判定看退出码;崩溃枪(读泄漏)= 一开机一枪;
有 Xid/挂死风险的(E2/E3/E5)等无子 agent;不做 BIOS/InfoROM/熔丝写、不碰
0x8212ac(override 使能)、不做 D 系列算力限制器、不做任何对外报告。

---

# ⑤ 不确定项(明说,按对结论的影响排序)

1. **"GSP 写 raw/latch(非 PLM)"从未测** —— 终局判定对 floorsweep 目标寄存器的推广未完成
   (审计 L1;E3 闭合)。
2. **`0x08A200D0` 的 GSP 侧读值从未测** —— "写被拒 vs 写进洞/别名"未分离(审计 L2;
   E2/R1 一枪闭合)。
3. **W 与 `*(pGpu+0xB98)` 数值是否相等** —— 角色相同已证(A),数值未证(仅 INFERENCE)。
4. **raw 写失败归因** —— f8 latch vs `0x8212ac=1` vs BSI/SEC2 互斥,三候选未分离
   (K3_ANALYSIS §2-3 早已指出,至今未补)。
5. **task2 降 PLM 的生命周期边界** —— 会话内持久已见;驱动重载/GSP reload/SBR/FLR 边界
   未测(公开轶事称 Blackwell FSP 跨 FLR/SBR 保持锁态 ⇒ 可能只有上电复位清)。
6. **EMEM 响应第 5 dword=0x00000202 的语义**(knob=0 的错误码?格式字?)与 MSGQ
   head/tail 的精确长度语义(现模块按 dword 猜,实际"20 字节响应"与 tail=0x10 对不齐)。
7. **MNOC port 1 当前 armed 状态** —— 2026-09 的 BADF 读数被模块双重基址 bug 污染,不作数;
   2026-07 的可用性不能自动外推到今天。
8. **f8 的合法开启者** —— 不存在于已扫描的 ~6 task × 4 subobject 子集;全集未扫;
   task2 零 payload 的语义本身也未完全解码(它只是"无 NVLink 默认")。
9. **FSP 是否先拷后验** —— 静态不可判(FSP 加密);③-F1/F2 黑盒探针是唯一途径;
   host 侧参照实现(先验后拷)方向相反,不构成证据。
10. **GSP 堆地址跨启动确定性** —— 两份样本(K33 + E1)一致 ⇒ 较强,但仍是观察到的
    确定性,不是保证(若漂移,所有依赖 P 的载荷作废;gadget 枪不受影响)。
11. **GSP 任务上下文的 PLM level 值** —— 只能从"d0 写不动"反推 < L3,没有直接读出;
    且"泵任务上下文"是否等于"RM 全部上下文"未证(理论上不能排除 libos 内核/启动期
    上下文有更高 level——但那些上下文不可达于我们的劫持点)。
12. **64-bit `ld` 对 PRI 窗口的事务形态** —— 是否被桥拆成两个 32-bit 读,未验证;
    只影响读枪数值解释,不影响任何写结论。
13. **`0x82013c` 的身份** —— 固件在 fuse RMW(0x108C774)里写 1;RegHal 表无行;
    它可能是 latch 流程的一部分(阶梯计划 L1 也列了它),语义未闭合。

---

## 总结(中文)

1. 终局判定骨架成立,但必须收窄:三方向穷尽的只是"**改 PLM**"(d0/dc/f8 按自身位就是
   L3-only);"**GSP 代码在 task2 降 dc 后写 floorsweep 目标寄存器**"从未被试——这是
   判定里唯一的真漏洞,也是 GSP 线剩余的全部收益(④-E3)。
2. "写被拒 vs 写进洞"目前不可区分(§21 自己的反面数据);一枪 GSP 泄漏读 `0x08A200D0`
   即可定案(④-E2,零副作用但一开机一枪)。
3. 地址 `W+0x8200d0` 没有算错:0x8200d0 本身已含 0x820000 选择器,与驱动 RegHal、宿主
   裸读、task2 实测三方一致;残留风险只是 W 与 pGpu+0xB98 数值未比对(角色相同已证)。
4. B1(task2-zero)是真实、可重复、会话内持久的合法交易:d0/dc 写 nibble 从 L3-only 开到
   全 level;但它不开 f8、不开 latch、不动 raw/eff ⇒ 它只是入场券,不是解锁。
5. 复现 B1 首选 EMEM(已实测打通;先做 knob=0x1d 正控制,再发 16 字节 task2-zero,
   bar0_read_mod 判 d0/dc==fbff);MNOC port 1 的"不可用"结论被模块 bug 污染,不可作数。
6. FSP 是否先拷后验只能黑盒判:最高优先探针是 EMEM QTAIL 过申报扫描(与 GSP bug 同型),
   其次是 SOM/EOM 重组溢出;CAPS 全类型枚举是零风险侦察,先行。
7. raw 写失败的归因(f8 vs 0x8212ac vs BSI)三候选至今未分离——无论 E3 结果如何,
   这都是下一步必须面对的岔路。
8. 全部实验遵守:一步一命令 ≤120s、fuser 验 holder、退出码判定、崩溃枪一开机一枪、
   挂死风险实验等无子 agent、不碰熔丝/override/InfoROM/BIOS、不对外报告。
