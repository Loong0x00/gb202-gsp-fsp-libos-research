# RTX 5090 / GB202 RT Core 硬件运行链与缓存：一手资料还原

日期：2026-07-11  
范围：GeForce RTX 5090（GB202，第四代 RT Core），重点是 SM 发射 ray 之后的 TTU/RT Core 数据通路、BVH/instance/primitive/stack，以及 RT 私有 L0 与 L1TEX/L2 的关系。

## 0. 先给结论

可以把现代 NVIDIA RT traversal 路径画成下面这样：

```text
SM shader / raygen
  | ray(origin, direction, tmin/tmax), AS root, flags, traversal state
  v
RT Core / TTU front end + ray slots + Stack Management
  |
  +--> root / interior complet request
  |      |
  |      v
  |    L0 complet cache ---- miss ----> SM-local L1TEX ----> shared L2 ----> VRAM
  |      |                                  ^
  |      v                                  |
  |    Box Intersection Engine              |
  |      | hit child refs                    |
  |      +--> internal complet: push/order, repeat
  |      +--> instance: fetch transform -----+
  |      |               world -> object; enter child BVH/BLAS
  |      +--> primitive/cluster range
  |                      |
  |                      v
  |              L0 primitive cache -- miss --> L1TEX --> L2 --> VRAM
  |                      |
  |                      +--> triangle / triangle-cluster intersection
  |                      +--> Linear Swept Sphere intersection (Blackwell)
  |                      +--> Opacity Micromap evaluation (Ada + Blackwell)
  |
  v
Intersection Management / result queue
  | update closest t, cull, return candidate/accepted hit or miss
  v
SM register file -> any-hit / closest-hit / miss shader, or resume traversal
```

其中最重要的缓存结论是：

1. NVIDIA 专利明确公开了 TTU 内部的只读 **L0 complet cache** 和 **L0 primitive cache**；它们位于普通 L1 之前。[S3]
2. complet cache 不只是“存几行数据”。专利把它设计成一个 **cache + request coalescer + ray scheduler**：相同 complet 地址的多个 ray 共用一次上级请求，并被成组送进 box-test datapath。[S3]
3. TTU 以 L1 的只读 client 身份访问内存；L1 miss 再到全 GPU 共享 L2，最后到显存。[S3][S7]
4. “root cache”不是 NVIDIA 公开资料中的另一种缓存：root 本身就是第一个 complet；专利明确说 complet 可以表示 root 或 interior node。[S3]
5. 专利中的“例如 8 cache lines”是 2018 年优先权的 **非限制性示例**，不是 GB202 参数；同一专利还明确说 data RAM 的行数 N、每行 M bytes 以及 request/tag/data 表规模可独立配置。[S3][S4]
6. Blackwell 白皮书证实每 SM 一个第四代 RT Core，但未给出 RT 内部 L0 的容量、line size、相联度、替换策略或 ownership。[S1]
7. 因此，本机实测的 `16 entries × 128 B backing = 2 KiB effective footprint` 与专利的 complet-path L0 高度吻合，但仍应叫 **GB202 root/complet residency layer 的实测结果**，不能写成 NVIDIA 官方公布的“每 SM 2 KiB RT SRAM”。
8. 后续 same-launch 实验已找到特定双-SM RT traversal 可见域；它与 TPC candidate
   相容，但仍不是 NVIDIA 对物理 cache wiring 的公开确认。见
   [`RT_CACHE_OWNERSHIP_FINDINGS.md`](RT_CACHE_OWNERSHIP_FINDINGS.md)。

## 1. 证据等级

为避免把跨代专利直接当成 Blackwell 规格，下文使用三个等级：

| 标记 | 含义 |
|---|---|
| **BW-confirmed** | RTX Blackwell 白皮书直接写出或画出，能归属于 GB20x/RTX 5090 |
| **NVIDIA-design** | NVIDIA 专利或 NVIDIA Research 原文公开的实现；说明 NVIDIA 的硬件设计范式，但不证明 GB202 原样采用 |
| **Inference / measured** | 把公开架构与本机计数器/延迟实验对接后的推断；不是官方规格 |

任何没有 **BW-confirmed** 标签的容量、表项数、栈深度和调度细节，都不应冒充 GB202 已公开参数。

## 2. GB202 已被官方证实的物理框架

### 2.1 SM、RT Core、L1 与 L2

**BW-confirmed：**

