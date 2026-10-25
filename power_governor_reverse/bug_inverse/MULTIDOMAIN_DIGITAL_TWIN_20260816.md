# GB202 多域控制逻辑数字孪生 — 2026-08-16

## 当前产物

`algorithm/gpu_inverse/digital_twin.py` 已把现有证据组合成一个可执行、可反事实求解的多域状态机：

```text
GPC/XBAR/SYS/NVD 各自 127 点 F(V) bank + 用户 offset/range
  -> 75-node VFE graph + 167-entry VF-tuple selector（当前仅诊断，不驱动输出）
  -> WORKLOAD_COMBINED_2X 候选搜索（位精确 Q12 动态功耗）
  -> DG0 状态/filter
  -> GPC 最终 max/min/PERF 仲裁
  -> GPC→XBAR type-3（当前 R610 精确倒数 + GB202 R570 PMU half-up 乘法）
  -> 目标时钟域方向性频点归一化（forward down / reverse up，当前参数显式化）
  -> 当前 top ID 7 路径图：GPC→XBAR→SYS/NVD 逐 relation 遍历
  -> MCLK/XBAR/SYS type-5 双端点 F→V→F 共享轨区间约束
  -> 各域 V/F 请求
  -> NVVDD/MSVDD 轨内 10-slot mode/offset 仲裁（相等时高 ID 胜）
  -> GSP 整数 grid 向上量化与 rail min/max clamp
  -> 各域可实现频率与各自时钟网格
  -> PMU 物理 divider 投影与逆算 readback（当前主域有效比率 15/2）
  -> 当前 CLK_DOMAIN_GET_INFO 支持列表的 floor/ceil bracket 诊断
```

模型配置直接引用当前 610.57.04 上恢复的四个 STATUS bank：

- `domain_rail_probe_20260816/gpc-post.csv`
- `domain_rail_probe_20260816/xbar-post.csv`
- `domain_rail_probe_20260816/sys-post.csv`
- `domain_rail_probe_20260816/nvd-post.csv`

配置中的最终频率近似仍保留既有 GPC 15 MHz grid；XBAR/SYS/NVD 不被强行套用同一
grid。另一个独立且已直接读回的观测面是当前固件公开支持列表：GPC/XBAR/SYS/NVD/PWR
严格满足 `15+floor(i*15/2)`，所以整数 MHz 相邻差为 7/8。它们仍进入 trace 的
floor/ceil bracket；此外，当前 R610 serializer `0x0112d0ac` 已证明同一 row 的
`+0x21/+0x22/+0x24/+0x3e` 被送到 PMU wire `+0x05/+0x0a/+0x0c/+0x25`，与明文 R570
PMU physical-grid importer 的位置完全一致。因此主域有效 15/2 现在也用于最后的
divider/readback 投影。仍未声称每条加密 R610 仲裁路径或实现体与 R570 字节相同。

这张表现在也不再只是经验公式：R610 静态路径从 domain 的 inclusive clock-program range
进入 program mode-2，再枚举 clock-table row 的 inclusive divider range；底层逐点执行
`floor(numerator*divider/denominator)`。`divider=2..466` 与最简有效比率 `15/2`
逐点重放 GPC/XBAR 的 465 项。位精确实现位于 `algorithm/gpu_inverse/clock_program.py`。
live row 原始字段仍未知，所以只声称约分后的有效比率，不猜字段的共同倍数。直接
`15/(1*2)` 与 doubled-input `15/(1*1)` 两种可能表示已对 0..3999 MHz 逐整数穷举，
divider/readback 完全一致；因此共同倍数/scale 表示不再影响当前主域输出。

MCLK、PCIE 和两个 API 域的稀疏表也已完整物化；证据和复现见
`../GSP_61057_CLK_DOMAIN_READBACK_20260816.md`。

## XBAR 不同 offset 为什么会得到相同结果

当前 PTX 边界条件为 GPC source 3000 MHz、ratio 1.000、MSVDD 最大 1065 mV。当前 XBAR bank 在 1065 mV 处的基准频率是 2572 MHz，因此静态上包络为：

