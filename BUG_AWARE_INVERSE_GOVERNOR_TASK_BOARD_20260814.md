# Bug-aware inverse governor：信息补全与求解任务板

日期：2026-08-14  
目标平台：RTX 5090（10DE:2B85 / ASUS 1043:89E3），Linux 610.57.04  
当前阶段：只读建模；任何实时写控制均处于安全门之后

## 0. 核心想法

不要先假设 GSP/RM 仲裁器实现了理想的 `V/F` 映射，而把当前固件的实际行为整体视为一个有状态、带延迟、可能错序的被控对象：

```text
u(t) ──> F_bug(x(t), workload(t), temperature(t)) ──> y(t)
          ↑                                  │
          └──────────── state/delay ─────────┘
```

- 控制量 `u`：GPC/XBAR 等频率偏移、V/F 点电压偏移、NVVDD/MSVDD 轨电压偏移、轨×时钟域偏移，以及必要时的时钟上限。
- 输出 `y`：最终 GPC/XBAR/SYS/MCLK、DG0/DG1、NVVDD/MSVDD 请求/实测、电源策略状态、功率与稳定性事件。
- 求解目标：寻找预畸变控制 `u = G(target, state)`，使 `F_bug(u)` 达到目标，而不是把固件逻辑重新搬回 CPU。
- 第一项可行性查询：在 800 W 策略下，是否存在使最终 GPC 稳态达到 3300 MHz、NVVDD 不超过 1.080 V 且无掉卡/Xid 的控制解。
- 若不存在，必须给出由已识别模型、控制边界和实测反例构成的不可行性证据；“成本太高”不算不可行。

## 1. 已确认基线

### 硬件与软件

- GPU：NVIDIA GeForce RTX 5090，PCI `0000:01:00.0`。
- 驱动：610.57.04；VBIOS：98.02.2E.80.50。
- 功率上限：800 W；默认 1000 W；硬件报告最大 1600 W。
- LACT GPU ID：`10DE:2B85-1043:89E3-0000:01:00.0`。
- 当前 `/etc/lact/config.yaml` SHA-256：`a33e679cfb0ac19552b2225a10dcf4c4ed2b1cf4529dc8bf2e667415f084bfd5`。

### 已有读能力

- `power_cap_limit_probe` 可读取策略 0..16、关系、DG0/DG1、估计功率、估计/观测电压以及 type 5/6/7 功率方程数据。
- `--clk-measure-freq 1` 可直接读取最终 GPCCLK；域 2/4 可读取 XBAR/SYS。不能再把 NVML 报告值当作唯一最终时钟。
- `--clk-prop-tops-summary` 已读出活动 topology 7；GPC→XBAR 的 type-3 比例当前约为 0.899902344。
- `--clk-client-vf-summary` 可读 Client VF 点及 `freq_offset_khz`、`volt_offset_uv`。
- `--clk-vf-points-status-raw` 解出的 127 点属于 XBAR VF bank，不能与 GPC Client VF 曲线混为一谈。
- 当前可调时钟域：GPC、XBAR、MCLK、SYS；工厂 GPC/XBAR offset 当前均为 +45 MHz，MCLK 为 +1000 MHz。
- 已知电压请求路径每轨最多 10 个 client：各 client 计算基础电压及 global/local/client offset，取无符号最大值，再按 5 mV 向上量化后交给 PWM/VRM。

### 已复现实象

- 先前 1.145 V 请求会触发黑屏、PCIe 掉卡；将 1.08 V 以上的 V/F 尾部抹平后不再掉卡。
- 2026-08-14 的 CP2077 6K PT 短测中，尾部设为 3300 后：最终 GPC 约 3172.2 MHz，NVVDD 约 1070.4 mV，而 DG0 约 3214.1 MHz。
- 这至少证明“电压选择/上游候选”“DG0”“最终 GPC”不是同一个量；不能用单值静态 V/F 表解释当前行为。
- 证据目录：
  - `benchmark_logs/cp2077_6k-pt-tail3300-dg0-vf-feedback-short_20260814_001713/`
  - `benchmark_logs/dg0-vf-nvml-max-tail3300-20260814_001713.log`

## 2. 信息缺口总表

状态定义：`DONE` 已用当前驱动/硬件验证；`PARTIAL` 只覆盖一部分；`OPEN` 尚无判别证据；`RISK-GATED` 需要先通过写入安全门。