- 完整 GB202 有 192 SM；RTX 5090 启用 170 个 RT Core。白皮书规格表列出 RTX 5090 的 170 个第四代 RT Core。[S1，pp. 46-47]
- 每个 SM 包含一个第四代 RT Core、128 个 CUDA Core、4 个 Tensor Core、4 个 Texture Unit、256 KiB register file 和 128 KiB unified L1/shared memory。[S1，pp. 9-10]
- 完整 GB202 为 128 MB L2；RTX 5090 特定配置为 98,304 KiB，即 96 MiB。[S1，p. 8、pp. 46-47]

这能证明“一 SM 对应一个 RT Core”的 **功能块数量关系**，但白皮书没有画出 RT Core 私有缓存与 SM/TPC 的物理 wiring，也没有说 L0 tag/data RAM 是否严格一份/SM。因此“一对一计数”不应单独升级成“L0 ownership 已经版图级证实”。

### 2.2 第四代 RT Core 公开模块

白皮书 Figure 9 的第四代 RT Core 框图列出五个模块：[S1，p. 16 / 文档印刷页 17]

| 模块 | 代际状态 | 官方公开功能 | 官方未公开内容 |
|---|---|---|---|
| Box Intersection Engine | 延续基础 RT 功能 | ray-AABB / BVH bounding-box test | 宽度、lane 数、延迟、吞吐细节 |
| Triangle Cluster Intersection Engine | **Blackwell 新增/强化** | Mega Geometry 的 triangle-cluster traversal/intersection；仍支持标准 ray-triangle | cluster 内部流水线、缓存接口、每周期实际发射规则 |
| Triangle Cluster Compression Engine | **Blackwell 新增** | 对 geometry/BVH 使用新的 cluster compression schemes，降低 footprint | 是 build、fetch、decode 还是融合流水的具体边界 |
| Linear Swept Spheres | **Blackwell 新增** | 硬件 ray-LSS intersection；sphere 是零长度 segment 的特例 | 数据布局、cache line packing、测试单元宽度 |
| Opacity Micromap Engine | Ada 已有，Blackwell 延续 | 在 RT Core 内评估 OMM，直接处理可判定 alpha 状态，减少 shader alpha work | OMM 私有缓存、查找结构和容量 |

白皮书还明确给出：[S1，pp. 16-22]

- Blackwell ray-triangle intersection throughput 相对 Ada 为 2 倍。
- CLAS 可由最多 256 个空间紧凑的 triangles 生成；多个 CLAS 再用于构建最终 BVH。
- `PTLAS` 是面向高 object count 的 persistent/partitioned top-level AS 管理方式。
- Blackwell 的 special cluster engines 对 geometry 和 BVH 实施新压缩方案。
- LSS 在典型 hair 场景相对 DOTS 约 2 倍快，并约省 5 倍 geometry VRAM。

这里有两个常见误读：

1. **CLAS/PTLAS 是 acceleration-structure/API/driver 能力，不等于每一个名字都是 RT Core 内部独立硬件盒子。** 白皮书只把 Triangle Cluster Intersection/Compression Engines 画进 RT Core。
2. **SER 2.0 不在 Figure 9 的 RT Core 内。** 它是 SM/软件控制的 thread reordering 能力，可以改善 shader 与 memory coherence，但不等于 TTU L0 cache 的 request grouping。[S1，pp. 23-24]

## 3. 从 SM 发出一条 ray 后，硬件逐步做什么

本节的通路细节来自 NVIDIA 的 TTU 专利族，属于 **NVIDIA-design**，不是 GB202 netlist。Blackwell 白皮书只确认基础 traversal、box/triangle tests 以及新增模块仍存在。[S1][S3]

### 3.1 发射与接口：SM 把 query 交给 TTU

NVIDIA 对 Turing 的官方说明已经把最外层契约说清：SM 发起 ray probe，RT Core 自主做 BVH traversal 与 ray-triangle tests，再把 hit/no-hit 返回 SM；BVH build/refit 由 driver 处理，ray generation 和 shading 由 shader/application 管理。[S2，`TURING RT CORES`]

更细的 TTU 专利接口是：[S3，¶[0125]、¶[0331]-[0338]]

