# RTX 5090 / GB202：RTCORE 与缓存性能计数器只读清点

## 结论

本机 NVIDIA 工具公开的 GB202 性能计数器中，没有 RTCORE 专属缓存的容量、占用、请求、流量、命中或未命中计数器。

公开可见的 RTCORE base metrics 恰好只有 8 个：4 个活动/射线 counter，以及基于它们得到的 4 个 throughput。它们都是 `Device` scope，collection hardware unit 是 `tpc`；counter 只有跨实例的 `avg`/`sum` roll-up，没有每个 SM/RT 单元的实例值。因此这些指标不能给出每个 SM 的 RT 私有缓存大小，也不能测量其命中率。

这项负结果不等于“硬件内部一定没有专用 L0”。它只证明当前 Nsight Compute 2026.2.1、Nsight Systems 2026.1.3、CUPTI 13.3/NVPerf 的公开 GB202 catalog 没有相应可观测量。若硬件确有未公开的 traversal/TTU L0，公开计数器无法直接读出其容量。

## 本机版本和权限状态

```text
GPU:                  NVIDIA GeForce RTX 5090
PCI device ID:        0x2B8510DE
Driver:               610.43.03
Nsight Compute:       2026.2.1.0 (build 38283040)
Nsight Systems:       2026.1.3.425
CUDA/CUPTI:           13.3
RmProfilingAdminOnly: 1
```

查询状态的只读命令：

```bash
nvidia-smi --query-gpu=index,name,pci.device_id,driver_version,vbios_version,memory.total \
  --format=csv,noheader
/usr/lib/nsight-compute/ncu --version
/usr/bin/nsys --version
rg '^RmProfilingAdminOnly' /proc/driver/nvidia/params
```

普通用户对真实设备执行 performance-counter query 会返回 `ERR_NVGPUCTRPERM`。本文没有修改内核模块参数、时钟、功耗、风扇、VBIOS 或驱动状态，也没有运行 GPU workload。

## 可复现的离线 GB202 catalog 查询

`--chips gb202` 使用 NVPerf 的虚拟芯片 metric evaluator，不创建 CUDA context，不采样硬件，也不需要 performance-counter 权限。

```bash
NCU=/usr/lib/nsight-compute/ncu

# 完整 PM-sampling base catalog 中与本问题相关的前缀
timeout 45s "$NCU" --csv \
  --query-metrics \
  --query-metrics-mode base \
  --query-metrics-collection pmsampling \
  --chips gb202 \
  | rg '^"(rtcore__|l1tex__|gcc__|lts__|dram__)'

# RTCORE 的完整 base metric 集合
timeout 45s "$NCU" --csv \
  --query-metrics \
  --query-metrics-mode base \
  --query-metrics-collection pmsampling \
  --chips gb202 \
  | rg '^"rtcore__'

# 搜索 RT 专属缓存/流量指标；本机结果为 0 行（rg exit 1）
timeout 45s "$NCU" --csv \
  --query-metrics \
  --query-metrics-mode base \
  --query-metrics-collection pmsampling \
  --chips gb202 \
  | rg -i '^"rtcore__.*(cache|hit|miss|capacity|sector|byte|request|fill|l0|l1)'
```

PM catalog 共 1634 个 base metrics；相关前缀计数如下：

| 前缀 | 数量 |
|---|---:|
| `rtcore__` | 8 |
| `l1tex__` | 254 |
| `gcc__` | 34 |
| `lts__` | 516 |
| `dram__` | 15 |
| `tpc__l1tex_sram_bytes...` | 18 |

RT counter 的 suffix 只出现 `avg` 和 `sum`：

```bash
timeout 45s "$NCU" --csv \
  --query-metrics \
  --query-metrics-mode suffix \
  --query-metrics-collection pmsampling \
  --chips gb202 \
  --metrics rtcore__cycles_executed,rtcore__rays,rtcore__rays_cast_api,rtcore__rays_cast_proceed \
  | rg -o '^"rtcore__[^"]+\.(avg|sum)' \
  | sort -u
```

输出：

```text
rtcore__cycles_executed.avg
rtcore__cycles_executed.sum
rtcore__rays.avg
rtcore__rays.sum
rtcore__rays_cast_api.avg
rtcore__rays_cast_api.sum
rtcore__rays_cast_proceed.avg
rtcore__rays_cast_proceed.sum
```

