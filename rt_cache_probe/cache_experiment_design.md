# RTX 5090 RT 缓存内容、层级与共享域：下一轮微基准设计审查

日期：2026-07-11；实验状态更新：2026-07-12  
审查对象：`agent_optix/minimal/gas_sweep.cpp`、`sweep_device.cu`、现有 timing / prime–probe / L1TEX counter 结果  
说明：正文保留最初的设计审查；2026-07-12 的“实测更新”段落记录其后已经运行并落盘的实验，
以免把历史计划误读为当前状态。

## 结论先行

现有数据已经很强地证明了下面这个较窄事实：

```text
循环访问 16 个不同的起始 GAS traversable 时，上层驻留命中；
加入第 17 个后，几乎每次 traversal 都重新向 L1TEX 请求 4×32B，
并增加约 27 cycles。
```

但当前源码中的 forced-miss 射线从原点沿 `-Z` 发射，而唯一三角形在 `z=+1`。
因此该射线大概率在起始 GAS 的外层包围范围就被拒绝，尚未证明它访问了内部
BVH node，更没有证明它访问了 primitive。当前最稳妥的名称仍应是：

> **16-entry starting-traversable/root-record residency structure**。

它可能是 TTU complet L0 的 root line，也可能是 GAS 启动描述符、root header、
handle-address translation/front-end record。现有“root/complet cache”结论还差一个
决定性控制：**保持起始 handle 不变而改变同一 GAS 内实际访问的 node/path**。

NVIDIA 专利术语里 root 本身就是第一个 complet，并没有另行公布一块“root cache”。
本文出现的 `root-only/start` 指一种**实测行为候选**：目前只观察到起始/root访问驻留，
尚未证明同一结构也驻留 interior complets；它不是在声称官方设计中有第三块独立 root cache。

下一轮最小、最高判别力的顺序是：

1. `optixTraverse()` + “根外 miss / 进入根但穿过 child gap / leaf hit”三路控制；
2. direct GAS、多个 IAS→同一 GAS、多个 IAS→不同 GAS、单 IAS 多 instance 的层级因子实验；
3. 单一固定 GAS 内的多 target path，区分 root、内部 complet、geometry descriptor 与 primitive；
4. 16-entry eviction-set / replacement 序列，区分总容量与 set conflict；
5. L1 trash 夹心实验，确认候选层位于普通 L1TEX 之上；
6. `%smid` 分层的跨 launch prime/probe，最后才判断 per-SM、per-TPC 或更大共享域。

完成 1–3 后，可以回答“16 项里面装什么”；完成 4–5 后，可以回答“它如何替换、
位于哪一级”；完成 6 后，才有资格在容量前加“每 SM”或“每 TPC”。

## 一、现有基准能证明什么、不能证明什么

### 已被直接支持

- Sattolo 环、same-handle、ring-only、packed/padded 地址布局和 prime–probe 一致支持
  `C=16` 的不同起始 GAS 驻留阈值。
- one-pass L1TEX 原始整数表明，K=17 后每次不同 GAS traversal 多出 4 个 32B
  sector lookup；这些 lookup 基本命中普通 L1。
- `guaranteed-hit` 与 `forced-miss` 有相同的 16→17 共模台阶，当前信号不属于
  closest-hit 或 primitive-hit 独占部分。
- same-handle 循环平坦，说明循环次数、entry table、`clock64()` 本身不是阈值来源。

### 仍然混在一起的候选

| 候选内容 | 为什么仍与现有数据相容 |
|---|---|
| 起始 traversable / GAS handle 描述符 | K 唯一变量正是起始 handle；forced miss 不必进入内部 BVH |
| GAS root header / root complet line | 启动 traversal 至少需要读取 root 信息；每项 128B backing 很吻合 |
| 通用 complet L0 | root complet 可能只是它在当前 workload 中唯一被访问的 line |
| 地址翻译/front-end record | distinct AS base address 同样会形成 16-entry 地址相关结构 |
| 普通 cache 的特殊 conflict | padded 已明显削弱该解释，但尚无系统 eviction-set/address-bit 映射 |

其中 root line 是目前最符合 NVIDIA 已公开 TTU 数据流的解释；把 start descriptor/front-end
保留在表中，是因为公开 OptiX 不暴露实际请求地址，现有 probe 也没有让同一 handle走不同内部路径。

### 当前报告里最需要收紧的一句话

不宜直接写“只在访问不同 GAS/root 记录时生效”。当前只确认“不同**起始 GAS**”
触发；`root record` 是最简硬件解释之一，还不是由同一 handle、多 node 实验独立证明的内容类型。

## 二、统一的实验执行器：只新增，不改基线

建议复制现有最小工程到一个新 target，例如：

```text
experiments/rt_structure_probe/
  structure_probe.cpp
  structure_device.cu
  structure_params.h
```

