# RTX 5090 新 RT counter 结果独立审计

日期：2026-07-11  
范围：审计新得到的 hit-path sector、L1TEX SRAM1 和 SMSP stall 差分。  
约束：本轮只读取源码、已有结果和离线 metric catalog，**没有运行 GPU**。

## 审计结论

| 命题 | 数学审计 | metric/source 审计 |
|---|---|---|
| hit-only 差分在 K=31/32 出现第二个 residency 阈值 | **成立，整数关系精确** | 后续same-GAS 1/64-input paired已排除per-primitive/path/geometry allocation；当前称traversable/GAS-scoped hit/deeper signal |
| K>=32 总数精确拟合“首环K次、随后每环`K-30`次” | **成立；时序为模型推断** | 与普通 fully-associative LRU 不相容；不唯一决定 victim/bypass/set 电路 |
| SRAM1 差分可拆成 root-associated + hit-path-associated 两项 | **三点逐整数成立** | 是跨 counter 的强守恒检查；`cmd_read` 是 active cycle，不是带地址的 line-read command |
| long-scoreboard residual 给出约 25.9/trace 的 K17 额外等待 | **归一化成立** | 强支持 shader warp 等待 RT 结果；不是 NVIDIA 正式的 cache-miss latency counter |
| MIO residual 为 28/op，unique=same、ring=0 | **成立** | 是 `optixTrace`-correlated MIO throttle signal；不能直接叫 query submit latency |

总体判断：新结果的**整数守恒非常强**，足以升级为“第二个、只在 hit/deeper
traversal 路径出现的 31-record 有效驻留阈值”和“root refill 会增加约 26 个
shader-warp 等待单位”。但 counter 没有公开 source/address qualifier，因而
`primitive`、`root`、`128B line`、`submit` 都应继续作为行为名称或候选解释，
不能当成芯片正式模块名。

## 一、证据与 provenance 边界

本轮检查了：

- [`PRIMITIVE_PATH_CACHE_FINDINGS.md`](PRIMITIVE_PATH_CACHE_FINDINGS.md)
- [`RT_PIPELINE_COUNTER_FINDINGS.md`](RT_PIPELINE_COUNTER_FINDINGS.md)
- [`RT_RESEARCH_MATRIX.md`](RT_RESEARCH_MATRIX.md)
- [`agent_optix/minimal/sweep_device.cu`](agent_optix/minimal/sweep_device.cu)
- [`agent_optix/minimal/gas_sweep.cpp`](agent_optix/minimal/gas_sweep.cpp)
- [`l1tex_injection_summary.tsv`](l1tex_injection_summary.tsv)

源码确认每个 K 的 profiler 覆盖操作数为：

```text
N(K) = K * (warmup_rounds + samples * rounds)
     = K * (64 + 1 * 1024)
     = 1088 K
```

Sattolo/反向序列每 K 次操作走完一个完整环；warmup 与 measured loop 连续，故总计
正好有 1088 个完整工作集环。第一环之外还有 `1087` 个环，这正是新公式中的
1087 来源，不是拟合参数。

审计时没有找到新 hit-sector、K32 SRAM 或 stall 批次的原始 `.ncu-rep`/完整 TSV；
它们目前只保存在上述派生 Markdown 中。现有 TSV 只保存了 K16/K17 forced-miss 的
request/SRAM 摘要。因此本报告能独立验证**算术、源码操作数和 metric 语义**，但
不能从原始 report 再核验每条新命令的 pass 数、raw integer、cache-control 参数和
NCU warning。正式归档应补一份 raw table，避免让派生报告成为唯一数据源。

## 二、primitive/hit-path 差分的数学审计

定义：

```text
H_u(K) = unique-GAS guaranteed-hit 的 L1 total sectors
M_u(K) = unique-GAS forced-miss 的 L1 total sectors
H_s(K) = same-handle guaranteed-hit 的 L1 total sectors
M_s(K) = same-handle forced-miss 的 L1 total sectors
N      = 1088K
```

