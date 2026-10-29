# host / FSP / PLM 三层权限报告一致性审阅

日期：2026-07-21
状态：**审阅完成；本轮已修订三份范围内源报告；全程仅处理 Markdown，未执行项目二进制、未访问设备**

## 结论先行

六份报告的后期结论已经足以把三层分开，但较早段落仍有少量过时或容易误读的
措辞。最重要的统一口径是：

1. **MODS host 入口层**是进程内 `SecurityUnlockLevel`，
   `ProgramSwFusePlan` 的精确条件是 `> 3`。该值在启动期由本地 bypass-record
   分类与可选 NVIDIA-network TLS Boolean 合成；它不是 GPU/FSP credential，
   不进入 task-2 packet，也不是 PLM 的 L0..L3 level。
2. **FSP 协议层必须再拆成两步**：QCAP key `0x13` 的 cache presence 只是
   FSP-reported PRC message-family capability/version entry；随后 task 2 的
   command status 只是 host 可见的完成/错误结果。QCAP presence 不保证命令成功，
   status zero 也不证明任何 PLM 已改变、仍开放或会维持多久。
3. **设备 PLM 状态层**才是 `d0/dc/f8` 的实际 word、位和 lifetime。
   Hopper sibling precheck 加 GB20x send-before-apply 只形成“task 2 旨在准备
   `d0/dc`”的较强推断；production GB202 是否写了它们仍为 UNKNOWN。
   `f8` 是 latch 的独立 PLM，现有同等级旁证连这个推断都没有。

因此，当前不能使用“task-2 authority”“task-2 permission”“task 2 已降低 PLM”
作为不带限定的简称。最安全的固定句式是：

> `SecurityUnlockLevel > 3` 只放行 MODS host writer；QCAP `0x13` presence 只放行
> task-2 packet 构造/发送，command status 只给出本次 FSP 请求的 host-visible
> 结果；`d0/dc/f8` 的实际值、变化和 lifetime 仍需独立证据。

本轮已把这套口径落入：

- `parallel/task2_lifecycle_audit.md`：将 GB202 不绑定 GSP direct-`f8` block 的
  纠错内联到正文，并明确 QCAP/status 只到 host-visible protocol boundary；
- `parallel/l2_plm_static_permissions.md`：最终矩阵补齐 H/F1/F2/D 四层；
- `parallel/task2_auth_provenance.md`：将“设备授权两步”改为
  admission/completion，并把 d0/dc INFERENCE 与独立 f8 UNKNOWN 分开。

以下第 2 节保留的是本轮范围外两份汇总报告的待修订项；第 3 节记录本轮已落地
修订。

## 1. 统一术语与证据矩阵

| 层 | 已证明的对象 | 已证明的检查/结果 | 不能据此推出 |
|---|---|---|---|
| H：MODS process-local gate | `SecurityUnlockLevel` enum 1..5；writer 要求 `>3` | host 启动时计算并缓存；当前 established stock path 中未见再次刷新/清除，故 process-lifetime 是 INFERENCE | QCAP 存在、task 2 成功、`dc/f8` 可写、PLM L4/L5 |
| F1：FSP family capability | QCAP dword=`low16 NvdmType, high16 Version`；task 2 查 key `0x13` | host 只测 key presence；Version 不比较、不随 packet 发送 | credential、grant、当前 firmware policy、命令成功、PLM 状态 |
| F2：FSP command completion | task 2/subobject 1 同步 send + response-completion；caller 只消费 status | status zero=`command completed with no host-visible error` | token、PLM snapshot、`d0/dc/f8` 已改变或仍开放、permission lifetime |
| D1：raw L2 access PLM | `domainBase+0xdc`；fixed fallback `0x8200dc` | 普通 L0/source0 完整 RMW 静态允许式已知 | 本卡 current word、self-write acceptance、task-2 actual effect |
| D2：latch access PLM | 独立 `domainBase+0xf8`；fixed fallback `0x8200f8` | address/field relationship 已知 | task 2/HULK 会处理它、current word、write/lifetime |

附加边界：PRC knob `0x1d` 是可选的独立 task-13 write/readback request；它与
task 2 共享 QCAP family，但不会创造 QCAP、不会自动嵌入 task 2，也尚未证明
`1=grant`、task-2 consume 或 self-clear。

## 2. 范围外汇总报告仍待修正的过时或越级段落

下面行号均指本次审阅时的现有文件。本轮授权范围不包含
`GB202_PARALLEL_WORK.md` 与 `L2_REENABLE_STATIC_FINDINGS.md`，因此这里只保留
建议，没有改动这两份文件。

