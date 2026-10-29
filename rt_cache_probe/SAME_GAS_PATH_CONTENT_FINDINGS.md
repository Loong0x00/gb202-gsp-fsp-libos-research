# RTX 5090 同一 GAS 多路径驻留判别

日期：2026-07-12  
设备/软件：RTX 5090，CUDA 13.3，OptiX 9.1

## 结论

把此前 distinct-GAS 的 `31+1` replacement 序列原样移到一个固定 GAS 内，令
64 条射线分别走不同空间 tile、不同内部路径和不同 triangle primitive，未观察到
任何路径各自占用 31-record hit/deeper 驻留域的证据：

```text
distinct GAS，one triangle each : 第31个fill随顺序移动，last-prev = +27 cycles
same GAS，1 build input         : 32 victims × 3 paths的paired median全部为0 cycles
same GAS，64 build inputs       : 32 victims × 3 paths的paired median仍全部为0 cycles
same GAS + 256 KiB L1 trash     : 完整victim map与独立repeat保持约±0--4.5 cycles，
                                  不随最后fill稳定移动
```

因此可以排除“每个 raw primitive 或每条 ray path 都分配一个 31-record 槽”的简单
模型。当前最窄而不过度解释的命名应是：

> **31-record AS-output-address-scoped hit/deeper traversal residency layer**。

这里的 allocation identity 至少比 primitive/path、build input和SBT GAS index都
粗。后续64个relocation clone已精确重新触发31+1边界，证明它随GAS output/handle
身份改变；64个static-transform wrapper共享同一child GAS时仍为null，说明任意
traversable handle不同并不足够。公开接口仍不能把GAS handle、output地址和内部
descriptor tag拆开。
见[`RT_RELOCATION_CLONE_FINDINGS.md`](RT_RELOCATION_CLONE_FINDINGS.md)。

## 固定结构

独立 probe 位于
[`experiments/rt_structure_probe`](experiments/rt_structure_probe)：

- 一个非压缩 GAS，8×8 个空间分离 tile；
- 每个 tile 两个三角形，中间留 gap，共64 targets / 128 triangles；
- GAS output为9,344 B；分别构建1-input与64-input版本；
- 64-input版本中每个target有独立triangle build input和SBT GAS index，使用
  `primitiveIndexOffset=2*target`维持全局primitive验证；
- `outside_root`：沿 `-Z` miss；
- `root_gap`：沿 `+Z` 穿过输入几何中央空隙；
- `leaf_hit`：命中 target左三角形，并逐次验证 primitive index `2*target`；
- 正式路径只调用`optixTraverse()`，不调用`optixInvoke()`。

早期 `K=1..64` 扫描始终probe target0，三条路径的中位数分别保持约
2594/2703/3125 cycles。这个null只说明热点A保留，无法排除既有的
`30 stable + 1 streaming slot`，所以又加入指定victim replacement。

## 指定 victim 序列

每个被测 victim 使用：

```text
scrub targets 32..63，重复4次
fill 31个targets A0..A30，顺序可选
insert : trace X=A31
control: re-trace最后一个fill                 # 等长，不引入新target
probe  : 只计时指定victim
```

fill order与 distinct-GAS 实验完全一致：

| order | 最后fill | 前一fill |
|---|---:|---:|
| sequential | A30 | A29 |
| reverse | A1 | A2 |
| deterministic permuted | A4 | A14 |
| deterministic Sattolo | A16 | A24 |

### 为什么必须同一动态调用点

第一版把 insert/control 放在不同模板分支和不同 launch。它产生过27、47或48
cycles的整数量级偏置，但偏置不随victim移动。把两者改成单 launch、同一动态循环、
同一计时调用点后，这些差异完全消失。这是编译布局/launch历史伪差，不能当作
RT cache事件。

正式 paired 记录对每个样本交替执行：

```text
sample even: control -> insert
sample odd : insert  -> control
```

CSV同时保存`cycles`、`control_cycles`和`pair_order`。判读先分别取两种顺序的
`insert-control` median，再取两者平均，从而抵消固定先后效应。

## 结果

### 无普通 L1 扰动