| ID | 信息/能力 | 状态 | 当前证据或缺口 | 完成判据 |
|---|---|---:|---|---|
| O-01 | 最终 GPC/XBAR/SYS 时钟直读 | DONE | clock-measure 域 1/2/4 可读 | 采集器统一打时间戳 |
| O-02 | 功率策略、DG0/DG1、方程与 regime | DONE | 610.57 已读出 | 并入同步快照 |
| O-03 | 当前 NVVDD/MSVDD target/sensed | DONE | 610.57 hash-pinned rail wrapper 读 aggregate target；policy 路径读 sensed，字段与时间戳分开 | 已实采并接入统一 schema |
| O-04 | 每轨 10 个请求槽及获胜 client | OPEN | retail GET 路径尚未找到 | 每次更新能得到 client ID、base、各 offset 与 final，或得到可区分的等价观测 |
| O-05 | 一次仲裁周期内的同步快照 | PARTIAL | core bracket 已达 whole median 20.866 ms / midpoint median 18.095 ms，但仍有 26 ms 尾部和实际 P-state 转场 | 融合长驻 ioctl，使最大窗口稳定低于一周期并保留 drift 拒绝 |
| O-06 | 错误/恢复事件 | PARTIAL | 可查 Xid；上下文超时但恢复的路径尚无统一捕获 | 同步保存 kernel log、应用退出状态、PCIe link/device presence |
| C-01 | 610.57 的 `0x2080901b/0x2080d01c` 方法表 | DONE | 已确认二者为 CLK_DOMAINS GET/SET_CONTROL，size 0x83c，当前 handler/flags 与 wrapper 均已钉死 | 静态审计可重跑 |
| C-02 | 610.57 rail/domain offset GET_CONTROL 布局 | PARTIAL | per-domain freq 与 rail×domain offset/masks 已闭合；global rail offset 的当前精确字段及所有未知字节仍未闭合 | 全结构无损 decode/re-encode 后才允许 preimage |
| C-03 | 无变化 SET round-trip | RISK-GATED | 现有 domain/topology 原始 SET 即便同值也返回 0x1b | C-01/C-02 完成后，精确 preimage SET 成功且 readback 完全一致 |
| C-04 | VF 点 `volt_offset_uv` 非零接受语义 | RISK-GATED | 字段存在；非零接受、符号、应用顺序未知 | 先 0 uV no-op，再做最小正负步进并读回/测量 |
| C-05 | rail、rail×domain、freq offset 的组合顺序 | OPEN | 旧 MODS 方法名和调用链已知，当前实现顺序未闭合 | 静态控制流 + 单变量最小扰动相互印证 |
| M-01 | 电压请求发生在何种候选频率之后 | OPEN | 现象支持错序/残留，但未辨认具体中间量 | 扰动试验能唯一排除至少两种竞争顺序模型 |
| M-02 | type 5/6/7 精确固定点语义 | PARTIAL | 参数可读，历史实现已抽取；610.57 的取整/顺序仍缺 | 对持出样本逐项预测内部估计量，误差受量化界约束 |
| M-03 | DG0→最终 GPC 的 filter/grid/arbiter 转移 | PARTIAL | 模型已参数化 alpha_up/down、down dwell、hysteresis 与 15 MHz grid；20260816 的 59 个稀疏 policy CSV 只识别 sample-level gain，194 ms 中位采样约混叠 9.7 个假设 20 ms 周期，不能冒充 per-cycle Q12 系数 | 原子阶跃观测后，对稳态预测误差不超过一个 15 MHz bin；转场误差不超过一个更新周期 |
| M-04 | rail1、XBAR、MCLK 与 GPC 的耦合 | OPEN | topology 可读，行为映射未测 | 单变量扰动矩阵得到有方向和置信区间的耦合关系 |
| M-05 | 温度、泄漏、冷热启动漂移 | OPEN | 单次短测不足 | 冷/热重复数据可估计参数漂移并给出上界 |
| S-01 | 逆模型/鲁棒求解器 | PARTIAL | 四竞争模型、5 mV step-map、verified-domain solver 与 GPC/XBAR/SYS/NVD 多域数字孪生已运行；PTX XBAR 四点静态预测误差 ≤1.5 MHz；MCLK tuple/live winner/held-out workload 尚缺 | 在持出 workload 上满足频率、电压、功率和稳定性约束 |

## 3. 执行队列

### P0-A：先把观测闭环

