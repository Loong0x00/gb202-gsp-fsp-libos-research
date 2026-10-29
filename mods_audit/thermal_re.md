# MODS 570.151（GB202/RTX 5090）thermal / hotspot 静态逆向记录

日期：2026-07-14  
范围：只对下载包、解包文件、本机 `nvidia-open 610.43.03` 源码，以及主任务提供的 610.43.03 只读 RM GET 截获文件做静态分析；**本分析未执行 `mods`/`mats`，未加载其内核模块，未写 MMIO，也未用此包驱动显卡。**

状态词：

- **VERIFIED**：由二进制反汇编、公开源码或已有逐样本数据直接证明。
- **INFERRED**：多项证据一致，但缺少 MODS 与 BAR0 同帧读数或 NVIDIA 的 GB202 hwref 定义。
- **UNKNOWN**：当前材料不能证明。

## 1. 样本与结论摘要

| 项目 | 结果 | 状态 |
|---|---|---|
| 外层 ZIP | `570.151_GB202_5090.zip`, 943,721,235 bytes, SHA-256 `d141f685ea70c9a49095b7369201ab0651222bea3c063acfd6616dfde058ded9`, MD5 `3ae2748b5cea1a73ce1f7f7056477ab1` | VERIFIED |
| `mods` | 392,339,552-byte stripped ELF64 ET_EXEC, SHA-256 `c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf` | VERIFIED |
| thermal 脚本 | 有 `systhermsanity.jse`、`thermcal.jse`、`thermresgpu.jse`、`gputest.jse`；没有名为 `thermal.jse` 或 `thermregpu.jse` 的文件 | VERIFIED |
| `.jse` 可读性 | 本包内这些文件是二进制/封装后的 JSE，不是可直接审阅的 JavaScript 源码 | VERIFIED |
| MODS 取内部温度的主要路径 | `IntTempMonitor` -> MODS thermal abstraction -> 私有 physical RM controls `0x20808536/3a/3b` -> 后端/GSP；不是在 host `mods` ELF 中硬编码 `0xad0aa0/0xad0ae0` | VERIFIED |
| hotspot 名称 | thermal device class `GPU` 的 provider index 6 确切映射为 `GPU_OFFSET_MAX` | VERIFIED |
| 当前温度格式 | `0x2080853b` 返回的 `NvTemp` 是 signed Q24.8，`C = int32 / 256.0` | VERIFIED |
| 与独立 BAR reader 的关系 | `GPU_OFFSET_MAX` 在语义上与 `max(BAR0+0xad0aa0, BAR0+0xad0ae0)` 高度一致；但包里没有这些地址，且没有 MODS/BAR 同帧对照 | INFERRED |
| 610.43.03 实机 private RM | ABI 已扩为 E255；GB202 的 GPU thermal devices 只实例化 provider 0..5，**没有 provider 6/7**；status 只给 edge 与 memory，其余为 255 °C invalid sentinel | VERIFIED negative |
| 107 °C 阈值 | MODS 可经 `0x20808540` 取 thermal HW fail-safe event limit；`mods` host ELF 未发现可信的静态 107 °C literal/寄存器地址 | VERIFIED（API 路径）/ UNKNOWN（其返回值是否正好 107 °C，未运行） |

核心判断：MODS 没有给出新的 GB202 BAR0 offset 证明。570.151 的通用 thermal 模型确实支持名为 **`GPU_OFFSET_MAX`** 的 GPU provider 6，`IntTempMonitor` 也通过 private RM/GSP channel status 读取所选内部传感器；但这不等于 GB202 的运行时配置一定实例化 provider 6。新取得的 610.43.03 实机原始返回反而直接证明：该驱动在这张 GB202 上只构造 GPU provider 0..5，provider 6/7 已从这个 channel/device graph 中删掉。因此 610 的 `0x20808536/3a/3b` 不能用来取得 hotspot，现有直接 BAR0 reader 仍是成功路径。

## 2. 二进制地址约定