### 2.1 `GB202_PARALLEL_WORK.md:51-54`

现文把“task 2 lowering `d0/dc`”放在 `Existing high-confidence static findings`
中，随后又用笼统的 `GSP/FSP/SEC2 authorization` 与 host level 对照。前者容易把
设计意图推断读成 GB202 device-state FACT；后者把 transport/firmware component、
QCAP、command status 和实际 PLM policy 压成一层。

建议替换为：

> - **FACT:** task 2/subobject 1 first requires cached FSP QCAP key `0x13`
>   presence and then returns one synchronous command status; neither result is a
>   credential or a PLM snapshot.
> - **INFERENCE:** the Hopper same-task `d0/dc` precheck plus GB20x
>   send-before-apply ordering strongly supports an intent to prepare those two
>   PLMs.
> - **UNKNOWN:** the production-GB202 consumer, actual `d0/dc` writes and
>   lifetime, and any effect on the independent `f8` PLM.
> - MODS' process-local `SecurityUnlockLevel > 3` entry check is orthogonal to
>   both the FSP protocol checks and the device PLM state.

### 2.2 `GB202_PARALLEL_WORK.md:208-225`

`remaining permission gap is ... concentrated in ... FSP/task-2 consumer` 和
`host network level and task-2 authority` 已落后于紧接着
`GB202_PARALLEL_WORK.md:227-232` 的 QCAP 解码。问题不只是缺 consumer；host
实际 level、QCAP cache presence、command status、PLM current words/self-write
与 lifetime 是不同未知量。`task-2 authority` 也没有一个已证明的单一对象。

建议把 `:214-225` 收口为：

> The MODS host gate is now identified as process-local
> `SecurityUnlockLevel > 3`; no bypass/TLS state is carried in the task-2
> packet, and task-2 completion does not modify that host value. Separately,
> QCAP `0x13` presence is only the FSP-reported PRC-family admission check and
> the returned status is only the host-visible result of this command. Neither
> proves a `d0/dc/f8` value. The remaining device-side gap is the unavailable
> GB202 consumer: whether task 2 changes `d0/dc` at all, for how long, and
> whether it touches the independent `f8` PLM. PRC knob `0x1d` and the signed
> HULK path remain separate mechanisms with unresolved target semantics.

`GB202_PARALLEL_WORK.md:227-232` 的 QCAP capability/status 区分应保留，但末句
`status still decides the actual request` 最好改成 `status is the host-visible
completion/error result; it does not establish a PLM state`，避免把 status 再读成
device permission。

### 2.3 `L2_REENABLE_STATIC_FINDINGS.md:46-56`

`security unlock level 至少为 4（NVIDIA network）` 把精确 host 条件与其一个
输入/枚举标签混写。后文已经证明 level 是本地合成的 process state；特别是本地
record 分类也参与 1..5 的计算。该段还从 host gate 直接跳到 PRI mask，遗漏了
QCAP presence 与 command status 不能证明 PLM state 的边界。

建议把该段开头改为：

> 第二条路线把问题从“地址未知”推进到了三个互不替代的门：
> `ProgramSwFusePlan` 先要求 MODS process-local
> `SecurityUnlockLevel > 3`；较早的 FSP task-2 路径另有 QCAP `0x13` presence
> check 和独立 command status，但二者都不证明设备权限已改变；设备侧 raw L2
> 与 latch 又分别面对 `domainBase+0xdc` 和独立 `domainBase+0xf8` PLM。
> 当前未读取本卡 PLM words，也没有证明 production GB202 task 2 的 lowering
> effect 或 lifetime。

随后关于 `disable_sw_override`、reset/reload 与 raw→effective 的内容可原样保留。

### 2.4 `L2_REENABLE_STATIC_FINDINGS.md:852-865`

枚举表本身正确；过时的是结尾“只在 NVIDIA network 等级 4/5 下执行/软件认证门”
这一缩写。精确 executable predicate 是 `SecurityUnlockLevel > 3`，其来源是 host
启动期的本地分类与 network Boolean 合成，不是一次 FSP/device authentication。

建议替换 `:864-865` 为：

> `ProgramSwFusePlan` 的精确 host predicate 是 process-local
> `SecurityUnlockLevel > 3`。4/5 是该 enum 的两个可通过值；它们在启动期由
> bypass-record 分类和可选 NVIDIA-network Boolean 合成。这只放行 host
> algorithm，不是 FSP credential，也不证明任何 PLM 已开放。

### 2.5 `L2_REENABLE_STATIC_FINDINGS.md:2038-2057`

