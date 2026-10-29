# `L2_REENABLE_STATIC_FINDINGS.md` 陈旧/过强表述审计

> **2026-07-21 后续修正：** 本文 A3/A4 写成后，新的两套独立构造重放证明
> GB202 index 65 的 `OBJGPU+0x668` 实际绑定状态感知 `0x144d4e8`，不是恒假
> 默认桩。相关旧建议由 `parallel/reset_coupled_binding_replay.md` 取代；主报告
> 已按新证据更新。历史输出未留档、不是当前值且不能区分三种 coupling 的限定
> 仍然成立。

> **2026-07-21 再更新：** getter/相邻 setter/virtual guard 的交叉审计现已把
> `+0xb68` 校准为 `isVirtual`，并证明固定物理实现直接返回
> `fuse(+0x40) || boot(+0x44)`，没有直接读取 base `+0x48`。因此“A3/A4 只知
> 两个未命名 bit”的中间口径也已过时；历史 0 尤其不能排除 base-only。

审计基准：2026-07-21 当前文件，共 1990 行。本文只对现有文本、归档和静态证据做交叉核对；没有访问 GPU、设备节点、MMIO、MODS、reset 或驱动状态，也没有修改主文档。

证据口径采用 `parallel/evidence_audit.md:42-48`：`V-RUNTIME`、`V-STATIC`、`REPORT-ONLY`、`INFERRED`、`UNKNOWN`。拓扑命名边界以 `parallel/evidence_audit.md:247-268` 和 `L2_SLICE_MAP_FINDINGS.md:41-85` 为准；repair 新证据以 `parallel/tmux_gsp_l2_repair.md:26-39` 和 `parallel/gsp_inforom_vtable_replay.py` 为准；latch/reset 边界以 `parallel/tmux_mods_permissions.md:31-40,67-76` 为准。

## 摘要

建议修正 12 处。其中最重要的是：

1. 后文仍有三处把未归档或根本未读取的状态写成已验证本卡事实：software mask 为 0、reset-coupled 探针实际执行/健康快照、以及 `disable_sw_override` 当前为 0。
2. “一个 raw mask bit = 一个 2 MiB 物理单元 = 一个新增 rollup class”仍在数处被当成确定关系；现有证据只支持条件 accounting model，不能预测 `48 -> 49`。
3. 主文档已经找到 `GB20xPrepareResense` 的 clear-coded latch 路径，因而不再存在“完全没有 latch-clear 代码”的硬错误；但 whole-ELF literal-scan 结论仍应限定为当前 MODS host direct-literal 路径，不能外推固件/硬件。
4. 当前 GB202 repair hook 的 no-op 绑定已有新持久化静态重放证据，应把共享 repair 实现与 GB202 实际 HAL 分开。当前 610 仍没有 client-visible per-LTS repair/self-test 接口。

## A. REPORT-ONLY / UNKNOWN 被写成已验证本卡状态

### A1. `:233-236` — software mask=0 又被写成当前事实

原文末句：

> 当前软件配置寄存器本来就是 0，直接再写 0 也不会获得额外 L2。

这与同文 `:62-68`、`:269-273` 的降级口径矛盾。SW=0 没有保存 stdout，只是 `REPORT-ONLY`（`parallel/evidence_audit.md:161-169`）。

建议替换 `:233-236` 为：

> 但这不影响静态机制结论：即使关闭自动修正，官方 floorsweep 写入器也只控制额外的 software-disable 层，最终 effective mask 仍会合入 raw/hardware mask。此前未归档报告称本卡 software mask 为 0；若该报告准确，再写 0 也没有增容收益，但不能把这个 0 称为当前实卡已复核值。

### A2. `:365-369` — 把 `disable_sw_override==0` 写成本卡值

原文列举：

> 1. 本卡硬熔丝 `disable_sw_override == 0`；

但 `:381-384` 已说明本卡当前值没有安全读回，`parallel/evidence_audit.md:20-22,203-209` 也定为未知；而且 direct-shadow writer 本体没有调用该 helper。

建议替换两层门的表述为：

> 1. 对 `IsSwFusingAllowed`/soft-burn 查询路径，`disable_sw_override` 必须读为 0；本卡当前值为 `UNKNOWN`；
> 2. GSP/PRI/firewall 仍须允许相关软件写入。该 helper 不在已审计的 direct-shadow writer 主机调用链中，因此该 bit 对 direct-shadow 的更低层作用也仍为 `UNKNOWN`。

