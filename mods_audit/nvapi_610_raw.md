# NVIDIA 610.43.03 private thermal GET 原始返回审计

日期：2026-07-14  
对象：RTX 5090 / GB202，驱动 610.43.03  
范围：只离线解析已经截获的四个 `NVOS54` 返回参数；本分析**没有发起新的 GPU 调用**，没有执行 MODS，没有写 MMIO。

状态词：

- **VERIFIED**：可由文件字节、精确结构尺寸、已安装 wrapper 的静态反汇编或两个样本的逐字节差异直接证明。
- **INFERRED**：和 MODS 570.151 的私有类型/名字及 channel graph 完全吻合，但 610 的私有 thermal 头文件未公开。
- **UNKNOWN**：现有字节不能可靠命名。

## 1. 样本

| RM control | 文件 | 大小 | SHA-256 |
|---|---|---:|---|
| `0x20808536` ThermalDeviceGetInfo | `nvos54_therm_855989_000_cmd_20808536_size_63d0_status_00000000.bin` | `0x63d0` | `961e2ef04431c4a676b307764027efebe536966907fe9f9e3fff9a8ce4d376d7` |
| `0x2080853a` ThermalChannelGetInfo | `nvos54_therm_855989_001_cmd_2080853a_size_3bf8_status_00000000.bin` | `0x3bf8` | `91e394619ac91d4285daea7f82b7f5ce78da76e9feeaa820fe33193d3cbfbcfc` |
| `0x2080853b` ThermalChannelGetStatus | `nvos54_therm_855989_002_cmd_2080853b_size_37f0_status_00000000.bin` | `0x37f0` | `679d40720899eff3326775d34e35304217c17fe5e24bb80c13f9b58f22012043` |
| `0x20808549` ThermalDeviceGetStatus | `nvos54_therm_856152_000_cmd_20808549_size_c1c_status_00000000.bin` | `0x0c1c` | `939390c9148248f33410e13c28aadf0a4b348cff6d906cd5c844f244d4e4a099` |

四个 RM status 都是 `0x00000000`。这些是 ioctl 完成后的 `params` 原样副本，不是 NvAPI 对外结构。

## 2. R610 已从 E32 扩为 E255

四个尺寸都能被一个且仅一个自然的 E255 布局精确解释：

| control | group header | record stride | record 数 | 尺寸恒等式 |
|---|---:|---:|---:|---|
| `8536` device info | `0x34` | `0x64` | 255 | `0x34 + 255*0x64 = 0x63d0` |
| `853a` channel info | `0x34` | `0x3c` | 255 | `0x34 + 255*0x3c = 0x3bf8` |
| `853b` channel status | `0x28` | `0x38` | 255 | `0x28 + 255*0x38 = 0x37f0` |
| `8549` device status | `0x28` | `0x0c` | 255 | `0x28 + 255*0x0c = 0x0c1c` |

所有 group：

```text
+0x00  u8       BOARDOBJGRP classType = 2
+0x01..03       padding
+0x04  u32[8]   E255 object mask
```

这里的首字节 `2` 是 `classType`，**不是 API version**。公开的 610
`ctrl2080boardobj.h` 直接定义了 E255 mask 为 8 个 `u32`、索引范围
0..254。Info group 还有 `0x10` 字节的私有 group data，故记录从 `0x34`
开始；status group 还有 `0x04` 字节，故记录从 `0x28` 开始。

- `853a/853b` mask 是 `0x00ffffff`：有效 channel 恰为 0..23。
- `8536/8549` mask 是 `0x007fffff`：有效 device 恰为 0..22。
- mask 外的全部 231/232 条记录逐字节为零；这些零不表示 0 °C。

另一个有用的边界结论：610 的 NvAPI V3 wrapper 对外只遍历 96 个 channel，
但底层原始 RM 结构实际容纳 255 个。本次完整 E255 mask 和 records 证明
96..254 也全部未置位且为零，所以 wrapper 的 96-slot 截断没有在高索引处漏掉
一个已实例化的 hotspot channel：**VERIFIED negative**。

以上均为 **VERIFIED**。

## 3. `0x2080853a` 的相关字段

R610 channel-info record 位于 `0x34 + 0x3c*i`。由 MODS 570 布局、610
wrapper 反汇编以及本次返回值共同确认的字段为：

