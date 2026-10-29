# RTX 5090 / GB202：RT cache 计数器、scope 与实例可见性静态审计

日期：2026-07-11（Asia/Singapore）  
审计范围：本机 Nsight Compute 2026.2.1、Nsight Systems 2026.1.3、CUDA/CUPTI
13.3、PerfWorks GB202 离线 catalog 和现有 `/home/user/rt_cache_probe` 结果。  
安全边界：本轮只做文件读取、离线 chip evaluator 和编译；**没有创建 CUDA
context、没有启动 GPU workload，也没有修改驱动或系统配置**。

> 后续运行时更新：same-launch prime/probe 已从 timing/%smid 找到特定双-SM
> 可见域；这不改变本文“公开 counter 仍无 per-instance 输出”的静态结论。见
> [`RT_CACHE_OWNERSHIP_FINDINGS.md`](RT_CACHE_OWNERSHIP_FINDINGS.md)。

## 结论

1. 公开 GB202 catalog 仍然没有 RT 私有 cache 的容量、line、tag、请求、hit/miss、
   refill 或 occupancy counter。这个负结果没有变化。
2. RTCORE 本身只有 4 个独立计数：`cycles_executed`、`rays`、
   `rays_cast_api`、`rays_cast_proceed`。另外 4 个 throughput 是派生量，不是额外
   硬件事件。
3. 这 4 个 RT counter **只存在于 PM-sampling catalog**，属性为
   `scope=Device, hw_unit=tpc`，且只公开 `.sum/.avg`；range-profiler catalog 中
   `rtcore__*` 为 0 项。因此没有按编号导出 `TPC[n]`、`SM[n]` 或 `RT[n]` 的公开
   路径。
4. 找到两组此前报告没有利用、对 RT 路径很有价值的 **RT-associated
   differential counters**：

   ```text
   smsp__warps_issue_stalled_long_scoreboard
   smsp__warps_issue_stalled_long_scoreboard_pipe_l1tex

   smsp__warps_issue_stalled_mio_throttle
   smsp__warps_issue_stalled_mio_throttle_pipe_mio
   ```

   第二项的本机官方描述分别明确写着 `non-RTCORE L1TEX` 和
   `non-RTCORE pipe of MIO instruction queue`。所以同一 pass 的 `.sum` 差分是
   当前最有希望的 RT 等待/入队压力旁路信号。它仍需用 unique/same/ring 控制
   实测验证，不能仅凭名字把差值宣布成正式 RT cache-miss counter。
5. Range-profiler 中的 L1TEX 和 SMSP counter 是 `Context` scope，并提供
   `.sum/.avg/.min/.max`。虽然没有实例编号，单线程且背景分布不变的控制下，
   `delta(sum) == delta(max)` 可作为新增流量集中在一个 L1TEX/SM instance 的
   间接证据；它不是实例值本身，也不能告诉我们是哪一个 SM。
6. `4 sectors = 128 B traffic` 是成立的；`4 sectors 必为同一条 128 B line`
   **不能仅由现有 counter 形式证明**。L1TEX 没有公开 tag/line lookup 数，也没有
   RT refill-request 数；`l1tex__t_bytes` 只是 sectors×32 B 的同义换算，不是独立
   证据。

## 一、两个 catalog 实际上不是同一种可观测面

用修改后的
[`metric_probe/pm_metric_probe.cpp`](metric_probe/pm_metric_probe.cpp) 可以离线选择
`pm` 或 `range` collection；默认仍为 `pm`。两种模式都只初始化 host evaluator，
不调用 `cuInit`。

```bash
# PM sampling catalog
/tmp/metric_probe_scope GB202 rtcore__ pm

# range-profiler catalog
/tmp/metric_probe_scope GB202 rtcore__ range
```

本机结果：

| collection | base metrics | `rtcore__*` | RT scope | RT hw unit | RT rollups |
|---|---:|---:|---|---|---|
| PM sampling | 1,634 | 8 | Device | TPC | avg, sum |
| Range profiling | 5,132 | 0 | — | — | — |

与 RT 相邻的普通 counter 则相反地可以用 range profiler 做精确、context-scoped
采集：

| metric family | PM 属性 | Range 属性 |
|---|---|---|
| `l1tex__t_sectors_lookup_{hit,miss}` | Device / L1TEX / avg,sum | Context / L1TEX / avg,min,max,sum |
| `smsp__warps_issue_stalled_*` | Device / SMSP / avg,sum | Context / SMSP / avg,min,max,sum |
| `tpc__l1tex_sram_bytes_*` | Device / TPC / avg,sum | Context / TPC / avg,min,max,sum |