`:2038-2040` 从日志 `Skipping FSP PRC during FS` 直接称其为
`PRC/权限协调步骤`，语气高于证据；`:2049-2057` 的 Hopper sibling 证据其实才
支持“准备 `d0/dc`”这一推断。日志能证明 FS-associated FSP PRC transaction，
不能单独证明 permission effect。即使 command status 为零，也没有 post-status
PLM read。

建议将两段合并成 FACT/INFERENCE/UNKNOWN：

> **FACT:** task 2 是 floorsweep 生命周期中的 FSP PRC transaction；其 sender
> 先要求 QCAP `0x13` presence，再等待 command status。Hopper sibling 在发送同一
> task/subobject 前读取 `d0/dc.[7:4]`，二者均为 `0xf` 时跳过发送。
> **INFERENCE:** 该 sibling precheck 与 GB20x send-before-apply 顺序强支持
> task 2 旨在准备 `d0/dc`。
> **UNKNOWN:** production GB202 是否实际改变任一 PLM、返回后是否仍保持，以及
> 是否处理独立 `f8`。日志、QCAP presence 与 status zero 均不能闭合这些状态。

### 2.6 `L2_REENABLE_STATIC_FINDINGS.md:2195-2216`

这是主报告中最需要收紧的一组。Hopper precheck 只证明 caller 能在**发送前**读取
`d0/dc` 并在值为 `0xf` 时跳过；它不证明这些值来自更早的 task 2，也不证明一次
task-2 status zero 后的持久性。因此 `Hopper 快路径支持...PLM...可持续` 和
`可能承载 d0/dc 权限的 stock host 候选时序` 都把 control-flow candidate 写得过于
接近 device-state evidence。

建议替换三段为：

> Hopper sibling precheck proves only that a pre-existing `d0/dc.[7:4] == 0xf`
> state can be observed before a send and can suppress that send. It does not
> establish the provenance of that state or persistence after an earlier task 2.
> The first no-FS-arguments GB20x path does establish a host control-flow
> candidate: task 2 may return status zero and the host may then skip apply and
> reset. There is, however, no PLM read between that status and return to the
> script layer. Consequently it remains UNKNOWN whether `dc` was ever changed,
> whether it remains writable, and whether `f8` independently permits the latch
> RMW. A later `SetSwFuses` call would additionally require the separate
> process-local `SecurityUnlockLevel > 3` gate. This timing is a research
> hypothesis, not a demonstrated permission window.

### 2.7 `L2_REENABLE_STATIC_FINDINGS.md:2668-2669`

可行性表仍用 `NVIDIA network level 4/5`，并把 `task-2/f8 权限` 合成一个缺口。
建议分别改为：

> | `NewFuse.SetSwFuses` 名称入口 | ...；仍缺 GB202 JSON，且 writer 要求
> process-local `SecurityUnlockLevel > 3`；这不提供 FSP 或 PLM 权限 |
> | 低层 raw shadow plan | ...；FSP 的 QCAP `0x13` presence/status 时序已知，
> 但 task 2 对 `d0/dc` 的 effect 仍只是推断，`f8` 又是无同等级旁证的独立缺口；
> 三只 PLM 的实际值/lifetime、传播/恢复和物理健康均未闭合，不实现实机 writer |

### 2.8 `L2_REENABLE_STATIC_FINDINGS.md:2812-2820`

`查 task 2 是否除 d0/dc 外也处理 f8` 预设了 task 2 已处理 `d0/dc`。当前只能说
这是一项强设计推断。建议改为：

> 继续只从可信 FSP/GFW consumer 查明 task 2 是否实际改变 `d0/dc`、写成什么值、
> 何时收回，以及是否另行处理独立 latch PLM `f8`。QCAP presence、command
> status、host 无显式 close 都不能替代这些 device-state 证据。

## 3. 本轮已落地的一致性修订

### 3.1 `parallel/task2_lifecycle_audit.md`

- 删除依赖读者先应用的页首临时 erratum，把 GSP `0x0108c4ae` block 的
  TU102/TU116 binding 与 GB202 success-stub binding 直接写入 `f8` 正文；
- 将 task-2 已知边界固定为 F1 QCAP `0x13` presence 加 F2 command status；
- 将 status-zero 后的 device effect 拆成 `d0/dc` actual effect/lifetime UNKNOWN
  与独立 `f8` UNKNOWN；
- 保留“task 2 旨在准备 d0/dc”为较强 INFERENCE，不升级成 GB202 FACT。

### 3.2 `parallel/l2_plm_static_permissions.md`

最终权限矩阵已补齐：