```text
record +0x00 u8   channel class
       +0x01 u8   channel type
       +0x02 u8   relative location
       +0x03 u8   target GPU
       +0x08 s32  minimum NvTemp (Q24.8)
       +0x0c s32  maximum NvTemp (Q24.8)
       +0x14 s32  scaling (Q24.8)
       +0x18 s32  software offset (Q24.8)
       +0x1c s32  hardware offset (Q24.8)
       +0x20 u8   simulation/flag byte 0
       +0x21 u8   simulation/flag byte 1
```

`+0x04`、`+0x10`、`+0x22..+0x33` 中仍有私有 flags/interface data；在没有
610 私有头文件时不强行命名，状态为 **UNKNOWN**。

class-specific 字段：

- class 1 (`DEVICE`) 的 wrapper 分支读取 record `+0x25/+0x26` 作为
  device/provider 字节：**VERIFIED layout**。本机 24 个有效记录中 class 1
  数量是 **0**。
- class 2 (`PROVIDER_V10`) 的 wrapper 分支读取 `+0x34/+0x35`，并另行复制
  `+0x25..+0x28` 的 V10 interface data。`+0x34` 是 device index，可由下面的
  graph 交叉验证；`+0x35` 在全部 class-2 记录中为 0，按结构形状推断是
  device 内 provider index。前者 **VERIFIED**，后者名字 **INFERRED**。

有效记录的 class 分布为：

```text
class 2: channel 0,1,3,4,5,6,7,8        (8 条)
class 4: channel 2                       (1 条 aggregation)
class 3: channel 9..23                   (15 条 debug-v10)
class 1: none
```

因此，“853a 是否藏有 class 1 / device provider 6”的直接答案是：**没有**。
这不是只扫 NvAPI 对外枚举得出的结论，而是对完整 255-record RM 原始返回的扫描。

## 4. 容易误读的 `6`：它是 device index，不是 provider 6

`8536` device-info 的记录位于 `0x34 + 0x64*i`。raw class `0x14` 的六个
device 及其 record `+0x14` 低字节为：

| device index | raw device class | `record+0x14` | MODS provider 名 |
|---:|---:|---:|---|
| 3 | `0x14` | 0 | `SYS_TSENSE` |
| 4 | `0x14` | 1 | `SYS_TSENSE_OFFSET` |
| 6 | `0x14` | 2 | `CONST` |
| 7 | `0x14` | 3 | `MAX` |
| 0 | `0x14` | 4 | `GPU_MAX` |
| 1 | `0x14` | 5 | `GPU_AVG` |

raw class `0x14` 是 GPU device family 的判断由两条独立关系支持：channel 0
明确是 type 1 `GPU_MAX` 并引用 device 0；channel 1 是 type 0 `GPU_AVG` 并
引用 device 1；其 provider 字节又恰为 MODS 表的 4/5。字节关系是
**VERIFIED**；`0x14` 的 NVIDIA 私有符号名没有公开，故符号命名本身为
**INFERRED**。

六个 GPU device provider 的集合精确为 `{0,1,2,3,4,5}`；没有 provider 6
或 7。MODS 570 的名字表则已证明 provider 6 是 `GPU_OFFSET_MAX`、provider 7
是 `GPU_OFFSET_AVG`。因此这张卡在 610.43.03 的这个 runtime graph 中没有实例化
`GPU_OFFSET_MAX`：**VERIFIED negative**（provider 名的映射来自已验证的 MODS
表）。

完整的普通 channel 引用能消除歧义：

| channel | class/type | `853a +0x34` device index | device/provider | `853b +0x04` |
|---:|---|---:|---|---:|
| 0 | `2/0x01` (`GPU_MAX`) | 0 | GPU / 4 | 255.0000 °C invalid |
| 1 | `2/0x00` (`GPU_AVG`) | 1 | GPU / 5 | 34.5546875 °C |
| 2 | `4/0x03` (`MEMORY`) | aggregation | memory path | 46.0000 °C |
| 3 | `2/0x10` | 3 | GPU / 0 | 255.0000 °C invalid |
| 4 | `2/0x13` | 2 | non-GPU raw class `0x15` / 2 | 255.0000 °C invalid |
| 5 | `2/0x14` | 4 | GPU / 1 | 255.0000 °C invalid |
| 6 | `2/0x3d` | 7 | GPU / 3 | 255.0000 °C invalid |
| 7 | `2/0x3e` | 5 | non-GPU raw class `0x15` / 3 | 255.0000 °C invalid |
| 8 | `2/0x3f` | **6** | GPU / **2** | 255.0000 °C invalid |

