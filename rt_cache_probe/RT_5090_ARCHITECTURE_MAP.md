# RTX 5090 RT 路径：当前实验架构地图

更新：2026-07-12  
范围：本机 GB202、Driver 610.43.03、CUDA 13.3、OptiX 9.1；单线程串行结论除非另注

## 总图

```text
OptiX/CUDA shader
  |
  |  current-hit triangle fetch: hidden 128-bit TTU D0--D4 JIT family
  v
RT traversal front end
  |
  +-- IAS +0x000  traversable header/decode          [L2 backing line]
  |
  +-- IAS +0x700  IAS root/first-complet ----+
  |                                           |
  |                                           +-- root domain
  +-- GAS +0x380  GAS root/first-complet -----+   16-entry effective capacity
  |                                               circular-successor replacement
  |                                               paired-two-SM visible domain
  |
  +-- IAS +0x600  instance/child-path ----------+   31-class stage A
  |       |
  |       +-- child pointer -> GAS +0x380
  |
  +-- GAS +0x400 / parent-qualified leaf -------+   31-class stage B
                                                    each: 30 stable + 1 allocation slot
                                                    AS-output/context scoped, not per
                                                    primitive/build-input/SBT index
  |
  v
ordinary backing hierarchy
  RT resident hit
      -> L1TEX refill: 4 x 32 B sectors = 128 B, about +27 cycles
      -> 96 MiB L2
      -> GDDR7
```

虚线边界不能由公开counter直接看到；图中的域归属来自容量方程、路径差分、逐地址
L2干预和opaque AS bytes的联合证据，不是NVIDIA公布的GB202 tag-RAM规格。

## 已经钉死的量

| 对象 | 当前最强结论 | 关键证据 |
|---|---|---|
| SM普通L1/shared池 | 物理总池128 KiB；随机依赖环近满命中约89 KiB，不是固定64 KiB数据分区 | 官方规格、本机细扫与sector hit ratio |
| root/first-complet驻留域 | 16 entries；128 B L1 backing/refill；2 KiB effective backing footprint | cyclic、prime/probe、精确sector与SRAM1守恒 |
| root地址映射 | 所测64-GAS池中等效全相联16项；未见E<16冲突集合 | 192个仿射序列、64个15项reduction |
| root串行replacement | 最后命中Ai后，插入X淘汰A(i+1 mod16)；非LRU | 16个单refresh、24个任意/重复顺序插入控制 |
| hit/deeper-path驻留类 | direct GAS有一个31-record阶段；IAS/shared-child的gap为+27、leaf为+54，显示两个同步31-class阶段；前30个fill稳定，第31个进入allocation slot | sector方程、same-GAS null、GAS relocation、IAS gap/leaf四fill-order |
| AS首冷backing | IU triangle hit可定位5条128 B line | CUDA persisting逐地址干预与dump |
| root状态可见域 | 特定相邻双SM可见；跨已测域为零；伙伴状态参与同一16项有效budget | same-launch SMID、双端L1 trash、S15/S16联合容量 |
| L2 | 96 MiB | NVIDIA规格与`cudaDeviceProp` |

## Replacement 的准确模型

早先prefix结果：

```text
fill A0..A15 -> refresh A0..A(N-1) -> insert X -> victim AN
```

同时满足LRU和circular-successor，不能判别。任意顺序给出决定性分叉：

```text
refresh only A2 -> LRU predicts A0, observed A3
refresh A1,A0   -> LRU predicts A2, observed A1
refresh all in reverse A15..A0 -> LRU predicts A15, observed A1
```

所以软件可见规则是“最后命中项的环后继成为下一victim”。它可能由pointer、clock或
某种way枚举PLRU实现；不能从行为直接命名晶体管级电路。

## IAS/GAS 五条backing line

| 地址 | 当前路径语义 | miss也访问 | hit新增 | 驻留域候选 |
|---|---|---:|---:|---|
| IAS `+0x000` | traversable header/decode | 是 | — | 未进入已测16/32方程 |
| IAS `+0x700` | IAS root/AABB/first-complet | 是 | — | 约16-record root域 |
| IAS `+0x600` | instance leaf、transform、child-root pointer | 否 | 是 | 31-class stage A候选；shared-child gap单独+27 |
| GAS `+0x380` | GAS root/first-complet | direct GAS / child hit | — | 约16-record root域 |
| GAS `+0x400` | one-triangle build中的triangle/geometry data | 否 | 是 | stage B backing候选；IAS parent context可能参与resident identity |

每条在当前exact build上都可由128 B persisting window单独恢复约0.61k cycles的
DRAM→L2首冷代价。offset是当前OptiX build布局，不是稳定ABI。