## 完整的 8 个 RTCORE base metrics

| Metric | 类型 | 描述 |
|---|---|---|
| `rtcore__cycles_executed` | Counter | cycles where an intersect or traversal unit op executed |
| `rtcore__rays` | Counter | rays cast by shader or traversal logic, including recasts |
| `rtcore__rays_cast_api` | Counter | rays cast by `TraceRay`/`RayQuery`, excluding recasts |
| `rtcore__rays_cast_proceed` | Counter | rays recast during traversal |
| `rtcore__throughput` | Throughput | RTCORE throughput |
| `rtcore__throughput_internal_activity` | Throughput | RTCORE throughput, internal activity |
| `rtcore__throughput_realtime` | Throughput | RTCORE throughput (realtime form) |
| `rtcore__throughput_realtime_internal_activity` | Throughput | realtime internal-activity throughput |

机器可读副本见 [rt_metrics_gb202.json](rt_metrics_gb202.json) 和 [rt_metrics_gb202.tsv](rt_metrics_gb202.tsv)。

## CUPTI Profiler Host API 交叉验证

[pm_metric_probe.cpp](pm_metric_probe.cpp) 直接使用 CUDA 13.3 官方样例提供的 `MetricEnumerator`，以 `CUPTI_PROFILER_TYPE_PM_SAMPLING` 和芯片名 `GB202` 初始化 host evaluator。它不调用 `cuInit`，不创建 context，也不读取实际 GPU counter。

构建到临时目录：

```bash
/opt/cuda/bin/nvcc -std=c++17 \
  -o /tmp/pm_metric_probe \
  /home/user/rt_cache_probe/metric_probe/pm_metric_probe.cpp \
  -I/opt/cuda/include \
  -I/opt/cuda/extras/CUPTI/include \
  -I/opt/cuda/extras/CUPTI/samples/common \
  -L/opt/cuda/extras/CUPTI/lib64 \
  -L/opt/cuda/lib64 \
  -lcupti -lcuda
```

运行：

```bash
timeout 30s /tmp/pm_metric_probe GB202 rtcore__
timeout 30s /tmp/pm_metric_probe GB202 gcc__
timeout 30s /tmp/pm_metric_probe GB202 lts__t_sectors_srcunit_tex
timeout 30s /tmp/pm_metric_probe GB202 tpc__l1tex_sram_bytes

# 可选第 3 个参数选择 range-profiler catalog；默认仍为 pm
timeout 30s /tmp/pm_metric_probe GB202 rtcore__ range
timeout 30s /tmp/pm_metric_probe GB202 l1tex__t_sectors_lookup range
```

第一条命令确认全部 8 项 RT metric 的属性均为 `hw_unit=tpc`、`scope=Device`。CUDA/range profiler 的 legacy NVPW evaluator 则不列出 `rtcore__`；[nvperf_eval_probe.cpp](nvperf_eval_probe.cpp) 可复现这个差异。这与 `ncu --query-metrics-collection profiling` 无 RT 指标、只有 `pmsampling` catalog 提供 RT 指标一致。

新增的 `range` 模式通过同一 CUDA 13.3 CUPTI host evaluator 进一步确认：range catalog 有 5,132 个 base metrics、`rtcore__` 为 0 项；`l1tex__t_sectors_lookup_{hit,miss}` 和 SMSP stall counters 则为 `scope=Context`。PM 模式对应的同名普通 counter 为 `scope=Device`。完整 scope/instance 审计见 [`../rt_counter_scope.md`](../rt_counter_scope.md)。

## `libnvperf_grfx_host` 与 Nsight Systems 的证据

Nsight Systems 随附的 graphics NVPerf catalog 同样只含这 8 个 RT 名称：

```bash
GRFX=/usr/lib/nsight-systems/target-linux-x64/libnvperf_grfx_host.so

strings -a "$GRFX" | rg '^rtcore__' | sort -u

# 结果为空
strings -a "$GRFX" \
  | rg -i '^rtcore__.*(cache|hit|miss|capacity|sector|byte|request|fill|l0|l1)' \
  | sort -u
```

Nsight Systems 的 GB20x top-level metric set 位于：

```text
/usr/lib/nsight-systems/target-linux-x64/GpuMetrics/gb20x-top.config
```