不要在已出正式结果的 `agent_optix/minimal` 上继续堆 mode。新执行器只需要三类抽象。

### 1. `RaySpec`

```cpp
struct RaySpec {
    OptixTraversableHandle handle;
    float3 origin;
    float3 direction;
    float  tmin;
    float  tmax;
    unsigned expected_hit;
    unsigned expected_primitive;
    unsigned expected_instance;
};
```

正式计时路径使用 `optixTraverse()`，随后只查询
`optixHitObjectIsHit()`、`optixHitObjectGetPrimitiveIndex()`、
`optixHitObjectGetInstanceIndex()` 做 checksum；不调用 `optixInvoke()`，也不执行
miss/closest-hit。保留现有 `optixTrace()` 作为交叉验证。若编译器/API允许空 payload pack，
正式 traverse pipeline 把 `numPayloadValues` 设为0；所有场景保持同一份最小 SBT、相同
`SBToffset/SBTstride/missSBTIndex`，避免把 SBT 选择变化误当成 traversal cache。

### 2. 小型 sequence interpreter

每轮执行预先生成的只读操作序列：

```text
TRACE(ray_id)       traversal，不计时
PROBE(ray_id)       traversal，单独记录 clock64 差
LOAD_L1(index)      普通 global pointer chase，用于 L1 trash
SCRUB(first,count)  用 disjoint traversables 清候选 16-entry 层
STAMP               记录 smid、laneid、clock64
```

这样 prime、evict、refresh、victim probe、L1 trash 和 ownership 都使用同一个内核，
不会因为不同 raygen 程序或 SBT record 引入额外变量。

### 3. 每项必须输出的元数据

- host `OptixTraversableHandle`；
- device 端 `optixGetGASPointerFromHandle()` 返回值（GAS case）；
- AS output buffer VA、大小、stride、allocation seed；
- source build / relocation clone / compacted clone；
- primitive 数、build-input 数、instance 数、build flags；
- 每条 ray 的 expected hit / primitive / instance 与实际 checksum；
- `%smid`、`%laneid`、每个 probe 的 raw cycles；
- `clockRate`、温度、功耗、utilization 的只读快照；
- 独立 process/context/run seed，而不只记录 launch 内 sample。

### 4. 先做一个便宜的 handle-decode negative control

循环不同 handle，但只调用 `optixGetGASPointerFromHandle(handle)` 并 checksum 返回指针，
不 traversal。若这里也有 16→17 台阶，优先解释为公开 handle decode / address structure；
若平坦，只能排除这条公开 intrinsic 路径，不能完全排除 RT front-end 内部描述符缓存。

## 三、P0：先区分 start record 与真实 BVH complet

### 几何与三条射线

构建一个固定的“双岛”或“四岛” GAS：左右各放一组小三角形，中间留出明显空隙。
GAS 的总体 AABB 覆盖中央空隙，但各 child/leaf AABB 不覆盖它。不要用只有一个三角形的 GAS，
因为它可能没有可区分的内部层级。

为每个 GAS 定义：

| ray | 路径意图 | 作用 |
|---|---|---|
| `outside-root` | 与现有一样沿 `-Z`，不进入 GAS bounds | 只测 starting traversable/root header 候选 |
| `inside-root-gap` | 沿 `+Z` 穿过总体 root AABB 的中央空隙，但不进入 child leaf | 至少要求 root/complet 做 child-box 测试，不走 primitive |
| `leaf-hit` | 沿 `+Z` 命中一个岛内三角形 | root + deeper complet + primitive 路径 |

“inside-root-gap 确实进入 root”不能只靠几何意图断言。必须用以下两项确认：

1. 冷状态下它相对 outside-root 有稳定的额外 RT cycles / L1TEX sectors；
2. paired smoke ray 命中同一岛，并验证 primitive index。

若 builder 把所有 primitive 压进一个 root leaf，使 gap ray仍触发 primitive test，就增加每岛 primitive
数量和岛间距，直到 cold traffic 清楚区分；OptiX 的 BVH 是 opaque，不能从输入图形直接宣布 node 数。

### 工作集

对三条路径分别做：

- K 个独立 build、同几何、共享同一 vertex buffer；
- K 个独立 build、同几何、独立 vertex buffer；
- build 一次后用 `optixAccelGetRelocationInfo()` + `optixAccelRelocate()` 制造 K 个
  拓扑等价 clone；
- K 个不同 leaf 内容但保持相同总体 root bounds 的 GAS；
- same-handle 控制。

relocation clone 很重要：现有“K 个相同三角形”只是输入数值相同，AS 是在不同目标地址上分别 build 的，
不能假定 opaque output 字节或内部编码相同。

### 判读