这解释了为什么现有 one-pass L1 sector 结果可以是 launch 精确整数，而
`rtcore__rays` 只能通过 PM 时间采样观察：两者不是同一类采集语义。

## 二、`hw_unit=tpc` 不等于“可读取每个 TPC”

### 公开 roll-up 的真实含义

NVIDIA 的 metric guide 明确定义 `.sum/.avg/.min/.max` 是对所有硬件 unit
instances 的 roll-up。例如 `.sum` 是所有 SM/SMSP/L2 slice 实例之和，`.max` 是
其中最大值；它们本身不携带实例编号。

本机 RT suffix query 只有：

```text
rtcore__cycles_executed.{avg,sum}
rtcore__rays.{avg,sum}
rtcore__rays_cast_api.{avg,sum}
rtcore__rays_cast_proceed.{avg,sum}
```

不存在 RT 的 `.min/.max`，更不存在 `rtcore[42]__...` 这类结果。因此：

- `.sum` 应用于事件总量；
- `.avg` 是所有 TPC monitor instances 的平均，不是“活跃 TPC 的平均”；
- `sum/avg` 顶多反映 evaluator 使用了多少 TPC instances，不能定位活跃 TPC；
- `hw_unit=tpc` 说明 raw counter 在 TPC performance-monitor domain 中汇总，
  不能证明物理 RT cache 以 TPC 为共享边界。

本机 `gb20x-top.config` 对所有 TPC→SM 的容量/驻留显示都乘 `0.5`：

```text
line 17: avg_bytes_tpc -> Bytes/SM, multiplier 0.5
line 44: ctas_sm_tpc  -> Avg CTAs/SM, multiplier 0.5
line 71: registers_tpc -> Avg Registers/SM, multiplier 0.5
line 85: warps_tpc -> Avg Warps, multiplier 0.5
```

所以 GB20x 的 performance-monitor TPC 单元覆盖两个 SM。RTX 5090 的 170 SM
对应 85 TPC monitor instances。`rtcore__*` 的 TPC granularity 至少会先把同一 TPC
内两个 per-SM RT Core 的活动合在一起，无法从该 counter 分拆。

### `keepInstances=true` 的陷阱

CUPTI 旧 profiler 样例确实要求 `NVPA_RawMetricRequest.keepInstances=true`；但这
表示 CounterData 内为 roll-up/evaluation 保留 raw unit-instance 数据，并不自动
提供一个按 TPC index 查询的接口。本机 CUDA 13.3 公共 host API
`CUpti_Profiler_Host_EvaluateToGpuValues` 只返回“每个输入 metric 一个 double”，
没有 `unitInstanceIndex` 输出参数：

```text
/opt/cuda/targets/x86_64-linux/include/cupti_profiler_host.h:348-382
```

Nsight Compute 的 `--print-metric-instances` 也不能改变这一点。对于 PM sampling，
官方明确说明所谓 instance 是 `(timestamp, sampled value)` 的**时间样本**，不是
`TPC id`。所以看到 PM metric 有数千 instances 时，不能把它们误读成数千个硬件
单元值。

### 目前能做的间接实例判读

Range-profiler 的 L1TEX/SMSP counter 有 `.min/.max`。对只有一个 raygen thread
的 context-scoped workload，可比较：

```text
delta_sum = (unique17 - same17).sum
delta_max = (unique17 - same17).max
```

若 `delta_sum == delta_max`、其余控制为零、每次确实只有一个 active instance，
且两次 launch 的 baseline 分布不变，这与新增事件只落在一个该类硬件 instance
完全一致。它比仅看 `.sum` 强，但因为 `.max` 没有 correlation ID、不同进程可能
被调度到不同实例，仍属于受控推断而非按实例直接测量。Range 的 Context scope
使它不混入别的 CUDA context；但仍不能用
`max(generic)-max(non_rt)` 代替“每实例差分的 max”。后者两个 max 可能来自不同
SMSP。

更强的 ownership 路径是 CUDA Green Context：本机导出 schema 已包含
`TARGET_INFO_CUDA_CONTEXT_INFO.numTpcs` 与 `tpcMask`，Nsight Compute 也把 SM/L1
列为 Green-Context-attributable units。它可以把 workload 约束到已知 TPC mask，
但 mask 表示“允许使用的资源”，仍不是“某次 trace 实际由哪个 RT Core 服务”。

## 三、发现的 RT-associated warp-stall 差分

