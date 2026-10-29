# Same-GAS RT structure probe

这是 Batch A 的独立 OptiX 9.1 微基准。它没有修改
`agent_optix/minimal`，也不会调用 `optixInvoke()`。

## 当前实现

- 一个固定 GAS，包含 8×8 个空间分离 tile；
- 每个 tile 有左右两个小三角形，中间留 gap，共 64 targets / 128 triangles；
- `--build-inputs 1|64`在同一GAS内切换单一或每target独立triangle build input；
  64-input模式同时使用64个SBT GAS index并验证其命中结果；
- `--handle-layout relocated --geometry-layout single-triangle`只build一次，再生成64个
  documented relocation clone；所有逻辑target使用同一ray/primitive/SBT，仅handle不同；
- `--handle-layout static-transforms`生成64个identity transform wrapper，全部共享同一
  child GAS，用作generic traversable handle与AS-output identity的反证；
- `--handle-layout ias-shared-child`生成64个独立一实例IAS并共享child GAS；配合
  `--geometry-layout double-triangle`用gap/leaf分离IAS的两个31-class阶段；
- 192 个 `RaySpec`：
  - `outside_root`：从 `z=0` 沿 `-Z`，预期 miss；
  - `root_gap`：沿 `+Z` 穿过 tile 中央空隙，预期 miss；
  - `leaf_hit`：沿 `+Z` 命中该 tile 左三角形，验证 primitive index `2*target`；
- 正式 device path 使用 `optixTraverse()`，只查询 outgoing hit object，绝不
  `optixInvoke()`；
- prime A → K−1 targets → 单独计时 probe A；
- `same_target` 与 `unique_target` 成对；unique members 从其余63个 targets中按 seed抽取；
- 指定victim replacement：32-target scrub、31-target可控fill、X31 insert与等长control；
- `replace-paired`在同一动态循环/计时调用点交替执行control→insert与
  insert→control，避免模板callsite和跨launch伪差；
- 支持sequential/reverse/permuted/Sattolo fill order及可选256 KiB
  `L1::evict_last`敏感性检查；
- 每个 probe 输出 raw `clock64` cycles、起止 `%smid`、hit/primitive/instance/SBT、
  checksum和累计validation error；paired模式另存`control_cycles`与`pair_order`；
- device 端另行输出 `optixGetGASPointerFromHandle()`，调用发生在所有 timing 结束后；
- OptiX correctness validation默认开启。

## 构建

构建只运行 CMake、NVCC 和主机编译器，不初始化 GPU：

```sh
cmake -S . -B build -G Ninja -DOPTIX_COMPUTE_ARCH=compute_120
cmake --build build -j 2
```

构建、correctness smoke、K=64扫描和paired replacement均已在本机执行。

## GPU correctness smoke

以下命令留给主调查线程审核后执行：

```sh
./build/rt_structure_probe \
  --max-k 2 --samples 2 --warmup 2 \
  --path all --working-set both --validation all \
  --output results/smoke.csv
```

正式 timing 应关闭 validation，并优先 one-K-per-process：

```sh
./build/rt_structure_probe \
  --max-k 17 --only-k 16 --samples 64 --warmup 8 \
  --path gap --working-set unique --validation off \
  --output results/gap_unique_k16.csv

./build/rt_structure_probe \
  --max-k 17 --only-k 17 --samples 64 --warmup 8 \
  --path gap --working-set unique --validation off \
  --output results/gap_unique_k17.csv
```

`--only-k` 很重要：它让 NCU counter 分母与被测 K 完全对应，也避免把同一 launch
内的多个 K 当成独立 run。完整 sweep仍可用于筛查：

```sh
./build/rt_structure_probe --max-k 32 --samples 32 --warmup 4 \
  --path all --working-set both --validation off \
  --output results/sweep_k32.csv
```

正式同一GAS replacement：

```sh
./build/rt_structure_probe \
  --build-inputs 64 --sequence replace-paired --replacement-scrub-passes 4 \
  --samples 64 --warmup 8 --path all --validation off \
  --output results/replacement_paired.csv

# 指定victim并放大普通L1 backing差异
./build/rt_structure_probe \
  --sequence replace-paired --replacement-victim 30 \
  --replacement-scrub-passes 4 --replacement-l1-trash \
  --order sequential --samples 48 --warmup 8 \
  --path all --validation off --timeout-ms 10000 \
  --output results/replacement_paired_trash_v30.csv
```

正式结果见仓库根目录
[`SAME_GAS_PATH_CONTENT_FINDINGS.md`](../../SAME_GAS_PATH_CONTENT_FINDINGS.md)和
[`RT_RELOCATION_CLONE_FINDINGS.md`](../../RT_RELOCATION_CLONE_FINDINGS.md)、
[`IAS_SHARED_CHILD_REPLACEMENT_FINDINGS.md`](../../IAS_SHARED_CHILD_REPLACEMENT_FINDINGS.md)。

Relocation clone复现：

```sh
./build/rt_structure_probe \
  --handle-layout relocated --geometry-layout single-triangle \
  --sequence replace-paired --replacement-scrub-passes 4 \
  --samples 64 --warmup 8 --path all --validation off \
  --output results/relocated_single_triangle.csv
```

Static-transform共享child反证只需把`--handle-layout relocated`改为
`--handle-layout static-transforms`。

## 安全边界

- 单 launch硬上限 2,000,000 次 traversal；
- `max-k=64`、`samples=256`、warmup=64；
- 10s watchdog，默认2s；超时只退出进程，不 reset GPU；
- accounted VRAM 必须同时小于64MiB和启动时空闲显存1%；
- OptiX disk compilation cache关闭；
- 不锁频，不改 power/ECC/persistence/fan/driver/module；
- 输出记录 GPU、SM数、L2、shared/SM、clock attribute、CUDA/OptiX版本、
  GAS output VA/handle/device pointer、build sizes、seed和精确 trace count。

若使用 Nsight Compute，保持：

```text
--clock-control none --cache-control none
```

核心 L1TEX hit/miss metrics应继续放在已验证的单 pass 组合里。

## 已知限制

1. OptiX builder不公开 BVH。`root_gap` 是输入几何上的中央空隙，不能只凭命名断言
   它访问了某个特定 interior complet；必须用 cold sectors/cycles 与 outside/hit作差确认。
2. 64 targets共用同一个 GAS handle。因此该程序测的是 same-GAS target/path residency，
   不复测此前的 distinct-GAS 16-entry基线。
3. hit probe 的 timed region包含 hit-object query与 checksum；same/unique同路径比较仍同构，
   但绝对 cycles不是裸 RT 指令延迟。
4. `unique_target` 的 K 行使用独立随机 subset；target A始终为0。因此K扫描只作筛查，
   record内容结论使用指定victim paired replacement。
5. 完整 K sweep在同一 launch内按升序执行；每个 K 有显式 warmup。正式结论仍应使用
   `--only-k` 的独立进程。
6. 1-input与64-input/SBT-index paired均为null，排除了per-primitive/path/geometry
   allocation；仍不能区分公开GAS handle、output/header地址与内部融合descriptor。
7. 当前没有自动温度/功耗读取；执行前后应由主调查脚本只读记录 `nvidia-smi`。

## 文件

- `structure_params.h`：host/device ABI、`RaySpec` 和 raw record；
- `structure_device.cu`：`optixTraverse` sequence与correctness检查；
- `structure_probe.cpp`：固定GAS构建、options/safety、pipeline、CSV输出；
- `CMakeLists.txt`：独立 OptiX IR和host target。