| 观察 | 最强解释 |
|---|---|
| 三条 ray 都只有同一个 16-entry / 4-sector 台阶 | 16 项主要跟 starting record/root header 相关；尚未看到 deeper cache |
| outside-root 为 16，gap 在相同位置另多一份 refill | start 与 complet 可能是两个结构，或一次 traversal 需要两条 line |
| outside-root 为 16，gap 的阈值提前 | 多条 complet line 共享同一个 16-line 数据 RAM |
| same handle 下，切换不同 gap/leaf path 也出现容量台阶 | 直接证明内容不只是 handle/start record，而包含 GAS 内 node/path |
| relocation clone 与独立 build 完全相同 | cache 按 AS/root 地址而不是几何内容识别 |
| 不同 leaf 内容、相同 root bounds 只影响 leaf-hit | outside-root 信号属于 root/start；primitive/deeper 内容被成功隔离 |

这是整个后续调查的第一道 gate。若 same-handle 多 path 始终没有任何新阈值，就不应把 16 项叫作
“通用 BVH node cache”；应继续叫 start/root residency structure。

## 四、P1：IAS / GAS 因子实验，定位层级与共享 bank

所有层级实验都用上节的 `inside-root-gap` 几何，确保射线穿过 IAS、进入 child GAS root，
又尽量不访问 triangle primitive。正式路径使用 `optixTraverse()`。

新 pipeline 必须使用：

```text
OPTIX_TRAVERSABLE_GRAPH_FLAG_ALLOW_SINGLE_LEVEL_INSTANCING
maxTraversableGraphDepth = 2
```

不要复用当前 `ALLOW_SINGLE_GAS` / depth 1 的 pipeline。

### 五个最小场景

| 场景 | 起始 top | instance/path | child GAS | 主要变化量 |
|---|---:|---:|---:|---|
| G | K 个 direct GAS | 无 | K unique | 当前基线：starting GAS/root |
| IS | K 个单-instance IAS | K unique | 1 shared GAS | top IAS/root/instance 变化，bottom root 固定 |
| IU | K 个单-instance IAS | K unique | K unique GAS | top 与 bottom 同时变化 |
| TS | 1 个含 K instance 的 IAS | K target paths | 1 shared GAS | top 固定，IAS node/instance 变化，bottom 固定 |
| TU | 1 个含 K instance 的 IAS | K target paths | K unique GAS | top 固定，IAS node/instance 与 bottom 变化 |

`TS/TU` 中把 instances 通过 transform 放到空间上分离的位置，每条 ray 只瞄准一个 instance。
每个 target 先用 paired hit smoke 验证 `instanceIndex`，正式 gap ray再穿过该实例所包围的 child GAS 中央空隙。

### 为什么这组比“给现有 GAS 套一个 TLAS”更有信息

假设每个变量 root 恰好对应一条 128B complet line，仅作为预测示意：

- 若 IAS root 与 GAS root 共用一个 fully-associative 16-line cache，`IS` 的总 resident set
  近似 `K 个 IAS root + 1 个 shared GAS root`，台阶应比 direct G 早一项；
- `IU` 近似 `K 个 IAS root + K 个 GAS root`，台阶应接近 K=8→9；
- 若 top 与 bottom 分属两个独立 16-entry bank，`IU` 仍应接近 16→17，但溢出时可能每次多
  8 sectors，而不是 4；
- 若只缓存起始 traversable，G、IS、IU 都在 16→17，TS/TU 在 top handle 固定后不应复现
  同一个阈值。

真实 IAS 可能需要 root、instance leaf、transform 等多条 line，不能机械套用上述数字。
正确方法是先测每种场景的冷 `unique−same` sector 数，定义每次变化路径的 line demand `q`，
再检验统一容量模型：

```text
K * q_variable + q_shared > 16 lines
```

### 层级判读矩阵

| G | IS | IU | TS | TU | 倾向解释 |
|---|---|---|---|---|---|
| 16 | 16 | 16 | flat | flat | 起始 handle/root 专用 16-entry 结构 |
| 16 | 15 附近 | 8 附近 | 有较早台阶 | 有更早台阶 | IAS/GAS complet line 共用统一约 16-line bank |
| 16 | 16 | 16，溢出 sector≈8 | IAS 与 GAS 各自可见台阶 | 两套独立或按类型分 bank |
| 16 | 16 | 更早 | flat | 有台阶 | bottom GAS root 是主要内容；top 另有 start structure |
| 16 | 有台阶 | 有台阶 | 有台阶且 shared child 也复现 | 有台阶 | instance/transform record 进入候选 cache |

表中的数值只是模式，不是预注册的唯一答案。正式归因必须同时满足 timing 台阶、probe 驱逐点和
每溢出 traversal 的 sector 整数关系。

### 可选的 transform 对照

