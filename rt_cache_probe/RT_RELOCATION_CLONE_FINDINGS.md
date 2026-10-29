# RTX 5090 RT relocation clone 驻留身份

日期：2026-07-12  
设备/软件：RTX 5090，CUDA 13.3，OptiX 9.1

## 结论

用一次GAS build的output制造64个documented relocation clone后，16-entry root域和
31-record hit/deeper域都把每个clone视为独立traversable identity。对one-triangle
GAS，hit-only replacement精确复现原独立build结果：

```text
same GAS handle，64 targets / 64 build inputs : 31-record replacement = flat
64 relocation clones，same topology/content  : last-fill victim = +27 cycles
relocation clones + L1 trash                  : hit-only last-prev = +501.75 cycles
```

因此31-record层不是按primitive、ray path、build input或SBT GAS index分配；它随
GAS output/handle relocation身份改变。当前最强命名是：

> **AS-output-address-scoped hit/deeper residency record**。

本机relocated GAS handle数值均为`targetAccel + 0xC`。但公开API让output VA、handle
和relocation fixup同时变化，仍不能声称硬件tag逐比特只取某一个字段。

一个重要反证是：64个不同`OptixStaticTransform` handle全部指向同一个child GAS
时没有复现任何16/31 victim。因此“任意traversable handle不同”并不足够；当前
信号更具体地跟build/relocate产生的AS output record走。

## Clone构造

扩展后的
[`experiments/rt_structure_probe`](experiments/rt_structure_probe)支持：

```text
--handle-layout relocated
--geometry-layout single-triangle | tiles
```

流程为：

1. 只build一次source GAS；
2. 调用`optixAccelGetRelocationInfo()`并验证本context兼容；
3. 分配63个同尺寸、满足OptiX alignment的target output；
4. 把source output逐字节device-to-device复制到每个target；
5. 对每个target调用`optixAccelRelocate()`，取得新的合法handle；
6. 所有逻辑target使用相同ray、相同primitive和相同SBT record，只改变clone handle。

`optixAccelRelocate()`可能在target内写入地址相关fixup，所以严谨说法是“复制前字节
同源、拓扑和build完全相同”，不是断言relocate后的opaque bytes仍逐字节相等。

correctness smoke验证64个output VA和64个handle均唯一；one-triangle source output为
2,560 B，64份总accounted VRAM约195 KiB。所有hit逐次验证primitive index 0。

## 单调用点 paired replacement

序列与31+1实验相同：

```text
scrub clone handles 32..63，重复4次
fill A0..A30
insert X=A31 / equal-length control=re-hit last fill
probe specified victim
```

每个sample在同一动态循环/计时调用点做AB/BA pair；`outside_root`扣除root域，
`leaf_hit - outside_root`作为hit-only局部差。

### sequential完整victim map

one-triangle clone的plain结果呈整数分解：

| victim | outside_root insert-control | leaf_hit insert-control | hit-only |
|---:|---:|---:|---:|
| A15 | +27 | +27 | 0 |
| A29 | 0 | 0 | 0 |
| A30 | 0 | +27 | +27 |
| X31 | -27 | -54 | -27 |

A15与X31的outside项属于16-entry root域；A30与X31额外的leaf-minus-outside项属于
31-record hit/deeper域。两个域都以27-cycle单位相加，且single-callsite的两种pair
order逐项相同。

### victim随fill order移动

| order | last | previous | last hit-only | previous hit-only | last-prev |
|---|---:|---:|---:|---:|---:|
| sequential | A30 | A29 | +27 | 0 | +27 |
| reverse | A1 | A2 | +27 | 0 | +27 |
| deterministic permuted | A4 | A14 | +27 | 0 | +27 |
| deterministic Sattolo | A16 | A24 | +27 | 0 | +27 |

这与独立build的一三角形GAS完全一致，证明victim跟随第31个relocated traversable
分配位置，而不是builder输出差异或某个固定VA的偶然值。

### 普通L1 backing放大

sequential加256 KiB同线程`L1::evict_last`后：

```text
A30 hit-minus-outside = +498.00 cycles
A29 hit-minus-outside =   -3.75 cycles
last-prev             = +501.75 cycles
```

这与先前独立build实验约+472-cycle的额外放大方向和量级一致，说明relocation clone
触发的不是纯shader/control-flow差异，而是同一hit/deeper record及其ordinary
L1/L2 backing路径。

## 128-triangle clone对照

同一机制也在9,344 B、128-triangle tiles GAS上重新触发27-cycle整数事件，但不同
path会组合多个root/interior/hit事件；例如sequential中outside A15为+27，gap/hit
可出现54/81的组合。one-triangle版本提供了更干净的root与hit差分，故用于正式
allocation结论；tiles版本只作结构复杂度对照。

## Static-transform共享child反证

另建64个identity `OptixStaticTransform`，全部指向同一个one-triangle GAS。每条
transform storage按128 B stride满足alignment，本机handle为`storage + 0x6`。这组
wrapper handle彼此不同，但child GAS output与handle完全相同。

结果：

- plain 32-victim×3-path paired map全部为0；
- 256 KiB L1 trash后，各path balanced median约在±0--3.75 cycles，sequential
  hit-only `last-prev`仅+2.0 cycles；
- K=1..64 unique-wrapper vs same-wrapper扫描，outside/gap/hit的所有median差均精确0。

所以static-transform wrapper本身没有在这两个已测域中分配可见的独立record；命中
仍由共享child GAS的AS-output record决定。这个null不排除transform走普通L1、其他
专用状态或在更复杂transform下出现不同事件，只排除“所有traversable handle统一
进入同一16/31 tag array”的简单模型。

## 允许与不允许的推断

当前允许：

- 16-entry root域和31-record hit域都按relocated GAS/AS-output identity区分；
- 31-record hit域不是per-primitive、per-path、per-build-input或per-SBT-index；
- 独立build不是阈值出现的必要条件；同一次build的relocation clone已足够；
- 软件优化的首要局部性键应是GAS/AS-output identity，而非同一GAS内的primitive号
  或外层static-transform handle。

当前不允许：

- 宣布tag只等于64-bit公开handle或只等于output VA；两者在本机共变；
- 宣布relocation后的opaque AS bytes逐字节相同；API可能执行fixup；
- 把27 cycles命名为固定DRAM/L2 latency；它是resident record掉到hot backing的局部代价；
- 从单线程结果推出并发pending-request replacement。

原始数据：

- [`plain_single_triangle_sequential.csv`](experiments/rt_structure_probe/results/replacement_paired_relocated_v1/plain_single_triangle_sequential.csv)
- [`replacement_paired_relocated_order_v1`](experiments/rt_structure_probe/results/replacement_paired_relocated_order_v1)
- [`plain_sequential.csv`](experiments/rt_structure_probe/results/replacement_paired_relocated_v1/plain_sequential.csv)（128-triangle tiles）
- [`replacement_paired_static_transform_v1`](experiments/rt_structure_probe/results/replacement_paired_static_transform_v1)
- [`static_transform_k64_v1`](experiments/rt_structure_probe/results/static_transform_k64_v1)
- 机器汇总：[`rt_relocation_clone_summary.tsv`](rt_relocation_clone_summary.tsv)
