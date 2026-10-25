# DG0 filter 可辨识性审计 — 2026-08-16

## 实测结果

对 `benchmark_logs/*20260816*/power-policy0-dynamic.csv` 的 59 个文件运行：

```bash
cd power_governor_reverse/bug_inverse/algorithm
python fit_dg0_filter.py <59 个 CSV> --pmu-period-ms 20
```

合计读取 18,682 行，其中 18,311 行的时间戳、`est_freq0_mhz` 与 `dg0_khz`
可解析。相邻样本间隔中位数 194.0 ms，P10/P90 为 80.0/211.0 ms。以 20 ms
作为显式假设的控制周期时，中位样本折叠约 9.7 次内部更新。

只在 `|target - previous DG0| >= 15 MHz` 的转场上拟合

```text
DG0[k] - DG0[k-1] = alpha_eff * (target[k] - DG0[k-1])
```

得到：

| 方向 | 转场数 | sample-level alpha_eff | RMSE | 输出不动比例 |
|---|---:|---:|---:|---:|
| 上升 | 1,122 | 0.6933 | 8.34 MHz | 7.3% |
| 下降 | 7,700 | 0.000182 | 12.72 MHz | 67.5% |

这支持“上升快速追踪、下降有长 hold/dwell”的非对称状态机，但不能推出上述数值
就是固件 Q12 系数。原因不是成本，而是信息论上的时间混叠：两个快照之间的候选轨迹、
更新次数和执行顺序都没有被观测；不同的 per-cycle gain、dwell 和短脉冲序列能产生完全
相同的 CSV 行。

`fit_dg0_filter.py` 因此只输出 `sample_to_sample_effective_gain_only`，并固定将
`per_cycle_q12_coefficient_identified` 报为 false。数字孪生已经容纳
`alpha_up/alpha_down/down_hold_steps/hysteresis_mhz`，当前配置将它们标作 placeholder，
不把拟合值写回固件模型。

## 最短判别实验

1. 在同一长驻进程中，以不高于一个控制周期的窗口原子化记录原始 candidate 与 DG0；
2. 分别产生单独的上升阶跃、下降阶跃和短脉冲，保持 workload/P-state/rail cap 不变；
3. 保存 raw integer、调用前后 `CLOCK_MONOTONIC_RAW`、PERF limit 与 rail target；
4. 用前两次非饱和响应解 Q12 gain，用短脉冲判别 dwell/hysteresis，再以未参与拟合的阶跃重放；
5. 只有逐周期预测误差不超过一个 15 MHz bin，才把 placeholder 改成 identified。

这是只读观测设计；若产生阶跃需要写控制量，仍必须先通过既有 preimage/readback/Xid
回滚安全门。
