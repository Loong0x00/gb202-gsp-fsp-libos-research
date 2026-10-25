# GB202 WORKLOAD_COMBINED_2X 控制逻辑复原状态（2026-07-28）

## 当前结论

研究目标不是穷举整个 GSP/PMU，而是闭合 RTX 5090 在重负载下出现
`SW Power Cap`、频率约 2.8--3.0 GHz、板卡功耗仍低于 800 W 的那条控制链。

目前已经完整复原并逐行验证了两路动态功耗预测器。它不是一个根据过去若干采样直接外推下一时刻
板卡功耗的简单控制器，而是一个模型驱动的候选频率搜索器：每轮读取两路 workload，针对每个候选
频点取得相应电压，分别估算 NVVDD 与 MSVDD 功耗，再选择估算总值不超过内部核心预算的最高频点。

当前完整链条为：

```text
TOTAL_GPU 上游预算 - PROP/MISC 当前消耗
  -> WORKLOAD_COMBINED_2X.CurrLimit
  -> keyed limit arbiter
  -> 可选历史平滑与上下比例钳位
  -> 当前 evaluator budget (object+0x34)
  -> 两路 workload 滤波
  -> 离散候选频率/电压搜索
  -> NVVDD 与 MSVDD 模型估算之和
  -> 最高满足 estimated <= budget 的候选
  -> 非对称 Q12 目标追踪
  -> PERF_LIMIT_PMU_DOM_GRP_1 (0x43)
  -> GPC/XBAR 时钟传播与最终仲裁
```

## 位精确复现的动态功耗公式

R570 GB202 明文 PMU 中的关键地址：

| 地址 | 作用 |
|---|---|
| `0x202a817e` | WORKLOAD_COMBINED_2X 候选搜索 |
| `0x202ac6ae` | 两路 physical branch 求值 |
| `0x202a72fe` | type-5 电流曲线 `V^p` |
| `0x202a7312` | type-5 功率曲线 `V^(p+1)` |
| `0x202b4c96` | 无符号定点乘法 |
| `0x202b4c5e` | 有符号定点乘法包装 |
| `0x202b4ea4` | Q12 对数近似 |
| `0x202b4e00` | Q12 指数近似 |
| `0x202b4f94` | Q12 幂函数 |

当前 RTX 5090 的两条 type-5 equation 都给出：

```text
pQ12 = 5324
p = 5324 / 4096 = 1.2998046875
```

对 mW 预算，每个分支的动态项按如下整数顺序计算：

```text
voltQ12          = round_nearest(voltage_mV * 4096 / 1000)
currentFactorQ12 = powQ12(voltQ12, 5324)                 # 约 V^1.2998
powerFactorQ12   = mulQ12(voltQ12, currentFactorQ12)     # 约 V^2.2998

dynamic_mW =
    (workloadQ12 * powerFactorQ12 * candidateFreqMHz * 1000) >> 24

physical_mW = leakage_mW + dynamic_mW
logical_mW  = physical0_mW + physical1_mW
```

这里的 `powQ12` 不是宿主机浮点 `pow()`。它先用有理近似算 Q12 `ln(x)`，乘 Q12 指数，再通过
一个 14 项整数指数表与 8 阶迭代算 `exp()`；乘法和倒数都有固件自己的舍入规则。

完整整数重放器：

```text
power_governor_reverse/replay_combined2x_q12.py
```

## 运行时验证

重放器已经对三组不同负载日志执行：

| 负载 | 行数 | branch 0 误差 | branch 1 误差 | logical 误差 |
|---|---:|---:|---:|---:|
| Cyberpunk 2077，PT 关闭 | 512 | 0 mW | 0 mW | 0 mW |
| Cyberpunk 2077，PT 开启 | 622 | 0 mW | 0 mW | 0 mW |
| FurMark Vulkan | 252 | 0 mW | 0 mW | 0 mW |

这证明以下内容已经闭合，不再是回归猜测：

- 两路输入字段的单位；
- type-5 指数；
- 电压归一化；
- Q12 对数、指数、幂和乘法的舍入；
- 动态项的乘除顺序；
- 漏电项与动态项的相加位置；
- 两路 physical 值汇总为 logical 值的方式。

## PT 开关对模型的影响

