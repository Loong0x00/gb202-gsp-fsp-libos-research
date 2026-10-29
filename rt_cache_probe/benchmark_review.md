# RTX 5090 / OptiX RT 私有缓存微基准：独立设计审查

日期：2026-07-11  
审查范围：`agent_optix/minimal/gas_sweep.cpp`、`sweep_device.cu`、`sweep_params.h` 及其 README；不修改实现。代码在审查期间仍在增加 `only-K`、same-handle、访问顺序和 launch 隔离控制，因此本文评估的是实验设计和证据门槛，不把某个瞬时源码版本当作最终版本。

> 2026-07-12 后续：本文关于“ownership 尚未实验”的陈述是审查当时状态。
> same-launch P/Q 已找到特定双-SM可见域，但仍未证明物理 per-TPC 2 KiB SRAM；见
> [`RT_CACHE_OWNERSHIP_FINDINGS.md`](RT_CACHE_OWNERSHIP_FINDINGS.md)。

## 一句话结论

现有程序是一个合格的 **RT 缓存候选筛查器**，但还不是一个能直接输出“Blackwell 每 SM RT cache = X bytes”的容量测量器。

当前探索性数据是：

- K=8 没有拐点；
- unique-GAS forced-miss 与 hit 都在 K=16→17 增加约 26.5 cycles/op；
- ring/empty 没有同位置拐点；
- `hit - miss` 在整个区间约为固定的 497 cycles/op。

这组结果已经足以说：

> 在当前分配、遍历和计时条件下，访问第 17 个不同 GAS 时，hit 与 miss 的共有路径出现了一个约 26.5-cycle 的有效工作集阈值；K=16 是一个值得继续验证的 RT-local / 地址相关结构候选。

它目前 **不足以** 说：

- “Blackwell 有 16-line complet L0”；
- “RT cache 是 16 × 128 B = 2 KiB”；
- “每个 SM 独占 2 KiB”；
- “primitive cache 是 16 lines”。

尤其是 `hit - miss` 不变，说明 16→17 的增量属于 hit 与 miss 共有的部分：handle/AS-root、complet、地址翻译、共享 L1 返回路径等。若是 primitive-only cache 溢出，正常预期是 hit 相对 miss 还会出现额外变化。因此当前数据对 **primitive cache 容量没有正证据**。

## 官方资料和专利究竟支持什么

### OptiX 的可依赖语义