`mods` 的主可执行 LOAD 映射满足 `VA = file_offset + 0x400000`；`.text` 从 VA `0x4a0940` / file `0x0a0940` 开始，`.rodata` 从 VA `0x8bd74a0` / file `0x87d74a0` 开始。下文同时列 VA 和 file offset，便于复核。

## 3. provider 名字与 `GPU_OFFSET_MAX` 的精确映射

### 3.1 字符串

| 名称 | file offset | VA |
|---|---:|---:|
| `GPU_AVG` | `0x8cf00ef` | `0x90f00ef` |
| `GPU_OFFSET_MAX` | `0x8cf00f7` | `0x90f00f7` |
| `GPC_OFFSET_MAX` | `0x8cf0492` | `0x90f0492` |
| `GPC_AVG` | `0x8cf04bf` | `0x90f04bf` |
| `MEM_MAX` | `0x8cf047f` | `0x90f047f` |

同一名字集合还包含 `SYS_TSENSE`、`SYS_TSENSE_OFFSET`、`CONST`、`MAX`、`GPU_MAX`、`GPU_OFFSET_AVG`、`DYNAMIC_HOTSPOT`、`DYNAMIC_HOTSPOT_OFFSET` 以及 secure/die 变体。

### 3.2 device/provider 映射函数

VA `0x16a0680` / file `0x12a0680` 接受 `(deviceClass, providerIdx)` 并经跳表返回名字。device class 跳表在 VA `0x92fdbc8`；class 1 分支为 VA `0x16a06a0`，其 provider 表在 VA `0x92fe280`：

| provider index | class 1 名称 |
|---:|---|
| 0 | `SYS_TSENSE` |
| 1 | `SYS_TSENSE_OFFSET` |
| 2 | `CONST` |
| 3 | `MAX` |
| 4 | `GPU_MAX` |
| 5 | `GPU_AVG` |
| **6** | **`GPU_OFFSET_MAX`** |
| 7 | `GPU_OFFSET_AVG` |
| 8 | `DYNAMIC_HOTSPOT` |
| 9 | `DYNAMIC_HOTSPOT_OFFSET` |

thermal device class-name 表在 VA `0x92ff180`；class 1 指向 VA `0x90c5e28` 的 `GPU`。因此 **device class 1 + provider 6 = `GPU_OFFSET_MAX`** 是 VERIFIED，不是按字符串顺序猜测。

另外，JSE 导出常量的原生注册代码在 VA `0x85706c` / file `0x45706c` 附近：`SAMPLE_TSENSE_MAX = 1.0`；VA `0x8570ad` / file `0x4570ad` 附近：`SAMPLE_TSENSE_OFFSET_MAX = 2.0`。这证明 sample enum 2 的含义，但 `-bg_int_temp` 的清晰参数解析字符串没有出现在原生 ELF 中，推测在不透明的 `gputest.jse` 内；确切 CLI 绑定仍为 UNKNOWN。

## 4. 私有 RM control 描述符

control descriptor table 位于 VA `0x9d4f450` / file `0x994f450` 附近：

| control | 参数大小 | MODS 内部名字/用途 | handler VA |
|---:|---:|---|---:|
| `0x20808536` | `0x714` | `subdeviceCtrlCmdThermalDeviceGetInfo` | `0x6fb3740` |
| `0x20808539` | — | `ThermalChannelPmumonGetSamples` | — |
| `0x2080853a` | `0x5b0` | `ThermalChannelGetInfo` | `0x6ad60e0` |
| `0x2080853b` | `0x728` | `ThermalChannelGetStatus` | `0x6ad6130` |
| `0x2080853c` | `0x1a8` | `ThermalChannelGetControl` | — |
| `0x2080853e` | — | `FanTestGetInfo` | — |
| `0x20808540` | `0x18` | `ThermalHwFsEventSettingsGet` | `0x726c9f0` |
| `0x20808542` | — | `ThermalHwFsEventStatusGet` | — |

