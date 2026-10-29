# RTX 5090 IAS/GAS backing-line decomposition

日期：2026-07-12  
设备：RTX 5090（GB202，CC 12.0），Driver 610.43.03，CUDA 13.3，OptiX 9.1

## 一句话结论

对 64 个独立 `IAS -> GAS` triangle-hit 做逐地址 L2 persisting 干预后，首冷路径可拆成五条彼此近似等价、各约 0.61k cycles DRAM→L2 penalty 的 128 B AS backing line：

```text
IAS output + 0x000   traversable header/decode
IAS output + 0x700   IAS root node / first-complet
IAS output + 0x600   instance leaf + child-root pointer + transform
GAS output + 0x380   GAS root node / first-complet
GAS output + 0x400   triangle primitive data
```

其中后四条正好对应先前 9/17 sector 方程中的四个替换敏感事件：

```text
约 16-record domain: IAS root + GAS root
约 32-record class backing: IAS instance leaf + GAS primitive；resident tag/bundle可能受parent IAS context限定
```

`IAS +0x000` 是额外的 handle/header decode backing line；它有独立的 L2 miss penalty，但现有 L1TEX unique−same 方程没有把它显示为第五个 4-sector replacement event。因此原来的“四个 event”应严格限定为 **L1TEX 可见且参与所测 16/32 驻留域竞争的四个事件**，不能再写成完整路径总共只有四条 AS line。

## 地址域因果分解

实验条件：

- `IU`：64 个独立 IAS，各指向一个独立 one-triangle GAS。
- `IS`：64 个独立 IAS，全部指向共享 GAS 0。
- 每个样本前用全 SM CUDA kernel streaming read 112 MiB，越过本卡 96 MiB L2。
- 每个 measured launch 只跑一圈 K=64，避免在同一个 launch 内重新把 AS 全部加热。
- `clock64()` 只包围 dependent `optixTrace`，不含 CUDA marker/thrash。
- CUDA marker 分别只给 IAS、GAS 或两者的 output allocation 建立 persisting preference。
- 当前用户无锁频权限；所有比较都使用同进程多样本中位数，并对关键 `IU hit` 做三进程重复。每个样本前的全 SM thrash 也提供相同的运行态预热。

完整表：[`l2_ias_gas_split_summary.tsv`](l2_ias_gas_split_summary.tsv)

| 场景 | 路径 | normal | 保护 GAS | 保护 IAS | 保护两者 |
|---|---|---:|---:|---:|---:|
| IS | outside-root miss | 6556.11 | 6570.59 | **5367.05** | — |
| IS | triangle hit | 8446.20 | 8427.48 | **6632.05** | — |
| IU | outside-root miss | 6576.63 | 6571.78 | **5360.47** | — |
| IU | triangle hit | 10586.83 | **9359.52** | **8766.23** | **7545.72** |

判读：

1. `IS/IU miss` 从不进入 child GAS；保护 GAS 的差异只有噪声，保护 IAS 恢复约 1.2k cycles。
2. `IS hit` 的 GAS 0 在 64 条 ray 间共享，很快变热；独立 IAS 仍恢复约 1.81k cycles。
3. `IU hit` 的独立 GAS 与独立 IAS 都有独立收益，分别约 1.22k 和 1.82k cycles。
4. 同时保护两者恢复 3041.11 cycles；两个单独恢复量之和为 3047.91，误差仅 6.80 cycles。

三进程 process-median：

| 条件 | 三个 process median | 跨进程中位数 |
|---|---|---:|
| normal | 10601.95, 10592.69, 10593.17 | 10593.17 |
| GAS | 9371.89, 9364.56, 9384.03 | 9371.89 |
| IAS | 8772.02, 8782.13, 8773.23 | 8773.23 |
| IAS+GAS | 7547.20, 7546.27, 7544.31 | 7546.27 |

跨进程中位数下：

```text
GAS recovery       = 1221.28 cycles
IAS recovery       = 1819.94 cycles
sum                = 3041.22 cycles
joint recovery     = 3046.91 cycles
absolute mismatch  =    5.69 cycles = 0.19%
```

普通 CUDA pre-read 两个区间得到 10578.34；persisting mark 后立刻 `cudaCtxResetPersistingL2Cache()` 得到 10598.20，均回到 10586.83 baseline 附近。这排除了预读、marker 算术或 launch 顺序本身。

## IAS 内逐 128 B line 扫描

one-instance IAS output stride 是 2048 B，共 16 个 128 B 候选区间。完整表：[`l2_ias_line_scan_summary.tsv`](l2_ias_line_scan_summary.tsv)

### Outside-root miss

只有两条有效：

| IAS offset | median cycles | recovery |
|---:|---:|---:|
| none | 6576.63 | 0 |
| `+0x000` | 5963.22 | 613.41 |
| `+0x700` | 5944.53 | 632.09 |
| full IAS | 5360.47 | 1216.16 |

其余 14 个 offset 均在 baseline 的约 ±24 cycles 内。

### Guaranteed hit

