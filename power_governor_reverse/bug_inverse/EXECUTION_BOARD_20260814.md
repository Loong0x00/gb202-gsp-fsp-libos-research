# `F_bug` 数据与算法执行板

日期：2026-08-14  
上位问题板：`/home/user/rt_5090_project/BUG_AWARE_INVERSE_GOVERNOR_TASK_BOARD_20260814.md`  
本轮范围：先做数据和算法；GPU 只读。禁止 SET、offset、锁频、功率配置修改与主动 benchmark。

## 结果接口

### 数据样本 v1

每个 JSONL 样本必须包含：

```text
schema_version = 1
sample_index
t_mono_start_ns, t_mono_end_ns, t_wall_ns
sources.<name>.start_ns, end_ns, returncode
sources.<name>.raw_stdout, raw_stderr, parsed
```

约束：

- 时间使用 `CLOCK_MONOTONIC_RAW`；所有来源保留调用前后时间，不能假装成原子读取。
- 单一来源失败只标记该来源失败，不丢弃整条样本。
- raw 数据是证据，parsed 数据可重建；解析器必须带 schema/version。
- 所有单位写进字段名：`_khz`、`_mhz`、`_uv`、`_mv`、`_mw`、`_w`、`_ns`。
- GPU 身份、driver/VBIOS、library/config hash 放入 run manifest。

### 规范训练表 v1

至少尝试产生以下列；缺测使用空值并附 `missing_reason`，禁止插值伪造隐藏状态：

```text
t_ns
final_gpc_mhz, final_xbar_mhz, final_sys_mhz, mclk_mhz
dg0_mhz, dg1_mhz
nvvdd_target_mv, nvvdd_sensed_mv
msvdd_target_mv, msvdd_sensed_mv
policy0_curr_limit_mw, policy0_curr_value_mw
estimated_power_mw, board_power_w
gpu_temp_c, hotspot_temp_c
active_perf_limits, workload_id, run_id
```

### 模型接口 v1

- `fit`：训练数据 + 明确可观测列 → 参数、残差、可辨识性报告。
- `compare`：至少比较 `V(final)`、`V(DG0)`、`V(pre-DG0 candidate)`、`V(stateful/hold)` 四类竞争模型。
- `predict`：必须同时给点预测、量化范围和缺失状态警告。
- `solve`：目标频率、`V <= 1080 mV`、`P <= 800 W`、验证过的控制边界 → 可行候选；否则输出当前模型下的 infeasible certificate。
- 不允许把 `pre-DG0 candidate`、10-client winner 缺测时的相关性结果宣称为因果闭合。

## 执行状态

状态：`TODO` / `RUNNING` / `DONE` / `PARTIAL` / `BLOCKED_BY_EVIDENCE` / `RISK_GATED`。

| ID | 工作 | 状态 | 依赖 | 本轮验收物 |
|---|---|---:|---|---|
| D-01 | 统一 JSONL 只读采集器 | DONE | 现有 probe | `data_pipeline/collector.py`、manifest、idle 实采与 8/8 测试 |
| D-02 | JSONL→扁平 CSV | DONE | D-01 | 实采 JSONL 已可重跑导出 CSV |
| D-03 | 旧 benchmark 多 CSV 时间对齐 | DONE | 无 | 20260814 CP2077 360 行规范训练表及 skew 报告 |
| D-04 | 同步 NVVDD/MSVDD target/sensed | DONE | V-01 | target 由 610.57 rail wrapper、sensed 由 policy 路径分别采集 |
| D-05 | 10-client winner 数据 | BLOCKED_BY_EVIDENCE | V-02 | aggregate GET 不含 slots/client ID；待跟 handler 或主动辨识 |
| A-01 | 四类竞争模型实现 | DONE | D-03 | 15 MHz PAVA step-map、5 mV 量化、synthetic 与实数 smoke |
| A-02 | 时延/hold 模型比较 | DONE | D-03 | held-out、AIC/AICc/BIC、5 mV 命中率与 uncertainty filter |
| A-03 | 受约束离散逆求解器 | DONE | A-01 | feasible、observed-only、verified-domain infeasible 均有测试 |
| A-04 | CP2077 首轮拟合 | DONE | D-03 | 量化报告明确 predictive/causal 边界 |
| A-05 | 跨 workload held-out | TODO | D-01, A-04 | CP2077/悟空/RT timeout/raster 对照 |
| A-06 | GPC/XBAR/SYS/NVD 多域数字孪生 | DONE | A-01,A-03,V/F banks | simulate/compare/solve、18 tests、PTX 四点误差 ≤1.5 MHz |
| A-07 | MCLK type-5 tuple 与 R610 动态范围闭合 | PARTIAL | A-06, private tuple/range | 5 点 STATUS F/V 与端点转换已接入；type-0x0f CONTROL/private range/order 仍缺 |
| A-08 | R610 VFE graph / VF-tuple selector 重建 | PARTIAL | A-06, current PMU evaluator | 75 节点、21 条算术边、167 个有效 tuple、18 个 relation bank、30 C 转场与稀疏 tuple→MHz 已重放；CONTROL/STATUS 已分离，R570 PMU 证实缺少当前 group 0x11；PMU rounding/filter/tie-break 仍参数化，暂不驱动输出 |
| V-01 | 610.57 两轨只读解析 | DONE | 当前 library | full-library/function hash-pinned reader，实机两轨 target 成功 |
| V-02 | 610.57 method/结构静态闭合 | PARTIAL | 610.57 binaries | method/handler/size/flags 与 per-domain offset 已闭合；global rail exact field 仍 open |
| V-03 | 精确 preimage/no-op SET | RISK_GATED | V-01,V-02,rollback | 本轮禁止执行 |
| I-01 | 数据→算法端到端 smoke test | DONE | D-01,A-01 | final collector JSONL 与旧 CP2077 都已产生持久化报告 |
| I-02 | 更新上位问题板 | DONE | I-01 | DONE/PARTIAL/OPEN 与证据路径已回写 |

