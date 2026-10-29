# RTX 5090 IAS → GAS hierarchy cache findings

日期：2026-07-12  
探针：[`experiments/ias_root_probe`](experiments/ias_root_probe)

## 结论摘要

对 `IU = K independent IAS roots -> K independent GAS children` 的 guaranteed-hit 单依赖环，发现两个精确容量边界：

```text
K <= 8   : 4 条 L1TEX 可见候选记录都只发生冷取
K = 9    : 每 trace 恰有 2 条候选记录稳态回填，约 +54 cycles
K = 17   : 每 trace 恰有 4 条候选记录稳态回填，约 +108 cycles
```

每条候选记录对应 `4 × 32 B sectors`。严格结论是：一条 IAS→GAS triangle-hit 路径在 unique−same 的 L1TEX 差分中暴露出 **四个相互可区分、参与替换的 128 B backing events**；其中两条竞争一个约 16-record 的驻留域，另两条竞争一个约 32-record 的驻留域。

后续逐地址 L2 persisting 实验发现，首冷 `IU hit` 实际有五条可归因 AS backing line。额外一条是 IAS traversable header/decode line；它有 L2 miss penalty，但不表现为第五个参与 9/17 方程的 L1TEX replacement event。因此“四个事件”不能再解释成完整路径总共只读取四条 AS line。完整修正见 [`IAS_GAS_BACKING_LINE_FINDINGS.md`](IAS_GAS_BACKING_LINE_FINDINGS.md)。

结合 direct-GAS miss/hit 与 IAS-outside-root 控制，最简解释是：

```text
16-record domain: IAS/GAS traversal-complet 类记录
32-record domain: instance/transform 与 leaf/primitive/deeper-path 类记录
```

记录的精确语义仍是强推断；公开 counter 没有地址或 RT source 标签，所以不能把四条直接命名为某四种 NVIDIA 物理 record。

## Timing 证据

配置：independent process，`max_k=64`，`only_k`，21 samples，256 measured rounds，64 warmup rounds。

| order | K | unique−same 最小值 | 稳定 mode |
|---|---:|---:|---:|
| Sattolo | 8 | 0 cycles | 0 |
| Sattolo | 9 | 54 cycles | 54 |
| Sattolo | 16 | 54 cycles | 54 |
| Sattolo | 17 | 108 cycles | 108 |
| sequential | 8 | 0 cycles | 0 |
| sequential | 9 | 54 cycles | 54 |
| sequential | 16 | 54 cycles | 54–58 |
| sequential | 17 | 108 cycles | 108；存在系统性慢样本 |

固定分配 64 个 IAS/GAS 后再只访问前 K 个，边界仍不变，排除了 `max_k=K` 导致的分配尺寸偶然性。顺序环和 Sattolo 单环边界一致，排除了单一 permutation 的偶然性。

原始 timing：

- `experiments/ias_root_probe/results/iu_hit_phys64_sattolo_k*_s21_r256.json`
- `experiments/ias_root_probe/results/iu_hit_phys64_sequential_k*_s21_r256.json`

注意：不同 handle-set 是不同 launch，独立取 unique/same 中位数会被稀疏慢样本扭曲。边界判断采用低延迟 mode、minimum 和逐样本 mode，不把异常长尾解释为 cache latency。

## 单次采集 sector 守恒

NCU 配置：

```text
--clock-control none
--cache-control none
--metrics l1tex__t_sectors_lookup_hit.sum,l1tex__t_sectors_lookup_miss.sum
1 replay pass
samples=1, rounds=1024, warmup=64
```

原始 `.ncu-rep` 已保存于：

```text
experiments/ias_root_probe/results/ncu_iu_hit_{unique,same}_phys64_k{8,9,16,17}.ncu-rep
```

提取表：[`iu_hit_sector_summary.tsv`](experiments/ias_root_probe/results/iu_hit_sector_summary.tsv)

定义：

```text
N = K × (1024 + 64) = K × 1088 trace calls
cold_unique(K) = (K−1) × 4 records × 4 sectors = 16(K−1)
```

观测与模型：

| K | total-sector unique−same | 精确模型 | 结果 |
|---:|---:|---:|---|
| 8 | 112 | `16×(8−1)` | 相等 |
| 9 | 78,392 | `16×(9−1) + 2×4×(N−9)` | 相等 |
| 16 | 139,376 | `16×(16−1) + 2×4×(N−16)` | 相等 |
| 17 | 295,920 | `16×(17−1) + 4×4×(N−17)` | 相等 |

