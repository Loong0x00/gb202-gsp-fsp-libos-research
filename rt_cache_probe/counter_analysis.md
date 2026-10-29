# OptiX K=16/17 L1TEX 计数器独立审查

## 结论先行

现有计数器数据**可靠支持**下面这条较窄的结论：在 `unique one-triangle GAS + forced miss + Sattolo ring` 中，K=16 时只有首次遇到各 GAS 的一次性 4-sector 填充；K=17 时则几乎每次 traversal 都额外产生 4 个命中 L1TEX 的 sector request。`same-handle` 和 `ring-only` 都没有这个变化。

这不是一个模糊的 `~4`：原始整数恰好满足

```text
K=16: (unique total L1 lookup) - (same total L1 lookup)
      = 60 = 4 * (16 - 1)

K=17: (unique total L1 lookup) - (same total L1 lookup)
      = 73,980 = 4 * (18,496 - 1)
```

因此，“16 个不同 GAS 可常驻、17 个循环访问开始逐次 refill”的解释很强；每次 refill 对应 `4 × 32 B = 128 B` 的 L1TEX sector traffic 也很强。它把当前证据提升为一个**约 16-entry、每次淘汰后请求 128B 的 RT traversal 公共路径缓存/驻留结构候选**。

但是，计数器尚不能区分它是 raw complet/root line cache、handle/root descriptor cache、地址翻译缓存，还是另一种 traversal front-end record cache；也不能证明 RT 单元内部实际以 128B raw bytes 保存每个 entry。因此 `16 × 128 B = 2 KiB` 目前可以作为“有效 backing-data footprint / 容量候选”，不应写成已证实的物理 SRAM byte capacity。后续 ownership 已找到特定双-SM可见域，但仍不支持“每 SM 2KiB”或“每 TPC一份2KiB SRAM”；见 [`RT_CACHE_OWNERSHIP_FINDINGS.md`](RT_CACHE_OWNERSHIP_FINDINGS.md)。

## 归一化审计

`sweep_device.cu::run_sweep()` 的 PM counter 覆盖整个 OptiX launch，而不只覆盖 `clock64()` 包围的 timed loop；warmup 也必须计入分母。当前参数是：

```text
samples = 1
rounds = 1024
warmup_rounds = 64
operations(K) = K * (64 + 1 * 1024) = K * 1088
N16 = 17,408
N17 = 18,496
```

用 timed-only 的 `16,384` / `17,408` 作分母会错误夸大计数。下表均使用全 launch 分母；`delta` 是 K17/op − K16/op。

| mode / metric | K16 / op | K17 / op | delta |
|---|---:|---:|---:|
| unique L1 hit | 34.409696691 | 38.406087803 | **+3.996391112** |
| unique L1 miss | 0.006606158 | 0.006487889 | -0.000118269 |
| unique L1 total lookup | 34.416302849 | 38.412575692 | **+3.996272843** |
| unique L2 TEX read | 0.005629596 | 0.005568772 | -0.000060824 |
| same-handle L1 hit | 34.410558364 | 34.410629325 | +0.000070961 |
| same-handle L1 miss | 0.002297794 | 0.002162630 | -0.000135164 |
| same-handle L1 total lookup | 34.412856158 | 34.412791955 | -0.000064203 |
| same-handle L2 TEX read | 0.001321232 | 0.001243512 | -0.000077720 |
| ring-only L1 hit | 1.999770221 | 1.999783737 | +0.000013516 |
| ring-only L1 miss | 0.000861673 | 0.000810986 | -0.000050687 |
| ring-only L1 total lookup | 2.000631893 | 2.000594723 | -0.000037170 |
| ring-only L2 TEX read | 0.000689338 | 0.000648789 | -0.000040549 |

最干净的差分是：