- TTU 类似 texture processor，是 SM 的 coprocessor。
- 它由一组 SM instructions 暴露；某些实现用多条指令组成一个概念上的 macro-instruction。
- 输入可包括 ray origin、direction、`tmin/tmax`、BVH/root reference、ray flags、mode/RayOp flags 和 traversal state。
- 输出回到 SM register file。
- TTU 作为 L1 的 **read-only client**；专利还画出 TTU 到 L1 的 dedicated read interface。
- 活跃 query 在 TTU 内可占用 ray slot；但某些实现对 query 之间不保留 architectural state，continuation state 由寄存器中的 traversal stack 在 SM 与 TTU 间往返。

这里“TTU 对 query 之间 stateless”与“活跃 ray 有内部状态”并不矛盾：前者说 query 边界外不必保留架构状态，后者是当前正在跑的 traversal 的 transient ray/stack/result 状态。

### 3.2 Root / complet 入口

专利把 **complet** 定义为 compressed treelet，可表示 BVH 的 root 或 interior node；complet 的 children 可以是另一个 complet 或某一种 leaf。[S3，¶[0124]；S4，描述 lines 1407-1422]

一轮 complet traversal 是：

1. Stack Management Unit 检查该 ray 的 traversal state / 栈顶。
2. 发出下一 complet 地址。
3. 先查 TTU 内 L0 complet cache。
4. L0 miss 时，经 L1 read interface 请求；再 miss 才向 L2/显存走。
5. complet 到达 ray-complet test block / Box Intersection Engine。
6. 测试的是该 complet 内 **children 的 bounding boxes**，通常不会重测 complet 自己的 parent-facing box。
7. 对 hit children 形成 references，按 traversal policy 排序并压入/更新栈。
8. child 是 interior complet 就递归；是 instance 或 primitive leaf 就切换数据路径。

专利解释了为何 child box 可以压缩：complet 自己的 bounding box 还定义一个局部坐标系，children boxes 在其中以压缩形式表达。[S3，¶[0127]-[0128]]

### 3.3 TLAS -> instance -> BLAS

两级 traversal 在专利中的数据流是：[S4，lines 1527-1550；同族 Figure 11A]

```text
top-level BVH traversal
  -> hit instance node
  -> fetch instance record / world-to-object matrix
  -> transform ray, not all geometry
  -> enter child BVH / bottom-level traversal
  -> leaf primitive range
```

instance record 可含 child BVH pointer、culling flags 和 world-to-object 3x4 matrix（齐次矩阵末行可隐含）。在专利示例里，transform matrix 从 L1 获取，TTU 硬件完成 ray transform。[S3，¶[0336]；S4，lines 1541-1550]

这解释了 instance 的核心省法：多个 world-space instances 可以共享同一 object-space BLAS，无需为每个 instance 复制/变换全部 geometry。

需要保持代际边界：专利允许硬件原生处理一层、两层或更多层 instance，也允许多余层返回软件处理；它没有公开 GB202 的最大 native nesting depth。[S3，¶[0354]-[0356]]

### 3.4 Primitive / triangle 数据路径

到 leaf 后，Stack Management 把工作切换到 primitive path：[S3，¶[0123]-[0131]、Figure 9]

1. primitive/triangle range 的 geometry 按需从 memory hierarchy 取回。
2. TTU 内的 L0 primitive cache 754 缓存 primitive data。
3. ray-primitive test/transform block 做交点计算。
4. Intersection Management Unit 维护 hit/result 状态，可能缩短当前 ray 的 `tmax`，从而剔除更远的 boxes/primitives。
5. opaque hit 可由硬件保持最近者；alpha/unsupported item 可以 mid-traversal 返回 SM，再带 continuation stack 恢复。

在 Blackwell 上，这个抽象的 primitive path 对应的 fixed-function 后端不再只有传统 triangle test：

- 普通 triangle 与 triangle cluster 进入 Triangle Cluster Intersection Engine；
- cluster geometry/BVH 还涉及 Triangle Cluster Compression Engine；
- LSS/sphere 进入 LSS hardware path；
- 有 OMM 的 alpha geometry 可先由 Opacity Micromap Engine 解析已知 opacity state；只有 unknown/需要 shader 的情况才返回可编程处理。[S1]

**不能从公开资料推出：** primitive cache 是否被这些后端共享、是否分 bank、是否另有 OMM/cluster/LSS 专用小 cache。白皮书没有画缓存，专利也没有 Blackwell 新模块。

### 3.5 Hit、any-hit、closest-hit、miss 与恢复

专利中的 control flow 是：[S4，lines 1513-1530]

