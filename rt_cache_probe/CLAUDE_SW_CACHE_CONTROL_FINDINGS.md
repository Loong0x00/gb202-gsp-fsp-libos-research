# RTX 5090 软件侧缓存控制面与 RT 数据路径交接

更新：2026-07-12  
设备：RTX 5090（GB202，CC 12.0），Driver 610.43.03，CUDA 13.3，OptiX 9.1，Nsight Compute 2026.2.1

本文保留 Claude 侧发现，并按后续独立复核重新标注证据等级。目标不是证明“存在缓存提示”，而是判断这些提示能否影响 **RT Core/TTU 对加速结构的读取**。

证据标签：

- **已验证**：本机命令、编译结果或 GPU 测量可复现。
- **强推断**：多个独立对照吻合，但没有地址标签或 NVIDIA 物理规格。
- **待验证**：目前只有工具链字符串、API 可能性或单方结果。
- **已纠正**：原表述超过证据范围。

---

## 1. 本机已验证的软件控制面

### 1.1 PTX/SASS 的 L1、L2 eviction hints

CUDA 13.3 `ptxas` 确实包含：

```text
L1::evict_first / evict_last / evict_normal / evict_unchanged / no_allocate
L2::evict_first / evict_last / evict_normal / evict_unchanged / no_allocate
```

Claude 侧还观察到 `CCTL.E.PF2`、`LDG.E.EF`、`LDG.E.LU` 与不同内存作用域的 `LDG` SASS 变体。

**纠正**：这些 L1/L2 qualifiers 在当前 PTX ISA 9.3 已公开，不属于只能靠 `strings` 才发现的隐藏接口。官方把它们定义成普通 global memory load/store 的 eviction-priority **性能提示**；这不证明它们能控制 TTU L0 或 TTU 的 backing 请求。

官方语义：<https://docs.nvidia.com/cuda/parallel-thread-execution/index.html#cache-eviction-priority-hints>

本机复核：

```sh
strings "$(command -v ptxas)" | grep -oE 'L[12]::[a-z_]+' | sort -u
```

### 1.2 L2 persisting access-policy 能力

本机 `cudaGetDeviceProperties` 与 `cudaDeviceGetLimit` 返回：

```text
L2 cache                         = 100663296 B = 96 MiB
persistingL2CacheMaxSize         =  62914560 B = 60 MiB
accessPolicyMaxWindowSize        = 134217728 B = 128 MiB
fresh-process current set-aside  =  18874368 B = 18 MiB
```

复现程序：[`scratchpad/cache_caps.cu`](scratchpad/cache_caps.cu)

**纠正**：`cudaAccessPropertyPersisting` 不是锁定或“钉死”。官方定义是更高的保留优先级；`hitRatio` 还是概率性分类，容量不足时仍会替换。严格用词应为 **persisting preference / L2 set-aside**。

官方语义：<https://docs.nvidia.com/cuda/cuda-programming-guide/04-special-topics/l2-cache-control.html>

Claude 报告的普通 CUDA load 对照为：32 MiB hot 数据配合 128 MiB streaming 压力，persisting 与 normal 为 4.79 ms 对 6.28 ms。这个结果方向合理，但原交接列出的 `l2persist.cu` 当前工作区不存在，因此 **+23.7% 尚未独立复核，不能作为本项目最终原始证据**。

### 1.3 TTU/RT Core 在工具链中的痕迹

本机复核通过：

```text
nvdisasm: EIATTR_RTCORE_ENTRY
libnvidia-ptxjitcompiler.so:
  [est ttu=%d]
  [ttu thru=%f]
```

这证明 NVIDIA 的内部编译/调度模型把 TTU 当作独立执行资源，并存在 RT Core entry 元数据。后续提取 OptiX disk-cache cubin 又确认：

- `optixTrace` 被拆为带 `.rt.info.callsite/liveState/callstack` 的 continuation states；
- current-hit `optixGetTriangleVertexData` 会生成连续的隐藏 `D0–D4` 128-bit opcode family；
- 九个 component-liveness 变体显示：`v0/v2` 单 bundle 时 D4 immediate=5，`v1`
  与所有双/多顶点组合为6；D2 slot `0x34/0x35` 对应两个结果 bundle candidate，
  `0x36` 是共同 finalize candidate；
