# RTX 5090: CUDA L2 persisting can protect OptiX AS data, but TTU does not self-inherit it

日期：2026-07-12  
设备：RTX 5090（GB202，CC 12.0），Driver 610.43.03，CUDA 13.3，OptiX 9.1

## 结论

本卡上出现了第一个已实测的软件侧 RT cache control：

> 在 OptiX launch 前，用普通 CUDA kernel 读取 GAS output，并让这些 CUDA loads 获得 `cudaAccessPropertyPersisting`，可以使对应 AS backing lines 穿过大于 L2 容量的 streaming 冲刷后仍服务 RT traversal。

但只把同一个 access-policy window 挂到执行 `optixLaunch` 的 stream 上、让 TTU 自己读取 GAS，**没有任何可测收益**。最简解释是：TTU/RT Core 的 AS 请求不继承 CUDA stream access property，或者它使用自己的固定 request priority；公开 stream policy 只影响 CUDA memory instruction。CUDA 仍可通过 **pre-touch + persisting preference** 间接替 RT 保留数据。

`persisting` 是保留优先级，不是锁定。本文的“保护/保留”均不表示不可驱逐。

## 实验结构

探针基于 [`experiments/ias_root_probe`](experiments/ias_root_probe)，增加 host-interlaunch 模式：

1. 连续构建 64 个 one-triangle GAS，每个 output stride 为 2560 B，总窗口 160 KiB。
2. 每次测量只追踪一遍 K=64 unique GAS；reuse distance 大于已测 16-entry RT root 域。
3. 每次 RT launch 前，用覆盖所有 SM 的 CUDA kernel 顺序读取 192 MiB，冲掉普通 L1 和 96 MiB L2 状态。
4. `clock64()` 只包围 64 次 dependent `optixTrace`，不包含 CUDA mark/thrash 时间。
5. `warm`、`normal`、`persist`、`cuda-normal-mark`、`cuda-mark`、`cuda-mark-reset` 分进程运行。
6. 不锁频，不改变 power/driver/cache-control；payload 与 hit 数硬校验。

公开能力实测：

```text
L2                              96 MiB
maximum persisting set-aside    60 MiB
maximum access-policy window   128 MiB
```

## Timing 结果

汇总：[`l2_persist_rt_summary.tsv`](l2_persist_rt_summary.tsv)

### Forced outside root

| 条件 | median cycles/trace | 相对 normal |
|---|---:|---:|
| warm，无冲刷 | 5214.59 | −1552.36 |
| 192 MiB + normal | 6766.95 | baseline |
| 192 MiB + persist on OptiX stream | 6772.34 | +5.39 |
| 192 MiB + CUDA normal pre-read | 6774.64 | +7.69 |
| CUDA persist mark → reset → thrash | 6765.97 | −0.98 |
| CUDA persist mark → thrash | **5561.33** | **−1205.62 / −17.82%** |

`cuda-mark` 恢复了 normal 与 warm 差距的 77.66%。五个独立进程的 process-median 为：

```text
normal:     6766.48  6775.88  6766.95  6765.09  6768.56
self-persist:6772.34 6774.56  6766.14  6769.12  6777.27
cuda-mark:  5563.08  5559.47  5562.23  5561.33  5560.31
```

### Guaranteed triangle hit

| 条件 | median cycles/trace | 相对 normal |
|---|---:|---:|
| warm，无冲刷 | 6188.38 | −2177.64 |
| 192 MiB + normal | 8366.02 | baseline |
| 192 MiB + persist on OptiX stream | 8348.86 | −17.16 |
| 192 MiB + CUDA normal pre-read | 8359.80 | −6.22 |
| CUDA persist mark → reset → thrash | 8361.48 | −4.54 |
| CUDA persist mark → thrash | **6525.36** | **−1840.66 / −22.00%** |

`cuda-mark` 恢复了 normal 与 warm 差距的 84.53%。剩余约 337 cycles/trace 正好符合“L1 已被冲刷、但 L2 行仍在”的中间层状态。

## 容量曲线

Forced-root path：