- Intersection Management 可在硬件中保留最近 opaque hit，并用新的更短 `tmax` 继续/裁剪 traversal。
- 需要 shader 决策的 alpha candidate 可连同 traversal state 返回 SM。
- SM 执行 any-hit/texture/material 逻辑后，可接受、忽略或修改 query，再恢复 TTU traversal。
- 栈清空且无结果时返回 miss；遍历完成且有 accepted closest hit 时返回 closest hit 数据。

Blackwell/Ada 的 OMM 改变的是其中 alpha candidate 的一部分：预编码为 opaque/transparent 的 micro-triangle 可以在 RT Core 内完成判定，避免 any-hit shader；unknown states 仍需 shader 侧处理。[S1；S8]

## 4. Stack：存什么、在哪里、如何溢出

### 4.1 栈里存的不是 geometry

traversal stack 主要保存“已经 hit、但尚未访问”的 child references / primitive ranges，以及在 TLAS/BLAS/instance 之间恢复所需的 state。它让硬件进行 depth-first traversal：向下时 push 尚未走的分支，完成当前分支后 pop 下一个。[S3，¶[0121]-[0128]]

NVIDIA Research 的 2017 CWBVH 论文展示了同一类压缩思路：8-wide BVH 的当前 node group/triangle group 可压成 64-bit base index + active mask；先处理一个 child，其余 group 压栈。[S6，§3、§4.1]

这篇论文是在 Pascal/Maxwell 上的软件 traversal，不是 RTX hardware format；它只能解释 wide/quantized BVH 和 compressed stack 为什么合理，不能当作 GB202 complet bit layout。

### 4.2 栈的物理位置没有 GB202 官方答案

公开 NVIDIA 资料给出过多种 **可选实现**：

- 短栈专利允许 stack 放 TTU 内 dedicated SRAM 或 low-level cache；短栈不够时用 backtracking 补足。[S5，Abstract/Description lines 179-243]
- 2017 软件 CWBVH 论文把每线程前若干项放 SM shared memory，超过后 spill 到 local memory。[S6，§4.1]
- TTU 专利的一个实现让 traversal state 以 SM registers 中的 stack 在 query/continuation 间往返，并说明 TTU 可在 query 之间 stateless。[S3，¶[0338]-[0345]]

所以以下数值均 **未知**：GB202 每 ray 短栈项数、每项位宽、ray slots 数、overflow 去 shared/L1/local/VRAM 的具体路线、instance nesting 占多少项。

## 5. RT 私有 L0：真正值得关注的运行逻辑

### 5.1 两条 L0 路径

NVIDIA TTU Figure 9 明确画出：[S3，Figure 9、¶[0123]-[0126]]

```text
L0 cache 750
  +-- complet cache 752  -> ray-complet test -> traversal logic -> stack manager
  +-- primitive cache 754 -> ray-primitive test/transform -> intersection manager
```

因此“RT cache”不是一个足够精确的词。至少在公开 TTU 设计中，应分为：

- **complet/root/interior-node locality**；
- **primitive/triangle data locality**；
- 另外还有 per-ray transient state（ray slots、stack、result queue），它们不一定是 cache。

本机当前 16-entry 实验只稳定击中了不同 GAS/root 的公共 traversal path，所以最稳的命名是 `root/complet residency layer`，不是 primitive cache。

### 5.2 complet cache 是 cache，也是调度器

专利 Figure 12 将详细 L0 组织拆成四部分：[S3，¶[0215]-[0237]、Figure 12]

| 结构 | 作用 |
|---|---|
| PRT, Pending Request Table | 每个 ray/request 一项，保存 request metadata |
| PAT, Pending Address Table | 每个 unique address 一组；多个 PRT 可指向同一 PAT |
| TAG | 地址/context -> PAT 或 resident data 的匹配 |
| DAT, Data RAM | 实际返回的 complet/cache-line data |

运行过程：

1. 第一个请求地址 A 的 ray 创建 PRT + PAT；若 DAT 无 A，向 L1 发一次请求。
2. 后续也请求 A 的 rays 各建 PRT，但挂到同一个 PAT，不重复向 L1 请求。
3. 数据返回后才在 DAT 中分配 line（allocate on return）。
4. PAT 激活，仲裁后把同一地址对应的数据和所有 PRT metadata 成组送入 datapath。
5. 这一组 rays 因同时完成同一 complet test，下一层仍较可能在相近时间请求相同 child complet，形成持续的 time coherence。

