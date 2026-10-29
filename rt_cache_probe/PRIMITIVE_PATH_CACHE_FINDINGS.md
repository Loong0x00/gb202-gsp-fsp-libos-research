# RTX 5090 primitive-path L0 实测

日期：2026-07-11  
设备/软件：RTX 5090，CUDA 13.3，OptiX 9.1，Nsight Compute 2026.2.1

## 结论

在现有“一 GAS 一 triangle”基准中，hit 路径暴露出第二个、与 16-entry
root/complet 层行为不同的 RT-private residency layer：

```text
root/complet-path effective threshold    : 16 lines
hit/deeper traversal-record threshold   : 31 lines
backing transfer per record miss         : 4 × 32 B sectors = 128 B
hit/deeper replacement behavior          : 30 stable records + 1 allocation-driven streaming slot
same-GAS allocation granularity          : not per primitive/path/build-input/SBT index
```

`31` 是可观测的 unique primitive-path record 驻留数，不应直接写成物理 SRAM
一定有 31×128 B。K=32 后的替换行为也不像普通 fully-associative LRU cache。

后续同一GAS、64个空间target/128个triangle的paired replacement又排除了“每个
raw primitive、ray path、build input或SBT GAS index分配一条record”。当前
allocation identity应收紧为GAS/AS-output scoped；后续relocation clone又证明同一次
build只要output/handle身份不同就会重新占槽，详见
[`SAME_GAS_PATH_CONTENT_FINDINGS.md`](SAME_GAS_PATH_CONTENT_FINDINGS.md)。

对照之下，随后完成的16-entry root层任意refresh实验显示hit-updated circular
successor：最后命中Ai后插入X会淘汰A(i+1 mod16)，真LRU已被否定。两层一边是
确定性环后继victim，另一边是热点A穿过40项仍保留，因此不能把31-entry结果解释成
同一replacement策略的第二个容量台阶。root层详见
[`RT_ROOT_REPLACEMENT_FINDINGS.md`](RT_ROOT_REPLACEMENT_FINDINGS.md)。

## 差分方法

每次 NCU launch 的完整操作数为：

```text
N = K × (warmup 64 + measured 1024) = 1088 K
```

same-handle 控制在 K=16、17、32、64 均逐整数满足：

```text
same_hit_total_sectors - same_miss_total_sectors = 7N + 4
```

其中 `7N` 是每次进入 hit/closest-hit 路径都存在的普通 L1TEX traffic；末尾 `4`
是同一个 primitive-path backing line 的一次性冷取。因此 unique-GAS 的
primitive-path refill sectors 可写成：

```text
P(K) = unique_hit_total - unique_miss_total - 7N
```

root/complet traffic 同时存在于 hit 与 forced-miss，因而在该差分中抵消。

## 容量扫描

one-pass `L1TEX hit+miss sectors` 得到：

| K | P(K) sectors | 128B line fetches | 精确分解 |
|---:|---:|---:|---|
| 16 | 64 | 16 | `K` 次冷取 |
| 17 | 68 | 17 | `K` 次冷取 |
| 24 | 96 | 24 | `K` 次冷取 |
| 28 | 112 | 28 | `K` 次冷取 |
| 29 | 116 | 29 | `K` 次冷取 |
| 30 | 120 | 30 | `K` 次冷取 |
| 31 | 124 | 31 | `K` 次冷取；之后零 refill |
| 32 | 8,824 | 2,206 | `32 + 2×1087` |
| 33 | 13,176 | 3,294 | `33 + 3×1087` |
| 36 | 26,232 | 6,558 | `36 + 6×1087` |
| 40 | 43,640 | 10,910 | `40 + 10×1087` |
| 48 | 78,456 | 19,614 | `48 + 18×1087` |
| 64 | 148,088 | 37,022 | `64 + 34×1087` |

因此：

```text
K <= 31 : line_fetches = K
K >= 32 : line_fetches = K + (K - 30) × 1087
```