sequential完整扫描覆盖32个victim、3条路径、每种pair order各32个样本。共
`32 × 3 × 2 = 192` 个分组，其 `median(insert-control)` 全部精确为0 cycles。
最后fill A30与前一fill A29也均为0。

### 256 KiB `L1::evict_last` 敏感性检查

该hint在 distinct-GAS 实验中曾把被选victim相对普通victim额外放大约472 cycles。
同一GAS的四种fill order结果如下；表中数值是平衡后的
`last - previous`：

| order | outside_root | root_gap | leaf_hit |
|---|---:|---:|---:|
| sequential | +3.25 | -2.00 | 0.00 |
| reverse | -2.00 | +1.50 | +5.25 |
| permuted | 0.00 | -0.25 | -0.25 |
| Sattolo | +0.75 | +0.75 | 0.00 |

最大绝对值只有5.25 cycles，无统一符号，也不在四种顺序下跟随最后fill。与
distinct-GAS的固定+27 cycles以及L1放大后的约+472 cycles相比，这是null结果。

### 64个独立 build input / SBT GAS index

把同一个GAS改成64个triangle build input，每个target保留两个triangle和独立SBT
GAS index。correctness smoke逐次验证primitive与SBT record，GAS output大小仍为
9,344 B。随后重复完全相同的paired replacement：

- 无L1 trash的32-victim×3-path完整扫描，192个order分组median仍全部为0；
- 带L1 trash的1-input/64-input、sequential/reverse完整32-victim hit map，所有
  balanced median的绝对值均不超过4.5 cycles；
- reverse A1/A2的一批选点曾出现约500-cycle共同偏移，但它没有选择最后fill，且在
  完整victim map及96样本独立进程复测中分别回到A1=+0.75、A2=-0.50 cycles，故按
  预注册的“随fill order移动”判据拒绝为cache victim证据；
- permuted与Sattolo选点同样只有0.5--0.75-cycle `last-prev`。

这进一步排除了每build-input/geometry/SBT GAS index分配一条31-record record。
原始结果：

- [`plain_64input_sequential.csv`](experiments/rt_structure_probe/results/replacement_paired_build_inputs_v1/plain_64input_sequential.csv)
- [`replacement_paired_build_inputs_map_v1`](experiments/rt_structure_probe/results/replacement_paired_build_inputs_map_v1)
- [`replacement_paired_build_inputs_trash_v1`](experiments/rt_structure_probe/results/replacement_paired_build_inputs_trash_v1)

机器可读汇总见
[`rt_same_gas_path_summary.tsv`](rt_same_gas_path_summary.tsv)。原始CSV：

- [`plain_same_callsite_sequential.csv`](experiments/rt_structure_probe/results/replacement_paired_v1/plain_same_callsite_sequential.csv)
- [`replacement_paired_trash_v1`](experiments/rt_structure_probe/results/replacement_paired_trash_v1)
- 早期K扫描：[`k64_all_seed20624.csv`](experiments/rt_structure_probe/results/k64_all_seed20624.csv)

## 允许与不允许的推断

当前允许：

- 31-record层不是按同一GAS内的每个raw triangle、ray path、build input或SBT GAS
  index独立分配；
- distinct-GAS与relocation-clone结果共同证明allocation identity随traversable/GAS
  output/handle身份改变；
- 同一小GAS内的root/gap/hit路径变化没有复现31/32容量边界；
- null不是被普通L1命中简单掩盖，因为L1-trash敏感性检查仍为null。

当前不允许：

- 宣布所有BVH interior/leaf数据都没有专用缓存；
- 宣布31-record tag位一定逐比特等于公开GAS handle；output地址、header/descriptor和
  handle在当前API下仍共变；
- 把9,344 B GAS的null外推到深BVH、compaction、cluster、LSS或OMM；
- 把`root_gap`名称当作NVIDIA未公开BVH中的确定节点编号。

relocation clones和static-transform共享child wrapper已经完成：前者重新占槽，后者
不占，支持AS-output-record而非generic handle模型。下一项应使用IAS/shared-child与
更深、可控BVH继续拆分instance record、child GAS record和interior-complet容量域。