给定 same-handle 在 K=16、17、32、64 都逐整数满足：

```text
H_s - M_s = 7N + 4
```

其中 `7N` 确实是每 trace 固定的 hit-vs-miss L1TEX traffic；`+4` 是每 launch
一次性的 4-sector hit-path 冷事件候选。

报告定义：

```text
P(K) = H_u - M_u - 7N
```

这个定义在算术上没有问题，但要注意它**不是纯 unique-minus-same residual**：

```text
P(K) = [(H_u - M_u) - (H_s - M_s)] + 4
```

因此：

```text
P/4             = 包含 same-handle 那一次冷事件的总 4-sector event-equivalents
(P-4)/4         = 相对 same-handle 的纯 unique hit-path excess
```

“P/4=K”可解释为 K 条 distinct hit-path record 各冷取一次，但前提是 same-control
的那 4 sectors 与其余事件属于同一 record class。aggregate counter 没有地址，
所以这仍是最简解释，而非 counter 自带的 source 标签。

### 复算表

| K | N | `7N+4` same baseline | P sectors | P/4 | 纯 unique excess `(P-4)/4` |
|---:|---:|---:|---:|---:|---:|
| 16 | 17,408 | 121,860 | 64 | 16 | 15 |
| 17 | 18,496 | 129,476 | 68 | 17 | 16 |
| 31 | 33,728 | 236,100 | 124 | 31 | 30 |
| 32 | 34,816 | 243,716 | 8,824 | 2,206 | 2,205 |
| 33 | 35,904 | 251,332 | 13,176 | 3,294 | 3,293 |
| 36 | 39,168 | 274,180 | 26,232 | 6,558 | 6,557 |
| 40 | 43,520 | 304,644 | 43,640 | 10,910 | 10,909 |
| 48 | 52,224 | 365,572 | 78,456 | 19,614 | 19,613 |
| 64 | 69,632 | 487,428 | 148,088 | 37,022 | 37,021 |

所有给定点都精确满足：

```text
K <= 31: P/4 = K

K >= 32: P/4 = K + (K-30)*1087
```

后一个式子可作如下精确整数分解：

```text
第一完整环：K 个 4-sector 冷事件
其后 1087 个完整环：每环 K-30 个 4-sector 事件
```

它与“首环每成员一次冷事件，随后每环只有30个成员命中、`K-30` 个重取”的模型
完全吻合。注意 aggregate counter 没有逐环时间戳，所以它不能单独证明这些事件
在时间上恰好按这一方式分布；`首环 + 1087稳态环` 是由循环结构、cold-control和
跨K精确系数共同支持的最简时序解释，不是counter直接输出的event trace。

### 容量与 replacement 能说到哪里

数据直接支持：

- 此访问族可完整驻留 31 条 unique hit-path records；
- 第 32 条使 replacement/allocate policy 进入另一工作区；
- 在上述最简时序模型中，溢出态每环稳定 hit 数为30，而非普通
  fully-associative LRU的0；
- contiguous/padded/permuted/separate+reverse 在 K32 都得到相同总数，显著削弱
  简单 stride、allocator 低位和单一顺序 conflict。

数据尚不能唯一选择：

- 30 条 protected + 1 victim slot；
- 31 条容量加 streaming bypass；
- type-partitioned ways 或保留 slot；
- 某种 set conflict/pseudo-LRU/allocate-on-return；
- 32 个物理槽中有一个保留或被其他不可见 record 占用。

所以推荐写“31-record **有效阈值**”或“在该序列下 K=31 可完全驻留”，不要写
“物理 data RAM 正好 31 lines”。Prime-A 在 K40 仍存活只证明 A 属于受保护/稳定
集合；在显式 probe 两个 overflow members 前，不能宣布固定 victim 的身份。