```text
XBAR_final <= min(GPC_source * ratio, F_xbar(1065 mV) + XBAR_offset)
```

| XBAR offset | 模型上包络 | compute 样本数/平均 XBAR | decisive constraint |
|---:|---:|---:|---|
| +330 MHz | 2902 MHz | 23 / 2900.630 MHz | MSVDD V/F ceiling |
| +360 MHz | 2932 MHz | 23 / 2931.078 MHz | MSVDD V/F ceiling |
| +390 MHz | 2962 MHz | 23 / 2961.374 MHz | MSVDD V/F ceiling |
| +420 MHz | 2992 MHz | 23 / 2992.052 MHz | MSVDD V/F ceiling |
| +430 MHz | 3000 MHz | 23 / 2991.430 MHz | GPC→XBAR ratio ceiling |
| +440 MHz | 3000 MHz | 41 / 3000.092 MHz | GPC→XBAR ratio ceiling |

前四点预测与实测误差均不超过 1.5 MHz。到 +430 后，V/F 可供频率超过 1:1 source
ceiling，+430 与 +440 因而落入同一个静态输出等价类。+430 的短样本均值低于包络而
+440 贴近包络；这说明静态上限与瞬时 source GPC/DG0/功率/采样状态仍需分层，不能反过来
把静态上限改成某次短采样均值。

这也解释了为什么“同一最终 XBAR”不保证内部状态相同：若两个 offset 在不同 V/F 点达到
同一传播上限，MSVDD winner、SYS/NVD 可用频率和功率估算仍可能不同。每域
`decision_certificate` 会列出全部 constraint candidate 的 before/after/changed、
`winner_chain` 与最终 decisive constraint；`compare` 同时显示 clock equality 和隐藏
rail/binding 差异。原始 CSV 统计与模型证书固定在
`algorithm/artifacts/ptx_xbar_boundary_certificate_20260816.json`，测试会重新读取六个
`hardware-clocks.csv` 并复算，而非只相信文档中的数字。

## 最初选择的 GPC 为什么不是最终频率

状态机保留每一层的不同名字，不把它们压成一个 `GPU clock`：

```text
curve/request candidate
  -> power-policy candidate / DG0
  -> client max/min
  -> PERF limits
  -> rail V/F ceiling
  -> hardware clock grid
  -> final measured GPC
```

自带示例中，功率搜索选择 3330 MHz，而 `GPC max=2992` 在下游胜出，最后物化为 2985 MHz bin。trace 会同时报告：

- `stages.power_policy.chosen_gpc_mhz = 3330`
- `stages.post_client_limits_mhz.gpc = 2992`
- `outputs.clock_mhz.gpc = 2985`
- `winner_chain = [user_gpc_max, clock_grid_quantization]`
- `decisive_constraint = clock_grid_quantization`

固件中还存在另一个离散化位置：GB202 R570 PMU 的 type-3 evaluator 先按
`(freq * ratio + 0x8000) >> 16` 做 half-up，再让目标 domain 对象按传播方向选
不高于/不低于输入的可表示频点。这说明“关系传播值”和“最终 GPC/XBAR/SYS 实频”本来就
不是同一个状态。当前 R610 row-to-PMU 字段桥和主域有效 15/2 已恢复，所以默认运行会在
所有 rail/VF/关系约束之后执行物理 divider 投影，并在 certificate 中列出 divider 与逆算
MHz。未约分字段、object-local source grid 和 MMIO lane 仍保持显式未知；公开支持列表也
继续单独报告 bracket，不把“列表包含该点”偷换成“全部当前加密路径已证明”。