K 个 `OptixStaticTransform` traversable 全部指向同一 GAS，可以在不构建 IAS BVH 的情况下，
只改变 starting transform record。若它也在 16→17 溢出而 direct pointer-decode 控制平坦，
候选更像 traversal front-end/root record，而非 GAS primitive data。

## 五、P1：同一固定 GAS 内多 node/path，不再让 handle 当替身变量

### 固定 GAS，K 只改变 target subset

一次构建 64 个空间分离的 geometry islands；后续 K=1..64 只选择其中 K 条 target rays，
**不能为每个 K 重建 GAS**。否则 BVH topology、output size 和地址会与 K 一起变化。

每个 K 从 64 个 target pool 中用独立 seed 抽成员，访问顺序再用另一个 seed 生成 Sattolo 环。
这修正当前 `handles[0..K-1]` 的 nested-set 设计。

### 两种 build-input 组织必须成对

保持顶点坐标和 target rays 一样，分别构建：

1. 一个 `OptixBuildInputTriangleArray` 含 64 primitives；
2. 64 个 build inputs，每个含一个 primitive。

二者都只有一个 GAS handle。若仅第二种出现 16-entry 特征，候选可能是 geometry/build-input/SBT
descriptor，而不是普通 BVH complet；若两者随访问 path 同样变化，node/primitive 解释更强。
两种 build 都令每个 input 的 `numSbtRecords=1`、geometry flags相同，并使所有命中最终映射到
同一份最小 hitgroup record；同时输出 hit-object 的 SBT GAS index，防止隐藏的 SBT-index变化漏检。

### 三种 path

- `root-gap`：只穿过总体 root 的空区域；
- `parent-gap(target)`：进入 target island 的父级空间，但避开 leaf AABB；
- `primitive(target)`：命中 target triangle，使用 `TERMINATE_ON_FIRST_HIT | DISABLE_ANYHIT`。

OptiX builder 不公开实际 BVH，因此“parent-gap”只是输入设计目标。必须用 cold sectors / cycles
确认它比 root-gap 多做稳定工作，又比 primitive path 少；否则不能把差分命名成某一级 node。

### 判读

| 结果 | 可支持的结论 |
|---|---|
| 同一 handle 的 parent-gap target 在 E 个 path 后淘汰 A | cache 内容包含 GAS 内部 complet/path，不只是 start record |
| root-gap 平坦，parent-gap 与 primitive 同阈值 | deeper complet 为主，primitive 尚无独立容量信号 |
| parent-gap 平坦，primitive 唯独出现阈值/额外 sectors | primitive-path cache 候选 |
| 两者都有阈值，但 primitive 每次溢出多另一组 sectors | complet 与 primitive 可能分 bank，或 primitive path多一条 line |
| 64 build inputs 才出现阈值 | geometry descriptor / SBT-GAS-index record 候选 |
| target subset 不同会在 E<16 时选择性淘汰 | set-associativity/address mapping，而非总容量 16 |

## 六、P1/P2：primitive cache 的专门实验

NVIDIA 旧 TTU 专利把 complet cache 与 primitive cache 画成两个结构；多GAS
hit−miss后来在31/32出现独立阈值，但同一GAS的1/64-build-input paired复测均为null。
因此这个31-record信号现在应称traversable/GAS-scoped hit/deeper record，不能命名为
per-primitive cache。

### 主实验：固定 GAS 的 target-triangle working set

- 建一个固定 64/128 triangle GAS，三角形位于分离的小 tile；
- 每个 tile 准备 paired `parent-gap` 与 `hit` ray；
- same-target 控制重复一个 tile，unique-target 才改变 primitive/path；
- K 只改变 target subset，不改变 GAS；
- `optixTraverse()` + hit-object query，不执行 shader；
- 收集 `hit−parent-gap` timing 与 `unique−same` L1TEX sectors。

要宣称 primitive cache candidate，至少同时满足：

1. unique hit 有稳定阈值，same-target 无；
2. paired parent-gap 在相同 K 不出现该额外台阶，或能用独立 complet traffic 扣除；
3. 阈值对 build seed、target subset、triangle 坐标微扰和 compaction 保持；
4. 溢出后的额外 sector 数与每次 primitive fetch 形成精确整数关系；
5. triangle 数变化而 root/start handle 固定。

### 辅助实验：random vertex access

用 `OPTIX_BUILD_FLAG_ALLOW_RANDOM_VERTEX_ACCESS` 构建固定 GAS，循环调用
`optixGetTriangleVertexDataFromHandle(gas, primIdx, ...)`，并与普通 vertex-buffer global load 对照。
这个 intrinsic 能按 primitive index 读取 GAS 内的 vertex data，适合作为“primitive 数据布局/line
granularity”辅助探针；但官方没有保证它走 ray-triangle intersection 的 L0 primitive cache。
所以即使看到阈值，也只能叫 random-access geometry-data cache，不能单独当成 TTU primitive L0。