## 本轮实际结果

- 最终 core+voltage 实采：`data_pipeline/artifacts/idle_core_voltage_final_20260814_010050.jsonl`，10 样本、0 source failure；whole-window min/median/max 为 19.470/20.866/26.146 ms，source-midpoint span 中位 18.095 ms。
- 该实采捕获一次 3075.099 MHz 的 GPC pre/post 转场；算法以 15 MHz uncertainty 门排除 2/10 条不稳态 bracket。由此 O-05 只能标 `PARTIAL`，不能声称原子快照。
- 两轨 target 在 final idle run 为 815/875 mV；rail wrapper 的 sensed 字段为 0，policy sensed 保留为不同字段。
- 历史 CP2077 scene 转成 360 行；四模型中 asymmetric hold 的 held-out RMSE 3.909 mV、误差不超过 5 mV 的比例为 100%，但 final/DG0 仍观测混淆，candidate/winner 缺失，所以 `causal_status=not_identified`。
- 3300 MHz / 1080 mV / 800 W 对历史观察行的查询结果是 `no_feasible_observed_candidate`；最近为 3195 MHz / 1060 mV / 641.8 W。这不是全局或物理不可行证明。
- 当前统一 idle 数据的 NVVDD target 恒为 815 mV，模型正确返回 `not_discriminating_constant_signal`。
- 610.57 已确认：`0x2080b202` 是 `VOLT_RAILS_GET_STATUS`；`0x2080901b/0x2080d01c` 是 `CLK_DOMAINS GET/SET_CONTROL`。后二者 size 均为 0x83c，但不是独立的 VOLT_RAILS method。

持久化证据：

- `data_pipeline/README.md` 与 `data_pipeline/artifacts/idle_core_voltage_final_20260814_010050.*`
- `algorithm/SMOKE_REPORT_20260814.md` 与 `algorithm/artifacts/`
- `voltage_61057/REPORT.md`
- `integration_artifacts/read_only_smoke_20260814_010759/`：一条命令产生的 current-GPU 端到端结果；10 样本、0 failure、whole-window 中位 20.884 ms，求解器因 core profile 缺 board power 正确返回 `indeterminate_missing_required_observations`。

## 已发现的历史数据资产

`run_catalog_20260814.jsonl` 由 `catalog_runs.py` 实际扫描生成：

- 168 个目录含至少一种目标 CSV；其中 CP2077 105 个、FurMark 63 个。
- 97 个 run 同时含非空 `telemetry.csv` 和 `power-policy0-dynamic.csv`。
- 86 个 run 含非空 `clock-hardware.csv`；旧文件通常只有 XBAR/SYS，不等于已有 direct GPC。
- 72 个 run 含非空 `pmgr-a613-channels.csv`；当前已知的 610.57 CP2077 run 均为空，版本/状态依赖仍需解决。
- 有 benchmark summary 的 90 个 CP2077 run 中，81 个标记 610.43，9 个标记 610.57；训练/验证必须按驱动分层。
- 20260814 CP2077 旧分散采集以 policy 时间最近邻对齐时：telemetry 中位偏差约 18 ms、最大 57 ms；clock-hardware 中位约 49 ms、最大 70 ms；perf limits 中位约 13 ms、最大 32 ms。它们只能作为带显式 skew 的历史数据，不能冒充同周期原子快照。

## 并行责任边界

- 数据线：`bug_inverse/data_pipeline/`。
- 算法线：`bug_inverse/algorithm/`。
- 610.57 电压观测线：`bug_inverse/voltage_61057/`。
- 集成与任务板：`bug_inverse/` 顶层。

各线可以读取整个项目，但只修改自己的目录；集成时不覆盖其他线产物。

## 本轮判定门槛

本轮不是以“完整破解仲裁器”为完成条件，而是以下四条必须全部落地：

1. 当前 idle GPU 真实产生至少一份版本化统一数据，失败来源也保留证据。
2. 20260814 CP2077 日志能够转成统一训练表，时间对齐误差被显式报告。
3. 四类模型和逆求解器在 synthetic 数据通过测试，并在真实日志跑出 honest result。
4. 610.57 电压观测/method 线产生 confirmed/inferred/unknown 报告，不能复用旧偏移冒充成功。

之后再决定下一最短实验：如果 winner/candidate 仍不可观测，就设计最小安全扰动；在写入安全门完成前仍不执行它。

## 下一轮最短反馈回路

1. 先把 policy/clock GET 融合为长驻 ioctl 调用，将 core bracket 稳定压到一个 PMU 周期以内；保持 pre/post drift 拒绝规则。
2. 在用户明确允许启动 workload 后，用 core+voltage 采集一次可复现 CP2077 短场景，同时单独低速采 board power/错误状态。
3. 静态跟进 `0x017e3458` 的 voltage object/vtable，判断 ten-client slot 是否存在 retail copier；若无，再设计上包络主动辨识。
4. 用 under-load target 变化重跑四模型；只有 candidate/winner 或独立激励存在时才讨论因果顺序。