PT 关闭后，`WORKLOAD_COMBINED_2X` 仍然是主动限制源，且同样使用两路模型。

稳态均值对比：

| 项目 | PT 关闭 | PT 开启 |
|---|---:|---:|
| 内部 CurrLimit | 407.516 W | 400.869 W |
| 实际两路总功耗 | 343.622 W | 354.472 W |
| 模型估算总功耗 | 388.918 W | 389.592 W |
| branch 1 估算/实际 | 1.495x | 1.429x |

因此目前可以排除“固件识别到 RT/PT 后套一个固定降频倍率”。即使关闭 PT，branch 1 仍被显著
高估，甚至相对误差稍大。限制来自一般性的 NVVDD/MSVDD 双支路模型、候选电压和 workload，而不是
一个 PT 专用开关。

## 漏电模型：候选路径不使用 residency 修正

`0x202ac6ae` 调用 leakage equation 时的实参已经由 RISC-V 调用点闭合：

```text
a0 = relationship / equation object
a1 = candidate voltage in uV
a2 = limit unit (mW or mA)
a3 = NULL
a4 = physical-branch output state
```

type-7 evaluator 会先执行完整 type-4 leakage 公式；只有 `a3 != NULL` 时，才额外读取两个 runtime
residency 指标并使用 `fsEff/pgEff` 衰减结果。候选搜索明确传入 `a3 = NULL`，所以这两个 residency
指标和 efficiency 字段不参与 WORKLOAD_COMBINED_2X 的候选漏电估算。

这消除了一个此前的未知项：为了复现本控制器，不需要先识别 type-7 的两个 residency 指标正式字段名。

基础漏电公式的整数形状为：

```text
vRatioQ12 = round_nearest(round_nearest(candidate_uV / 1000) * 4096
                          / reference_voltage)
vFactor   = powQ12(vRatioQ12, k_voltage)
tFactor   = powQ12(k_temperature_base,
                   (k_temperature_offset + temperature) * 16)
leakage   = mulQ12(base_leakage, mulQ12(vFactor, tFactor))

if unit == mW:
    leakage = floor_or_saturate(leakage_current * candidate_uV / 1_000_000)
```

构造器 `0x202f252a/0x202f2560/0x202f2596/0x202f2634` 已把 A616 公共记录到 PMU
私有对象的字段映射闭合：

```text
public +0x06 u16 -> object +0x04 Q12 final scale
public +0x08 u16 -> object +0x06 secondary base field（本路径未读取）
public +0x0c s32 -> object +0x08 reference voltage
public +0x10 s32 -> object +0x0c voltage exponent
public +0x14 s32 -> object +0x10 temperature base
public +0x18 s32 -> object +0x14 temperature offset
public +0x1c u8  -> object +0x18 calibration power-channel index
public +0x1d u8  -> object +0x19 runtime temperature-channel index
public +0x20 u16 -> object +0x20 fsEff
public +0x22 u16 -> object +0x22 pgEff
```

因此此前把 `+0x06/+0x08` 称为 `fsEff/pgEff` 是错误的。当前两条 type-7 记录的
final scale 分别是 3971 与 3527；真正的 `(fsEff, pgEff)` 分别是 `(4096, 778)` 与
`(0, 0)`。候选搜索传入 `residency=NULL`，所以真正的 efficiency 字段仍不参与
WORKLOAD_COMBINED_2X 候选漏电估算。

两条记录的 calibration channel 分别是 3 与 7，runtime temperature channel 都是 1。
`0x202f2596` 在构造时通过 `0x202b718c(channel, 0, &value)` 读取一次 calibration channel，
把结果固定保存到私有对象 `+0x1c`；运行时 `0x202b5218` 则按 channel 1 重新读取温度。

当前 A612 配置已经把这些通道定名：

```text
channel 3 = INPUT_TOTAL_CORE
channel 7 = INPUT_MISC0
```

二者不是额外的独立板载电流表，而是由 `INPUT_TOTAL_BOARD` 按固定 Q12 比例拆分：

```text
INPUT_TOTAL_CORE = TOTAL_BOARD * 2540 / 4096
INPUT_MISC0       = TOTAL_BOARD * 1556 / 4096
```

