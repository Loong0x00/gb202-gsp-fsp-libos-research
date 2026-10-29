# GB202 `disable_sw_override` 来源、读取者与生命周期静态审计

日期：2026-07-21  
状态：完成；严格静态、只读、有限窗口

## 范围与证据口径

本报告只描述本地 MODS 570.151、610.43.03 OpenRM 源码以及两份已归档 610
GSP-RM inner ELF 中名为 `disable_sw_override` 的配置位。没有运行 MODS、GSP
或其他 NVIDIA 诊断程序，没有访问 GPU、设备节点、BAR/MMIO、PCI config、
debugfs 或实时驱动状态，也没有执行 reset、模块、固件、电源或 VBIOS 操作。

主要 artifact：

- `mods_audit/static/extracted_inner/mods`，SHA-256
  `c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf`；
- `/tmp/gsp_inner_19f040_a.elf`（610.43.03），SHA-256
  `bda917c95547644398eaf77fefe6c7f1b701c962db91f88bffaed6448a218a47`；
- `/tmp/gsp_inner_61074.elf`（610.74），SHA-256
  `bff2477fea7c8c8fde194006009f060f8eb1761fe2a1951235530dd57950b2a8`；
- `/usr/src/nvidia-610.43.03/src`。

本文使用：

- **FACT**：被文件、明确地址的小窗口或公开源码直接支持；
- **INFERENCE**：由 FACT 支持的最窄语义解释；
- **UNKNOWN**：当前静态材料不能决定。有限负搜索不被写成“绝不存在”。

## 直接结论

1. **FACT：** MODS 的 GB202 RegHal 表把该位定位为
   `BAR0 0x8212ac.bit0`，其读访问 metadata 指向独立 PLM
   `0x8200fc`。这不是 L2 raw OPT 的 `0x8200dc`，也不是 override latch 的
   `0x8200f8`。
2. **FACT：** MODS 至少有两个实际读取用途：
   `GB20xFuseAccessor::IsSwFusingAllowed` 的许可 predicate，以及物理 fuse-binary
   编程前对 FMMC mirror 状态的检查。两个调用都只是 constant compare，不写该
   位。
3. **FACT：** 已审计的 direct-shadow 主机 writer
   `ProgramSwFusePlan 0x1515ea0..0x15160df` 不调用
   `IsSwFusingAllowed`，也没有直接读取 `0x8212ac` 的可见前置检查。
   **UNKNOWN：** 该位是否仍会在更低的 PRI/FSP/硬件层阻止 latch/raw shadow
   写入。
4. **FACT（直接立即数范围）：** 在 MODS `.text` 中，相关常量的两个真实代码
   用途分别是 `0x407c4001` at `0x1516c71` 和 `0x407c4000` at
   `0x15170b6`；二者都传给 compare slot `+0x98`。没有发现直接立即数形式的
   `0x207c4000/0x207c8000` field-write 调用或原始地址 `0x8212ac` 写入。
   这不排除计算得到的 ID、表驱动代码或不可见 firmware。
5. **FACT：** 610.43.03 的公开 RM 没有可供普通 client 查询此原始位的 fuse
   control：`ctrl2080fuse.h` 没有方法，`RMCFG_MODULE_FUSE=0`。本轮也没有在
   OpenRM 源码中找到该名称、地址或对应 RegHal ID。
6. **UNKNOWN：** 本卡当前值、该状态寄存器对 hot/boot/fuse/base reset 的逐类
   保持/重采样规则、物理 OTP raw 坐标、以及任何 firmware-internal setter 或
   consumer。

## 1. 位的来源与两种软件表示

### 1.1 RegHal 地址与字段

对 MODS 内嵌 GB202（chip ID `0xff2`）RegHal 表的离线解码得到：

| RegHal 项 | 静态含义 |
|---|---|
| `0x107c4000`、`0x107c8000` | ordinary read，均映射到 `0x8212ac` |
| 两个 read ID 的 `0xfffe` metadata | access PLM `0x8200fc` |
| `0x207c4000`、`0x207c8000` | field descriptor，bit `[0:0]` |
| `0x407c4000/1`、`0x407c8000/1` | constant descriptor，值 0/1 |

这里的 field/constant descriptor 只证明 RegHal 数据模型能够描述这个字段和
常量；它本身不是一次寄存器写。实际操作方向仍由调用的 handler slot 决定。

公开 610.43.03 generated HAL 把 GB202 记为 chip index 65，并将
`gpuGetPrimaryFuseBaseAddr` 绑定到 `gpuGetPrimaryFuseBaseAddr_GH100`；该实现返回
`NV_FUSE0_PRI_BASE`，Blackwell 公开 `hwproject.h` 将其定义为 `0x820000`
（`g_chips2halspec_nvoc.c:129-132`、`g_gpu_nvoc.c:2723-2733`、
`kern_gpu_gh100.c:647-653`、`blackwell/gb100/hwproject.h:31`）。因此
`0x8212ac` 位于当前 primary-fuse aperture 内；公开源码仍没有发布这个 offset 的
字段名或访问函数。

