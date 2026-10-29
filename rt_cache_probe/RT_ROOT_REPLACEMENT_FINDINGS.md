# RTX 5090 RT root-residency replacement 与集合冲突实验

更新：2026-07-12  
设备：RTX 5090（GB202，CC 12.0）  
基准：`agent_optix/minimal` replacement / eviction-set modes

## 结论

direct-GAS forced-miss 暴露的16-entry root/first-complet residency layer，在当前
单线程串行路径上表现为：

```text
effective capacity : 16 entries
address mapping    : 所测64-GAS地址池中等效全相联；未找到E<16 eviction set
victim rule        : hit-updated circular successor
miss penalty       : 27.0 raygen-observed cycles
```

设填充顺序为 `A0,A1,...,A15`，插入新项为X。填满后 next-victim 指向A0；最后一次
命中Ai后，下一次插入稳定淘汰：

```text
victim = A[(i + 1) mod 16]
```

这**不是真LRU**。早先的prefix实验依次refresh `A0..A(N-1)`，最后命中恰好是
`A(N-1)`，所以 successor 规则也预测victim N，偶然与LRU逐项相同。任意refresh
顺序已经把两者直接分开。

“circular successor”是可观测语义，不是版图命名。物理实现仍可能是hit-updated
round-robin/clock pointer、按特定way枚举的PLRU，或产生同一串行行为的其他状态机。

## 基线方法

一次构建64个物理独立 one-triangle GAS。每个 victim 单独运行：

```text
TRACE 32个disjoint scrub roots，重复P次
TRACE A0..A15
TRACE refresh_order[]
TRACE X
time TRACE victim
```

`replacement_rotation` 把candidate与scrub集合在64-GAS池中循环平移。正式任意顺序
矩阵使用 `P=4`；`P=1/2/4` 收敛实验表明，一次scrub有时仍保留probe相关状态，四次
后难例收敛。每次仍只有一个active raygen thread。

另运行完全相同但不插入X的控制。`with_X−no_X` 对A0..A15有一个与代码路径有关的
公共差；真正victim在其相邻逻辑项局部基线之上精确再多27 cycles。X自身在no-X
控制中是冷项，方向相反，符合预期。

## Prefix为何误判成LRU

原26个layout/rotation汇总点本身仍然有效：

| refresh prefix N | successor预测 | LRU预测 | 实测victim | penalty |
|---:|---:|---:|---:|---:|
| 0 | 0 | 0 | 0 | 27.0 |
| 1 | 1 | 1 | 1 | 27.0 |
| 2 | 2 | 2 | 2 | 27.0 |
| 8 | 8 | 8 | 8 | 27.0 |
| 15 | 15 | 15 | 15 | 27.0 |
| 16 | 0 | 0 | 0 | 27.0 |

它们证明hit更新replacement状态、FIFO/random不符，却不能单独区分LRU与successor
pointer。机器汇总：[`rt_root_replacement_summary.tsv`](rt_root_replacement_summary.tsv)。

## 决定性反证一：单独refresh每一项

固定 contiguous/rotation0，分别只refresh一个Ai。16/16文件均得到唯一victim：

```text
refresh A0  -> victim A1
refresh A1  -> victim A2
...
refresh A14 -> victim A15
refresh A15 -> victim A0
```

每项惩罚都恰为27.0 cycles。只refresh A2时，真LRU应仍淘汰最老的A0，实测却淘汰
A3；因此真LRU被直接否定。

原始结果：
[`agent_optix/minimal/results/replacement_arbitrary_v1`](agent_optix/minimal/results/replacement_arbitrary_v1)。

## 决定性反证二：任意与重复refresh顺序

以下六条序列跨 contiguous/separate/padded/permuted 四种layout，分别使用rotation
`0/7/31/47`。24/24个插入/不插入X控制点的预测victim局部差分均精确为+27.0 cycles：

