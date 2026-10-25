# RTX 5090 (GB202) L2 Slice / Memory-Partition 逆向任务

设备:NVIDIA GeForce RTX 5090 / GB202 / sm_120,Driver 610.43.03,CUDA 13.3。
Arch Linux 7.x,单卡 + 9950X3D(带 RDNA2 iGPU,当前 BIOS 关闭)。

## 动机(为什么做,划定用途)

**目标是给 CUDA/ML kernel 用**——这些负载**我们自己控制显存分配**,所以能主动做 slice 感知的数据放置:
- 把数据**铺满 48 个 L2 slice**拿满并行读带宽;
- **避开热点 slice**(实测均匀访问都有 ~10% 负载不均 = 木桶效应,散射访问更糟);
- slice 感知地用 **persisting set-aside**(≤60MB)钉热数据。

**明确不为图形/游戏**:图形管线够不到 L2 放置控制,且实测该类负载瓶颈是 MLP 饥饿不是 L2 端口。别往那个方向漂。

## 已确立的事实(别重做,直接承接)

- **48 个 LTS(L2 slice)**:ncu `lts__t_sectors_op_read.sum / .avg = 48.0` 精确,多次复现,板上钉钉。
- **16 个内存控制器**:DRAM 峰值读带宽实测 1.94 TB/s = 512-bit × ~30Gbps GDDR7 ✓ → **48 slice / 16 MC = 每控制器 3 slice**(待family A验证)。
- **L2 = 96MB,line = 128B(4×32B sector)**(承接 RT cache RE)。
- **延迟(锁频 2.895GHz 实测)**:L1 命中 44cyc/15ns(有效容量 ~89KB,90KB 拐、96KB 崩);L2 命中 114ns(小工作集/TLB热)→ 281–296ns(大工作集);DRAM 312ns。满载竞争时每次访存 **+~313ns 恒定排队**(延迟拥塞非带宽,DRAM BW 仅 9%)。
- **persisting set-aside**:`cudaLimitPersistingL2CacheSize` 本卡最大 60MB;`accessPolicyWindow` 可用。
- **失败教训(必须绕过的坑)**:naive 连续块 + ncu rollup(sum/avg/max/min)测 slice 映射**失败**——① 桌面背景 GPU 流量均匀铺满 48 slice、淹没探针;② 小块读被 L1 吸收根本不到 L2。**必须**:L1 bypass + 背景隔离 + 冲突式或 per-instance 观测。

## 家族 A:读/写端口 & slice 特性

- 复核 48 LTS;测**每 slice 读带宽**(bytes/clock/slice,sector/clock/slice)——用锁频独占下的峰值 L2 读带宽 ÷ 48。
- 验证 **16 MC × 3 slice = 48** 的分区结构(FBP/MC↔slice 映射)。
- 写端口是否对称(`lts__t_sectors_op_write`);slice 内是否再分 bank。
- L2 关联度、替换策略(承接 RT RE 已知 128B line;补 set/way)。

## 家族 B:地址 → slice 的 hash(★核心,即"写物理地址")

**目标:给定一个(物理)地址,判定它落 48 个 slice 中的哪一个,并反推 hash,做出可验证的"把数据放到指定 slice"原语。**

- NVIDIA slice select 是**地址位的 XOR hash**(故意打散,非简单取模)。要解出:哪些地址位 XOR 成 slice-select 位、interleave 粒度(每 slice 连续多少字节才 wrap)。
- **两条观测手段(至少落一条)**:
  1. **冲突式 RE(不需 per-instance 索引,首选)**:两个地址同 slice ⟺ 一起访问时计数器**集中**(max/avg↑)、否则**铺开**(max/avg→1)。用 pairwise 冲突找"同 slice 等价类",像 CPU LLC slice 逆向那样解出 hash。**前提是先把背景隔离干净 + L1 bypass,让 max/avg 真反映目标流量**(这正是上次失败点)。
  2. **per-instance 索引计数器(能拿到更好)**:ncu CLI 只给 rollup;要看"第 N 号 slice 亮",需 **CUPTI PerfWorks range profiler 的 instance 级输出** 或 ncu 报告导出后逐 instance 读。拿得到就能直接"打一个地址看哪个 slice 计数涨"逐位解 hash。
- **物理地址问题**:slice hash 作用在**物理地址**上;device 显存的 VA→PA 用户态拿不到。**绕法**:在**单个大页/大连续分配**内做 RE——页内 offset ≈ PA 低位偏移,hash 若只用低位(页内)则"buffer 基址 + offset → slice"可解且足够做放置;若 hash 吃高位则需确认 PA 手段(host-pinned 用 `/proc/self/pagemap`;device 端记录不可得时以相对 offset 表征)。先测 hash 依赖的最高地址位,判定是否需要绝对 PA。
- **L1 bypass**:`__ldcg` / `ld.global.cg` / volatile / streaming,确保读真到 L2 而非 L1。