### 1.2 普通 fuse macro 与 FMMC 视图

MODS 同时保留两种读取方式：

- `UseSoftBurn=false` 时，许可 helper 构造小写名称
  `disable_sw_override`，再经普通 fuse-name/descriptor 路径取值；同一字符串簇
  紧邻 `Reading from HW fuse macro`。
- `UseSoftBurn=true` 时，它不查名字，而是用 RegHal constant
  `0x407c4001` 比较当前 FMMC/PRI 可见字段。

**INFERENCE（强）：** MODS 把“普通硬件 fuse macro 中的
`DISABLE_SW_OVERRIDE`”与“FMMC 可见的 `0x8212ac.bit0`”视为同一语义状态的两种
数据源。

**UNKNOWN：** 外部 `gb202_f.json` 不在本地 MODS 包中，因此普通 macro 描述器
本应提供的 raw row/bit/offset 坐标没有恢复。现有证据不能判断本卡是否物理烧写
该位、它是否能被某种 shadow 覆盖，或它是否也受 VBIOS 配置影响。不能仅凭名字
把其存储介质写成已经证明的 OTP。

## 2. 已确认的读取者

### 2.1 `IsSwFusingAllowed`

MODS 的可见分发链为：

```text
NewFuse IsSwFusingAllowed callback
  -> NewFuse vtable +0xc0       0x1456860
  -> MultiMacro aggregator      0x146dcb0
  -> GB20x accessor +0x80       0x1516c50
```

`0x1516c50..0x1516d4b` 的实际短路逻辑是：

```text
if UseSoftBurn:
    if (0x8212ac.bit0 == 1):
        return UseFakeFuses
    return true
else:
    status, value = GetFuseValueByName("disable_sw_override")
    return (status == 0 && value == 0)
```

关键指令是 `0x1516c71: mov esi,0x407c4001`，随后调用 handler vtable
`+0x98`；这是字段 constant compare。名称分支在
`0x1516cbb..0x1516d3d` 构造名称并调用普通 fuse getter，最后把 getter status 与
输出值合并，只有二者都为 0 才返回真。

因此：

- **FACT：** 对真实 soft-burn 许可 predicate，bit=1 表示禁止；bit=0 只表示
  通过这一个 predicate。
- **FACT：** `UseFakeFuses=true` 可以改变 predicate 的返回值，但这是 MODS
  进程内测试数据策略，不会把硬件位清零。
- **FACT：** 该 callback 返回的是派生布尔值，不是原始 fuse bit；它受到
  `UseSoftBurn`、`UseFakeFuses` 和名称读取成功与否共同影响。

### 2.2 物理 fuse-binary 编程前检查

第二个直接读点位于 `0x1517050..0x151718d`。该函数先要求 host security level
大于 3，然后检查 FMMC 状态；后续日志和 fuse-binary 大小/row 流程把它限定在
物理硬件 fusing 路径，而不是 direct-shadow writer。

相关短路为：

1. 若 `FMMC_SOFT_BURN_ENABLE==1` 且未使用 fake fuses，则报
   `FMMC_SOFT_BURN_ENABLE is set, please clear it using -base_reset before HW fusing`；
2. 若 `FMMC_MIRROR_ENABLE==1`，则在 `0x15170b6` 用
   `0x407c4000` 比较 `disable_sw_override==0`；该条件成立且未使用 fake fuses
   时，报对应 `FMMC_MIRROR_ENABLE ... -base_reset` 错误。

这是该位的第二个真实读取用途。它用于解释 mirror 是否仍能影响硬件 fusing
前置状态，不是该位的 setter。

### 2.3 支持名称与 client-side 诊断 API

MODS ELF 含大写普通 fuse 名 `DISABLE_SW_OVERRIDE`、小写 RegHal 名
`disable_sw_override`、JS 名 `IsSwFusingAllowed` 和 `GetFuseValues`。解码脚本也
有 `device.Fuse.GetFuseValues(names, out)` 的调用实例。

- **FACT：** MODS JSI 内有派生查询 `IsSwFusingAllowed` 和通用按名称读取接口
  `GetFuseValues`。
- **FACT：** 它们属于私有诊断程序，不是 610 production RM 的公开 client
  control。
- **UNKNOWN／当前包不可闭合：** GB202 的 authentic `gb202_f.json` 缺失，因而
  不能把 `GetFuseValues(["DISABLE_SW_OVERRIDE"], ...)` 写成当前本地包可独立完成
  的可靠 GB202 原始位查询。详见 `parallel/gb202_fuse_descriptor_inventory.md`。