| refresh order | 真LRU victim | successor victim | 实测 |
|---|---:|---:|---:|
| `A0,A3` | A1 | A4 | A4 |
| `A1,A0` | A2 | A1 | A1 |
| `A1,A2` | A0 | A3 | A3 |
| `A15,A7` | A0 | A8 | A8 |
| `A2,A2` | A0 | A3 | A3 |
| `A15,A14,...,A0` | A15 | A1 | A1 |

重复A2仍指向A3，完整逆序refresh全部16项后仍由“最后命中A0”决定A1，而不是由
完整LRU栈顺序决定A15。

原始结果：
[`agent_optix/minimal/results/replacement_insert_control_matrix_v1`](agent_optix/minimal/results/replacement_insert_control_matrix_v1)。

## 任意地址 eviction-set 搜索

新增 `evict-set` 模式。每轮从64-GAS池中选择一个victim、1--16个显式candidate，
再自动选择32个与二者不重叠的scrub roots：

```text
SCRUB 32 disjoint roots
TRACE victim
TRACE candidate prefix E
time TRACE victim
```

第一轮共192个独立进程：

- 4种allocation layout；
- 6个victim：`0,7,16,31,47,63`；
- 8个与63互质的地址步长：`1,2,5,11,22,31,47,62`；
- 每个文件扫描 `E=0..16`。

结果：192/192的最大相邻台阶都只在E=16出现，且全部恰为+27.0 cycles；没有任何
E<16提前淘汰。

随后对四个物理/逻辑差异很大的16项eviction set逐一删除每个成员，得到64个不同
15项子集。64/64均不淘汰victim；E=1..15平台spread全部为0.0 cycles。它们只保留
已知的E=0→1发射间隔+17 cycles，没有+27 refill台阶。

因此当前允许写：

> 在所测64-address GAS root池、四种分配布局与地址排列中，该层表现为16-entry
> effective fully-associative capacity；未发现小于16项的冲突集合。

不能把有限地址池升级成“所有GB202地址、所有record类型在物理上一定全相联”。

原始结果：

- [`agent_optix/minimal/results/evict_set_screen_v1`](agent_optix/minimal/results/evict_set_screen_v1)
- [`agent_optix/minimal/results/evict_set_reduction_v1`](agent_optix/minimal/results/evict_set_reduction_v1)
- 汇总：[`rt_root_set_conflict_summary.tsv`](rt_root_set_conflict_summary.tsv)

## 和其他层、ownership的关系

本结论只属于16-entry root/first-complet层。31-record hit/deeper-path层中热点A穿过
K40仍可保留，replacement明显不同，不能沿用successor规则。

paired-SM联合容量显示伙伴P的远端A会参与Q所见的同一16-entry effective budget；
这与本报告的容量一致，但没有证明两个SM共享同一物理pointer或data array。

## 尚未证明

- successor状态机的物理电路名称、way编号和bit布局；
- 并发rays、pending request grouping、allocate-on-return时是否保持同一规则；
- primitive/instance/OMM/cluster层是否采用同样策略；
- 16×128B backing footprint是否等于内部物理data RAM payload。

## 工程含义

单纯“最近访问热点就按LRU保护整条recency栈”的优化模型是错的。当前串行路径上，
最后命中Ai会保护Ai，却把下一淘汰位置确定性移到Ai的环后继。对root工作集做排序时，
访问顺序不仅影响新旧程度，也会移动明确的victim pointer；应避免把关键root放在
热点最后访问项的后继位置。应用仍不能直接控制物理way或SM/TPC placement。

## 安全边界

- 单active raygen thread；全部序列严格串行；
- replacement每victim按 `32P + 19 + N` 的保守trace上界计数；
- eviction-set launch同样受2,000,000 traces硬上限约束；
- host watchdog默认2 s、硬上限10 s，超时只退出probe进程；
- 显式VRAM不超过64 MiB和启动时free VRAM的1%；
- 未修改时钟、功耗、驱动、固件、ECC或持久化设置。