GB202 catalog 对下面两对 metric 的描述非常特别：

| generic counter | qualified counter | qualified 描述的关键字 |
|---|---|---|
| `smsp__warps_issue_stalled_long_scoreboard` | `..._long_scoreboard_pipe_l1tex` | dependency on **non-RTCORE L1TEX** |
| `smsp__warps_issue_stalled_mio_throttle` | `..._mio_throttle_pipe_mio` | free entry in **non-RTCORE** MIO pipe |

两对都同时存在于 range 和 PM catalog；range 版本为 `Context` scope、hw unit
`smsp`。建议只对同一 pass 的 `.sum` 做：

```text
rt_long_scoreboard_candidate =
    smsp__warps_issue_stalled_long_scoreboard.sum
  - smsp__warps_issue_stalled_long_scoreboard_pipe_l1tex.sum

rt_mio_throttle_candidate =
    smsp__warps_issue_stalled_mio_throttle.sum
  - smsp__warps_issue_stalled_mio_throttle_pipe_mio.sum
```

解释边界：

- 若 unique K17 相比 K16 增长，而 same-handle/ring 不增长，它会直接把 16→17
  台阶连接到 shader warp 的 RT 等待或 RT MIO queue 压力；
- `long_scoreboard` 更接近等待 RT/L1 返回，`mio_throttle` 更接近提交端队列满；
- 它们不是 cache hit/miss counter，不能由数值直接反推出 entry 数或 bytes；
- catalog 没有公开声明 generic 必然只由 `non-RT + RT` 两部分构成，故差值必须
  先通过空 workload、ring-only、same-handle、unique K16/K17 验证为非负且随
  RT 工作量缩放；
- 必须让一对 counter 在同一 profiler pass 中采集，避免 replay 状态差异。

这两组差分是本次静态审计新增的最有价值发现。

## 四、RT L0 miss 到普通缓存的可观测数据路径

本机 Nsight Systems 的 GB20x 配置给出明确硬件连接描述：

```text
/usr/lib/nsight-systems/target-linux-x64/GpuMetrics/gb20x-top.config:1012
```

其中写明：

- L1Data/Texture 有 LSU 与 TEX 两条并行 pipeline；
- cache fills 和 RTCORE 会与 LSU/TEX 竞争；
- 每 SM 有两块 64 KiB SRAM，共 128 KiB；
- shared 从 SRAM0 向上增长，tagged cache 从 SRAM1 末端向下增长。

同文件 `1166` 行又写明 tagged remainder 服务 local、global、texture、surface。
它没有列出 RT 专属容量，但确认 RTCORE 与普通 L1TEX 端口/填充路径存在资源
耦合。

### 最有用的普通缓存 counter

| 层/问题 | 建议 metric | 能证明什么 | 不能证明什么 |
|---|---|---|---|
| L1 tag stage | `l1tex__t_sectors_lookup_{hit,miss}` | RT 控制差分导致多少 32B sector lookup、在 L1 命中还是 miss | sector 地址、tag 数、RT source identity |
| L1 source classification | `l1tex__t_sectors_pipe_tex*`、`l1tex__average_t_sector_pipe_{lsu,tex}` | 检验 RT backing lookup 是否被计入 TEX/LSU qualifier 或留在 residual | catalog 未声明 RT 一定属于哪一类 |
| Shader front ends | `l1tex__lsuin_requests`、`l1tex__texin_requests` | 检验新增 RT sector 是否绕过普通 LSU/TEX instruction input | 不是 L1 line/refill-request 数 |
| SRAM arrays | `l1tex__sram_cycles_array_{0,1}_cmd_{read,write}`、`l1tex__data_bank_{reads,writes}` | 哪块普通 L1 SRAM/端口在 K17 多活动、是否只有 read | 一次 active cycle 对应多少 sectors、RT 私有 SRAM |
| L1→XBAR | `tpc__l1tex_m_l1tex2xbar_req_cycles_active` | L1 miss 是否向下游发请求 | 请求来源仍混合 |
| XBAR→L1 | `l1tex__m_xbar2l1tex_read_sectors_realtime` | L2 返回给 L1 的 sector 数 | RT source identity |
| L2 | `lts__t_requests_srcunit_tex*`、`lts__t_sectors_srcunit_tex_op_read*` | 普通 L1TEX 发到 L2 的 requests/sectors 及 L2 miss | L2 只标 `srcunit_tex`，没有 `srcunit_rtcore` |
| L1 carveout | `tpc__l1tex_sram_bytes_mem_{tagged,untagged}_realtime` | 每周期累计的动态 tagged/untagged 配置量 | RT L0 容量或占用 |