### A3. `:1221-1231,1253-1255` — 未归档 reset-coupled live probe 写成已执行事实

这两段写成“已发出控制”“哨兵确实被覆盖”“查询后健康检查仍为 35 C/40.43 W”。项目没有保存 probe stdout 或健康快照；`parallel/evidence_audit.md:169-180` 明确将其降为 `REPORT-ONLY`。后续已证明 GB202 使用状态感知 getter，所以不能再说它恒假；但旧输出仍未留档，也不能代表当前值或拆分三种 coupling。

建议用一段替换两处 live 叙述：

> 此前未归档的只读探针报告称：输出先填 `0xa5`，该 control 返回 `NV_OK` 并把结果写为 0；同一报告还称查询后显示/温度/功耗正常。由于项目没有保存 stdout 或健康快照，这些运行观察均为 `REPORT-ONLY`，不能称为当前值或独立复核事实。可独立复核的静态结论是：该 control 为 route-to-physical GET，且 GB202 绑定有条件的状态感知 getter；固定实现直接返回 fuse OR boot，并不直接读取 base。

### A4. `:1238-1251` — 已由归档重放闭合并纠正

原审计时确实缺少 OBJGPU `+0x668` 重放。现在
`parallel/gsp_objgpu_668_replay.py`、结果留档和
`parallel/objgpu_668_independent_check.md` 已闭合该槽，并发现旧手工解释漏掉
group-2 bitmap `0x303f`。

建议将 `:1247-1251` 改为：

> 两套独立有界重放证明：GB202 index 65 / group 2 low 1 把状态感知
> `0x144d4e8` 安装到 `OBJGPU+0x668`，不是恒假 `0x19508c4`。该绑定为
> `V-STATIC`；历史 control 返回仍因未留档而不能作为当前三项 coupling 证据。

该槽现已升级为 `V-STATIC`，但仍不能升级为当前 live coupling 值。

### A5. `:1875-1878,1894-1898` — 离线工具的“当前 mask/self-test”容易被误读成板卡验证

`plan-l2` 的 `0x12`、2 MiB/bit、128 MiB 是输入/内置 accounting model；IFF self-test 对这些板卡命题只是自洽测试。fjson self-test 使用 synthetic `DUMMY_DISABLE`。证据见 `parallel/evidence_audit.md:294-308`。

建议替换相关 bullet 为：

> - `plan-l2`：按调用者提供或示例假设的低 8-bit mask 计算条件性 raw-shadow 候选和 accounting 容量；默认/示例 `0x12` 不是本卡当前值的独立验证；
> - `self-test`（仅离线 parser/encoder）：检查记录布局、CRC 和内部测试向量的一致性；不验证本卡 `0x12`、2 MiB/bit、128 MiB 满配或任何硬件行为。

并把 `:1897-1898` 的“三套工具测试通过”限定为“离线软件内部测试通过”。

### A6. `:1904` — “已验证不可重新启用”未限定为静态 MODS 路径

建议把表项：

> `fbp_l2slice_enable` | 已验证不可重新启用

替换为：

> `fbp_l2slice_enable` | 对 MODS 570.151 的静态路径分析表明它只写 SW-disable 层，不能清 raw/effective hard mask；未做本卡 live 调用

## B. 48 rollup / 96 NCU `l2s` / 16 LTC / 32 MiB 的粒度混同

### B1. `:43-45` — “最小 +2 MiB 候选”写得过确定

raw address 可以静态精确定位；“该 bit 是 +2 MiB”则依赖未归档的 `8 x 0x12` 与 accounting model（`parallel/evidence_audit.md:161-167`）。

建议替换为：

> 离线可以准确列出单个 raw-shadow mask-bit 的候选目标；只有在 `8 x 0x12` 报告和 2 MiB/bit accounting model 都成立时，才可把它条件性标成“理论 +2 MiB”。

### B2. `:104-105`（并约束 `:111-124` 的用词）— “每个 L2 slice”应改成 RM mask 术语

`physical LTS enable mask` 是 RM control/HAL 的字段命名，不证明 bit 与 96 个 NCU `l2s` 或 48 个 PerfWorks rollup 的绝对身份关系。

建议替换 `:104-105` 为：

> 所以 `0x820d70` 是粗粒度 FBP LTC/ROP-L2 状态，而 `0x822900` 是按 FBP 展平的 RM LTS effective-disable mask 数组；这里的一个 mask bit 尚不能与 NCU `l2s` 或 PerfWorks rollup 的绝对物理身份等同。