## 三、这是不是 primitive cache

它是一个强的 **hit-specific/deeper-traversal residency signal**，但当前 hit 与 miss
路径同时改变了多件事：

```text
forced miss:     -Z，通常在 start/root bounds 外终止，执行 miss program
guaranteed hit:  +Z，进入 leaf/triangle 路径，执行 closest-hit program
```

P 的 residual 可能来自：

- leaf/complet 或 geometry descriptor；
- compressed triangle/primitive record；
- deeper BVH node/path record；
- traversal front-end/translation record；
- hitgroup/SBT 数据被 unique AS traffic 间接驱逐后重读；
- hit path 特有的 stack/payload/runtime data traffic。

所有 GAS 共用一个 hitgroup SBT record，所以“K 条独立 SBT record”不是合适解释；
但 shared SBT line 的间接 eviction 仍未被 counter 地址排除。每个 GAS 是独立 build、
独立一三角形输入及独立 output，因而 leaf、geometry descriptor 与 triangle record
完全共变。多 allocation layout 只测试地址/顺序，不拆开这些内容变量。

另外，root 在 K17 已持续 refill，而 P 仍只冷取17次，强烈排除了“所有 record
共享同一个未分区的16-entry fully-associative pool”。它支持独立的 residency
budget/replacement class；仍可能是同一物理 cache 的 type-partitioned ways，而不必
是第二块独立 SRAM。

当前最稳妥命名：

> 31-record hit-path/leaf-primitive-path residency layer candidate。

后续同一固定GAS、多target triangle与paired parent-gap/hit实验已经完成。单callsite
AB/BA控制中，32 victims×3 paths×2 pair orders的median全部为0；L1-trash四种fill
order也没有随最后fill移动。因此升级为raw triangle primitive cache的必要条件没有
满足，反而排除了per-primitive/per-path allocation。64个独立build input/SBT GAS
index复测也保持null，当前剩余候选是traversable/GAS handle、output/header descriptor
或融合记录；详见
[`SAME_GAS_PATH_CONTENT_FINDINGS.md`](SAME_GAS_PATH_CONTENT_FINDINGS.md)。

## 四、SRAM1 守恒关系审计

令：

```text
A(K) = SRAM1_read_active_cycles(unique_hit)
     - SRAM1_read_active_cycles(same_hit)
```

根据 forced-miss root signal 和上节的纯 unique hit-path excess：

| K | A 实测 | root-associated excess | hit-path excess | 和 |
|---:|---:|---:|---:|---:|
| 16 | 30 | `K-1 = 15` | `(P-4)/4 = 15` | 30 |
| 17 | 18,511 | `N-1 = 18,495` | `(P-4)/4 = 16` | 18,511 |
| 32 | 37,020 | `N-1 = 34,815` | `(P-4)/4 = 2,205` | 37,020 |

三点逐整数守恒，不是近似。它说明在这个单线程串行 workload 中：每一个由 sector
差分推断出的 root-associated 或 hit-path-associated 4-sector event，恰好伴随
一个额外 `array_1_cmd_read active cycle`。K17 和 K32 同时覆盖 cold-only 与 steady
replacement 两种状态，因此一致性很强。

但 metric 的正式定义是：

```text
l1tex__sram_cycles_array_1_cmd_read
= # of cycles where L1TEX SRAM read array 1 was active
```

所以它不是：

- read-command count；
- cache-line count；
- 读取 bytes；
- sector 地址或 tag；
- RTCORE 私有 SRAM counter。

单依赖链降低了同周期多客户端重叠，使“一事件一 active cycle”成为很强的受控
解释；换成多 warp 后 active-cycle counter 会饱和/重叠，不能继续按事件相加。