K=31 的 31 条 unique line 全部驻留；K=32 时每个后续完整环只有2条重取，
而不是32条全 miss。继续增加K后，每环重取数严格为 `K-30`。

这等价于如下**可观测行为**：30条记录保持稳定，剩余 `K-30` 条围绕一个
replaceable/victim位置循环；任一时刻总共约31条可驻留。它与 fully-associative
LRU 在 `C+1` 循环时全 miss 的行为不同，更像 streaming cache 的固定/旁路式
分配。但计数器看不到 tag/victim ID，不能据此宣布真实 replacement 电路。

## Prime-probe 对 replacement 的额外限制

新增 `prime-hit` 模式每轮先命中 A，再命中 K-1 个其他独立 GAS，最后只计时 A。
K=24--40 的低噪声下界均为：

```text
unique A probe = 4516 cycles
same-handle    = 4489 cycles
差值           = 27 cycles
```

这27 cycles是K>16后共同存在的root/complet miss；K=31->32没有再增加primitive
miss penalty。也就是说每轮最先访问/refresh的A在K=40仍保留其primitive-path
record，而sector扫描中持续miss的是其余overflow成员。

这直接排除了普通fully-associative LRU：若容量31且顺序为A后31个不同record，
A应在K=32被淘汰。它与“先占据的约30条稳定保留，overflow集合在有限victim位置
循环”的解释一致。当时还需显式选择overflow成员；下节的31+1逐victim实验完成了
这一步，并把行为进一步收紧为allocation-driven streaming slot。

## 指定victim：第31个fill进入streaming slot

后续新增31+1逐victim实验，序列为：

```text
hit-scrub 32个disjoint GAS，重复4次
hit-fill A0..A30                 # 31条candidate record
test:    hit X=A31
control: 再hit最后一个resident  # 等长、但不分配新record
probe one victim
```

root域在这组31-record序列中必然thrash。为避免把root pointer平台误认成hit/deeper
victim，正式判读同时使用：

1. test/control等长差；
2. 相邻逻辑victim局部差；
3. hit-probe与forced-miss-probe四差分；
4. 可选256 KiB `L1::evict_last` trash，把被淘汰record的backing代价放大。

sequential fill的32个独立victim进程中，A30相对A29精确多27 cycles；X在control
分支本来未分配，故呈反向差。contiguous/separate/padded/permuted四种layout的
高样本边界复现均为：

```text
A29 test-control = -12 cycles
A30 test-control = +15 cycles
A30 - A29        = +27 cycles
X31 test-control = -66 cycles
```

L1-trash四差分中，普通victim A0/A10/A15/A16/A28/A29聚在约`+152..+156`，A30为
`+626.4`，即额外约472 cycles；X31因control-cold方向相反。其他layout上trash
放大倍数较小，但A30相对A29仍多约23--32 cycles，符合`L1::evict_last`是hint而非
形式化flush。

### victim跟随最后fill，而不是固定地址

改变31项fill order后：

| fill order | 最后fill | 前一fill | 实测victim | 无trash `last-prev` |
|---|---:|---:|---:|---:|
| sequential | A30 | A29 | A30 | +27.0 |
| reverse (`A0,A30..A1`) | A1 | A2 | A1 | +27.0 |
| deterministic permuted | A4 | A14 | A4 | +27.0 |
| deterministic Sattolo | A16 | A24 | A16 | +27.0 |

所以victim跟随第31个**分配位置**，不是A30地址特例。

填满后额外hit A0、A15、A29，再插入X，victim仍是最后fill的A30；被refresh的稳定
项没有进入streaming slot。故当前最小行为模型是：

> 前30条首次分配的record进入稳定位置；第31条进入一个allocation-driven
> streaming/replacement slot；以后每个新record替换该slot，普通hit不移动它。

这逐项解释既有精确公式。K项首环各冷取一次；之后前30项稳定，剩余`K-30`项依次
争用一个slot，所以每个后续完整环恰好重取`K-30`条：

```text
line_fetches = K + (K - 30) × 1087,  K >= 32
```