| derived response | K16 / op | K17 / op | delta |
|---|---:|---:|---:|
| unique − same, L1 total lookup | 0.003446691 | 3.999783737 | **+3.996337046** |
| unique − same, L1 hit | -0.000861673 | 3.995458478 | **+3.996320150** |
| same − ring, L1 total lookup | 32.412224265 | 32.412197232 | -0.000027033 |

`same − ring` 在 16/17 间稳定到约 `2.7e-5 sector/op`，说明普通 `optixTrace` 公共开销没有同步改变；变化只在“使用不同 GAS handle/address”时出现。

## 原始整数为何比均值更有信息

原始值是：

| mode | K | L1 hit | L1 miss | L2 TEX read | L2 miss |
|---|---:|---:|---:|---:|---:|
| unique miss | 16 | 599,004 | 115 | 98 | 98 |
| unique miss | 17 | 710,359 | 120 | 103 | 103 |
| same-handle miss | 16 | 599,019 | 40 | 23 | 23 |
| same-handle miss | 17 | 636,459 | 40 | 23 | 23 |
| ring-only | 16 | 34,812 | 15 | 12 | 12 |
| ring-only | 17 | 36,988 | 15 | 12 | 12 |

把 L1 hit+miss 合并后，unique−same 的精确关系说明：

- K=16：与同一 handle 相比，仅多 60 sectors，正好是另外 15 个 GAS 各 4 sectors 的一次性访问。64 圈 warmup 后，timed 阶段没有持续 refill 流量。
- K=17：与同一 handle 相比，多 73,980 sectors，正好是全 launch 18,496 次操作除第一次外、每次 4 sectors。Sattolo 单环配合这一恒等式符合容量 16、循环 17 时每访问一次淘汰一次的稳态行为。
- 这些附加 sectors 几乎全是 L1 lookup hits；L1 misses 和 L2 reads 没有按每操作增加。也就是说候选上层结构 miss 后，backing data 已在普通 L1 中，延迟的约 26.5 cycles 台阶并不是落到 L2 的台阶。

Nsight Compute 13.3 对 `l1tex__t_sectors_lookup_hit.sum` 的本机 catalog 描述是“向 T-stage 发出的、tag-hit 且 data-hit 的 sector requests 之和”。官方 profiling guide 定义一个 sector 为对齐 32B、L1/L2 cache line 为 4 sectors/128B。因此可严谨地说“每次候选 refill 请求 128B 的 L1TEX sector traffic”。仅凭 aggregate sector counter 看不到四个 sector 的地址，严格说仍不能证明它们必然属于同一条相邻 128B line；不过整数恒等式、官方 4-sector line 定义和时延阈值一起，使“一次 128B refill”成为目前最简洁的解释。

## One-pass 复核与 NCU replay 陷阱

原始四-metric 命令需要 3 个 kernel-replay passes，且使用 `--cache-control none`。官方文档明确指出：kernel replay 可恢复被 kernel 写过的 device memory，但不能恢复硬件 cache；`Flush None` 会让后续 replay 继承此前 GPU 工作，跨 pass 的 metric 可能不一致甚至越界。

因此又做了 6 次专门复核，只请求下面两个 metrics，并加 `--disable-extra-suffixes`：

```text
l1tex__t_sectors_lookup_hit.sum
l1tex__t_sectors_lookup_miss.sum
```

unique-miss、same-miss、ring 各自的 K16/K17 六次采集全部由 NCU 明确报告为 **`1 pass`**，且 12 个 hit/miss 原始值与上表逐项完全相同。由此：

1. `hit + miss`、`unique − same` 的两个精确整数恒等式已由同一 pass 的兼容 counters 复核，不再存在跨 replay 混算问题。
2. 核心 `+4 sectors/op` 不是后续 replay 变暖造成的假象。
3. L2 两项仍来自原来的多-pass 报告；“L2 没有 per-op 台阶”在数量级上很清楚，但若要把几个 sector 的小差异作严格 conservation 分析，仍应把 L2 metrics 单独做 one-pass 采集。