关键配置行：

- `290-293`：`Top_Level_Overview.rtcore__throughput` 仅由 `rtcore__cycles_executed` 构成。
- `588`：GPU trace 中 RTCORE 只显示 throughput。
- `707`、`710`：L1TEX 仅提供整体 tag-stage miss/hit 流量。
- `708`、`711-713`：L2 只能按来源 `srcunit_tex`（描述为来自 L1TEX）观察 miss/hit-rate，没有 `srcunit_rtcore`。
- `1012`：NVIDIA 的本地说明明确写道，cache fills 与 RTCORE 会和 L1TEX 的 LSU/TEX 两条流水线竞争。
- 同一行还明确写道，每个 SM 的片上 L1TEX RAM 为 `2 x 64KB = 128KB`。因此“64KB”是单块 SRAM 的大小，不是整个 SM 上这组物理 SRAM 的总量。tagged L1 与 shared/TRAM 的实际分配仍是动态的。

可直接查看这些行：

```bash
CFG=/usr/lib/nsight-systems/target-linux-x64/GpuMetrics/gb20x-top.config
nl -ba "$CFG" | sed -n '108,151p;284,296p;580,592p;700,724p;1008,1026p'
```

配置中的普通缓存容量计数器包括：

```text
tpc__l1tex_sram_bytes_mem_tagged_realtime
tpc__l1tex_sram_bytes_mem_untagged_realtime
tpc__l1tex_sram_bytes_mem_untagged_data_shared_realtime
tpc__l1tex_sram_bytes_mem_untagged_data_tram_realtime
```

这些是 L1TEX/shared/TRAM 的配置量，不是 RTCORE 私有缓存指标，也没有 `rtcore__` 对应版本。

## GCC、L2 和 DRAM 能看到什么

- `gcc__` 的 34 项指标把 L1.5 请求只分成 `constant`、`instruction`、`tsheader`，没有 RT/BVH/traversal 类型。
- `lts__` 的 source-unit 类别为 `ce/crop/gcc/pe/raster/tex/zrop`，没有 `rtcore`。可见的 RT 相关下游流量只能混在 L1TEX/GPC 或全局 L2 统计中。
- `dram__` 的 15 项指标只有全局 read/write bytes、sectors、cycles 和 throughput，没有 RT qualifier。

因此可以把 RT activity 与 L1TEX/L2/DRAM 流量做时间相关性分析，但无法仅凭这些 counter 把 RT 发起的流量从纹理、LSU 或其他 GPC 流量中严格分离，更不能从中直接计算私有 L0 容量。

## 管理员只读 query 与安全边界

真实设备 query 需要管理员权限，是因为本机 `RmProfilingAdminOnly=1`。管理员执行下面的命令只读取 counter catalog，不运行 workload，也不改变 GPU 配置：

```bash
sudo /usr/lib/nsight-compute/ncu --csv \
  --query-metrics \
  --query-metrics-mode base \
  --query-metrics-collection pmsampling \
  --devices 0 \
  | rg '^"rtcore__'
```

`sudo` 只绕过 `ERR_NVGPUCTRPERM`；它不会解锁另一个隐藏 metric catalog。本机管理员 query 仍没有 RT cache 指标。CUDA/range `profiling` catalog 中没有 `rtcore__`，PM-sampling catalog 仍只有上述 8 项。

不要为了本调查执行以下操作：

- 不要把 `RmProfilingAdminOnly`/`NVreg_RestrictProfilingToAdminUsers` 改为允许所有用户。
- 不要卸载或重载 NVIDIA 内核模块。
- 不要重启显示服务，不要锁频、改功耗或刷写 VBIOS。
- 不要访问未文档化的 MMIO/寄存器。

若以后只想做相关性采样，Nsight Compute 的 documented metric 语法是 `pmsampling:<metric>`。应显式使用 `--clock-control none --cache-control none --pm-sampling-max-passes 1 --disable-pm-warp-sampling`，并只对可信、极短的 RT workload 加 `timeout`。这仍然只能得到活动与共享路径的相关性，不能给出 RT 私有缓存容量。参见 [Nsight Compute CLI 的 PM Sampling 文档](https://docs.nvidia.com/nsight-compute/NsightComputeCli/index.html)。