这与普通 demand cache 的差别是：它主动把 **memory-address coherence 转成 execution scheduling**。专利明确说 complet cache 位于 `execute -> request -> execute -> request` 循环内，并希望每周期持续给 ray-complet block 供数。[S3，¶[0175]-[0208]]

### 5.3 为什么很小的 L0 仍然有用

ray coherence 在 BVH 顶层最强：一批 primary rays 往往都访问同一 root 和若干 top-level complets。越向树底层，boxes 越小，rays 分歧越大，PAT groups 越容易退化成 singleton。[S3，¶[0180]-[0208]]

因此 complet cache 的目标不是容纳整个 BVH，而是：

- root/top-level hot records 常驻；
- 合并正在 flight 的相同 line 请求；
- 用很小 data RAM 放大 L1 bandwidth；
- 把一批 ray 的后续 traversal 自然保持在相近 phase。

这也解释了为什么 root-working-set 微基准会出现非常干净的 entry threshold：它刻意反复触发最适合 complet cache 的路径，同时去除了深层 BVH divergence。

### 5.4 miss、L1 backing 与 L2

专利给出的层次是：[S3，¶[0176]-[0189]、¶[0238]-[0247]、¶[0331]-[0335]]

```text
TTU L0 complet/primitive data
  -> L1 (shared by TTU, SM load/store, texture clients in that implementation)
  -> L2
  -> device memory
```

- TTU 为 read-only client，不需要 dirty/writeback path。
- L0 DAT 满且返回数据暂时无处放时，专利示例甚至允许 drop response 后重发 L1 request，并通过 critical mode 保证 forward progress。
- L0 命中降低 latency，也避免同一 line 对 L1 的重复请求；L0 grouping 还提高 L1 与下游 cache locality。
- Nsight Compute 官方定义：L1/L2 cache line 为 128 B，由 4 个 32 B sectors 组成；L1 miss sectors 形成对 L2 的请求，所有 GPU memory clients 最终通过 L2 到 framebuffer/device memory。[S7，`Quantities`、`Caches`]

最后一句只能给“现代 L1/L2 的计数单位”。把它与 TTU 专利的“一个 complet 通常由一条 cache line 取回”拼接，得到 `complet backing record = 128 B` 是合理而且被本机 counter 支持的 **cross-source inference**，但仍不是 NVIDIA 直接公布的 GB202 AS binary format。[S3，¶[0198]-[0201]、¶[0335]；S7]

### 5.5 专利的 8 lines 为什么不能拿来否定实测 16

专利同时写了三件事：[S3，¶[0238]-[0247]]

1. 某个 non-limiting mode 可以有 100+ tags，只用 8 条 DAT lines。
2. streaming cache “例如 8 cache lines”可以处理数百 rays。
3. DAT 为 `N lines × M bytes`；PRT/TAG/PAT/DAT 的规模可以独立配置。

而 2025 continuation 仍具有 2018-08-10 prior-art date。[S4，Info lines 15-39]

所以 8 是 Turing 时代专利族的设计示例，不是跨代不变量。GB202 实测 16-entry 不与专利矛盾，反而符合专利明确保留 N/M 可配置的表述。

### 5.6 primitive cache 知道得明显更少

公开专利只明确说：primitive data 在 ray-primitive test 前按需经 L0 primitive cache 754 取得。[S3，¶[0123]、¶[0126]、¶[0130]]

公开资料没有给：

- primitive cache 的 entries/bytes；
- line 与 triangle/cluster packing；
- 是否使用和 complet cache 相同的 PRT/PAT/DAT grouping；
- replacement/associativity；
- Blackwell cluster、LSS、OMM 是否共享该 cache。

因此 current hit/miss benchmark 在 16->17 共同出现相同台阶，并不能证明 primitive cache 容量；它更支持 triangle test 前的共同 root/complet path。

## 6. 把本机实测放回公开架构

当前本机结果（详见 `FINDINGS_5090_RT_CACHE.md`）是：

```text
不同 GAS/root working set: C = 16 entries
K=17 后每次额外 L1TEX lookup: 4 sectors = 128 B
L1 miss 不随每次 trace 增加: backing data 仍在普通 L1
稳定 miss penalty: 约 26.5-27 cycles
串行root替换: hit-updated circular successor（真LRU已否定）
root地址映射: 所测64-GAS池等效全相联16项，无E<16冲突集
跨SM可见域: 特定相邻双SM共享同一16项有效budget
```