- from-handle 与 `optixHitObjectGetTriangleVertexData` 都不在当前 entry 内联 D0–D4，
  而走普通 load/状态/helper 路径；
- `libnvidia-rtcore.so` 同时含 `nv.rt.ttu.trifetch` 与 `nv.rt.ttu.trifetch.with.flags`。

因此“TTU 只有一条指令”已经被否定。当前仍没有解出 cache-policy bit，也没有用户可直接发射的公开 PTX traversal 指令。完整证据见 [`OPTIX_JIT_REVERSE_FINDINGS.md`](OPTIX_JIT_REVERSE_FINDINGS.md)。

---

## 2. 当前 RT 缓存实测结论

### 2.1 Root / first-complet 路径：16-record 有效驻留域

直接独立 GAS、强制向包围盒外发射的单依赖追踪显示：

- K <= 16：unique 与 same-handle 等延迟。
- K = 17 起：稳态约 `+27 cycles/trace`。
- 每个推断 refill 伴随 `4 × 32 B` 的 L1TEX sector 增量。
- K17 的 shader long-scoreboard residual 折算约 `25.9156 warp-stall units/refill`。

严格结论：存在 **16-record root/first-complet 有效驻留边界**。约 2 KiB 是按 16×128 B backing event 推出的工作集尺度，不是 NVIDIA 公布的物理 SRAM 容量。

后续任意顺序 replacement scan 修正了prefix造成的LRU误判。prefix长度N的victim
确实为N，但这是因为最后命中 `A(N-1)`；单独refresh Ai时，16/16项都淘汰
`A(i+1 mod16)`。六种多次、重复和逆序序列跨4种layout/rotation的24/24插入控制
也只由最后命中的环后继决定，局部惩罚精确为27.0 cycles。因此真LRU被否定，当前
可观测语义是 **hit-updated circular successor**；物理实现仍可能是pointer、clock
或产生同一行为的PLRU状态机。见
[`RT_ROOT_REPLACEMENT_FINDINGS.md`](RT_ROOT_REPLACEMENT_FINDINGS.md)。

地址选择实验又覆盖192个仿射candidate序列，全部只在第16个evictor出现+27台阶；
四个16项集合逐成员删除得到64个15项子集，全部不淘汰且平台spread为0。因此所测
64-GAS root池支持16-entry effective fully-associative capacity，未发现E<16冲突集。

### 2.2 Hit/deeper-path：31-record 有效阈值

直接 GAS 命中与 miss 对差显示：

- K <= 31：每个 unique 对象只出现冷取事件。
- K >= 32：出现可重复的额外 4-sector 事件。
- K32 在连续、padding、物理置换和反向次序下保持相同整数关系。
- prime-hit 探针中，热点 A 穿过 K40 仍保持低延迟，排除普通 fully-associative LRU。

后续31+1逐victim把它收紧为明确的分配行为：前30个fill进入稳定位置，第31个fill
进入一个allocation-driven streaming slot；插入第32项只替换第31个fill。把fill
顺序改成sequential/reverse/permuted/Sattolo后，victim分别跟随最后fill的
`A30/A1/A4/A16`，相对前一fill均精确+27 cycles。填满后额外hit A0/A15/A29不移动
slot。这逐项解释旧公式每环恰好重取`K-30`条；仍不能把可观测“30+1”直接写成
物理30个锁定ways加一块RAM。见
[`PRIMITIVE_PATH_CACHE_FINDINGS.md`](PRIMITIVE_PATH_CACHE_FINDINGS.md)。

同一GAS内容判别随后又完成：一个GAS内64个空间target/128个triangle的单callsite
AB/BA paired replacement中，32 victims×3 paths×2 pair orders的median全部为0；
加256 KiB L1 trash后，四种fill order的`last-prev`最大绝对值仅5.25 cycles且不随
最后fill移动。把同一GAS进一步拆成64个独立triangle build input和64个SBT GAS
index后，plain完整扫描仍全0，L1-trash完整map也保持约±0--4.5 cycles。故31-record
层不是per-primitive/per-ray-path/per-geometry allocation；当前候选收紧为
GAS/AS-output-scoped record。进一步把同一次one-triangle build复制并relocate成
64个合法GAS handle后，四种fill order的hit-only victim又全部精确+27 cycles，
L1 trash放大到+501.75。相反，64个static-transform handle共享同一child GAS时，
plain/L1-trash/K64扫描均为null。故tag随relocated AS output身份改变，而不是随
builder内容、primitive或generic traversable handle改变；公开GAS handle、output
地址与内部descriptor仍未区分。见
[`SAME_GAS_PATH_CONTENT_FINDINGS.md`](SAME_GAS_PATH_CONTENT_FINDINGS.md)。