注意：`0x20808540` 是 event settings GET，不是当前温度 GET。此前若把它当 device temperature control 会读错结构。

## 5. `0x20808536`：thermal device info ABI

**570.151 ABI，VERIFIED：**

```text
total size                   0x714
+0x000 u8                    BOARDOBJGRP classType
+0x001..+0x003               padding
+0x004 u32                   objMask (E32)
+0x008..+0x013               group header remainder
+0x014 + i*0x38              device entry i, i=0..31
  entry +0x00 u8             device class; 1 = GPU
  entry remainder            本次未完全命名
```

构造/枚举函数 VA `0x16ac7a0` / file `0x12ac7a0` 清零 `0x714` 参数并调用 control；它以 `base + 0x14 + i*0x38` 访问 entry。打印路径 VA `0x169d000` 读取 entry byte 0 并查 class-name 表，交叉证明 byte 0 是 device class。

## 6. `0x2080853a`：thermal channel info ABI

调用函数 VA `0x16a64f0` / file `0x12a64f0`：清零完整 `0x5b0`，直接调用 `0x2080853a`，读取返回 mask，并以 `base+0x30`、stride `0x2c` 遍历 32 个 channel。

```text
total size                   0x5b0
+0x000 u8                    BOARDOBJGRP classType（不是 API version）
+0x001..+0x003               padding
+0x004 u32                   objMask (E32)
+0x008..+0x02f               group header remainder
+0x030 + i*0x2c              channel entry i, i=0..31
  +0x00 u8                   channel class/type
  +0x01 u8                   channel type/subtype
  +0x02 u8                   relative location
  +0x03 u8                   target GPU
  +0x08 s32 NvTemp           minimum
  +0x0c s32 NvTemp           maximum
  +0x14 s32                  scaling
  +0x18 s32 NvTemp           software offset
  +0x1c s32 NvTemp           hardware offset
  +0x20 u8                   simulation flag 0
  +0x21 u8                   simulation flag 1
  +0x22 u8                   flags
```

class jump table VA `0x92fdfd8` 给出扩展 union：

| class | 意义 | 观察到的附加字段 |
|---:|---|---|
| 0 | invalid | — |
| 1 | `DEVICE` | `+0x24 deviceIdx`, `+0x25 providerIdx` |
| 2 | `PROVIDER_V10` | `+0x25 deviceIdx`, `+0x26 providerIdx` |
| 3 | `DEBUG_V10` | `+0x25 deviceIdx`, `+0x26 providerStart`, `+0x27 providerEnd`, `+0x28 listSize` |
| 4 | `AGGREGATION` | `+0x25 deviceIdx`, `+0x26 start`, `+0x27 end`, `+0x28 nextChannel`, `+0x29 mode` |
| 5 | `ESTIMATION` | `+0x25 channel1`, `+0x26 channel2`, `+0x27 mode` |

VA `0x16ac7a0` 的模型构建路径接受 class 2–5；class 1 在更早的专门路径处理。因此扫描 `GPU_OFFSET_MAX` 时不能只接受 class 1：应同时解析 class 1 和 class 2 的不同 byte offset。

`+0` 是 BOARDOBJ/BOARDOBJGRP 的 `classType`，不是版本号。这与 610 开源头文件 `ctrl2080boardobj.h` 中 `NV2080_CTRL_BOARDOBJ_BOARDOBJGRP_CLIENT_INFO_E32` 的开头布局相符。MODS 调用方没有给 853a 写入任何显式 API version。

## 7. `0x2080853b`：thermal channel current status ABI

主调用路径 VA `0x169dc10` / file `0x129dc10`：

- 清零 `0x728` 参数；
- 在 `+0x04` 写 requested channel mask；
- 调用 `0x2080853b`；
- entries 从 `+0x28` 开始，32 个，stride `0x38`；
- 普通记录从 entry `+0x04` 取 signed 32-bit temperature；
- 乘 VA `0x92ff448` 的 double `0.00390625`，即除以 256。