本机 GB20x 配置说明 tagged memory 从 ordinary L1TEX SRAM1 末端向下增长，因此
结果强支持 backing lookup 确实激活**普通 tagged L1TEX array1**。它不证明上层
RT residency structure 自身存放在 SRAM1，也不独立证明四个 sectors 是同一条
连续128B line。root/primitive 两个分量的名称来自 mode 差分，不是 SRAM counter
给出的 source qualifier。

## 五、`l1tex__t_requests` 的解释必须收紧

现有摘要为：

```text
                 K16       K17
unique miss      599051    636491
same-handle      599051    636491
```

所以“root residency miss 没有增加 `l1tex__t_requests.sum`”在所给数字中成立。
但它**不推出**“RT traffic 必然在 request counter 之后注入”，理由有两个：

1. 官方数量关系是 `request : sectors = 1 : N`。相同数量的 T-stage requests 可以
   在 L0 hit/miss 状态下携带不同 sector 数；不需要增加 request count。
2. [`l1tex_injection_summary.tsv`](l1tex_injection_summary.tsv) 记录该 request 值来自
   **4 passes**，而 sector/SRAM 核心关系是 one-pass。即使 raw request 值在两组
   逐整数相同，采集 provenance 仍弱于 one-pass 守恒。

因此允许的结论是：

> 新增4-sector lookups没有对应的新增公开 T-stage request count。

不应直接写：

> 已证明 RT refill 在 T-request 计数点之后进入。

要升级，需单独请求 `l1tex__t_requests.sum`、关闭 extra suffixes并确认 NCU 报告
one pass；再同时检查 `pipe_lsu`/`pipe_tex` qualifiers。即便 one-pass 仍相同，
也只能在结合 qualifier residual 后讨论 bypass/injection point。

## 六、long-scoreboard 差分审计

定义：

```text
L = smsp__warps_issue_stalled_long_scoreboard.sum
  - smsp__warps_issue_stalled_long_scoreboard_pipe_l1tex.sum
```

qualified counter 的 catalog 描述包含 `non-RTCORE L1TEX`，所以 L 是当前最好的
RT-associated wait residual；但 catalog 没有正式声明 generic 恰好只由
`non-RT + RT` 两项构成。

K17：

```text
unique forced-miss : 225.0309 / op
same forced-miss   : 199.1167 / op
net                :  25.9142 / op
```

用 N17=18,496 复算，四位小数与约 479,309 个净 warp-stall units 相容。unique
相对 same 有 `N-1=18,495` 次 steady root refill，因此每实际 refill 为：

```text
~479309 / 18495 = 25.9156 warp-stall units
```

K16 的 0.9087/op 差分则约对应 15 次额外冷 root，摊到每次约 1,054.6 stall
units；冷态显著更慢与 L2/DRAM 路径相容。

这组数据强支持：

- raygen warp 的 RT-result dependency 在 root residency miss 时多等待约26个
  `gpc_cycle*warp` 单位；
- K17 的延迟台阶不是只有 L1 traffic 相关性，而有 shader-side waiting 响应；
- cold fill 与 steady L1-backed refill 是不同延迟级别。

不能把它形式化等同于：

- `clock64()` 的26个周期；
- RT Core 内部执行周期；
- cache tag lookup 本身的 latency；
- 单个正式命名为 root/complet 的硬件事件。

该 counter 是所有 SMSP instances 的 Context-scope warp-cycle roll-up。当前只有一个
shader warp，所以数值接近周期是合理的；多 warp 时会求和并重叠，per-trace 数值
不会保持。

## 七、MIO throttle 差分审计

定义：

```text
T = smsp__warps_issue_stalled_mio_throttle.sum
  - smsp__warps_issue_stalled_mio_throttle_pipe_mio.sum
```

K17 给定结果：

```text
unique forced-miss = 28 * N
same forced-miss   = 28 * N
ring-only          = 0
```

N17=18,496，所以 residual 为 517,888，算术精确。它严格跟随“是否执行
`optixTrace`”，但不响应 unique root cache overflow。因此它是很好的
`RT-trace-correlated MIO throttle residual`。