在 `:113`/`:123` 保留源码术语 `physical LTS enable mask` 时，建议首次出现后加“（RM 字段名；非绝对实例映射证明）”。

### B3. `:340-342` — repair “pair”被直接连到 2 MiB mask bit

GSP 文案证明 generic repair 有 pair 语义；它不证明一个 repair pair 等于一个 2-MiB mask bit、一个 rollup domain 或两个 NCU `l2s`。

建议替换为：

> GSP 文案明确有 paired-repair 语义，这与当前 accounting model 数值相容；但现有公开/归档数据没有证明 repair pair、RM mask bit、48 个匿名 rollup 和 96 个 NCU `l2s` 之间的身份映射。可保留的结论只是 generic repair 属于容量中性的 spare swap，而非增容。

### B4. `:1656-1666` — 编码一个 bit 被写成“+2 MiB 请求/单元”

编码器直接证明的是稀疏的**一个 raw mask-bit 修改**；容量增量和物理独立启用粒度均未证明。

建议替换 `:1656-1660` 为：

> 这证明高层编码器可以表达“单个 FBP、单个 raw mask bit”的修改。在 `0x12` 报告与 2 MiB/bit accounting model 成立时，可把它条件性标注为“理论 +2 MiB”；编码器本身不证明容量增量或物理 slice 身份。单项计划只减少同一次调用的多项部分提交面，global latch、失败不回滚和 reset/reinit 风险仍在。

并把 `:1665-1666` 的“一个 bit（理论 +2 MiB）/全部 32 MiB”改为“一个报告中的 raw mask bit（accounting model 下理论 +2 MiB）/报告中全部 16 bit（model 下 32 MiB）”。

### B5. `:1946-1960` — 不能预测单 bit 会让 48 类变 49 类

现有 placement 只证明同一 allocation 内的 48 个**相对 rollup class**；没有绝对 physical ID。一个 raw mask bit 与一个 rollup class 的一一关系也未证明（`L2_SLICE_MAP_FINDINGS.md:3-25,74-85,414-430`）。

建议用以下文字替换该段的测试能力描述：

> 该构想只能作为未来另行授权的风险隔离框架，不能称为逐物理 slice 自检。现有 `l2_slice_re` 能在自己的 CUDA allocation 内校准相对 LTS rollup class，但不能把流量钉到某个绝对 FBP/LTC/LTS，也不能识别“新启用的那一类”。清一个 raw mask bit 后，公开证据不足以预测 rollup class 数必然从 48 变成 49；它可能不变、改变为其他基数，或只改变另一观察层。任何未来校准都必须动态发现结构并 fail-closed，且即使观察到新增类也不能证明它与目标 mask bit 同一。

### B6. `:1988-1989` — “单个 2 MiB 单元”不是已证明硬件粒度

建议替换为：

> 任何未来硬件研究至多先选择一个报告中的 raw mask bit；“理论 +2 MiB”只是 accounting 标签，不能称为已识别的单个 2-MiB 物理单元。开始前仍需独立证明恢复语义、隔离系统并取得用户明确批准。

## C. latch-clear / rollback 表述范围

### C1. 没有发现仍然无条件声称“当前完全不存在 latch-clear 代码”

主文档 `:1069-1078` 已明确记录 `GB20xPrepareResense` 的 `0x404f0000` clear-coded 路径；`:731-746` 只声称 direct-shadow **failure tail 本身**不清 latch/不回滚；这两处范围正确。`parallel/tmux_mods_permissions.md:67-76,88` 独立支持这种区分。

### C2. `:1159-1165` — whole-ELF absence 结论建议再限定为 direct-literal host scan

该段已正确保留“GSP reset 内部未知”的 caveat，因此不是硬错误；但“一共只出现 11 次，均属于……”容易被读成架构级穷尽。建议替换最后两句为：

> 在当前 MODS x86-64 ELF 的 direct-literal constant scan 中，已见 `0x404f0000` 使用点不包括正常 `GB20xPostSwProgram90` 或已审计的 direct-shadow success/failure tail。因此可说“这些 host 路径不主动发出已知 clear constant”。该负结果不排除间接/动态 RegHal 构造、其他版本/模块、GSP/FSP/GFW 或 reset 硬件状态机改变 latch。

### C3. `:1949-1950` — reset/冷断电不能写成已证明的失败恢复