与公开架构逐项对应：

| 实测现象 | 最吻合的公开机制 | 仍不能证明的部分 |
|---|---|---|
| 不同 GAS 才有 16-entry threshold | 每个 GAS 有独立 root/complet；同一 handle 反复命中 L0 | 被索引对象也可能是融合的 GAS header/root descriptor |
| K=17 后每 trace 多 4×32 B L1 sectors | L0 complet miss 后以一条 L1 line refill；现代 L1 line=128 B | 4 sectors 的具体地址未直接导出 |
| 额外 sectors 几乎都 L1 hit | L0 位于 L1 之前，L1 是 backing store | L0 SRAM 内部编码是否也原样占 128 B |
| hit 与 forced miss 共同台阶 | 在 primitive-specific work 之前的共同 root/complet path | primitive cache 容量仍未知 |
| same-handle / ring-only 无台阶 | 不是循环本身、handle table load 或简单地址步长造成 | 不能单凭此排除所有 TLB/descriptor fusion |
| 任意refresh后victim为最后命中项的环后继 | hit更新circular victim pointer；真LRU不符 | 物理pointer/clock/PLRU电路未区分 |
| 192个地址序列只在E16淘汰；64个15项子集均保留 | 所测root池等效全相联16项 | 有限地址/record类型不能代表全芯片版图 |
| paired SM在第16个Q-local evictor清除远端A | 两个SM观察到同一16项有效replacement budget | 物理共享、复制/迁移或转发未区分 |

建议最终措辞：

> RTX 5090 实测到一个位于普通 L1TEX 之前的 16-entry RT traversal root/complet residency layer。该层溢出后，每次不同 GAS traversal 额外请求 4 个 32 B L1 sectors，等价于 128 B backing record，形成约 2 KiB effective backing footprint；这与 NVIDIA TTU 专利的 L0 complet cache 数据流高度一致，但不是官方公布的每-SM 2 KiB SRAM 规格。

## 7. 哪些陈述现在可以说，哪些不能说

### 可以高置信度说

- RTX 5090 有 170 个第四代 RT Core；Blackwell SM 设计为每 SM 一个 RT Core。[S1]
- Blackwell RT Core 固定功能包含 box、triangle cluster、triangle cluster compression、LSS、OMM 五类公开模块。[S1]
- NVIDIA 的 TTU 架构公开设计把 box/complet 与 primitive intersection 分成两条 datapath，并有 stack/ray/intersection management。[S3]
- NVIDIA 公开过 TTU 内 L0 complet cache 和 L0 primitive cache；complet cache 由 L1 backing，并能把相同地址的 ray requests 合并和成组调度。[S3]
- root 是 complet 的一种位置/角色，不是公开证实的另一种 root-only cache。[S3]
- 本机 16-entry/128-B 结果与 complet-path L0 一致，且 refills 命中普通 L1TEX。
- 本机root层的任意refresh/victim扫描否定真LRU，并得到hit-updated circular
  successor语义；这是实测行为，不是公开资料披露的GB202 replacement电路。

### 只能作为跨代 NVIDIA 设计范式

- PRT/PAT/TAG/DAT 的具体组织。
- allocate-on-return、drop-and-retry、round-robin PAT service。
- TTU 在 query 之间 stateless、stack 经 SM registers 往返。
- short stack 用 dedicated SRAM / low-level cache。
- complet 正好匹配一条 L1 line。
- 8-line example。

这些来自专利，不是 GB202 implementation disclosure。

### 目前不能声称

- “GB202 的 RT Core 内部物理 SRAM 正好 2 KiB/SM”。
- “RT cache 官方容量就是 16×128 B”。
- “所有 RT L0 都是 fully associative / LRU”。
- “primitive cache 也是 16 entries”。
- “stack 在 GB202 上固定有 N 项，且一定放在某个指定 SRAM”。
- “OMM、LSS、cluster engines 各有某个容量的私有 cache”。
- “一个 RT Core 的 L0 一定无法被同 TPC/其他 SM 共享或干扰”。

## 8. 下一轮硬件问题应如何分解

若继续做微架构逆向，应该把“RT cache”拆成五个独立问题：