```text
total size                   0x728
+0x000 u8                    BOARDOBJGRP classType
+0x001..+0x003               padding
+0x004 u32                   requested/returned objMask (E32)
+0x008..+0x027               group header remainder
+0x028 + i*0x38              status entry i, i=0..31
  +0x00 u8                   status entry type/class
  +0x04 s32 NvTemp           current temperature, C = value / 256.0
  +0x0c u32                  providerMask（type 3/debug 记录）
  +0x10 + j*4 s32 NvTemp     provider temperatures（type 3）
```

第二条独立调用路径 VA `0x16ab570` / file `0x12ab570` 重复同一公式：temperature 地址为 `base + 0x2c + 56*i`，再除以 256。服务端辅助路径 VA `0x6ad5ae0`/`0x6ad5bb0`（file `0x66d5ae0`/`0x66d5bb0`）同样分配/清零 `0x728`，写一个 channel bit，并从 `params+0x2c+56*i` 取值。这三重交叉引用使布局和换算式均为 VERIFIED。

最小只读布局可表达为（仅用于说明 570.151 的字节 ABI）：

```c
struct ch_status_570 {
    uint8_t  group_class;
    uint8_t  pad0[3];
    uint32_t mask;
    uint8_t  group_rest[0x20];
    struct {
        uint8_t type;
        uint8_t pad0[3];
        int32_t temp_q8;
        uint8_t rest[0x30];
    } entry[32];
}; /* sizeof == 0x728 */
```

## 8. MODS 的实际 monitor 调用链

原生 factory 注册 `IntTemp` monitor 的对象在 VA `0x1877f860` 附近；构造函数 VA `0x17e3440` / file `0x13e3440`，vtable VA `0x93090d0`。关键方法：

| 方法 | VA | file offset | 作用 |
|---|---:|---:|---|
| init | `0x17e3900` | `0x13e3900` | 检查 thermal support |
| gather/config | `0x17e3dc0` | `0x13e3dc0` | 调 thermal abstraction，构造/选择内部传感器列表 |
| aggregate/sample | `0x17e4610` | `0x13e4610` | 更新样本状态 |
| print | `0x17e4860` | `0x13e4860` | 打印 current/max |

相关字符串：

- file `0x8889850`, VA `0x8c89850`: `Invalid Params passed to IntTemp bglogger`
- file `0x8889880`, VA `0x8c89880`: `GPU temperature by internal sensor [%s]`
- file `0x88898b0`, VA `0x8c898b0`: `Current temp : %.3f` / `Maximum temp : %.3f`
- file `0x88899c0`, VA `0x8c899c0`: `CONSTANT: SAMPLE_TSENSE_OFFSET_MAX`

`gather/config` 调用 VA `0x16b0c50`、`0x16b0d60`、`0x16b1580` 的 thermal wrappers，并未直接读 MMIO。`IntTempMonitor` 的 selector `-1` 表示枚举，否则选择一个 sample。由此可确认 MODS 的内部温度监控是 RM thermal object/channel 模型，不是这份 host ELF 内的一段固定 PTHERM register reader。

## 9. 107 °C / thermal event 路径

VA `0x16a1df0` / file `0x12a1df0` 逐 event ID 调 `0x20808540`：调用前清零 24 bytes，在 `+0` 写 event ID，并设置 byte `+8 = 1`；返回后将 `+4` 的 signed NvTemp 除以 256，并读取 `+0x14` provider index，再通过上述 GPU provider 表打印 provider 名。

event 名字表在 VA `0x92fec80`，包括 `EVENT_ID_EXT_OVERT`、`OVERT`、`ALERT_0H...`、`THERMAL_0..11`、`DEDICATED_OVERT`、`SCI_FS_OVERT` 等。handler VA `0x726c9f0` / file `0x6e6c9f0` 含 `EVENT_GET RPC` 错误路径并复制返回记录，说明阈值来自 firmware/GSP/VBIOS 侧数据。