| thrash MiB | normal | self-persist | CUDA persist mark |
|---:|---:|---:|---:|
| 32 | 5216.23 | 5216.00 | 5216.33 |
| 64 | 5215.62 | 5216.16 | 5216.16 |
| 80 | 5215.72 | 5215.92 | 5216.08 |
| 96 | 5234.64 | 5234.72 | 5234.69 |
| 112 | 6771.12 | 6766.73 | **5560.05** |
| 128 | 6774.56 | 6766.89 | **5562.08** |
| 160 | 6769.78 | 6766.97 | **5560.92** |
| 192 | 6781.28 | 6766.73 | **5561.56** |
| 224 | 6770.59 | 6765.28 | **5561.59** |

三条曲线在 `thrash <= 96 MiB` 完全重合；从 112 MiB 起，normal 与 TTU self-persist 同时跳到 DRAM 平台，只有 CUDA persisting pre-mark 保持 L2 平台。这把效果直接绑定到 96 MiB L2 容量，而不是 launch 顺序、marker kernel 开销或时钟漂移。

## 精确定位 GAS 内被访问的 128 B 行

每个 GAS output allocation 为 2560 B，分成 20 个 128 B 候选行。access-policy window 覆盖整个连续 allocation，但 CUDA marker 每次只读取每个 GAS 的同一个 128 B offset。

### Forced outside root

只有：

```text
output + 0 B
output + 896 B
```

能各自恢复约一半 penalty；其他 18 个 offset 与 normal 相同。

连续范围阶梯：

| 每 GAS 标记范围 | 包含的有效行 | median cycles/trace |
|---|---:|---:|
| none | 0 | 约 6767 |
| `[0,896)` | +0 | 6148.20 |
| `[0,1024)` | +0、+896 | **5531.22** |
| full 2560 B | 同上加无关行 | 约 5561 |

### Guaranteed hit

只有：

```text
output + 0 B
output + 896 B
output + 1024 B
```

有效，每行各恢复约 610–630 cycles。

| 每 GAS 标记范围 | 包含的有效行 | median cycles/trace |
|---|---:|---:|
| none | 0 | 8366.02 |
| `[0,896)` | +0 | 7756.02 |
| `[0,1024)` | +0、+896 | 7141.95 |
| `[0,1152)` | +0、+896、+1024 | **6526.17** |
| full 2560 B | 同上加无关行 | 6525.36 |

所有 GAS handle 相对各自 output base 的值均为 `+12`，已经在探针 JSON 的 `gas_handle_output_offsets` 中记录。因此：

- `output+0` 可高置信称为 **traversable handle/start-header line**。
- `output+896` 只在 root traversal 就需要，结合 16-entry/4-sector L0 信号，是 **root/first-complet line 候选**。
- `output+1024` 只在 triangle hit 增加，是 **leaf/primitive/deeper-path line 候选**。

### Opaque AS byte dump 进一步确认语义

探针用正常 `cudaMemcpyDeviceToHost` 只读复制了本进程拥有的四个 GAS output：

[`as_dumps/one_tri_gas_k4.bin`](as_dumps/one_tri_gas_k4.bin)

四个相同几何的 2560 B allocation 逐字节相同，说明这个配置下输出使用相对 offset，不含随 allocation 改变的绝对 vertex pointer。header 的关键 32-bit words 为：

```text
output + 0x08 = 0x00000a00   # complete GAS size = 2560 B
output + 0x10 = 0x00000400   # points at output + 1024
output + 0x20 = 0x00000380   # points at output + 896
handle          = output + 12
```

`output+0x380` 的开头包含 node header `0x007f7f60`，随后直接出现 AABB/geometry 相关 float `-0.4, -0.4, 1.0`；`output+0x400` 直接包含 triangle vertex/primitive 编码，包括 `-0.4, -0.4, 1.0, +0.4, ...`。

因此在这个 exact build 中可以把语义提升为：

```text
output + 0x000 : traversable header / relative-offset table
output + 0x380 : root node / first complet backing line
output + 0x400 : triangle primitive data line
```

这仍不是官方 ABI，但已经由 header relative offsets、原始内容和独立 persisting timing 三种证据交叉确认。

这些 offset 是 Driver 610.43.03、OptiX 9.1、当前 build flags 下的实测布局，不是 OptiX ABI，其他驱动、build flag、compaction、geometry 数量或 primitive 类型都可能改变。

## IAS 与 GAS backing 成本已经分开

完整报告：[`IAS_GAS_BACKING_LINE_FINDINGS.md`](IAS_GAS_BACKING_LINE_FINDINGS.md)  
汇总：[`l2_ias_gas_split_summary.tsv`](l2_ias_gas_split_summary.tsv)