主文档自身 `:741-746`、`:1174-1178` 和 `parallel/evidence_audit.md:344-350` 都说恢复语义未闭合。

建议替换：

> 一旦失败只能立即停止进一步操作；device reset、resense 或冷断电是否清除 latch/partial raw state 目前都没有被证明，不能预先称为恢复方案。任何未来实验之前必须先取得独立、可验证的 rollback/recovery 证据。

## D. repair / self-test 能力表述

### D1. `:311-321` — generic repair 代码存在不等于 GB202 能执行

建议替换段首为：

> 当前 inner GSP 中确有 generic LTS-repair 实现、reset-choice/no-spare 文案及真实代码引用；这证明共享实现不是纯死字符串，不证明 GB202 dispatch 可达。`RMCFG_FEATURE_LTS_REPAIR=1` 也只表示通用功能族被编入。

随后应立即接 GB202 结论：

> 新的 bounded constructor replay 已静态证明：GB202 index 65 的 repair slot `+0x188` 和 marking helper `+0x1b0` 都绑定 16-byte zero-return stub，而非 generic repair/marking 实现（`parallel/tmux_gsp_l2_repair.md:26-39`；`parallel/gsp_inforom_vtable_replay.py`）。因此当前 610 的共享 repair 文案不能写成 GB202 可用 repair 能力。

### D2. `:344-352,1907` — no-op 绑定不应再保留为 REPORT-ONLY

这不是“能力过强”，而是新证据使旧等级陈旧。建议把 `:346-350` 的“尚未归档 replay、REPORT-ONLY”替换为：

> 当前已归档 bounded constructor replay；GB202 index 65（group 2 low index 1）使 mask `0x3001` 的 bit 1 为 0，从而把 `+0x188` 绑定到 `0x1975824` zero-return stub，并把 `+0x1b0` 绑定到另一个 zero-return stub。该具体 HAL 绑定现为 `V-STATIC`。

同时把可行性表 `:1907` 更新为：

> GSP/InfoROM LTS repair | generic 等量 swap 实现存在；当前持久化重放证明 GB202 repair/marking slots 为 zero-return stubs；没有 client repair 入口，也不能支持扩容或逐 LTS 修复

### D3. `:1878,1894,1897-1898` — “self-test”必须明确是离线软件自测

建议统一改名为 `offline parser/encoder self-test`，并添加：

> 这些测试只验证 schema、布局、CRC 和 synthetic/internal vectors；不执行硬件 BIST，不验证 L2 data/tag/set/way/bank，也不证明本卡 mask、容量模型或 disabled-unit health。

### D4. `:1914-1942` 已是正确的能力边界，不建议削弱

该节正确区分了 topology GET、MIG/ECC N/A、CUDA hint、缺失的 `0x208f050f` dispatch、fault injection 与 BIST，并明确说不能形成逐-slice健康证书。建议保留，作为 repair/self-test 的总判定。

## 已经正确收窄、无需再改的段落

- `:47-81` 已把 96 MiB/8 FBP/96 NCU `l2s`/48 rollup 与 `16 LTC`、`8 x 0x12`、SW=0 分层。
- `:70-74` 已把 16 bit、32 MiB、128 MiB 明确写成依赖报告的 accounting model。
- `:269-273` 已把 SW=0 明确降为未归档报告。
- `:1627-1638` 已对 `0x12`、2 MiB/bit、16 bit/32 MiB 使用条件句；只需由 B4 避免后文又升级成确定物理单元。
- `:731-746` 和 `:1069-1078` 已正确区分 failure-tail 无 rollback 与 resense 有 clear-coded operation。
- `:1914-1942` 已正确结论为“当前 610 没有逐 LTS 的受支持隔离或完整性自检入口”。

## 建议的全局术语规则

后续主文档统一使用以下四种名称，可避免再次回退：

1. `96 NCU l2s attributes`：归档 `V-RUNTIME`，不改称物理 slice。
2. `48 anonymous PerfWorks LTS rollup domains/classes`：归档 `V-RUNTIME`，无绝对实例 ID。
3. `48 active mask-bit units`：只有在 `8 x 0x12` 报告准确时才由 accounting model 推得，等级为 `REPORT-ONLY + INFERRED`。
4. `16 LTC`：未归档 topology-probe 返回，保持 `REPORT-ONLY`；16 DRAM rollup 不能替代 16 LTC。

“一个 mask bit = 2 MiB = 一个 rollup = 两个 NCU l2s”只能称为最简数值模型，不能写成已索引物理映射。
