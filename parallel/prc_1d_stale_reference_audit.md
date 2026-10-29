# `FLOORSWEEPING_ALLOW_INB_ONE_SHOT` 旧 `0x1c` 引用复扫

日期：2026-07-22
状态：**完成；纯 Markdown 文本审计**

## 结论

对本报告创建前 `/home/user/rt_5090_project` 的 142 个既有 Markdown 文件复扫后，
**没有发现仍把
`PRC_KNOB_ID_FLOORSWEEPING_ALLOW_INB_ONE_SHOT` 的现行 ID 事实性写成 `0x1c`
的位置**。当前规范映射一致为：

```text
0x1c  PRC_KNOB_ID_RPR_ALLOW_INB
0x1d  PRC_KNOB_ID_FLOORSWEEPING_ALLOW_INB_ONE_SHOT
```

剩余相关命中分为两类：

- **(a) 已纠正历史说法的明确引用**：正文同时说明现行 ID 是 `0x1d`，`0x1c`
  是旧误判或前一条 RPR record；不误导，无需修改。
- **(c) 文件名兼容项**：`parallel/prc_1c_public_audit.md` 的路径保留旧 ID，但标题、
  开头 erratum 和正文均已纠正为 `0x1d`。部分报告仍引用这个历史路径；路径本身
  不是现行 ID 断言。

类别 **(b) 当前仍会误导读者的事实陈述：0 处**。

本轮只读取 Markdown；没有执行 MODS、项目程序、固件或其他目标二进制，没有
访问 GPU、设备节点、BAR/MMIO、PCI config、debugfs 或实时驱动状态，也没有修改
任何既有报告。

## 检索口径

本轮交叉使用三组文本条件：

1. 完整名称及稳定子串：
   `FLOORSWEEPING_ALLOW_INB_ONE_SHOT`、`ALLOW_INB_ONE_SHOT`；
2. 全项目 Markdown 中的 `0x1c`/`0x1C`；
3. 历史路径 `prc_1c_public_audit.md`。

结果规模（不含本审计报告自身）：12 个 Markdown 含目标完整名称/子串，17 个
Markdown 含某种
`0x1c/0x1C`，4 个 Markdown 正文引用历史文件名。随后对同时含 floorsweep/
one-shot 与 `0x1c` 或历史路径的文件逐段人工复核，避免只按同一行匹配而漏掉
跨行关系。

## (a) 明确作为已纠正历史说法的引用

下列位置都明确给出 `0x1d` 为当前 ID，并把 `0x1c` 限定为旧误判或真实的
`RPR_ALLOW_INB`；最小修订建议均为 **保留原文**。

| 文件与行 | 当前语义 | 最小修订建议 |
|---|---|---|
| `L2_REENABLE_STATIC_FINDINGS.md:1855-1863` | 明说精确 ID=`0x1d`；解释此前 `0x1c` 是 record-boundary 错配，并列出 `0x1c=RPR` | 保留 |
| `parallel/prc_1d_domain_followup.md:55-65` | 标题绑定 `0x1d`；同一 record store=`0x1d`，前一项 RPR 才是 `0x1c` | 保留 |
| `parallel/task2_lifecycle_audit.md:252-263` | `FACT（纠正旧记录错配）`；目标 store=`0x1d`，`0x1c` 属于前一条 RPR record | 保留 |
| `parallel/prc_knob_metadata.md:15-33` | 明写“`0x1d`，不是 `0x1c`”，并解释两个 record 基址 | 保留；这是规范纠错证据 |
| `parallel/prc_knob_metadata.md:50-65` | 连续映射表正确列出 `0x1c=RPR`、`0x1d=floorsweeping`；`:62` 的 `+0x1c` 是字符串对象内偏移 | 保留，勿把 `+0x1c` 机械替换 |
| `parallel/prc_knob_metadata.md:188-194` | 最终判定再次区分目标 `0x1d` 与 RPR `0x1c` | 保留 |
| `parallel/prc_autoinject_audit.md:21-28` | 自动注入 negative 使用 `0x1d`；相邻说明 `0x1c` 属于 RPR | 保留 |
| `parallel/prc_1d_value_semantics.md:8-14` | 当前连续映射表正确 | 保留 |
| `parallel/prc_1d_value_semantics.md:54-63,328` | record 证据和最终 FACT 均明确“`0x1d`，不是 `0x1c`” | 保留 |
| `parallel/mods_final_crosscheck.md:84` | 标为 `ID 后续纠正`，明确目标=`0x1d`、RPR=`0x1c` | 保留 |
| `parallel/tmux_mods_permissions.md:46` | 标为 `ID corrected`，明确目标=`0x1d`、RPR=`0x1c` | 保留 |
| `parallel/prc_1c_public_audit.md:3-5,104-107` | 开头说明文件名来自早期误判；正文区分目标 `0x1d` 与独立 NVDM `UEFI_RM=0x1C` | 保留；同时属于类别 (c) |
| `parallel/prc_id_correction_map.md:14-15,25-33` | 给出正确连续映射，并把 `0x1c` 命中描述为“初扫时/已修正” | 保留 |
| `parallel/prc_id_correction_map.md:39-48,73-102,104-115,159,186-194` | 影响追踪、兼容文件名策略、正确 RPR/偏移保留项及最终复扫结论 | 保留；这些是历史审计记录，不是现行 `0x1c` 断言 |