“30 stable + 1 slot”仍是可观测组织，不证明版图上有30个锁定ways加一块独立RAM；
bypass、allocate-on-return或融合的leaf/primitive record状态机都可产生相同行为。

## 同一 GAS 多路径：不是 per-primitive allocation

独立结构probe在一个9,344 B GAS内放置64个空间tile、128个triangle，并分别测
`outside_root`、`root_gap`和验证primitive index的`leaf_hit`。它把上面的31+1序列
改成同一GAS的targets：32个scrub、31个fill、X31 insert、等长control和指定victim。

为避免不同模板callsite和跨launch产生整数周期伪差，正式版本在单launch的同一
动态循环/计时调用点执行AB/BA paired probe。结果为：

- sequential完整32-victim扫描中，3条路径、两种pair order的192个分组median全部
  精确为0 cycles；
- 加256 KiB `L1::evict_last`后，四种fill order的`last-prev`最大绝对值仅5.25
  cycles，无固定符号，也不跟随最后fill；
- 对照的distinct-GAS实验是固定+27 cycles，并可被同一L1 hint额外放大约472
  cycles。

同一GAS随后又改成64个独立triangle build input和64个SBT GAS index；primitive
与SBT correctness逐target通过，而32-victim×3-path plain paired median仍全部为0。
带L1 trash的sequential/reverse完整victim map也保持`|balanced median|<=4.5`
cycles，异常选点在96样本独立复测中消失。因此31-record层的tag/allocation identity
至少比primitive/path/build-input/SBT index更粗，当前最符合traversable/GAS对象、
output/header descriptor或融合记录。机器汇总见
[`rt_same_gas_path_summary.tsv`](rt_same_gas_path_summary.tsv)。

## Relocation clone：身份随GAS output/handle改变

为排除“64个独立build的opaque内容不同”这一解释，把一次one-triangle GAS build的
2,560 B output复制到63个新target，并逐个调用documented `optixAccelRelocate()`。
64个clone拓扑和build来源相同，只改变合法的output/handle relocation身份。

单调用点paired结果重新精确出现hit-only victim：

| fill order | last | previous | last hit-only | previous hit-only |
|---|---:|---:|---:|---:|
| sequential | A30 | A29 | +27 | 0 |
| reverse | A1 | A2 | +27 | 0 |
| permuted | A4 | A14 | +27 | 0 |
| Sattolo | A16 | A24 | +27 | 0 |

L1 trash把sequential hit-only `last-prev`放大到+501.75 cycles。因此独立build不是
31-record allocation的必要条件；relocated GAS output/handle身份不同已经足够。
严格说API让handle、output VA与relocation fixup共变，不能再细分硬件tag取了哪一位。
详见[`RT_RELOCATION_CLONE_FINDINGS.md`](RT_RELOCATION_CLONE_FINDINGS.md)。

## IAS shared-child：两个同步31-class阶段

64个独立一实例IAS全部指向同一个two-triangle GAS后，中央gap与leaf把层级进一步
拆开：第31个IAS fill在gap路径为+27，leaf为+54，所以`leaf-gap`再+27；前一fill
全部为0。sequential/reverse/permuted/Sattolo四种顺序都精确复现。

因此direct GAS只暴露一个31-record阶段，但IAS hit路径至少有两个同步31-class
阶段。static-transform wrapper共享child时完全flat，说明这不是generic wrapper
handle效应，而与built IAS/GAS AS-output context相关。两个阶段究竟是两套bank、
一个multi-line bundle，还是parent-qualified child record，timing尚不能区分。详见
[`IAS_SHARED_CHILD_REPLACEMENT_FINDINGS.md`](IAS_SHARED_CHILD_REPLACEMENT_FINDINGS.md)。

原始结果：