1. **Complet/root residency**：已得到 16-entry、128-B backing candidate、双-SM
   可见域与远端A参与同一16项有效budget；下一步测 associativity/indexing 和
   共享/迁移/复制的物理实现。
2. **Interior-complet locality**：一个 GAS 内制造深度/宽度可控的 BVH，区分 root-only descriptor 与通用 complet cache。
3. **Primitive cache**：固定单个 root/BVH，改变独立 triangle blocks/leaf ranges，避免 root working set 改变。
4. **Instance/transform locality**：固定 BLAS、扫独立 TLAS instance records 与 transform matrices，观察是否存在独立 transform/descriptor cache。
5. **Stack/ray slots**：扫 traversal depth、branch fanout、并发 rays；寻找 short-stack overflow 与 ray-slot saturation，而非缓存容量台阶。

Blackwell 新模块还可分别做：

- standard triangles vs CLAS：比较 root/interior/primitive sectors 与 throughput；
- triangle clusters 的 compressed/uncompressed-like layout：定位 compression engine 影响；
- LSS/sphere：固定 BVH 后扫 primitive records；
- OMM：扫 OMM descriptors/data 的 working set，区分 OMM engine lookup 与 any-hit fallback。

## 9. 一手资料与精确定位

### [S1] NVIDIA RTX Blackwell GPU Architecture Whitepaper

URL：<https://images.nvidia.com/aem-dam/Solutions/geforce/blackwell/nvidia-rtx-blackwell-gpu-architecture.pdf>

- pp. 8-10：GB202 GPC/TPC/SM、完整芯片 192 SM、RTX 5090 96 MB L2、每 SM 一个 RT Core 与 128 KB L1/shared。
- pp. 16-17（PDF 页码；印刷页 17-18）：`Blackwell 4th Generation RT Cores`、Figure 9、2× ray-triangle throughput、OMM、Triangle Cluster Intersection Engine、LSS。
- pp. 17-21：CLAS（最多 256 triangles）、PTLAS、Mega Geometry API/driver/architecture。
- p. 21：special cluster engines、geometry/BVH compression、2× third-generation intersection rate。
- pp. 21-22：LSS 与 sphere special case。
- pp. 46-47：RTX 5090 170 RT Cores、21,760 KB aggregate L1/shared、98,304 KB L2。

### [S2] NVIDIA Turing Architecture In-Depth

URL：<https://developer.nvidia.com/blog/nvidia-turing-architecture-in-depth/>

- Section `TURING RT CORES`：每 SM 一个 RT Core；RT Core 自主做 BVH traversal 与 ray-triangle testing；SM 发起 probe 并接收 hit/no-hit；BVH build/refit 与 shader 的职责边界。

这是 Turing 官方说明，只用于稳定的 SM/RT Core 合作契约，不用于推断 Blackwell 内部容量。

### [S3] US20200050550A1 — Method for efficient grouping of cache requests for datapath scheduling

URL：<https://patents.google.com/patent/US20200050550A1/en>

优先权：2018-08-10；NVIDIA Corporation。

- Figure 9；¶[0118]-[0131]：TTU block diagram，ray/complet/primitive/stack/intersection management，L0 complet + primitive caches。
- ¶[0175]-[0208]：L0 同时作为 streaming cache 与 scheduler；complet path 的 execute-request loop；按相同 complet 地址发现和维持 ray coherence。
- Figure 12；¶[0215]-[0237]：PRT、TAG、PAT、DAT；hit/miss grouping、allocate on return、成组下发 datapath。
- ¶[0238]-[0247]：drop/retry、N×M configurable data RAM、8-line non-limiting example。
- ¶[0331]-[0337]：TTU-L1 dedicated read interface、read-only L1 client、SM instruction/macro-instruction、BVH/complet/instance/triangle buffers。
- ¶[0338]-[0358]：query continuation、traversal stack、stack initializers、node/hit types。

### [S4] US20250004947A1 — 同一 cache-request 专利族的 2025 continuation

URL：<https://patents.google.com/patent/US20250004947A1/en>

- `Info`：虽然 publication date 为 2025-01-02，prior-art date 仍是 2018-08-10。
- Description lines 1407-1422：complet=compressed treelet、stack/top-child traversal、primitive/instance/item leaf handling。
- lines 1483-1501：两条 datapath 与 L0 caches。
- lines 1527-1550：SM/TTU/L1 pipeline、TLAS -> transform -> BLAS -> primitive。
- lines 1607-1732：L0 complet cache grouping、PRT/PAT/DAT、8-line example、N×M configurable。
- lines 1901-1904：dedicated L1 read interface、read-only L1 client、results to SM registers。