## 3. 设置者与 direct-shadow 边界

### 3.1 RegHal descriptor 不等于已找到 setter

对 MODS `.text` 做 exact little-endian immediate inventory，再逐点用小窗口排除
跨指令假命中后：

- `0x407c4001` 只有一个真实代码立即数，位于 `0x1516c71`；
- `0x407c4000` 只有一个真实代码立即数，位于 `0x15170b6`；
- 二者都调用 compare slot `+0x98`；
- `0x107c8000`、`0x207c8000` 的若干 raw byte 命中均是相邻 x86 指令字节拼接，
  不是 RegHal 操作数；
- 没有直接立即数形式的 `0x207c4000/0x207c8000` write 调用，也没有 raw
  `0x8212ac` 指令立即数。

这是“已检查编码形式中的 direct setter 未见”，不是 whole-program absence
proof。通用 handler 可以接收计算所得 ID，RegHal 表也可以被表驱动消费；FSP、
硬件和缺失的外部 fuse 描述器不在此负枚举内。

### 3.2 已知 direct-shadow writer 不走许可 helper

`ProgramSwFusePlan 0x1515ea0..0x15160df` 的可见前置条件是 MODS 进程内
security level `>3`。之后它尝试设置独立 latch `0x820040.bit0`，再写/回读 raw
plan。该函数体：

- 不调用 `0x1516c50`；
- 不使用 `0x407c4000/1` 或 `0x8212ac`；
- 不调用 accessor 的 `IsSwFusingAllowed` vtable 链。

所以应严格分层：

- **FACT：** `disable_sw_override` 是公开/诊断 soft-burn predicate 的直接 gate；
- **FACT：** 它不是已审计 direct-shadow host body 中的显式 gate；
- **UNKNOWN：** PRI firewall、FSP 或硅级 fuse logic 是否在 handler 以下仍用该位
  拒绝 `0x820040` latch 或 raw-shadow write。没有下层 consumer 证据，不能回答
  “它对 direct-shadow 完全无效”，也不能回答“它必然阻断”。

### 3.3 普通 fuse programming 的边界

普通 name path 把 `DISABLE_SW_OVERRIDE` 当作真实 fuse 名，物理 fusing 路径也能
接收完整 fuse binary；这只证明制造/诊断软件体系认识该状态。由于 authentic
GB202 fuse descriptor、raw field 坐标和设备端策略均缺失，本报告没有发现并且
不构造该位的写入方案。

`UseSoftBurn`、`UseFakeFuses` 的 setter 只修改 MODS 进程内布尔量；它们不是
`0x8212ac.bit0` 的硬件 setter。

## 4. 初始化与 reset 生命周期

### 4.1 当前 host 可见事实

- `IsSwFusingAllowed` 每次从所选数据源读取；没有看到 MODS 在对象构造时把
  `disable_sw_override` 初始化为某个常量。
- 已审计的 direct-shadow 成功尾和失败清理都不读、不写、不保存或恢复
  `0x8212ac.bit0`。
- `GB20xPrepareResense` 操作的是另一只 latch `0x820040.bit0`
  （clear-coded `0x404f0000`）并随后条件 reset；它没有引用
  `0x407c4000/1` 或 `0x8212ac`。
- 物理-fusing precheck 的两条日志明确把清除
  `FMMC_SOFT_BURN_ENABLE/FMMC_MIRROR_ENABLE` 与 `-base_reset` 联系起来；这给出
  MODS 对 FMMC enable/mirror 状态的 reset 预期，不是
  `disable_sw_override` 本身会被 base reset 清除的证据。

### 4.2 可以与不能推出的生命周期

**INFERENCE：** 在 `UseSoftBurn=false` 的普通 macro 读取语境中，该值被当作
硬件 fuse-derived policy；若它来自已烧写物理 fuse，reset 后重新 sense 时应回到
同一物理值。但“若”不能省略，因为 raw OTP 坐标和本卡烧写状态均未取得。

**UNKNOWN：** 当前材料没有 GB202 reset-domain 表，因而不能决定：

1. `0x8212ac` 的 FMMC/status view 在 hot、boot、fuse、base reset 中分别是
   retain、clear、reload 还是重新 rollup；
2. software-shadow latch 激活时，该位自身能否被 shadow；
3. FSP/GFW 在 boot 或 reset 时是否缓存、重算或另行强制该 policy；
4. 是否存在 firmware-internal restore、one-shot 或 self-clear 语义。

最安全的结论只是：**现有 host 代码没有给这个位实现 runtime toggle 或 reset
restore；物理 fuse 值、FMMC view 和下层 policy 的生命周期仍须分开看。**

## 5. 610 GSP/OpenRM 的可见边界

### 5.1 OpenRM

对 `/usr/src/nvidia-610.43.03` 的精确源码检索没有找到：