- [ ] **A1 — 构建同步只读快照器**（PARTIAL：schema/manifest/core bracket 已完成；最大窗口尚未稳定小于一个 PMU 周期）
  - 同一进程读取：最终 GPC/XBAR/SYS/MCLK、DG0/DG1、策略 0 完整状态、regime、NVVDD/MSVDD target/sensed、温度、功率、active PERF limits。
  - 每次调用记录 `CLOCK_MONOTONIC_RAW` 前后时间；保存 raw blob 和 decode 结果，禁止只存格式化文本。
  - 验收：连续 10 分钟不改变 GPU 状态、不报 RM error；样本能按仲裁周期对齐。

- [x] **A2 — 移植 610.57 电压轨只读解析**
  - 对 `/usr/lib/libnvidia-api.so.1`（当前 SHA-256 `fea6a0090bbdca9b294682b34a8808e1a4e3f6613f9b6684b412893d5047cef8`）重新定位 wrapper、method 与结构长度。
  - 不复制 610.43 偏移；先用静态交叉引用和只读调用验证。
  - 验收：NVVDD/MSVDD aggregate target 与 policy sensed 分别采样、分别命名并保留时序；两者不是应被强行相等的同一量。

- [ ] **A3 — 找到 10-client 电压请求观测面**
  - 搜索 GET_STATUS/GET_INFO、诊断字段、状态缓存，以及 request-update 调用族。
  - 若 retail 接口确实不暴露，设计 client-specific 扰动，用上包络变化识别 winner/equivalence class。
  - 验收：至少能回答“1.08 V 请求由哪个 client/哪一类候选产生”，且可重复。

- [ ] **A4 — 修复/解释 `--pmgr-a613-summary` 的状态依赖**
  - 当前空闲时曾返回 RM status `0x3b`，但此前负载中读取成功。
  - 做 idle/load、首次/重复调用的最小矩阵；记录原始状态和方法返回码。
  - 验收：得到明确前置条件或稳定替代读取路径。

### P0-B：闭合 610.57 控制结构，但先不写

- [x] **B1 — 静态定位 610.57 `0x2080901b/0x2080d01c`**
  - 记录方法表 entry、结构 size、handler、权限/flags、wrapper 调用者。
  - 对比 610.43 的 0x83c 与旧 MODS 0x7bc，列出所有字段增删和未知区域。
  - 验收：两个独立静态证据指向同一结构与 handler。

- [ ] **B2 — 完整 decode GET_CONTROL**（PARTIAL：per-domain 布局已闭合，global rail 与未知字节仍 open）
  - 解析 rail offset、rail×clock-domain offset、freq-domain offset、mask、flags、版本字段。
  - 未知字节原样保存；多次读取验证稳定/动态区域。
  - 验收：能够由 decode 后字段无损重建原始 buffer。

- [ ] **B3 — 建立写入安全门与回滚器**
  - 强制匹配 PCI ID、subsystem ID、driver、library hash、method size 和原始配置 hash。
  - SET 前保存精确 preimage；SET 后立即 readback；异常、信号、超时均回滚并解除 clock lock。
  - 监视 Xid、PCI device presence 与 display；任何异常立即停止后续写入。
  - 验收：代码审计 + 在纯模拟 buffer 上注入每种失败路径，均执行回滚状态机。

- [ ] **B4 — 最小 no-op 与最小步进验证**（`RISK-GATED`）
  - 顺序固定：精确 preimage no-op → 0 uV VF no-op → 单域最小频率步进 → 单域最小电压步进。
  - 任一步未成功 readback，不进入下一步。
  - 硬限制：NVVDD 不允许超过 1.080 V；不得复现 1.145 V 条件。

### P0-C：识别实际的 `F_bug`

- [ ] **C1 — 建立基线数据集**（PARTIAL：历史目录 182 runs/110973 规范行与 current idle schema 已建立；缺同版本重复 workload）
  - workload：idle↔load 转场、CP2077 6K PT 冷/热、黑神话悟空 RT、另一个会出现上下文超时但可恢复的 RT 游戏；另加一个 raster 对照。
  - 每种至少 3 次，明确 shader compilation、场景、相机路径、帧率限制、温度区间。
  - 验收：同条件重复的关键输出分布可量化；所有原始快照可重放解析。

- [ ] **C2 — 判别仲裁顺序和延迟**（PARTIAL：四模型已可比较，但当前数据仍 `causal_status=not_identified`）
  - 竞争模型至少包括：
    1. 电压由最终时钟选点；
    2. 电压由 DG0 选点；
    3. 电压由 DG0 之前的候选选点，之后 DG0/filter 再降频；
    4. 电压请求跨周期残留或以不同上/下降延迟更新。
  - 使用阶跃/短脉冲与 client winner 信息判断，不靠相关性命名中间量。
  - 验收：持出转场能预测请求电压方向、量化台阶及到达周期。