V/F relation 自身的选点也已从 R570 明文 PMU 恢复。`0x202c5b28 -> 0x202c5c76`
返回 `{u16 MHz, u32 voltage}`；`0x202c52d2` 做 frequency→voltage，`0x202c50a4`
做 voltage→frequency。两者不是线性扫描，而是 `mid=(lo+hi+1)>>1` 的上中位数二分，
并在区间边界额外求值相邻点。模型的 `vf_relation_search.py` 现已逐次记录 lo/hi/mid、比较
方向、相邻点与 clamp edge，`VFCurve` 也改用该算法。这个结论只覆盖同代 group `0x0b`
relation 搜索，不冒充当前 R610 新增 group `0x11` 的 tuple 状态机；逐地址证据见
`../R570_PMU_VF_RELATION_SEARCH_20260816.md`。

另有一个初选后的 domain-frequency 改写层：R570 `0x202c2c28` 对 u16 MHz 应用
signed-kHz/1000 或 signed-Q12 调整，随后先窄化为 s16、再把负值夹到 0；
`0x202c4786` 遍历活动域，每次变化后通过 `0x202c3e6e` 重新走 VF relation 投影。
`domain_adjustment.py` 已位精确复刻这个内核和循环。由于当前 R610 对象的 group flag、
调整类型和值尚未 readback，默认配置不启用这个阶段；其存在证明“初选”和“后来实频”之间
还有合法的固件改写层，但不能把未知对象假设成某次观测差值。详见
`../R570_PMU_DOMAIN_ADJUSTMENT_20260816.md`。

同代 R570.151 MODS 的 `0x072f6370` 又以 x86-64 独立实现了完全相同的两种算术和
s16/负数边界，错误文本直接称其为 `Clock Domain offset`；上层 `0x06ddb4c0` 同样只在
调整值相对原始值发生变化后重走量化。另一方面，`CLK_DOMAIN_35_PROG_CLIENT_FREQ_DELTA_ADJ`
位于另一条 RPC/频率列表路径，因此目前只把该层命名为 clock-domain adjustment，不擅自把
每个压缩对象分别归属为 Factory OC 或用户 offset。

PMU `0x202c8fde` 还固定了四级次序：group `+0x38` → owner `+0x3c/+0x44` →
owner `+0x80` → peer `+0x3c`；`0x202c904a` 的 mode 1 执行完整四级，mode 2 先执行
owner 两级，并可对 type 6/7 解析出的 linked object 再执行完整四级。该顺序已进入
`domain_adjustment.py`，包括一个证明 literal/Q12 不可交换的反例；当前 R610 对象值未知，
所以仍只作为独立可执行内核，不接入默认输出。

关系聚合也不是一个含糊的“依次 clamp”。`0x202c40f6` 让每个活动 relation 从同一个
原始频率独立生成候选，再取最小；相等候选由后扫描 relation 获胜。`0x202c3fbe` 对各活动
域的 terminal upper bound 也取最小，但严格小于才换 winner，因此相等时保留先扫描者。
`0x202c3c4e/0x202c3d5e` 则把内部 `0x41` 当成“已命中边界”并转成 public success。
这些规则已在 `relation_arbitration.py` 中单独复刻和测试。

另一个独立维度是电压请求在哪一层选点。配置支持 `pre_power_requested`、`post_client_limits`、`final` 三种竞争顺序；相同 2985 MHz 最终 GPC 可以对应不同 NVVDD。当前 GSP 的 10-slot 整数算法已经静态恢复，但没有当前 boot 的 live slot/base/delta dump，因此 request stage 和当前 winner 不会被伪装成唯一已知答案。

当前 R610 的同步读回纠正了一个跨快照误判。在 thermal channel 1 = 30.47265625 C
时，用 relation STATUS → 五个 V/F bank point126 → relation STATUS 做只读夹读，前后状态
稳定，GPC/NVD/SYS/PWR/XBAR 都精确相等：3270/2715/2842/2302/2812 MHz。此前约
29.5 C 的顺序读回也给出五域端点一致：3270/2730/2857/2302/2827 MHz。因此在这两个
观测状态里，type-9 relation current MHz 是当前 effective bank endpoint 的精确摘要；尚未
证明所有 P-state/转场都保持该别名关系。