shared-child矩阵又补上IAS：64个独立一实例IAS共享同一two-triangle GAS时，最后fill
的gap为+27、leaf为+54，故leaf-gap再+27；四种fill order都移动到A30/A1/A4/A16，
前一fill全0。它显示IAS hit有两个同步31-class阶段，而static-transform wrapper全
flat。物理上仍可能是两套bank、multi-line bundle或parent-qualified child record。
见[`IAS_SHARED_CHILD_REPLACEMENT_FINDINGS.md`](IAS_SHARED_CHILD_REPLACEMENT_FINDINGS.md)。

**纠正**：目前应称为 **31-record-class AS-output/context-scoped hit/deeper residency stages**，不能直接命名为 raw triangle primitive cache。direct GAS暴露一阶段，IAS/shared-child暴露两个同步阶段；static transform不进入该已测域。relocation细节见[`RT_RELOCATION_CLONE_FINDINGS.md`](RT_RELOCATION_CLONE_FINDINGS.md)。

“约 4 KiB”同样只是 31×128 B backing-event 尺度；32 个物理槽加 reserved/fill/victim 槽是候选解释，不是已证规格。

### 2.3 IAS → GAS：9/17 阈值与 sector 方程已闭合

`IU = K independent IAS -> K independent GAS` 命中路径在 K=9 与 K=17 精确跳阶：

```text
K <= 8 : 无稳态 refill
K = 9  : 每 trace 2 个 4-sector event，约 +54 cycles
K = 17 : 每 trace 4 个 4-sector event，约 +108 cycles
```

固定构建 64 个物理 IAS/GAS、Sattolo 与 sequential 两种次序都复现。单-pass NCU 的 unique−same sector 差与整数模型逐项相等：

| K | 实测 total-sector delta | 模型 |
|---:|---:|---:|
| 8 | 112 | `16×(8−1)` |
| 9 | 78,392 | `16×(9−1)+2×4×(N−9)` |
| 16 | 139,376 | `16×(16−1)+2×4×(N−16)` |
| 17 | 295,920 | `16×(17−1)+4×4×(N−17)` |

`N=K×1088`。所以这是四个 **L1TEX 可见、参与替换的 128 B event**：两个进入约 16-record 域，两个进入约 32-record 域。

### 2.4 地址干预把 IAS/GAS 与四个 event 对上

L2 persisting marker 现在可只覆盖 IAS、只覆盖 GAS 或顺序覆盖两者。K=64 `IU hit` 的三进程中位数：

| 保护范围 | cycles/trace | recovery |
|---|---:|---:|
| normal | 10593.17 | 0 |
| GAS | 9371.89 | 1221.28 |
| IAS | 8773.23 | 1819.94 |
| IAS+GAS | 7546.27 | 3046.91 |

两个单独 recovery 之和与联合结果只差 5.69 cycles（0.19%）。逐 128 B IAS 扫描和 raw dump 给出：

```text
IAS +0x000  header/decode                  # 额外 L2 line
IAS +0x700  root node / first-complet      # 16-domain candidate
IAS +0x600  instance leaf + transform      # 32-domain candidate
GAS +0x380  child root node                # 16-domain candidate
GAS +0x400  triangle primitive data        # 32-domain candidate
```

IAS `+0x600` 中的 packed child pointer 直接等于 GAS `output+0x380` root 地址。这样后四条正好解释两组 16/32 event；IAS header 是第五条可归因 L2 backing line，但不进入所测 L1TEX replacement 方程。

完整报告：[`IAS_GAS_HIERARCHY_FINDINGS.md`](IAS_GAS_HIERARCHY_FINDINGS.md)、[`IAS_GAS_BACKING_LINE_FINDINGS.md`](IAS_GAS_BACKING_LINE_FINDINGS.md)。