尤其是 channel 8 record `+0x34 == 6`：这是 **device index 6**；查 `8536`
后该 device 的 provider 是 **2**。把这个字节直接报成 provider 6 会得到一个
看似命中 `GPU_OFFSET_MAX`、实际错误的结论。

## 5. `0x2080853b` 没有藏着第三个有效温度

R610 channel-status record 位于 `0x28 + 0x38*i`：

```text
record +0x00 u8   status class/type
       +0x04 s32  current NvTemp; Celsius = signed_value / 256
       +0x0c u32  debug provider mask（class 3）
       +0x10..34  10 个 debug provider NvTemp（class 3）
```

对 24 个有效 channel 和每个 class-3 子温度槽做完整扫描：

- channel 1：`0x0000228e / 256 = 34.5546875 °C`，是 edge/GPU_AVG；
- channel 2：`0x00002e00 / 256 = 46.0000 °C`，是 memory；
- 其余 22 个 channel 的 current 全为 `0x0000ff00 = 255.0000 °C` invalid
  sentinel；
- channel 9..23 的 15×10 个 debug-provider 槽也全部为 `0x0000ff00`；
- 除 class tag、上述两个温度和 invalid sentinel 外，status 中没有其他非零
  payload。

较早的独立样本
`nvos54_therm_854269_001_cmd_2080853b_size_37f0_status_00000000.bin`
与本样本只有 **一个字节**不同：绝对 offset `0x64`（channel 1 current 的低
字节）从 `0xd9` 变为 `0x8e`，即 edge 从
`0x22d9/256 = 34.84765625 °C` 变为 `34.5546875 °C`；memory 仍为 46 °C。
这进一步验证 channel 1 是活动 edge 信号，而其余 255 °C 项是静态 invalid。

结论：`853b` 原始 RM 返回中没有 50--80 °C 一类的隐藏 hotspot，也没有任何
非 255 °C 的 provider 子温度。**VERIFIED negative**。

## 6. `8536/8549` 的额外信息

`8536` 的 23 个有效 device record class 分布是：

```text
0x14: indices 0,1,3,4,6,7
0x15: indices 2,5
0x1a: index 8
0x16: indices 9..21
0x17: index 22
```

每条有效 `8536` record 的 `+0x0c` 都是 `0x5a00`（若按 NvTemp 解释为
90 °C），但这是 GET_INFO 内的恒定配置字段；没有随两个时间点变化的证据，且
wrapper 的相应 device serializer 不把它当 current sample。它的精确私有名称为
**UNKNOWN**，不能当作 hotspot。

`8549` 的精确布局是 header `0x28` + 255×`0x0c`。有效 record 的 `+0x00`
复现相应 `8536` raw class，`+0x04/+0x08` 对全部 23 个 device 都为零；mask 外
记录也全零。因此这个 read-only device-status GET 在本卡上没有返回 current
temperature payload，更没有 GPC/hotspot 样本：**VERIFIED negative**。

## 7. 最终判断

| 问题 | 结论 | 状态 |
|---|---|---|
| R610 的 private thermal ABI 是否仍是 32 slots？ | 否，四个 control 都是精确的 255-slot E255 布局 | VERIFIED |
| `853a` 是否有 class-1 DEVICE record？ | 0 条 | VERIFIED |
| 是否存在 GPU provider 6 (`GPU_OFFSET_MAX`) device？ | GPU provider 集合只有 0..5 | VERIFIED negative |
| `853b` 是否有 edge/memory 之外的有效温度？ | 没有；其余 current 和全部 debug 子温度均为 255 °C invalid | VERIFIED negative |
| `8549` 是否补回 device/GPC 当前温度？ | 没有，所有 status payload 为零 | VERIFIED negative |
| private RM 能否与 `0xad0aa0/0xad0ae0` 做同帧 hotspot 对照？ | 在 610.43.03 这套 graph 上不能；provider 6 已未实例化 | VERIFIED negative |

这批原始返回使一个关键点从推测变成了否定结果：610 wrapper 并非仅在 NvAPI
对外层“过滤掉”一个仍有值的 provider 6；完整 RM E255 graph 本身就没有该
GPU provider。现有可用路径仍是项目已经验证过结构不变量的只读 BAR0 reader；
private `853a/853b/8549` 不能提供第二份同帧 hotspot 值。