现有 exact counter 已显示 K17 新增 lookup 几乎全是 L1 hit，L2 没有 per-op
增量；因此当前最合理路径是：

```text
RT residency/L0 candidate miss
    -> ordinary L1TEX tag/data lookup (4 sectors, hit)
    -> RT traversal resumes
```

若普通 L1 miss，则下游会以 `srcunit_tex` 出现在 L2，公开 catalog 没有办法把它
再标回 RTCORE。

### 不应误用的 counter

- `gcc__cache_requests_type_tsheader` 的描述是 texture/sampler header，不是
  traversal-structure header；不能拿来当 BVH/root cache。
- `l1tex__texin_tsl1_requests_*` 是 texture/sampler-header cache，不是 TTU L0。
- `tpc__l1tex_sram_bytes_mem_tagged_realtime` 是累计 byte×cycle 配置量；要用
  `.avg.per_cycle_elapsed` 得到平均配置 bytes。它不是实际 working-set 占用。
- `rtcore__throughput*` 都由 `rtcore__cycles_executed` 派生；不能与 base counter
  当成独立交叉验证。

## 五、为何 4 sectors 尚不能形式化证明“一条 128B line”

NVIDIA 对 quantities 的公开定义是：

```text
1 sector = aligned 32 B
1 L1/L2 cache line = 4 sectors = 128 B
1 request may access one or more sectors
1 request may look up multiple tags/cache lines
```

因此现有整数恒等式严格证明的是：

> 每次候选上层 miss 会产生 4 个 L1TEX sector lookups，即 128 B 的 backing
> traffic。

它没有记录四个 sector 的地址。理论上 counter 仍允许：

- 同一 128B line 的 4 个 sectors；
- 两条 line 各 2 sectors；
- 四条 line 各 1 sector。

下面这些看似可用的“request”也不能补上缺口：

- `l1tex__lsuin_requests`/`texin_requests` 是 shader input requests，不是 RT
  refill/tag requests；
- PM catalog 没有 `l1tex__t_requests` 或 `l1tex__t_tags/lines`；
- `l1tex__t_bytes` 按官方定义就是 sectors×32 B；
- `lts__t_requests_srcunit_tex` 只看到已经掉出 L1 的 L2 request，而当前 4-sector
  增量在 L1 hit；即使冷态得到 1 L2 request + 4 sectors，官方 request 仍允许
  lookup 多个 tags。

所以“single 128B line refill”是结合精确 4-sector 周期、128B line 定义、
地址布局控制和 TTU complet 专利得到的强解释，但不是该 aggregate counter 单独
给出的形式证明。若要形式化，需要公开 tag/line count、sector 地址 trace，或能
控制并跨越 root-record 的 128B 对齐边界；当前 OptiX GAS 内部布局和公开 metric
都没有提供这些条件。

## 六、如何把 RT activity 与 L1 traffic 做有意义的关联

### A. 精确 launch/range 差分（优先）

继续使用 `unique K16/K17`、`same-handle K16/K17`、`ring-only K16/K17`，每次只
采一组能被 NCU 明确报告为 one-pass 的 counter。建议按以下逻辑分批：

```text
Batch 1: L1 total/hit/miss sectors
Batch 2: generic + non-RTCORE long-scoreboard pair
Batch 3: generic + non-RTCORE MIO-throttle pair
Batch 4: SRAM0/SRAM1 read/write active cycles
Batch 5: LSUIN/TEXIN requests and pipe-qualified sectors
Batch 6: L1->XBAR and L2 srcunit_tex reads/requests
```

每组先验证同一 pass，再做以下差分：

```text
unique - same       # 不同 GAS/root residency 的净效应
same - ring         # optixTrace 公共开销
K17/op - K16/op     # 16-entry threshold 的稳态效应
```

同时采 `.sum` 与 `.max` 的 L1/SMSP counter；在单 active-instance 与 baseline
分布不变的控制成立时，新增 `sum=max` 会强力支持净事件集中于一个可见硬件 unit
instance，但仍不提供其编号。

### B. PM-sampling 时间相关（补充，不替代 exact counts）

RT counter 只能这样取：

```text
pmsampling:rtcore__cycles_executed.sum
pmsampling:rtcore__rays.sum
pmsampling:rtcore__rays_cast_api.sum
pmsampling:rtcore__rays_cast_proceed.sum
```

可在同一 PM timeline 加入：