因此两者之和仍是 TOTAL_BOARD。type-7 构造器在初始化时各采一次并冻结为两路 leakage
calibration scalar；这会让漏电模型基准带有启动时采样状态，而不只是 VBIOS 静态常量。

temperature channel 1 也已经由既有 raw capture 闭合为 `GPU_AVG/edge`。私有
`0x2080853b ThermalChannelGetStatus` 中该值位于 `0x28 + 1*0x38 + 4 = 0x64`，格式是有符号
Q24.8；公开 Thermal Execute V2 只返回整数 edge 温度，精度不足以进行逐点位精确漏电回放。

## keyed limit 的 GSP 导出证据

R610 的 `0x2080a620`（参数大小 `0x8398`）能够正常导出 policy-index limit-arbitration
配置。既有成功抓取在 `+0x5bcc` 与 `+0x5d50` 附近显示两组 8-entry 表；每组均含
policy index `2/7/8/9` 及其 `0x10000 | index` 编码变体；它们不能与 PMU
keyed arbiter 中的 8-bit source key 混为一谈。第一组对应值为 `450000/45000`，
第二组为 `600000/60000`。`600000/60000` 与 Astral 已知的 600 W/60 A
上界精确对应；`450000/45000` 也按相同比例出现，但其是否就是 75%
可调下界仍待结构或调用点闭合。这些数值属于静态 policy-limit 配置，不应
直接等同于运行时约 400--500 W 的最终 evaluator budget。

`0x2080a61f` 用全零两个输入直接查询时返回 `NV_ERR_NOT_SUPPORTED (0x56)`；这只能排除
“零参数即可枚举”的用法。GSP handler 静态审计显示它先访问 A620 大结构的 `+0x5290`
子区域，再执行第二阶段查询，说明其 8-byte 输入是选择器而不是一个独立的全量 dump ABI。

## 已闭合与尚未闭合

## 2026-07-28：有限 DRAM MAX 导致的反馈环已闭合

通过 R610 的 `0x2080e0af` 将 `0x75`（DRAM MAX）和 `0x78`（DRAM MIN）分开提交后，
已经证明性能下降只由 MAX 一侧触发。最关键的 15000 对照中，两边实际 MCLK 都是约
15001 MHz；MIN-only 时 XBAR/SYS 为 2356/2332 MHz，MAX-only 时降为 1494/1501 MHz，
branch-1 实际电压从约 967 mV 降为 870 mV。

但候选搜索仍按约 2553 MHz / 1091 mV 求值 branch 1。workload 生成器把低实际频压下的观测功耗
归一化后，branch-1 workload 从约 257 上升到 369；该 workload 再用于高候选频压，令 branch-1
估算从约 188 W 上升到 275 W，最终压低 DG0/GPC 目标并让 600 W 上限下的整卡只使用约 414 W。

16000 MAX 在实际 MCLK 仍为约 15001 MHz 时复现同一坏状态，证明触发条件是“存在有限 MAX”，
而不是实际跑到了哪个显存频率。14000 MAX 又将 XBAR/SYS 进一步降至 1440/1239 MHz，证明 MAX
数值还参与动态传播。

最后一个因果缺口已经用直接 XBAR 对照补上。同一 FurMark Vulkan 负载中：

| 输入 | branch-1 实际 MHz / mV | workload | branch-1 估算 | DG0 |
|---|---:|---:|---:|---:|
| 无临时限制 | 2129.6 / 888.6 | 325.9 | 166.6 W | 2379.1 MHz |
| MCLK MAX 16000 | 1498.2 / 870.0 | 526.2 | 234.1 W | 3018.9 MHz |
| XBAR MAX 1493 | 1492.3 / 870.0 | 522.4 | 233.8 W | 3021.8 MHz |

也就是说，非约束性的 MCLK MAX 和直接 XBAR MAX 不只是跑分相似，而是把关键内部变量带入了
同一个下游状态。结合 topology ID 7 的 type-5 `MCLK <-> XBAR` 共享 rail 关系，以及同代
RM/MODS 中已经恢复的“源频率端点 -> 共享 rail 电压端点 -> 目标频率端点 -> 求交/量化”算法，
现在可以闭合为：有限 MCLK MAX 被当成跨域 XBAR/rail 上限传播；实际 branch-1 频压下降后，
workload 归一化和更高候选频压求值之间出现错配，随后由 WORKLOAD_COMBINED_2X 改变核心目标。