命中路径精确增加第三条：

| IAS offset | median cycles | recovery |
|---:|---:|---:|
| none | 10586.83 | 0 |
| `+0x000` | 9995.09 | 591.73 |
| `+0x600` | 9975.58 | 611.25 |
| `+0x700` | 9986.63 | 600.20 |
| full IAS | 8766.23 | 1820.59 |

三条单独 recovery 之和为 1803.19 cycles，与 full-IAS 的 1820.59 相差 17.41 cycles。逐行效应和 IAS/GAS 地址域联合效应都表现为近似整数个约 0.61k-cycle DRAM→L2 penalty。

## Opaque IAS bytes 对语义的交叉确认

探针新增 `--dump-ias`，用正常 `cudaMemcpyDeviceToHost` 只读复制本进程拥有的 AS output。配对 dump：

- [`as_dumps/paired_ias_is_iu_k4_20260712.bin`](as_dumps/paired_ias_is_iu_k4_20260712.bin)
- [`as_dumps/paired_gas_k4_20260712.bin`](as_dumps/paired_gas_k4_20260712.bin)
- [`as_dumps/paired_as_k4_20260712.json`](as_dumps/paired_as_k4_20260712.json)

当前 exact build 的所有 IAS handle 都是 `output + 4`。header 直接给出：

```text
output + 0x08 = 0x00000800   # IAS output size = 2048 B
output + 0x20 = 0x00000700   # points to hot root-node line
output + 0x38 = 0x00000600   # points to hot instance-leaf line
```

`output+0x600` 包含 identity transform 的 `1.0f/0.0f` 矩阵数据，并在 `+0x608` 保存带 flag 的 child-root pointer。配对 dump 中：

```text
GAS0 output base       = 0x7fa25a400600
GAS0 root line         = base + 0x380 = 0x7fa25a400980
IAS instance + 0x608   = low address 0x7fa25a400980, high flag byte 0x04
```

也就是说 IAS instance leaf 直接指向 child GAS 的 root-node line，而不是要求 traversal 再从 GAS handle header 开始。这解释了 `IU hit` 中保护 GAS 只恢复约两条 line（GAS root + primitive），而 direct-GAS hit 会出现三条（GAS header + root + primitive）。

`output+0x700` 含 node header、量化 bounds/AABB 数据；它与 outside-root 即被访问的行为一致。

`output+0x200` 还保存了完整 child GAS traversable handle，但逐行 timing 中 `+0x200` 无收益。它可能是构建/辅助 metadata；至少不是本路径在 L2 压力下的关键 traversal line。

## 当前硬件运行图

```text
IAS handle (= output+4)
  |
  +--> IAS +0x000  header/decode backing
  |
  +--> IAS +0x700  root/complet candidate ---------+
  |                                                   | ~16-record domain
  +--> IAS +0x600  instance leaf                     |
          |                                           |
          +-- child-root ptr --> GAS +0x380 ----------+
          |                                          
          +-- transform/instance data --+             
                                        | ~32-record domain
GAS +0x400  triangle primitive ---------+
```

严格说，16/32 的归属仍是由容量方程、路径语义、地址内容共同支持的强推断；尚无 NVIDIA 公开物理 cache tag 或每请求地址 counter。但它已经比“root cache/primitive cache”二分法具体得多，并且每条地址都可由软件 persisting 干预单独验证。

后续shared-child指定victim进一步显示：64个独立IAS共享同一GAS时，gap最后fill为
+27、leaf为+54，故leaf-gap仍为+27；四种fill order全部复现。它证明IAS hit有两个
同步31-class阶段，但不允许仅凭上图把两个resident tag写成一个IAS tag加一个完全
无parent context的GAS tag。图中offset仍是已验证backing地址，内部tag/bundle组合
见[`IAS_SHARED_CHILD_REPLACEMENT_FINDINGS.md`](IAS_SHARED_CHILD_REPLACEMENT_FINDINGS.md)。

## 复现入口

```sh
# IU hit，只保护 IAS
./build/optix_ias_root_probe \
  --max-k 64 --only-k 64 --samples 9 --rounds 1 --warmup 0 \
  --scenario iu --handle-set unique --mode hit \
  --l2-policy cuda-mark --l2-window ias --thrash-mib 112

# 扫 IAS output+0x600
./build/optix_ias_root_probe \
  --max-k 64 --only-k 64 --samples 7 --rounds 1 --warmup 0 \
  --scenario iu --handle-set unique --mode hit \
  --l2-policy cuda-mark --l2-window ias --thrash-mib 112 \
  --mark-offset 1536 --mark-bytes 128
```

原始数据：

- `experiments/ias_root_probe/results/l2_split_*`
- `experiments/ias_root_probe/results/l2_split_repeat*`
- `experiments/ias_root_probe/results/l2_ias_line_iu_{miss,hit}_*`

这些 offset 属于 Driver 610.43.03、OptiX 9.1、当前 build flags 和 one-instance/one-triangle 布局，不是公开 OptiX ABI。