| 层 | 规范含义 | 证据边界 |
|---|---|---|
| H | process-local `SecurityUnlockLevel > 3` 与可选 RegHal diagnostic | 只约束 host；不是 FSP/device credential |
| F1 | cached FSP-reported QCAP key `0x13` presence | message-family gate；不是 grant/PLM snapshot |
| F2 | task-2 synchronous command status | host-visible completion/error；不是 device effect |
| D | `dc` raw-L2 PLM 与独立 `f8` latch PLM | d0/dc effect 是 INFERENCE；f8 actual effect/current/lifetime UNKNOWN |

最终引文也已同步采用 H/F1/F2/D，不再从 host gate 直接跳到 PLM lowering。

### 3.3 `parallel/task2_auth_provenance.md`

- 开篇矩阵从三种笼统“授权”改为 H/F1/F2/D；
- `task 2 的可见设备授权` 改为 `host-visible admission/completion`；
- 参数表中的 `network level` 改为 process-local `SecurityUnlockLevel`；
- INFERENCE 只保留 FSP/硬件 trust-boundary policy 解释，FACT 明确只到
  QCAP presence 与 command status；
- UNKNOWN 将 production GB202 `d0/dc` actual effect/lifetime 与独立 `f8` 分列；
- 最终可引用表述明确 QCAP/status 都不是 PLM-state proof。

### 3.4 范围外仍待统一的 `network level` 简写

本轮范围内三份源报告的规范位置已经改用 `SecurityUnlockLevel > 3` 或
`process-local SecurityUnlockLevel`。范围外仍建议收紧：

- `GB202_PARALLEL_WORK.md:249,332`；
- `L2_REENABLE_STATIC_FINDINGS.md:797,849,1038-1039,1348,1858,2143,2213,
  2536,2585,2668`。

真正讨论 TLS detector 本身的段落仍应保留 `NVIDIA network`；问题只在把最终
process enum 简写成 network credential/level。

## 4. 无需实质修正的报告/段落

- `parallel/prc_1d_domain_followup.md`：没有把 host 成功包络当成 FSP allowed
  domain，也没有把 `0x1d`、QCAP 或 task-2 status 当作已证 permission；FACT /
  INFERENCE / UNKNOWN 边界一致。无需修改。
- `parallel/task2_lifecycle_audit.md`：现已在正文明确 status zero 不证明 PLM、
  QCAP 只表示 shared family、GB202 不绑定 direct-`f8` block，且 `f8` 是独立缺口。
- `parallel/l2_plm_static_permissions.md`：已正确区分 field definition、full-RMW
  condition、current hardware state、H/F1/F2 gates/results 和 task-2 inference。
- `parallel/task2_auth_provenance.md`：现可作为四层术语基线；尤其
  `SecurityUnlockLevel`、QCAP presence、command status 与 PLM UNKNOWN 的拆分
  已在开篇、参数表、UNKNOWN 清单及最终引文中一致。
- `L2_REENABLE_STATIC_FINDINGS.md:906-911,985-993,2082-2088,2109-2125,
  2238-2248`：这些后期段落已经给出正确限定。修订较早段落时应引用/前移这些
  结论，而不是新增第四套“authorization”术语。

## 5. 推荐的全局写作规则

1. 只把 `SecurityUnlockLevel` 称为 **host entry gate/process state**；除非正在讲
   detector，不称它为 network credential。
2. 第一次出现 QCAP 时固定写 **cached FSP-reported family entry presence**；不写
   `QCAP authorization`。
3. status zero 固定写 **host-visible command completion with no returned error**；
   后接一句“not a PLM-state proof”。
4. `task 2 lowers d0/dc` 必须加 **INFERENCE / intended effect**；production GB202
   actual effect 必须保留 UNKNOWN。
5. 每次并列 `dc/f8` 时都注明：`dc` 是 raw-L2 access PLM，`f8` 是 latch access
   PLM；对前者的 task-2 类比不能覆盖后者。
6. `PLM lowered` 若来自 MODS 日志，只表示被比较的 write nibble `[7:4] == 0xf`；
   不自动等于完整 L0/source0 RMW 条件，更不等于本卡 live state。

按以上改写后，六份报告会形成单向、不可越级的证据链：

```text
SecurityUnlockLevel > 3
  -> 只决定是否进入 host writer

QCAP 0x13 presence
  -> 只决定是否进入 task-2 send path

task-2 command status
  -> 只决定 host 是否可继续到后续 apply 阶段

dc/f8 actual PLM state
  -> 必须由独立 consumer/state evidence 决定；当前未闭合
```
