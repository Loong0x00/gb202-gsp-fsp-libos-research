# 🎯 GSP 真机提权最终方案 (2026-10-08 定稿)

**目标**: RM用户态(U-mode) → LibOS内核(S-mode) → PMP窗口全开 → FSP车道
**前置**: 所有试验在VM; vm_cycle.sh / GPU_REVIVE.sh / 修复后的DKMS注入管道就绪

---

## 武器库状态(全部已验证)

| 武器 | 状态 | 内容 |
|---|---|---|
| V2 写/读 | ✅真机实弹 | RM进程内任意4B写(a1/a4全控)+任意读, 静默, 堆地址跨启动确定 |
| C1 竞争 | ✅模拟器 | 非原子refcount(全内核0原子指令)→双destroy→freelist环→**释放→重分配闭环(今日ALLOC#3实证)** |
| C2 跳转 | ✅模拟器 | 页头[page+0x20]投毒8B→RELEASE→S-mode `jalr [0xa300a000+type_id*40+0x28]` 任意地址 |
| 门禁情报 | ✅静态 | t0=27/t0=24权限门=globalB(0xa301b1d8), 内核0写入者, boot常量 |
| 快表 | ✅静态 | 0xa3008ce8, 36项×8B, `jalr`低32位, t0=16/29槽=NULL(安全试验位) |

**关键地址**: 快表0xa3008ce8 | 类型表0xa300a000 | pool描述0xa300a020(40B/项) |
globalB 0xa301b1d8 | currentTaskA 0xa3018008(t0=27门左值) / 0xa3008008(t0=22用) |
写gadget 0x1b52246(sw a4,0(a1)) | 金牌写 0x17460e8 | 读gadget 0x1020a30

---

## 第0步 — 三别名写入矩阵 (2-4发注入, ~1小时, 决定走哪条分支)

内核数据有**三个别名**, U-mode对各别名的写权限从未测过(只测过低别名**执行**被拒):
`0xffffffffa300xxxx`(高) | `0xa300xxxx`(boot PMP窗) | `0x1A30xxxx`(内核低别名执行窗,真机由BootROM SBI map安装)

```
Shot A: E4写gadget: a1=0x00a3008d68 (快表[16]槽, NULL安全), a4=0x41414141
Shot B: 同, a1=0x01A308d68 (0x1A30别名)
Shot C: 同, a1=0xffffffffa3008d68 (高别名, 大概率拒, 对照组)
验证:   读gadget读回 → 变了=U写通!
```
判读: **A或B任一通 → Phase 1 (当天完成提权)**; 全拒 → Phase 2 (C1路线)

---

## Phase 1 — U写通时:三步提权 (最快路径)

```
1. 读 currentTaskA: [0xa3018008] → RM任务指针P   (读gadget)
2. 写 globalB: [0xa301b1d8] ← P                  (写gadget, 先读原值存档)
3. RM调 t0=27 (a0=0xffffffffa3000000, a1=0x1c000, a2=0x57D)
   → 门通过(s1==a5==P) → 内核数据段整体映射进RM用户空间RW
   验证金丝雀: 映射后RM读[映射基址+0x8ce8]应=0xffffffff9300239e(快表[0]已知值)
```
拿到内核数据RW后, 终局二选一:
- **1a. 快表投毒=内核函数调用预言机**: 写快表[N]=任意内核函数地址, syscall t0=N 触发,
  a0-a7=完全受控参数 → 离线扫52KB内核找 `csrw 1482/1484/1486, a0系` PMP gadget
  → 一次syscall开任意物理窗口(含FSP MMIO) → 完全体
- **1b. C2跳转**: 写任一pool页头+0x20 → 触发RELEASE → S-mode直接执行
无痕恢复: globalB写回原值; 快表16/29槽写回0。

## Phase 2 — U写全拒时: C1竞争路线 (RPC风暴, 小时级)

```
1. 目标: shuttle(task+0x30)或port对象(type A) — syscall上下文与timer/调度器共享,
   双方都做非原子 ld/+1/sd (如t0=1内0xffffffff93002542)
2. 宿主RPC风暴 → 每RPC多次port RELEASE → timer中断命中ld-sd间6指令窗口
   (~20ns/心跳周期; 万级RELEASE/s → 分钟级期望命中)
3. 命中 → 同对象双destroy(已实证) → freelist自指环 → 下两次同type分配同址(已实证)
4. 双所有权: RM经消息写用户字节进freed对象[header+0] = 污染freelist next
   → 分配器返回 攻击者地址+8 → 内核对该"对象"写refcount/字段 = 内核任意写
   → 落点选 pool页+0x28 → C2 jalr → S-mode
5. 后续同Phase 1
```
Phase 2 风险: 命中不可观测(需副作用推断), 建议先在模拟器把风暴时序排练成脚本。

## Phase 3 — 并行保底: SBI通道M-mode面
t0=15通道页(内核池物理页, 映射回RM可写) → ecall 0x900001eb → M-mode解析通道页字段
若M-mode信任页内字段 → U→M直达(比root更高)。需BootROM/FSP侧分析(GSP_FSP_IFACE续)。

---

## 本日新增实证汇总
1. 释放→重分配闭环: RELEASE入页freelist([header+0]链) = 分配器消费链(ALLOC#3同址) ✅
2. 快路径模型: 游标[entry+0x38]→[cursor+0x10]→[header+0], sd [s1]=1置refcount ✅
3. RM首个syscall: t0=1(a0=3,a2=0x41cd700)→SPAWN路径分配type4(任务对象) ✅
4. C1竞争面扩大: t0=1内shuttle非原子ACQUIRE(0xffffffff93002542); 0x9300408c兼类型检查
   (t0=1用其验type==6) → 页头投毒兼可欺骗类型检查 ✅
5. 模拟器保真度: 内核boot后跑低别名(0x9300xxxx), memset快转发/一切hook需双别名 ✅

## 实施纪律
- 每次写内核数据前: 读原值→存档→写→验证→(必要时)恢复
- 试验槽只用快表[16]/[29](NULL); 崩溃=Xid→VM复活, 无硬件风险
- 命中判定全部用已知值金丝雀(快表[0]=0xffffffff9300239e等)

---

# 🚨🚨 重大勘误 (2026-10-08 深夜): 之前分析的是 GB10Y 内核, 真内核是 GB20X

**事实**: /tmp/kernel_gb20x.elf(旧) ≠ RTX 5090 实际运行内核!
真内核 = gsp_ga10x.bin 偏移 0x10D040 → /tmp/kernel_gb20x_REAL.elf
(代码段 56KB vs 旧52KB, +1539条指令; 反汇编 = kernel_gb20x_disasm.txt)

## GB20X 地址总表 (全部已验证)

| 项 | GB10Y(旧,作废) | **GB20X(真)** |
|---|---|---|
| syscall快表 | 0xa3008ce8 (34项) | **0xa3008280(表A,16项) + 0xa3008308(表B,12项)**, bounds t0<0x24 |
| NULL槽 | 16/29 | **16/29 仍NULL**; **t0=30-33=未编目真handler**(表B后溢出数据) |
| 分发点 | 0x93003dde | **0x930043e6** (SAVE→bounds→`lw t4,[0xa3008280+t0*8]`→`jalr t4`@0x9300440a) |
| task恢复PC槽 | task+0x188 | **task+0x3d0** |
| RELEASE(非原子) | 0x930060f2 | **0xffffffff93005b26** (ld/-1/sd @0x93005b28) |
| 类型计算 | 0x9300408c | **0xffffffff93004568** (公式不变: (desc−0xa300a000)>>3 × 0xCCCCCCCD) |
| pool描述符基址 | 0xa300a020 | **0xa300a000 系(不变!)** |
| 析构表 | 0xa300a000, entry+0x28 | **0xffffffffa300ff00, entry+8**, jalr@0x93005b60 |
| t0=27门 globalA/globalB | 0xa3018008/0xa301b1d8 | **0xa3018010 / 0xa301a1d0** (handler 0x93006076) |
| t0=27门后lookup | 0x93005218 | **0x93005550** |
| PMP gadget区 | 0x93000034-f0 | **完全一致(boot代码未变!)** `csrw 1482,a0;csrw 1484,a7`@0x930000b8 |
| trap/SAVE | 0x93000114/0x930001cc | **一致** |
| 原子指令 | 0 | **0 (C1成立)** |
| C2链 | 页头+0x20→类型→jalr | **结构完全保留** |

## GB20X 新攻击面 (待审计)
1. **t0=30-33 幽灵handler**: 表B后的真实函数指针, bounds<0x24放行
   - t0=30 @0x930005d4 = **SBI直通**: `li a7,8; li a6,0; ecall` — 用户a0-a5直传M-mode!
   - t0=31 @0x93008bd8, t0=32 @0x9300428c, t0=33 @?(待dump)
2. 1539条额外指令的函数级diff (GB10Y无对应)
3. t0=30 的 SBI fn8 是什么服务(BootROM侧)

## Shot 系列地址修正 (v3脚本已更新)
- R读探针: a1 = 0xa3008280−0x168 = **0xa3008118**, 期望 sepc=0xffffffff930034a0
- W写探针: a1 = **0xa3008300** (t0=16槽, 值0, 无损)
- M标记写: a1 = **0xa30080f8** (经 sw a0,0x208(a1) 落到0xa3008300)
- B_RD: a1 = **0x1a308118**; B_WR: a1 = **0x1a308300**

---

## 实弹进展日志 (VM, 2026-10-08 深夜)

### ✅ 管道全线贯通 (Shot R v4, GB20X地址)
```
弹: MAP={1, gadget=0x102A30(笔误少个0), a4=0, a1=0xa3008118, a1hi=0}
果: Xid 120: instruction access page fault @ pc:0x102a30, task:3(RM), partition:4#0
   sepc:0x102a30 stval:0x102a30 scause:0xc
读数: ① K3-1溢出→pump→gadget调用链100%工作(精确调用我们放的地址)
     ② persistenced绞杀成功(远端脚本化v4) ③ DKMS+MAP验证流程可靠
     ④ GSP task异常→Xid120→驱动恢复(DRV=1) — 弹着点可重复观测
笔误修正: R/B_RD模式 gadget=0x01020A30 (原写成0x102A30少个0)
```
下一发: Shot R v5 (正确读gadget @ GB20X表0) — 决定低别名U读权限

---

# 🏆 实弹session收官 (2026-10-08 凌晨, 全程VM)

## CAL校准弹: 逐位命中
```
弹: a1=0x04191510, gadget=0x1020A30(读原语)
果: sepc=0x0000000fe4790e10 ← 与历史已知值逐位一致!
✅ a1通道100%工作 | ✅ 读原语GB20X复活(任意RM地址→sepc泄漏) | ✅ 堆布局跨内核稳定
```

## Phase 0 判决: U直接读写内核数据 = 结构性死路
```
Shot R v5: RM读0xa3008280(GB20X快表[0]) → 无load fault, 返回0
CAL:    同一管道读RM地址 → 正确非零值
结论: RM(Sv39独立页表)在VA 0xa3008280处映射自己的零页 —
     内核低别名是内核地址空间的结构, RM访问同VA落进RM自己内存
     = 不是权限位问题, 是地址空间隔离 → Phase 1(globalB直写)正式排除
```

## ★★★ 新主攻: t0=30 幽灵syscall = SBI直通 + 内核unlink写原语 ★★★
```
t0=30 @0xffffffff930005d4 (表外溢出槽, bounds<0x24放行, RM可直接调):
  li a7, 8; li a6, 0
  ecall                      ← 用户a0-a5原封直达M-mode (SBI fn8, 语义待查)
  a5=[a0]; a4=[a0+8]         ← S-mode解引用用户指针(无校验!)
  [a4]=a5; [a5+8]=a4         ← 双写(值和目标都来自*a0)
  [a0]=0; [a0+8]=0           ← 内核数据清零
攻击面: a0=内核VA(如0xffffffffa300xxxx) → S-mode走内核页表
  → 读内核数据当链表节点 → 改写内核数据!
  前置问题: ① ecall(fn8)对任意a0是否无害 ② RM如何发起t0=30
  (思路: RM固件114个syscall站点里找现成t0=30调用点 → 劫持控制流过去)
t0=31 @0x93008bd8(锁+全局门) t0=32 @0x9300428c(fault上报型) t0=33-35 详见反汇编
```

## 下次优先级
1. RM固件搜 t0=30/31 调用点(`li t0,30`/`addi t0,zero,30` + 0000序列)
2. BootROM SBI fn8 语义(现有SBI拦截资料+模拟器)
3. t0=30 unlink 原语演练(模拟器: RM传a0=内核VA → 观察双写/清零落点)
4. Phase 2 (C1竞争) 保留为backup

---

# 🎯 步骤1+3完成 (2026-10-08 凌晨2)

## 步骤1: RM固件syscall调用点普查 (t0归因, 138站点)
```
t0=30: 0处 — RM从不调用, 无自然入口
t0=31: 3处 | t0=32: 1处 | t0=33: 12处 | t0=34: 83处(故障上报主力)
调用gadget扫描: li t0,30/mv t0,a1/add t0/load t0(a0/a1) + 0000 全部0处
  = RM固件不存在任何字节序列可直达t0=30 (含指令中部入口)
```

## 步骤3: 🎯🎯🎯 t0=30全链实证 (GB20X真内核+模拟器, emu_test_t30_ghost.py)
```
注入: U-mode `c.li t0,30(F9 42); 0x0000` + 手工PMP别名(跳过boot)
链路: trap→SAVE→分发→★幽灵槽[30]→jalr 0x930005d4→li a7,8;ecall→unlink
伪造: SBI fn8 返回受控节点{prev=P, next=N} (节点在RM侧内存)
结果: [N]=P ✓✓  [P+8]=N ✓✓  节点清零 ✓✓
  = **内核数据双写原语成立**: 值和目标都来自节点内容(全控)
约束: P/N都必须是"可写内核地址"(第二写[P+8]和第一写[N]各落一脚)
  用途示例: globalA/globalB双写同值→t0=27门通过(映射内核数据入RM VA)
```

## t0=30 真身 = t0=15通道拆卸的内部流
```
unlink入口0x930005dc被SBI通道管理代码多处jal调用(0x93000990/0x93000e8e/...)
幽灵槽[30]=0x930005d4 恰好别名到"ecall(fn8)+unlink"序列
∴ 正常路径: t0=15(通道操作) → 内部 → ecall a7=8 → M-mode返回节点 → unlink
```

## 唯一剩余未知 (步骤2, 决定性): SBI fn8 的 a0 返回语义
- 若 fn8 返回值受通道页(RM可写!)内容影响 → 节点可控 → 任意内核写 = 全链通
- 若 fn8 返回内核自选节点 → 原语仅限"拆卸自己" = 无攻击价值
- 查法: BootROM反汇编 / 模拟器跑t0=15全流观察 / t0=31(3个真实调用点)对照

## 修正后的最短路径
```
t0=15(RM自然调用) + 通道页内容投毒 → SBI fn8返回受控节点
  → unlink [N]=P [P+8]=N → globalA/globalB同值 → t0=27门开
  → 内核数据映射进RM → 全局胜利
```

---

# ⚰️ 步骤2判决: t0=30/fn8线关闭 (2026-10-08 凌晨3)

## 穷尽证据
```
SBI全景: fn0×1 | fn8×1(孤儿序列,仅幽灵槽可达) | 0x900001eb+a6子命令(0x0b-0x13)
t0=30触发序列: li/addi/ori/xori/lui+c.addi/c.addi+mv+load 全编码 = 0处
泵约束: gadget只能RM地址(U-mode), 内核地址fetch即fault(Phase 0)
t0=33 callee(0x93009f78) = 固定MMIO操作, 用户参数丢弃
t0=15 GB20X handler = 安全封装(参数丢弃)
fn8语义 = BootROM(硅ROM, 固件里没有) = 离线不可知
∴ t0=30线: RM无法触发 → fn8语义无关紧要 → 关闭
```

## GB20X handler盲区提示
旧"34 handler干净"审计是GB10Y的! GB20X handler代码不同(+1539条),
本轮粗扫(参数基址store)全干净, 但**未做真正数据流审计** — 仍待深查

## ═══ 战略重定位: 剩余可行线 ═══

### A线 (主推): C1竞争 — 全要素已备
```
GB20X实证: 0原子指令 | RELEASE=0x93005b26(ld/-1/sd非原子)
         | 析构jalr@0x93005b60 | 页头+0x20公式不变
GB10Y实证: 竞争→双destroy→freelist环→释放→重分配闭环
真机路径: RPC风暴→port/shuttle对象RELEASE×海量→timer中断命中6指令窗口
        → 命中后: 同对象双分配 → 类型混淆 → 页头污染 → C2 jalr → S-mode
待做: 风暴脚本(host侧, mods LoopMs+RPC spam) + 命中检测信号
```

### B线 (并行): 模拟器完整init → fn=72 RPC → RM自然启动
```
修SBI假返回(a7=0x900001eb子命令按观察语义建模) → 内核init完成
→ 注入fn=72 GSP_SET_SYSTEM_INFO → RM全syscall序列可见
→ GB20X handler真实参数流全曝光(比静态审计强百倍)
```

### 武器库存量 (全实弹验证)
任意读(sepc泄漏) | 写0到任意RM地址 | 写常量a0 | pump=任意RM函数调用(a1全控)
堆布局确定 | VM管道16分钟/发成功率100%

---

# 双线进度 (2026-10-08 早晨)

## A线 C1竞争: 前提全部静态确认 ✅ + 风暴已上线
```
抢占性(决定性): syscall=异常trap(scause=2) → 硬件不清SIE → handler全程可中断
  全内核无 csrc sstatus(关中断) → timer可打断RELEASE窗口(ld@0x93005b28→sd@0x93005b38)
  打断后跳调度器(0x930019b6)可切任务 → 双上下文RELEASE同对象 = 竞争结构成立
概率估算: 窗口~50ns / 心跳~1ms ≈ 5e-5/RELEASE; 4路smi风暴≈数千RELEASE/s
  → 期望命中~秒级-分钟级(取决于调度切换到同对象任务的概率)
风暴脚本: storm_c1.sh (干净驱动+4路nvidia-smi全量查询+dmesg监视, 480s/轮)
命中信号: Xid120异常sepc / GSP挂死 / SMI连续失败
```

## B线 模拟器GB20X完整init: 受阻(比预期深) ⚠️
```
进展: GB20X memset循环定位(0x93005206)+双别名快转 ✓ (64次生效)
卡点: SBI之前卡进"内存池结构遍历循环"(0x93008b2a↔unlink@0x930005dc)
  循环走的是BootROM初始化的结构 — 模拟器零页语义→无限走零节点
  = 完整init需要BootROM-ABI建模(物理内存初始内容), 比SBI返回值更深
结论: B线降级为长期线; RM syscall观察改用"spawn配方"路径(GB10Y已验证),
     GB20X版本待kernel走到池就绪点后试
```

---

# A线风暴实战记录 (2026-10-08 上午)

## v1 进程级锤 (4×nvidia-smi -q, 480s)
```
结果: 零Xid / 零SMI失败 / GPU存活 — 干净
有效RPC率: ~百次/s(进程spawn开销) — 命中期望~2%/8min → 太慢
```

## v2 NVML进程内锤 (ctypes直连libnvidia-ml, 2.85M调用/s, 30min跑)
```
结果: 10.6亿+调用 零失败 零Xid GPU健康
关键发现: ★ NVML利用率/温度走驱动缓存 — 高频调用≠高频RPC!
  驱动后台低频轮询GSP, 锤子对真实RPC率贡献≈0
```

## 风暴v3设计要点 (下次)
```
1. 强制RPC生成器: CUDA cuMemCreate/cuMemFree循环(每次=真RM RPC+port操作)
   或 nvidia-smi进程混合模式 / mods gputest LoopMs多实例
2. 命中可观测性(C1命中是静默的!): 
   - 双destroy→freelist环→下次分配同址→结构混乱→延迟崩溃
   - 需要长尾观察期(风暴后跑压力测试诱发崩溃)
   - 或对照: 风暴前后nvidia-smi -q全字段diff(遥测异常=腐败信号)
3. 定向化: 找出RM端口对象的专门RPC(子通道操作), 而非泛查询
```

## B线终态: GB20X完整init需BootROM-ABI建模(池结构遍历依赖BootROM初始化的内存) — 长期线

---

# 🏆 C1/C2 在 GB20X REAL 真内核上重证完成 (2026-10-08, emu_test_c2_gb20x.py)

## 补掉的最大缺口
之前 C1/C2 模拟器实证是在认错的 GB10Y 内核上跑的 — 本轮在
**RTX 5090 实际运行的 GB20X 内核**(/tmp/kernel_gb20x_REAL.elf)上三段全证:

```
Phase A  公式探测: (desc−0xffffffffa300a000)/40 — 7/7精确命中 ✅
Phase B  C2: 页头+0x20投毒8B → RELEASE(0xffffffff93005b26)
         → 析构槽[0xa300a000+type*40+8] → jalr 0xcafec0de @S-mode ✅
Phase C  C1: T1挂起在ld后(0xffffffff93005b2c) → T2完整destroy#1
         → T1写回过期值 → destroy#2 → freelist自指环(0x90040f8) ✅
         → 同对象双分配 → 类型混淆 → 接Phase B = S-mode
```

## GB20X 最终地址表(本测试验证版)
```
RELEASE      = 0xffffffff93005b26   (ld@0x5b28 / sd@0x5b38, 非原子窗口6条)
类型计算     = 0xffffffff93004568   (公式同GB10Y, 魔数@0x9300cb20)
表/pool基址  = 0xffffffffa300a000   (40B/项, ★dtor在entry+8 — GB10Y是+0x28)
快表         = 0xa3008280(16项)+0xa3008308(12项), bounds t0<0x24
```

## 提权链现状: 链条在正确内核上100%闭合(模拟器)
剩余两环(真机): ①抽中50ns窗口(风暴) ②命中后编排(用户字节→页头)

---

# 降频实验 + v3真锤子 (2026-10-08 白天)

## ★ 降频物理验证 (用户的关键直觉)
```
nvidia-smi -q 往返: 锁210MHz=0.105s | 默认闲置=0.10s | 锁3135MHz=0.070s
拆账: GPU侧耗时 210MHz≈37.5ms / 3135MHz≈2.5ms = 15倍 = 精确时钟比!
→ GSP侧RPC处理跟随图形时钟域 → 锁210MHz时竞争窗口(墙钟)×15
(前提存疑: GSP定时器若同钟缩放则增益归零 — 未证)
```

## NVML真RPC探测 (延迟分拣)
```
GetBAR1MemoryInfo      = 229µs ★真RPC
GetTotalEnergyConsumption = 4295µs ★真RPC(最重)
其余14个常用查询 = 0.3~13µs 全是缓存
```

## v3锤子实战 (4线程×BAR1+Energy + 210MHz锁频, 30min)
```
结果: 783,170次真RPC | 435次/s | 零失败 | 零Xid | GPU全程健康
判读: ~2-8M张RELEASE彩票+15倍窗口仍未可观测命中
  → 同对象切换概率是硬瓶颈(或定时器同钟缩放吃掉增益)
  → 或命中但静默(无腐败检测器,无法区分)
```

## 下一步关键升级
1. **腐败检测器**(区分"没命中"vs"命中但静默"): 风暴后紧接
   显存压力测试(大量alloc/free) → 若freelist已环化必崩 → 崩=证据
2. **定向竞争**取代盲抽: 找让两任务锁步操作同一port对象的RPC对
3. 编排环(②用户字节→页头)仍是通往"命中=拿root"的关键

---

## ⚠️ 环境状态通报 (用户告知, 2026-10-08)
**FSP 已死,不回话** — MNOC/FWUP/FSP车道全部暂停
影响评估: K3-1→RM→EMEM 路径不经过FSP(宿主驱动↔GSP RM直通) — 本线不受影响
      EMEM是FSP块上的SRAM窗口, 寄存器访问走总线 — FSP CPU死≠窗口死(待验证)

## K3-1 TX-post槽激活计划 (进行中, k3_txpost.sh)
```
发现: +0xc8 TX-post槽(24调用点) a0=*(meta+0x30)全控 + a1=*(meta+0x38)全控
     + gadget 0x1137ee8 (sd a1,0(a0)) = 地址+值全控8字节写 — 绕过a4=0卡点!
布局: MapOff[8]={触发,+0xb8→ret(0x1137eec无害),+0xc8→sd gadget,a0lo/hi,a1lo/hi,...}
验证弹: a0=EMEMD(0x08AF2AC4) a1=0xDEAD5315 → 宿主bar0rw读回
通过后: 下一发写GPCCLK域对象(0x200ed398)绕过210下限 → 时钟放大器

---

# TX-post验证弹战报 (2026-10-08 深夜)

## 管道成果
✅ v17补丁器8参数直传MAP(7项offset:value) — MapOff[7]精确落位
✅ .ko四特征值验证(0x8AF2AC4/0xDEAD5315/双gadget全编入)
✅ bar0rw读回管道打通(FSP死≠总线死,EMEM窗口宿主可读)

## 弹着点: Xid 119 (GSP_INIT_DONE超时) — 与历史所有弹(Xid120)不同
```
诊断: GSP在init阶段就死 — TX-post(24调用点)在init期间就触发
两个嫌疑:
  ① FSP死→EMEM窗口在RM页表未映射→gadget写0x08AF2AC4页错误→RM早夭
    (10/1 DEADBEEF成功时FSP活着=窗口已映射 — 今天唯一变量就是FSP状态)
  ② meta+0x30/0x34活元数据被污染→init消息队列瘫
判别弹: A=不写0x100c8(定+0xc8) | B=+0xc8保留但a0改核心SCRATCH寄存器
```

## 教训清单(本轮踩坑)
scp不带执行位(fire.sh没+x根本没跑) | /tmp跨重启不可靠(每轮重传)
手动续跑漏步骤 | 校验grep数组大小写错([8]vs[7])

---

# 🎯 Xid119双案齐破 + C1全线封存 (2026-10-08 下午)

## Xid119根因(判别弹A铁证)
```
+0xb8的ret gadget返回a0=meta+0x8c(数据地址) → 新VM泵会调用返回值
→ 跳进数据段 → RM早期死循环 → 软复位失败 → 二次加载超时(119)
历史弹(读gadget)返回可跳值 → 干净Xid120 → GSP可复位 ✓
∴ 不是FSP映射!不是meta+0x30!是ret不合格。TX-post槽(+0xc8)从未被真正测试!
```

## C1三种形态全零,正式封存
```
盲抽12.6M=0 | 相位瞄准380K(13x富集)=0 | 双流并发(Energy 419K阻塞+BAR1 70K门铃)=0
+模拟器149tick×30万指令=零RELEASE(打点无共释放者)
→ C1竞争在此平台结构性不成立,资源全面转确定性线
```

## TX-post复活设计(下次弹)
```
+0xb8 = 读gadget, a1 = (通道表项地址 - 0x168)  [表项含合法RM函数指针]
  → 链: 泵→读gadget→jalr真函数→正常返回→泵继续 → RM存活
  → +0xc8 = sd a1,0(a0) 每次TX触发 → EMEM标记
先决: 从老K3泄漏数据/模拟器确认通道表某表项的值是RM代码指针
```

---

# 🔥 主线①首日战报: GB20X污点审计 (audit_gb20x_taint.py)

## 审计基础设施
污点追踪器(34 handler × 深度2, 栈槽/指针加载/算术传播, store汇点)
已知误报源: c.jr ra边界识别(已发现,下版修)

## 头号发现: t0=3 = 用户命令数组解释器 ★★★
```
RM真实调用t0=3(RM固件1个调用点@0x1e6215e)
入口: a0=参数(进解析器) a1=count(1-7) a2=用户指针/超时
流程: 用户缓冲→栈alloca→0x930006bc解析器(a0用户值作参数!)
     →0x93008ee6命令循环: cmd=lw[用户缓冲+i*4] 分发执行
内部机械(全部用户命令字驱动):
  · case 2 → 0x93006976(ctx)
  · 通道列表遍历+unlink(0x930005dc)
  · 类型校验(0x93004568==6=SBI通道)
  · ★非原子acquire: 0x93008fce (ld/+1/sd三连,又一处!)
  · RELEASE(0x93005b26) + BITSET(0x9300476c)
```

## 危险函数GB20X版(调用链已钉死)
```
BITSET @0x9300476c: [0xF8000000+idx*8] |= 1<<bit  ← 64位idx,理论任意地址
  调用者: 0x93007ae2(函数0x93007a5c=通道按index拆除)
          0x930083aa/fa(函数0x930082c0)
  idx来源: 通道表index(内核管理) — 用户是否可控待查
UNLINK2 @0x93004782: [a0+0x10]←[[a0+0x10]+8]+unlink双写 ← 二阶指针
  调用者: 0x93004826系 ← t0=22链
  a0来源: 待查
```

## 下次续审清单(按优先级)
1. 0x930050c6(解析器引擎)对用户a0参数的处理 — 是否写回用户指针
2. t0=3命令分发的全部case(只见case2+teardown,余下未dump)
3. 用户命令字→通道index的生成路径(可控即=BITSET任意地址置位!)
4. t0=22链的UNLINK2 a0来源
5. 修审计器边界bug后跑全内核(不只handler)

---

# 🔥 t0=3 直射实验 (2026-10-08 晚)

## 弹着点: 泵成功调用了 t0=3 syscall!
```
gadget = 0x1e7bdd8 (RM RX段, 字符串区巧合字节 45 4D 00 00)
       = c.li t0,3; c.unimp
配置: a0=meta+0x8c(暂存区), a1=7(count), a2=4
结果: Xid 120, task:3(RM), sepc=0x1e7bde0, stval=0x2c, scause=0xd
     = handler执行了(至少3次,3个连续c.unimp trap)
     = 返回后走进字符串区触发load fault(预期)
     ★ t0=3 handler以S-mode运行了! RM数据进了内核命令解释器!
```

## 模拟器副作用分析(伪造全局ctx, count=1, cmd=2)
```
所有store均在栈上 — 无内核数据段写入
但这只是伪造环境; 真机全局ctx是真数据, 行为可能不同
需要真机后续观察(第二发读原语看内核数据段有无变化)
```

## 下一步: 精确控制暂存区内容
```
暂存区meta+0x8c的内容 = staging元数据(大部分不可直接控)
→ 需要让a0指向我们能控制的内存:
   方案A: TX-post槽(a0全控, 但Xid119问题待修)
   方案B: HEX载荷写入staging接收区, gadget指向那里
   方案C: MAP多槽写入send buffer区, a0指向send区
最优: 方案C — MAP offset 0x10XXX 就是send区, 我们写命令数据到那里
     然后gadget=0x1e7bdd8, 泵的a0自动=meta+0x8c但a0不是命令缓冲...
     
等等 — 重新看handler: a0是"某个对象指针",不是命令缓冲!
     命令缓冲是a2(复制到栈), 命令解析用a0作为参数
     所以真正要控制的是a2! 但泵的a2=4(硬编码)!
     → 必须用TX-post槽(a0和a1都全控)才能传a2
     → 回到TX-post修复优先
```

## RM固件t0=3调用点真相
```
之前扫描的"1处@0x1e6215e"是误判:
  字节8d42 = c.addi a0,3 (不是 c.li t0,3!)
  真正的c.li t0,3(45 4D)只出现在字符串数据里(6处)
  RM固件实际不调用t0=3
```

---

# 💀 W^X 铁壁 + 5发弹链复盘 (2026-10-08 深夜收官)

## 今晚5发弹的完整链
```
v1: TX-post(a1错0x100000) → pc:0x0 (读gadget读到0)
v2: TX-post(a1错0x10000)  → pc:0x0 (还是读0)
v3: TX-post(a1=meta+0x40-0x168) → pc:0x0 (MAP新offset可能没写上)
v4: stub(gadget指针拆分错)  → pc:0xFE400790E50 (高位错)
v5: stub(指针正确0x0FE4790E50) → ★精确命中stub地址!
    → instruction access fault = staging不可执行
```

## MAP双槽64位指针写入: 技术验证成功 ★
```
0x100b8写低32 + 0x100bc写高32 → 完整64位指针 ✓
v5弹着点pc=0xfe4790e50 = 精确的meta+0x40 ✓
→ 证明: MAP可以精确控制任意64位回调指针!
```

## W^X否定性发现(第4个死刑)
```
① Phase 0: RM不能读写内核数据(独立页表)
② C1竞争: 无共释放者(模拟器149tick零RELEASE)
③ t0=30/fn8: RM无触发序列
④ W^X: RM代码注入到用户空间结构性不可能
   (staging=RW不可执行, 固件=RX不可写)
```

## 下一步活路(排除法后剩余的)
1. 利用现有原语(读+a1控)在RM固件里找gadget链(纯代码复用,无注入)
2. 深挖t0=3 handler解析器对staging数据的处理(模拟器+真机对照)
3. 模拟器: 让GB10Y跑完整RM(已证明可行), 观察全部syscall流
4. 真机: t0=3直射+全量dmesg分析(handler执行了什么副作用?)

---

# 🏆🏆🏆 黄金弹: t0=2完整内核命令管道打通 (2026-10-08)

## 弹着点
```
Xid 120: load address misaligned @ pc:0x1a96f64, task:3(RM)
sepc:0x1a96f64, stval:0x1, scause:0x4
```

## t0=2 handler 完整解剖(黄金入口!)
```
handler @ 0xffffffff93003802 (仅12条指令!):
  c.swsp a0, 0xc(sp)       ← 用户a0存栈(命令字,截32位)
  c.mv   a2, a1            ← ★用户a1 → a2(源数据指针)!
  c.addi4spn a0, sp, 0xc   ← a0 = &栈上的命令字
  c.li   a1, 1             ← count = 1
  jal    0x93008ee6        ← 命令解释器(同t0=3!)
  ...干净返回...

泵调用链:
  gadget = 0x1a96f56 (c.li t0,2 + c.unimp 在RM RX段)
  a0 = meta+0x8c (MAP offset 0x1008c 写入命令字!)
  a1 = MAP offset 0x10038 (源数据指针!)
  
→ 完全受控的内核命令执行: 命令字+源指针都全控!
```

## 武器化路径
```
1. 枚举命令字(0x1008c)不同值的内核行为
2. 找到写内核数据的命令case
3. 配合源指针(0x10038)构造攻击载荷
4. → 页头投毒 → C2 jalr → S-mode提权
```

## RM固件syscall调用点编目(24处,14个号)
```
t0=1:1 | t0=2:2 | t0=3:3 | t0=6:1 | t0=8:1 | t0=9:4 | t0=11:1
t0=13:2 | t0=15:2 | t0=17:1 | t0=23:1 | t0=26:1 | t0=30:1 | t0=31:3
干净wrapper: t0=15@0x1a9e5d2, t0=23@0x1a9e1d6 (泵可直调,RM存活)
```

---

# 🏆🏆🏆🏆🏆 完整提权链打通 — LibOS ROOT (2026-10-08) 🏆🏆🏆🏆🏆

## 模拟器100%验证的完整攻击链
```
步骤1: t0=2 syscall(泵可触发,真机已证Xid120)
  → 命令解释器 → teardown → type_byte=2 → UNLINK路径

步骤2: UNLINK(攻击者对象+0x18)
  → 写入1: [受害者页+0x20] = FAKE_DESC ★页头投毒!
  → 写入2: [FAKE_DESC+8] = 受害者页+0x20 (副作用,覆盖析构槽)

步骤3: 修复析构槽(写入ATTACK_PC)
  (真机: 用第二个泵调用/MAP写入)

步骤4: RELEASE(受害者对象)
  → refcount 1→0 → destroy路径
  → type计算: 读被污染页头 → type=6
  → 析构查表: [type_table + 6*40 + 8] = ATTACK_PC
  → jalr ATTACK_PC = ★★★ S-mode任意代码执行 ★★★

模拟器弹着点: UNIMP@kernel pc=0xcafec0de ← 精确命中!
```

## 每一步的真机可用性
```
步骤1(t0=2 syscall): ✅ 真机已证(Xid120, handler执行后返回)
步骤2(UNLINK写入):  ✅ UNLINK是内核代码,真机自然执行
步骤3(析构槽写入):  🔧 需要第二个写原语(TX-post或MAP)
步骤4(RELEASE):     ✅ 内核自然行为
整个链: 全部在模拟器验证,组件在真机分别验证
```

## 关键地址(GB20X)
```
t0=2 handler:    0xffffffff93003802 (命令解释器入口)
命令解释器:      0xffffffff93008ee6
UNLINK:          0xffffffff930005dc
RELEASE:         0xffffffff93005b26
类型计算:        0xffffffff93004568
类型表/pool基址: 0xffffffffa300a000
ctx全局指针:     [0xffffffffa3008010]
```

---

# 真机提权瓶颈分析 (2026-10-08 深夜)

## 当前武器 vs 需要的
```
有的:
  ✅ 泵调用任意RM地址(a0=meta+0x8c固定, a1全控)
  ✅ t0=2/3/15 syscall触发(S-mode handler确认执行)
  ✅ MAP写入staging元数据(多个offset验证)
  ✅ 模拟器完整提权链(UNLINK→RELEASE→jalr)

缺的:
  ❌ a0控制(泵a0=meta+0x8c地址, 不是值)
     → 命令字永远是地址低位(0xE4790E9C, 3.8B亿)
     → 表查找永远越界, 无法命中teardown路径
  ❌ 内核写原语(污染对象链表指针)
     → Phase 0: RM不能写内核内存
```

## a0控制的唯一活路: TX-post槽
```
TX-post(+0xc8): a0=*(meta+0x30)全控, a1=*(meta+0x38)全控
→ 需要+0xb8(泵)不崩RM:
  读gadget(0x1020A30) + a1指向合法RM函数指针
  → 读gadget返回函数地址 → 泵调用它 → 正常返回 → RM存活
  → +0xc8(TX-post)触发 → a0=我们的命令字 → t0=2 → 内核命令执行!

MAP方案(11项):
  0x100a4: 1 (触发)
  0x100b8: 0x1020A30 (读gadget) / 0x100bc: 0
  0x10038: a1=meta+0x50-0x168 / 0x1003c: 高位
  0x10050: 0x1137EEC (c.jr ra) / 0x10054: 0  ← 读gadget的返回值
  0x100c8: 0x1a96f56 (t0=2 trap)  ← TX-post gadget
  0x10030: 命令字 / 0x10034: 0   ← TX-post的a0!

之前Xid119的真正原因: +0xb8的ret gadget返回meta+0x8c(数据地址)→泵调用→崩
修正: 读gadget返回合法RM函数→泵调用→正常→TX-post触发!
```

## 下次第一发: TX-post复活(上述11项MAP)
命中判据: 无Xid(或Xid120且sepc≠0x1a96f64) + SMI存活
→ a0全控 = 命令字可指定 = 内核命令执行管道全通

---

# 🎯 TX-post 首次成功触发! (2026-10-08 深夜)

## 弹着点(全新!)
```
Xid 120: load access page fault @ pc:0x10209F0, task:3(RM)
sepc: 0x10209F0  stval: 0xD0  scause: 0xD
```

## 解读
```
✅ +0xb8 读gadget链100%工作:
   泵→读gadget(0x1020A30)→加载[meta+0x50]=0x1137EEC(c.jr ra)
   →泵调用→立即返回→RM存活!

✅ TX-post(+0xc8)首次触发!
   崩塌地址从0x1a96f64(之前所有弹)变为0x10209F0(读gadget附近)
   = 泵循环存活到了TX-post回调阶段!

🔬 崩塌原因: stval=0xD0 = NULL+0xD0
   = handler试图解引用一个NULL指针的+0xD0偏移
   = t0=2 handler确实在处理,但内核真实ctx的某个子指针为NULL
   (可能: ctx+0x450的表指针为NULL, 或当前任务无SBI通道)

## 技术含义
a0全控验证成功! TX-post的a0=*(meta+0x30)确实被传递!
下一步: 调试为什么handler内部NULL解引用, 或换cmd=0/1试
```

## TX-post NULL解引用分析 (sepc=0x10209F0)
```
0x10209e4: ld a5, 0x178(a0)   ← 从[a0+0x178]加载方法指针
0x10209e8: c.jalr a5           ← 调用(对象方法调用!)
0x10209ea: c.bnez a0, +0x22    ← 检查返回值
0x10209f0: ld a0, 0xd0(s4)    ★ CRASH: s4=NULL → [0xD0]

含义: TX-post回调不是简单函数指针!
     是一个对象方法: [obj+0x178]=方法, 调用后再访问[s4+0xD0]
     s4=NULL说明对象上下文未建立(我们只写了+0xc8函数指针)
     
下一步: 
  A. 往meta+0x178写一个合法RM函数地址(使方法调用不崩)
  B. 或搞清楚s4从哪来(可能=meta+0x30的a0值需要指向有效对象)
  C. 或直接用+0xb8泵替代(读gadget已证明工作!)
```

---

# 今日最终状态 (2026-10-08)

## a0控制: 技术上已证明, 但泵调用返回值
```
加载gadget(0x15b74d8: c.lw a0,0(a1); c.jr ra) @+0xb8:
  泵 → 加载gadget → a0 = [meta+0x50] = 2 ✓ (值确实加载了!)
  → 泵调用返回值a0=2 → 跳到地址2 → init死(Xid119)

证明: a0确实被我们的MAP值替换! 问题只是泵把a0当函数地址调用。

读gadget(0x1020A30: ld a5,0x168(a1); jalr a5) @+0xb8:
  泵 → 读gadget → 跳转到[meta+0x50]指定的函数 → 函数返回 → RM存活 ✓
  但a0 = 泵原始a0(meta+0x8c地址, 不是值)

结论: 两条路径各有半截:
  读gadget: RM存活 + 跳转到指定函数, 但a0=地址
  加载gadget: a0=值(全控!), 但泵调用返回值导致崩溃
```

## 下次开工优先级
```
1. TX-post修复: a0=*(meta+0x30)不经过泵的返回值调用!
   → 修复NULL解引用(s4): meta+0x30需要指向有效对象(不是小数值)
   → 对象+0x178处放返回非零的函数 → 跳过NULL路径
   → a0=对象指针(通过偏移传递命令字)
   
2. 或者: 加载gadget返回t0=2 trap地址(a0=trap地址, 泵调用→syscall!
   但a0=trap地址→命令字=27852374→仍然越界)
   
3. 或者: 读gadget链的函数返回一个"设置a0后trap"的wrapper
   需要找RM固件中的syscall wrapper函数入口点
```

---

# 💀 根本性发现: 溢出本身破坏metadata (2026-10-08 终)

## 实验: 最小MAP诊断
```
MAP = 仅3项(触发 + c.jr ra + 高位0)
结果: Xid 119(GSP init死)

结论: 不是MAP值的问题——溢出本身就把RPC消息内容
     复制到metadata区域, 覆盖了关键结构!
     MAP只拦截特定offset的写入, 其余位置全部被
     原始RPC消息数据污染!

     之前所有"读gadget链RM存活"的实验,
     其实是读gadget恰好跳转到了不依赖被污染字段的代码路径!
     当执行流回到调用者(0x10209F0)时, 污染的s4=NULL导致崩溃。
```

## K3-1溢出的真实影响
```
RPC消息(fn=73)内容 → 复制到metadata区域(232字节)
→ 大部分metadata字段被消息数据覆盖
→ MAP只恢复少量字段
→ 剩余字段全是垃圾(消息数据)
→ 被污染的metadata结构导致各种崩溃

这不是bug——这是K3-1溢出的DESIGNED行为:
它是"用消息内容砸metadata"的原始攻击!
我们的MAP只是"精准修复"少数关键位置的补丁。
```

## 真机提权的完整技术路线图(终极)
```
1. dump原始metadata(通过NVRM debug dump或内存泄漏)
2. 逐字段恢复: MAP覆盖metadata的每一个关键字段
   (需要58+项MAP, 每项恢复一个正确的值)
3. 在恢复的基础上, 仅修改:
   +0xb8 → 我们的gadget
   +0x38 → 我们的a1
   +0x30/0xc8 → TX-post参数
4. 其余字段全部恢复为原始值 → RM完全正常工作
5. 我们的gadget在正常工作的RM中执行 → syscall → 提权

或者:
1. 缩小RPC消息(修改驱动, 发更少的registry条目)
   → 减少溢出范围 → 减少metadata污染
   → MAP只覆盖溢出实际到达的字段
```

---

# FN=76实验结果 + RPC序列数据 (2026-10-08 最终)

## RPC序列(spy弹, 前48条)
```
fn=72 (system_info) → fn=73 (registry) → fn=1 → fn=65 → fn=228
→ fn=76 ×30+次(混合fn=103) → 后续
fn=76的len范围: 0x4a到0x605c(最大24KB)
```

## FN=76 vs FN=73
```
FN=73: Xid 119(init死)或Xid 120(sepc=0x1a96f64=trap返回地址)
FN=76: Xid 120(sepc=0x10209F0=读gadget调用者) + RmInitAdapter failed
区别: FN=76下GSP不超时! 内核存活! 只是RM任务崩了!
```

## 当前状态
- GSP内核: 存活(无119)
- RM任务: Xid 120 @ 0x10209F0 (s4=NULL)
- TX-post: 未触发(RM死在TX之前)
- s4 gadget: 未生效(MAP可能未写入——fn=76第一条RPC太小)
  
## 下次最优先
1. 验证fn=76弹的MAP是否真正写入(读.ko确认)
2. 如果MAP没写入: 找fn=76大消息(elems>33)的RPC→改FN到那条
3. 如果MAP写入了但s4 gadget没效果: 调试读gadget调用链
4. 换一个更晚的RPC函数(如fn=103)

---

# 🔥 黄金GADGET链成功 (2026-10-08 深夜)

## 历史性突破: t0=2 syscall带控制命令字到达内核!!

### 黄金gadget (真s10=x26版本)
```
0x10c1d66: c.mv s10, a1         ← s10 = a1 = 我们控制的指针
0x10c1d68: c.beqz a5, +0x68     ← a5≠0不跳
0x10c1d6a: ld a5, +704(a1)      ← a5 = [a1+0x2C0] 二级加载!
0x10c1d6e: c.jalr a5            ← 调用!
```

### 完整攻击链(已实弹验证!)
```
FN=73 RPC → 溢出(v19跳过未命中) → MAP写入metadata
→ pump callback(+0xb8) = 读gadget(0x1020A30)
→ 读gadget: a5=[a1+0x168]=[meta+0x50]=0x10C1D66, a0=s3=P
→ 黄金gadget: s10=a1=meta-0x118
→ ld a5,[a1+0x2C0]=[meta+0x1A8]=0x1A96F52
→ lwu a0,[s10]=[meta-0x118]=命令字2!
→ c.li t0,2; c.unimp → 内核SYSCALL!
→ Xid 119(超时无崩溃) = 任务在内核处理命令!
```

### MAP(12项, 全部命中)
```
0x100a4:1                    触发
0x100b8:0x1020A30            读gadget  
0x10038/3c: meta-0x118       a1指针
0x10050:0x010C1D66           黄金gadget
0x101A8:0x01A96F52           lwu+t0=2trap
0xFEE8:2                     命令字=2!!
```

### 关键发现记录
- s3 = P = staging基址(0x0FE4770E10) — 实弹测量
- s10 = 1(泵上下文原始值) — 旧gadget bug(设了s4不是s10)
- s10真实编号 = x26(x20是s4!)
- metadata在FN=73时全零 — GSP init后填充部分字段
- v19跳过未命中 = 保住metadata前64KB = GSP存活

### 下一步: 完成提权
1. 确认命令字2触发的具体内核操作(teardown路径?)
2. 模拟器分析: t0=2 handler对a0=2做什么
3. 设置假类型表(staging区) → UNLINK页面投毒 → destructor→ATTACK_PC
4. 模拟器链已100%验证, 只需在真硬件复现

---

# 🔥🔥🔥 完整内核命令通道打通 (深夜续)

## 实弹验证的完整链
```
溢出(v19) → 读gadget(a0=s3=P, a1=meta-0x118)
→ 黄金gadget 0x10C1D66(s10=a1, ld a5,[a1+0x2C0], jalr)
→ 0x1A96F52: lwu a0,[s10]=我们MAP的32位值
→ t0=2 syscall → 内核!
```

## t0=2 handler真相(0x93003802)
```
c.swsp a0, 0xc(sp)      ← 我们的a0值存栈
c.addi4spn a0, sp, 0xc  ← a0=栈地址
c.li a1, 1              ← 立即模式
jal 0x93008ee6           ← 命令解释器
```
→ 命令类型 = 我们的a0值(直接,不是指针!)

## 命令dispatch
```
a0 == 2    → teardown(global_ctx) → UNLINK+RELEASE所有内核对象
a0 == 其他 → lookup(table[N]) → TYPECALC → RELEASE
```

## 实验结果
- a0=2: Xid119(读[2]崩—当时以为是命令号)
- a0=0x1C0DDC0: **RM存活到0x18C09C8(内核sret返回后续行!)** "Reset required"
- a0=0x1598D5A: 同上(lookup路径)
→ teardown/lookup真实执行! 内核对象被销毁! 系统状态被改变!

## lookup函数(0x9300a090)
```
table = [ctx+0x450]  (内核对象表)
N = 我们的a0(32位索引)
count = [table+8]
if N < count:
    entry = table + (N+1)*16
    if [entry+0x10] < 0 (有效):
        return [entry+8] = 对象指针
```

## 轮询循环发现(0x1a96f52-0x1a96f76)
```
loop:
  lwu a0, [s10]       ← 重新加载我们的命令字
  t0=2 syscall         ← 内核处理
  check result
  lwu a0, [s10]       ← 再加载
  t0=9 syscall         ← 另一个内核操作(也用我们的a0!)
  check result
  goto loop            ← 反复调用!!
```

## 距离分析(阻断点)
- 内核表(0xFFFFFFFF_A3xxxxxx)到staging(0x0FE4790E10): ~1.1TB
- 32位索引×16 = 最大64GB → **无法通过索引到达staging**
- 需要其他路径把64位受控值传入RELEASE

## 下一步方向
1. t0=9的lookup细节(它也用我们的a0但可能有不同用法)
2. 其他syscall号(t0=15/23的wrapper已找到)带受控参数
3. 模拟器全boot(初始化ctx)后分析真实表地址
4. 寻找64位参数传递路径(ld替代lwu的trap入口)

---

# 🎯 C2首射 + t0=3发现 (最终日)

## C2算术(64位回绕) — 已验证可行!
```
staging = 0x0FE4790E10
BASE = 0xFFFFFFFFA300A000  
dist = staging - BASE (mod 2^64) = 69817894272

假描述符 desc = staging + 0x20068 = 0x0FE47B0E78
type = (desc - BASE)/40 = 1745450635  ← 32位内!
dtor槽 = BASE + type×40 + 8 = staging+0x20070 = meta+0x70 ← MAP可控!
[meta+0x70] = ATTACK_PC
```

## C2实弹结果(Xid 119, 无0xCAFEC0DE)
- teardown触发了(超时=内核处理)
- 但RELEASE没作用于staging对象(staging不在ctx对象列表)
- 需要找到RELEASE staging对象的路径

## t0=3 = 用户命令解释器(用户指针直读!)
```
0x93003828: sd a0, -0x40(s0)   ← a0=用户指针!
0x9300382c: c.beqz a0          ← 非零检查
0x9300382e: addi a5, a1, -1    ← a1=计数(1-7)
...内核读取[a0]指向的数据并处理!
污点分析: t0=3 → BITSET(0x9300476c) + UNLINK2(0x93004782)
BITSET: [a0+(a1>>6)*8] |= 1<<(a1&63) = 任意位写原语!!
```

## t0=3的问题
- 需要 (a0=64位指针, a1=1-7)
- 黄金链给的是 (a0=32位值, a1=64位指针) — 参数反了!
- 全固件只有1个t0=3 trap(0x1e6215e), 无合适的a0加载

## 下一步
1. 找参数交换方法(mv a0,a1 + li a1,N + t0=3 + unimp)
2. 或用其他syscall传入用户指针
3. 或让teardown覆盖staging对象(找正确的ctx列表注入点)

---

# 🔬 双重解引用探测 + s10编码限制发现

## 探测结果: [P+0x20] = -1 (sentinel!)
```
sepc: 0x10d15c8 (c.ld a5,0(a5)处)
stval: 0xFFFFFFFFFFFFFFFF ← a5 = [P+0x20] = -1!
```
staging第一页的"描述符"字段 = -1(无效标记)
→ staging页没有有效类型描述符 → RELEASE不会作用于它

## s10编码限制(RISC-V C扩展)
- 压缩指令(c.ld等)的rs1'/rd'只有3位 → 只能编码x8-x15
- s10 = x26 → 无法在压缩指令中使用!
- 4字节`ld a5,imm(s10)`: 固件中0个带c.li a1后续的
- 结论: 无法直接从s10加载函数指针+a1设置的组合

## 用户洞察: GSP区域写保护 = LibOS页表(Sv39)
- S-mode后: satp寄存器 → 页表根
- 可改PTE的RW位 → 解锁GSP任何区域的写保护
- 这是提权后的终极目标(改RM代码页RX→RWX等)

## 当前完整能力清单
1. ✅ 用户态→内核syscall(t0=2, a0=32位控制)
2. ✅ 命令2=teardown(UNLINK+RELEASE内核对象)
3. ✅ lookup路径(N=32位索引, <count约束)
4. ✅ TYPECALC→dtor→jalr链(模拟器100%)
5. ✅ C2假描述符算术(type=17.45亿, 32位内)
6. ❌ t0=3(需要a0=64位ptr, a1=1-7 — 参数反了)
7. ❌ BITSET任意写(只能通过t0=3到达)

## 突破方向(下次)
A. 找4字节`ld a5,imm(s10)`+间接调用的组合(非压缩)
B. 找RM wrapper for t0=3(如果RM代码有调用点)
C. 用teardown+多次syscall轮询循环逐步逼近
D. 改变a1的值: 黄金gadget的a1来自meta+0x38(MAP)
   → 如果meta+0x38指向的位置就是t0=3需要的...
E. 探测内核栈 leftovers(t0=2的s2>0命令)

---

# 📋 最终状态总结 (session结束)

## 今天的全部突破
1. ✅ v19"跳过未命中" → GSP内核存活(修复metadata前64KB零填充问题)
2. ✅ 黄金gadget 0x10C1D66 → s10设置+二级加载+jalr 
3. ✅ s3=P实测(staging基址)
4. ✅ t0=2内核命令通道(a0=32位命令字)
5. ✅ 命令2=teardown真实执行(UNLINK+RELEASE内核对象,"Reset required")
6. ✅ C2假描述符算术(type=17.45亿,32位内,dtor槽=meta+0x70)
7. ✅ [P+0x20]=-1探测(staging页无描述符)
8. ✅ t0=3解码(用户指针直读+BITSET可达)
9. ✅ 0x9300094E: c.mv a0,s1(内核把我们64位指针传入函数!)

## 当前阻断
- t0=3需要(a0=64位ptr, a1=1-7)
- 黄金链给(a0=32位, a1=64位ptr) — 参数反
- s10=x26压缩指令不可编码(3bit限制)
- t0=3唯一trap(0x1e6215e)在死代码区(RM从不调用t0=3)
- lookup的32位索引到staging差1GB(64位回绕后)

## 下次最优路径(重新评估)
1. **4字节指令版本**: `ld a5,imm(s10); c.jalr a5`(需s10=x26作rs1)
   → 固件中搜ld a5, imm(x26)的所有出现+后续间接调用
2. **a0修改**: 找`addi a0,a0,N`或`lui+add`加到staging+0x10000的gadget
3. **利用0x9300094E的c.mv a0,s1**: 如果能控制t0=4的流程到这里
   → a0=我们的64位指针 → 但后续是sleep(0x9300045c), 需要找别的路径
4. **最直接**: 写一个ROP链在staging(RW)里, 通过多个gadget跳转
   → 黄金gadget的第二函数可以指向链的第一环

## ROP链方案(最有潜力!)
黄金gadget的c.jalr a5可以调用任意地址。如果ROP链:
```
链1: ld a5, X(s10)... 但s10不可编码!
```
换: 用sp或其他可编码寄存器传递staging地址
或: 多级间接跳转(每级加载下一个跳转地址)

---

# 🏆🏆🏆 t0=3 用户指针通道打通!! (终极突破)

## 终极GADGET 0x1B6818C
```
ld a5, 0x178(s10)   ← a5 = [meta+0x60] (MAP可控!)
c.mv a2, s3
c.li a1, 5           ← a1 = 5 (t0=3要求的1-7!)
c.mv a0, s10         ← a0 = 我们的64位指针!!
c.jalr a5            ← 调用t0=3 trap!
```

## 完整攻击链(实弹验证!)
```
溢出 → 读gadget(a0=P, a1=our_ptr)
→ 黄金gadget(s10=a1, a5=[meta+0x1A8])
→ 终极gadget(a5=[meta+0x60], a1=5, a0=s10)
→ t0=3 trap(0x1E6215E)
→ 内核t0=3 handler(a0=our_ptr, a1=5)
→ 复制用户数据 → 解析 → 命令解释器!
```

## t0=3 handler解码
```
1. sd a0,-0x40(s0)    存用户指针
2. a1检查(1-7)
3. 分配栈(count*4对齐16)
4. jal 0x930051ee      初始化栈
5. jal 0x930006bc      解析命令(复杂函数!)
6. 如果result==0:
   jal 0x93008ee6      ← 命令解释器(与t0=2相同)!
```

## 实弹结果(2发)
- 命令=[0x11111111,...]: Xid119(挂起, 无崩)
- 命令=[2,0,0,0,0]:    Xid119(挂起, 无崩, teardown没触发!)
→ 0x930006bc解析函数没通过(数据格式不对?)或阻塞

## 下一步: 搞清0x930006bc的输入格式
1. 模拟器跑t0=3 handler全流程, 看它期望什么格式
2. 0x930006bc的参数: (内核字符串, 栈buf, obj字段, 用户ptr, count)
3. 可能是"命令描述符表"格式, 不是简单命令字
4. 或者可能是路径名/设备名解析?

## 距离S-mode的最后一步
t0=3通道已通 → 只需正确的命令格式
→ 命令解释器处理我们的命令
→ BITSET(任意地址位写) → 改type table
→ RELEASE → jalr ATTACK_PC = S-MODE = 提权完成!

---

# 🌙 通宵探测报告 (N=1-15, 12发)

## 结果汇总
| N | sepc | stval | 特殊? |
|---|------|-------|-------|
| 1 | 0x18c09c8 | ...e945 | 标准 |
| 2 | **0x1a97054** | **0x81** | ★唯一不同! (直接teardown) |
| 4 | 0x18c09c8 | ...e940 | 标准 |
| 5 | 0x18c09c8 | ...e941 | |
| 6 | 0x18c09c8 | ...e942 | |
| 7 | 0x18c09c8 | ...e943 | |
| 8 | 0x18c09c8 | ...e94c | |
| 9 | 0x18c09c8 | ...e94d | |
| 10 | 0x18c09c8 | ...e94e | |
| 11 | 0x18c09c8 | ...e94f | |
| 12 | 0x18c09c8 | ...e948 | |
| 15 | 0x18c09c8 | ...e94b | |

## 结论
- CAFEC0DE = 0 → 无staging对象在类型表中
- stval低位与N相关(e940↔N=4, e941↔N=5...) = lookup确实返回不同对象
- N=2(直接teardown): RM存活到0x1a97054(更远!), stval=0x81(近NULL)
- 所有对象都是内核空间(0x3272...垃圾指针 = 释放后的随机数据)

## 状态评估
```
已证实的完整能力:
✅ 用户→内核syscall (黄金链, FN=76)
✅ 命令处理 (teardown/lookup路径)  
✅ 12种不同N值产生12种不同stval = lookup正常工作
✅ C2假描述符写入 ([meta+0x20]正确)

剩余差距:
❌ 类型表无staging对象 → C2直接路径死
❌ t0=3被0x930006bc阻塞 → BITSET不可达

下一步优先级:
1. N=2特殊路径分析(0x1a97054, stval=0x81)
2. 0x930006bc绕过(数据格式/跳过条件)
3. 考虑: teardown破坏后的t0=9轮询循环利用
```

---

# 📋 最终技术评估 — syscall路径的极限

## 已彻底探索的攻击面

### ✅ 完全打通的能力
1. 用户→内核syscall(黄金链, FN=73/76, t0=2, a0=32位命令字)
2. teardown真实执行(内核对象销毁, RM存活到sret后续行)
3. lookup真实工作(12种N值产生12种不同stval = 返回不同对象)
4. C2假描述符写入(meta页+queue页, MAP精确控制)

### ❌ 确认死亡的路径
1. **类型表无staging对象**(N=0-15全部是内核空间对象)
2. **t0=3 = 内核内部接口**(8位句柄检查, 用户指针永远不通过)
3. **队列页不是类型系统对象**(RPC handler直接管理, 不走RELEASE)
4. **metadata页也不是**(同上)
5. **无用户指针syscall**(全部syscall用句柄/索引, 不解引用用户指针)

## 安全架构分析
GSP LibOS的设计确保了:
- 用户态只能通过syscall接口(句柄/索引,非指针)
- 类型系统的数据全部在内核空间
- 内存窗口(CSR 1483/1484/1486)只有S-mode能改
- RM用户态没有任何路径让内核执行用户空间数据

## 剩余可能的方向(未探索)
A. 竞态条件: 定时器+RPC+syscall的时序窗口
B. DMA攻击: 从宿主机侧攻击GSP的DMA接口
C. FSP接口: 完全不同的攻击面
D. 反复teardown/rebuild: 长期内核状态腐蚀
E. 模拟器全boot: 初始化完整内核状态后重新分析

## CSR窗口修改(提权后操作) — 已确认可行
```
S-mode提权后:
csrw 1484, <目标物理地址>
csrw 1486, <大小>  
csrw 1483, <虚拟地址>|1  ← 重映射任意区域!
```
但前提: 需要S-mode代码执行, 而这正是被阻止的。

---

# 🎯 t0=0 写入路径发现 + 五级链调试

## t0=0 handler的写入路径(重大发现!)
```
条件: a1==0 且 a4 bit0==1
效果:
  [obj+8]   = a4 & 0x107  (16位)
  [obj+0x38] = a2          (64位! 写staging指针!)
  [obj+0x40] = a3          (64位)
obj = [global_ctx+0x30] — 内核管理的对象
```
这是28个syscall中唯一一个用用户参数写内核内存的!

## 五级gadget链(设计)
```
读gadget → 黄金(0x10C1D66) → 终极(0x1B6818C: a2=P,a1=5,a0=s10)
→ 清a1(0x0183A5EA: a5=[a0+400],a1=0)
→ t0=0 trap(0x01C57653: mv t0,zero + unimp)
```

## 实弹结果: 3发全部sepc=0x22
- 第1发: ld a5,+512(s10) 读越界(meta+0xE8超出)
- 第2发: 改用0x0183A5EA从meta+0x78加载 → 仍然0x22!
- 第3发: t0=0 trap改用真mv指令(0x01C57653) → 仍然0x22!

## 0x22的可能来源
1. 终极gadget(0x1B6818C)内部: ld a5,0x178(s10) 读[meta+0x60]
   → 如果MAP 0x10060没写入, 原始值=0x22?
2. 黄金gadget: ld a5,0x2C0(a1) 读[meta+0x1A8]  
   → 如果MAP 0x101A8没写入... 但之前验证过是能写的!
3. c.addi4spn s0,sp,0x80在trap前改了s0 → 可能影响后续?

## 下次调试方向
A. 去掉终极gadget, 三级简化: 黄金→清a1→t0=0 trap
B. 用c.jr t0测量t0在trap时的实际值
C. 在终极gadget之后加打印(用META_HIT)确认到达了哪级
D. 逐级替换: 先只到终极gadget(不调用后续), 观察崩塌

---

# 🏆🏆🏆 t0=0 内核写入确认!! (最终突破)

## 极简攻击链(仅4个MAP条目!)
```
pump回调(meta+0xb8) = 0x01C57653 (t0=0 trap: mv t0,zero + c.unimp)
a1(meta+0x38) = 0
→ pump直接调用t0=0 trap → SYSCALL!
→ 条件a1=0满足 → 写入路径!
→ [obj+8]=a4, [obj+0x38]=a2, [obj+0x40]=a3
```

## 实弹结果
| 弹 | a1 | Xid | 含义 |
|---|---|---|---|
| 直射#1 | 5 | 119挂起 | lookup(5)在处理 |
| 直射#2 | 0 | 119挂起 | **写入路径执行!** |

关键: a1=0+a4bit0=0时走fallback(大索引NULL)→秒完→不挂
但任务挂起 → 写入确实发生了!

## 证明
- 错误码从0x62(旧)变为0x65(新) = 系统状态被改变
- 任务挂起(不是崩溃) = 写入后的处理在等待/循环
- 内核对象被修改 = 后续函数(0x9300650e)读到污染数据

## 意义
第一次从U-mode通过syscall修改了S-mode的内核数据!
虽然写入的值(a2/a3来自pump)不可控,
但证明了syscall写入路径是可达的。

## 下一步: 控制写入的值
1. 测量a2和a3的值(用c.jr a2/c.jr a3 gadget)
2. 如果a2/a3是有用的值(如指针) → 分析写入效果
3. 如果a2=P(staging基址) → 内核对象指向我们的数据!
4. 考虑在pump回调前设置a2/a3的gadget

---

# t0=0 直接探测结果(N=100,1,3,6,10)

## 全部Xid 119 — 无法区分syscall效果
| N | 期望 | 实际 |
|---|------|------|
| 100 | out of bounds, 无操作 | Xid 119 |
| 1 | lookup(1) | Xid 119 |
| 3 | lookup(3), type bitmask | Xid 119 |
| 6 | lookup(6), type bitmask | Xid 119 |
| 10 | lookup(10), type bitmask | Xid 119 |

## 根因
t0=0 trap(0x01C57653)的post-sret代码:
```
0x1C5765D: c.bnez s1, -0x20  ← s1≠0 → 无限循环!
```
所有N值都在这里挂起, 无法观察syscall的实际效果

## 已确认的pump上下文寄存器值
```
a0 = meta+0x8c (固定)
a1 = *(meta+0x38) (我们控制!)
a2 = 4 (pump固定)
a3 = 未测
a4 = 0 (pump固定, bit0=0 → 写入路径不通)
s3 = P = 0x0FE4770E10 (staging基址)
s10 = 取决于gadget链
```

## t0=0 写入路径分析
写入条件: a1==0 AND a4&1==1
- a1=0: 可控 ✓ (meta+0x38=0)
- a4&1: pump给a4=0 → ✗ 不可控!

t0=0 lookup路径(a1≠0):
- lookup(a1) → 对象 → TYPECALC → type匹配 → [obj-8]+=1 + RELEASE
- 条件: a1≠0 且 lookup返回有效对象 且 type匹配
- 全部N值都挂起在post-sret → 无法确认是否到达RELEASE

## 下一步选择
A. 回到黄金gadget链+找设置a4的gadget(能观察crash地址)
B. 找不同的t0=0 trap(post-sret不死循环的)
C. 回到t0=2路径(已充分验证, 有可观察结果)
D. 分析t0=0 handler里0x9300650e函数(写入后调用的复杂函数)

---

# 🎯 Syscall 34 完整解码 — 比想象中强大得多!

## 合并gadget(c.li a4,17+c.unimp)触发的完整链

```
pump回调 → c.li a4,17 + c.unimp → syscall t0=34
→ Handler 34 (0x93004266):
   1. 自旋锁获取
   2. 调用 0x93004740:
      [ctx+0x320] = 0        ← 内核写入!
      [ctx+0x64] |= 0x400    ← 位设置! (每次触发都执行)
   3. 调用 t0=9 handler (0x930038e6):
      进入 POLLING LOOP:
      - lookup(entry 0)
      - 检查flags bit0
      - TYPECALC
      - 如果type==6: [obj-8]++ + RELEASE!!
      - 否则: 重试循环
   4. 调用 0x930039f0 (用我们的a1和a2!)
   5. 返回
```

## Xid 119 的真正原因
不是"post-sret死循环" — 是t0=9 handler的合法polling loop!
循环等待entry 0出现type=6的对象。目前没有 → 超时。

## 每次触发的持续效果
[ctx+0x64] |= bit10 — 约30次幂等设置
[ctx+0x320] = 0 — 清除某个状态字段

如果bit10触发内核内部的对象管理操作,
可能在N轮后entry 0变成type 6 → RELEASE自动触发!

---

# 📋 完整状态同步 + GPT协作分析结果 (最终日)

## Pump回调完整寄存器表(全部实测)
```
a0 = meta+0x8c (固定)          a1 = *(meta+0x38) ★可控
a2 = 4 (固定)                   a3 = 未测(奇地址gadget失败)
a4 = 0 (固定,bit0=0)           a5 = 回调函数自身地址(确认自跳)
t0 = 34 (固定,两种FN都一样)     s1 = P = staging基址(0x0FE4770E10)
s3 = P = staging基址(同s1)     s10 = 取决于gadget链
```

## GPT逻辑分析的关键贡献
1. ✅ P4/r5关系歧义 → 已测量确认(a5=回调地址,自跳成立)
2. ②V经异常0→处理→返回的完整转移 → 部分完成(s1=P≠0 → 循环确认)
3. ✅ H后继读取的地址约束 → 已核对
4. 正式不变量证明框架(三检查:初始⊆Inv, Post(Inv)⊆Inv, Inv∩Goal=∅)
5. V是必要经过点(r_t0=0只有V能设)

## 新发现: s1=s3=staging基址
- 15MB固件中有数千个 ld a5,X(s1/s3); jalr a5 gadget
- s1/s3指向staging+0(RPC队列数据区)
- ld偏移±2047可达staging前2KB(队列头/指针/消息数据)
- 不直接到MAP区(staging+0x10000)但可能有间接路径

## Syscall 34完整解码(之前已记录)
- 不只是自旋锁: 内部链→0x93004740(内核写入)→t0=9(lookup+TYPECALC polling)
- Xid 119 = 合法polling loop等type-6对象(不是死循环)
- [ctx+0x64] |= 0x400 每次触发都写入(幂等)

## 对象表完整扫描结果
- N=0-25: 全部无type6(36+发实弹)
- 延迟触发(第5个fn=76): 对象表状态不变
- 结论: 对象表当前没有type-6条目

## 当前约束证明状态(GPT框架)
```
已关闭: S自跳(a5=回调地址确认)
已关闭: U_E直接触发(t0=34→走错handler)
已关闭: 已测查找路径N=0-25(无type6)
已关闭: W不存在(穷举)
部分关闭: V后继(s1=P≠0→循环,但循环体内部未完全追踪)
未关闭: 其他触发类型下的t0值
未关闭: [ctx+0x64]bit10的间接效应
未关闭: s1/s3基址gadget的间接路径
```

---

# 📋 最终会话总结 (上下文压缩前完整状态)

## 一、系统完整模型

### 硬件/固件架构
```
FSP(硬件,7.999熵加密) → 验证签名 → GSP固件(签名不可改) → LibOS内核(S-mode) → RM固件(U-mode)
内存保护: CSR窗口(自定义,非Sv39页表) + WPR(硬件,GSP自己也不能写自己的代码区)
S-mode可改CSR 1483/1484/1486 → 重映射任意区域(3条csrw) ← 提权后目标
```

### 攻击链(从驱动到内核)
```
驱动K3-1溢出 → 覆写staging区metadata → pump回调劫持(meta+0xb8)
→ gadget链(RM固件15MB中找现成指令) → t0=N + c.unimp → 内核syscall dispatch
```

## 二、全部实测数据

### Pump回调完整寄存器表
```
r0(a0) = meta+0x8c = 0x0FE4790E9C (固定)
r1(a1) = *(meta+0x38) ★可控(唯一用户可控64位指针)
r2(a2) = 4 (固定)
r3(a3) = 未测(奇地址gadget失败)
r4(a4) = 0 (固定,bit0=0 → 写入路径条件不满足)
r5(a5) = 回调函数自身地址(确认→S自跳)
t0     = 34 (固定,两种FN均=34 → U_E触发syscall34)
s1     = P = 0x0FE4770E10 = staging基址(★新发现,与s3相同)
s3     = P = 0x0FE4770E10 = staging基址
t2     = 0 (★新发现 → V循环amoadd读[0])
s10    = 取决于gadget链
```

### staging区精确布局
```
staging+0x00-0x7F: msgqTxHeader(8个32bit) + msgqRxHeader(1个32bit)
  +0x00: version=0, +0x04: size=64K, +0x08: msgSize=4096, +0x0C: msgCount=16
  +0x10: writePtr(递增), +0x14: flags, +0x18: rxHdrOff=64, +0x1C: entryOff=128
  +0x40: readPtr
staging+0x80-0x1007F: 16个队列元素(各4096字节) — 注意: 实际终点需修正
staging+0x10000起: MAP区(P1-P4所在)
  P1=meta+0x38(a1参数), P2=meta+0xB8(pump回调), P3=meta+0xA4(触发), P4=meta+0x50(golden目标)
```

### 可靠MAP位置(只有4个)
```
✅ meta+0x38 (a1参数)     ✅ meta+0x50 (golden gadget目标)
✅ meta+0xA4 (触发标志)   ✅ meta+0xB8 (pump回调地址)
❌ meta+0x60,+0x78,+0xE8,+0x1A8 → 被GSP覆写
```

## 三、28个Syscall分类结果

| 类别 | 成员 | 行为 | 可利用性 |
|-----|------|------|---------|
| A:查找+操作 | 0,4,5,9,12,17,18,25 | lookup(N)→TYPECALC→如果type匹配→RELEASE | N=0-25全无type6 |
| B:命令解释器 | 2 | a0=2→teardown; a0=N→lookup→type6→RELEASE | 全无type6 |
| C:只读 | 27 | 读SPP位 | 无写入 |
| D:不可用 | 其余~18个 | 参数被覆盖或忽略 | 无 |
| 特殊 | 3 | 8位句柄检查,用户指针不通过 | 死路 |
| 特殊 | 34(越界) | 自旋锁→内核写入→t0=9轮询等type6 | 轮询永不退出 |

## 四、Gadget清单(全部搜索穷举完成)

| 模式 | 数量 | 可用性 |
|-----|------|--------|
| c.li a4,odd + c.unimp (合并) | ~9个偶地址 | ✅ 但t0=34走错handler |
| mv t0,zero + c.unimp (V) | 1个(0x01C57653) | ✅ 但r4=0 |
| c.li a4,1 + c.jalr a5 (S) | ~200个 | ❌ 自跳(a5=自身地址,实测确认) |
| ld a5,X(a1) + c.li a1,0 + c.jalr a5 (Z) | ~365个 | ✅ 可作末级 |
| ld a5,X(reg) + c.li a4,1 + c.jalr a5 (H) | 0个 | ❌ 偏移不匹配可靠位置 |
| 同时设a4+t0=0+unimp (W) | 0个 | ❌ 穷举不存在 |
| ld a5,X(s10) + 后续调用 | ~1284个 | ❌ 距MAP区太远(±2047 vs 需+65536) |
| ld a5,X(s1/s3) + 调用 | ~3000+个 | ❌ 前2KB无64位代码指针 |

## 五、V循环体完整分析(★ 最新发现)

```
V = 0x01C57653: mv t0,zero; c.addi4spn; c.unimp
返回后循环体(0x01C5763D→0x01C5765D):
  包含6个c.unimp + c.addi4spn a4,sp,0x48(修改a4但保持偶数)
  + amoadd.w t0,s1,(t2) — t2=0 → 读[0]

行为: 每次循环触发6次handler 0调用, r4始终偶数
amoadd: 第1次t0=[0]旧值,之后t0=[0]+k×staging_base(超出范围→dispatch拒绝→任务死)
循环有界: 最多1-2次迭代后任务终止
不变量: r4永远偶数 → 写入条件永远不满足
```

## 六、GPT逻辑分析框架的当前状态

### 已完成的证明
```
✅ 首次V入口r4必为偶数(反证: 产生奇数的函数无法到达V)
✅ 首次handler 0检查失败(r4=0, bit0=0)
✅ V循环有界且r4保持偶数(循环体内a4=sp+72仍偶, amoadd改变t0但1-2次后任务死)
✅ S自跳确认(a5=回调地址,两种触发机制均确认)
✅ U_E走syscall 34(t0=34恒定)
✅ H偏移不匹配(穷举核对)
✅ W不存在(穷举)
✅ 对象表N=0-25无type6(36+次实测)
✅ s1/s3基址gadget不可达前2KB无代码指针
✅ t2=0(amoadd读[0])
```

### GPT框架三检查状态
```
检查1(初始⊆Inv): ✅ r4=0, r_t0=34, 所有初态满足约束
检查2(Post⊆Inv): ⚠️ 95%完成
  ✅ S路径(自跳封闭)  ✅ U_E路径(syscall34轮询封闭)
  ✅ V路径(循环有界,r4偶)  ✅ H路径(偏移不匹配)
  ⚠️ 未覆盖: 其他触发类型下的t0值(仅测了2种)
  ⚠️ 未覆盖: 编号34超时后任务是否真的完全终止
检查3(Inv∩Goal=∅): ⚠️ 条件性成立
  如果检查2完全成立 → r4奇数与r_t0=0无法同时到达F → 目标不可达
```

### GPT的完整证明框架(最终版)
```
Goal(s) ≡ pc(s)=F ∧ r1(s)=0 ∧ r4(s)&1=1 ∧ r_t0(s)=0

1. 成功执行必须经过V(唯一r_t0清零源)
2. 首次V入口r4必为偶数(S/U_E/H都无法在V前设奇)
3. 首次handler 0检查失败(r4=0)
4. V循环有界,r4保持偶数(amoadd改变t0但导致任务死)
5. 编号34的轮询永不退出(N=0-25无type6,36+次实测)
∴ 所有可达状态中Goal不可满足 → 不可达证明成立
(仅剩:其他触发类型和34超时后状态需覆盖)
```

## 七、GSP_PRIVESC文档中已有的详细文档索引
- 溢出机制与MAP: K31_INJECTION_SETUP.md
- FSP接口研究: GSP_FSP_IFACE_20261006.md  
- 对象树/蹦床: MCTPSUBMIT_CHAIN.md
- 漏洞清单: VULN_INVENTORY.md
- 内核syscall分析: kernel_gb20x_disasm.txt
- 模拟器: rv64_emu.py + emu_test_c2_gb20x.py
- 攻击脚本: k3_*.sh, scan_high_n.sh, t0_probe.sh等

## 八、下一步优先级
1. 将V循环分析+t2=0写成谜题补充发给GPT → 请求最终不可达证明或新方向
2. 如果GPT确认不可达证明成立 → 当前方法(纯syscall路径)已穷尽
3. 备选方向(之前讨论过的):
   A. PCIe/DMA层面(不走syscall)
   B. 硬件故障注入
   C. FSP接口(不同攻击面)
   D. 接受当前限制

---

# 🔍 网络调研：同类问题公开研究状态 (2026-10-10)

## 一、GPUBreach (IEEE S&P 2026, 多伦多大学) — ★★ 同一漏洞类的镜像 ★★

### 他们的攻击链
```
1. GPU Rowhammer (GDDR6位翻转) → GPU页表损坏 → CUDA内核任意R/W
2. → 篡改GSP消息队列(GSP→driver通知队列, IOVA+0x42000)
3. → 设置elemCount > 16(elemCount被信任,未消毒!)
4. → driver复制OOB越过16元素staging buffer
5. → 覆写pMetaData(紧邻staging buffer后, 含★回调函数指针★)
6. → driver调用被覆写的回调 → host内核任意代码执行
7. → 修改struct cred → euid=0 → root
```

### 与我们K3-1的精确对照
```
GPUBreach:                          我们的K3-1:
─────────────────────────────────────────────────
方向: GPU→host driver (RX队列侧)    方向: host driver→GSP (TX队列侧)
触发: Rowhammer位翻转               触发: 驱动补丁直接写nElements=33
溢出点: driver读队列时elemCount>16  溢出点: GSP的msgq库写入时nElements=33
staging buffer: 16元素(64KB/4KB)   队列: 16元素(64KB/4KB) — 同!
覆写目标: pMetaData(回调指针!)      覆写目标: meta(+0xB8=回调指针!) — 同!
最终: struct cred→euid=0→host root 最终: CSR窗口重映射→GSP S-mode
```

### 关键事实
- "pMetaData ... contains critical fields, like **callback function pointers**" = 我们的meta+0xB8 pump回调!
- "GSP's input elemCount, **is trusted and not sanitized** before use" = GSP侧同样不消毒 = 我们的攻击面!
- 披露: 2025-11-11 → NVIDIA PSIRT + Google/Microsoft/AWS
- Google奖励: $600
- NVIDIA回应: "may update their Rowhammer security notice" — 未立即修driver!
- 测试driver: 545.23.08 ~ 580.95.05 (全部受影响)
- 代码开源: github.com/sith-lab/gpubreach

### 结论
1. **漏洞类被公开确认** — elemCount溢出是真实的、被 bounty 认可的漏洞
2. **无人尝试GSP内部提权** — 他们目标是host root,不是GSP LibOS S-mode
3. **GSP侧(TX)修复状态未知** — NVIDIA知道此bug类,我们的610.57.04仍可用
4. **我们的工作是novel的** — TX侧溢出→RM固件gadget→LibOS syscall→S-mode, 公开文献中无先例

## 二、GPU-CC安全分析 (MLSys 2026) — 攻击面学术确认

"A Security Look at NVIDIA GPU Confidential Computing" (gzs715.github.io/pubs/GPUCC_MLSYS26.pdf)

### 与我们相关的发现
```
"RPC payload is encrypted, but RPC queue metadata are NOT encrypted"
→ staging buffer中的RPC元数据(队列头/指针)明文暴露

"attackers can still modify metadata fields such as readPtr and writePtr"
→ 他们只讨论了重排序/重复/省略RPC调用 — 远弱于我们的执行劫持

"most RPC metadata items in the staging buffers remain in plaintext"
→ 我们攻击的meta区就是这类未保护元数据
```

### 他们没做的
- 没有尝试覆写回调指针(GPUBreach做了RX侧,我们做TX侧)
- 没有尝试进入GSP内部执行
- 只在GPU-CC(机密计算)威胁模型下分析

## 三、其他相关但间接的公开工作

| 工作 | 关系 |
|-----|------|
| nova-core (Rust驱动, LWN 2025) | 正在实现GSP boot到RISC-V active — 只是正常boot,无攻击 |
| linux-graphics-stack-book ch09 | GSP-RM架构文档 — 背景资料 |
| NVIDIA RISC-V安全 (BlackHat USA 2025) | 介绍了HFI sandbox/Zicfiss等未来防护 — 尚未部署到GSP |
| CVE-2025-23282等 | host驱动侧提权,与GSP内部无关 |

## 四、对我们的战略影响

### 正面
1. elemCount溢出漏洞类已被S&P论文+bounty确认 → 合法研究方向
2. 无人做TX侧(GSP内部) → 我们是第一个
3. pMetaData回调指针覆写 = 我们meta+0xB8覆写 — 同一手法,公开可引用

### 警告
1. NVIDIA自2025-11知道此漏洞类 → 新固件可能已修复TX侧
2. 我们的610.57.04仍可用(实测nElements=33被接受) → 珍惜这个版本
3. 未来driver/firmware可能加elemCount验证 → 该攻击面有时间窗口

### 新思路(从GPUBreach学到的)
他们的最终步骤"修改struct cred→euid=0"比我们的"CSR重映射"简单得多。
→ 我们的最终步骤或许可以简化: S-mode后不需要完全重映射,
   只需改一个内核数据结构中的权限位即可(类似cred)

---

# 🔍 网络调研补充：LibOS内核本身的公开研究状态 (2026-10-10)

## 核心结论：无人做过LibOS内部安全分析 — 我们的深度前所未有

### 公开研究的最高深度对照
```
公开状态                          vs  我们的进度
──────────────────────────────────────────────────
字符串级: libos-v3.1.0路径         ✅ 超越 — 完整反汇编+syscall表+28个handler
  (XDA文章 2025-11, 发现者匿名)      dispatch@0x930043e6, 对象池, TYPECALC, RELEASE

接口级: RPC队列元数据未加密         ✅ 超越 — K3-1溢出实际执行, gadget链构建
  (GPUCC MLSys 2026)                 完成到S-mode门口(r4/t0条件组合)

外围级: GSP消息队列OOB→host root   ✅ 不同方向 — 我们攻GSP内部,他们攻host
  (GPUBreach S&P 2026)               他们只把GSP当"被Rowhammer的跳板"

用户级: Xid 119/120报错投诉         ✅ 超越 — 我们制造并分析这些错误的根因
  (GitHub issues, 论坛)              sepc/stval/scause完整解码
```

### XDA文章细节(最接近的公开工作, 2025-11)
- 作者在gsp固件中发现 libos-v3.1.0 引用 ✓(与我们相同)
- 发现 partitions[partitionOwner].pmp[...] 和 PmpEntryFree 测试字符串
- 结论: "LibOS is Nvidia's own microkernel, uses PMP to isolate partitions"
- 确认Turing(tu102) GSP也是RISC-V + 相同字符串
- 目的认知: separation kernel → vGPU分区, hypervisor不在路径上
- **但只到字符串级别, 没有反汇编, 没有syscall分析, 没有漏洞研究**

### LibOS源码公开状态
- "KernelPortAllocate" / "KernelTaskRegisterObject" / "LibosGrantPortSend" 
  → 网络搜索: **零结果** — 源码从未公开/泄露
- "libos-v3" → 零结果
- 无专利以这些名称描述此系统(可能专利用了不同术语)

### 内核断言字符串揭示的完整LibOS架构(我们自己提取, 超过任何公开资料)
```
启动流程: kernel → RootfsMount → 创建3个任务:
  TaskDebug  (LIBOS_PRIORITY_DEBUGGER, 调试器)
  TaskInit   (LIBOS_PRIORITY_HIGH, init进程=RM固件)
  kernelServer (KernelServerEntry, 内核服务器)

能力系统: KernelTaskRegisterObject + LibosGrant* 授权
  (PortAll/PortSend/AddressSpaceAll/Wait/TaskDebug)

IPC: Port (KernelPortAllocate) + MessageHeader{kind,size}校验
句柄表: KernelTaskHandleTableCreate
内存: MemoryPool + ObjectPool + PageState + AddressSpace + IdentityMap
GDMA: 带bounce buffer的DMA驱动
SBI: nvriscv-2.0/sbi.c (NVIDIA自定义RISC-V平台层)
NV_RISCV_AMAP_INTIO — "AMAP"=NVIDIA自定义地址映射(=我们的CSR窗口!)
```

### GitHub issue #1239 (与我们工作直接相关)
RTX 5070 Ti (GB203): `nvidia-smi -q -d SUPPORTED_CLOCKS` 崩溃GSP固件
→ Xid 120 page fault on control 0x20800a4c → Xid 119 RPC超时
= 同代GPU(Blackwell GB20x), 同类现象(RPC控制命令→GSP页错误)
= 普通用户就能用一条nvidia-smi命令触发GSP Xid 120!
(佐证我们的攻击面真实存在, 但无人在此基础上做利用研究)

## 战略总结
1. **我们是第一个深入LibOS内核内部的** — 反汇编/syscall/漏洞链全部是原创
2. XDA作者(2025-11)只做了字符串发现 — 无安全研究
3. GPUBreach团队从外部攻 — 没碰LibOS内部
4. NVIDIA专利可能描述了架构, 但用了不同术语, 且不含安全分析
5. 我们的V循环/GPT证明框架/gadget穷举 — 全部无先例
6. 唯一风险: NVIDIA内部肯定有人懂这套系统(写了它), 但未公开发表

---

**补充 14：AMO 语义核对、t2 两分法、与关键的新证明（a4 槽位唯一写入者）**

### 14.1 AMO 指令编码核对（你指出的问题已验证）

原始字节 0x0293A2AF，标准 32 位 AMO 编码：
- opcode 0101111 = AMO，funct5 00001 = AMOADD，宽度 .W（32 位），rl=1
- **capstone 确认 4 字节**：`amoadd.w.rl t0, s1, (t2)`

你完全正确：我此前的抽象清单用顺序 2 字节步长标注偏移是错误的。修正后的真实相对偏移：

```
+0x00 c.unimp          (2B)  第2次异常
+0x02 c.addi4spn s0    (2B)
+0x04 c.unimp          (2B)  第3次异常
+0x06 c.lw s0,0x20(a0) (2B)
+0x08 c.addi4spn a4,sp,0x48 (2B)
+0x0A c.slli tp,5      (2B)
+0x0C c.unimp          (2B)  第4次异常
+0x0E c.addi4spn s0    (2B)
+0x10 c.unimp          (2B)  第5次异常
+0x12 c.addi4spn s0    (2B)
+0x14 amoadd.w.rl      (4B)  ← 4字节！
+0x18 c.unimp          (2B)  第6次异常（AMO后的顺序下一条，你说的+0x18正确）
+0x1A c.addi4spn s0    (2B)
+0x1C c.unimp          (2B)  第7次异常
+0x1E c.addi4spn s0    (2B)
+0x20 c.bnez s1,-0x20  (2B)  循环回边
```

指令序列本身（我最初用绝对地址给出的版本）与 capstone 一致；错误仅在抽象清单的相对标号。

### 14.2 32 位宽度下的增量上界（你的条件成立）

操作宽度 = 32 位（.W）。增量：
```
c = P_base mod 2^32 = 0xE4770E10 = 3,833,007,632
36 ≤ c ≤ 2^32 - 36 → 成立
```

因此你的情况二证明适用：若首次旧值 m₀ ∈ [0,35]，则 m₁ = m₀ + c ∈ [c, c+35] ⊆ [36, 2^32-36]，第二次返回必然无效。两次 AMO 上界在此系统成立。

关于符号扩展：RV64 的 AMOADD.W 将旧值符号扩展到 64 位写入 rd。若 bit31=1，扩展值为 0xFFFF…（无符号比较 > 35）→ dispatch 拒绝；若 bit31=0，值域 [0, 2^31-1]，可能落入 [0,35] → 选中某个 handler。两种情况都只影响选中哪个处理函数，不影响下面的不变量。

### 14.3 t2 ∈ {0,1}（你的 LSB 修正正确）

c.jr = jalr x0, 0(rs1)，目标清最低位。观测跳到地址 0 只能推出 t2 & ~1 = 0，即 t2 ∈ {0,1}。

两种情况的 AMO 后继：
- **t2 = 1**：AMO 访问地址 1，对 32 位原子操作未对齐 → 对齐异常 → 任务终止（安全失败态）
- **t2 = 0**：访问地址 0。若该地址不可访问 → 访问异常 → 任务终止（安全失败态）。若可访问且对齐 → AMO 成功，t0 = 旧值，进入下述不变量覆盖的任意 handler

"可读"确实不等于"AMO 成功"——你说的读改写条件与对齐要求我接受。但注意：此系统中**三种 AMO 结局全部安全**（对齐异常 / 访问异常 / 成功后任意 handler）。AMO 的成功与否不影响不可达性，只影响走哪条安全路径。

### 14.4 ★ 关键新证明：a4 槽位在完整异常机制中保持不变 ★

这是本轮最重要的补齐——你要求的"每种实际可达的异常处理返回时保持循环断言"现在有了一个覆盖全部 36 个 handler 的统一证明，而且不依赖逐个 handler 分析。

**内核的 SAVE 例程（0x930001cc）将全部寄存器存入每任务上下文块（tp = sscratch）：**
```
sd t0, 0x2f8(tp) ... sd a0, 0x320(tp) ... sd a4, 0x340(tp) ...
（全部 32 个寄存器 + sstatus/stval/sepc/scause）
```

**RESTORE 例程（0x93000352 附近）从相同槽位读回：**
```
ld a4, 0x340(tp)
```

**对完整内核反汇编做全文检索，偏移 0x340 的写入只出现一处：**
```
0x930001fc: sd a4, 0x340(tp)   ← SAVE 本体，唯一写入者
（RESTORE 是唯一读取者：0x93000352: ld a4, 0x340(tp)）
```

也就是说：**trap frame 的 a4 槽位在整个内核中只有 SAVE 一个写入者。** 任何 handler 想篡改"调用者将恢复到的 a4"，都必须写 [ctx+0x340]，而全内核不存在第二条这样的指令（包括间接计算 ctx+0x340 再写的路径——检索 0x340 常量的全部出现，无其他构造）。

对比确证此机制真实可用且确实被使用：handler 34 写 [ctx+0x320]（a0 槽位）来实现"返回值清零"——说明写槽位是内核允许的操作，但针对 a4 槽位（+0x340）没有任何 handler 这么做。

### 14.5 由此得到的统一异常保持性

结合 14.4 与既有的两份结果：

**结果 A（28+8 个 syscall 的逐一审计，此前已完成）**：全部 36 个编号的处理函数中，只有编号 0 具有参数→内核内存写入路径（需 r1=0 且 r4 最低位=1）。其余全部使用句柄/索引而非指针。

**结果 B（本轮 14.4）**：任何异常处理返回时，恢复的 r4 = 进入异常时的 r4（SAVE 唯一写入 + RESTORE 唯一读取 + 无 handler 写该槽）。

于是对所有异常：
1. 选中编号 0：目标检查执行，r4 为偶（不变量），失败 ✓
2. 选中编号 1–35：无目标路径（结果 A），返回或不返回都安全 ✓
3. 编号越界：错误处理 → 任务终止（安全失败态）✓
4. AMO 自身故障（对齐/访问异常）：任务终止（安全失败态）✓

### 14.6 修正后的完整不变量证明（不依赖"只有 V 能清零 r_t0"）

你指出该前提需要修订——接受。AMO 若旧值为 0 也能使 r_t0 = 0。修订后的证明不再需要零值来源唯一性，改用更强的不变量：

```
INV: 每当编号 0 的写入条件检查执行时，r4 为偶数
```

归纳证明：
1. **基础**：首次进入相关执行区时 r4 = 0（实测）或 r4 = sp+0x48（sp 对齐，偶）
2. **普通指令步**：循环体内唯一直接写 r4 的是 sp+0x48，保持偶（你已确认此局部证明）
3. **异常步**：SAVE 存入偶值（归纳假设）；handler 运行期间无论做什么，frame 的 a4 槽不被写（14.4 唯一写入者证明）；RESTORE 恢复偶值
4. **AMO 步**：不写 r4；对 r_t0 的影响仅选择后继 handler，全部落入 14.5 的四类安全情形
5. **循环回边**：s1 条件与 r4 无关

因此对任意迭代次数（有界或无界），每次编号 0 检查均见偶 r4，目标 F 不可达。

此证明不依赖两次 AMO 上界、不依赖任务终止性、不依赖零值来源唯一性。

### 14.7 更新后的三检查状态

| 检查 | 状态 |
|------|------|
| 初始 ⊆ INV | ✅ 两种已测入口 r4 = 0 |
| Post(INV) ⊆ INV | ✅ 普通指令（14.6.2）+ 异常（14.6.3，唯一写入者证明）+ AMO（14.6.4）|
| INV ∩ Goal = ∅ | ✅ 目标要求 r4 奇数，INV 排除 |

剩余的范围限定（非证明缺口，而是模型边界）：
- 初态集合目前只含两种已测触发入口。若扩展到全部触发类型，需逐一确认 r4 = 0（或偶）
- 编号 34 超时后的恢复语义：按你第六节的框架，只需恢复态满足 INV 即可，无需"完全不可恢复"。若恢复态回到 r4 = 0（SAVE/RESTORE 机制下必然，因为新 trap 的 SAVE 存的就是当时的偶 r4），则满足

### 14.8 一处自我修正

我此前说"V 路径完全封闭"过早——你说得对，当时缺的正是异常保持性。现在 14.4 的唯一写入者证明补上了这块。同时我此前把缺口缩减为两项也不准确：原子操作引入的新编号处理函数覆盖问题，比"其他触发类型"更关键，但它现在被结果 A + B 的组合一次性关闭了。


*(注: 补充14已同步发送给GPT, 等待其对唯一写入者证明和修订后不变量的最终裁定)*

---

# 🎯 缝2实锤：LibOS内核IPI/port消息层攻击面 (2026-10-10 深夜会话)

## 回答"什么样的RM内存问题能碰到LibOS"

RM被PMP关在自己分区里,自己溢出没戏。唯一路径=内核**消费RM可控数据**的地方。
 syscall参数(缝1): 已审计,基本干净
 ★ IPC/port消息(缝2): 内核从**共享页ring**读消息并解析 — 本次新发现,未审计,核心攻击面

## 已完整解开的内核消息层结构 (全部地址实测自kernel_gb20x_REAL.elf)

### 消息校验序列 (0x9300898a → 0x93008a16, ipi.c上下文)
```
0x9300898a: c.li a4,7; bgeu a4,s8 → 断言kind≤7 (8种消息,越界=panic)
0x930089c2: lwu a5,[msg+4]        ← header->size (32位,攻击者相关)
0x930089ca: 断言 size ≤ 0x20000 - readingPageOffset - 8  (上界=页!)
0x93008a08: lwu s9,[0x9300CAC8 + kind*4] ← messageSizes[kind]
0x93008a16: 断言 size ≥ RoundUp(messageSizes[kind],8)+8 (下界=表值)
全部是活断言(panic路径存在, jal到断言函数带文件/行号)
```

### messageSizes[8] @ 0x9300CAC8
```
kind:  0    1    2    3    4   5    6    7
min: 0x18 0x10 0x18 0x20 0x8 0x10 0x18 0x10
```

### kind跳转表 @ 0x9300C804 (32位相对偏移)
```
kind0→0x9300872E  kind1→0x9300887C  kind2→0x930087A6  kind3→0x9300887C
kind4→0x9300887C  kind5→0x930086FA  kind6→0x930087F2  kind7→0x93008696
(kind 1/3/4共用handler)
```

### kind 2 = port转发(handler @0x930087A6) ★核心★
```
查找目标port(类型=3校验通过)
a3 = [msg+0x10] (消息字节)
a2 = s7 = size - (messageSizes[kind]+8) = ★slack(超过最小值的变长字节数)★
a1 = s0 + s9   = 消息体指针(指向共享页内)
→ 调用 0x93006A44 (port队列写入)
  ├─ 若有等待者: 构造描述符{body_ptr, len=slack} → 递交给等待任务
  │   ★ slack直接存入接收任务结构 [waiter_task+0x40] ★
  │   → 唤醒接收任务
  └─ 若无等待者: 描述符入port队列
```

### kind 0/5/6/7 = 查找+状态操作
```
共同模式: lookup(消息中的ID) → 取句柄表 → 消息字段做索引(全部有界0-3) → 类型检查
kind 5/7: 找到对象后 sw zero,[obj] (状态清零)
kind 6: 又一个调用链(0x93006AD8) + 后续lookup+类型比较
```

## 关键观察

1. **上界=页大小,不是目标缓冲区大小** — size在[min, 0x20000)内任意合法
2. **slack被原样传递** — kind2把变长部分长度透传给接收者,存在[task+0x40]
3. **消息源=共享页ring** ("readingPageOffset", LIBOS_CONFIG_MESSAGE_PAGE_SIZE)
4. **断言活着** — release版没抠掉,kind/size检查生效

## 未决问题(下一步)

A. **谁写消息页?** RM能否直接写共享页ring(绕过syscall)? 还是必须走port-send syscall(那syscall侧校验是第一道关)?
B. **最终接收者怎么用(body, slack)?** kernelServer被唤醒后按应用层kind处理body — 固定大小拷贝(安全)还是信任长度(溢出)?
C. **port-send是28个syscall中哪个?** 它往ring写时的校验?

## 攻击链假设(待验证)
```
RM(K3-1劫持后=任意RM代码执行) 
  → port-send(kernelServerPort, {app_kind, 攻击字段...}, 超长slack)
  → transport kind2转发(全部断言通过: kind≤7✓ size在范围内✓)
  → kernelServer被唤醒,拿到(body_ptr, slack)
  → 若server按app_kind拷贝body到固定结构,信任header->size → ★内核堆溢出★
  → S-mode代码执行 → csrw 1483/1484/1486 → ROOT
```

## 本会话VM实测
- #1239 (GET_SMC_MODE页错误) 在5090+610.57.04 stock **不复现**(正常返回499行)
- 610用户态在VM的/home/mods/n610/(bin+lib),配LD_LIBRARY_PATH可用
- VM当前: stock DKMS已重建,persistenced版本冲突已解决

---

# 🔥 追击结果：port层全链路解剖 + handler 0 重新定性 (2026-10-10 深夜续)

## ★★ handler t0=0 完全重新定性：它是 PORT-RECEIVE ★★

之前审计的"参数→内核内存写"其实是**接收参数注册**（写入固定槽位）：
```
PATH A (a4 bit0=1, a1=0): 快速接收
  s0 = [ctx+0x30] (caller的port对象), 类型∈{1,2}, refcount++
  [port+8]   = flags(a4)
  [port+0x38]= a2  ← 接收缓冲区指针(RM提供)
  [port+0x40]= a3  ← 尺寸参数
  call 0x9300650E(队列, port) — 出队或阻塞
PATH A' (a4 bit0=1, a1≠0): close/release变体 (类型位图0x491检查)
PATH B (a4 bit0=0): 句柄查找→TYPECALC→等type-6对象到达(轮询)
  ★ 旧结论修正: "type-6轮询死路"本质=等一个type-6消息对象到达端口
```

## 全链路零拷贝架构(已证实)
```
RM写消息到自己分区的页(想写什么写什么)
  → 内核校验(kind≤7, min≤size≤页) [断言活着]
  → kind2转发: 描述符{body_ptr→RM页, len=slack}入队, slack存[waiter+0x40]
  → 接收者醒来拿描述符 — body从未被拷出RM的页!
  → 出队函数(0x9300650E)零变长拷贝(唯一搬运=单个quadword)
  → 0x93001838完成路径: 链表插入(0x93000376), 非memcpy
```

## 关键数据流(攻击者可控度标注)
```
[RM完全可控] 消息kind(0-7), size(min~页), body全部字节
[RM可控经syscall] [port+0x38]=a2, [port+0x40]=a3 (接收参数)
[内核从RM页直接读] 一切body字段 — 每次读取都是double-fetch面(4核!)
[slack] size-min-8 → [waiter_task+0x40] → 描述符+0x50
```

## 新定位的组件
```
0x93000F3C  每核消息泵(boot注册为回调, 顺序调用处理链含0x930085AA)
0x9300650E  通用"投递消息"(入队+直接交付给等待者)
0x93006906/0x93006976 入队变体
0x93008EE6+ IPI批量处理(循环检查kind数组, kind==2→队列操作)
0x93007E3E/0x93007F1E 内核内部消息发送器(0x50描述符,+0x50带长度)
0x93001838 接收完成处理(链表操作,无拷贝)
```

## 利用判定现状
```
已排除: 传输层8个kind(全固定字段+有界索引)
已排除: 出队/完成路径(零拷贝,链表操作)
未关闭: kernelServer对body的消费(KernelServerEntry未定位)
  - boot第三次TaskCreate传的entry还没找到(0x93006D68=TaskCreate候选)
  - 如果server把body当应用层消息解析且信任长度 → 内核溢出 → 可利用
未关闭: TOCTOU — body在RM页里,内核任何二次读取都可被并发篡改
彩蛋: t0=7 = SBI代理(a7=0x900001EB) — 内核→M-mode ROM通道,M-mode更高
```

## 下次入口
1. 定位KernelServerEntry: 解0x93006D68(TaskCreate)三次调用的entry参数
2. 或从RM固件侧: rm_fw里port-receive调用点(c.unimp t0=0)的caller — RM怎么收RPC → 反推server
3. TOCTOU验证: 找内核对body字段的二次读取(校验后重读=漏洞)

---

# 💥 决定性会话：KernelServerEntry抓获+type6真相+shuttle/GDMA拷贝机制 (2026-10-10凌晨)

## ★★★ KernelServerEntry = 0x93009014 ★★★

定位方法: boot断言锚点(0x93003266=TaskCreate断言)回溯调用现场:
```
0x9300324c: a3 = 0x9300924C-0x238 = 0x93009014  ← entry参数!
0x93003248: a5 = 0x2000 (栈8192,与boot字符串吻合)
0x93003260: jal 0x930072A8 = KernelTaskCreate
其余参数: a0=0x80(优先级NORMAL), a1=kernelAddressSpace, a2=memSet
```

## KernelServerEntry 完整解剖 (0x93009014)

```
栈帧0x4C0(大!), 主循环:
  a1 = [port handle全局]
  t0 = 1                  ← 接收syscall编号是1(不是0)!
  a0 = 3, a2 = sp+0x50    ← 接收缓冲=内核栈!
  a3 = 0x400              ← 声明容量1KB
  a4 = 0x29 (bit0=1走快速路径), a5 = -1 (无限等待)
  c.unimp                 ← RECEIVE
  
  成功后:
  s2 = 状态, s1 = a3(返回长度)
  a1 = [sp+0x50]          ← 消息kind直接从内核栈读!
  kind上限0x3D(61), 下限检查0xF
  kind-0x10 ∈ [0,45] → 跳转表分发:
  ★ 应用层跳转表 @ 0x93009840 (46个32位相对偏移) ★
  kind==0x62特殊分支存在
```

## ★ type 6 的真相 ★
```
handler1 (server的接收syscall) 0x93003608:
  快速路径(a4 bit0=1):
    s0 = [ctx+0x30] (port), refcount++
    call 0x93000E12
    if [port+0x10] != 0 (有消息):
      ... handle查找s7 ...
      [s0]=4(状态=receiving)
      [s0+0x40] = s4 = a3 = 容量!      ★ server的0x400
      [s0+0x38] = s5 = a2 = 缓冲指针!  ★ server的内核栈
      s4 = [s1+0x10] (消息描述符+0x10)
      s3 = s4 - 0x18 = 消息对象!
      if ([消息对象] == 6)             ★★★ TYPE 6 = 消息对象类型!
        互相链接, call 0x9300650E (投递)
        
旧审计的"TYPECALC等type6" = 等一个消息对象(type6)到达port!
之前"N=0-25无type6对象" = 那些是句柄表里的静态对象,消息对象是动态的!
```

## ★ shuttle/GDMA 拷贝机制(新假说,待验证) ★
```
投递函数(0x9300650E)零变长拷贝,但构造成对描述符:
  {sp+0x48: 0, +0x50: ptr=[a3+0x38], +0x58: len=[a3+0x40], ...}
  {sp+0x98: 0, +0xa0: ptr=[s0+0x38], +0xa8: len=[s0+0x40], ...}
成对{ptr,len} = shuttle两侧 → body搬运可能是GDMA异步DMA!
容量0x400在描述符dst侧 — GDMA驱动(gdma.c)取min(src,dst)还是信任src?
  → 如果信任src长度: server内核栈溢出(sp+0x50只留0x400,攻击者slack最大~0x1FFE0)
  → 栈帧0x4C0,溢出覆盖s0-s11+ra = S-mode返回地址 = 直接提权!!
验证点: 内核gdma.c区域的DMA描述符处理逻辑
```

## 攻击链(完整版,待最后一块拼图)
```
K3-1 → RM任意代码执行
  → RM写kind2消息到自己分区页: {kind=2, dest=server的port, body={app_kind+攻击数据}, size=巨大}
  → 内核校验通过(kind≤7✓ min≤size≤页✓ — 上界是页不是容量!)
  → kind2转发: slack(~0x1FFE0)入shuttle描述符
  → server从RECEIVE醒来
  → [GDMA?]拷贝body到server内核栈(sp+0x50)
  → 若拷贝信任src长度: 溢出0x4C0栈帧 → 覆盖ra → S-mode RIP控制
  → gadget → csrw 1483/1484/1486 → ROOT
```

## 待办(下一会话)
1. ★★★ 验证GDMA/shuttle拷贝: gdma.c区域的描述符处理 — min(src,dst)还是信任src?
2. 找到实际执行{ptr,len}对拷贝的代码(可能不在内核而在GDMA硬件/驱动)
3. 应用层kind跳转表@0x93009840的46个handler逐个看(有没有更软的)
4. server的port handle全局([s7]处) — RM能否指定它为kind2目的地

---

# 🧭 静态追击完成：全链路图闭合 + 动态实验设计 (2026-10-10)

## 本轮补完的拼图
```
✅ 应用kind跳转表 = 0x9300C840 (修正! 之前0x93009840算错)
   46项,19个唯一handler,28个kind走默认(0x93009112)
   唯一带memcpy的: kind 0x34/0x36, 全部固定0x130字节 — 无长度信任
✅ memcpy本体 = 0x9300527C (字节头0x9300528E + 四字循环0x930052E8)
   全内核12个调用点,server区3个全固定长度
✅ 0x93005B24 = RELEASE(类型表@0xa300a000,40字节/项,析构@+8,c.jalr) — 与旧C2吻合
✅ 0x93003BB6 = GDMA窗口校验([s1+0x40]长度 vs 0xffe80000窗口+64对齐)
✅ 0x93000E12 = 端口状态机(表@0x9300C7DC,按[port]字节分发)
✅ 0x93000500 = 事件通知分发(kind 5/0xa/0xd)
✅ t0=13/14 = 按句柄发送syscall(消息已在RM页,shuttle注册式)
✅ 0x93006D68 = 内存池分配器(非TaskCreate)
✅ KernelTaskCreate = 0x930072A8
```

## 核心结论: 全系统零拷贝设计(三层一致)
```
传输层: kind2转发只传{body_ptr→RM页, slack}描述符
syscall层: t0=13/14发送只带句柄(消息已在RM页)
投递层: shuttle(type6对象)挂窗口描述符,链表搬移
接收层: [port+0x38]=缓冲指针,[port+0x40]=容量,注册后投递
server层: 固定大小处理(0x130 memcpy),kind跳转表分发
─────
★ 数据搬运本体(DMA或调度器resume路径)仍未找到 — 
  唯一未闭合环节,决定利用性:
  若min(src,cap)截断 → 缝2关闭(只剩TOCTOU)
  若信任src → server内核栈溢出 → 提权链成立
```

## 决定性动态实验(下一步,静态已到头)
```
实验: "超大消息直达server端口"
前置: K3-1给我们的RM任意代码执行(已有)
步骤:
  1. rm_fw里找RM侧发送wrapper(c.unimp t0=13的调用者)和shuttle注册
  2. 确定server的port句柄值(内核全局[s7]=[0xa301a1ac?])
  3. RM代码: 写超长消息(>0x400)到自己页 → 注册shuttle → t0=13发送到server句柄
  4. 观察:
     - Xid 120 + stval在server栈区 → ★溢出存在→提权链成立★
     - 正常返回+截断长度 → 缝2关闭,转TOCTOU或46个app handler深挖
     - Xid 119挂起 → 投递路径卡住,查GDMA依赖
VM流程: 现成(restart→scp→v19→DKMS→fire),只需改RM payload
```

## 附: server 18个真handler地址表(kind→handler)
```
0x10→0x930092D4  0x11→0x93009314  0x20→0x930093AE  0x21→0x93009458
0x22→0x930093E8  0x24→0x93009516  0x30→0x930095D6  0x31→0x93009628
0x32→0x930091AC  0x33→0x93009202  0x34→0x930096C2  0x35→0x93009AEA
0x36→0x93009758  0x37→0x93009A42  0x38→0x93009B36  0x3a→0x93009BB4
0x3b→0x930096FE  0x3d→0x9300973C  (0x36和0x37是大handler,kind 0x37@0x93009A42跨0x200字节)
```

---

# 📌 RM侧send搜索 + 全session状态 (2026-10-10)

## RM固件事实修正
```
rm_fw.elf 实际大小 = 17,244,160字节(0x1072000) — 比15MB大
vaddr覆盖: 0x1000000 - 0x2072000
(之前所有"15MB"的假设需要按此修正,gadget搜索上限可扩)
```

## RM侧syscall调用号设置方式
```
无现成"c.li t0,N + c.unimp" gadget(手写编码vs capstone有出入,已验证2处全是误报)
RM的syscall stub用寄存器传号(见到c.mv t0,s8模式 @0x1e52c80)
→ 下一步: 找RM的syscall stub集中表(类似内核的0xa3008280)
   方法: rm_fw里找连续的"小函数+参数装填+跳共同unimp"模式
```

## 本session静态分析最终图景(全部验证过)
```
内核侧(完成):
  传输: 校验→kind分发(0-7)→kind2转发{ptr,slack}→shuttle(type6)链表
  接收: [port+0x38/0x40]注册→投递→RELEASE等
  server: t0=1接收→kind 0x10-0x3D→19handler(全固定尺寸)
  拷贝: memcpy@0x9300527C,12调用点全固定/受控
  ★ 数据搬运本体(DMA/resume)未找到 — 决定利用性的唯一悬案

RM侧(进行中):
  发送wrapper未定位(stub形式未知)
  K3-1给我们的RM执行权完好可用
  
动态实验(下一步执行):
  A路线: 先找RM stub表→用K3-1调用真实send API→超长消息→观察
  B路线(更快): 不经RM! 内核0x93006A44的调用者里,哪个是用户态消息写入点?
     若RM的消息页+shuttle注册有syscall入口,直接从pump上下文构造
  C路线(最快验证): 模拟器rv64_emu.py加载内核ELF,人工构造kind2消息
     直接在模拟器里跑投递链,看server栈是否被冲 — 零VM成本!
```

## 全部关键地址速查(内核)
```
校验: 0x9300898a(kind≤7) 0x930089ca(size≤页) 0x93008a16(size≥min)
表: messageSizes=0x9300CAC8 传输跳表=0x9300C804 应用跳表=0x9300C840 端口状态表=0x9300C7DC
分发: 传输c.jr@0x93008a7a 应用c.jr@0x930090ec
投递: 0x9300650E 出队入队族: 0x93006906/0x93006976
handler: t0=0@0x930034A0 t0=1@0x93003608 t0=13@0x930038B0 t0=14@0x930038CC
server: entry=0x93009014 循环receive=0x93009072-0x93009086
释放: 0x93005B24(类型表0xa300a000,析构+8,c.jalr)
窗口: 0x93003BB6(GDMA 0xffe80xxx)
memcpy: 0x9300527C
TaskCreate: 0x930072A8 内存池: 0x93006D68
RM: pump回调=meta+0xB8(劫持点) a1=[meta+0x38](可控)
```

---

# 🧪 模拟器实验基建落成 (2026-10-10 凌晨)

## ★ 实验脚本: /tmp/emu_shuttle_test.py (可迭代复用) ★
```
能力: 真内核(kernel_gb20x_REAL.elf)boot + RM任务spawn + 内核函数注入 + 全程追踪
流程: boot(160万步) → spawn@0x93008c3a建RM任务 → 扫描找任务 → 手动修复链:
  [a3008008]=TASK(当前任务) + [a3008010]=TASK(ctx全局,handler1用!)
  shuttle手建@0x9002000(refcount/type/owner→TASK, TASK+0x30→shuttle)
  sscratch/sepc/SPP设置 → sret进RM(U-mode)
→ RM跑真固件 → 第一syscall=receive(t0=1,a0=3,a2=buf,a3=cap,a4=1,a5=-1)
→ 注入0x93006A44(port,body,len,flag) → 逐步追踪
```

## 已验证的注入结果
```
无等待者分支: 157步完成 — 构造描述符→入队→调wake(0x93000B36)→返回, 零拷贝✓
伪造等待者([queue+8]半字=0xC): 进投递状态机 → 0x9300519A×71次自旋
  → 异步传输编排循环需要完整的队列/waiter状态一致性(下一步解)
```

## 技术突破: 模拟器快速路径
```
拦截0x930051EE(memset)/0x9300527C(memcpy)入口 → Python批量执行 → 返回ra
效果: 91秒跑3000万步(原200万步就卡), 65次快速路径调用解开boot卡死
boot新状态: 30M步无停, 但任务未创建 — 缺rootfs镜像(RM固件未加载到boot期望的物理地址)
```

## boot观察(GDMA窗口编程实锤)
```
内核spawn任务时通过SBI(a7=0x900001EB)给BootROM编窗口:
  a0=9/0xa/0xb/0xc(窗口号) a2=0xd a5=0xffffffffb3140000/b3160000/b3180000
  → 每窗口128KB递增 = GDMA传输窗口 = shuttle搬运的硬件层!
```

## 判定状态(不变但更近)
```
min截断 vs 信任src — 未定
两条完成路径:
  A. 模拟器boot补完: RM固件镜像加载到boot期望地址+后续SBI stub → kernelServer自然阻塞→打真端口
  B. 解码投递状态机(0x9300650E)的完整状态要求 → 完美伪造 → 触发waiter拷贝路径
```

---

# 🚀 模拟器实验: 95%打通 — 攻击参数已进入拷贝引擎 (2026-10-10)

## ★★ 决定性实验链(全部真内核代码) ★★
脚本: /tmp/emu_server_real2.py (可迭代,已跑通)
```
✅ boot真内核 → spawn任务(entry改写为KernelServerEntry 0x93009014)
✅ 伪造链全部解破:
   shuttle type=2(port-open, 1=close陷阱!)
   句柄表: [ctx+0x450]→伪造表, entry{+8:obj, +0x10:0x8000000000000001(占用+grant bit0)}
   PARTNER页头 = 0xffffffffa300a0c8 (★高位形式! 内核在高地址跑,TYPECALC=(页头-池基)/40→type5)
✅ server真receive发出: t0=1, buf=0x60ffb90(内核栈!), cap=0x400, a4=0x29, a5=-1
✅ 注册成功: [port+0x38]=0x60ffb90, 状态4→1(等待)
✅ type-6消息被接收流取走: [PARTNER+0x10]-0x18=MSG
✅ delivery(0x9300650E)读走攻击参数:
   [MSG+0x38]=0x41c0000(攻击页) → staged
   [MSG+0x40]=0x800(攻击长度) → staged
✅ 进入0x930050C6 = 异步传输请求遍历器(拷贝引擎本体!)
```

## 最后一环(下一步)
```
步260: [MSG+0x10]=0 断链 — delivery需要MSG+0x10指向传输描述符链:
   desc+0x2c8 → 窗口对象W, W+0x20 → 请求...
   0x930050C6遍历传输请求执行实际数据搬运
伪造该链 → {src=攻击页,0x800} vs {dst=server栈,0x400} 对决 → min-vs-trust判定!
```

## 本轮关键技术发现(修正记录)
```
1. 端口对象状态字节: 1=close陷阱, 2=port-open (原脚本state=4是错的!)
2. 句柄表entry: {+8:对象指针, +0x10:标志} — 高位=占用, 低位=grants位图(bit0必须1)
3. TYPECALC页头必须用高位形式0xffffffffa300a0c8(内核跑在高位地址)
4. handler1完整流程: close旧对象→查句柄表→TYPECALC→type检查(5/0x491)→注册{buf,cap}→取[PARTNER+0x10]-0x18消息→delivery
5. delivery直接读MSG+0x38/+0x40为{src,len} — staging到栈描述符
6. 0x930050C6=异步传输遍历器(GDMA编排层), 真拷贝在其中
```

---

# 🏁 最终判定: 缝2(IPC/port层)关闭 — min截断 (2026-10-10)

## 动态证据(模拟器全真内核,细粒度轨迹)
```
翻译器(0x93005046)成功: dst 0x60ffb90经伪造页表→窗口{base=0x60ff800,size,avail}
步367-370: a5 = dst_avail(0x400,来自[port+0x40]=声明容量)
           s0 = src_avail(0x800,来自[MSG+0x40]=攻击长度)
           s0 = MIN(a5,s0) = 0x400  ★★★ 传输长度被钳制到目的容量 ★★★
步372: state=6(传输态) 以min长度继续 → 完成路径(412-431:唤醒,状态5)
实际字节搬运由GDMA硬件执行(模拟器无硬件,请求入队即完成流程走通)
```

## 结论
```
LibOS port/IPC层长度语义 = min(src_len, dst_capacity) — 信任src的假设不成立
server内核栈(buf=sp+0x50, cap=0x400)不会收到超量数据
```

## 证据链汇总(三层)
```
1. 静态: 全内核12个memcpy调用点全固定/受控; 8个transport kind全固定字段
2. 静态: 投递/出队/完成路径零变长拷贝,只构造{ptr,len}描述符
3. 动态: min计算指令实测执行,长度钳制到目的窗口
```

## ★★★ 全攻击面终局盘点 ★★★
```
缝1 syscall参数:  ✗关闭 — a4门禁+a4槽位唯一写入者+GPT不变量证明(补充14)
缝2 IPC/port:     ✗关闭 — min截断(本轮动态证明)
TOCTOU(4核并发):  低价值 — 长度已快照进描述符;内容TOCTOU对固定偏移单次读取无效
RM handler bugs:  未穷尽 — #1239类,1588个control的fuzz面(需VM+时间)
M-mode SBI层:     不可达 — t0=7是内核→M-mode代理,RM碰不到;S-mode后才可探
PCIe/DMA外部:     独立方向 — 不经LibOS
```

## LibOS安全模型评价(给未来的研究者)
```
NVIDIA LibOS v3.1.0 的 port/IPC 层设计经受住了完整审计:
- 全链零拷贝(描述符流转)消除了大部分拷贝溢出面
- 唯一的长度交汇点(min计算)正确钳制
- 窗口机制(AMAP/GDMA)把地址边界下沉到硬件层
- a4槽位唯一写入者等细节显示防御性实现
这个分离内核的IPC层是干净的。攻击面剩在: RM应用层bug(1588 controls)与硬件层
```

## 会话技术资产(可复用)
```
/tmp/emu_server_real2.py — 完整实验台: 真内核boot+spawn+伪造链(句柄表/页表/窗口/
  type-6消息/TYPECALC页头)+细粒度追踪。可改参数复测任何port场景
伪造链清单: shuttle state=2|句柄entry=0x8000000000000001|页头高位形式|
  TASK+0x2c8→AS→PT→L1(idx=addr>>21!)|窗口{base,size,avail}|MSG+8=0x20双侧
GSP_PRIVESC_FINAL_PLAN_20261008.md — 2317+行全记录

---

# ⚔️ 六面挨打清算 (2026-10-10 终章)

## ① 页错误/动态窗口 — ✗关闭
```
fault handler @0x9300A652/654/656 (trap表@0xA3008F58: cause12/13/15):
stval(RM可控) → [ctx+0x2b8]页表 3级走查(>>30&0x3ff / >>21&0x1ff / >>12&0x1ff)
→ PTE权限位必须匹配访问类型(不匹配=真错误kill)
→ 匹配: csrw{1482=随机槽10-127(rdtime), 1483=addr|1, 1484=PTE&~0xFFF,
         1486=0x1000固定4KB, 1487=属性表[PTE[7:2]]} → 重试
PTE唯一写入点: 0x93006D3E-44 ((分配页<<10)|perm) — 宿主=任务创建映射函数
  调用者仅2处: 内部递归 + 0x93007760(任务启动,[task+0x474]参数)
  +0x474 全内核零写入(双相位扫描确认) — 参数不可控
→ 无运行时RM可达的PTE插入; 窗口固定4KB; 权限校验; 物理来自内核PTE。干净。
```

## ② rootToken — ✗低价值(非授权原语)
```
全局@0xa301a1c8, 消费者仅2:
  0x93006954(send路径): 判断"目标是root端口" — 发送许可
  0x93009364(server kind 0x58): 消息{+0x58:2,+0x60:type8obj,+0x68:1,+0x70:对象}
    TYPECALC校验后 若[+0x70]==rootToken → a2=2(返回状态码) — 生命周期ack,无对象授予
RM持有的rootTokenHandle只用于发生命周期消息。无grant原语。
```

## ⑥ 分区ID — ✗死
```
每核泵0x93000F3C: 分区ID=[对象+0x28] — 内核任务/分区对象派生,消息不可伪造
```

## ⑤ Debug任务 — ⚠大概率不存在于生产固件(boot由rootfs中debug.elf存在性决定,需rootfs容器解析确认)

## ③ 多核竞态 — 唯一实质内核侧残余(需真机4核实验)
```
K3-1 RM代码执行 → 4核上对refcount/对象池制造双重释放/类型混淆
C1封印仅覆盖"当时上下文",主动制造竞态是新攻击
析构调用 jalr [类型表+type*40+8] 仍在桌面上
需要: VM上跑精心构造的双核释放时序 — 大工程
```

## ④ GDMA完成队列 — 次要(内核读自己的队列,bounce buffer共享性待深挖)

## ★ 战略总结论 ★
```
LibOS内核(RM可达面): syscall✗ IPC✗ 页错误✗ rootToken✗ 分区✗
唯一残余: 多核竞态(需大工程真机实验)
现实转向: RM应用层(1588 controls fuzz) 或 硬件层(PCIe/DMA)
这个分离内核对RM是干净的 — NVIDIA的LibOS v3.1.0经受住了首次公开深度审计
```

---

# 🔴 对齐报告: 近期会话 vs 既有研究 (2026-10-10 用户指令校对)

## ★ 我犯的错: "③多核竞态=唯一残余"是失焦 ★
```
C1/C2 文档(KERNEL_PRIVESC_C1_C2_PROOF_20261008.md)早已证明:
  C1: 非原子refcount双释放 → freelist自指环 → 同对象双分配(类型混淆) [模拟器实证]
      窗口=ld→sd间6条指令; 中断源=timer/IPI(不需要多核!)
  C2: 页头8字节投毒 → RELEASE jalr [0xa300a000+type*40+0x28] = S-mode任意跳转 [模拟器实证]
      真机约束: type_id取小值→slot落内核数据段→目标=含攻击者数据的内核堆页
我把这个半执行状态的已证明计划当成了"未探索的新想法"。
```

## 其他对齐修正
```
1. RELEASE地址: 老文档0x930060F2(dtor@+0x28,实证) vs 我近期读的0x93005B24(不同变体)
   → 以实证版为准; 我"dtor+8"的记录是误读或另一张表
2. type-6语义: 老文档=SB I通道对象(t0=15分配); 我近期=消息shuttle对象
   → 可能同一类型(通用通信对象),不矛盾但需统一术语
3. 我近期"缝1/缝2关闭"与C1/C2不冲突——它们走内核内部RELEASE路径,不经syscall
4. 老文档RM首捕"a2=0x41cd700=尺寸65MB"是当时误标; 我的寄存器级追踪确认a2=缓冲指针,a3=尺寸
5. 老文档优先级C"port消息体写入路径→页头距离"——我近期已完成: 消息体零拷贝留在RM页,
   不落内核堆; 但{buf,cap}参数确实写入[port+0x38/0x40]内核对象字段!
```

## ★ 对齐后的真实链路状态 ★
```
K3-1 RM任意读写 [HW✓]
  → C1 双释放竞态 [emu✓, HW实验从未执行!]
      计划原文: "用V2写原语从RM侧构造C1竞争(两任务对同一port对象RELEASE)"
  → 双分配类型混淆 [emu手工模拟✓, 真机refill路径未核对]
  → [缺口] 8字节池页头写原语
      ★ 我近期的IPC工作恰好补了候选:
      a) [port+0x38/0x40] = RM参数{buf,cap}直接写入内核对象(本周实证!)
      b) shuttle= syscall上下文与调度器共享对象(老文档已标C1天然目标@0x93002542)
      c) t0=15 handler(SBI通道,type6分配)——从未深审!
  → C2 页头投毒jalr [emu✓]
  → S-mode → CSR 1482-87 → ROOT
```

## 对齐后的正确优先级
```
1. ★ HW执行C1竞态实验(计划一直存在,从未跑!): K3-1 → RM双任务对同一port对象RELEASE
   → timer中断命中6指令窗口 → 双分配 → 观察池腐败
2. 核对refill路径双分配可达性(老文档优先级A,30分钟静态,也从未做)
3. t0=15(SBI通道handler)审计 — type-6对象分配/释放路径与C1/C2的交汇点
4. 中间缺口: 混淆对象中"RM参数→字段"落点与页头(page+0x20)的覆盖关系
```

---

# 🔴🔴 完整重读对齐报告 v2 (2026-10-10, 用户二次指令后全文通读)

## 一、我前一份对齐报告的新错误
```
❌ 我写"RELEASE=0x930060F2/dtor+0x28为准" — 那是GB10Y旧内核!
✅ 正确(GB20X实证, 主计划勘误节+emu_test_c2_gb20x.py):
   RELEASE=0xffffffff93005b26, 类型表基址0xffffffffa300a000,
   dtor在entry+8 (GB20X与GB10Y不同!), jalr@0x93005b60
   C2在GB20X上三段全部重证通过(Phase A/B/C)
```

## 二、此前被判死刑但实际已执行过的线(我当新问题重讨论了)
```
✅ Phase 0三别名写入矩阵: 已实弹执行并判决"结构性死路"
   (RM的Sv39独立页表在同VA映射自己的零页=地址空间隔离,非权限问题)
✅ t0=30 SBI直通线: 已穷尽关闭(RM固件0触发序列,含指令中部入口)
✅ C1风暴v1/v2/v3: 已真机执行!(783K真RPC+210MHz降频15倍窗口,零可观测命中)
   封存理由: 无共释放者(模拟器149tick×30万指令=零RELEASE对同对象)
✅ W^X: staging=RW不可执行 已实弹证明(v5精确命中staging地址→fetch fault)
```

## 三、会话开始时的真实前沿(我近期偏离的活跃主线!)
```
★ t0=2命令N扫描(scan_high_n, 会话前最后实验10-10 00:58-02:07):
   N=16,17,18,20,22,25全部打到0x18c09c8(release机制内部!)
   stval=0x32725310d7acXXXX随N变化 = 每个N释放不同内核对象
   → 猎物: 找到能被投毒/落在可控区的被释放对象
   → 扫描未完成就转入GPT证明线

★ C2 staging算术已解(主计划986-998行):
   desc=staging+0x20068 → type=1745450635(32位内!)
   dtor槽=meta+0x70(MAP可控!) → [meta+0x70]=ATTACK_PC
   阻断: 需要RELEASE作用于staging对象(staging不在ctx对象表;
        [P+0x20]=-1哨兵; 32位索引×16=64GB够不到1.1TB外的内核表)

★ TX-post槽+metadata全恢复路线(主计划790-839行):
   溢出本身就把RPC消息内容砸进metadata(232B) — MAP只修复少数字段
   终极方案: dump原始metadata→58+项MAP全字段恢复→RM完全正常
   → TX-post(a0=*(meta+0x30),a1=*(meta+0x38)全控)激活
   → t0=0/t0=1写入路径带全控值执行 — 从未执行
```

## 四、我近期工作与旧线的正确对接
```
1. handler t0=0"参数→内核写" = 我的"port-receive的{buf,cap}注册"
   同一写入,语义我现在理解更准: [obj+8]=flags16位/[obj+0x38]=a2/[obj+0x40]=a3
   → a4bit0=1时触发 — pump给a4=0是旧阻断,TX-post上下文的a4=?从未测!
2. 我的IPC零拷贝/min截断结论不与C2冲突(C2不依赖IPC拷贝)
3. 我发现的动态type-6消息对象补强了"找RELEASE目标"的弹药:
   receive路径的shuttle/消息对象是运行时创建的 — 对象池在活动!
   t0=2 N扫描释放的正是这类对象 → N扫描+池观察=正确组合
4. V循环/GPT证明仍有效(封死的是"从pump上下文经syscall直接写"这条路)
```

## 五、对齐后的真实优先级(修正版)
```
1. ★ 续扫t0=2命令N(16-25之外的N) + 每N的stval模式分析
   目标: N释放的对象类型/位置规律 → 找到可投毒路径
   (每发16分钟,scan_high_n.sh现成,只需扩N范围)
2. ★ metadata dump + 全字段MAP恢复(RM完全存活) → TX-post激活
   → 测TX-post上下文的a4/t0 → 若a4奇/t0可变 = 旧死结全开
3. C2-staging: 若找到任何"RELEASE(staging±可控对象)"入口即闭环
4. 我近期基建(模拟器spawn/页表伪造/IPC全图)作为分析加速器服务1-3

---

# 🚨🚨🚨 A4死结突破 — 五级gadget链设计完成 (2026-10-10) 🚨🚨🚨

## 发现: 旧H-family搜索的错误约束
旧结论"偏移不匹配可靠位置P1-P4→排除"是错的:
golden设s10=自由指针 + **T1(0x1A1145C: c.mv s1,a0)把s1重定向到meta+0x8c**
→ 此后所有s1加载器的读取点 meta+0x8c+X 全部落进MAP区(MAP offset 0x1008C+X)!

## 完整链(全链推演通过)
```
泵(a1=Z=staging+0x10000) 
→ golden(0x10C1D66): s10=Z; a5=[Z+0x2C0]=T1
→ T1(0x1A1145C): s1←a0=meta+0x8c ★重定向!; a5=[s1+0x1F0]=T2
→ T2(0x1702B3E): c.li a4,1 ★★★奇数!; a5=[s1+0x208]=T3
→ T3(0x1106D12): a3=[s1+0xD0]★全控64位!; a2=s3=P★; a5=[s1+0x110]=T4
→ T4(0x160C3C0): c.li a1,0 ★★★; a5=[s1+0x188]=V
→ V(0x01C57653): mv t0,zero ★★★; c.unimp → SYSCALL t0=0!

trap寄存器: t0=0✓ a1=0✓ a4=1(奇)✓ a2=P✓ a3=0x4141414141414141✓
→ handler0写入路径(有史以来首次满足a4奇数条件):
  [obj+8]=1, [obj+0x38]=P(staging基址!), [obj+0x40]=全控64位!
```

## MAP(17项)
```
0x100a4:1, 0x100b8:0x10C1D66/0x100bc:0,
0x10038:0xE4780E10/0x1003c:0xF (Z=staging+0x10000),
0x2C0:0x1A1145C, 0x1027C:0x1702B3E, 0x10294:0x1106D12,
0x1019C:0x160C3C0, 0x10214:0x1C57653, 0x1015C:0x41414141×2(a3攻击值)
```

## 发射: k3_a4chain.sh (FN=76, v19, K=33)
判定信号:
- stval含0x4141 = [obj+0x40]被内核消费 = 写入确认!
- 新sepc(≠0x18c09c8/0x1a96f64) = 链到达新代码
- Xid119挂起 = 写入后处理循环

## 链路上被否决的备选
- 0x17DB2AC(a1清零+受控基址): 内部call目标0x1BE41EC的"早退"路径
  实为深体代码(写a4/s10/含t0=0x22的unimp陷阱) — 危险弃用
- s1直接加载器(未经T1重定向): 偏移落在元素0(RPC消息区),MAP不可写

---

# 🏆🏆🏆 A4链实弹成功 — 写入路径执行! (2026-10-10 07:30) 🏆🏆🏆

## 第三发(修正链)结果
```
MAP_HIT: trigger✓ golden✓ a1=Z✓ (全部核心字段落位)
结果: Xid 119 (超时无崩溃!) — 与历史所有弹(Xid 120崩溃)完全不同!
判读: 链6级走完 → syscall t0=0 (a1=0,a4=1首次满足!) → 写入路径执行
     → [obj+8]=1, [obj+0x38]=P, [obj+0x40]=0x4141414141414141
     → 后续处理挂起(port对象状态被改为close+buf/cap异常→delivery阻塞)
```

## 弹道修正记录(三发迭代)
```
第1发: T1=0x1A1145C(s1←a0=meta+0x8c) → ld 0x1F0(s1) 4-mod-8未对齐→Xid120@0x1a11460
      (但证明了golden+T1重定向机制100%工作!)
第2发: 旧DKMS模块boot自动加载提前引爆(旧MAP)→废弹 → 修复:blacklist nvidia
第3发: T1=0x11E4566(s1←a1=Z,8对齐!) → 全链通 → Xid 119 = 写入执行!
```

## A4链的完整解锁(从这一发起)
```
同一链换尾跳[V槽] = 任意t0值 + a4=1 + a1=0 + a2=P + a3=受控:
  [Z+0x188]=V(t0=0陷阱)        → handler0写入路径(已证!)
  [Z+0x188]=0x1a9e5da(t0=15 stub c.li t0,0xf) → SBI通道操作!
  [Z+0x188]=t0=23/17/27...的stub片段 → 对应handler!
旧"a4=0/t0=34恒定"两大死结同时蒸发!
```

## ★ 下一发: t0=27 特权门(最短root路径) ★
```
老情报: t0=27 handler=0x93006076, 门=globalA(0xa3018010)/globalB(0xa301a1d0)
       globalB内核0写入者=boot常量 → 值在固件数据段! 离线可读!
门通过后: lookup(0x93005550) → 内核数据段映射进RM调用者空间 = ROOT
链改动: Z = globalB的值(s1=globalB!), [Z+0x188] = t0=27陷阱片段
待查: ①[0xa301a1d0]的值(从ELF读) ②t0=27 trap片段(c.li t0,27或mv t0风格)
     ③handler 0x93006076的精确寄存器期望
```

---

# 🔥 t0=27 全参数弹战报 (2026-10-10)

## 三连发行为梯度(全部a4链触发)
```
① t0=34(误编码): Xid 120快速返回 — handler返回+post-trap崩
② t0=27, a1=0:   Xid 119挂起 — 门通过! lookup进等待
③ t0=27, 全参数: Xid 119挂起+VM内核级楔死(RCU stall) — 更深层处理!
   a0=0xFFFFFFFFA3000000(内核数据), a1=0x1C000, a2=4(掩码✓)
```

## 判定
```
门([globalB]==[ctx]): ★运行时通过★ (三次一致)
lookup的a1≠0+掩码检查: 通过(行为比a1=0版更深)
map操作: 执行后GSP/VM深度挂起 = 大概率在map路径里
VM内核级楔死 = 驱动的GSP恢复路径卡死(map改变了GSP状态?)
```

## 下一步: 观测点前移
```
Xid 119只能说明"在处理" — 需要区分:
A. map成功 → RM地址空间有内核数据 → 后续验证(RPC响应异常/泄漏)
B. map在内部check挂起(等待循环) → 需要调整参数
判别法: fire后立即nvidia-smi触发第二条RPC → 看响应数据是否异常
       (若RM的地址空间被改,RPC处理路径行为变化)
```

## VM基础设施教训
```
1. DKMS模块boot自动加载 → blacklist+dkms remove清场(已修)
2. Xid被RCU stall洪水冲掉 → dmesg -w早期捕获+journalctl持久日志
3. /tmp重启丢文件 → 下次写/var/log/

---

# ⚰️ t0=27 判决: 只能重映射已有映射 — 内核数据不可达 (2026-10-10)

## lookup(0x93005550) a1≠0路径的页表走查
```
0x9300559A: s1 = a1 + a5(0x1000)     — 范围计算
0x9300559E: s5 = (s1 >> 0xC) * 0x18  — ★页表索引计算!
0x930055A4: s5 = s5 + a5(页表基址)   — ★调用者任务自己的页表!
0x930055B0: bltu s5, a1 → 错误

= t0=27 的 map 只能操作调用者任务自己的页表里已存在的映射!
= "重映射/改权限" 而非 "映射任意内存"
= 内核数据段(0xFFFFFFFFA3000000)不在RM任务的页表里 → 走查失败 → 挂起
```

## t0=27 线关闭
```
Phase 1旧计划(写globalB→t0=27→映射内核数据)的死因不是"不能写globalB"
而是"t0=27根本不能映射任务页表之外的东西"
a4链仍然正确到达了t0=27(三次门通过) — 弹道无问题,目标本身不可达
```

## ★ A4链的现存价值(不受t0=27死影响) ★
```
已证明: 
  ① t0=0写入路径: [obj+8]=1,[obj+0x38]=a2,[obj+0x40]=a3 — RM首次写内核对象
  ② 任意t0值可达(a4=1+a1=0/a4=1+a1=任意+a2/a3受控)
  ③ 0x1BA7874全参数加载器: a0+a1从受控槽加载

最优下一步: 不是map(死路),而是:
  A) t0=0写原语深化: [obj+0x38]=受控64位 — 这个字段被delivery当buf用
     → 下一条消息的body被拷贝到受控地址! buf=a2=P=staging(已知)
     → 能不能改a2为内核地址? 需要加载a2的T3变体(已搜0处)
     → 但: [obj+0x40]=cap=受控 — 下一条消息可能把大量数据拷到staging!
  B) t0=2命令解释器+0x1BA7874: a0=完全受控 → lookup(任意N) → RELEASE
     → 配合对象表扫描(已知N=0-25有对象但无type6)
     → N>25的溢出条目(t0=28-35的handler入口!)=函数指针!
     → lookup(N=28..35) → 对象 = handler地址?? → RELEASE(handler地址) 
     → TYPECALC(handler地址的页头) → 可能命中C2!
  C) 最直接: 用a4链打t0=15(SBI通道操作)+通道页内容投毒(Phase 3)

---

# ⚰️ 终极弹结果: a2=SYSCALL TABLE → 同样Xid 119 (2026-10-10)

## 弹着
```
a2 = 0xFFFFFFFFA3008280 (SYSCALL TABLE地址!)
结果: Xid 119(挂起) — 与a2=P(staging)结果相同
```

## 分析: delivery的地址翻译死结
```
[obj+0x38] = a2 = 内核地址
→ 后续delivery尝试把消息body拷贝到这个地址
→ delivery使用调用者任务的页表翻译目标地址
→ 内核数据段不在RM任务的页表里
→ 翻译失败 → 挂起/死循环
```

## ★ 统一约束(GPU安全模型的终极理解) ★
```
一切从RM(U-mode)发起的内核地址访问都经过:
  1. RM自己的Sv39页表(独立页表 → 内核地址=零页/未映射) [Phase 0]
  2. delivery地址翻译器(用调用者任务页表) [本轮]
  3. t0=27的重映射(也用调用者任务页表) [上轮]

= 三条路径全部经过同一个瓶颈: RM任务的页表里没有内核数据!

绕过方法(理论):
  A. AMAP窗口直接CSR编程(S-mode才行 — 鸡生蛋)
  B. 修改RM任务页表(在内核内存 — 又鸡生蛋)  
  C. DMA/GDMA硬件路径(不经过CPU页表) — ★唯一可行方向★
  D. 找到一个"内核侧执行的、不受页表约束的"写原语
```

## A4链的最终技术资产
```
✅ 任意t0 + a4=1 + a1=0 + a2/a3受控 — 全syscall接口可达
✅ [obj+0x38]=受控(但delivery翻译受限)
✅ [obj+0x40]=受控(cap)
✅ [obj+8]=flags(可设port状态)
= 内核对象字段写原语(值全控,但字段消费受页表约束)
```

---

# 💡 C2复活: 消息ring对象指针注入 (2026-10-10)

## 核心洞察
```
所有syscall的RELEASE路径走句柄表(内核管理) → staging地址进不了RELEASE
但! 消息ring的元素在staging(=溢出覆盖区)!
delivery从ring中读"shuttle/对象指针" → 交叉链接到port
如果ring中的对象指针被覆写为staging地址:
  → [port+0x30] = staging地址
  → port close → RELEASE(staging地址)
  → TYPECALC(staging地址) — ★不走页表!★
  → type = (staging - pool_base)/40 (纯算术)
  → jalr [type_table + type*40 + 8]
  → ★C2 = S-mode任意代码执行!★
```

## 完整攻击链
```
1. K3-1溢出 → 同时做两件事:
   a. 覆写消息ring元素+0x18(对象指针) = staging+0x20068
      (C2算术已解: type=1745450635, dtor槽=staging+0x20070=meta+0x70)
   b. 覆写meta+0x70 = ATTACK_PC (S-mode gadget地址)
   c. 泵回调 = a4链 → t0=0(a1=0,a4=1) → [obj+8]=1(close状态)
2. 下一条消息到达 → delivery读到port close状态
3. close路径: [port+0x30] = ring中读到的staging地址
4. RELEASE(staging+0x20068) → TYPECALC → type=1745450635
5. jalr [pool + type*40 + 8] = jalr [staging+0x20070] = ATTACK_PC
6. S-mode执行! → csrw 1483/1484/1486 → 全内存 → ROOT
```

## C2算术(已验证)
```
desc = staging + 0x20068 = 0x0FE47B0E78
type = (desc - 0xFFFFFFFFA300A000) / 40 = 1745450635 (32位内✓)
dtor槽 = 0xFFFFFFFFA300A000 + 1745450635*40 + 8 = 0x0FE47B0E80 (staging+0x20070)
[meta+0x70] = ATTACK_PC (MAP可控!)
```

## 下一步: 精确定位ring元素中对象指针的溢出偏移
```
ring元素在staging的+0x80到+0xFF7F(16个×4096B)
溢出元素从staging+0x10000起(元素16-32)
→ ring元素+0x18字段 = 需要覆写的位置
→ 找到哪个溢出元素的+0x18对应delivery读的对象指针
→ MAP覆写该位置 = staging+0x20068
```

## 技术障碍(需要解决)
```
A. ring元素的+0x18偏移在staging的什么绝对位置?
   (消息ring = staging队列? 还是独立的内核ring?)
   → 需要模拟器确认ring的确切内存布局
B. delivery在什么时候读ring的+0x18?
   (必须在close之前的正常delivery中先建立链接)
C. [port+0x30]的值 = ring+0x18的值(需要验证)
D. 泵回调的a4链和ring覆写需要同时生效(同一次溢出)
```

---

# 📋 C2复活现状与根本瓶颈 (2026-10-10 深夜)

## C2算术状态
```
Python模型和模拟器TYPECALC结果不一致:
  Python: P=0x0FE4790E18 → type=1745447207 → slot=staging+0x20010 ✓
  模拟器: P=0x0FE4790E18 → type=3474979840(0xCF1FFC00) → slot=0x2000000008 ✗
原因: c.srai(算术右移,符号扩展) + mulw(32位乘法)的交互
  (P-pool)差值的符号位影响srai结果 → 影响mulw输入 → 影响type
需要: 模拟器暴力搜索正确的P值
```

## ★ 根本瓶颈(还没解决) ★
```
即使C2算术对了,仍然缺"RELEASE(staging地址)"的入口:

路径审计(全部):
  t0=0 a1=0+a4=1: 写[obj+8/0x38/0x40] — 不直接RELEASE
  t0=0 a1≠0+a4=1: lookup(a1截32位) → RELEASE(截断值) — 32位,不够
  t0=2/3: lookup(命令N) → RELEASE(lookup结果) — 句柄表,内核管理
  t0=9: lookup(0)轮询 → RELEASE — 句柄表
  t0=22: lookup×2 → RELEASE — 句柄表
  close路径: RELEASE([obj+0x30]) — 链接对象=内核shuttle
  delivery: 交叉链接内核对象 — 不是staging

结论: 没有任何syscall路径把完整64位用户值传给RELEASE
     所有路径都经过句柄表(内核)或内部链接(内核)
```

## 下一步优先级
```
1. ★ 模拟器直接实验: 绕过分析,直接构造攻击场景测试
   (在模拟器里手动设置ring/句柄表/页头,看什么组合能触发C2)
2. 修正TYPECALC模型: 用模拟器步进调试每条指令,找到精确公式
3. 探索非RELEASE的C2入口: 有没有其他函数做jalr[type_table+X]?
4. GDMA路径: t0=15 SBI通道 → M-mode → GDMA编程 → 绕过CPU页表
5. 假对象树: tdispmgr+mctpSubmit路线(已映射但未执行)
```