### primitive 数与 BVH 深度矩阵

固定几何分布族，构建 `1,2,4,8,16,64,256,1024,4096` primitives；每个 GAS 测：

- outside-root；
- root-gap；
- 选定 leaf 的 parent-gap；
- leaf hit。

再交叉：

- `PREFER_FAST_TRACE` / `PREFER_FAST_BUILD`；
- compacted / non-compacted；
- balanced spatial grid / 高重叠或强偏斜分布。

“深 BVH”在 OptiX 下不能由输入顺序保证，builder 可能重排、压缩或变宽。只应写成
`deep-path candidate`，并用 cold sector count 和 traversal cycles 证明某组 rays 的实际访问成本更高。
不要把 `log2(primitive_count)` 当作真实 node depth。

## 七、P2：16 是总容量、相联度，还是偶然 set conflict

### 受控地址池

优先使用一次 source build + K 个 relocation clones，减少 topology 差异。将 outputs 放在一个大 allocation
的非重叠、128B-aligned subranges，测试：

```text
stride = aligned_output_size
stride = 4 KiB
stride = 64 KiB
stride = 2 MiB
random live gaps / random base offset
```

2MiB stride 时只需 24 个 clone 就能跨过16-entry边界并保持约48MiB跨度；不要同时申请128个
2MiB-spaced outputs。64/128 candidate pool只用于紧凑/4KiB等仍满足显存预算的布局。

同时记录 output VA 和 `optixGetGASPointerFromHandle()`，不能只看 handle 的 `+0xC` 外观。

### eviction-set 搜索

对每个 victim A：

```text
SCRUB 32 个 disjoint handles
TRACE A
TRACE S[0..E-1]
PROBE A
```

先从 64/128 个 candidate pool 中找能淘汰 A 的集合，再做 greedy reduction：逐个移除 member，若仍淘汰
则永久删除。对不同 A、base、stride、seed 重复。

### 判读

- 任意地址集合都在 15 个 evictors 后保留、16 个后淘汰：支持 fully-associative 或等效 16-entry 总容量；
- 某些小于 16 的集合可淘汰，而另一些 16+ 集合不能：明确是 set mapping/associativity；
- 最小 eviction set 大小固定为 W，且 conflict 随地址位变化：W 是 associativity 候选，总 line 数可能大于16；
- breakpoint 随 stride/base 变化：当前 16 很可能只是地址冲突，不是总容量。

### replacement policy 序列

每次先用 disjoint scrub 冷却候选层，并单独运行一个 victim probe，避免 probe 本身改变后续结果：

```text
LRU/FIFO 区分： A, B1..B15, A(refresh), X, probe A
无 refresh 对照：A, B1..B15,             X, probe A
recency 曲线：   A, B1..Br, A, B(r+1)..B15, X, probe A
victim 扫描：    单独重复上述序列，分别 probe A/Bi
```

- refresh 能稳定保护 A：LRU/PLRU 倾向；
- refresh 不保护 A、最早插入者被淘汰：FIFO/round-robin 倾向；
- 淘汰概率平滑且跨重复随机：random 倾向；
- 对特定二进制 recency pattern 敏感：tree-PLRU 候选。

专利描述的 allocate-on-return、pending request grouping 会让并发结果偏离传统 cache。replacement 主测试必须先用
单线程串行 traversal；并发 rays 另列，不要混进容量结论。

### 2026-07-12 实测更新

上述串行 replacement 主测试及其任意顺序扩展已完成。prefix的26个点虽逐项等于
LRU预测，但单独refresh Ai时，16/16项都淘汰 `A(i+1 mod16)`；六种多次、重复、
逆序refresh跨4种layout/rotation的24/24 insert/no-insert控制也由最后命中的环后继
决定，局部惩罚恒为27.0 cycles。故prefix只是偶然模拟LRU；真LRU已被否定，当前
串行可观测语义为hit-updated circular successor。

任意地址池扫描也已完成：192/192个仿射序列只在E=16淘汰，四个16项集合逐成员
删除得到64个15项子集，全部不淘汰且平台spread为0。当前允许称“所测64-GAS池中
16-entry effective fully-associative”，但不升级成所有地址的物理版图保证。完整结果见
[`RT_ROOT_REPLACEMENT_FINDINGS.md`](RT_ROOT_REPLACEMENT_FINDINGS.md)。

## 八、P2：L1 trash 夹心实验，确认层级

当前 exact sector relation 已很强地暗示候选层在普通 L1TEX 前面。再做一次同线程夹心实验，可把“驻留数据是否
独立于 L1 tag/data”直接测出来。

使用 256–512KiB 的随机 pointer-chase 表，单线程在同一 raygen 中访问，目标是替换该 SM 的普通 L1，数据仍留在 L2。
先用独立 CUDA pointer-chase 基线与 L1TEX counters确认它确实产生 L1 replacement。

