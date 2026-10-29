# RTX 5090 RT 路径缓存实测结论

日期：2026-07-11；扩展更新 2026-07-12（Asia/Singapore）  
设备：NVIDIA GeForce RTX 5090，CC 12.0，170 SM  
软件：Driver 610.43.03，CUDA 13.3，Nsight Compute 2026.2.1，OptiX 9.1

## 一句话结论

本机实测确认了一个位于普通 L1TEX 之前、只在访问不同 GAS/root 记录时生效的
**RT traversal root-record 驻留层**：

```text
有效驻留阈值       = 16 entries
淘汰后的 backing 访问 = 4 × 32 B L1TEX sectors = 128 B / traversal
有效 backing footprint = 16 × 128 B = 2 KiB
越界惩罚           ≈ 26.5--27 GPU cycles
```

结合 NVIDIA 的 TTU L0 专利描述，它最像 **root/complet-path L0 cache**。但当前
公开计数器不能看到 RT 单元内部的数据 RAM，故严谨表述是“16-entry、2 KiB
L1-backed 有效工作集”；不能把它直接写成已证实的“每 SM 2 KiB 物理 SRAM”。

后续 IAS/GAS、L2 persisting 与 OptiX JIT 实验已经把运行图扩展为：

```text
IAS/GAS root events       -> 约 16-record domain
instance/leaf stages      -> 31-record class；direct GAS一阶段，IAS hit两同步阶段
IU triangle-hit 首冷路径  -> 5 条可逐地址干预的 128 B AS backing line
RT backing 的 L2 residency -> 可由 CUDA persisting pre-touch 间接控制
current-hit vertex fetch  -> OptiX JIT 中可见隐藏 TTU D0-D4 opcode family
root traversal ownership  -> 特定双-SM可见域（TPC candidate），跨已测域不共享
root replacement          -> hit-updated circular successor；非LRU
root address mapping      -> 所测64-GAS池等效全相联16项；未见E<16冲突集
```

五条地址、9/17 整数 sector 方程和 compiler 证据的当前统一图见
[`IAS_GAS_BACKING_LINE_FINDINGS.md`](IAS_GAS_BACKING_LINE_FINDINGS.md) 与
[`OPTIX_JIT_REVERSE_FINDINGS.md`](OPTIX_JIT_REVERSE_FINDINGS.md)；跨层最终地图见
[`RT_5090_ARCHITECTURE_MAP.md`](RT_5090_ARCHITECTURE_MAP.md)。

## 先把三个容易混淆的容量分开

| 层级 | 本机结论 | 证据强度 |
|---|---:|---|
| 全 GPU L2 | 96 MiB（100,663,296 B） | 官方白皮书 + CUDA API 直接确认 |
| 每 SM 统一 L1/shared 物理池 | 128 KiB | 官方白皮书；本机配置显示两块 64 KiB SRAM |
| RT traversal root-record 驻留层 | 16 entries，128 B/refill，2 KiB effective backing footprint | 三类微基准和 one-pass counters 一致 |
| root域 replacement | 最后命中Ai后插入X，victim精确为A(i+1 mod16)，固定+27 cycles；真LRU被否定 | 16个单refresh + 24个任意顺序插入控制 |
| root域地址映射 | 192/192序列只在第16个evictor淘汰；64/64个15项reduction均不淘汰 | 4 layouts、6 victims、8 address steps |
| RT hit/deeper-path 驻留类 | direct GAS一条31-record阶段；IAS/shared-child gap+27、leaf+54，显示两个同步31-class阶段；均为30 stable+1 slot | sector方程、same-GAS/relocation、IAS gap/leaf paired |
| RT AS 的 L2 backing | CUDA persisting pre-touch 可保护；TTU self-policy 无效 | 96 MiB 容量阶梯、reset/normal controls、逐地址扫描 |
| RT traversal 可见域 | 特定 paired SM 约 0.46--0.50k-cycle transfer；远端 A +15 Q-local roots保留，第16个清除；跨域约0 | same-launch `%smid`、A/C 因果对照、双端 L1-trash、v11联合工作集 |

因此原先的 `96 MiB L2 + 64 KiB/SM L1 + RT 私有缓存` 需要修正为：

