# RTX 5090 IAS shared-child replacement 分解

日期：2026-07-12  
设备/软件：RTX 5090，CUDA 13.3，OptiX 9.1

## 结论

64个独立的一实例IAS全部指向同一个one-/two-triangle GAS时，指定victim序列同时
暴露出：

```text
IAS outside-root stage        : 16-entry class，+27 cycles
IAS instance/child-path stage : 31-record class，+27 cycles
leaf-only additional stage    : 31-record class，再+27 cycles
shared child hit total        : 最后fill为+54 cycles
```

double-triangle中央gap控制把后两项逐27 cycles分离；四种fill order中，两项都随
第31个IAS allocation位置移动。相反，64个identity static-transform wrapper共享同一
child GAS时，plain、L1 trash和K=1..64扫描全部为null。

最强硬件含义是：已测16/31域面向**built AS output records/context**，不是面向所有
generic traversable handle。IAS hit路径至少有两个软件可分的31-class阶段；它们可能
是两个独立record class、一个多line bundle，或parent-context-qualified child阶段，
当前timing不能把三种物理实现区分开。

## 构造

扩展后的
[`experiments/rt_structure_probe`](experiments/rt_structure_probe)新增：

```text
--handle-layout ias-shared-child
--geometry-layout single-triangle | double-triangle
```

构造细节：

- source GAS只build一次；
- 64个identity `OptixInstance`全部引用该GAS；
- 每个instance单独build成一个一实例IAS，因此有64个独立IAS output/handle；
- IAS output均为2,048 B，本机handle=`output + 0x4`；
- 所有逻辑target使用同一ray、primitive 0与SBT record 0，只改变IAS handle；
- pipeline使用single-level-instancing graph，correctness validation逐trace通过。

对照的`static-transforms`同样有64个不同wrapper handle并共享child GAS，但wrapper
不是builder产生的AS output。

## 31+1 paired序列

与direct-GAS实验完全相同：

```text
scrub wrappers 32..63，重复4次
fill A0..A30
insert X31 / equal-length control=re-hit last fill
probe specified victim
```

每个sample在同一动态循环/计时调用点做control→insert和insert→control交替pair。
因此以下整数差不是跨launch或模板callsite偏置。

## Single-triangle初步分解

sequential完整32-victim map得到：

| path | selected victim | insert-control |
|---|---:|---:|
| outside_root | A15 | +27 |
| root_gap | A15 | +27 |
| leaf_hit | A30 | +54 |

single-triangle的gap射线没有进入child AABB，所以它与outside同构，不能扣除
instance/child-path阶段。这促成double-triangle控制。

## Double-triangle gap控制

最小GAS只含左右两个三角形，中央gap位于总体GAS/instance AABB内但不命中primitive：

| victim | outside_root | root_gap | leaf_hit | leaf−gap |
|---:|---:|---:|---:|---:|
| A15 | +27 | 0 | 0 | 0 |
| A29 | 0 | 0 | 0 | 0 |
| A30 | 0 | +27 | +54 | +27 |
| X31 | -27 | -54 | -54 | 0 |

判读：

- outside A15是只访问IAS起始root时的16-entry successor victim；
- gap A30进入instance/child-path但不命中primitive，暴露一个31-class +27阶段；
- leaf A30在gap之上再多+27，暴露leaf-only第二阶段；
- 多项在X31处会按replacement状态合成，故正式容量判据使用last与previous局部差。

### victim随fill order移动

| order | last | previous | last gap | last leaf | last leaf−gap | previous leaf−gap |
|---|---:|---:|---:|---:|---:|---:|
| sequential | A30 | A29 | +27 | +54 | +27 | 0 |
| reverse | A1 | A2 | +27 | +54 | +27 | 0 |
| deterministic permuted | A4 | A14 | +27 | +54 | +27 | 0 |
| deterministic Sattolo | A16 | A24 | +27 | +54 | +27 | 0 |

所以两个31-class阶段都与第31个IAS allocation同步，不是A30地址或单一BVH布局
偶然性。

### L1 trash

sequential加256 KiB `L1::evict_last`后，A30的`leaf-gap=+51.25`，A29为-0.75，
局部`last-prev=+52.0` cycles。放大弱于direct-GAS relocation clone的约+502，说明
该hint对IAS两阶段backing的作用不同；它仍保留selected-victim方向，不作为物理flush
或line地址证明。

## 与IU四事件方程的关系

此前`K independent IAS -> K independent GAS`的L1TEX整数方程显示每条hit路径有
两个16-class与两个32-class 128 B replacement event。shared-child指定victim现在
给出互补证据：即使child GAS固定，unique IAS的gap与leaf仍各增加一个31-class
27-cycle阶段。

这意味着不能把IU的两个32-class事件过早写死成“一个IAS line + 一个无上下文的
GAS primitive line”。第二阶段可能由parent IAS context限定，也可能是IAS hit路径的
另一record class。现有`IAS +0x600`与`GAS +0x400`地址干预仍证明两处backing都参与，
但内部resident tag/bundle如何组合尚未形式化可见。

## Static-transform反证

64个identity static transform共享同一child GAS时：

- plain 32-victim×3-path paired map全部为0；
- L1-trash完整map约±0--3.75 cycles；
- K=1..64 unique-wrapper与same-wrapper的outside/gap/hit median差逐点全0。

所以“wrapper handle不同”不是充分条件；builder/relocator产生的AS output records才是
当前16/31域的强相关对象。static transform可能走普通L1、另一专用路径或透明
forward，null不能外推成所有transform都无缓存成本。

## 原始数据

- [`plain_double_sequential.csv`](experiments/rt_structure_probe/results/replacement_paired_ias_shared_v1/plain_double_sequential.csv)
- [`replacement_paired_ias_shared_double_order_v1`](experiments/rt_structure_probe/results/replacement_paired_ias_shared_double_order_v1)
- [`replacement_paired_ias_shared_order_v1`](experiments/rt_structure_probe/results/replacement_paired_ias_shared_order_v1)（single-triangle）
- [`replacement_paired_static_transform_v1`](experiments/rt_structure_probe/results/replacement_paired_static_transform_v1)
- 机器汇总：[`rt_ias_shared_child_summary.tsv`](rt_ias_shared_child_summary.tsv)