- [`agent_optix/minimal/results/hit_replacement_equal_control_independent_v1`](agent_optix/minimal/results/hit_replacement_equal_control_independent_v1)
- [`agent_optix/minimal/results/hit_replacement_fill_order_v1`](agent_optix/minimal/results/hit_replacement_fill_order_v1)
- [`agent_optix/minimal/results/hit_replacement_refresh_v1`](agent_optix/minimal/results/hit_replacement_refresh_v1)
- [`agent_optix/minimal/results/hit_replacement_fourway_trash_layout_v1`](agent_optix/minimal/results/hit_replacement_fourway_trash_layout_v1)
- 机器汇总：[`rt_hit_replacement_summary.tsv`](rt_hit_replacement_summary.tsv)

原始结果：

- [`prime_hit_unique_k40.json`](agent_optix/minimal/results/prime_hit_unique_k40.json)
- [`prime_hit_same_k40.json`](agent_optix/minimal/results/prime_hit_same_k40.json)

## 地址与访问顺序反证

K=32 在以下四组条件下逐整数得到相同的 `P=8,824 sectors = 2,206 lines`：

- contiguous + Sattolo；
- padded allocation + Sattolo；
- physically permuted allocation + Sattolo；
- separate allocation + reverse order。

所以31/32边界不是2560 B连续步长、allocator低位或单一访问顺序造成的普通
set-conflict伪影。

## 和 root/complet 层为什么是两块行为

K=16 的 unique-vs-same hit 差值为：

```text
120 sectors = 15 × 8
```

即另外15个GAS各自带来两条冷线：4 sectors 的root/complet line，加4 sectors的
hit-only primitive-path line。

K=17 的差值为：

```text
74,044 sectors = 73,980 + 64
```

- `73,980 = 4 × (18,496 - 1)`：16-entry root/complet层溢出后，几乎每次trace
  都重取root line；
- `64 = 4 × 16`：另外16条primitive-path line只冷取一次，之后仍然驻留。

因此两种record不是同一个16-entry bank的共同流量；hit-only layer在K=17仍完全
容纳其17条record。

## SRAM data-stage 复核

one-pass `l1tex__sram_cycles_array_1_cmd_read.sum` 也逐整数符合“两条line”的解释：

```text
K=16: unique_hit - same_hit = 30
      = 15 root line reads + 15 primitive line reads

K=17: unique_hit - same_hit = 18,511
      = 18,495 root line reads + 16 primitive cold reads

K=32: unique_hit - same_hit = 37,020
      = 34,815 root line reads + 2,205 extra primitive reads
```

K=32 的 primitive 部分 `2,205 = 2,206 unique fetches - 1 same-handle fetch`。
也就是说每个4-sector refill对应一次 tagged SRAM1 read-active cycle；普通
`l1tex__t_requests` 计数仍不增加。K=32 的 unique-hit 与 same-hit 都逐整数为
`1,441,803 requests`（该request metric需要4-pass，所以只作source-path辅助）；
RT hit-path refills与root refills一样绕过普通LSU/TEX T-request计数点。

## 当前允许的命名

高置信度：

> RTX 5090 上存在一个hit/deeper traversal residency layer，可完整驻留31条
> distinct-AS-output/context-scoped backing record；第32条开始出现确定性、非LRU式的
> streaming refill。同一GAS内64个不同target/build input/SBT index不会各自分配
> 一条该record。

仍需实验才能升级为：

- raw triangle primitive cache：同一GAS多target/64-build-input已反证
  per-primitive与per-geometry allocation；relocation clone证明tag随GAS
  output/handle身份变化；static-transform共享child为null，当前更可能是AS-output
  descriptor/backing record而非generic traversable handle；
- 31×128B物理data RAM：内部可能压缩，且可能有保留/victim slot；
- 每SM私有：direct-GAS forced-miss/root 状态已显示双-SM可见域，但尚未对31-record
  hit-specific event 单独做 ownership，因此不能把 primitive-path 层直接沿用同一域；
- 通用primitive容量：当前只测一三角形GAS，不含cluster/LSS/OMM。

static-transform共享child wrapper已经为null；下一步应使用IAS/shared-child继续区分
instance AS-output与child GAS record。31-record hit/deeper域的ownership也尚未单独
完成。它已经不能命名为raw triangle cache。