该 continuation 便于网页检索，但不能因为“2025 发布”就把其 8-line 示例标成 Blackwell disclosure。

### [S5] US20160070820A1 — Short stack traversal of tree data structures

URL：<https://patents.google.com/patent/US20160070820A1/en>

- Abstract / Description lines 179-243：有限 short stack、overflow 后 backtracking、stack 可位于 dedicated on-chip storage/low-level cache/SRAM。
- 这是 2014 priority 的通用 NVIDIA traversal 设计，不是 RTX 5090 stack 规格。

### [S6] Ylitie, Karras, Laine, “Efficient Incoherent Ray Traversal on GPUs Through Compressed Wide BVHs,” HPG 2017

NVIDIA Research 页面：<https://research.nvidia.com/publication/2017-07_efficient-incoherent-ray-traversal-gpus-through-compressed-wide-bvhs>  
论文 PDF：<https://research.nvidia.com/sites/default/files/publications/ylitie2017hpg-paper.pdf>

- §3：compressed 8-wide BVH、每 child 10 B、quantized boxes/child pointers。
- §4 / Algorithm 1：wide-node traversal 与 child/triangle group。
- §4.1：64-bit compressed node/triangle group stack entries。
- §4.2：node/triangle 通过普通 cache hierarchy 读取。

这是 NVIDIA Research 的 pre-RTX 软件 traversal 基线，只能作算法/数据布局 lineage。

### [S7] NVIDIA Nsight Compute Profiling Guide

URL：<https://docs.nvidia.com/nsight-compute/ProfilingGuide/index.html>

- `Quantities`：sector=32 B；L1/L2 line=4 sectors=128 B。
- `Caches` / L1TEX：L1 data/shared/texture cache 的关系，L1 miss 到 L2。
- `L2 Cache`：L2 位于 on-chip clients 与 framebuffer/device memory 之间。

它定义 counter/缓存层级；不描述 RT 私有 L0。

### [S8] NVIDIA Technical Blog — Opacity Micromaps production behavior

URL：<https://developer.nvidia.com/blog/path-tracing-optimizations-in-indiana-jones-opacity-micromaps-and-compaction-of-dynamic-blass/>

- `With Opacity MicroMaps`：四态 OMM 的 opaque/unknown/transparent 分类。
- `Verifying OMM presence`：能在 RT Core 内完成完整 traversal 的 rays 不需要 shader-side alpha evaluation；unknown 情况回到 shader/ray query。
- Conclusion：OMM 由 GeForce RTX 40/50 series 的 RT Core hardware 加速。

## 10. 最终硬件心智模型

最接近现有一手资料、且不过度宣称的模型是：

```text
每个 Blackwell SM
  SM schedulers / register file / shaders
       |
       | RT query (ray + AS + flags + stack state)
       v
  1 × Fourth-Generation RT Core
       - ray/stack/intersection control          [patent lineage]
       - L0 complet/root residency + grouping   [patent lineage; GB202 16-entry measured]
       - L0 primitive residency                  [patent lineage; capacity unknown]
       - Box Intersection Engine                 [Blackwell confirmed]
       - Triangle Cluster Intersection Engine    [Blackwell confirmed]
       - Triangle Cluster Compression Engine     [Blackwell confirmed]
       - Linear Swept Sphere path                [Blackwell confirmed]
       - Opacity Micromap Engine                 [Ada+Blackwell confirmed]
       |
       v
  128 KiB unified L1/shared (L1TEX) per SM       [Blackwell confirmed]
       |
       v
  96 MiB shared L2 on RTX 5090                   [Blackwell confirmed]
       |
       v
  GDDR7
```

这个模型把三件常被混为一谈的东西分开了：

1. **RT Core arithmetic/fixed-function engines**；
2. **TTU 内部 traversal residency/scheduling structures**；
3. **普通 SM L1TEX -> GPU L2 -> GDDR7 memory hierarchy**。

目前最清楚的未知数不是“有没有 RT cache”，而是：GB202 的 complet、primitive、
instance/transform、OMM/cluster data 各自如何分享或切分 L0；已测双-SM可见域究竟
对应共享、复制还是转发；以及 stack/ray-slot 的真实规模。