所有复核均保持 `--clock-control none --cache-control none`，没有锁频、flush cache 或修改设备配置。每次 launch 内已有 64 个完整环的显式程序 warmup；这和让 profiler 在 pass 之间隐式保留 cache 是不同的，且是被测应用语义的一部分。

### Padded 地址布局复现

随后把 `allocation-layout` 从单一 allocation 内连续 2,560B 子区的 `contiguous` 改成 `padded`，仍用 Sattolo 顺序，复跑 unique-miss 与 same-miss 的 K16/K17。该实现为每个 GAS 单独分配输出，并在相邻 GAS 之间保持 4–28KiB 的 live dummy allocation，因而显著改变相邻地址间距。四次采集也全部是 `1 pass`。

| padded mode | K | L1 hit | L1 miss | unique − same total |
|---|---:|---:|---:|---:|
| unique miss | 16 | 599,004 | 115 | **60** |
| same-handle miss | 16 | 599,019 | 40 | — |
| unique miss | 17 | 710,359 | 120 | **73,980** |
| same-handle miss | 17 | 636,459 | 40 | — |

不只是归一化结果一致：padded 与 contiguous 的八个 hit/miss 原始整数**逐项 bit-for-bit 相同**，所以仍有 `60 = 4 × (16−1)` 和 `73,980 = 4 × (18,496−1)`。这显著削弱了“连续 2,560B stride 的特定地址低位/allocator 布局制造 K=16 冲突”这一解释，也说明 counter 信号在这两类布局间具有极高确定性。

它仍不能完全排除所有 set-conflict 或 translation 假设：要做到这一点还需随机 base offset、独立 member seeds 和明确的 page/VMM stride 控制。但候选不随当前最强的 packed-vs-padded 地址扰动改变，已经比单一布局证据更强。

另外两点：

- 这些是 Device-scope `sum`，包含该 OptiX launch 的全部 L1TEX source traffic，不能从 metric 名称直接归属为 RTCORE 私有 counter。unique−same 与 ring 控制让 RT traversal refill 成为强相关解释，但不是硬件 source attribution。
- 每条命令是独立进程、独立 context/GAS build；K16 与 K17 不是同一 allocation seed 的配对实验。当前恒等式很难由普通噪声产生，但正式结论仍应跨多次新进程/新地址 seed 复现。
- 当前程序输出中的 `candidate_entry_bytes=128`、`candidate_resident_entries=16`、`candidate_capacity_bytes=2048` 是源码硬编码的候选标签，不是 runtime 自动测得的 metadata；分析时不能拿这三个字段反过来当证据。

## 允许的结论措辞

推荐：

> RTX 5090/当前驱动和 OptiX 9.1 的单线程 one-triangle-GAS probe 显示，一个 RT traversal 公共路径的驻留结构存在 16-entry 有效阈值。越过阈值后，每次不同-GAS 访问额外请求 4 个命中 L1TEX 的 32B sectors（128B backing traffic）；same-handle 与 ring 控制无此变化。这支持“16 × 128B = 2KiB backing footprint”的强候选，但尚不能把它等同于已证实的每-SM RT 私有 SRAM 容量。

不推荐：

> 已测得 Blackwell 每 SM RT cache = 2KiB。

后一句仍跳过 cache 内容类型、内部编码/压缩和 replay-independent replication；
后续双-SM可见域只解决了 observable locality，并未证明一份物理 per-TPC data RAM。

## 参考

- [NVIDIA Nsight Compute 13.3 Profiling Guide：sector、cache line 与 quantities](https://docs.nvidia.com/nsight-compute/ProfilingGuide/index.html#quantities)
- [NVIDIA Nsight Compute 13.3：Cache Control 与 Replay](https://docs.nvidia.com/nsight-compute/NsightCompute/index.html)
- 本地独立设计审查：`/home/user/rt_cache_probe/benchmark_review.md`
- 被审查实现：`/home/user/rt_cache_probe/agent_optix/minimal/sweep_device.cu`、`gas_sweep.cpp`