解释：

- K=8：新增 7 个 unique handle，每个只冷取四条 128 B 候选记录。
- K=9 与 K=16：第一遍 K 个对象建立冷状态；此后每次 trace 恰有两条 4-sector event。
- K=17：第一遍后每次 trace 恰有四条 4-sector event。
- 等式覆盖 warmup 与 measured rounds 的全部 trace，而不是只拟合 timing 样本。

这是当前“两个 record domain、每条 IAS→GAS hit 暴露四条 L1TEX 可见替换记录”模型的最强证据。

## 地址干预把四条替换记录映射到 IAS/GAS

在 112 MiB L2 streaming 压力前，CUDA marker 分别只给 IAS 或 GAS output 建立 persisting preference。K=64 `IU hit` 的三进程中位数为：

| 保护范围 | cycles/trace | 相对 normal 恢复 |
|---|---:|---:|
| normal | 10593.17 | 0 |
| GAS | 9371.89 | 1221.28 |
| IAS | 8773.23 | 1819.94 |
| IAS + GAS | 7546.27 | 3046.91 |

两个单独恢复量之和为 3041.22 cycles，与联合保护只差 5.69 cycles（0.19%）。

逐 128 B IAS line 扫描与 raw byte dump 给出：

```text
IAS +0x000  traversable header/decode  # 额外 L2 line
IAS +0x700  root node / first-complet  # 16-domain candidate
IAS +0x600  instance leaf/transform    # 32-domain candidate
GAS +0x380  child root node             # 16-domain candidate
GAS +0x400  triangle primitive data     # 32-domain candidate
```

IAS `+0x600` 中的 packed child pointer 直接指向 GAS `+0x380`，所以 IAS→GAS traversal 不需要再次读取 GAS header。这样，四个 replacement event 正好分成两个 root/complet 与两个 leaf/deeper-path event；第五条 IAS header 负责 traversable decode，但没有进入所测 16/32 域方程。

## Shared-child指定victim的后续修正

后续不再只看IU aggregate方程，而是构建64个独立一实例IAS、全部共享同一个
two-triangle GAS，并在单调用点做31+1指定victim：

```text
outside-root last victim : 16-class pattern
root-gap last fill       : +27 cycles
leaf-hit last fill       : +54 cycles
leaf - gap               : +27 cycles
```

四种fill order均把gap/leaf victim移动到A30/A1/A4/A16，前一fill全0。说明unique
IAS hit路径本身有两个同步31-class阶段，即使child GAS固定仍可观察到gap一阶段、leaf
再一阶段。相反，64个static-transform wrapper共享child时全flat。

这保留“四个替换event、两个16-class与两个32-class”的整数结论，但修正过早的
一对一命名：不能简单把两个32-class event写死成“一个无上下文IAS line + 一个无
上下文GAS primitive line”。第二阶段可能由parent IAS context限定，也可能是IAS
hit路径的另一record class或multi-line bundle。逐地址L2干预仍证明IAS `+0x600`
与GAS `+0x400` backing都参与；resident tag如何组合尚不可见。完整数据见
[`IAS_SHARED_CHILD_REPLACEMENT_FINDINGS.md`](IAS_SHARED_CHILD_REPLACEMENT_FINDINGS.md)。

## 仍未证明的内容

1. `l1tex__t_sectors_lookup_*` 是 aggregate sector counter，没有地址、TTU source 或 record type 标签。
2. 四个相邻 sector 最简解释为一个 128 B cache-line event，但 counter 本身不显示四者地址连续。
3. 16/32 是本访问模式下的有效驻留域；same-launch direct-GAS forced-miss probe 已
   找到特定双-SM可见域，但尚未把四个 IAS/GAS event 分别做 ownership，也未证明
   物理组相联度、bank 数、reserved/victim slot 或一份共享的 per-TPC 容量。见
   [`RT_CACHE_OWNERSHIP_FINDINGS.md`](RT_CACHE_OWNERSHIP_FINDINGS.md)。
4. +27 cycles 是 shader-visible dependent trace residual，不是 RT Core 内部 SRAM 的裸命中延迟。
5. 地址干预已经区分 instance/transform 与 child-GAS 范围；仍需带地址或 RT source 标签的计数器才能把每次内部请求形式化归属。