同一套 host-interlaunch 实验现在支持 `--l2-window gas|ias|both`。对 K=64 独立 `IAS -> GAS` hit，在 112 MiB streaming 压力下：

| 条件 | 三进程 median cycles/trace | 恢复量 |
|---|---:|---:|
| normal | 10593.17 | 0 |
| 只保护 GAS | 9371.89 | 1221.28 |
| 只保护 IAS | 8773.23 | 1819.94 |
| 同时保护 | 7546.27 | 3046.91 |

IAS 与 GAS 的单独恢复量之和为 3041.22 cycles，与联合保护只差 5.69 cycles（0.19%）。ordinary pre-read 与 persisting mark 后 reset 都回到 normal，证明这是两个地址域的可加 L2 residency 效应。

逐 128 B IAS line 扫描定位：

```text
outside-root miss: IAS +0x000, +0x700
triangle hit:      IAS +0x000, +0x600, +0x700
```

每条各恢复约 0.61k cycles，其他 13–14 条无效。配对 raw dump 又确认：

- IAS handle = `output + 4`；
- header `+0x20` 指向 `+0x700` root node；
- header `+0x38` 指向 `+0x600` instance leaf；
- `+0x600` 含 identity transform，并保存直指 child GAS `+0x380` root line 的 packed pointer；
- `+0x700` 含 node/AABB 数据。

因此 `IU hit` 的五条可归因 L2 backing line 是：

```text
IAS header + IAS root + IAS instance leaf + GAS root + GAS primitive
```

其中后四条可与 9/17 sector 方程的两个 16-record root 事件和两个 32-record deeper-path 事件对应；IAS header 是额外 decode line。原来“完整路径暴露四条记录”的说法已收紧为“四条 L1TEX 可见、参与 16/32 替换域的事件”。

## Counter 边界

- 六种 L2 policy 下，单-pass L1TEX 计数完全一致：`2133 hit + 378 miss sectors`。因此 CUDA marker 没有减少 RT 上游请求数，只改变下游 residency。
- device-scope L2/DRAM 总计数受桌面与背景流量污染，不能用于这个 64-trace 短 launch。
- `lts__...srcunit_tex` 在全部条件下固定 `0 hit + 361 miss`，说明 RT backing 仍不属于公开 TEX source qualifier；它不能验证 RT 的 L2 hit/miss。
- 多 metric LTS 组需要 3 replay。因为 replay 会使首轮 cold 状态变 warm，已弃用这些报告，不拿它们做守恒。

Timing 的五进程重复、96 MiB 容量阶梯、normal-marker/reset 反证和精确 AS offset 扫描已经共同证明 persisting 效果；公开 counter 目前不能给 TTU 流量加 source label。

## 实用含义

安全、公开、当前可用的策略是：

```text
set L2 persisting set-aside
    -> set access-policy window over hot GAS/IAS output
    -> launch a CUDA pre-touch kernel over需要保护的AS行
    -> run competing streaming work
    -> optixLaunch consumes the retained lines
```

对于未知/不稳定的 AS layout，标记完整的小型 hot AS 最稳妥；60 MiB set-aside 足以覆盖相当大的热点区。对大型 AS 只标记开头并不保证命中上层 BVH，因为布局不公开。应按实际 driver/build 配置重新做 offset/segment profiling。

Marker 本身有时间和带宽成本；本报告的 RT timing 故意不包含 marker。实际应用只有在 AS 会跨多个后续 RT launches 重用、同时存在足以驱逐 L2 的竞争流量时才可能净收益。

## 原始数据

- `experiments/ias_root_probe/results/l2_repeat_r*`
- `experiments/ias_root_probe/results/l2_curve_*`
- `experiments/ias_root_probe/results/l2_offset_miss_*`
- `experiments/ias_root_probe/results/l2_offset_hit_*`
- `experiments/ias_root_probe/results/l2_range_miss_*`
- `experiments/ias_root_probe/results/l2_range_hit_*`
- `experiments/ias_root_probe/results/l2_split_*`
- `experiments/ias_root_probe/results/l2_split_repeat*`
- `experiments/ias_root_probe/results/l2_ias_line_iu_{miss,hit}_*`
- `experiments/ias_root_probe/results/ncu_l2_*`