```text
disable_sw_override
DISABLE_SW_OVERRIDE
0x8212ac
0x107c4000 / 0x207c4000 / 0x407c4000
```

公开 control 层虽然保留 `NV2080_CTRL_FUSE`/legacy group 编号，但
`ctrl2080fuse.h` 只有生成文件壳，没有任何 method；
`generated/rmconfig.h:729` 明确为 `RMCFG_MODULE_FUSE 0`。因此：

- **FACT：** 当前公开 610 source 没有导出这个 raw bit 的 GET control；
- **FACT（已检查定义范围）：** 当前 610 OpenRM controls 没有能向普通 client
  返回该位的字段；本报告没有建立 NVML/`nvidia-smi` 到该位的查询路径；
- **UNKNOWN：** 闭源 RM/FSP 内部是否另有私有读取者或 policy consumer。

2026-07-21 对 NVIDIA GitHub 公开索引做的精确名称检索也没有结果；这只能作为
当时索引的负结果，不能证明 NVIDIA 私有源码或其他版本不存在该机制。

### 5.2 GSP-RM ELF：有限编码负结果

610.43.03 和 610.74 两份 inner ELF 均无该英文名称、完整 `u32 0x8212ac` 或
上述 MODS RegHal IDs。对 executable PT_LOAD 的 `LUI 0x821` 精确锚点逐点检查
也没有形成固定 `0x821000 + 0x2ac` 访问。

固件中存在容易误判的动态地址形状：某些共享函数把对象 companion field 加到
`0x821000` 后访问负 offset `-0x3fc`。这个地址只有在 companion 恰为
`0x6a8` 时才等于 `0x8212ac`，而当前没有该字段的正式名称和值证明。因此不能把
这些函数直接命名为 `disable_sw_override` reader。

其中一个候选函数在 610.43.03 为 `0x018494c0`，610.74 为
`0x01849f60`。610.43.03 构造器在 `0x019e186c..0x019e187c` 取得完整 chip
index 并进入 group 2，在 `0x019e2b4a..0x019e2b58` 对 low index 使用 selector
mask `0x03f8fc00`；GB202 index 65 的 low index 是 1，而 bit 1 为 0。随后
`0x019e2e94..0x019e2e9c` 给相应 `+0x3c8` slot 安装
`0x019d0fbc`，其函数体只返回 `0x56`。610.74 在
`0x019e36a6..0x019e36b4`、`0x019e39f0..0x019e39f8` 和
`0x019d1b08` 保持同一选择结果。当前 610 status 头将 `0x56` 定义为
`NV_ERR_NOT_SUPPORTED`（`src/common/sdk/nvidia/inc/nvstatuscodes.h:115`）。因此
GB202 没有在这个 slot 绑定上述候选函数。

这项交叉检查只排除了一个诱人的 shared-HAL 误绑定。它不能排除表驱动 PRI、
跨函数动态地址、FSP 内部 consumer、packed descriptor 或另一份未取得 firmware。

## 6. Client-visible 只读接口判定

| 接口 | 能否读原始 bit | 证据等级 |
|---|---|---|
| MODS `IsSwFusingAllowed` | 否；只返回受 fake/soft-burn/read-status 影响的派生布尔值 | FACT |
| MODS `GetFuseValues` | 设计上可按名称读普通 fuse；本地 GB202 descriptor 缺失，不能闭合为可靠现成探针 | FACT / UNKNOWN |
| OpenRM `NV2080_CTRL_FUSE` | 当前 610 头为空、模块关闭，无此 GET method | FACT |
| NVML / `nvidia-smi` | 已检查的 610 OpenRM controls 没有该字段；未建立查询路径 | FACT（已检查接口范围） |
| 裸 BAR/MMIO | 地址已知但不是公开 client-safe 接口；本报告未访问 | FACT |
| 私有 GSP/FSP/闭源 RM | 是否存在 bit-specific query 未知 | UNKNOWN |

因此目前没有一个同时满足“production 610、公开、client-visible、只读、直接返回
`0x8212ac.bit0`”的接口。诊断程序的派生 predicate 不能冒充原始位读数。

## 7. 最小可引用结论

> MODS 570.151 的 GB202 RegHal 数据把 `disable_sw_override` 定位到
> `0x8212ac.bit0`，读访问 metadata 指向 `0x8200fc`。该位被
> `IsSwFusingAllowed` 和物理 fuse-binary 编程前的 FMMC mirror 检查读取；目前
> 看到的两个 RegHal constant 用途都只是 compare。已审计的 direct-shadow
> `ProgramSwFusePlan` 主机函数不调用这条许可 helper，所以该位对 direct-shadow
> 的更低层影响仍为 UNKNOWN。公开 610 OpenRM 没有 fuse GET method，当前本卡值
> 与 reset/firmware 生命周期也均未通过静态材料闭合。