```text
96 MiB L2
128 KiB/SM 统一 L1/shared 物理池（不是固定 64+64）
另有一个 RT traversal 16-entry 驻留层，覆盖约 2 KiB 的 L1 backing 数据
```

NVIDIA 白皮书明确写出 RTX 5090 的 L2 为 96 MB、每 SM 含一个第四代 RT Core
和 128 KB L1/shared。参考：

- [NVIDIA RTX Blackwell GPU Architecture 白皮书](https://images.nvidia.com/aem-dam/Solutions/geforce/blackwell/nvidia-rtx-blackwell-gpu-architecture.pdf)

## 为什么原来的“L1 = 64 KiB”不能成立

Claude 的 `latsweep.cu` 有两个优点：Sattolo 单环正确，编译后的 load 也保持严格
依赖。但原扫描从 64 KiB 直接跳到 96 KiB，只能说明边界位于两者之间，不能把
64 KiB 称为最后平台点。

补做 84--100 KiB 细扫后：

| 工作集 | 中位周期/load | 判读 |
|---:|---:|---|
| 88 KiB | 48.155 | L1 平台，99.80% sector hit |
| 89 KiB | 51.191 | 最后近平台点 |
| 90 KiB | 71.716 | 渐进 transition，95.36% hit |
| 96 KiB | 172.401 | 严重 thrash，73.12% hit |

所以该随机单环下的近满命中工作集约为 89 KiB，而非 64 KiB。它是集合相联缓存
的“有效工作集”，也不应反过来当成物理 SRAM 字节数。完整控制数据见
[`l1_control/README.md`](l1_control/README.md) 与
[`l1_control/results.tsv`](l1_control/results.tsv)。

原程序固定只走 `2^21` 步；工作集超过 8 MiB 后连一个随机环都没有走完。因此
它的 96 MiB/1 GiB 段不能定位 L2 容量。L2=96 MiB 来自官方规格与本机
`cudaDeviceProp.l2CacheSize`，不是那段大工作集曲线。

## RT 缓存微基准

### 1. 稳态循环工作集

程序构建 K 个物理独立的一三角形 GAS，仅启动一个 raygen 线程，以 Sattolo 单环
反复执行 `optixTrace(handle)`。forced-miss 射线只走 traversal 公共路径，避免把
primitive hit 路径混入容量判读。

低噪声下界在 16→17 出现唯一台阶：

```text
K=14  4094.4 cycles/trace
K=15  4093.7
K=16  4093.1
K=17  4119.6   <-- +26.5 cycles
K=18  4119.1
K=19  4118.7
```

K=7/8/9 没有台阶，所以 NVIDIA 旧专利里的非限制性“例如 8 lines”并不是这块
GB202 上实测到的数值。

反证控制：

- `same-handle`：循环次数同为 K，但始终 trace 同一个 GAS；16→17 无台阶。
- `ring-only`：保留相同 handle/next volatile loads，不调用 `optixTrace`；K16/K17
  均约 101.2 cycles/step，无台阶。
- 地址顺序与物理布局：sequential、reverse、Sattolo、contiguous、permuted、
  separate、padded 均保留 16→17 阈值，显著削弱预取、固定 stride 和简单页布局解释。

### 2. Prime–evict–probe

每轮执行：

```text
prime A -> 访问 K-1 个不同 GAS -> 只计时 probe A
```

结果：

| 总工作集 K | unique GAS 最低 probe 周期 | same-handle 控制 |
|---:|---:|---:|
| 13--16 | 3992 | 3992 |
| 17--24 | 4019 | 3992 |

也就是 A 加 15 个其他记录仍能驻留；加入第 16 个其他记录、总计 17 个时，A 被
淘汰，probe 固定增加 27 周期。contiguous 与 padded 两种分配独立复现。

原始结果：

- [`prime_unique_k24.json`](agent_optix/minimal/results/prime_unique_k24.json)
- [`prime_unique_padded_k24.json`](agent_optix/minimal/results/prime_unique_padded_k24.json)
- [`prime_same_k24.json`](agent_optix/minimal/results/prime_same_k24.json)

### 3. Nsight Compute 的精确整数关系

`samples=1, rounds=1024, warmup=64`，所以 counter 覆盖的总操作数为：

```text
N16 = 16 × 1088 = 17,408
N17 = 17 × 1088 = 18,496
```

one-pass 采集 `L1TEX hit + miss sectors`：

| 模式 | K | L1 hit | L1 miss | total lookup |
|---|---:|---:|---:|---:|
| unique GAS | 16 | 599,004 | 115 | 599,119 |
| same handle | 16 | 599,019 | 40 | 599,059 |
| unique GAS | 17 | 710,359 | 120 | 710,479 |
| same handle | 17 | 636,459 | 40 | 636,499 |

最关键的不是近似均值，而是原始整数恰好满足：

```text
K=16: unique - same = 60     = 4 × (16 - 1)
K=17: unique - same = 73,980 = 4 × (18,496 - 1)
```

这表示：

- K=16 时，仅另外 15 个 GAS 各发生一次 4-sector 冷填充，之后全部驻留；
- K=17 时，除第一次外几乎每次 trace 都重新请求 4 sectors，符合容量 C=16、
  循环访问 C+1 项时逐次淘汰的经典行为；
- 新增 sectors 几乎全是普通 L1TEX hit，L1 miss 没有逐操作增加，所以 +27 周期
  是 RT 驻留层 miss 后回普通 L1 取 backing record，而不是掉进 L2。

Nsight Compute 定义 sector 为 32 B、L1/L2 line 为 4 sectors = 128 B：

- [Nsight Compute Profiling Guide — Quantities](https://docs.nvidia.com/nsight-compute/ProfilingGuide/index.html#quantities)

这 12 个 L1 原始整数又用只请求 hit/miss 的单 pass 方式全部复现；padded 分配下
也逐项 bit-for-bit 相同。完整独立核算见
[`counter_analysis.md`](counter_analysis.md)，机器可读汇总见
[`counter_summary.tsv`](counter_summary.tsv)。

## 和 NVIDIA TTU L0 专利如何对应

NVIDIA 专利明确描述：TTU 有自己的只读 L0 streaming/complet cache；L0 miss
会向普通 L1 请求数据，一个 complet 通常由一条 cache line 取回，data RAM 有
N 条、每条 M bytes。旧的非限制性示例用了 8 条，但同时明确 N/M 可配置。

- [US20200050550A1 — TTU L0 cache](https://patents.google.com/patent/US20200050550A1/en)

本机观察到的“16 项可驻留、越界后每次从 L1 请求 128 B、约 +27 周期”与该结构
高度吻合。因此推荐名称是：

```text
RT traversal root-record residency cache
或：root/complet-path L0 candidate
```

不要把这里的 16-entry 层命名成 primitive/triangle cache：forced-miss 与
guaranteed-hit 的共同台阶相同，而 hit-minus-miss 额外成本在 16→17 不变。
独立后续实验在 K=32 找到 hit/deeper-path 的 31-record effective threshold，
并把 triangle primitive backing 定位到当前 GAS output `+0x400`；但这仍不能
直接等同为“物理 32-entry triangle cache”，因为 instance leaf、deeper complet
和其他 hit 状态可能共享该域。同一GAS的64-target paired实验进一步反证了
per-primitive/per-ray-path allocation；64-build-input/SBT-index复测也为null，当前
候选应收紧为traversable/GAS-scoped record。

## 结论边界

已经达到：

1. 16-entry 有效容量阈值；
2. 淘汰后每次 4×32 B = 128 B 的 L1TEX backing traffic；
3. 16 entries 覆盖 2 KiB backing working set；
4. 该层位于普通 L1 前面，且只与不同 GAS/root traversal 地址相关。
5. IAS→GAS hit 的四个 L1TEX 可见 replacement events 可分成两个约 16-record
   root 域事件和两个约 32-record deeper-path 域事件；
6. 当前 exact AS build 的五条首冷 backing line 已逐 128 B 定位，IAS/GAS
   单独与联合保护效果近似严格可加；
7. 已提取 OptiX continuation cubin，并确认 live-data-dependent TTU D0–D4
   triangle-fetch 指令族；九个 component 变体把 D2 `0x34/0x35` 定位为两个
   result-bundle candidate、`0x36` 为共同 finalize，并确认 from-handle/hit-object
   entry 都不内联该序列。
8. same-launch P/Q 实验在 `{0,1}`、`{2,3}`、`{22,23}`、`{44,45}` 四组 SM 间
   复现双向 warm transfer；`0->22`、`23->44` 等跨组为零。普通 backing-load 与
   P/Q 双端 L1-trash 对照支持这是 RT traversal 状态的双-SM可见域，而非纯 L1
   backing 假象。v11 进一步在三组 paired SM 上精确复现 S=15保留、S=16清除，
   证明远端 A 参与 Q 所见的同一16-entry有效replacement budget。
9. 单线程任意refresh victim scan 已修正prefix带来的LRU误判：只refresh Ai时，
   16/16项均淘汰A(i+1 mod16)；六种多次/重复/逆序序列跨4种layout与rotation的
   24/24插入控制均由**最后一次命中的环后继**决定，局部差分固定+27.0 cycles。
   因此真LRU被否定，当前可观测语义为hit-updated circular successor。
10. 任意地址eviction-set扫描覆盖192个独立进程，最大台阶全部精确位于E=16；
    四个16项集合逐成员删除得到64个15项子集，全部不淘汰且平台spread为0。
    所测64-GAS root池支持16-entry effective fully-associative capacity。
11. hit/deeper层31+1逐victim显示：第31个fill是唯一随新X被替换的candidate；改变
    fill order后victim跟随最后fill的A30/A1/A4/A16，局部差均+27.0 cycles；填满后
    refresh稳定项不移动victim。这证明“30 stable records + 1 allocation-driven
    streaming slot”的可观测组织，并精确解释每环`K-30`条refill公式。
12. 同一9,344 B GAS内64个target/128个triangle的single-callsite AB/BA paired
    replacement中，32 victims×3 paths×2 pair orders的median全部为0；L1-trash
    四fill-order控制的`last-prev`最大绝对值5.25 cycles且不随最后fill移动。
    进一步拆成64个build input与64个SBT GAS index后仍为null。因此31-record
    allocation不是per-primitive/path/geometry，而是traversable/GAS对象级候选。
13. 同一次one-triangle build的2,560 B output复制并`optixAccelRelocate()`成64个
    合法clone后，四种fill order的hit-minus-outside victim均重新精确为+27 cycles，
    L1 trash把sequential `last-prev`放大到+501.75 cycles。独立build内容差异被排除，
    31-record tag随relocated output/handle身份变化。
14. 64个identity `OptixStaticTransform` handle共享同一child GAS时，plain和L1-trash
    32-victim map均为null，K1--64 unique-wrapper/same-wrapper的三条路径median也全0。
    因此generic traversable handle不同不足以占槽；当前信号更具体地跟AS output
    descriptor/backing record走。
15. 64个独立一实例IAS共享同一child GAS时，outside路径在A15出现16-class +27；
    double-triangle中央gap在最后fill出现+27，leaf为+54，因此leaf-gap再精确+27。
    sequential/reverse/permuted/Sattolo四种顺序都随最后fill移动，前一fill全0。这把
    IAS hit拆成两个同步31-class阶段，并与IU的两16/两32事件方程闭合。

尚未达到：

1. aggregate sector counter 看不到四个 sector 的地址，不能形式化证明四者一定是
   同一条连续 128 B line；
2. 不能证明 RT 内部 data RAM 以未压缩 128 B/entry 原样保存，所以“物理 SRAM
   正好 2 KiB”仍是候选；
3. ownership 已不再是“完全未知”：可观察状态跨特定双 SM 共享。但 warm transfer
   仍不能区分单份共享 SRAM、伙伴转发、coherent replication 或 victim 结构，故
   不能把 2 KiB effective footprint 写成“每 TPC 2 KiB物理 SRAM”；
4. 31-class层已排除raw primitive/path/build-input/SBT index作为allocation identity；
   relocation与shared-child已证明AS output/context相关。但IAS的两个31-class阶段
   仍不能区分“两套bank、multi-line bundle、parent-qualified child record”。
5. 双 SM 联合曲线已证明16-entry**有效**budget，但仍不能区分一份共享 SRAM、
   迁移/复制到伙伴local array或转发；31-record hit-specific域也尚未单独做ownership，
   “30+1 slot”仍不能等同为物理way/RAM布局。
6. D0–D4 的 dispatch/wait/result 字段与可能的 TTU request priority bit 尚未解码。
7. replacement的串行语义已区分于真LRU，但仍不知道物理pointer/PLRU bit布局，
   也未证明并发rays、pending grouping或其他record类型采用相同规则；有限64-address
   池的等效全相联结果不能升级成所有GB202地址的版图级保证。

严谨最终措辞：

> RTX 5090 的单线程 OptiX probe 实测到一个位于普通 L1TEX 之前的 RT traversal
> root-record 驻留层，具有 16-entry 有效阈值。越界后每次不同 GAS traversal
> 额外请求 128 B 的 L1 backing 数据，对应 2 KiB effective backing footprint，
> miss penalty 约 27 cycles。它很可能是 TTU root/complet-path L0，但 2 KiB
> 尚不能等同于已证实的物理 SRAM 容量。所测root池未发现E<16 set conflict，
> 串行replacement遵循hit-updated circular successor而非LRU。same-launch实验
> 进一步显示相关 traversal
> 状态在特定双-SM域内可见、跨已测域不共享；该域强烈符合 TPC candidate，但尚未
> 证明为一份每-TPC物理 cache。远端 A 会占用 Q 所见16项有效budget这一点已经由
> S=15/16 联合工作集边界确认。

## 复现与审查文件

- 基准源码与说明：[`agent_optix/minimal/README.md`](agent_optix/minimal/README.md)
- Device 端 trace/prime-probe：[`sweep_device.cu`](agent_optix/minimal/sweep_device.cu)
- Host 端 GAS/布局/安全限制：[`gas_sweep.cpp`](agent_optix/minimal/gas_sweep.cpp)
- 第一轮独立设计审查：[`benchmark_review.md`](benchmark_review.md)
- one-pass counter 独立审查：[`counter_analysis.md`](counter_analysis.md)
- 公开 GB202 metric catalog：[`metric_probe/README.md`](metric_probe/README.md)
- IAS/GAS 9/17 sector 方程：[`IAS_GAS_HIERARCHY_FINDINGS.md`](IAS_GAS_HIERARCHY_FINDINGS.md)
- IAS/GAS 五条 backing line：[`IAS_GAS_BACKING_LINE_FINDINGS.md`](IAS_GAS_BACKING_LINE_FINDINGS.md)
- L2 persisting → RT：[`L2_PERSIST_RT_FINDINGS.md`](L2_PERSIST_RT_FINDINGS.md)
- OptiX JIT / TTU D0–D4：[`OPTIX_JIT_REVERSE_FINDINGS.md`](OPTIX_JIT_REVERSE_FINDINGS.md)
- SM ownership：[`RT_CACHE_OWNERSHIP_FINDINGS.md`](RT_CACHE_OWNERSHIP_FINDINGS.md)
- root replacement：[`RT_ROOT_REPLACEMENT_FINDINGS.md`](RT_ROOT_REPLACEMENT_FINDINGS.md)
- same-GAS record内容：[`SAME_GAS_PATH_CONTENT_FINDINGS.md`](SAME_GAS_PATH_CONTENT_FINDINGS.md)
- relocation clone：[`RT_RELOCATION_CLONE_FINDINGS.md`](RT_RELOCATION_CLONE_FINDINGS.md)
- IAS shared-child：[`IAS_SHARED_CHILD_REPLACEMENT_FINDINGS.md`](IAS_SHARED_CHILD_REPLACEMENT_FINDINGS.md)
- 当前架构地图：[`RT_5090_ARCHITECTURE_MAP.md`](RT_5090_ARCHITECTURE_MAP.md)

所有 GPU workload 都有 2,000,000 traces/launch 和 10 s watchdog
硬上限；普通 probe 的显式 VRAM 上限为 64 MiB，L2-thrash 模式为 256 MiB，
且都不得超过启动时空闲 VRAM 的 1%。测试没有修改驱动、固件、功耗、ECC、持久化模式或内核模块；没有锁频，
也没有让 profiler flush cache。`sudo` 只用于读取受限性能计数器。测试后 GPU 为
37--38°C。