FurMark 中这一耦合反而把核心从约 2.35 GHz 推到约 2.96 GHz，而 PT 中它会降低核心目标并空置
功耗预算。这进一步证明它不是一个简单的“锁显存必然降性能”规则，而是同一个跨域状态扰乱了
依负载组成而变号的闭环控制器。

活动 topology 始终为 ID 7；其中 relation 4/5 分别是 rail 1 上的双向 type-5
`MCLK <-> XBAR` 与 `MCLK <-> SYS`。公开 control/status 对象在加入 MAX 前后不变，所以不是切换
topology 或重写静态配置，而是现有 topology 内的动态 range/arbitration 结果。

完整证据、数值和 `PROVED/INFERENCE/UNKNOWN` 边界见：

```text
power_governor_reverse/MEMORY_MAX_FEEDBACK_CLOSURE_20260728.md
```

### 已闭合

- 20 ms 左右的采样/求值周期；
- 两路功率观测、workload 生成与滤波路径；
- 两路候选功耗求值的全部整数数学；
- 候选搜索以 `estimated <= CurrLimit` 为接受条件；
- 候选结果的 Q12 升降目标平滑；
- GPC 到 XBAR 的固定传播比例 `0xe660 / 65536 = 0.89990234375`；
- 动态限制源 `0x43 PERF_LIMIT_PMU_DOM_GRP_1`；
- 有限 DRAM MAX `0x75` 是显存锁定性能下降的触发端，DRAM MIN `0x78` 不是；
- MAX 状态下 branch-1 的实际 870 mV / 1.44--1.49 GHz 与候选约 1.1 V / 2.56 GHz 发生错配，
  经 workload 归一化和候选求值形成高估反馈环；
- 16000 非约束 MAX 仍复现，排除了实际 MCLK 频率本身；
- MCLK MAX 16000 与直接 XBAR MAX 1493 在同一负载下产生相同的 1.49 GHz / 870 mV branch-1
  状态以及近乎相同的 workload、估算功耗和 DG0，补上了 XBAR 状态的必要因果对照；
- 同代 type-5 代码的完整端点变换顺序已经恢复：源频率范围经 FREQ_TO_VOLT 转成共享 rail
  电压范围，再经 VOLT_TO_FREQ 转成目标域频率范围并求交/量化；
- 本次 A620 抓取对应 Astral 原厂 BIOS 的 600 W 板卡上限；它与约
  400--500 W 的运行时内部核心模型预算是两层不同约束。此前写成
  800 W 是混入了更早 Lightning BIOS 的状态，现已更正。

### 尚未闭合

- 上游 keyed limit 的全部来源键、优先级及每种状态的条件表；
- 构造时从 power channel 3/7 采样后固定保存的两个 leakage 基准量的精确运行值；通道身份与
  固定拆分关系已经闭合，只差同一启动周期的实际采样数值；
- 候选搜索中频点索引表与 V/F 表的全部映射字段名；
- `0x43` 与其他温度、电压、可靠性限制进入最终时钟仲裁时的完整优先/合并顺序；
- R610 私有对象中保存 rail-1 动态传播上限的确切字段；
- R610 中执行 type-5 范围转换的确切私有函数；
- R610 加密 PMU 是否对同一 R570 算法增加了结构外修正。现有 R610 运行时三组日志与 R570 算法
  位精确一致，至少证明本次动态求值核心未出现可观察差异。

## 下一步

1. 拆出 A620 子对象的实际 method 实现，将两组 8-entry 导出表定名为确切的
   policy-limit 上/下界结构；同时单独追 PMU keyed arbiter 的真正 8-bit source key，
   继续找运行时约 400--500 W 的胜出输入。
2. 用同步的 A619 dynamic model 与 channel-1 Q24.8 温度反求 channel 3/7 的构造期 leakage
   基准量，并逐点位精确回放 leakage；
   residency 路径不参与本控制器，暂不作为前置条件。
3. 把频点索引、候选电压选择和最终 `0x43` 仲裁展开成可执行状态机。
4. 用现有日志回放完整候选搜索，目标是同时逐点复现 `estimated power` 与 `DG0/cap_freq`。
