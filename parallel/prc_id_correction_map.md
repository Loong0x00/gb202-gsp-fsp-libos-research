# PRC ID 纠错的全项目 Markdown 影响图

日期：2026-07-21  
范围：`/home/user/rt_5090_project` 当前可见 `*.md`  
方式：`rg` 精确名称/`0x1c` 检索、相邻 ID 映射检索及相关段落人工复核；没有修改
任何既有报告，没有运行 MODS，也没有访问 GPU。

## 结论

MODS 570.151 的正确连续映射为：

```text
0x1b  PRC_KNOB_ID_RRL_ALLOW_INB
0x1c  PRC_KNOB_ID_RPR_ALLOW_INB
0x1d  PRC_KNOB_ID_FLOORSWEEPING_ALLOW_INB_ONE_SHOT
0x1e  PRC_KNOB_ID_HBM_FREQ_CHANGE_ALLOW_INB
0x1f  PRC_KNOB_ID_ROW_REMAP_ALLOW_INB
0x20  PRC_KNOB_ID_ROW_REMAP
0x21  PRC_KNOB_ID_HULK_ALLOW_INB
0x22  PRC_KNOB_ID_HULK
0x23  PRC_KNOB_ID_FORCE_RESET_COUPLING_ALLOW_INB
0x24  PRC_KNOB_ID_FORCE_RESET_COUPLING
```

初次影响扫描定位到六组把 floorsweeping one-shot 当成 `0x1c` 的 Markdown。
共享工作树随后按本清单同步完成了纠正；本报告落盘后的最终复扫中，**没有剩余
topical `0x1c` stale 命中**。当前 Markdown 也没有发现
ROW_REMAP/HULK/FORCE_RESET_COUPLING 六项仍使用整体少一位的旧 ID。

## 1. 已识别并已修正的 floorsweeping `0x1c` 位置

以下位置在初扫时把 `0x1c` 指向目标 floorsweeping one-shot knob。当前共享树均已
改成 `0x1d`，并在需要之处补了记录边界说明；表格保留为影响追踪记录。

### 1.1 项目索引/任务描述

| 文件 | 行 | 处理 |
|---|---:|---|
| `GB202_PARALLEL_WORK.md` | 96 | **已修正：** 显示 PRC `0x1d`，并注明旧报告文件名保留了纠错前 ID |
| `GB202_PARALLEL_WORK.md` | 109（初扫时 108） | **已修正：** follow-up 目标改为 `0x1d` record；metadata 报告已完成该项 |

### 1.2 旧 MODS 交叉核对

| 文件 | 行 | 处理 |
|---|---:|---|
| `parallel/mods_final_crosscheck.md` | 84 | **已修正：** `0x1d`，并明确 `0x1c=RPR_ALLOW_INB`；host read/write/readback 结论不变 |
| `parallel/tmux_mods_permissions.md` | 46, 47, 62, 117 | **已修正：** 全部使用 `0x1d`，并以 `parallel/prc_knob_metadata.md` 取代旧 ID-store 解释 |
| `parallel/inbox/tmux_mods_permissions.done.md` | 15 | **已修正：** unresolved question 使用 `0x1d` 并附 metadata 纠错来源 |

初扫还发现 `parallel/tmux_mods_permissions.md:46` 引用了旧主报告行号；当前版本已
改为直接引用 metadata 报告，避免只机械替换数字 ID。

### 1.3 autoinject 报告

`parallel/prc_autoinject_audit.md` 初扫命中的六处现均已改为 `0x1d`；当前行号为：

```text
12, 24, 63, 73, 75, 77
```

其中当前 `:63` 已补充“callers 都以名称进入 resolver，旧 ID 错配不改变二进制
行为”。更严格的等价表述是：

> 四个 direct writer callers 中，三个专用 caller 只构造 IST/CCD 名称，另一个
> 是通用 map executor；没有专用 caller 构造 floorsweeping one-shot 名称，因而
> 没有 caller 经 name->ID resolver 自动得到 `0x1d`。

这样不会把“审查四个 caller 的可见输入”夸大成“对整个大 ELF 的所有立即数
`0x1d` 做了语义完备搜索”。

### 1.4 公开源码审计

`parallel/prc_1c_public_audit.md` 的文件名建立在旧 ID 上。正文现已加 erratum，
标题和下列 topical 位置均已改为 `0x1d`：

```text
1, 4
48, 50-52, 57
88, 104-107
149, 177
231
263
286
294
302
```

修订没有做全文件机械替换：

- 当前 `:101` 的 `#define NVDM_TYPE_UEFI_RM 0x1C` 是真实、独立的 NVDM
  常量，已正确保留；
- 当前 `:104-107` 已明确目标是 `0x1d`，早期 `0x1c` 只造成表面碰撞，纠错后
  数值也不相同；
- 当前 `:276` 继续保留 `NVDM_TYPE_UEFI_RM=0x1c` 不属于 PRC knob 的事实。

报告文件采用了第一种兼容策略：

1. 保留历史路径 `prc_1c_public_audit.md`；
2. 标题改成 `0x1d`，开头加入“`0x1d`/`0x1c=RPR`”erratum；
3. `GB202_PARALLEL_WORK.md` 明确说明文件名保留旧 ID。

因此无需改现有链接；文件路径本身不会改变证据。

## 2. 已经正确、不要反向改回的 PRC `0x1c`

以下 `0x1c` 现在表达的是纠错事实或真正的 RPR knob，应保留：

| 文件 | 行 | 含义 |
|---|---:|---|
| `L2_REENABLE_STATIC_FINDINGS.md` | 1403, 1407 | 说明旧误判，并正确列出 `0x1c=RPR_ALLOW_INB` |
| `parallel/task2_lifecycle_audit.md` | 255 | 明确说明 `0x18603d4` 的 `0x1c` 属于前一条 RPR 记录 |
| `parallel/prc_knob_metadata.md` | 18, 30, 53, 194 | 纠错说明、RPR 邻接记录和最终映射 |