对 `mods` 全文件搜索以下 GB202 已发现值均为零命中：

- `0x00ad0aa0`, `0x00ad0ae0`
- 八个 source words `0xad0a90/a94/a98/a9c/ad0ad0/ad4/ad8/adc`
- `0x00ad0718`
- 它们的 BAR 物理地址形式

对 Q9.5 107 °C word 的精确字节搜索也没有可信命中。零命中不证明 firmware 不读它，只能证明 **host `mods` ELF 没有以这些立即数静态保存它们**。

## 10. 与独立 BAR0 发现的对照

独立 reader 已经证明：

```text
bank A aggregate: BAR0 + 0x00ad0aa0
  == max(0xad0a90, 0xad0a94, 0xad0a98, 0xad0a9c)  [650/650]

bank B aggregate: BAR0 + 0x00ad0ae0
  == max(0xad0ad0, 0xad0ad4, 0xad0ad8, 0xad0adc)  [650/650]

current Q9.5 decode:
  C = sign_extend((raw >> 3) & 0x3fff, 14) / 32.0

hotspot candidate:
  max(decode(BAR0+0xad0aa0), decode(BAR0+0xad0ae0))

BAR0 + 0x00ad0718:
  static limit = (raw & 0x3fff) / 32.0 = 107 C
```

这里有两种不同的数值层：直接 BAR word 是 bits `[16:3]` 的 signed Q9.5；private RM channel status 已由 firmware/RM 归一化成 signed Q24.8。两者换算精度不同并不矛盾。

对应强度：

- `GPU_OFFSET_MAX` 是 MODS 570.151 thermal 模型中明确存在、可由 IntTemp monitor 的内部传感器选择路径使用的 GPU provider：**VERIFIED（能力）**；本包的不透明 JSE 与 610 实机 graph 均不能证明它在 GB202 上实际被实例化。
- `0xad0aa0/ae0` 是两个真实的硬件 max aggregate 且负载跟随：**VERIFIED**。
- `max(aa0, ae0)` 就是 NVIDIA 内部语义上的 `GPU_OFFSET_MAX`：**INFERRED**。610 graph 没有 provider 6，因而不能再通过 853b 做同帧对照；要提升为 VERIFIED 需另一条仍暴露 provider 6 的固件/MODS 环境。
- MODS 与独立发现“完全相同地直接读取这两个 offset”：**否；静态证据不支持。** MODS host 路径走 private RM/GSP；底层 GSP/firmware 最终是否读取这些寄存器仍为 UNKNOWN。

## 11. 610.43.03 实机 private RM 返回：ABI 已变，且 provider 6 已删除

主任务通过只读 GET 路径截获了 `libnvidia-api.so.1` 在本机真实提交/接收的 control payload。本分析只离线解码这些文件：

| control | 文件 | size | SHA-256（代表样本） |
|---:|---|---:|---|
| `0x20808536` | `hotspot_reader/nvos54_therm_855989_000_cmd_20808536_size_63d0_status_00000000.bin` | `0x63d0` | `961e2ef04431c4a676b307764027efebe536966907fe9f9e3fff9a8ce4d376d7` |
| `0x2080853a` | `hotspot_reader/nvos54_therm_855989_001_cmd_2080853a_size_3bf8_status_00000000.bin` | `0x3bf8` | `91e394619ac91d4285daea7f82b7f5ce78da76e9feeaa820fe33193d3cbfbcfc` |
| `0x2080853b` | `hotspot_reader/nvos54_therm_854269_001_cmd_2080853b_size_37f0_status_00000000.bin` | `0x37f0` | `a199c5ff3cd35a30fd4d0a00be60c6b9423cc3dfe3449cd0d49f32ccfa25853e` |

两次 853a 逐字节相同；每次调用中的两份 853b 逐字节相同。另一次捕获的 853b SHA-256 为 `679d40720899eff3326775d34e35304217c17fe5e24bb80c13f9b58f22012043`，差异只包括动态 edge 温度。

