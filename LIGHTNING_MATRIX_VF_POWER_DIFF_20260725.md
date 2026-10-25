# RTX 5090 Lightning / Matrix VBIOS V/F 与功耗策略差分

日期：2026-07-25

范围：只读本地 ROM 文件。未刷写 VBIOS，未访问当前 GPU，未改动驱动、频率、电压、功耗或风扇。

## 样本

| 文件 | 用途 | SHA-256 |
|---|---|---|
| `Asus.RTX5090.32768.250115.rom` | Astral OC 600 W 对照 | 见本地 corpus |
| `Asus.RTX5090.32768.251013.rom` | Matrix 800 W | `4c772b46b2df424b94c4c71fffece98da96375c5d2699ce0bfcd1a51828015dd` |
| `Asus.RTX5090.32768.251013_1.rom` | Matrix 600 W 变体 | 见本地 corpus |
| `Asus.RTX5090.32768.251013_2.rom` | Matrix 600 W 变体 | 见本地 corpus |
| `281640.rom` | MSI Lightning 800 W | `9ae22a0b80836ac80b60b4bcada3c1867daf224a645009225b2fd239d9751e0b` |
| `281649.rom` | MSI Lightning 1000 W | `5dabed819ca9b8a63756444421c46287d95115d51c091fe95cd7594c50873abc` |
| `281814.rom` | Astral 2001 W XOC 反例 | `0a1a511e72d707f513aab02a1d1ccfa8a78347d56915b0c922398724193ec97d` |

GB202 BIT `P` 的大表指针需加 PCI expansion gap；`P+0x68/0x6c/0x70` 的 Voltage Rail/Device/Policy 小指针直接相对 legacy-image base。下述差分已按这一混合基址规则重新读取。

## 核心结论

Lightning 800 W 与 Matrix 800 W 在下列与核心 V/F 直接相关的表中逐字节相同：

- `PERFORMANCE`；
- `BASE_CLOCK`；
- `VOLTAGE_MAP`（`0x1cf1` bytes）；
- `VOLTAGE_RAIL` v0x30（`0x87` bytes）；
- `VOLTAGE_DEVICE` v0x10（`0x104` bytes）；
- `VOLTAGE_POLICY` v0x20（`0x09` bytes）；
- `FactoryOC/OVERCLOCKING` v0x10（`0x1b` bytes）；
- `THERM_CHANNEL` 和 `THERM_POLICY`；
- 已识别的 Low Power 策略表。

两份 Lightning 800/1000 W 之间，上述所有 V/F/电压/热策略表也不变。Matrix 600/800 W 同板配对之间也是同样结果。

因此，Lightning 800/1000 W 和 Matrix 800 W 不属于 Astral/GALAX 2001 W 那类将 `VOLTAGE_RAIL` 索引从 `3,4` 改为 `6,6` 的固定高压 XOC 配置。静态证据支持它们保留常规运行时 V/F 调节路径。

## `FactoryOC/OVERCLOCKING` 表

该表不是旧 envytools 所假定的单一 `header + record_size * count` 布局。7-byte 头部是：

```text
10 07 05 02 05 02 00
```

它后面包含两组子记录：两条 5-byte `Clocks` 记录，再加两条 5-byte `Vpstate` 记录，因此总长度是 `7 + 2*5 + 2*5 = 0x1b` bytes。MODS/RM 字符串也分别存在 `FactoryOC Table Clocks entry` 和 `FactoryOC Table Vpstate entry` 的解析报错。

完整 raw 内容为：

```text
Astral 600 W:
10 07 05 02 05 02 00
01 c8 af 00 00  00 00 00 00 00
00 00 00 00 00  01 20 5e 27 00

Matrix 800 W / Lightning 800 W / Lightning 1000 W:
10 07 05 02 05 02 00
01 b8 f9 02 00  00 00 00 00 00
00 00 00 00 00  01 10 a8 29 00
```

第 0 条 `Clocks` 记录是 `type=1` 加一个 little-endian `u32`：

```text
Astral 600 W             45000
Matrix/Lightning        195000
差值                    150000
```

第 0 条 `Vpstate` 记录是全零占位；第 1 条 `Vpstate` 记录同时变化：

```text
Astral 600 W        2580000 kHz = 2580 MHz
Matrix/Lightning    2730000 kHz = 2730 MHz
差值               150000 kHz =  150 MHz
```