metric 的正式语义是 warp 在等待 MIO instruction queue free entry；所以 `28`
代表累计 warp-stall units，不是 issued-query count，也不自动等于 query submit
latency。它可能是 RT submit pipe、固定 dispatch/handoff、或 generic 与
`non-RTCORE pipe_mio` qualifier 覆盖差。ring=0 和 unique=same 显著缩小了候选，
但还应补 guaranteed-hit 与不同 payload/SBT 的 trace 控制，才能把它从“trace
公共成本”进一步定位为“提交端”。

## 八、其余可能的 counter source 混淆

1. **Hit 与 miss 不只差 primitive。** 两者射线方向、BVH 深度、miss/closest-hit
   program、SBT路径和payload返回都不同；`7N` same-control 扣掉固定公共差，但
   unique AS traffic 仍可能间接驱逐 shared hit-path data。
2. **Sector counter 没有地址。** 4 sectors 是128B traffic-equivalent，不形式化
   证明同一128B line；SRAM1 active-cycle守恒显著加强单次访问解释，但仍无tag。
3. **Unique 与 same 使用两个 table allocations。** P 的 hit-minus-miss在各自同一
   table内做，取消得较好；SRAM的 unique-minus-same会跨 `entries` 和
   `same_entries` 两个地址。相同访问形状与精确守恒使 table伪影不太可能，但最强
   控制应在同一 table 中忽略loaded handle并强制handle0。
4. **Root/primitive 是行为标签。** SRAM和sector metric都不带source qualifier；
   精确分解说明两类mode residual守恒，不表示counter识别出了两种record。
5. **同一物理bank仍可能分区。** K17 root thrash不驱逐hit-path records；后续root
   任意refresh又显示16-entry circular-successor而非LRU。两者排除简单共享同一
   replacement域，但不排除同一RAM的type-partition、reserved ways或独立tags。
6. **多布局只反证地址伪影。** 它不区分leaf/complet、geometry descriptor、triangle
   record和translation，因为这些仍随每个独立GAS一起变化。
7. **独立进程/replay状态。** hit、miss、same、unique多数是分开NCU命令；整数关系
   很难由噪声偶然产生，但正式数据表仍应记录每个run seed、raw values、passes和
   profiler options。

## 九、建议采用的结论措辞

推荐：

> 在 RTX 5090 的独立一三角形 GAS probe 中，hit/deeper-traversal 路径出现第二个
> 31-record 有效驻留阈值。K<=31时P/4总事件数精确等于K，与每条distinct record
> 一次冷取且随后驻留的模型一致；K>=32时总数精确符合“首环K次、随后每环K-30次”
> 的分解，显示非普通LRU的
> replacement/streaming行为。对应事件与ordinary L1TEX SRAM1 read-active cycle
> 逐整数守恒。另有RT-associated long-scoreboard residual在16-entry root路径
> 溢出时增加约25.9 warp-stall units/refill，而MIO residual固定为28/op且与cache
> 状态无关。

暂不推荐：

> 已证明每SM有31×128B primitive SRAM、每次RT提交固定花28 cycles。

后一句跨越了 record内容、连续line、物理bytes、replacement、ownership 和 metric
unit/source 六个尚未完成的证明环节。

## 十、最小后续验证

不扩大实验规模也能显著提高可信度的三项：

1. 保存所有新批次的 raw TSV/NCU report，并让 request 与每对 stall counters明确
   one-pass；
2. 用同一 `GasRingEntry` table 做 unique/same handle选择，消除跨table SRAM差分；
3. 固定一个 GAS，使用多 target hit 与 paired parent-gap ray，确认31阈值随
   primitive/leaf target而不是起始GAS变化。

官方 metric 数量语义参考：
[NVIDIA Nsight Compute Profiling Guide](https://docs.nvidia.com/nsight-compute/ProfilingGuide/index.html)。