## 编译器逆向得到什么

逆向OptiX continuation cubin有明确收益：current-hit triangle component读取会生成
一组普通公开SASS反汇编器未命名的128-bit D0--D4指令。九个component变体显示：

- D4 immediate/variant随component组合变化；
- D2 slot `0x34/0x35` 是两个result-bundle candidate；
- slot `0x36` 是共同finalize；
- from-handle与hit-object entry不内联这组D指令。

这证明compiler根据live component需求构造TTU fetch/result协议，能帮助定位请求、
等待和结果路径。它还没有解出dispatch/wait字段，也不提供可安全手写的公开ISA。

## 软件真正能控制的层

```text
ray / instance / traversable/GAS sorting
  -> 提高16-entry root域和31-record hit域的时间局部性；同一GAS内仅按primitive
     排序不会增加31-record allocation容量命中

CUDA persisting pre-touch AS output
  -> 保护下游L2 backing

只给OptiX stream设置persisting policy
  -> 对TTU self-read无效
```

普通global preload只能暖普通backing；双端L1 trash后它与RT trace prime明显分离。
因此“RT resident状态”和“L1/L2 backing residency”是两个需要分别优化的控制面。

root排序不能再用纯LRU直觉：最后触碰热点Ai会保护Ai，但把下一victim移动到环后继。
CUDA/OptiX也没有稳定接口把ray固定到实测双SM域，不能把SMID配对硬编码进产品。

## 仍然未知，按信息增益排序

1. IAS/shared-child的两个31-class阶段是两套bank、一个multi-line bundle，还是
   parent-context-qualified child record；timing已分出gap+27与leaf再+27，但tag组合
   仍不可见。
2. 同一固定GAS内更深interior path能否占用16-entry域；它决定root-only还是通用
   complet cache。
3. 31-record hit/deeper域的ownership；replacement已定位为可观测
   `30 stable + 1 allocation slot`。
4. circular-successor在并发rays、pending request grouping和allocate-on-return下
   是否保持。
5. 双SM域是一份物理共享array、复制/迁移、伙伴转发还是victim结构。
6. 深BVH/嵌套IAS的stack项数、spill路径和局部存储位置。
7. cluster、LSS、OMM是否有独立驻留域或共享31-record域。
8. D0--D4的dispatch/wait/result字段与潜在priority bit。

## 证据入口

- 总结：[`FINDINGS_5090_RT_CACHE.md`](FINDINGS_5090_RT_CACHE.md)
- root replacement/set mapping：[`RT_ROOT_REPLACEMENT_FINDINGS.md`](RT_ROOT_REPLACEMENT_FINDINGS.md)
- IAS/GAS地址：[`IAS_GAS_BACKING_LINE_FINDINGS.md`](IAS_GAS_BACKING_LINE_FINDINGS.md)
- ownership：[`RT_CACHE_OWNERSHIP_FINDINGS.md`](RT_CACHE_OWNERSHIP_FINDINGS.md)
- hit/deeper域：[`PRIMITIVE_PATH_CACHE_FINDINGS.md`](PRIMITIVE_PATH_CACHE_FINDINGS.md)
- same-GAS内容判别：[`SAME_GAS_PATH_CONTENT_FINDINGS.md`](SAME_GAS_PATH_CONTENT_FINDINGS.md)
- relocation clone：[`RT_RELOCATION_CLONE_FINDINGS.md`](RT_RELOCATION_CLONE_FINDINGS.md)
- IAS shared-child：[`IAS_SHARED_CHILD_REPLACEMENT_FINDINGS.md`](IAS_SHARED_CHILD_REPLACEMENT_FINDINGS.md)
- JIT：[`OPTIX_JIT_REVERSE_FINDINGS.md`](OPTIX_JIT_REVERSE_FINDINGS.md)
- 机器汇总：[`rt_root_replacement_policy_summary.tsv`](rt_root_replacement_policy_summary.tsv)、
  [`rt_root_set_conflict_summary.tsv`](rt_root_set_conflict_summary.tsv)、
  [`rt_hit_replacement_summary.tsv`](rt_hit_replacement_summary.tsv)、
  [`rt_same_gas_path_summary.tsv`](rt_same_gas_path_summary.tsv)、
  [`rt_relocation_clone_summary.tsv`](rt_relocation_clone_summary.tsv)、
  [`rt_ias_shared_child_summary.tsv`](rt_ias_shared_child_summary.tsv)、
  [`rt_paired_capacity_summary.tsv`](rt_paired_capacity_summary.tsv)