### 11.1 R610 E255 布局

三个结构都返回 `+0 = 2`，这是 E255 BOARDOBJGRP 的 concrete `classType`；mask 是从 `+4` 开始的八个 little-endian `u32`。它不是请求 mode，不能通过把 `+0` 改成 1 来枚举另一组对象。

尺寸给出无歧义的数组起点和 stride：

```text
ThermDeviceGetInfo  0x63d0 = 0x34 + 255 * 0x64
ThermChannelGetInfo 0x3bf8 = 0x34 + 255 * 0x3c
ThermChannelStatus  0x37f0 = 0x28 + 255 * 0x38
```

因此：

```text
0x20808536:
  mask[8]                 +0x04
  device[i]               +0x34 + i*0x64
    raw class tag         entry+0x00
    GPU provider id       entry+0x14（当 raw class tag == 0x14）

0x2080853a:
  mask[8]                 +0x04
  channel[i]              +0x34 + i*0x3c
    channel class         entry+0x00
    channel type          entry+0x01
    class-2 deviceIdx     entry+0x34
    class-2 providerIdx   entry+0x35

0x2080853b:
  mask[8]                 +0x04
  status[i]               +0x28 + i*0x38
    status class          entry+0x00
    current NvTemp        entry+0x04, signed /256 C
    debug providerMask    entry+0x0c（status class 3）
    debug provider temps  entry+0x10+j*4（status class 3）
```

`libnvidia-api.so.1` 的 channel-info wrapper 位于 VA `0x21d40`，status wrapper 位于 VA `0x23080`。class-2 serializer VA `0x222cd` 明确从 raw entry `+0x34/+0x35` 复制 device/provider 两个 byte；status 路径 VA `0x23347`/`0x233ad` 分别读取 status class 与 `+4` current。这里的 R610 offset 不是仅凭尺寸猜测。

### 11.2 R610 device graph 没有 `GPU_OFFSET_MAX`

8536 返回 device mask `0x007fffff`（0..22）。raw class tag `0x14` 是本卡的 GPU-provider device class：其 provider 值与 channel 0=`GPU_MAX`、channel 1=`GPU_AVG` 的公开 V2 元数据精确交叉验证。所有该类对象如下：

| device index | raw tag | entry `+0x14` provider | MODS 570 provider 名 |
|---:|---:|---:|---|
| 0 | `0x14` | 4 | `GPU_MAX` |
| 1 | `0x14` | 5 | `GPU_AVG` |
| 3 | `0x14` | 0 | `SYS_TSENSE` |
| 4 | `0x14` | 1 | `SYS_TSENSE_OFFSET` |
| 6 | `0x14` | 2 | `CONST` |
| 7 | `0x14` | 3 | `MAX` |

集合恰为 `{0,1,2,3,4,5}`。**没有任何 raw-tag-0x14 device 的 provider 为 6 (`GPU_OFFSET_MAX`) 或 7 (`GPU_OFFSET_AVG`)。** 这是 R610/本机 GB202 运行时对象图的 VERIFIED negative，不再是“ABI compatibility unknown”。

853a 返回 channel mask `0x00ffffff`（0..23）。class-2 channels 0、1、3..8 的 `(deviceIdx, channel-providerIdx)` 依次为：

```text
ch0 (0,0), ch1 (1,0), ch3 (3,0), ch4 (2,0),
ch5 (4,0), ch6 (7,0), ch7 (5,0), ch8 (6,0)
```

其中 `entry+0x35` 的 channel-providerIdx 全是 0；GPU provider 的真正编号来自所引用 8536 device 的 `entry+0x14`。把 ch8 的 device index 6 误读成 provider 6 会产生一个看似合理但错误的 `GPU_OFFSET_MAX`。

### 11.3 R610 status 只有 edge 与 memory