| 序列 | 预期用途 |
|---|---|
| `A -> probe A` | RT warm-hit baseline |
| `A -> L1-trash -> probe A` | L1 churn 是否破坏 RT resident A |
| `A -> 16 RT evictors -> probe A` | RT miss、L1 backing hit baseline |
| `A -> 16 RT evictors -> L1-trash -> probe A` | RT miss 后 backing 是否掉到 L2 |

判读：

- 第二行仍 warm、且 probe 不产生4-sector lookup：候选 data 真正在普通 L1 之上独立驻留；
- 第三行约 +27 cycles、4 sectors L1 hit：复现当前 RT-L0→L1 refill；
- 第四行再增加 L2 latency、4 sectors 变为 L1 miss/L2 read：建立完整 `RT resident -> L1 -> L2` 层级；
- L1 trash 单独就使 A 冷：可能共享 tag/data RAM、统一失效域或 trash workload 也间接冲刷 RT；不能立刻说候选就是 L1。

不要使用 profiler cache flush。NCU 保持 `--clock-control none --cache-control none`，只收同一 pass 可共存的 metrics。

## 九、P3：SM / TPC ownership

### 先回答“是否跨 ray/warp 共享”

若 OptiX IR 能可靠编译 warp intrinsic，可用一个 warp：lane 0 prime A，`__syncwarp()`，lane 1 probe A；记录
`%smid/%laneid`。这能排除 per-ray 私有状态，但只能证明同 warp/同 SM 可共享，不能证明整 SM ownership。
由于 OptiX 不公开 CUDA block 组织，不能未经验证使用 `__syncthreads()` 做跨-warp barrier。

### 最安全的跨 SM 主实验：相邻 launch 配对并按 smid 后分层

每个 trial 使用同一 context：

```text
launch P: 1 raygen thread，prime A，记录 smid_P
launch Q: 1 raygen thread，立即 probe A，记录 smid_Q 和 cycles
```

重复足够多次，只按实际 `(smid_P, smid_Q)` 分类，不假设调度位置。再加入：

- Q 先用16个 disjoint handles scrub 的 cold control；
- P/Q same-handle 与 different-handle control；
- 地址 seed、launch 顺序、空 host delay 交叉；
- probe 的 L1 sector / L2 read 计数小批量复核。

### 判读

| 结果 | 可支持的 ownership |
|---|---|
| `P==Q` warm，`P!=Q` cold | per-SM / per-RT-unit 候选 |
| 某些不同 SM 对稳定互相 warm，形成小型 cluster | TPC 或其他 SM group 共享候选；不能先假定 `smid/2` 就是 TPC |
| 所有 SM 对都 warm | device-wide/shared slice，或 launch 期间另一个共享层保留 |
| 即使 `P==Q` 也全 cold | launch boundary flush/context tagging；实验不具判别力，不是“非 per-SM”的证据 |
| 只出现一个 smid | scheduler locality 导致无跨 SM 样本；保持未决 |

若自然调度不给跨 SM pair，可选的第二阶段是两个 stream 各一个 width-1 OptiX launch，以有界 global-atomic handshake
做 prime/probe并记录 smid。每个 spin 必须有 `clock64()` deadline，超时写状态后退出；不能无限自旋、不能 GPU reset。
它只在主实验采不到样本时启用。

### TPC 结论的证据门槛

公开 `rtcore__*` metrics 是 device scope，没有 per-SM instance。TPC ownership 必须来自稳定的跨-SM warm adjacency：

1. 多个 address/run seed 重复同一 SM cluster；
2. cluster 内 warm、cluster 外 cold；
3. 与普通 per-SM L1 warm/cold行为区分；
4. 不用未公开的 `floor(smid/2)` 映射当作前提。

只有达到这四项，才可写“每 TPC 共享”；否则只报告“single-thread visible / SM-locality candidate”。

### 2026-07-12 执行结果

相邻 launch 会改变/隔离目标状态，两个 stream 在本机又被序列化；最终采用单个
width=8192 launch 内的 P/Q 有界握手。按实际 `%smid` 得到 `{0,1}`、`{2,3}`、
`{22,23}`、`{44,45}` 四个稳定双-SM warm cluster，正反方向约 `0.46--0.50k`
cycles，`0->22`、`23->44` 等跨 cluster 为零。