另外两个含目标名称但没有 `0x1c` 关系的文件也已核对：

- `parallel/task2_auth_provenance.md:322` 正确写为 `0x1d`；
- `parallel/gb202_fuse_descriptor_inventory.md:274` 只记录目标字符串查询，未声称
  numeric ID。

## (b) 当前仍会误导读者的事实陈述

**未发现。**

具体来说，没有任何当前 Markdown 同时满足以下条件：

1. 把 `0x1c` 作为目标 knob 的现行 ID；且
2. 没有在同段、同表或文件开头明确纠正为 `0x1d`。

因此本类别没有强制修订项。若未来新增报告，建议第一次出现目标名称时直接使用：

> `PRC_KNOB_ID_FLOORSWEEPING_ALLOW_INB_ONE_SHOT = 0x1d`

不要仅写“floorsweep knob `0x1c`”，也不要从历史文件名反推 numeric ID。

## (c) 文件名保留旧 ID、正文已纠正

### 规范文件本体

| 文件与行 | 判定 | 最小修订建议 |
|---|---|---|
| `parallel/prc_1c_public_audit.md:1,3-5` | 文件名保留旧 `1c`；标题已经是 PRC `0x1d`，开头明确 `0x1d=floorsweeping`、`0x1c=RPR` | 无需重命名；保留兼容路径和 erratum |

直接重命名会破坏现有引用，而正文已经自校正，收益小于链接迁移成本。

### 对历史文件名的引用

| 文件与行 | 上下文是否自解释 | 最小修订建议 |
|---|---|---|
| `GB202_PARALLEL_WORK.md:120-122` | 是；紧邻文字明确 `0x1d` 且说明 filename retains earlier ID | 保留 |
| `parallel/prc_id_correction_map.md:73-102,124,192` | 是；专门解释旧文件名、兼容策略和独立 `NVDM_TYPE_UEFI_RM=0x1C` | 保留 |
| `L2_REENABLE_STATIC_FINDINGS.md:1930-1934` | 基本是；链接前四行已明确目标是 `0x1d`，但文件名本身未在此处解释 | 无强制修改；若追求局部自解释，可在链接后加“（历史文件名，正文已纠正为 `0x1d`）” |
| `parallel/fsp_task2_consumer_followup.md:31-34` | 较弱；仅把历史文件名列在复用材料中，本段没有解释 `1c` | 建议最小加注“`prc_1c_public_audit.md` 为历史兼容名，正文主题是 `0x1d`” |

后两处裸路径不构成类别 (b)：它们没有声称目标 ID 是 `0x1c`，且被引用文件开头
已有明确 erratum。建议加注只为降低跳转前的视觉歧义。

## 非 PRC-ID 的 `0x1c` 命中

以下命中不属于 (a)/(b)/(c)，列出以证明没有机械替换遗漏：

| 文件与行 | 实际命名空间 |
|---|---|
| `parallel/prc_knob_metadata.md:62` | floorsweeping 名称字符串对象内的 `+0x1c` 写入偏移 |
| `parallel/prc_1c_public_audit.md:101,104-107,276` | 顶层 NVDM message type `UEFI_RM=0x1C` |
| `L2_REENABLE_STATIC_FINDINGS.md:1386` | debug-token response 的 `usageCounter` 结构偏移 |
| `parallel/deviceinfo_class10_identity.md:115` | DeviceInfo translation 表值 |
| `parallel/effective_setter_provenance.md:175` | method/field offset |
| `parallel/reset_getter_internal_fields.md:240` | `runlistPriBase` 结构偏移 |
| `isa_re/results/sr_index_catalog.md:35` | SASS special-register index `SR_AFFINITY` |
| `mods_audit/nvapi_610_raw.md:73`、`mods_audit/thermal_re.md:121` | thermal 结构字段偏移 |
| `hotspot_reader/gsp_therm_current_evidence.md:178` | RM envelope 字段偏移 |

这些位置均不应改成 `0x1d`。

## 最终判定

1. **(a) 历史纠错引用：存在，均已自解释，保留。**
2. **(b) 仍误导的现行事实陈述：0 处。**
3. **(c) 历史文件名：1 个文件、4 个引用文件；正文/主索引已纠正。**
4. 唯一值得考虑的最小文档增强，是给
   `parallel/fsp_task2_consumer_followup.md:31-34` 的裸历史文件名加一条说明；
   `L2_REENABLE_STATIC_FINDINGS.md:1934` 可选同样注释。两项都不是事实修复。