| channel | info class/type | 解析身份 | 853b current |
|---:|---|---|---:|
| 0 | class 2 / type 1 | `GPU_MAX` | `0xff00 / 256 = 255 C`，invalid sentinel |
| 1 | class 2 / type 0 | `GPU_AVG` | `0x22d9 / 256 = 34.847656 C`；下一次 `0x228e / 256 = 34.554688 C` |
| 2 | class 4 / type 3 | `MEMORY` | `0x2e00 / 256 = 46.0 C` |
| 3..8 | class 2 | 其他 device-backed channels | 全部 255 C invalid |
| 9..23 | class 3 | debug channels | current 全部 255 C；providerMask=0；所有 provider temps 也为 255 C |

channel 1 与同期 edge 约 34.85 C 精确吻合，channel 2 与 memory 46 C 精确吻合。整个返回中没有第三个有限温度，因此没有字段能与同期较高的 BAR0 hotspot candidate 对齐。

### 11.4 对 KMD 路线的最终影响

不应为 610 制作一个仅包装 `0x20808536/3a/3b` 的 sysfs/debugfs patch：即使 control 成功，firmware 返回的对象图也没有 provider 6，节点只会重复 edge/memory 或输出 255 C sentinel。公开的 `0x20800513/0x20808513` Thermal System Execute V2 路径也已在项目的独立探针中只返回 edge，不能补回 junction。

因此 KMD/private-RM 路线在已审计的 610.43.03 数据路径上是 **VERIFIED negative**。成功交付仍应采用已经负载验证的只读 BAR0 aggregate reader；MODS 570 逆向的价值在于确认内部命名和解释为何新驱动路径读不到，而不是替代 BAR0 reader。

## 12. 最终状态矩阵

| 问题 | 答案 | 状态 |
|---|---|---|
| MODS 570.151 是否懂 GB202 的内部 hotspot 类传感器？ | 是，明确含 `GPU_OFFSET_MAX`、dynamic hotspot、GPC/MEM/SYS provider 模型 | VERIFIED |
| MODS 570 模型里 `GPU_OFFSET_MAX` 的 class/provider 是什么？ | device class 1 (`GPU`), provider 6 | VERIFIED |
| 当前值用哪个私有 control？ | `0x2080853b`, status entry `+4`, signed `/256.0 C` | VERIFIED |
| 如何发现对应 channel？ | `0x20808536` device info + `0x2080853a` channel info | VERIFIED（570.151） |
| MODS host 是否直接硬编码 `0xad0aa0/ae0`？ | 未发现；实际 host 调用链为 thermal abstraction -> private RM/GSP | VERIFIED（静态样本） |
| `GPU_OFFSET_MAX == max(aa0,ae0)`？ | 高概率，但没有同帧 private-RM/BAR 比较 | INFERRED |
| 107 °C 在 MODS 哪取？ | `0x20808540` event settings GET 可返回 limit/provider；具体实机返回值未测 | VERIFIED / UNKNOWN |
| 这些 private controls 能否由普通用户态封装调用？ | 本机 `libnvidia-api.so.1` 的真实 GET 均成功，原始 payload 已截获 | VERIFIED |
| 610 是否沿用 570.151 private ABI？ | control IDs/核心 Q24.8 语义沿用，但 group 从 E32 扩为 E255，8536/853a 记录尺寸与字段 offset 已改变 | VERIFIED |
| 610 GB202 的 graph 是否还有 provider 6？ | 没有；GPU class devices 只含 provider 0..5 | VERIFIED negative |
| 610 的 853b 能否读到 hotspot？ | 不能；只有 edge、memory 两个有限温度，其他均 255 C invalid | VERIFIED negative |

最终安全路线只有已经实测的只读 BAR0 reader：`max(decode(0xad0aa0), decode(0xad0ae0))`。610 private RM 抓包已经排除了“只需把 provider 6 从 KMD 导出”的设想；它不是隐藏在 host 结构中，而是没有出现在返回的 runtime object graph。MODS 570 的 provider 命名仍为 BAR0 候选提供了有价值的语义佐证，但两者的精确同一性继续保持 **INFERRED**。