早先保存的 GPC CSV 是另一控制器快照：base/effective=3225/3337 MHz、total offset=
112 MHz；后来同步读回的 GPC endpoint=3270 MHz、total offset=45 MHz。两者相差 67 MHz，
但不能当作同一周期的后级 component。模型现在把稀疏 relation 观测和旧 curve CSV 明确
隔离。频率仍可能在 power candidate、client/keyed limit、传播、rail V/F ceiling、domain
grid 与 P-state/context 阶段发生变化；这里只撤销了无效的跨快照分解。

## 温度如何改变 VF relation

当前公开对象已经重建为 75 个 VFE 节点、21 条 sum/product 边和七组 VF tuple bank，
覆盖全部 18 个 VF relation、167 个有意义 tuple。关系与主要域精确映射为：rel13=GPC、
rel14=NVD、rel15=SYS、rel16=PWR、rel17=XBAR；rel0..7 是八个 API40 频率键，rel8..12
是五个 MCLK 频率键。

一次无主动 workload 的自然温升给出了判别性运行时证据：channel 1 从 29.39..29.63 C
跨到 30.99609375 C 时，NVD/SYS/PWR/XBAR tuple 分别从 46/67/88/109 变为
47/68/89/110。NVD、SYS、XBAR relation 频率同时各降 15 MHz，PWR 保持 2302 MHz；
这与 tuple 中直接读出的 30 C Q8.8 边界一致。

随后一次读回中，全部依赖私有 VFE43 的 type-7 relation 又一起从 130/151 前进到
131/152。虽然公开 channel 5 仍返回 255 C unavailable sentinel，tuple interval 已把当时的
VFE43 限定到 30..35 C；模型保留这个区间证据，不伪造一个精确内部温度。

`stages.vfe_tuple_selection` 会输出每个 relation 的 required VFE、候选 tuple、当前状态、
选择原因和与 firmware readback 的逐 relation 对照。对于已实测 tuple，它还输出稀疏的
relation-stage MHz 绑定；未见过的 tuple 不做插值/外推，尤其 PWR 88→89 都是 2302 MHz，
已经否定了“所有 bank 每前进一步必减 15 MHz”。当前 CONTROL 也已证实与自动 STATUS
选择分离：18 个 CONTROL record 全是默认 override/sentinel，而 STATUS `+6` 持续给出活动
tuple。

静态边界进一步闭合为 PMU CLK unit：VF relation 是 group `0x0b`，tuple 是可选 group
`0x11`。GB202 R570 明文 PMU 的 CLK dispatch table 有 `0x0b` 且与 host 的
`0x2610b0 / 0x30 / 0x80` identity 位精确对应，但没有 `0x11`。所以当前 R610 tuple
evaluator 不能用 R570 的相似代码冒名替代。它仍是
`diagnostic_only_not_connected_to_clock_or_voltage_outputs`：当前 PMU 的 product rounding、
温度过滤/采样时刻和共享边界 tie-break 尚未恢复，不能让一个合理猜测反过来污染已经确认的
时钟/电压输出。完整 ABI 与证据边界见
`../GSP_61057_VFE_TUPLE_MODEL_20260816.md`。

R610 GSP 的 ownership 也更明确：type-9 constructor 沿用 vtable `+0x20` 的
`0x0111b738`，该函数从 PMU BoardObj STATUS 搬运八个 u16 live 字段；随后
`0x0111b07c/0x0111e408` 才把它们打包为公开 STATUS。因此 current MHz、ordinal、tuple
不是公开 GET handler 现场算出的，而是 PMU 已经决策后的状态回传。

## XBAR、SYS 与共享 MSVDD

四 bank 的 rail-adoption 实验已经确认：

```text
GPC  -> NVVDD
XBAR -> MSVDD
SYS  -> MSVDD
NVD  -> MSVDD
```

当前默认配置只把已静态/运行时支持的 GPC、XBAR 当作主动 V/F request producer；SYS/NVD 作为共享 MSVDD 的 consumer。改变 winning MSVDD 会同时改变 SYS/NVD 可实现频率。SYS/NVD 是否在特定状态下另有主动 request client 仍未直接观测，因此没有强行加入 max-arbiter。