## 家族 C:测量隔离(把背景 L2 流量清掉)

上次探针被桌面合成器流量淹死。要让 5090 的 lts 计数器只反映探针流量。

**★本阶段硬约束:不许碰桌面。** 不停显示管理器(`gdm`)、不切 TTY、不改显示路由、不动 iGPU/BIOS——桌面保持正常运行(用户要保留)。本阶段隔离**只走软件排除法**:

- **统计扣除(本阶段主手段)**:先**不带探针**采每-slice `lts` 背景基线(多轮取中位数),再**带探针**采,**差分**得纯探针信号。配合:关 Chrome/停动画让背景低且稳、静止桌面;探针多轮取中位降噪;能取 per-instance 索引更好(逐 slice 扣)。
- **冲突式 RE 用差分不用淹没**:hash RE 需要小地址集,不能靠"多灌自己流量"稀释背景;两地址同 slice 与否,看**扣背景后**的 max/avg 集中度。

**消源方案(无头 / 桌面路由 iGPU)= 下一阶段,且必须用户显式批准后才动**,本阶段禁止。

**MIG 不可用**:GeForce 5090 无 MIG(数据中心卡才有),别去试"独占一半 L2 实例"撞墙;L2 整块共享、48 slice 对所有 SM 全可见,切 SM(green context/TPC mask)**不隔离 L2 计数器**。

**为什么不能靠"控 L2"排除桌面**:① L2 旋钮(persisting/evict hint)只作用**本进程**,碰不到桌面这个**另一进程**;② `lts` 计数器数的是 **lookup 次数**,命中/未命中/`no_allocate`/bypass **一律计数**,桌面请求过 L2 转发就 +1 → 污染**只能消源或统计扣除**,不存在"桌面 bypass L2"的排除法。

## 方法(承接本项目已验路子)

1. 锁频独占(`nvidia-smi -lgc/-lmc`,跑完 `-rgc/-rmc`),消除频率抖动,cycle/带宽可比;
2. 计数器需 root(`RmProfilingAdminOnly=1`),ncu/CUPTI 走 sudo;
3. 先把家族 C 隔离做干净,再做 B 的冲突式/per-instance 观测,否则重蹈上次覆辙;
4. 冲突判据用 `lts__t_sectors_op_read` 的 max/avg 集中度;能取 per-instance 更好;
5. 每个结论标 **verified / inferred / unknown**,别把推断写成事实。

## 交付物

- `L2_SLICE_MAP_FINDINGS.md`:48 slice 确认 + 每 slice 读/写带宽 + MC↔slice 结构 + **地址→slice hash 函数(XOR 位式)+ interleave 粒度 + 是否吃高位/需绝对 PA** + 置信标。
- **可跑原语**:`place_on_slice(buf, slice_id)` / `spread_across_all_slices(buf)` 的最小实现 + 验证(计数器证明数据确实落在目标 slice)。
- **对照 demo**:同数据量下 "48-slice 铺开" vs "全挤 1 slice" 的 L2 读带宽比(应 ≈48×),坐实 slice 并行度可控。
- 复现脚本(隔离 → 锁频 → 探针 → 解析)+ raw 计数器数据。
- 隔离方案落地记录(用了无头还是 iGPU,怎么恢复)。

## 护栏(硬性)

- **只读观测 + 自有分配**:靠计数器和自己的显存做 RE,不碰别的进程内存;
- **★本阶段不许碰桌面/显示**:不停 `gdm`、不切 TTY、不改显示路由、不动 iGPU/BIOS、不试 MIG。要动这些先回报用户等批准;
- **绝不**刷/改 vBIOS、固件、绕签名、写 MMIO/PCIe config;
- 锁频(`nvidia-smi -lgc/-lmc`)**必须可逆 + 跑完 `-rgc/-rmc` 恢复**,并记录;
- watchdog + 显存上限(参考本项目 64MiB/1% 空闲惯例),别把卡跑挂。

## 停止条件

家族 A + B 解到置信标、`place_on_slice` 原语验证通过、48×带宽对照 demo 成立;家族 C 至少落地一条干净隔离。产出报告 + inferred/unknown 清单。**不为图形/WuWa,不追求整条内存子系统完整**——只交付"能主动控 48 个 L2 slice 放置"这一件事的验死结果,给 CUDA/ML 用。