普通 GAS backing-load、forward/reverse control order、Q-only trash，以及 P/Q 各自
不重叠的 256 KiB `L1::evict_last` 双端 trash 都已加入。双端 trash 后普通-load
对照多数回到约零，而 RT trace prime 在多个 paired SM 中仍约 `0.42--0.47k`
cycles。后续联合容量实验进一步得到：伙伴P留下的A与Q本地15个unique roots仍共存，
第16个Q本地root使远端A的相对收益精确归零；三组paired SM、正反顺序均复现，跨域
对照始终为零。因此已证明“特定双-SM域所见的同一16项有效budget”，但仍不能仅凭
该现象宣布一份物理共享per-TPC SRAM；复制、迁移或转发仍可产生同样可见行为。完整数据见
[`RT_CACHE_OWNERSHIP_FINDINGS.md`](RT_CACHE_OWNERSHIP_FINDINGS.md)。

## 十、总判读矩阵

| 候选结构 | distinct start GAS | same GAS multi-path | K IAS→same GAS | one IAS K inst→same GAS | primitive-hit only | L1 trash后仍warm | 跨SM warm |
|---|---|---|---|---|---|---|---|
| handle/start descriptor | 16 | flat | 16 | flat | 无独立台阶 | 可能 | 看 ownership |
| GAS root-only cache | 16 | root固定时flat | child shared后主要看 IAS top | top/shared child时flat | 无独立台阶 | 是 | 看 ownership |
| unified complet L0 | 16 | target path可淘汰 | 按总 line 数提前 | IAS path可淘汰 | hit与node路径共模 | 是 | 看 ownership |
| IAS instance/transform cache | direct GAS无特征或仅基线 | flat | 有阈值 | 有阈值 | 无关 | 是 | 看 ownership |
| primitive L0 | hit路径才有额外信号 | unique primitive target淘汰 | child geometry固定时flat | child固定时flat | 明确阈值 | 是 | 看 ownership |
| 普通 L1/TLB | 可能 | 地址/page敏感 | 地址/page敏感 | 地址/page敏感 | 不按RT内容分离 | L1 trash会破坏 | 主要per-SM L1模式 |
| set conflict | 当前像16 | 仅特定成员淘汰 | breakpoint随VA变化 | 随path/address变化 | 不稳定 | 不定 | 不定 |

没有任何单个 timing jump 能唯一选中一行；至少需要一项 positive probe、一个 same-work negative control和 sector traffic 三者一致。

## 十一、统计与 NCU 采集规则

### timing

- probe 输出每次 raw cycles，不只输出样本平均；
- 先用 warm/cold calibration 得到两个离散 mode，再做 hit probability；不要只比较 noisy median；
- 独立统计单位是新 process/context/build/allocation seed；launch 内 21 samples 不是21次独立实验；
- K/member/order/address 使用独立 seed；K 顺序随机、反向或 Latin square；
- 每个 K 固定总 traversal 数与计时窗，避免 K 越大 launch 越长；
- `clock64()` 配 CUDA event wall time和 `%smid`，过滤规则在看结果前预注册。

### counters

核心 one-pass 组保持：

```text
l1tex__t_sectors_lookup_hit.sum
l1tex__t_sectors_lookup_miss.sum
```

L2 metrics 单独 one-pass（若 catalog 允许同 pass），不要把 cache-control none 的多 replay 小差异做 conservation。
RT metrics `rtcore__rays` / `rtcore__cycles_executed` 另开采集，用于确认 workload，不用于声称私有 cache hit。

每个 counter 必须按整个 launch 的真实 traversal 数归一化，包含 warmup、scrub、prime 和 probe；最好让 sequence generator直接输出
`total_trace_calls`、`unique_start_records`、`expected_cold_lines`，避免手工分母错误。

### validation

- smoke/correctness：`OPTIX_DEVICE_CONTEXT_VALIDATION_MODE_ALL`；
- 正式 timing/counter：validation OFF；
- 两者先做结果一致性检查；
- compilation disk cache仍关闭，但不要把编译时间计入 workload。

## 十二、安全边界

沿用并收紧现有边界：

- 不锁频，不改 power limit、ECC、persistence、fan、firmware、driver/module；
- 不访问未文档化 MMIO，不 GPU reset；
- documented CUDA/OptiX allocation/build/launch/read-only counters only；
- 单线程实验每 launch最多 2,000,000 traversals、10s watchdog；推荐正式 run控制在2s内；
- ownership 的并发版本最多两个 width-1 launch，每个 spin有硬 deadline；
- VRAM默认≤64MiB且≤空闲显存1%；large-BVH若需要放宽，单独审查并仍低于256MiB；
- NCU 使用 `--clock-control none --cache-control none`；
- 每批前后读取温度、功耗、GPU processes；温度异常或桌面负载活跃时停止；
- watchdog 只终止 probe process，不重置设备。

这些实验会写本进程拥有的 VRAM，因此不是字面意义的“只读显存”；但系统配置和持久设备状态保持只读、无修改。

## 十三、最小实施批次与停止条件

### Batch A：1个新 target，预计最少代码