MCLK 是 5 点 frequency-indexed bank，不能套用 127 点 F(V) 记录。本轮只读 STATUS 已恢复：

| MCLK | shared-rail source voltage |
|---:|---:|
| 405 MHz | 530 mV |
| 810 MHz | 555 mV |
| 7001 MHz | 650 mV |
| 13801 MHz | 715 mV |
| 15001 MHz | 715 mV |

因此提供 `clock_max_mhz.mclk` 时，模型现在会自动执行 `MCLK [Fmin,Fmax] -> [Vmin,Vmax] -> XBAR/SYS [Fmin,Fmax]`，再对目标上下端点分别 clamp。普通时钟域的 kHz 输入先做 `min=floor(kHz/1000)`、`max=ceil(kHz/1000)`。例如 16000 MHz finite MAX 超出最高点，按端点饱和到 715 mV，再把当前 610.57 bank 的 XBAR/SYS 上限变成 1455/1462 MHz。历史 610.43 实测约为 1493/1501 MHz，差约一个小 bin；这是跨驱动/VBIOS 状态差异，当前没有用隐藏修正项强行抹平。若需要直接注入尚未观测的 range 状态，可同时使用 `propagated_rail1_min_mv` 和 `propagated_rail1_max_mv`。

## 运行

目录：`power_governor_reverse/bug_inverse/algorithm/`

```bash
PYTHONPATH=. python multidomain_twin.py simulate \
  --config configs/gb202_61057_observed.json \
  --scenario examples/furmark_ratio_scenario.json \
  --control examples/control_xbar450_ratio1.json \
  --candidate-table --output /tmp/gb202-sim.json

PYTHONPATH=. python multidomain_twin.py compare \
  --config configs/gb202_61057_observed.json \
  --scenario examples/furmark_ratio_scenario.json \
  --control-a examples/control_xbar450_ratio1.json \
  --control-b examples/control_xbar500_ratio1.json \
  --output /tmp/gb202-compare.json

PYTHONPATH=. python multidomain_twin.py solve \
  --config configs/gb202_61057_observed.json \
  --scenario examples/ptx_xbar_boundary_scenario.json \
  --grid examples/ptx_xbar_solver_grid.json \
  --output /tmp/gb202-solve.json
```

求解器只接受 `verified: true` 的离散轴；不可行结论严格限定于当前参数化模型和枚举域，不声称物理上全局不可能。它还会输出产生同一 clock+rail signature 的控制等价类。
每个候选解都携带逐域决策证书，所以同一等价类可以继续按“由哪条约束折叠”分类，而不只
比较最终 MHz。

## 验证

```bash
cd /home/user/rt_5090_project/power_governor_reverse/bug_inverse/algorithm
PYTHONPATH=. python -m unittest discover -s tests -v

cd ..
PYTHONPATH=algorithm python -m pytest -q \
  algorithm/tests data_pipeline/tests test_catalog_runs.py
```

当前 algorithm 层 `unittest discover` 为 154 项；连同 data-pipeline/catalog
回归的完整 pytest 为 164 项。覆盖旧数据管线/四模型/
求解器、真实 GPC/XBAR/SYS/NVD/MCLK bank、当前 R610 `0x0800/0x1000` Q12 scale、
九域公开频率列表、clock-program mode 0/1/2 与 mode-2 divider 精确 465 点重放、两个
XBAR offset 的传播压缩、逐域 winner certificate、六个原始 PTX CSV 的统计重算、DG0 与
最终 GPC 分层、共享 MSVDD、三种电压决策顺序、当前 R610 type-3 比率/倒数、GB202
R570 PMU half-up 与方向性 domain-grid、非对称 Q12 tracker、top-7 path walker、type-5
双端点、75-node VFE graph、全部 relation tuple bank、30 C tuple 转场、稳定性硬约束、
Q12 功耗逐 mW、DG0 稀疏采样不可辨识，以及 10-slot 电压仲裁。

## DG0：当前 Q12 系数已读回，额外门控仍保持显式未知