该字段的名称和用途已由本地 MODS/RM 文本交叉确认：解析器将 `P+0x98` 称为 `FactoryOC Table`，记录称为 `FactoryOC Table Clocks entry`；后续执行路径明确报告“使用 factory OC offset 调整 P-state frequency tuple”，MODS 的 `PrintFactoryOCSettings()` 诊断接口描述为“打印 RM 时钟域的 factory OC frequency delta”。

数值单位也与 kHz 一致：Matrix 与 Astral OC 的公称 Boost 差恰为 150 MHz，两类记录的差值也都恰为 150000。因此 `Clocks` 记录可确认为 VBIOS 内置核心时钟偏移，第 1 条 `Vpstate` 记录则与出厂 Boost/vPstate 目标对齐；它们都不是电压滑块启用位或 V/F 手动调节上限。

这也说明：Matrix/Lightning 在不替换基础 `VOLTAGE_MAP` 的前提下，预先加了比 Astral OC 多 150 MHz 的核心 offset。

RM 文本还明确显示 factory OC offset 用于调整 `PSTATE freq tuple`，所以它不只是 GPU-Z 之类工具显示的标称字段。它在 PERF/PSTATE 状态构建时进入实际频率元组；LACT/Afterburner 的用户 V/F offset 则是状态建立后通过 RM 调优接口施加的另一层。因此执行顺序可记为“基础元组 → factory OC 调整 → 运行时用户调优”。

尚不能从静态文本确认的是：驱动对用户 offset 的最终上限，是只约束用户层增量，还是约束加上 factory OC 后的总增量。因此不能先验地把 150 MHz 当成可与现有 LACT 曲线无上限叠加的“免费频率”。

### 旧版 `GET_LEVEL_INFO` 只读实验的否定结果

曾尝试用公开头文件中的只读命令 `NV2080_CTRL_CMD_PERF_GET_LEVEL_INFO_V2`，直接区分 default 与 overclock 频率范围。所有试过的参数组合都返回 `NV_ERR_INVALID_ARGUMENT (0x1f)`。这不是继续枚举参数就可能解决的 Blackwell 查询路径，610.43.03 开源 Kernel-RM 已给出原因：

- `subdeviceCtrlCmdPerfGetLevelInfo_V2_VF()` 一进入就把调用者的 `flags` 强制清零，因此调用者无法借此选择 factory/default/overclock 类型；
- 随后它调用旧的 `NV_RM_RPC_PERF_GET_LEVEL_INFO`；
- 生成的 RPC HAL 表明确把 GB202 绑定到 `rpcPerfGetLevelInfo_STUB`。

所以该遗留接口无法回答“195 MHz factory OC 是否占用用户 offset 上限”。为避免无意义重复查询，这个旧实验分支已从本地只读探针中删除；后续验证改用 MODS 实际使用的现代 Clock Domains GET control，不再继续碰这个旧 RPC。

### 现代 Clock Domains 只读查询：factory OC 与用户范围确实分字段

继续逆向后，MODS 真正用于读取手动超频范围的接口已定位为：

```text
JsPerf.GetOverclockRange(domain, out)
  -> PERF 虚表 +0x410
  -> MODS 原生实现 0x1665220
  -> out.MinOffsetkHz / out.MaxOffsetkHz
```

该实现不会临时计算范围；它从 `0x20809019` 返回的 Clock Domains Info 缓存中读取两个有符号 16-bit MHz 值，再乘 1000 返回 kHz。MODS 的旧结构大小是 `0x26b0`、每域 `0x134` bytes；当前 610.43.03 GSP 方法表中同一只读命令大小为 `0x3030`、每域 `0x180` bytes。当前 GSP 的方法记录为：

```text
0x20809019  size=0x3030  handler=0x010dd19c  flags=0x48
```

对当前 Astral 5090 实际执行一次该只读 GET，GPC 记录返回：

```text
api_domain          = 0x00000001 (GPC)
MinOffset           = -1000 MHz
MaxOffset           = +1000 MHz
FactoryClockOffset  = +45000 kHz = +45 MHz
```

同一条记录中，手动 offset 的 `-1000/+1000 MHz` 范围与 factory offset 的 `+45 MHz` 是三个独立字段。内存域也给出独立的 `-1000/+3000 MHz` 范围。这个运行时结构证据比静态执行顺序更进一步：**factory OC 并没有通过把手动滑块的 `MaxOffset` 从 1000 减到 955 来“占掉额度”**。Matrix/Lightning ROM 中的 `+195 MHz` 仍应进入 factory 字段，而用户调节范围保留为独立字段；最终频率依然会受频点表、功耗候选、可靠性和稳定性约束。