1. 加 `optixTraverse()`、`RaySpec`、per-probe timing、smid；
2. 双岛 GAS：outside-root / root-gap / leaf-hit；
3. same handle 与 K relocated clones；
4. K=15/16/17/18 timing + L1 one-pass counters。

**成功门槛**：确认16项是否只属于 start record；若 same-handle root/leaf path已有独立阈值，进入 Batch C；否则先做 Batch B。

### Batch B：层级定位，信息增益最高

实现 G / IS / IU / TS / TU 五个场景，只先跑 K=7/8/9/14/15/16/17/18，再根据台阶细扫。

**成功门槛**：sector 整数关系能由“只缓存起始 record”“统一16-line complet bank”或“分层 bank”之一解释，且至少两个地址 seed复现；
不能解释时不继续乘 bytes，先检查每路径 cold line demand。

### Batch C：固定 GAS multi-path / primitive

1个固定64-target GAS、one-input vs 64-input、parent-gap vs hit；先 K≤32。

**成功门槛**：同一 handle 内出现可重复 eviction，才把内容名称从 root/start 扩展到 internal complet或primitive。

**当前状态**：1-input与64-input/SBT-index版本均已完成。单callsite AB/BA的
32-victim×3-path plain median全部为0；L1-trash完整victim map和独立repeat不随
最后fill移动。成功门槛未满足，反而排除了31-record层的per-primitive/path/geometry
allocation；当前最强候选为traversable/GAS-scoped record。见
[`SAME_GAS_PATH_CONTENT_FINDINGS.md`](SAME_GAS_PATH_CONTENT_FINDINGS.md)。

### Batch D：replacement + L1 hierarchy

做 eviction-set reduction、refresh sequence和L1 trash夹心。

**当前状态**：任意refresh、insert/no-insert、192点eviction scan、64个15项
reduction和L1双端trash均已完成。root层为circular-successor而非LRU；所测池未见
`E<16`冲突，warm RT状态在普通L1 churn后仍可见。剩余问题是物理状态机实现、
并发语义，以及不同AS record类型能否复现同一规则。

### Batch E：ownership

已完成same-launch、`%smid`分层的P/Q实验：`{0,1}`、`{2,3}`、`{22,23}`、
`{44,45}`等相邻双SM域可见，跨已测域不可见；联合容量在伙伴第16个local evictor
处清除远端A。允许称“特定双-SM可见域/TPC candidate”，仍不允许把170 SM与170
RT Core的数量关系替代物理共享证明。

## 十四、完成各批次后允许使用的措辞

| 证据 | 允许措辞 |
|---|---|
| 只有当前数据 | “16-entry starting-GAS/root-record residency candidate，128B L1 backing/refill” |
| Batch A 证明 gap也同域 | “16-line root/complet-path L0 candidate” |
| Batch B 符合统一 line-demand 模型 | “IAS/GAS traversal complet 共享约16-line residency bank” |
| Batch C same-GAS multi-node 驱逐成立 | “缓存内部 BVH complet/path records，不只是起始handle” |
| primitive paired differential独立成立 | “triangle primitive-path L0 candidate，容量/line demand为……” |
| eviction-set显示所有地址均C=16 | “effective total capacity 16 entries”，而不只是 no-thrash threshold |
| L1 trash夹心成立 | “该resident层位于普通L1TEX之前，miss由L1/L2 backing补给” |
| smid共享域成立 | “per-SM”或“per-TPC shared”；此前不能加这个限定 |

即便全部完成，`16×128B=2KiB`首先仍是 backing working-set footprint。只有证明每个 resident entry 在内部 data RAM
以未压缩128B保存，才能写“物理 SRAM 正好2KiB”；公开 OptiX/NCU 很可能无法把最后这一点证明到版图级。

## 参考与实现依据

- 现有正式结果：[`FINDINGS_5090_RT_CACHE.md`](FINDINGS_5090_RT_CACHE.md)
- 现有计数器审查：[`counter_analysis.md`](counter_analysis.md)
- 第一轮基准审查：[`benchmark_review.md`](benchmark_review.md)
- 一手架构资料还原：[`rt_arch_sources.md`](rt_arch_sources.md)
- 当前 device 路径：[`agent_optix/minimal/sweep_device.cu`](agent_optix/minimal/sweep_device.cu)
- OptiX 9.1 本地官方头文件：
  `agent_optix/optix-dev/include/optix_device.h`（`optixTraverse`、hit-object query、random access）、
  `optix_types.h`（IAS、build flags、graph flags）、`optix_host.h`（accel relocation）
- NVIDIA TTU L0 专利结构先验：
  [US20200050550A1](https://patents.google.com/patent/US20200050550A1/en)
- Nsight Compute sector/line 定义：
  [Nsight Compute Profiling Guide](https://docs.nvidia.com/nsight-compute/ProfilingGuide/index.html#quantities)