数字孪生的 DG0 状态现在用 GB202 R570 PMU `0x202a817e` 的 U16-Q12
`clkUpScale/clkDownScale` 算术；trace 分别保留 `raw_candidate_gpc_mhz`、Q12 direction/
delta/rounded-step、`dg0_gpc_mhz` 和最终 GPC。可选 dwell/hysteresis 是另行标记的模型层，
不是冒充固件已证实字段。当前 GSP `0x017a0d38` 已将对象 `+0x390/+0x392`
导出到 status record `+0x16/+0x18`；policy 0/10/16 各三轮只读值一致为
`clkUpScale=0x0800`、`clkDownScale=0x1000`。配置已使用这两个当前 boot 参数，
证明链见 `../GSP_61057_Q12_SCALE_READBACK_20260816.md`。

对 2026-08-16 的 59 个 policy CSV（18,311 个可解析行）实跑
`fit_dg0_filter.py`：采样间隔中位 194 ms，以 20 ms 控制周期假设计约折叠 9.7 次更新。
样本级拟合显示上升有效 gain 0.693、下降 0.000182，且 67.5% 的下降转场 DG0
保持不动。它们不能从稀疏日志唯一恢复 firmware Q12 系数；现在与直接 readback 对照后，
差异反而量化了采样折叠和可能的外层 hold/P-state 门控，而不再拿 sample-level gain 代替
PMU 单周期系数。完整推导与最短判别阶跃见 `DG0_IDENTIFIABILITY_20260816.md`。

## 尚未闭合，不能称为“完整固件等价”

1. 当前 boot 每轨十个 request slot 的 active/deferred mask、winner、base 与 request/client offset；静态整数 core 已恢复；
2. R610 keyed-limit 的全部来源、优先级与条件表；
3. Q12 tracker 外层是否另有 dwell/hysteresis；当前系数已经直接读回，稀疏日志只用于识别 sample-level effective gain；
4. R610 对 GB202 R570 type-3 evaluator 的逐指令确认，以及当前各 domain divider-grid 对象参数；
5. 当前公开支持频率列表是否是所有最终 clock-arbitration 路径的最后量化器；
6. R610 type-5 私有对象字段、callback 插值细节与精确 transition ordering；双端点区间运算已从同代 clear RM 恢复；
7. type-0x0f MCLK CONTROL 语义；五点 STATUS F/V bank 已恢复；
8. P-state/context-switch 转场期间的状态残留与错误恢复状态机；
9. SYS/NVD 在各种 workload/P-state 下是否各自提交主动 MSVDD request。
10. 当前 PMU group `0x11` 的 VFE product rounding/saturation、温度 filter/sampling 与
    tuple 边界状态机；R570 clear PMU 没有这个 group；
11. 未观测 tuple/output ordinal 到 relation MHz 的精确 lookup/interpolation；已观测 tuple
    只做稀疏绑定。relation current 是否在所有状态都等于 bank point126，以及 GPC 旧快照
    3337/112 MHz 与后来 3270/45 MHz 状态之间为何改变，仍未闭合。
12. R570 group `0x0b` relation 搜索的 exact endpoint status code 与 current point-object
    `+0x0c` mode-1 输入；选点、相邻点、clamp 与 adjustment mechanism 已复刻；
13. 当前 R610 post-selection domain-adjustment group flag、两套 object type/value 与活动域
    mask；R570 的整数内核和逐域 relation reproject 循环已复刻，但不能代入猜测的 live 值。
14. 当前 R610 type-0x0c/type-0x0d 的 GSP wire layout、16-domain masked import 和状态门控
    已逐字节复刻；PMU 如何生成返回的逐域 u32、这些字的单位/位域，以及对象遍历中的
    virtual targets 仍未闭合。`Perf+0x560` 已确认是 no-op，不再列为求解器未知项。

因此当前严格称为“已运行的完整骨架 + 若干位精确子模块 + 显式未知参数”，而不是宣称已得到 NVIDIA 源码级等价物。
