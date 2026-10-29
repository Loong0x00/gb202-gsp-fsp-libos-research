# RTX 5090 RT query 提交、等待与 L1TEX refill 路径

日期：2026-07-11

## 结论

两组 GB202 counter 差分把单条 `optixTrace()` 的 shader-side 行为分成了两个阶段：

```text
SM warp
  -> RT/MIO query 提交压力：约 28 warp-stall units / trace，和 cache hit/miss 无关
  -> RT traversal 执行
  -> root/complet L0 miss 时，SRAM1 读一条 128B backing line
  -> 等待结果的 long-scoreboard stall 增加约 25.9 / trace
  -> payload/result 回到 shader
```

这些是受控差分，不是 NVIDIA 正式命名的 `RT submit cycles` 或 `RT wait cycles`。
但 unique/same/ring 三组控制使其硬件含义比单看 counter 名称更清楚。

## Long scoreboard：命中等待与 L0 miss penalty

本机 catalog 对 qualified counter 的描述明确排除 RTCORE：

```text
generic  = smsp__warps_issue_stalled_long_scoreboard.sum
non-RT   = smsp__warps_issue_stalled_long_scoreboard_pipe_l1tex.sum
candidate = generic - non-RT
```

one-pass 结果，counter 覆盖 warmup+timed 的 `N=1088K` 次操作：

| 模式 | K | candidate / trace |
|---|---:|---:|
| unique GAS forced-miss | 16 | 200.0302 |
| same-handle forced-miss | 16 | 199.1215 |
| unique GAS forced-miss | 17 | 225.0309 |
| same-handle forced-miss | 17 | 199.1167 |

因此 K=17 的不同-GAS root/complet L0 miss 净增加：

```text
225.0309 - 199.1167 = 25.9142 stall units / trace
```

它与同一运行中约25 cycles/trace的端到端timing差、以及非profiler运行的
26.5--27 cycles台阶一致。K=16只有冷填充造成约0.91/trace的摊薄差。

这支持：16-entry阈值不只是L1 traffic相关，而是shader warp确实在等待RT query
返回；L0 miss的主要可见代价约26 cycles。

## MIO throttle：提交端公共成本

第二对 qualified counter 也明确排除 RTCORE：

```text
generic  = smsp__warps_issue_stalled_mio_throttle.sum
non-RT   = smsp__warps_issue_stalled_mio_throttle_pipe_mio.sum
candidate = generic - non-RT
```

K=17 one-pass 结果：

| 模式 | candidate / operation |
|---|---:|
| unique GAS forced-miss | 28.0000 |
| same-handle forced-miss | 28.0000 |
| ring-only（无 optixTrace） | 0.0000 |

所以这个差分精确跟随“是否提交RT query”，但完全不响应16-entry cache overflow。
最合理的用途是把它当成 RT/MIO issue-queue pressure候选，而不是cache-miss指标。

## 和 L1TEX 数据路径合并

同一批实验已经给出：

```text
root L0 hit   : 无额外 L1 sector / SRAM read
root L0 miss  : +4×32B L1TEX hit sectors
                +1 SRAM1 read-active cycle
                +0 ordinary l1tex__t_requests
                +约25.9 long-scoreboard stall / trace
```

这把路径限定为：RT/cache-fill traffic绕过普通LSU/TEX T-request计数点，在更靠后的
L1TEX tagged SRAM路径读取一条128B backing line，并延长等待RT结果的scoreboard。

pipe-qualified sectors 又给出直接的 residual-source 控制：

```text
K17 forced miss:
  unique      pipe_lsu=636491, pipe_tex=0
  same-handle pipe_lsu=636491, pipe_tex=0

K32 guaranteed hit:
  unique      pipe_lsu=1441803, pipe_tex=0
  same-handle pipe_lsu=1441803, pipe_tex=0
```

尽管总 `l1tex__t_sectors` 在 unique workload 中分别多出root/primitive refills，
普通 LSU 与 TEX 两个 qualifier逐整数不变。这说明新增sector位于它们之外的
RTCORE/cache-fill residual路径，而不是entry-table global loads或texture访问。

## 限制

- catalog没有保证 generic counter 严格等于 `non-RT + RT` 两项之和；这里依赖
  same/ring控制验证差分的行为。
- `warp` counter单位不是端到端clock64周期的官方别名；数值接近不能当作形式等号。
- 单线程依赖probe只测latency路径；多warp时MIO queue与RT pipeline可以重叠，
  per-trace数值不会保持不变。
- 这些counter仍是context范围roll-up，不能提供SM/TPC实例编号。

静态catalog与scope审计见 [`rt_counter_scope.md`](rt_counter_scope.md)。