### 2.5 SM ownership：不是严格 per-SM，而是双-SM可见域

同一 OptiX launch 内的 P/Q 握手实验按实际 `%smid` 分类，不预设 `smid/2=TPC`。
matched A/C prime 控制在四组 SM 上得到：

```text
same SM                         warm benefit 约 1.0--1.2k cycles
{0,1},{2,3},{22,23},{44,45}    双向约 0.46--0.50k cycles
0->22、23->44 等跨组           约 0
```

普通 global-load 预热也能贡献部分局部性，因此又加入 P/Q 各自不重叠的 256 KiB
`L1::evict_last` pressure。多数运行中，普通 GAS backing-load 的双端 trash A/C 差
回到约 0，而 trace prime 仍保留约 `0.42--0.47k cycles` 的 paired-SM收益。

严格结论是 **two-SM RT traversal residency domain（TPC candidate）**。它证明
可观察状态的共享域，不证明单份物理 cache，也不能把 16×128 B 直接写成“每 TPC
2 KiB SRAM”。完整方法、异常值与 raw CSV 见
[`RT_CACHE_OWNERSHIP_FINDINGS.md`](RT_CACHE_OWNERSHIP_FINDINGS.md)。

v11 又把 Q unique scrub 扫成1--62。三个 paired 域在 `S<=15` 都保持约
`-0.48k cycles`，`S=16` 正反control order同时归零；cross-domain 全程约零。
所以远端 A 会参与 Q 所见的同一16-entry effective replacement budget。它仍可能
由共享、迁移或复制实现，不能单凭曲线命名物理data array。

---

## 3. 哪些控制能影响 RT

| 控制面 | 普通 CUDA load | RT L0 | RT 的 L1TEX/L2 backing | 当前结论 |
|---|---:|---:|---:|---|
| `.ca/.cg/.cs/.lu` | 是 | 无公开证据 | 无公开证据 | 不能直接套到 TTU |
| `L1::evict_*` | 是，hint | 无公开接口 | 未知 | 工具链存在不等于 TTU 接受 |
| `L2::evict_*` / `createpolicy` | 是，hint | 否 | 未知 | 需 RT 实验 |
| stream access-policy window | 是 | 否 | **已测** | TTU 自身不继承；CUDA persisting pre-touch 可间接保护 RT backing |
| preferred shared/L1 carveout | CUDA kernel hint | 否 | 未知且用户难以绑定 OptiX JIT kernel | 低优先级 |
| ray/instance/handle 排序与 AS 布局 | 间接 | **是** | 是 | 已由 16/31 与 prime-hit 行为证明工作集次序重要 |

**纠正**：“L0 手动优化不了”不准确。当前没有发现直接控制 opcode，但软件可以通过 ray sorting、handle 分组、instance grouping、AS 布局和相干性显著改变 L0 命中率。

`cudaFuncAttributePreferredSharedMemoryCarveout` 也不能简单解释成“shared 用得少，OptiX 就获得全部 128 KiB L1”。它是 kernel 级偏好提示；OptiX JIT raygen 没有向应用公开可供 `cudaFuncSetAttribute` 使用的 CUDA function handle。物理统一池、CUDA shared 上限与实测有效 L1 容量不能直接相加对账。

---

## 4. L2 persisting → RT 实验已经完成

完整报告：[`L2_PERSIST_RT_FINDINGS.md`](L2_PERSIST_RT_FINDINGS.md)

核心结果：

```text
forced-root miss, K=64, cycles/trace

warm / no thrash                   5214.59
192 MiB thrash + normal            6766.95
192 MiB thrash + persist on RT     6772.34   <- TTU 自己不认
CUDA normal pre-read + thrash      6774.64   <- 预读本身无效
CUDA persist mark, reset, thrash   6765.97   <- 去掉priority后无效
CUDA persist mark + thrash         5561.33   <- 有效，-17.82%
```

容量扫描在 `thrash <= 96 MiB` 时所有策略都保持 warm；从 112 MiB 起 normal 与 TTU self-persist 一起跳到 DRAM 平台，只有 CUDA persisting pre-mark 保持 L2 平台。五个独立进程完全复现。

结论：