```text
pmsampling:l1tex__t_sectors_lookup_hit.sum
pmsampling:l1tex__t_sectors_lookup_miss.sum
pmsampling:l1tex__sram_cycles_array_0_cmd_read.sum
pmsampling:l1tex__sram_cycles_array_1_cmd_read.sum
```

要求：workload 必须长于多个采样周期、GPU 上没有无关 graphics/compute 活动、
`--pm-sampling-max-passes 1`，并查看 timestamp instances，而不是只看 aggregate。
不同 pass 的时间轴可能错位；短的单线程 OptiX launch 很容易欠采样。

可计算但必须正确解释：

```text
cycles_executed.sum / rays.sum
```

这是“每 counted ray 的 RT unit active/executed cycles”候选，不是端到端 ray
latency；cache 等待周期可能不属于 `cycles_executed`，并且多个 RT 操作可以重叠。
`rays_cast_api` 是 API 初始 cast，`rays_cast_proceed` 是 traversal recast；不要在
未实测前假设 `rays == api + proceed` 对所有路径恒成立。

## 七、证据等级更新

### 当前已经证明

- 公开 catalog 没有 RT 私有 cache counter；
- RT activity counter 的公开 monitor granularity 是 TPC、输出 scope 是 Device；
- 普通 L1 exact counters 的 range scope 是 Context，并有 min/max roll-up；
- 现有 K17 控制差分为每操作 4 个 L1-hit sectors，即 128B backing traffic；
- 配置明确指出 RTCORE 与普通 L1TEX LSU/TEX/cache-fill 路径竞争。

### 新增可验证假设

- generic minus `non-RTCORE` long-scoreboard 是否精确跟随 16→17 的约 27-cycle
  台阶；
- generic minus `non-RTCORE` MIO-throttle 是否只在高并发 RT 提交时增长；
- K17 的 L1 `delta(sum)==delta(max)` 是否确认净 backing traffic 只落在一个
  L1TEX instance；
- RT backing lookup 在 pipe qualifier 中属于 TEX、LSU，还是 unqualified
  residual；
- 新增 lookup 实际激活 SRAM0、SRAM1 或两者。

### 仍然不能由公开 counter 单独证明

- 四个 sectors 的地址属于同一 cache line；
- 16-entry structure 的内部 record 编码/压缩和物理 SRAM bytes；
- cache 是 per-SM、per-two-SM TPC，还是更复杂的端口/前端 ownership；
- 一个具体 SM/TPC index 的 RT cache hit/miss；
- primitive cache、complet cache、descriptor cache 和 translation cache 的正式
  硬件命名。

## 本地证据索引

- 现有 catalog 审计：
  [`metric_probe/README.md`](metric_probe/README.md)
- PM/range 离线 evaluator：
  [`metric_probe/pm_metric_probe.cpp`](metric_probe/pm_metric_probe.cpp)
- RT metric 机器可读清单：
  [`metric_probe/rt_metrics_gb202.json`](metric_probe/rt_metrics_gb202.json)
- 已有 sector 整数审计：
  [`counter_analysis.md`](counter_analysis.md)
- GB20x 本机 metric config：
  `/usr/lib/nsight-systems/target-linux-x64/GpuMetrics/gb20x-top.config`
- CUPTI host evaluator 输出形状：
  `/opt/cuda/targets/x86_64-linux/include/cupti_profiler_host.h:348`
- Green Context/TPC mask schema：
  `/usr/lib/nsight-compute/host/target-linux-x64/exporter/export_schema_version_notes.txt:37`

官方语义参考：

- [Nsight Compute Profiling Guide：metric roll-ups、PM sampling 与 quantities](https://docs.nvidia.com/nsight-compute/ProfilingGuide/index.html)
- [CUPTI profiler host / `keepInstances` 工作流](https://docs.nvidia.com/cupti/main/main.html)

## 推荐的严谨措辞

> GB202 的公开 RT performance monitor 以 TPC 为硬件单元，只输出 Device-scope
> avg/sum 和时间采样，没有可索引的 per-SM/per-TPC RT cache counter。现有控制
> 实验强证实 16-entry 阈值越界后每 traversal 多 4 个命中普通 L1TEX 的 32B
> sectors，即 128B backing traffic；但 aggregate sector counter 不能形式化证明
> 四者属于同一 line。Range-profiler 的 L1/SMSP min/max roll-up，以及 generic
> minus non-RTCORE 的 long-scoreboard/MIO-throttle 成对计数，是下一轮验证 RT
> 等待路径和单实例集中度的最佳公开信号。