OptiX 9.1 官方文档确认：`optixTrace()` 从给定 traversable 开始遍历；遍历结束后还会执行 closest-hit 或 miss 程序。当前 probe 因此同时计入了遍历、SBT/continuation 和用户程序返回成本。OptiX 还提供 `optixTraverse()`，其官方语义是只遍历并生成 hit object，**不调用 closest-hit 或 miss**。它应成为主要的遍历隔离版本；`optixTrace()` 版本保留为交叉验证。[OptiX 9.1 Programming Guide](https://raytracing-docs.nvidia.com/optix9/guide/optix_guide.251118.LTR.pdf)，[OptiX Device API](https://raytracing-docs.nvidia.com/optix9/api/group__optix__device__api.html)

OptiX 公开的 `OPTIX_ACCEL_BUFFER_BYTE_ALIGNMENT` 是 128 bytes，但这是 **AS 输出缓冲区的对齐要求**，不是 RT L0 cache-line 大小声明。[OptiX Types](https://raytracing-docs.nvidia.com/optix9/api/group__optix__types.html)

所以以下推理不成立：

```text
AS buffer 需 128B 对齐
=> RT cache line 必定 128B
=> K=16 必定是 2048B
```

### 专利是结构先验，不是 GB202 规格表

NVIDIA 的专利明确描述过：

- TTU 内有 L0 complet cache 和 L0 primitive cache；
- complet 通常由一条 cache line 取回；
- L0 可采用 allocate-on-return、pending-address grouping 和 read-only data RAM；
- 一个“非限制性实施例”举例使用 8 条 data lines。

这些内容证明“RT traversal 单元内部可能有专用的小型 L0”是非常合理的硬件假设。[US20200050550A1](https://patents.google.com/patent/US20200050550A1/en)，[US11302056B2](https://patents.google.com/patent/US11302056B2/en)

但专利同时明确写成 `N` 条、每条 `M` bytes，总量 `N × M`；它没有把 `M` 指定为 128。8 条也是 example/non-limiting，而不是所有代际的固定配置。该专利族优先权日期为 2018-08-10，不能直接当作 2025 Blackwell 第四代 RT Core 的实现规格。

还有一个对“每 SM”措辞非常重要的限制：同一专利允许一个 TTU 服务两个 SM。NVIDIA 对 Turing 曾公开说每 SM 有一个 RT Core，但 RTX 5090 的“170 个 RT Core”和本机 170 SM 数量相等，只能说明数量关系相容，不能证明 cache ownership、共享域或请求路由。[Turing Architecture](https://developer.nvidia.com/blog/nvidia-turing-architecture-in-depth/)，[RTX 5090 官方发布信息](https://www.nvidia.com/en-us/geforce/news/rtx-50-series-graphics-cards-gpu-laptop-announcements/)

因此，即使容量拐点完全成立，第一版严谨命名也应是：

> 当前 OptiX 路径和执行 locality 可见的 RT traversal 有效缓存/地址结构阈值。

不能先验命名成“每 SM RT L0 bytes”。

## 现有设计做对了什么

- 单个 raygen 线程避免了 SM warp 间隐藏延迟，`optixTrace` 在程序语义上顺序完成；handle-ring 的 `next` 依赖也阻止下一次 handle load 提前完成。
- 每个 GAS 有独立输出 buffer 和 traversable handle，确实制造了不同 AS 地址工作集。
- forced-miss 与 guaranteed-hit 分开，方向和 payload 有正确性校验。
- empty 和 ring 控制能排除明显的循环、`clock64()` 以及 handle-table load 拐点。
- warmup 后再计时，并保存 raw samples，而不是只保留一个平均数。
- VRAM、trace-count 和 watchdog 有保守上限；不改功耗、风扇、固件或内核模块。

这些特点让当前 16→17 结果不是一个可以随手忽略的噪声点。下面的问题决定它最终能被叫作什么。

## 会制造假拐点的因素

| 优先级 | 混淆因素 | 可能产生的假象 | 必须做的控制 | 通过后能排除什么 |
|---|---|---|---|---|
| P0 | 每个 GAS 单独 `cudaMalloc` | 第 17 个 allocation/page 触发 GPU TLB、地址翻译或 allocator 粒度阈值 | 把所有 GAS 输出放进一个连续 allocation 的非重叠 128B-aligned 子区；再比较 128B-packed、4KiB、64KiB、2MiB stride | 区分“不同 AS 数据数”与“不同 allocation/page 数” |
| P0 | 固定相同大小 allocation 的地址低位规律 | 第 17 个地址开始打到同一 L1/RT set，表现为 associativity conflict，不是总容量 | 记录 buffer VA 与 handle；改变 allocation 顺序、保留 dummy gaps、随机 offset/stride、多次重建 | 若 breakpoint 随地址映射移动，则是 conflict/allocator 候选 |
| P0 | K 的成员永远是 `handles[0..K-1]` | 某个具体 handle/GAS 恰好慢；嵌套集合和 K 强相关 | 从至少 64 个 GAS pool 中为每个 K 随机抽不同成员；访问顺序和成员集合使用两个独立 seed | 排除特定 handle 和 nested-set 历史 |
| P0 | unique handle 本身，而非 AS line | 16-entry handle decode/root descriptor/translation cache 会和 complet L0 一样拐 | same-real-GAS 重复 K 次；再做“一 handle、多节点/primitive 工作集” | same-handle 只排除循环；一-handle多节点才开始区分 handle cache 与数据 cache |
| P0 | `optixTrace` 调用 miss/CH | SBT、continuation stack、用户程序和 instruction cache 污染测量 | 以 `optixTraverse()` + hit-object query 为主，不 `optixInvoke()`；trace 版只作验证 | 去掉 miss/closest-hit 执行成本 |
| P0 | hit 与 miss 路径并非只差 primitive | 直接相减被误叫成 primitive-cache latency | 先验证共有 breakpoint；再用一-handle多-leaf、constant-root/vary-primitive 场景 | 只有 primitive 工作集独立变化时，差值才有 primitive 解释力 |
| P0 | 所有 K 在同一 launch 内按升序跑 | 热历史、温升、DVFS、长 launch preemption 与 K 完全相关 | one-K-per-launch；K 顺序随机/反向/Latin-square；独立进程重复 | 排除顺序漂移和跨 K cache carry-over |
| P0 | inner samples 同属一次 warm launch | 9 个 sample 被误当 9 个独立实验，置信区间虚假变窄 | 统计单位用“新 context + 新 build + 新 allocation seed”的 run；inner sample 只估 run 内噪声 | 避免伪重复 |
| P1 | `rounds × K` 使每个 sample 的操作数随 K 变化 | timer/loop 固定开销按 `1/K` 衰减，或大 K 更易被抢占 | 每个 K 使用相同 trace 总数，例如 8192；warmup 也以固定最小 trace 数定义 | 排除时间窗长度和 amortization |
| P1 | 顺序环访问 | 硬件预取、地址步长或 replacement policy 对固定环特殊优化 | Sattolo 单环；多 seed；顺序、逆序、随机顺序都跑 | 排除固定 stride/next-line 效应 |
| P1 | AS 是 opaque builder 输出 | 一 GAS 可能触及 1 条、数条或特殊 inline root/triangle；2,560B allocation 不是 working set | forced-miss、one-handle-many-node、build flag/compaction/layout 交叉；冷流量辅助估计 | 才能把“每 GAS”换算成“每 complet/primitive line” |
| P1 | 普通 L1/L2/TLB 参与 RT miss 返回 | L1 容量或 set miss 被误叫 RT-private L0 | only-K 的 L1TEX/L2 sector 采样；unique−same、trace−ring 差分；L1 trash/no-trash 对照 | 无共享-cache 流量跳变时才增强 RT-private 解释 |
| P1 | validation mode 为 ALL | 官方说明会启用额外 device-code 检查设施，可能改变性能路径 | correctness/smoke 用 ALL；正式计时用 OFF；两者结果交叉检查 | 排除调试设施 |
| P1 | `clock64()` 的含义被过度解释 | 它计的是线程经历的 per-SM cycles，包括 time slicing/等待，不是 RT 指令本身 cycles | 同时记录 CUDA event wall time；过滤 preemption outlier；记录 SM clock/temp/power | 正确解释为端到端调用延迟 |
| P1 | 单线程没有覆盖专利的多 ray grouping 行为 | 测到 serial effective capacity，却被外推成并发工作负载下物理容量 | 另做 1、2、8、32 ray concurrency sweep；不与单线程容量主结果混在一起 | 验证容量是否依赖 pending requests/allocate-on-return |
| P1 | 单 raygen 线程被说成“每 SM RT cache” | shader 在线程所在 SM，不证明 RT cache 私有域 | 记录 `%smid`；跨 SM/同 locality 干扰实验；至少按 smid 分层复现 | 只在共享域验证后才能加“per-SM” |
| P2 | 系统显示/其他进程流量 | 偶发 L1/L2 eviction 或 preemption 被看成局部 jump | 空闲桌面、记录进程/utilization；robust statistics；重复 run | 降低外部噪声 |
| P2 | identical one-triangle GAS 特例 | builder 可能用特殊最小结构，不能代表一般 BVH | 改三角形内容但保持相同复杂度；2、4、8 primitive GAS；compacted/non-compacted | 验证结果是否仅限最小 GAS encoding |

### `clock64()` 的具体限制

CUDA 官方定义 `clock64()` 为 per-multiprocessor、每周期递增的计数器；两次采样之差包含线程从开始到结束经历的时间，而不是该线程真正执行指令的周期数，因为线程会被 time-slice。[CUDA C++ Programming Guide](https://docs.nvidia.com/cuda/archive/13.0.0/cuda-c-programming-guide/index.html#time-function)

对本 probe 而言，端到端 latency 正是有用量，但应称为：

```text
raygen thread observed cycles per completed traversal call
```

不应称为“RT Core 内部命中延迟”。

## 如何鉴别当前 K=16 候选

### 候选解释和判决实验

| 假设 | 当前数据是否相容 | 最强鉴别实验 | 预期结果 |
|---|---|---|---|
| H1：16 条 complet/root L0 | 相容；miss 与 hit 共模 jump | cold/warm + prime–E–probe；packed/padded 均固定 E=16 驱逐 | 单 GAS 冷暖差约等于 26.5 cyc；E=16 后 probe 突然变冷 |
| H2：16-entry handle/root metadata cache | 同样相容 | 单一 handle 内选择 ≥32 个不同节点/叶；与 32 handles×一 root 对照 | 只有多 handle 拐，单 handle 多 node 不拐 |
| H3：GPU TLB / per-allocation translation | 很相容；当前每 GAS 一个 allocation | 单 allocation packed GAS 与一-GAS-per-large-stride 对照 | breakpoint 随 page/allocation 数而不是 K 固定 |
| H4：L1/RT set conflict | 相容 | 改 base offset、stride、handle membership seed；输出 address low bits | breakpoint 或 jump 大小随地址映射变化 |
| H5：普通 L1 容量 | 可能，但最小 GAS 所需实际 lines 未知 | K=16/17 only-K 采 L1TEX/L2 sectors；L1 trash 对照 | 17 的共享-cache misses/sector 明显同步增加 |
| H6：循环/timer | ring/empty 无 break，已被显著削弱 | same-handle K sweep + 固定总操作数 | same-handle 仍 flat |
| H7：primitive cache | 当前不支持 | 看 `hit-miss` 或 primitive-only 工作集 | 目前差值恒定；需要另一个只在 hit 上出现的 breakpoint |

### 最高信息量的 prime–evict–probe

单纯 cyclic K sweep 会把容量、set 冲突和 replacement policy 混在一起。建议增加如下序列：

```text
1. 把目标 GAS A 的 root/complet 反复访问到 warm。
2. 顺序或随机访问 E 个与 A 不同的 GAS，每个一次或固定次数。
3. 单独计时再次访问 A。
4. 扫 E=0..32，并对不同 A、不同 allocation/offset seed 重复。
```

同时测独立 cold baseline：先访问远大于候选容量的 disjoint pool，再访问 A。需要检查：

- `cold(A) - warm(A)` 是否接近 cyclic K=16→17 的约 26.5 cycles；
- eviction threshold 是否对不同目标 A 都是 16；
- threshold 是否不随 packed/padded/page layout 改变；
- same-handle 和 ring 控制是否没有相同现象。

若不同目标的阈值是 4、8、16 等一组值，更像 set associativity/conflict；若总在 16 且 cold-warm penalty 匹配，才更像总驻留容量。

## 建议的最小确认实验矩阵

### A. 正确性和空假设控制

1. `empty`、`ring`、`same_handle_miss`、`same_handle_hit`。
2. `optixTraverse` 的 miss/hit，两者不调用 `optixInvoke`，通过 hit-object query 校验。
3. 每个 K 单独 launch；正式测量 validation OFF。
4. 每个 timed block 固定总 operations；K=12..21 逐点密扫。
5. K 的执行顺序、mode 顺序随机化；把 seed 写进输出。

same-handle 的判读边界很重要：

- same-handle 也在 16→17 跳：基本否定 RT data working-set 解释；
- same-handle 不跳：只证明必须有不同地址/handle，仍无法区分 L0、TLB 和 handle cache。

### B. 地址、set 和 TLB 控制

至少实现下列四种仍保持所有 output buffer 存活的布局：

1. 当前：每 GAS 一个 `cudaMalloc`；
2. 一个大 allocation 内按 `align_up(outputSize, 128)` 紧密子分配；
3. 一个大 allocation 内 4KiB / 64KiB stride；
4. 大 stride 或 documented CUDA VMM granularity，使每 GAS 落入不同映射单位。

对每种布局：

- 从 ≥64 GAS pool 随机抽 K 个，而不是始终前 K 个；
- 至少 6 个 allocation/membership seeds；
- 输出每个 output-buffer VA、handle、相邻 VA delta、128B/4KiB/64KiB 低位；
- 不要把 handle 数值当物理地址；它和 CUDA VA 只能作为布局相关元数据；
- dummy allocation 必须保持 live，释放后 allocator 可能立刻复用，不能算有效 padding。

如果 K=16 在所有布局和随机成员集上稳定，TLB/allocator/set-conflict 的解释会显著变弱。

### C. 共享 L1/L2 counter 相关性

本机 catalog 没有 RTCORE 专属 cache hit/miss counter，因此 counter 只能做相关性证据，不能直接算私有 L0 容量。只采 K=14..19，尤其 16/17，并使用足够多 operations 放大单线程信号：

- 每个 K、每个 mode 单独 launch/range；
- 采 L1TEX tag/sector lookup hit/miss、L2 `srcunit_tex`/sector 等当前 GB202 catalog 中可用项；
- 用 `unique miss - same-handle miss`、`unique hit - same-handle hit`，并参考 ring 控制；
- Nsight Compute 使用 `--clock-control none --cache-control none`，避免工具替用户锁频或主动 flush cache；
- 限制为 one-pass，避免 replay 的 cache 状态成为新变量。

判读：

- 17 同时出现普通 L1/L2 sector/miss 突增：优先怀疑共享层或地址翻译；
- latency 跳但共享层流量在统计误差内等价：支持 RT-local front-end/L0，但仍不能单独区分 complet data 与 handle metadata；
- PM sampling 是 Device scope 且短 workload 信号弱，必须保留 raw counter 和采样误差。

### D. complet 与 primitive 的正交化

当前“不同小 GAS + miss/hit”不是完全正交设计。建议再做两个场景：

1. **constant handle / varying leaves**：一个较大 GAS，使用不同 ray origin/direction 选择 K 个不同 leaf/primitive；handle 恒定。
2. **varying handles / root-only miss**：当前独立小 GAS forced-miss，尽量只触发 root/complet 路径。

理想判读：

- 仅场景 2 在 16 拐：handle/root/complet 结构候选；
- 场景 1 的 hit 在另一个 K 拐、miss 不拐：primitive cache 候选；
- 二者均随传统 L1 traffic 变化：共享层候选。

对 one-GAS-many-leaf，BVH 内部节点数仍是 opaque 的，所以第一轮只能叫“单 handle 内节点/primitive 工作集”，不可直接把 K 当 cache-line 数。

### E. 执行 locality 和“每 SM”

每次 raygen 至少记录开始和结束 `%smid`；若不同则丢弃该 sample。然后：

- 把独立 run 按 smid 分层，检查 breakpoint 是否跨多个 smid 一致；
- 做 probe 与 background traversal 的干扰实验，尝试比较相同/不同 smid 或 TPC locality；
- 若公开 API 无法可靠控制 RT 请求路由，就把最终结论停在“local RT unit/domain”，不要强行写“per-SM”。

跨 smid 重复只能证明一致性，不能证明不共享；要证明 ownership，需要干扰域证据或官方 GB202 文档。

## 数据采集和统计方案

### 实验单位

正式统计单位是一个独立 run：

```text
新进程/新 OptiX context
+ 新 GAS build
+ 新 allocation/member/order seed
+ 一个预先指定的配置 block
```

一次 launch 内的 9 或 21 个 samples 只是该 run 的技术重复，不能把它们当作 n=9/21 的独立样本。

建议最低规模：

- 至少 30 个独立 runs；
- 覆盖至少 6 个 allocation/member seeds；
- 每 seed 至少 5 次新进程重复；
- 探索数据与确认数据分开。K=16 已经从探索数据中看到，后续 p-value/CI 必须用新数据。

### 主响应量

以 run 为 block，先求每个 launch 的 robust center（median 或 20% trimmed mean），再构造配对差分：

```text
Dmiss(K) = unique_forced_miss(K) - same_handle_miss(K)
Dhit(K)  = unique_hit(K)         - same_handle_hit(K)
P(K)     = unique_hit(K)         - unique_miss(K)
```

`Dmiss` 是当前 complet/root/translation 候选的主要响应。`P` 只能作为 primitive-sensitive 响应，不能假定各阶段延迟严格可加。

### 变更点检测

不要用“肉眼看起来在 16 跳”作为最终判据。可使用下面的简单、可审计流程：

1. 对每个 run 计算相邻差 `J_r(K) = D_r(K+1) - D_r(K)`。
2. 在所有候选 K 上取最大 robust jump，`b_hat = argmax_K median_r J_r(K)`。
3. 在 run/seed block 内置换 K 标签，得到 **max-statistic** 空分布；这会校正“从 31 个位置挑最大值”的多重比较。
4. 分层 bootstrap：先重采 allocation seed，再重采该 seed 下的 run，得到 breakpoint 和 jump 的 95%/99% CI。
5. 同时拟合无拐点的平滑模型与一个未知 breakpoint 的 two-plateau/hinge 模型，用 held-out runs 比较预测误差；不要仅报告 BIC 最小模型。
6. 做 leave-one-seed-out：删掉任一地址布局 seed，breakpoint 都不应消失。

建议预注册的确认门槛：

- max-statistic permutation `p < 0.01`；
- jump 的 99% CI 全部大于 0；
- breakpoint bootstrap 的绝大部分质量落在 K=16（允许报告 15–17，而不是硬凑一个整数）；
- same-handle、ring、empty 对“26.5-cycle jump”的等价界限通过，例如其 99% CI 落在 unique jump 的 ±20% 以内；
- packed/padded/page-spread/member-seed 的 breakpoint 差异不超过预注册的 ±1 K；
- cold-warm penalty 与 cyclic jump 在预注册容差内相符；
- `optixTraverse` 和 `optixTrace` 均复现，但以 traverse 结果为主。

如果布局间显著异质，应报告各布局结果，不能把它们 pool 成一个更窄 CI。

### 必须保存的元数据

- GPU name、UUID、PCI ID、SM count；
- driver、CUDA runtime、OptiX header/ABI/version；
- RT core version property（若 API 返回）；
- build flags、compaction、GAS output/compacted size；
- allocation layout、buffer VA、handle、seed、成员集合和访问顺序；
- K、warmup、operations、sample raw cycles、hit validation；
- `%smid` begin/end；
- run 前后只读查询的 SM clock、memory clock、temperature、power、utilization；
- validation on/off、OptiX disk cache 状态；
- 当前 GPU 上的其他进程列表或至少 utilization 快照。

不建议为了“漂亮曲线”用 `nvidia-smi -lgc`：它会改变设备配置，不符合本项目优先只读的约束。更好的办法是记录 clocks、随机 block 顺序、使用 cycles 与 wall time 双计时，并把明显 DVFS/preemption run 按预注册规则剔除。

## 证据等级和允许的措辞

| 等级 | 所需证据 | 可以说 | 不能说 |
|---|---|---|---|
| E0 | 单次曲线有 jump | “观察到候选拐点” | cache、容量、bytes |
| E1 | 新数据重复；negative controls flat；统计显著 | “不同 GAS 地址工作集在 K=16 有稳定阈值” | RT-private、complet、物理容量 |
| E2 | 地址/页/成员/顺序控制不改变；L1/L2 无同步 jump；traverse 复现 | “RT-local handle/root/complet 路径存在约 16-entry/record 的有效阈值” | 16 cache lines、2KiB |
| E3 | cold-warm 与 prime–probe 驱逐都在 16；一-handle多-node 鉴别通过 | “16 个 resident root/complet records/lines 的容量候选” | bytes，除非 line width 独立确定 |
| E4 | line width 由独立流量/地址实验或 GB202 官方资料确定 | “容量约 N × M bytes” | per-SM，除非共享域已验证 |
| E5 | smid 分层 + 同/跨 locality 干扰证明 ownership，或官方文档给出 | “每 SM（或每 TPC/RT unit）容量 X” | 跨驱动/架构普遍不变 |

### 什么数据只能给界限

- 扫到 Kmax 仍无 jump：在确知一 GAS 对应一目标 line/record 时，只能给 `capacity >= Kmax` 的下界；否则只能说“该工作集范围内未见有效阈值”。
- K=16→17 jump 但地址布局未控制：只能给“此访问模式的 no-thrash threshold 约 16”；物理 cache 可能更大，只是 set conflict。
- miss 有 jump、hit 同样 jump、`hit-miss` flat：只能给共有 root/complet/translation 路径候选，不能给 primitive-cache 容量。
- 专利 8 lines + AS 128B alignment：只是 `8 lines` 与 `128B alignment` 两个不同来源的先验，不能相乘成 1KiB 实测值。
- 单线程落在某个 SM：只能证明 shader execution locality，不能证明 RT cache 是该 SM 独占。

## 对当前 16→17 数据的正式判词

目前最准确的结论是：

> K=8 的专利候选没有在该 probe 中出现。unique one-triangle GAS 的 forced-miss 与 hit 在 K=16→17 都出现约 26.5 cycles/op 的共模上升，而 ring/empty 没有；`hit-miss` 仍约 497 cycles/op。该结果把 loop/timer-only 假象显著削弱，并把候选集中到不同 GAS 地址共有的 handle/root-complet/translation/shared-return 路径。由于每 GAS 仍是独立 allocation，且 cache-line width、每次 traversal 触及的 opaque AS lines、RT/SM ownership 均未被独立确定，16 目前只是“有效 unique-GAS threshold”，不是 Blackwell RT L0 的 line count 或 byte capacity。

下一步最有判别力、也仍然安全的三项是：

1. one-allocation packed GAS 对比 page-spread GAS；
2. cold/warm + prime–E–probe，检查 E=16 和约 26.5-cycle penalty 是否同时复现；
3. `optixTraverse` only-K + random member seeds，并用 same-handle/L1TEX 差分做控制。

完成这三项后，才值得决定是把 16 升格为 complet-L0 候选，还是归因于 TLB/allocator/set/handle translation。

## 安全边界

该 probe 并非字面意义的“只读 GPU”：建立 GAS、写 timing buffer 必然会写进本进程拥有的 VRAM。但它可以保持 **系统配置只读、设备状态非持久修改**：

- 不锁频、不改 power limit/ECC/persistence/fan；
- 不 reload driver/module，不访问未文档化 MMIO；
- OptiX disk compilation cache 保持关闭；
- 只使用 documented CUDA/OptiX allocation、build、launch、counter query；
- 每 launch 有短 watchdog 和 trace 上限；
- profiler 使用 clock/cache control `none`；
- 超时只终止 probe 进程，不 reset GPU。

在这个边界内，上述确认矩阵属于低风险、短时、可回收的只读式微架构观测。

---

## 第二轮追加评审：prime–probe 与 L1TEX 整数计数（2026-07-11）

本节基于第一轮之后取得的新数据，**其判词优先于前文对 16→17 仍停留在 E1/E2 的保守表述**。本轮只审查结果，没有再次运行 GPU，也没有修改基准源码。详细 counter 归一化审计见 [counter_analysis.md](counter_analysis.md)。

### 新证据

prime–probe 的 K 定义为：一个先 prime、最后 probe 的目标 A，加上中间的 `K-1` 个 evictors。结果是：

```text
unique evictors, contiguous GAS layout:
    K <= 16 : probe floor = 3992 cycles
    K >= 17 : probe floor = 4019 cycles

unique evictors, padded GAS layout:
    K <= 16 : probe floor = 3992 cycles
    K >= 17 : probe floor = 4019 cycles

same-handle evictors, K=1..24:
    probe floor = 3992 cycles
```

所以 A 与 15 个其他项共存时 A 仍命中；插入第 16 个其他项、使集合达到 17 项时，A 稳定多付约 27 cycles。紧密连续子分配和保留 4–28KiB dummy gaps 的 padded 独立分配得到同一边界，显著削弱了 allocation 数、传统 TLB/page 数和简单地址步长解释。same-handle 的完全平坦则排除了 trace 数、prime/probe 循环和 miss/SBT 公共路径本身造成的阈值。

one-pass NCU 的 L1TEX hit+miss sector 整数差分更有鉴别力：

```text
K=16: unique - same = 60
      = 4 * (16 - 1)

K=17: unique - same = 73,980
      = 4 * (18,496 total traversals - 1)
```

这意味着：

- K=16 时，除了 same-handle 已包含的第一个 GAS，另外 15 个 GAS 各产生一次 4-sector 冷填充；之后所有重复 traversal 都由候选上层驻留结构满足，不再查 L1TEX 的这 4 个 sectors。
- K=17 的循环中，除第一个访问外，每次 traversal 都重新向 L1TEX 请求 4 个 sectors；这正是 16-entry 容量面对 17-item 循环时逐次淘汰/逐次 refill 的稳态指纹。
- 新增 lookup 几乎都是 L1 hits；L2 只有初始冷填充，没有 per-traversal 台阶。因此 27 cycles 是候选 RT-local 层 miss、由普通 L1 命中返回时的端到端增量，不是 L1→L2 或 DRAM 台阶。

NVIDIA 官方将一个 sector 定义为对齐 32B，L1/L2 line 为 4 sectors/128B。[Nsight Compute Profiling Guide](https://docs.nvidia.com/nsight-compute/ProfilingGuide/index.html#quantities)

### E3 / E4 判定

| 证据项 | 第二轮判定 | 理由 |
|---|---|---|
| 16-entry 有效容量 | **E3 已达到** | cyclic sweep、直接 prime–probe 驱逐和 exact sector-count 三种观测都在 16/17 给出同一边界；same-handle 为负控制；contiguous/padded 为布局控制 |
| 位于普通 L1 之上的 RT traversal 驻留层 | **强证据，达到 E3** | 该层命中时不出现 4-sector L1 lookup；溢出后每次都出现且命中 L1；这不是普通 L1 自身的容量 miss |
| 每次 refill 的 backing 请求量 | **E4 的流量部分已达到** | exact `+4 sectors/refill`，即 `4 × 32B = 128B` 的 L1TEX backing traffic |
| `16 × 128B = 2KiB` 有效 backing footprint | **可以报告** | 16 个 resident items，每个被淘汰后对应 128B backing 请求，因此覆盖的 L1-backed working set 为 2KiB |
| RT 单元内部 data RAM/物理 SRAM 恰为 2KiB | **E4 尚未达到** | aggregate sector counter 没有给出四个 sector 的地址；也不证明内部保存的是原始 128B、解压后的更宽 record，还是只保存其子集与 metadata |
| raw complet cache，而非融合的 handle/root record cache | **尚未区分** | 当前一个 handle 恰对应一个最小 GAS root；改变 handle、root 地址和 complet record 是同一操作 |
| 每 SM 2KiB | **未达到 E5** | 尚无 cache ownership/共享域干扰证据；单 raygen 的 `%smid` 不能单独证明 RT cache 私有于该 SM |

这里的“E3 已达到”特指：

> 在该 RTX 5090、当前驱动、OptiX 9.1、单线程 one-triangle-GAS forced-miss 路径上，存在一个位于普通 L1TEX 之前、对不同 GAS/root 地址具有 16-entry 有效驻留容量的 RT traversal 层。

它不是对任意 BVH、并发 ray 数、所有 RT Core、所有驱动版本的普遍物理规格声明。

### 为什么现在不再优先怀疑普通 TLB 或 L1 set

传统 translation-only TLB 不能单独解释 K≤16 时重复 traversal 完全省去那 4 个 AS-data L1TEX sector lookups：地址翻译命中只提供地址，仍需要某处提供 root 数据。K=17 时出现的是每 traversal 固定 128B 的 L1TEX data lookup，而且这些 lookup 命中 L1。连续单 allocation 布局仍在 16/17 发生相同驱逐，也进一步削弱了“第 17 个独立 allocation/page”的解释。

普通 L1 容量/set 也不是这个台阶本身：候选层溢出后，新增请求在 L1 命中，而不是使 L1 miss/L2 request 每操作增加。地址映射仍可能决定这个 RT-local 结构的 set conflict 行为，但它最多影响“16 是总 entry 数还是本地址集合的有效 associativity”；它不再能把整体现象解释成普通 L1 cache 容量。

仍需保留的较窄替代解释是：

> 16-entry 的结构可能是一个融合的 handle decode / root descriptor / complet-return cache，而不一定是只存 raw complet bytes 的纯 data cache。

因此命名时不应只写 `handle translation cache`。纯 translation 不足以解释 128B AS backing lookup；更准确的替代名称是 `handle-resolved root-record cache`。

### 应该称为 root、complet，还是 handle translation

本轮 forced-miss 射线不会到达 primitive intersection，且 hit/miss 先前显示相同的 16→17 共模台阶，所以可以排除 `primitive cache` 作为本结果的主要对象。

在 NVIDIA 专利术语中，root/interior BVH node 由 complet 表示，并通过 L0 complet cache 供 ray-complet test 使用；当前行为和这个结构高度吻合。但 OptiX GAS encoding 与 traversable handle 的解析仍是 opaque，最小 one-triangle GAS 还可能使用专门的 root descriptor encoding。

推荐按严谨程度使用下面的名称：

1. 最严谨：**RT traversal root-record residency cache/structure**。
2. 结合专利的解释性名称：**root/complet-path L0 cache candidate**。
3. 可接受但必须带限定：**16-entry、128B-backing-line 的 effective RT L0**。
4. 暂不应使用：**primitive cache**、**纯 handle translation cache**、**已证实每 SM 2KiB 物理 RT SRAM**。

“complet”目前是最可能的内容解释；“root-record”是实验直接支持度最高的中性名称；“handle translation”只能保留为可能与 root descriptor 融合的实现细节。

### 2KiB 的准确措辞

现在可以说：

> RTX 5090 的该 OptiX forced-miss 微基准测得一个 16-entry 的 RT traversal root-record 驻留层。每个被淘汰项会触发 4 个命中 L1TEX 的 32B sector lookups，即 128B backing traffic；因此该路径的有效 L1-backed working-set capacity 为 `16 × 128B = 2KiB`。RT-local 命中相对 L1-hit refill 节省约 27 个 raygen-observed cycles。

更短的工程表述可以是：

> **RT root/complet L0：16 entries，128B backing line，2KiB effective backing footprint，L0→L1-hit penalty ≈27 cycles。**

必须紧跟一句限制：

> 2KiB 是被实测 16-entry 结构所覆盖的 backing-data footprint；尚未证明其内部物理 SRAM payload 恰为 2KiB，也尚未证明它由每个 SM 独占。

仍然不能说：

> **Blackwell 每 SM RT L0 cache = 2KiB。**

后一句同时把“有效 backing footprint”升级成“物理 data RAM bytes”，并把未知的 RT/TPC ownership 升级成“每 SM”，跨过了两个尚未完成的证明环节。

### 还差什么才能把 E4 写成物理 2KiB

最小追加证据是：

1. 同一 one-pass 同时得到 refill request/tag 数和 sector 数，证明每次是一个 tag/一个 request 对应四个 sectors，而不是多个地址合计四 sectors。
2. 改变目标 A 和随机成员/地址 seeds，prime–probe 都保持 16，排除只对当前一组地址形成的 16-way conflict set。
3. 一个 handle 内制造多个可选择 root/interior complet records；若它们也占用同一 16-entry 池，便可把融合 handle-only cache 与 complet-data cache 分开。
4. 若能从官方 GB202 文档或独立地址级流量证据确认 RT-local fill unit 原样保存一条 128B line，才可把“2KiB backing footprint”升级为“2KiB data payload capacity”。

即使完成这些，`per-SM` 仍需另做 cache-sharing/interference locality 实验。

---

## 第三轮实测更新：replacement 与双SM联合容量（2026-07-12）

第二轮末尾列出的第2、4项已得到更强证据：

- 64-GAS池的prefix扫描最初与LRU逐项相同，但任意refresh直接推翻了该解释：只
  refresh Ai时，16/16项均淘汰A(i+1 mod16)；多次、重复、逆序序列跨4种layout/
  rotation的24/24 insert/no-insert控制也由最后命中的环后继决定，局部差固定27
  cycles。当前串行语义是hit-updated circular successor，不是真LRU。
- 地址选择扫描覆盖192个仿射序列，全部只在E=16出现27-cycle台阶；四个16项集合
  逐成员删除所得64个15项子集全部不淘汰且平台spread为0。所测64-GAS root池支持
  16-entry effective fully-associative capacity，物理全地址保证仍未达到。
- same-launch P/Q在三组paired SM上做联合容量缩放。远端prime A与Q本地15个roots
  共存，第16个local root使A收益归零；正反执行顺序一致，cross-domain对照为零。
  因此两个SM观察到同一16项有效budget，但物理共享array与复制/迁移/转发仍未区分。

详见 [`RT_ROOT_REPLACEMENT_FINDINGS.md`](RT_ROOT_REPLACEMENT_FINDINGS.md) 与
[`RT_CACHE_OWNERSHIP_FINDINGS.md`](RT_CACHE_OWNERSHIP_FINDINGS.md)。本节判词优先于
前文仍把replacement或ownership写成“未完成”的历史计划。