另一条只读命令 `0x2080901a`（单域 Info，当前和 MODS 均为 `0x804` bytes）对 GPC 返回 459 个离散频点，范围是 `15–3450 MHz`。这只说明 3.2 GHz 等频率存在于可枚举时钟表内，不代表硅片、V/F 或游戏负载允许实际稳定运行到那里。

本次运行时验证只发出 GET control；没有 SET、MMIO、复位、驱动卸载或 VBIOS 写入。

## 功耗和电流额度

`POWER_BUDGET` v0x40 中定位到的有效策略值如下。单位由本机 GSP `PowerPoliciesGetInfo/DynamicStatus` 和 MODS 的 `limitUnit` 映射交叉确认：

| VBIOS | 整卡/组合功耗额度 | 总输入电流额度 | NVVDD 电流额度 | MSVDD 电流额度 |
|---|---:|---:|---:|---:|
| Astral 600 W | 600 W | 60 A | 480 A | 180 A |
| Matrix 600 W | 600 W | 60 A | 480 A | 180 A |
| Matrix 800 W | 800 W | 80 A | 480 A | 180 A |
| Lightning 800 W | 800 W | 80 A | 720 A | 240 A |
| Lightning 1000 W | 1000 W | 100 A | 720 A | 240 A |

同板配对证据：

- Matrix 600 → 800 W 仅在 `POWER_BUDGET` 内将三组 600000 mW 改为 800000 mW，并将两组 60000 mA 改为 80000 mA；
- Lightning 800 → 1000 W 仅将同类三组 800000 mW 改为 1000000 mW，并将两组 80000 mA 改为 100000 mA；
- Lightning 800/1000 W 的 NVVDD/MSVDD 轨级 720/240 A 不随整卡 800/1000 W 档切换而变。

这表明 Matrix 800 W 主要抬高整卡总预算，Lightning 则还额外放宽了 NVVDD/MSVDD 的轨级电流预算。对于会出现明显电流瞬变的光追游戏，这是 Lightning 相对 Matrix 更有可能减少 PMU 功耗/电流候选降频的一项实质差别。这只是策略余量判断，不保证具体芯片能稳定达到某个频率。

## 热策略与 Astral 2001 W 的区别

Astral 600 W、Matrix 800 W 与 Lightning 800 W 的 `THERM_CHANNEL` 和 `THERM_POLICY` 表逐字节相同。Matrix 600/800 与 Lightning 800/1000 的同板配对也没有任何热策略开关变化。

相比之下，Astral 2001 W 会停用 `THERM_POLICY` 的若干记录，并将 Voltage Rail 两个索引改为 `6,6`。因此 Lightning/Matrix 的 800/1000 W 档是“保留常规保护与 V/F 调节，放宽预算”，而 Astral 2001 W 更接近“固定高压、停用部分护栏”的纯 XOC 策略。

## 板级差异（不当作 V/F 限制）

Lightning 为双 16-pin 输入水冷板，Matrix 为 16-pin/BTF 供电拓扑，Astral Black 为单 16-pin 且两路风扇控制拓扑。它们在下列表中存在预期的板级差异：

- `POWER_SENSE`；
- `POWER_TOPOLOGY`；
- `FAN_COOLERS`；
- `FAN_MGMT`；
- `FAN_TEST`。

这些差异决定跨刷后的功耗遥测、输入分路和风扇行为，但不是 Lightning/Matrix 保留 V/F 调节的原因。本记录不将双输入拓扑进一步当作当前主线。

## 对当前 2.7–2.8 GHz 游戏墙的含义

Lightning/Matrix 并没有提供一条不同的基础 V/F 曲线或不同的电压策略算法。它们做的主要是：

1. 预置比 Astral OC 多 150 MHz 的核心 offset；
2. 抬高整卡功耗和总输入电流预算；
3. Lightning 另外抬高 NVVDD/MSVDD 轨级电流预算。

因此，它们有可能让当前游戏中约 2.8 GHz 的 `PMU_DOM_GRP_1` 功耗候选向上移动，但不会消除芯片本身的 `OVERVOLTAGE/RELIABILITY`、温度和稳定性边界。“会尝试更高”与“芯片可以稳定更高”仍是两件事。