- **TTU/RT Core 的 AS 请求不继承 CUDA stream access-policy，或使用自己的固定 request priority。**
- **CUDA kernel 可以先读取 GAS output、把对应行标成 persisting，从而间接保护给后续 RT traversal 使用。**
- 这是已实测的软件侧 RT backing 控制面；仍是 eviction preference，不是锁定。

逐 128 B marker 扫描还定位了 one-triangle GAS 的热行：

```text
GAS handle = output + 12

output + 0       traversable/start-header line
output + 896     root/first-complet line
output + 1024    triangle primitive-data line
```

forced-outside path只需要前两行；triangle hit精确再增加第三行。连续标记 1/2/3 行时延逐级下降，标记完整 2560 B GAS 不再带来额外收益。

GAS byte dump 的 header 还直接包含相对 offset `0x380` 与 `0x400`；对应行分别包含 node/AABB 数据和 triangle vertex 编码，所以语义不再只依赖 timing 猜测。

IAS/GAS 分解进一步得到：

```text
IU miss: 保护 GAS 无效；保护 IAS 恢复约 1.22k cycles
IU hit : GAS 恢复约 1.22k；IAS 恢复约 1.82k；联合恢复约 3.05k
```

IAS stride 为 2048 B。miss 只需要 `+0x000/+0x700`，hit 精确增加 `+0x600`；三条各约 0.61k cycles。raw IAS dump 显示 handle=`output+4`，`+0x600` 含 transform/child-root pointer，`+0x700` 含 root/AABB node。

公开 L2/DRAM device-scope counter 对这个短 launch 有背景污染；L1TEX 单-pass在所有策略中固定 `2133 hit + 378 miss sectors`，证明 marker 没有改变上游 RT 请求数，而是改变下游 residency。

### 其他待办

1. 继续差分已经提取的 OptiX JIT cubin，解码 TTU D0–D4 的 dispatch/wait/result 字段与 RTCORE entry metadata。
2. 把root层已得到的circular-successor测试扩展到并发rays和pending grouping；物理
   pointer/clock/PLRU电路仍未区分。
3. 将64-GAS池的等效全相联结果扩展到不同AS类型、build flags和更大地址跨度；
   当前192+64控制已经排除所测池内的E<16 set conflict。
4. 在不同 driver/build flags/compaction/geometry type 下重复 AS line mapping，区分稳定结构与当前布局偶然性。

---

## 5. 当前文件索引

- 总体发现：[`FINDINGS_5090_RT_CACHE.md`](FINDINGS_5090_RT_CACHE.md)
- hit/deeper-path：[`PRIMITIVE_PATH_CACHE_FINDINGS.md`](PRIMITIVE_PATH_CACHE_FINDINGS.md)
- counter 证据：[`RT_PIPELINE_COUNTER_FINDINGS.md`](RT_PIPELINE_COUNTER_FINDINGS.md)
- 独立 counter 审计：[`new_counter_audit.md`](new_counter_audit.md)
- 官方架构/专利来源：[`rt_arch_sources.md`](rt_arch_sources.md)
- IAS/GAS 探针：[`experiments/ias_root_probe`](experiments/ias_root_probe)
- 本机缓存能力查询：[`scratchpad/cache_caps.cu`](scratchpad/cache_caps.cu)
- L2 persisting → RT：[`L2_PERSIST_RT_FINDINGS.md`](L2_PERSIST_RT_FINDINGS.md)
- OptiX JIT / TTU 逆向：[`OPTIX_JIT_REVERSE_FINDINGS.md`](OPTIX_JIT_REVERSE_FINDINGS.md)
- IAS→GAS 四记录方程：[`IAS_GAS_HIERARCHY_FINDINGS.md`](IAS_GAS_HIERARCHY_FINDINGS.md)
- IAS/GAS 地址域与五条 backing line：[`IAS_GAS_BACKING_LINE_FINDINGS.md`](IAS_GAS_BACKING_LINE_FINDINGS.md)
- SM ownership：[`RT_CACHE_OWNERSHIP_FINDINGS.md`](RT_CACHE_OWNERSHIP_FINDINGS.md)
- root replacement：[`RT_ROOT_REPLACEMENT_FINDINGS.md`](RT_ROOT_REPLACEMENT_FINDINGS.md)
- 当前架构地图：[`RT_5090_ARCHITECTURE_MAP.md`](RT_5090_ARCHITECTURE_MAP.md)