- [ ] **C3 — 拟合功率固定点与 DG0**
  - 优先实现可解释的逐字段仿真；无法直接闭合的内部量再用受约束 surrogate。
  - 明确每一步定点位宽、符号、饱和、向上/向下取整。
  - 验收：稳态 DG0 预测至少 90% 样本不超过一个 15 MHz bin；失败样本必须能归因到未观测状态。

- [ ] **C4 — 拟合 DG0→最终 GPC 转移**
  - 分离 topology ratio、grid、filter、PERF limit、热/功率限制与 context-switch 事件。
  - 验收：持出稳态最终 GPC 中位数误差 ≤15 MHz，转场 settling 误差 ≤一个仲裁周期。

- [ ] **C5 — rail1/XBAR/MCLK 耦合与温漂**
  - 在通过安全门后做单变量、小步进、正负对称扰动；不同时动两个控制量。
  - 验收：得到局部 Jacobian、置信区间、温度依赖和不可辨识方向。

### P1-D：求解和验证

- [x] **D1 — 定义约束优化问题**

```text
min_u  w_f * |f_final-target| + w_v * V + w_p * P + w_du * |Δu|
s.t.   F_bug(u, x, workload, T) satisfies:
       NVVDD <= 1080 mV
       power <= 800 W
       no PCIe loss / Xid / unrecovered context timeout
       controls remain inside verified readback bounds
```

- [ ] **D2 — 先求静态曲线编译器**
  - 对温度/workload regime 生成受约束的 GPC VF、rail×domain 与辅助域 offset 表。
  - 不先上高频 CPU 用户态闭环；只有静态解无法覆盖状态漂移时才加入低速 supervisor。

- [ ] **D3 — 鲁棒性与可行性判定**
  - 对参数置信集合求最坏情况约束，而不是只优化训练轨迹均值。
  - 3300 MHz 查询若失败，输出：约束冲突、控制边界、实测反例和置信范围。

- [ ] **D4 — 持出验证**
  - 用未参与拟合的场景、冷热状态和上下文切换压力验证。
  - 通过条件：最终时钟达到查询目标的一个 bin 内、NVVDD ≤1.080 V、功率 ≤800 W、无 Xid/PCIe loss，且恢复/回滚路径实际演练成功。

## 4. 写入安全门（全部满足才允许实时控制）

- [ ] 当前 GPU、subsystem、driver 和方法结构全部精确匹配。
- [ ] GET 能生成无损 preimage；未知字段不被归零或猜测。
- [ ] dry-run 显示唯一将变化的字段、单位和量化后值。
- [ ] rollback 在信号、超时、RM error、readback mismatch、进程退出下都必达。
- [ ] 独立监视器能检测 Xid、PCIe disappearance、display loss 和进程卡死。
- [ ] 电压上限在请求生成前强制裁剪为 1.080 V，而不是事后发现。
- [ ] 每次实验仅改变一个变量，并有同温度/同 workload 对照。
- [ ] 终端/后台任务状态已固定，避免测试结束或终端退出遗留锁定状态。

## 5. 产物约定

后续实现时统一生成：

```text
power_governor_reverse/
  snapshots/        # 原始 method buffer + monotonic timestamps
  datasets/         # 可重放的统一列式数据
  models/           # 固定点模型、参数和置信范围
  solver/           # 正向仿真、逆向求解、约束验证
  experiments/      # 每个实验的输入、环境、回滚与结果清单
```

每个结论必须链接到：原始 buffer/日志、解析器版本、驱动/library hash、GPU ID、配置 hash、workload 复现步骤。没有这些只能标为假设。

## 6. 下一最短反馈回路

1. 将 policy/clock GET 融合成长驻 ioctl 路径，使 core bracket 的最大窗口稳定小于一个约 20 ms 的 PMU 周期。
2. 静态跟进 `0x017e3458` 到 ten-client request array/status copier；不存在 retail copier 时才转入上包络主动辨识设计。
3. 在用户明确允许启动 workload 后，用 current core+voltage schema 采 CP2077 短场景，并低速旁采 board power/错误状态。
4. 用 under-load target 变化重跑四模型；只有 candidate/winner 或独立激励存在时才升级因果结论。
5. B2/B3 未完成前不进入 B4 no-op，不碰实时 offset。