`parallel/prc_knob_metadata.md:62` 的 `+0x1c` 是 floorsweeping 名称 payload 的
**字符串内写入偏移**，不是 knob ID，也必须保留。

## 3. 与 PRC ID 无关的 `0x1c`

全项目 `0x1c` 检索还命中以下独立命名空间/结构偏移，不应修改：

| 文件 | 行 | 含义 |
|---|---:|---|
| `L2_REENABLE_STATIC_FINDINGS.md` | 1084 | debug-token 结构的 `usageCounter` 字段偏移 `+0x1c` |
| `parallel/prc_1c_public_audit.md` | 101（以及当前 104-107、276 的说明） | `NVDM_TYPE_UEFI_RM=0x1C`，顶层 NVDM type |
| `isa_re/results/sr_index_catalog.md` | 35 | SASS special-register index `SR_AFFINITY=0x1c` |
| `mods_audit/nvapi_610_raw.md` | 73 | thermal 结构字段偏移 `+0x1c` |
| `mods_audit/thermal_re.md` | 121 | thermal `NvTemp` 字段偏移 `+0x1c` |
| `hotspot_reader/gsp_therm_current_evidence.md` | 178 | RM envelope 内的字段偏移 `+0x1c` |

数值相同不代表协议对象相同；这些命中均不参与 PRC name->ID 表。

## 4. ROW_REMAP/HULK/FORCE_RESET_COUPLING 旧偏移审计

同一 `0x28`-byte 表的后续 ID store 为：

```text
0x1860556  [rsp+0x528] = 0x1f  ROW_REMAP_ALLOW_INB
0x18605d0  [rsp+0x550] = 0x20  ROW_REMAP
0x1860648  [rsp+0x578] = 0x21  HULK_ALLOW_INB
0x18606b4  [rsp+0x5a0] = 0x22  HULK
0x1860738  [rsp+0x5c8] = 0x23  FORCE_RESET_COUPLING_ALLOW_INB
0x18607b0  [rsp+0x5f0] = 0x24  FORCE_RESET_COUPLING
```

旧的相邻错配会把它们分别写成 `0x1e/0x1f/0x20/0x21/0x22/0x23`。对当前
所有 Markdown 做名称与这些新旧 ID 的同段/同表检索后：

- 只在 `L2_REENABLE_STATIC_FINDINGS.md:1422-1427` 找到完整数值映射；该表已经
  全部正确；
- `L2_REENABLE_STATIC_FINDINGS.md:1045-1046` 的
  `0x21=HULK_ALLOW_INB`、`0x22=HULK` 也正确；
- `parallel/prc_knob_metadata.md:56` 的 `0x1f=ROW_REMAP_ALLOW_INB` 正确；
- 其余 HULK Markdown 命中讨论的是 `NVDM_TYPE_HULK=0x11`，不是 PRC knob
  `0x21/0x22`；
- **没有发现仍把上述六项写成旧偏移 ID 的现存 Markdown 位置。**

## 5. `prc_autoinject_audit` 的 native negative 是否仍成立

**成立；仅 ID 文案需要从 `0x1c` 修成 `0x1d`。** 理由分三层：

1. JS negative 依赖的是 `g_FspPrcWriteArray` 默认空、只有显式
   `ArgFspPrcWrite()` push，以及可见脚本中不存在完整 floorsweeping 名称；它与
   数字 ID 无关。
2. `.text` direct-call 扫描得到的 writer executor callers 仍只有：

   ```text
   0x123fcd4  通用保存 map
   0x1ebc909  PRC_KNOB_ID_IST = 1
   0x1ef55c3  PRC_KNOB_ID_CCD = 1
   0x1ef6128  PRC_KNOB_ID_CCD = 0
   ```

   三个专用 caller 都按名称构造 IST/CCD；没有 floorsweeping 专用 caller。通用
   caller 只会执行外部已放入的 map，不会自行合成目标项。
3. executor 的真实路径是“名称 -> `0x1858280` resolver -> ID”。纠正表布局后，
   floorsweeping 名称会解析为 `0x1d`；这不会凭空增加新的 caller，也不改变默认
   map 为空的事实。

因此可保留原报告的限界结论：**当前可见 JS/native direct 路径不会在无显式输入
时自动注入 floorsweeping one-shot 请求。** 仍需保留原有 caveat：该 negative
不覆盖动态间接 caller、未解码/未包含模块、FSP 启动默认值或 firmware 内部
policy。

## 6. 最终复扫状态

修订完成后重新执行全项目 `0x1c`、完整 floorsweeping 名称和相邻系列名称/ID
检索，结果为：

1. `GB202_PARALLEL_WORK.md`、`parallel/prc_autoinject_audit.md`、
   `parallel/mods_final_crosscheck.md`、`parallel/tmux_mods_permissions.md`、
   `parallel/inbox/tmux_mods_permissions.done.md` 的 topical ID 均为 `0x1d`；
2. `parallel/prc_1c_public_audit.md` 正文主题为 `0x1d`，旧文件名已有明确 erratum；
3. 剩余 `0x1c` 均属于 RPR 记录、纠错说明、字符串/结构偏移、SASS SR index 或
   `NVDM_TYPE_UEFI_RM`；
4. ROW_REMAP/HULK/FORCE_RESET_COUPLING 的六项映射均为
   `0x1f..0x24` 的正确序列；
5. autoinject 的 JS/native bounded negative 经 ID 纠错后仍成立，证据和 caveat
   均未改变。
