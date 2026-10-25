# RTX 5090 / Blackwell V/F 运行时控制发现

日期：2026-07-24  
设备：ASUS RTX 5090 Astral，GB202-300-A1  
系统：Linux，NVIDIA 610.43.03 open kernel modules，LACT `r1110.ab83c4c2`

## 结论摘要

1. LACT 并不写任意电压值。它读取驱动给出的固定、不可变电压点，然后只为每个点写入 `freq_offset_khz`；因此界面里的 `电压 -> 频率` 本质是提交给 NVIDIA 性能管理栈的一张频率偏移表。
2. 当前最合理的运行时路径是：

   ```text
   LACT
     -> NVAPI/NVML/RM 控制接口
     -> CPU 侧 Kernel-RM
     -> GSP-RM
     -> PERF / PMU / VOLT / AVFS 控制逻辑
     -> 时钟发生器与板载电压调节器
   ```

3. 现在已经静态确认：LACT 的私有 V/F 设置命令最终进入 GSP-RM 中的 Subdevice/Clock 方法，而不是由 CPU 侧 Kernel-RM 本地实现。真正高频率、实时地根据负载、温度、功耗和曲线形状选择工作点的逻辑，属于 GSP-RM 协调的 PERF/PMU/VOLT/AVFS 控制栈。不能简单说“全是 GSP 主线程算的”，但可以排除 LACT 或桌面端驱动逐帧指定电压。
4. VBIOS 提供基础 V/F 表、SKU/板卡限制、功耗和电压调节器相关参数；它更像规则和初始数据来源，不是运行时每几十毫秒亲自选择电压的执行者。
5. SEC2/FSP 主要处于安全启动、认证和固件装载链上，不是正常游戏负载下的 V/F 调速循环。
6. NVIDIA 没有公开 Blackwell 完整的 PERF/PMU 固件实现，因此目前无法仅凭公开源码把“约 50 mV 曲线窗口”精确定位到 GSP-RM 中的某个函数还是 PMU 中的某个控制器；可以确定它位于 NVIDIA 固件/RM 性能控制栈，而不是 LACT 自己计算出来的。
7. 本地 MODS 样本还提供了一条更直接的证据：其 PERF 对象实现了按电压轨、以及按“电压轨＋时钟域”设置电压偏移的接口，并通过特权 RM 命令 `0x2080d01c` 交给 GSP-RM。这证明“如何应用 V/F 偏移”是可执行的 RM/固件策略，不是 VRM 芯片自己凭空决定。
8. 这不等于整条控制链的代码都能直接阅读。MODS 内置 RM 明确区分“加密调试 PMU 镜像”“加密量产 PMU 镜像”和“未加密 PMU 镜像”三条装载路径；零售卡通常处于量产安全状态，因此最底层 PMU 程序很可能只能看到密文。当前能直接反汇编的是 CPU 侧 RM、GSP-RM 及其 PMU RPC 边界。
9. 现在已有本机运行时直接证据：内部限制 ID `0x43` 是 `PERF_LIMIT_PMU_DOM_GRP_1`，MODS 将读取它的接口命名为 `GetCurrPowerCapLimFreqkHz`，说明文字就是“Get current power capping limited frequency”。在最新 6K 光追基准中，该 PMU 动态目标平均为 **2804.1 MHz**，实际核心平均为 **2772.5 MHz**；与此同时 237 个传统静态 PERF limit 始终没有任何一个 active。因此这次降频可以明确归到 PMU 动态闭环，而不是温度、600 W 板卡上限或某个普通静态限频项。
10. 又进一步定位到产生 `0x43` 的具体策略：策略 0 的类型值为 `0x14`，MODS 的显式类型表将其命名为 **`WORKLOAD_COMBINED_2X`**（`0x13` 才是 `WORKLOAD_DIE_2X`）。该组合策略动态状态里的第一个 domain-group 频率目标（`DG0`）在成对查询中与 `0x43` 读数 12 次有 11 次完全一致，另一次只差一个 15 MHz 档位；在完整 CP2077 基准中，`DG0` 平均 **2799.0 MHz**，也紧贴 `0x43` 的 **2804.1 MHz**。这说明游戏里的约 2.8 GHz 不是 LACT 曲线没有生效，而是 PMU 汇总 die 与 physical/logical-single 工作负载模型后主动生成了约 2.8 GHz 的目标，之后再由时钟仲裁器落到约 2.77 GHz 的实际档位。
11. 两个 domain group 的实际时钟域也已命名。MODS 在调用 `GetCurrPowerCapLimFreqkHz` 后把 `0x43` 明确打印为 `PMU_DOM_GRP_1 gpc2clk limit`，所以 `DG0` 是核心 `GPC2CLK` 目标。610.43.03 自己的 ID 表又将 `0xe9/0xea` 命名为 `THERM_POLICY_XBAR` 与 `PWR_POLICY_XBAR`；成对读取表明 `DG1` 精确取二者较低值，因此 `DG1` 是片上互连 `XBAR` 时钟目标，不是第二个核心频率。

## “到底谁来管”的调用链追踪

### 1. LACT 只改固定电压点上的频率偏移

本机安装的 LACT 是提交 `ab83c4c28189d5fbf55e995029162a453d02f733`。对应源码中：

- `get_vf_curve()` 从驱动读取每个点的 `voltage_uv`、当前频率和基础频率；
- `apply_vf_curve()` 如果发现配置试图改变电压，会直接报 `Voltage is immutable`；
- 真正提交的字段只有 `point_control.data.prog.freq_offset_khz`；
- 最后调用私有 NVAPI `ClockClientClkVfPointsSetControl`。

所以 LACT 的 UI 虽然画的是 V/F 曲线，但在协议层面表达的是：

```text
在驱动定义好的第 N 个电压点上，把基础频率加/减多少 kHz
```

它没有“现在立即把核心电压设成 910 mV”这样的逐时刻控制命令。

本地源码位置：

- `/tmp/LACT-src/lact-daemon/src/server/gpu_controller/nvidia.rs:385-505`
- `/tmp/LACT-src/lact-daemon/src/server/gpu_controller/nvidia/nvapi.rs:30-33,123-187`

### 2. 私有 NVAPI 到 RM 命令的映射

对本机 `/usr/lib/libnvidia-api.so.1` 的查询表和调用桩进行反汇编后得到：

| LACT/NVAPI 操作 | NVAPI Query ID | RM Control 命令 |
|---|---:|---:|
| VF points get info | `0x507b4b59` | `0x2080902a` |
| VF points get status | `0x21537ad4` | `0x2080902b` |
| VF points get control | `0x23f1b133` | `0x2080902c` |
| VF points set control | `0x0733e009` | `0x2080d02d` |

公开头文件 `ctrl2080base.h` 表明：

- `0x90` 是 Clock legacy non-privileged 类别；
- `0xd0` 是 Clock legacy privileged 类别。

因此三个读取命令是非特权 Clock 查询，而设置曲线的 `0x2080d02d` 是特权 Clock 控制。

### 3. 设置命令确定由 GSP-RM 接收和执行

当前机器启用了 GSP 固件：

```text
Driver / GSP firmware: 610.43.03
NVreg_EnableGpuFirmware: 1
```

从安装固件 `/usr/lib/firmware/nvidia/610.43.03/gsp_ga10x.bin` 提取出的 GSP-RM RISC-V ELF 中，四个命令均存在于 Subdevice 方法表：

| RM 命令 | 参数大小 | GSP 处理入口 | 方法标志 |
|---:|---:|---:|---:|
| `0x2080902a` | `0x324` | `0x010cb548` | `0x48` |
| `0x2080902b` | `0x1810` | `0x010cb6ec` | `0x48` |
| `0x2080902c` | `0x1014` | `0x010f35b4` | `0x48` |
| `0x2080d02d` | `0x1014` | `0x010cafcc` | `0x44` |

方法记录指向 class ID `0x4b01b3`；公开生成头 `g_subdevice_nvoc.h` 也将该 ID 定义为 `Subdevice`。公开 RM 标志定义则给出：

```text
0x04 = PRIVILEGED
0x08 = NON_PRIVILEGED
0x40 = ROUTE_TO_PHYSICAL
```

因此：

- 三个读取方法的 `0x48` = 路由到物理 GPU + 非特权；
- 设置方法的 `0x44` = 路由到物理 GPU + 特权。

CPU 侧公开内核模块中找不到这四个私有命令的处理实现。相反，`rmresControl_Prologue_IMPL()` 明确将带 `ROUTE_TO_PHYSICAL` 的固件客户端命令通过 `NV_RM_RPC_CONTROL` 转发；GSP 客户端的控制函数被设为 `rpcRmApiControl_GSP`。这把调用链钉死为：

```text
LACT
  -> libnvidia-api.so 私有 NVAPI
  -> RM control 0x2080d02d
  -> CPU Kernel-RM 负责序列化/RPC
  -> GSP-RM 的 Subdevice/Clock VF set handler
```

也就是说，问“谁接受并落实 LACT 写入的曲线”，答案现在是 **GSP-RM**，不是 CPU 侧开源内核模块，也不是 VBIOS 自己运行一段调速代码。

### 4. GSP 与 PMU 的职责边界

这里仍需区分“接受策略”与“高速闭环执行”：

- GSP-RM 持有 Clock/VF 私有控制对象，负责接收、鉴权、校验、保存和协调用户提交的曲线约束；
- GSP 固件中同时存在 `PERF_DAEMON`、`RmPmuPerfmonSampling`、`RmClockForceUprocVfeVfGen`、`RMClkVfOverride`、`EnableCoreVoltage`、`RmVolt*` 等性能/电压控制痕迹；
- 公开 Kernel-RM 代码还明确存在“来自 GSP-RM 的 PMU LibOS 日志缓冲区”，证明 PMU 是 GSP-RM 管理的独立 GPU 内微控制器/固件执行层，而不是 CPU 上的线程；
- NVIDIA 的 Blackwell DGX B200 官方文档明确说，GPU PMU 会在多个功耗策略中选择最保守的一个实施功耗限制。

据此，目前最精确、不过度推断的回答是：

```text
曲线写入的所有者：GSP-RM Clock/VF
运行时策略协调者：GSP-RM PERF/Clock
快速功耗反馈与底层执行：PMU + VOLT/AVFS/硬件控制器
实际输出电压的器件：板载 VRM
```

仍未钉死的只有一个更细的问题：Blackwell 所表现出的“当前电压以下约 50 mV 多点共同影响频率”究竟由 GSP-RM 的 PERF/Clock 代码先算成目标，还是由 PMU 内部 PERF daemon 在闭环中计算。NVIDIA 没有公开这部分实现；现有证据不足以诚实地把它单独归给其中一个。

### 5. MODS 内部电压偏移路径

对本地 MODS 包只做静态反汇编，没有在宿主机上运行它。解码的 JavaScript 和原生 ELF 同时表明内部 PERF API 至少有：

```text
SetRailVoltTuningOffsetMv(railIdx, offsetMv)
SetRailClkDomainVoltTuningOffsetMv(railIdx, clkDom, offsetMv)
SetFreqClkDomainOffsetkHz(clkDom, offsetKHz)
```

原生包装层的具体行为也已经定位：

- `SetRailVoltTuningOffsetMv` 入口 `0x015e1240`，通过 PERF 虚表 `+0xa8` 进入 `0x01677190`；
- `SetRailClkDomainVoltTuningOffsetMv` 入口 `0x015e13a0`，通过 PERF 虚表 `+0xb0` 进入 `0x01677270`；
- JS 层传入的 mV 乘以 `1000.0f`，内部使用 µV；
- 它们先更新 PERF 对象缓存，再由合并/校验函数 `0x01676470` 处理各电压轨和时钟域的偏移；
- 最后 `0x0166aa60` 提交 RM control `0x2080d01c`。

MODS 自带的 RM 方法表还保留了未剥除的命令名，因此可以精确命名这对接口：

```text
0x2080901b = subdeviceCtrlCmdClkDomainsGetControl
0x2080d01c = subdeviceCtrlCmdClkDomainsSetControl
```

这一路径还显式校验了逻辑电压轨、时钟域、偏移范围和 PState 锁定状态，并有如下错误文本：

```text
Cannot offset voltage on %s rail
Logical Rail %s not accepted for RailVoltTuning
Logical rail %s not accepted for RailClkDomainVoltTuning
Logical clock %s not accepted for RailClkDomainVoltTuning
PState is not locked, so no offsets can be applied to Clock Domains
```

当前 610.43.03 GSP-RM 的 Subdevice 方法表中仍有同一个命令 ID：

| RM 命令 | 610 GSP 参数大小 | GSP 处理入口 | 方法标志 |
|---:|---:|---:|---:|
| `0x2080901b` | `0x83c` | `0x010dd334` | `0x48` |
| `0x2080d01c` | `0x83c` | `0x010f3d1c` | `0x44` |

因此电压调校路径与 LACT 的 Clock VF-points 路径不是同一个命令，但它们都是 **Subdevice 下的特权 GSP-RM control**。MODS 样本使用的结构大小为 `0x7bc`，而当前 610 GSP 方法表要求 `0x83c`；这个 ABI 大小变化也说明不能把旧 MODS 调用原样直接塞给 610 GSP。

`0x010f3d1c` 并不是一个“收到数字后直接写 VRM 寄存器”的短跳板；它包含对 GPU/PERF 对象状态的检查、错误分支和多层间接调用。

老 RM 实现还把下一层说得更明白：

- `CLK_DOMAIN PMU_DATA_INIT` 负责把 Clock Domain 的 BoardObj 数据初始化到 PMU 侧；
- 电压偏移应用路径包含 `CLK_DOMAIN_3X_PROG voltage offsets` 和 `CLK_DOMAIN_30_PRIMARY VOLT_ADJUST_DELTA_UV`；
- 频率/电压互换不是纯 CPU 函数，RM 明确构造并发送 `CLK_DOMAIN_PROG_FREQ_TO_VOLT RPC` 与 `CLK_DOMAIN_PROG_VOLT_TO_FREQ RPC`；
- 发送路径取出 PMU 对象后调用统一的 PMU RPC transport，再将返回的电压/频率写回请求结构。

所以现在可以把边界缩小为：**Clock Domain/VF 数据和政策由 RM/GSP 管理，频压换算与快速执行明确有 PMU RPC 参与，板上 VRM 只是最终输出电压的物理执行器。**

### 6. PMU 程序能否直接读取

本地 MODS ELF 的 RM 实现包含以下三条独立日志和对应条件分支：

```text
Encrypted PMU-RISCV Debug Image will be loaded
Encrypted PMU-RISCV Prod Image will be loaded
Un-Encrypted PMU-RISCV Image will be loaded bIsPmuInDebugMode[%d]
```

对应代码位于 `0x06a8e500` 附近：它先检查 GPU/固件状态和调试模式，再分别选择加密调试镜像、加密量产镜像或未加密镜像。这里可以确认的是：

- NVIDIA 的 RM 确实支持并主动选择加密的 PMU RISC-V 量产镜像；
- “PMU 是代码”不代表量产 PMU 的明文一定存在于磁盘上；
- 当前安装的 `/usr/lib/firmware/nvidia/610.43.03/ucodes_ga10x.bin` 只有 24 字节 `NVUCODES` 头，`0x18` 到文件末尾全部为零，不含可反汇编的 PMU 正文；
- PMU 载荷应当来自 GSP 固件携带的 bindata/受保护镜像，而不是这个空壳 `ucodes_ga10x.bin`；
- 当前 `nvidia-smi -q` 只报告 `GSP Firmware Version: 610.43.03`，启动日志没有公开实际选择的 PMU 镜像类型。

因此目前的可读边界是：

```text
可读：LACT -> 用户态 NVIDIA API -> CPU RM -> GSP-RM 方法 -> PMU RPC 参数/返回值
受阻：量产 PMU 镜像内部的实时 V/F 控制算法（很可能为加密载荷）
```

这已经足以确定责任归属和控制接口，但若要精确解释“为什么某一次光追负载从 2835 MHz 降到 2670 MHz”，还需要 PMU 运行时日志、遥测状态或受控实验；单靠磁盘上的量产固件无法诚实地还原全部算法。

### 7. 固件样本可复现信息

```text
外层固件：/usr/lib/firmware/nvidia/610.43.03/gsp_ga10x.bin
外层 SHA-256：572373620a37418f24dc16b5031c39338778c3257e48e8408de9a57291b24f3a
内层偏移：0x19f040
内层 SHA-256：bda917c95547644398eaf77fefe6c7f1b701c962db91f88bffaed6448a218a47
格式：ELF64 little-endian RISC-V，stripped，RVC
```

详细提取方法见 `parallel/GSP_ARTIFACT_PROVENANCE.md`。

### 8. 直接读取 PMU 动态功耗目标

MODS 的 Power 对象提供了一个用途非常明确的只读方法：

```text
GetCurrPowerCapLimFreqkHz
Get current power capping limited frequency.
```

静态反汇编表明，该包装函数构造一个 `0x148` 字节的 limit status 项，把 limit ID 写成 `0x43`，然后提交：

```text
0x2080a079 = subdeviceCtrlCmdPerfLimitsGetStatusV2
参数大小   = 0x14804 = 4 + 256 * 0x148
有效位     = entry + 0x13c
频率 kHz   = entry + 0x144
```

当前 610.43.03 GSP-RM 方法表中也保留了同一命令，参数大小仍为 `0x14804`，处理入口为 `0x0163f038`，方法标志为 `0x48`。所以它是由当前 GSP 接收的非特权、只读物理 GPU 查询，不是旧 MODS 自己模拟出来的数值。

`0x43` 的名称也已经确定。NVIDIA 570.86.16 驱动包内的 `libnvidia-ml.so` 保存了一张显式的 ID 到名称映射表；文件偏移 `0x211360` 的记录是：

```text
ID      = 0x43
字符串  = PERF_LIMIT_PMU_DOM_GRP_1
```

这不是按字符串排列顺序推测，而是二进制表内的直接键值对应。

为验证运行时状态，本地写了两个独立只读探针：

- `/home/user/rt_5090_project/power_cap_limit_probe.c`：读取 `PMU_DOM_GRP_1` 当前动态限频；
- `/home/user/rt_5090_project/perf_active_limits_probe.c`：读取 RM 暴露的 237 个传统 PERF limit 以及当前 active 集合。

两者只分配进程私有 RM client/device/subdevice 对象并发出 GET control，退出前释放；不包含 SET control、MMIO、PCI config、复位、模块、固件、频率、电压、风扇或功耗写入。

当前 GSP 还公开给 RM 三个相关的只读控制方法：

```text
0x2080a618  PowerPoliciesGetInfo           参数 0x4e20
0x2080a619  PowerPoliciesGetDynamicStatus  参数 0x60af8
0x2080a61a  PowerPoliciesGetStatus         参数 0x3610
```

`GetInfo` 在本机返回 17 个受支持策略（mask `0x1ffff`）和 violation mask `0x7bff`。`GetDynamicStatus` 显示策略 0 的类型值是 `0x14`。重新逐项解出 MODS 二进制里的直接类型表后，映射为：`0x11=WORKLOAD_PHYSICAL_SINGLE_2X`、`0x12=WORKLOAD_LOGICAL_SINGLE_2X`、`0x13=WORKLOAD_DIE_2X`、`0x14=WORKLOAD_COMBINED_2X`；当前 GSP 的断言也明确要求 die 策略类型为 `0x13`。因此策略 0 是汇总下层模型的 `WORKLOAD_COMBINED_2X`，不是 `WORKLOAD_DIE_2X`。该动态记录还包含 `CurrLimit`、`CurrValue` 以及两个 domain-group 频率目标。

`CurrLimit` 和 `CurrValue` 的单位现已确认。MODS 的动态状态打印函数从每个策略的缓存信息中读取同一个 `limitUnit`，再调用单位后缀函数；该函数的直接分支为：枚举 `0` 输出 `mW`，枚举 `1` 输出 `mA`，其余值报 `Unknown policy limit unit type`。当前 `GetInfo` 的通用记录头从 `+0x00d0` 开始、步长为 `0xfc`；策略 0 的头字为 `0x00000314`，按字节拆分正是 `type=0x14`、输入通道 `3`、`limitUnit=0`。继续按 `0xfc` 步长读取所得 17 个类型与动态状态逐项一致；策略 9 的头字 `0x0001091e` 又显示 `limitUnit=1`，证明这个字节确实随策略改变。`+0x009c=0x00010014` 虽然低字节也恰好是 `0x14`，但它位于策略 0 的类型专用配置区，不能误当成通用头。

GSP 中的断言还要求 `TOTAL_GPU` 与 core/FB，以及 combined、die、logical/physical-single 各关系两端的 `limitUnit` 相同。本机各功率策略的 `600000`、`1001000`、`5001000` 等额定值以及运行时变化也都与上述单位一致。因此策略 0 的这两个字段可分别记为当前组合策略功率预算和当前组合模型功率值，单位均为 mW；它们不是整卡 `nvidia-smi` 功耗的简单副本。

新增的 `--policy-info-summary` 已把 17 条策略的通用头、输入通道、单位和额定上下限直接列出。最重要的拓扑分成两棵镜像树：

```text
功率树（mW）
  policy 3/4  WORKLOAD_PHYSICAL_SINGLE_2X，input 4/5
    -> policy 5/6  WORKLOAD_LOGICAL_SINGLE_2X，input 4/5
    -> policy 0    WORKLOAD_COMBINED_2X，input 3

电流树（mA）
  policy 11/12 WORKLOAD_PHYSICAL_SINGLE_2X，input 13/12
    -> policy 13/14 WORKLOAD_LOGICAL_SINGLE_2X，input 13/12
    -> policy 10    WORKLOAD_COMBINED_2X，input 11
```

同一次 `GetDynamicStatus` 返回内，功率树满足精确恒等式。例如某个样本为 `policy0.CurrValue=47807`、`policy3=29648`、`policy4=18159 mW`，且 `29648+18159=47807`；policy 5/6 又分别精确重复 3/4。电流树也满足 `policy10=policy11+policy12`，13/14 分别重复 11/12。policy 16 则使用一个约 50 MW 的放宽上限并重复 policy 0 的当前值，像是不会参与正常限频的观测/对照副本。由此可确认 policy 0 是实际汇总器，而不是单一 die 传感器。

继续向上追踪又得到两条逐整数精确成立的预算关系：

```text
policy2 TOTAL_GPU.CurrValue
  = policy0 WORKLOAD_COMBINED_2X.CurrValue
  + policy1 PROP_LIMIT.CurrValue

policy0 WORKLOAD_COMBINED_2X.CurrLimit
  = policy2 TOTAL_GPU.CurrLimit
  - policy1 PROP_LIMIT.CurrValue
```

例如同一返回中的数值为 `75263 = 46671 + 28592 mW`，以及 `589426 = 618018 - 28592 mW`；另一次独立查询仍以零误差满足 `81162 = 50330 + 30832`、`587186 = 618018 - 30832`。因此 policy 1 是组合 2X 树之外、必须先从 TOTAL_GPU 动态预算中扣除的那部分功率，policy 0 再把剩余预算分给两条 physical/logical-single 模型。CP2077 中 policy 0 的 `CurrLimit` 从空闲附近的约 590 W 降到平均约 465 W，正是这条上游扣减链随负载增大的结果。

当前 GSP 的只读 `0x2080a612` PMGR info 方法又返回了受支持 power-channel mask `0x7abf`。其通道记录从 `+0x1c` 开始、步长 `0x148`；记录头的低字节为通道类型，下一字节为 power-rail 枚举。MODS 内有一张直接的“枚举值→名称”表，因此可把本机实际使用的输入通道确定为：

| Channel | Rail enum | 名称 | 被哪些策略使用 |
|---:|---:|---|---|
| 0 | `0xf5` | `INPUT_TOTAL_BOARD` | policy 2 |
| 3 | `0xd6` | `INPUT_TOTAL_CORE` | policy 0/16 |
| 4 | `0xf6` | `INPUT_NVVDD` | policy 3/5 |
| 5 | `0xd4` | `INPUT_MSVDD` | policy 4/6 |
| 7 | `0xe8` | `INPUT_MISC0` | policy 1 |
| 9 | `0xa9` | `INPUT_SUM` | policy 9 |
| 11 | `0x0d` | `OUTPUT_TOTAL_CORE` | policy 10 |
| 12 | `0x10` | `OUTPUT_MSVDD` | policy 12/14 |
| 13 | `0x01` | `OUTPUT_NVVDD` | policy 11/13 |

这把上述整数关系落实到了真实 rail：policy 3/4 分别是 NVVDD 与 MSVDD 功耗，policy 0 是二者之和 `TOTAL_CORE`；policy 1 是 `MISC0`，policy 2 是 `TOTAL_BOARD`。因此预算链可以明确写成：

```text
NVVDD + MSVDD = TOTAL_CORE
TOTAL_CORE + MISC0 = TOTAL_BOARD
TOTAL_CORE 可用预算 = TOTAL_BOARD 动态预算 - MISC0 当前功耗
```

`MISC0` 是 NVVDD/MSVDD 核心 rail 之外的板卡功耗汇总，可能包含显存/FB 供电及其他板上负载；现有接口不能把它武断地只称为显存功耗。CP2077 中 policy 0 平均约 465 W 的含义现已清楚：总板预算先扣掉负载下显著增大的 `MISC0`，剩余部分才交给 NVVDD/MSVDD 的 2X 模型反算频率。

相邻的只读 `0x2080a613` PMGR status 方法返回每条 power channel 的实时值。探针新增 `--pmgr-a613-summary` 后，同一帧直接满足：

```text
INPUT_NVVDD  32.521 W + INPUT_MSVDD 19.915 W
  = INPUT_TOTAL_CORE 52.436 W

INPUT_TOTAL_CORE 52.436 W + INPUT_MISC0 32.129 W
  = INPUT_TOTAL_BOARD 84.565 W

OUTPUT_NVVDD 27.847 A + OUTPUT_MSVDD 6.680 A
  = OUTPUT_TOTAL_CORE 34.527 A
```

另一次独立查询仍精确得到 `27.901+17.098=44.999 W`、`44.999+27.568=72.567 W` 和 `29.243+8.152=37.395 A`。后续同步 CP2077 采样及 A612 静态字段推翻了这里“独立真实 rail 电表”的解释：本机输入功率通道由整卡输入按 Q12 固定比例构造，`TOTAL_CORE/TOTAL_BOARD=0x09ec/0x1000`、`NVVDD/TOTAL_BOARD=0x0627/0x1000`，其余两路为差值。它们确实是策略使用的实时状态，但不是彼此独立的物理测量；详见 `BLACKWELL_CONTROL_LOGIC_EXTRACTION_20260725.md` 19.11。

为排除“两个接口只是碰巧接近”，探针新增了成对读取模式：先读策略 0 的 `DG0`，随即读 `0x43`。短时 CUDA 负载下 12 对结果有 11 对完全相同，例如 `3007/3007 MHz` 和 `2977/2977 MHz`；唯一一对是 `2977/2992 MHz`，刚好相差一个 15 MHz 时钟档位，符合两条顺序查询之间控制器刷新了一次目标。

最新运行结果：

| 场景 | PMU `0x43` 动态目标 | 实际核心频率 | 传统 active PERF limits |
|---|---:|---:|---:|
| 空闲 | 3090 MHz | 空闲状态 | 0 |
| 短时 CUDA FMA | 3090 → 3030 → 3022 → 3007 → 2977 MHz | 最终约 2970 MHz | 0 |
| CP2077 6K 光追基准 | 2437–3000 MHz，平均 2804.1 MHz | 2707–2857 MHz，平均 2772.5 MHz | 1857/1857 次查询均为 0 |

CP2077 同一轮还测得：平均电压 916.4 mV、1 秒平均板卡功耗 404.6 W、瞬时最高功耗 452.7 W；没有 Xid、硬件 slowdown、温度限制或 power-brake。策略 0 的 423 个样本为：

```text
WORKLOAD_COMBINED_2X DG0：2505–2985 MHz，平均 2799.0 MHz
WORKLOAD_COMBINED_2X DG1：2250–2685 MHz，平均 2515.8 MHz
0x43 动态目标：       2437–3000 MHz，平均 2804.1 MHz
实际核心：            2707–2857 MHz，平均 2772.5 MHz
```

`DG0` 和 `0x43` 的平均值只差 5.1 MHz；顺序成对查询又几乎逐项完全相等，因此可以把 `WORKLOAD_COMBINED_2X` 的 `DG0` 确认为 `PMU_DOM_GRP_1` 动态目标的上游来源。MODS 的测试脚本进一步把该值逐字打印为 `PMU_DOM_GRP_1 gpc2clk limit`，所以 `DG0` 对应核心 `GPC2CLK`。`CurrLimit` 与 `DG0` 的相关系数约为 `+0.710`，`CurrValue` 与 `DG0` 约为 `-0.710`，说明该策略确实在参与计算频率目标。上游预算关系现已由 `TOTAL_BOARD - MISC0 = TOTAL_CORE` 精确确定；尚未还原的是 2X 模型如何由功率、电流、电压和芯片参数反解具体频率的公式。

对当前 610.43.03 驱动的全部 `0..236` limit ID 做了一次只读枚举后，还找到了两个旧 570 名称表没有覆盖的有效项。必须使用 610 自身的稀疏 ID→名称表，不能按记录位置或旧版编号推算：

```text
0xe9 = PERF_LIMIT_THERM_POLICY_XBAR
0xea = PERF_LIMIT_PWR_POLICY_XBAR
```

顺序成对读取显示：高状态下 `0xe9 = 0xea = DG1 = 3135 MHz`；状态切换后 `0xe9` 保持 `3135 MHz`，而 `0xea` 与 `DG1` 同时降到 `2722/2752 MHz`。交错读取又重复了这一关系。因此 `DG1` 是 `XBAR` 时钟目标，并取热策略和功耗策略候选值中的较低者；这也解释了 CP2077 中 `DG1` 平均约 2516 MHz 却不等于实际核心频率。

探针新增 `--perf-limit-summary`，在一次只读 RM control 中同时查询八条相关候选。当前空闲快照为：`OVERVOLTAGE_LOGIC/RELIABILITY_LOGIC/RELIABILITY_ALT_LOGIC = 3030 MHz`，`PMU_DOM_GRP_1/THERM_POLICY_DOM_GRP_1 = 3090 MHz`，`THERM_POLICY_XBAR/PWR_POLICY_XBAR = 3135 MHz`。因此空闲/轻载的核心频率能力上限先受约 3030 MHz 的过压/可靠性逻辑约束；光追游戏中则由降到约 2.8 GHz 的 PMU 动态功耗候选变成最低项。

进一步对策略 0 的 Blackwell 动态状态做了字段级只读采样。已确认的结构关系如下：

```text
+0x00a0  CurrLimit（mW）
+0x00a4  CurrValue（mW）
+0x01e0  observed logical total；每次都精确等于 CurrValue
+0x01e8  observed physical branch 0
+0x09c8  observed physical branch 1
          恒等式：+0x01e0 = +0x01e8 + +0x09c8
+0x0210  observed physical branch 0 frequency（MHz）
+0x0214  observed physical branch 0 leakage
+0x0218  observed physical branch 0 voltage（mV）
+0x021c  observed physical branch 0 value
+0x0220  sensed voltage（uV）；每次严格等于 +0x0218 * 1000
+0x0224  observed physical branch 0 workload

+0x11b8  estimated logical total
+0x11cc  estimated physical branch 0 workload
+0x11d4  estimated physical branch 0 voltage（mV）
+0x11d8  estimated physical branch 0 candidate frequency（MHz）
+0x11e0  estimated physical branch 0 value
+0x1468  estimated physical branch 1 workload
+0x1470  estimated physical branch 1 voltage（mV）
+0x1474  estimated physical branch 1 candidate frequency（MHz）
+0x147c  estimated physical branch 1 value
          恒等式：+0x11b8 = +0x11e0 + +0x147c
```

一次不额外启动负载、利用《崩坏：星穹铁道》后台自然活动的 10 秒采样中，`CurrLimit` 为约 577–598 W、`CurrValue` 为约 33–67 W，而板卡功耗为约 59–97 W。这进一步说明该策略操作的是组合后的内部 rail 模型，并非直接复制整卡功耗。随后在同一次 RM 返回内确认：`+0x01e8` 与 `+0x021c` 都精确等于 policy 3 的 `CurrValue`，policy 4 则等于 policy 0 减去该值。因此这两个重复项来自第一条 physical/logical-single 功率分支；它们更细的结构成员名仍待确认。

后续扩大静态检索范围后，上述“旧 MODS 不含 2X 类型专用状态”的判断需要作废。该 RM 中实际保留了一整套直接以 `obsMet.logicalSingles[]`、`obsMet.logicalSingles[].physicalSingles[]`、`obsMet.dies[]`、`estMet.logicalSingles[]`、`estMet.dies[]` 和 `regimesStatus.searchRegimes[]` 命名的 2X 指标路径。物理分支明确包含 `workload`、`leakagemX`、`voltmV`、`observedVal`、sensed voltage/ADC samples、独立时钟域 Vmin、soft floor、Fmax@Vmin/Vmax，以及 V/F residency；估算分支则包含 `estimatedVal`、`effectiveFreqMHz` 和候选频率。`regimesStatus` 又保存候选 tuple、起止索引和搜索 regime。这说明 2X 不是简单用“当前功耗乘一个比例”限频，而是先采样每个 physical-single 的工作负载、电压、漏电和 V/F 驻留，再形成 logical-single/die 的 observed metrics，随后在候选频率元组上建立 estimated metrics 并搜索满足预算的 domain-group 频率。

一次约 4 秒的只读带宽负载验证把上述字段关系从“静态命名”推进到了运行时恒等式。稳定阶段 `CurrLimit` 约 535–536 W，实际模型值约 133–135 W，而两个候选频率保持在 3030/2767 MHz；对应 `estimated logical total` 约 285 W，仍明显小于可用预算，所以 DG0 保持 3090 MHz。代表性样本为：`observed 133256 = 82628 + 50628`，`estimated 285340 = 82281 + 203059`。这证明 DG0 搜索真正比较的是候选频率下的 `estimated logical total` 与 `CurrLimit`，而不是当前实测 `CurrValue` 与整卡瓦数。

随后用同一探针对 Cyberpunk 2077 6K Path Tracing 基准做了两轮场景内采样。第二轮修正字段后得到 414 个完整样本：整卡一秒平均功耗 409.3 W、实际核心 2772.9 MHz、独立 `0x43` 动态目标 2795.2 MHz，policy 0 同步 DG0 为 2787.4 MHz；三层数值已按 `DG0 -> 0x43 -> 实际离散时钟` 的顺序吻合。policy 0 的平均 `CurrLimit` 为 459.999 W、`CurrValue/observed logical` 只有 257.949 W，而候选元组的 `estimated logical` 已达 447.307 W。更关键的是，414 个样本中 `estimated logical` 从未超过 `CurrLimit`；二者差值中位数只有 3.661 W，估算值/预算中位数为 99.17%，75.4% 样本落在预算下方 10 W 内，84.1% 落在 20 W 内。`CurrLimit` 与同步 DG0 的相关系数为 `+0.730`，候选 branch 0 频率与 DG0 为 `+0.761`。这已经直接验证：2X 搜索器选择的是“估算功耗不越过核心预算”的最高候选 tuple；约 409 W 的整卡实测值并不是它直接比较的数，所以表面仍有约 191 W 距 600 W 上限并不代表核心频率还有同等可用余量。

该轮首次扩展采样还暴露并修正了一个探针标注错误：动态 policy 的 DG0/DG1 位于 `+0x0028/+0x002c`；`+0x01c0/+0x01c4` 在第一轮始终为 3090/3135 MHz，是模型边界字段，不能标成最终策略目标。第一轮 CSV 原始数据保持不改并附了勘误，第二轮探针已使用正确偏移。第二轮内的线性描述为 `DG0_MHz ~= 1444.97 + 2.91825 * CurrLimit_W`；粗略对应约 499/533/564 W 的核心策略预算可到 2900/3000/3090 MHz，再加该场景平均约 140 W 的 `MISC0` 预留，总板预算规划值约为 639/673/704 W。它混合了不同画面负载，只能作为下一步预算范围，不能当成固定硬件公式。完整分析见 `benchmark_logs/cp2077_6k_20260725_022230/combined2x-analysis.txt`。

当前 610 GSP 的构造检查代码与这套结构相符：`WORKLOAD_COMBINED_2X` 同时持有一段 `logicalSingleRelIdxFirst..Last` 和一段 `dieRelIdxFirst..Last`，逐项要求 limit unit 一致，并要求 die 关系指向类型 `0x13 WORKLOAD_DIE_2X`；logical-single 又继续汇总 physical-single。由此可把算法结构写成：`physical measurements -> logical/die observed metrics -> candidate-frequency estimated metrics -> regime/tuple search -> DG0/GPC2CLK target`。具体定点公式仍在 PMU 实现内，但参与变量和搜索方式已经不再只是推测。

### 2X 三段搜索器的精确运行时复原

后续新增的只读 `--policy0-regimes-raw` 把同一次 `POWER_POLICIES_GET_DYNAMIC_STATUS` 返回中的七个 regime 边界、152 字节搜索区和 estimated metrics 放在同一行。由静态成员名和运行时取值共同确认，搜索区从 `startRegimeId` 开始，随后是五个 28 字节 `searchRegime` 记录和两个 4 字节 tuple 状态槽；当前卡只有前三个 regime 有效，后两个为 `0xff` 哨兵。每个有效记录包含：

```text
u16 tupleStartIdx
u16 tupleEndIdx
u16 clkFreqStartIdx
u16 clkFreqEndIdx
u8  regimeId + 3 字节状态/填充
两端各一组 (freq0MHz, freq1MHz)
```

FurMark 稳定负载的一组代表性表为：

```text
regime 1: tuple   0..279, clock  30..309, (225,2085) -> (2317,2085) MHz
regime 2: tuple 280..373, clock 310..403, (2325,2092) -> (3022,2715) MHz
regime 3: tuple 374..377, clock 363..366, (3022,2722) -> (3022,2745) MHz
```

这些索引严格落在 7.5 MHz 时钟网格上，三段的含义也因此明确：regime 1 只抬 primary、secondary 保持不变；regime 2 两路按传播比例同步上升；regime 3 则固定 primary ceiling、继续抬 secondary。它不是一条简单的“瓦数转 MHz”直线，而是当前两条 V/F/传播关系生成的二维分段表。

尾部 tuple 状态槽不是最终 DG 输出；它记录当前用于 estimated metrics 的求值 tuple。离线解码器按端点线性插值后，在 89 个稳定样本中复原 `est_freq0_mhz` 的平均绝对误差为 `0.266 MHz`、最大 `0.5 MHz`，复原 `est_freq1_mhz` 的平均绝对误差为 `2.124 MHz`、最大 `5.69 MHz`。第二轮 112 个样本又得到 `0.308/2.472 MHz` 的平均绝对误差。两次都远小于一个 7.5 MHz 档位，因而 tuple 结构、端点含义和插值关系已经得到逐样本验证，而非仅有相关性。

同一批数据还厘清了 raw ceiling 与模型求值频率的层次。112 个稳定 FurMark 样本中：

```text
DG0 - regimesStatus.freqPriStartMHz:
    平均 -0.062 MHz，平均绝对误差 0.062 MHz；111/112 完全相等

DG0 - evaluated tuple freq0:
    平均 +370.365 MHz
```

唯一一次 DG0 与 `freqPriStartMHz` 不同只差约 7 MHz，是两条顺序状态读取跨过控制周期造成的单档变化。因此 `freqPriStartMHz` 是当前 primary raw ceiling，直接对应 policy 0 发布的 DG0；tuple 频率则是功耗模型内部的求值工作点，不能拿来直接代替 DG0。一次同帧原始快照更直观：`DG0/observed logical freq = 2962/2962 MHz`，但 estimated tuple 为 `2557/2295 MHz`；在这一求值点上 estimated 已达 `394.493 W`，而 `CurrLimit=394.824 W`。这就是约 3.0 GHz raw clock 与约 2.6 GHz 功耗等效求值频率同时出现的原因。

搜索状态的可重复离线解码器位于 `scripts/decode-combined2x-regimes.py`。它会检查 blob 长度、解码三个分段、插值 tuple，并分别报告 tuple→estimated frequency 和 DG0→primary ceiling 的误差。

### 板上 power-equation 参数也可只读获取

逆向 MODS 的 `GetPowerEquationTable` 后确认它最终只调用 `0x2080a616 subdeviceCtrlCmdPmgrPwrEquationGetInfo`，参数区为 `0x490` 字节；相同只读调用可由当前 610.43.03 驱动直接接受。当前卡返回 `equationMask=0x3f`，即六条有效方程，按两条 rail 成对出现：

```text
equation 0/1: type 0x07，四个有符号 k 类系数、效率/扩展字段
equation 2/3: type 0x05，主参数均为 5324
equation 4:   type 0x06，1000000, 802897, 2000, 108, rail/tag 2, 1300000
equation 5:   type 0x06，1000000, 987463, 2000, 108, rail/tag 3, 1300000
```

构造分派代码确认 type `0x05` 走 `DYNAMIC10` 方程路径；type `0x06` 的字段形态与参考电压、基准功率、GPC/utility 基准时钟的 scale equation 一致；type `0x07` 在 leakage 方程基类上增加两个 16 位效率字段，且静态属性表明确列出 `k0..k3/fsEff/pgEff`。所以 2X 的 estimated power 并非 PMU 中写死一个“RT 倍率”，而是用 VBIOS/RM 下发的每 rail 动态、缩放和泄漏方程，加上实时 workload、voltage、frequency、leakage 与 V/F residency 求值。

把现有 CP2077 与 FurMark 样本放进物理形态 `workload * frequency * voltage^2 + leakage/scale` 的回归后，两路功率都能达到 `R² > 0.9999`；加入当前接口已经暴露的线性/交叉项后，平均绝对误差约为 `63/48 mW`。这证明字段足以描述输出，但回归系数会混入上述 VBIOS 方程、定点缩放和共线性，不能冒充 PMU 的原始整数实现。当前仍缺的是 type 5/6/7 的完整定点求值顺序以及 estimated working frequency 如何由 raw ceiling 与 V/F residency 生成；方程参数本身已经不再是黑箱。

这也解释了为何 CP2077 只有约 405 W 板卡实测功耗，却持续报告 `SW_POWER_CAP`：`CurrValue` 是当前 observed value，而 `DG0` 来自“把候选频率提高后”的 estimated value 与 `CurrLimit` 比较，二者不要求在当前采样点相等。600 W 总板预算先扣除 `MISC0`，使核心模型在该基准中的平均 `CurrLimit` 只有约 465 W；模型据此把 DG0 选在约 2.8 GHz。相同场景下把平均电压从约 898 mV 提高到约 917 mV，板卡功耗由约 393 W 增至 409 W，实际频率反而由约 2788 MHz 降至 2772 MHz，正符合“更高电压提高 estimated power，从而降低获批频率”的行为。

### FurMark Vulkan 对照：同一 2X 策略，不同的负载映射

为解释“FurMark 能接近 600 W 且频率接近上限，而 6K 路径追踪只有约 409 W/2.77 GHz”的表面矛盾，又用 FurMark 2.10.2 的 `furmark-vk` 在 3840x2160、VSync 关闭条件下做了 15 秒同步采样。稳定负载中 NVML 得到 293 个 GPU 利用率 100% 的样本：实际图形频率平均 2958.1 MHz，板卡瞬时功耗平均 574.1 W、峰值 591.1 W，全部样本均报告 `SW_POWER_CAP`。LACT 独立采样为平均 2956.6 MHz、约 1010 mV、571.0 W，与 NVML 一致。

剔除启动/退出并要求 policy 0 `CurrValue >= 300 W` 后，299 个 2X 样本为：

```text
CurrLimit                  400.248 W
CurrValue / observed       355.487 W
estimated                  397.766 W
CurrLimit - estimated        2.481 W
DG0                       2966.06 MHz
estimated <= limit+5 W       86.6% 样本
estimated <= limit+10 W      99.7% 样本
```

因此 FurMark 并没有绕过 `WORKLOAD_COMBINED_2X`；恰恰相反，它同样把 estimated tuple 压在预算边缘，而且 DG0 与实际频率只差约 8 MHz。真正的区别是模型误差/保守余量随 workload regime 改变：FurMark 中 `estimated-observed` 平均只有约 42.3 W，而按同样用较高 observed 值剔除 CP2077 场景切换样本后，CP2077 为约 `445.6-274.3=171.3 W`。更直观地说，FurMark 在更小的约 400 W 2X 预算下仍获批约 2966 MHz；CP2077 即使有约 450 W 预算，模型却只给约 2765 MHz，因为它把路径追踪的候选 tuple 判定为远比 FurMark 更“昂贵”。

这证明 `CurrLimit -> DG0` 不存在跨 workload 通用的一条瓦数/频率直线。2X 会根据两条分支的 workload、模型电压、漏电和搜索 regime 使用不同映射。甜甜圈的高实际功耗和高显示频率并不反驳2X限频；它说明该模型对稳定 Vulkan 栅格压力负载的 observed/estimated 比较接近，而对 6K RT/PT 混合负载明显更保守。当前最值得继续追的对象因此不是整卡功耗上限，而是2X的 workload/regime 分类及其倍率/模型参数。

### 关闭 LACT 调校后的 A/B 对照：400 W 并非 CP2077 的固有上限

随后通过 LACT 自己的 `SetClocksValue(Reset)` 路径清除了整张自定义 V/F 曲线、显存 `+2000` 偏移和显存锁频，只保留风扇曲线与 VBIOS 报告的默认 `600 W` 功耗上限。读回确认显存由 `15001 MHz` 恢复到 `14001 MHz`，配置中不再存在 `gpu_vf_curve` 或 clock offset。测试完成后已通过同一 LACT 配置接口恢复原曲线和显存设置。

相同 6144×3456、相同游戏设置的 CP2077 内置基准，与相同 3840×2160 Vulkan FurMark 的结果如下：

| 负载 | LACT 状态 | 实际频率 | 电压 | 整卡功耗 | policy0 核心预算 | policy0 observed / estimated |
|---|---|---:|---:|---:|---:|---:|
| CP2077 6K PT | 自定义曲线 | 2772.9 MHz | 916.9 mV | 409.3 W | 460.0 W | 257.9 / 447.3 W |
| CP2077 6K PT | 默认曲线 | 2745.6 MHz | 1020.1 mV | 568.5 W | 400.7 W | 354.8 / 392.5 W |
| FurMark Vulkan | 自定义曲线 | 2958.1 MHz | 1010.3 mV | 574.1 W | 400.2 W | 355.5 / 397.8 W |
| FurMark Vulkan | 默认曲线 | 2263.9 MHz | 918.1 mV | 600.7 W | 373.9 W | 371.0 / 372.7 W |

这组对照推翻了一个过度简化的初步表述：**CP2077 的约 400 W 不是该 workload 在默认卡上的固有功耗，也不是 NVIDIA 单独给 RT/PT 写死了约 400 W 上限。**关闭 LACT 调校后，它会在约 `1.02 V` 下接近整卡 600 W；原先约 400 W 主要来自自定义 V/F 曲线让该负载驻留在约 `0.917 V`，而 FurMark 在同一自定义曲线下驻留在约 `1.01 V`。因此“同一曲线、不同 workload”会落到完全不同的电压点，动态功耗随 `V²` 与实际开关活动显著变化。

同时，V/F 曲线会进入 2X 模型本身，而不只是最后把同一 DG0 换算成另一个电压。CP2077 从自定义切回默认后，policy0 的平均 `CurrLimit` 从约 `460.0 W` 降到 `400.7 W`，但 estimated 值反而从 `447.3 W` 降到 `392.5 W`，DG0 又从 `2787.4 MHz` 升到 `3002.9 MHz`；两条分支的 workload、候选频率和模型电压也同步改变。FurMark 也出现同样的重映射。因此此前观察到的 `estimated-observed` 差值不能全部归因于“RT workload 固有保守倍率”，其中有相当部分来自自定义曲线改变 V/F residency、有效频率以及 workload 归一化结果。

还有一个独立且重要的异常：默认 CP2077 的平均 FPS 为 `11.399`，先前两次自定义曲线运行则为 `9.961/9.835`，尽管自定义曲线的 NVML 显示核心频率略高、显存频率也更高。为排除缓存变暖或一次性波动，恢复原曲线后又立即做了第三次相同设置的 A-B-A 复测，得到 `9.948 FPS`、`2784.4 MHz`、`919.5 mV`、`406.7 W`，再次回到前两次自定义曲线结果。因此默认状态的约 `+14.6%` 吞吐差异可重复归因到运行状态变化，而不是游戏设置差异；四次 summary 除 FPS/time 外的游戏设置完全一致。现有数据仍不足以把原因唯一归为 clock stretching；更稳妥的解释是 NVML 显示的 GPC 时钟不能代表该 PT workload 的完整有效吞吐量，隐藏的 duty cycle/clock stretching、XBAR 目标（默认约 `2669 MHz`，自定义约 `2505 MHz`）以及 RT/Tensor/片上互连驻留都可能参与。后续若要判断这条曲线是否真的提升游戏性能，必须以相同场景 FPS/帧时间为准，不能只看显示 MHz。

默认 FurMark 仍在达到 `--max-time 15` 后以用户态段错误退出；负载阶段完整，测试后 GPU 正常回到空闲，内核日志无 NVIDIA Xid。

本次 FurMark 在达到 `--max-time 15` 后用户态进程以 139 段错误退出，但负载完整持续约15秒；测试后 GPU 回到空闲，内核日志没有出现 NVIDIA Xid。原始数据位于 `benchmark_logs/furmark_vk_3840x2160_20260725_031937/`。

离线差分又表明 Matrix 600→800 W 不改变这些工作负载模型/VF 表，只把总预算相关的 600 W/60 A 字段提高到 800 W/80 A。因此若启动对应 800 W BIOS，policy 0 的核心可用预算应近似多出 200 W（仍需扣除同一时刻的 `MISC0`），现有 CP2077 样本中 `CurrLimit` 与 DG0 的线性斜率约为 `+2.68 MHz/W`、相关系数约 `0.71`。线性外推会超过当前约 3.09 GHz 的 domain ceiling，所以合理预期不是继续线性增加，而是先撞到 V/F/时钟 ceiling。这个结论说明提高板卡预算确实直接作用于当前最主要的 2X 限制，但最终能否到达并稳定维持 ceiling 仍必须由对应 BIOS 的运行时数据验证。

同时修正一个初步误判：`+0x01f8/+0x01fc`、`+0x0200/+0x0204` 以及后面的对应组合应按连续递增的 64 位值解释，不是两个独立的 32 位“估算功耗”字段。不能把其中的高 32 位数值（例如约 `155000`）标成 `EstPower`。探针现同时提供 `--policy0-model-raw` 和已验证字段版 `--policy0-model-summary`；后者还直接输出 observed/estimated 两个求和误差，便于发现结构或固件版本变化。

有一个重要限定：在光追负载中，`0x43` 不是每个 50 ms 样本都等于实际频率。按时间戳就近对齐后，动态目标平均比实际频率高约 30 MHz，但平均绝对差约 124 MHz，原始相关系数只有约 0.076；对两秒窗口平滑后相关性升到约 0.47。说明它是快速变化且与用户态异步采样的 PMU 控制周期输出，随后还会经过滤波、其他约束仲裁和时钟步进，不能把任一瞬时读数当作最终硬上限。

不过三条证据结合后，控制归属已经很清楚：

```text
PMU WORKLOAD_COMBINED_2X 汇总下层负载/芯片模型并计算 DG0 目标
  -> PERF_LIMIT_PMU_DOM_GRP_1（0x43）发布该动态目标
  -> PERF/Clock 仲裁、滤波和离散时钟档位
  -> 最终实际 GPC 频率
```

本轮原始数据位于：

- `/home/user/rt_5090_project/benchmark_logs/cp2077_6k_20260724_231007/`
- `power-cap-limit.csv` / `power-cap-limit-summary.txt`
- `power-policy0-dynamic.csv` / `power-policy0-dynamic-summary.txt`
- `perf-active-limits.csv` / `perf-active-limits-summary.txt`
- `telemetry.csv` / `telemetry-summary.txt`

## 本机实验证据

### 对照基准

Cyberpunk 2077 2.31，6144×3456，Path Tracing，完整内置基准：

| 指标 | 旧曲线 | 2026-07-24 新曲线 |
|---|---:|---:|
| 平均 FPS | 9.9648 | 9.9682 |
| 平均 GPU 频率 | 2787.6 MHz | 2772.1 MHz |
| 最高 GPU 频率 | 2850 MHz | 2835 MHz |
| 平均电压 | 898.1 mV | 916.7 mV |
| 最高电压 | 905 mV | 935 mV |
| 平均板卡功耗 | 393.0 W | 409.0 W |
| 瞬时最高功耗 | 429.1 W | 446.9 W |
| `SW Power Cap` 状态位 | 92.2% 样本 Active | 100% 样本 Active |
| Xid | 无 | 无 |

原始记录：

- 旧曲线：`benchmark_logs/cp2077_6k_20260724_203146/`
- 新曲线：`benchmark_logs/cp2077_6k_20260724_204743/`

新曲线完整跑完，没有 Xid；高频段在加载/切换阶段短暂达到约 3022 MHz，证明配置确实被驱动接收。正式 PT 场景却主要停留在 910–925 mV 和约 2700–2835 MHz。

### 约 50 mV 窗口与实测高度吻合

正式场景平均电压约为 916.7 mV。

当前配置中，870–920 mV 各点为：

```text
870:2572  875:2647  885:2737  890:2791  895:2827
900:2858  910:2858  915:2863  920:2869
```

这九个点的算术平均值为 **2780.2 MHz**，实测平均频率为 **2772.1 MHz**。

这不是 NVIDIA 已公开确认的精确公式，但它与社区多张 Blackwell 卡得到的现象非常一致：运行时频率会受到当前工作电压以下约 50 mV 多个曲线点的共同影响，而不是只读取屏幕上当前电压对应的单点。

其他窗口：

```text
915 mV 向下 50 mV：平均 2737.2 MHz
920 mV 向下 50 mV：平均 2780.2 MHz
950 mV 向下 50 mV：平均 2876.8 MHz
975 mV 向下 50 mV：平均 2909.2 MHz
1000 mV 向下 50 mV：平均 2953.3 MHz
```

因此，写入 `950 mV -> 2900 MHz` 并不能保证实际负载运行 2900 MHz；其前方一段曲线也必须一起塑形。

## 为什么还有大量瓦数余量却不继续升频

600 W 是允许的板卡功耗上限，不是 GPU 必须追逐的功耗目标。GPU Boost/AVFS 仍会综合：

- 整段 V/F 曲线形状；
- 当前和相邻电压点；
- 负载类型及各功能域活动；
- 温度和漏电模型；
- 瞬时/内部功耗策略；
- 可靠性和固件策略限制；
- 用户设置的 offset、locked clocks 和 power cap。

默认状态约 470 W、约 2700 MHz，而自定义曲线约 409 W、约 2772 MHz，说明当前曲线已经实现了明显的效率提升。剩余的约 190 W 并不会自动转化为更高核心频率，因为运行时控制器并没有把“把板卡功耗填满”作为唯一目标。

## `SW_POWER_CAP` 不能按字面解释

NVIDIA NVML 对该状态的公开定义是：时钟已被优化，以确保不超过当前设置的功耗限制。它没有承诺该状态只会在传感器读数等于 600 W 时出现。

本机新基准还有一个内部不一致：

- 1824/1824 个 50 ms 样本均报告 `SW Power Cap: Active`；
- 但 `SW Power Capping` 计数器在约 97.5 秒场景内只增加约 15.842 秒。

另外，NVIDIA 开发者论坛已有 Blackwell 用户报告性能限制原因在实际限功耗时不显示、空闲时反而显示 Power；610 驱动反馈中仍有人把 Blackwell performance limiter reporting 列为未解决问题。

新的私有 RM 查询把这件事进一步分开了：

- NVML 的 `SW_POWER_CAP` 在 CP2077 中始终为 Active；
- `subdeviceCtrlCmdPerfGetActiveLimits` 返回的 237 个传统 PERF limit 始终全部 inactive；
- `PERF_LIMIT_PMU_DOM_GRP_1` 的动态目标却在约 2.5–3.0 GHz 之间持续变化。

所以 `SW_POWER_CAP` 在本机更接近“PMU 动态功耗优化闭环正在约束频率”的粗粒度提示，而不是“某个静态 PERF limit 已触发”，更不能据此断言板卡已经撞到 600 W。它可以在板卡总功耗只有约 407 W 时有效，因为 PMU 使用的可能是更短时间尺度、分域估计以及电流/可靠性模型，而不只是 NVML 展示的整卡平均瓦数。具体控制公式仍位于未公开的 PMU/RM 实现中。

本机已排除两个简单的软件因素：

- `nvidia-powerd.service`：disabled、inactive；
- NVML Power Smoothing：设备报告不支持。

## 各组件的职责

### LACT

- 保存并提交 V/F 曲线、频率 offset、locked clocks、显存 offset 和 power cap。
- 不负责根据每一帧负载实时计算电压。
- 曲线中的 `clockspeed` 是交给 NVIDIA 控制栈的目标/约束，不是直接写 VRM 的命令。

### Kernel-RM

- 接收用户态控制请求。
- 在启用 GSP-RM 的架构上，将许多 RM 控制操作路由到 GSP。
- 公开的 610.43.03 源码中可以看到 GSP-RM RPC、`KernelPerf`、`KernelPmu`、`KernelVolt` 以及 `ctrl2080clkavfs` 等接口骨架，但核心策略实现没有完整公开。

### GSP-RM

- NVIDIA 官方描述为把传统上由 CPU 驱动完成的 GPU 初始化和管理任务卸载到 GPU System Processor。
- 负责性能管理请求在 GPU 内部的接收、校验和协调，是当前 Blackwell V/F 控制链上的关键管理层。
- 不能仅凭现有公开资料断言“50 mV 窗口平均算法完全在 GSP 主线程中执行”。

### PERF / PMU / VOLT / AVFS

- PERF：性能状态、Boost 和性能限制策略。
- PMU：GPU 内部电源管理微控制器/固件体系，适合执行低延迟运行时控制。
- VOLT：电压轨和调压请求相关对象。
- AVFS：自适应电压频率缩放，结合频率、电压、温度、芯片特性和安全边界确定可用工作点。
- 这一层最接近“此刻到底给多少电压、跑哪个频率”的实际决策与执行。

### VBIOS

- 提供基础曲线、板卡/SKU 限制、功耗参数、温度参数和电压调节器配置。
- 是策略数据来源之一，不是实时 DVFS 调度线程。

本地同板族 ROM 的离线差分直接证明 XOC VBIOS 不只是更改界面显示的整卡功耗上限。ASUS Astral 普通 600 W ROM 与 2001 W XOC ROM 的 BIT `P` 表指针布局相同，但内容有这些变化：

- `POWER_BUDGET` 中多组 `600000 mW` 改为 `2001000 mW`；
- VBIOS 记录编号与运行时 policy 编号逐项对齐：policy 9 的总电流额定值从 `60000 mA` 提到 `5001000 mA`（实际上近似取消），policy 13 的 NVVDD 电流从 `480000 mA` 提到 `2000000 mA`，policy 14 的 MSVDD 电流从 `180000 mA` 提到 `1000000 mA`；
- policy 7 的类型专用区另有一项从 `60000` 改为 `120000`，第二版 XOC 又提到 `160000`；由于 610 的公开头文件和旧 MODS 类型表均尚未命名 Blackwell 新类型 `0x20`，暂不强行给该字段指定单位或 rail；
- `THERMAL POLICY` 表的第 0、1、4 条记录首字节由 `1` 变为 `0`，并伴随表头状态变化；这至少证明若干策略被停用，具体三条名称仍待解析 0x20 版记录格式；
- `FAN_COOLERS/FAN_MGMT` 的少量差异属于板卡风扇拓扑，不是功耗算法本身。

重新按 GB202 的混合指针基址规则检查后，上述“Voltage Rail 没有差异”的早期结论需要作废。BIT `P` 中的大表指针（例如 `VOLTAGE_MAP`、`POWER_BUDGET`、`OVERCLOCKING`）需加 PCI expansion gap，而 `P+0x68/0x6c/0x70` 的小指针直接相对 legacy-image base。按正确基址读取后得到：

- 普通 Astral 600 W 与 Astral 2001 W XOC 的 `VOLTAGE_MAP`、`VOLTAGE_DEVICE`、`VOLTAGE_POLICY` 以及完整 `FactoryOC/OVERCLOCKING` 表仍逐字节相同；该 FactoryOC 表实际为 `0x1b` bytes，由 7-byte 头、两条 Clocks 记录和两条 Vpstate 记录组成，不是早期按通用头部误截的 `0x11` bytes；
- 但 `VOLTAGE_RAIL` v0x30 的第 0 条记录有两个单字节索引变化：记录 `+0x0d` 由 `3` 改为 `6`，`+0x0f` 由 `4` 改为 `6`；两份 Astral 2001 W XOC（`Asus.RTX5090.32768.250327.rom` 与 `281814.rom`）都是 `6,6`；
- 对全部本地 ROM 的扫描表明，普通 575/600 W BIOS、MSI Lightning 800/1000 W 和 ASUS Matrix 800 W 都保留 `3,4`；GALAX 2001 W XOC 与 Astral 2001 W XOC 才是 `6,6`。因此“提高功耗上限”与“改变电压路由/失去常规 V/F 调节”是两项可分离的 VBIOS 改动，不能把所有 XOC BIOS 当成同一类。

这两个索引的 Blackwell 私有字段名称尚未在公开头文件中确认，但它们位于经确认的 `VOLTAGE_RAIL` 记录内，而且与 2001 W 固定高压 XOC 类群一一共现。结合实际使用报告中“Astral 2001 W XOC 强制约 1.15 V，软件电压滑块不生效”的行为，它们很可能把原本分立的运行时电压客户或限制路由到同一 XOC 策略。在字段语义或实机运行时行为得到验证前，不应再预期 `281814` 会保留现有可控 V/F 曲线，也不应把它作为日用 3 GHz 试验的首选。

本地 `281814.rom`（ASUS Astral 2001 W XOC #2）的 `FAN_COOLERS` 活动槽为 `00 01 ff ff`，与 Astral Black 的两路控制器拓扑一致；MSI Lightning 800/1000 W 则是 `00 ff ff ff`，ASUS Matrix 是 `00 01 02 ff`。`281814` 虽然风扇拓扑最近，却存在上述电压路由改动；Lightning/Matrix 的电压路由更接近普通 BIOS，却存在风扇控制器数量或板级拓扑不匹配。目前没有一份候选同时满足“Astral Black 两路风扇拓扑、保留普通 V/F 路由、高功耗上限”三个条件。

后续对 Lightning/Matrix 的同板档位差分进一步确认：Matrix 600→800 W 和 Lightning 800→1000 W 都不改动 `VOLTAGE_MAP/RAIL/DEVICE/POLICY`、`THERM_POLICY` 或基础 `PERFORMANCE` 表，只放宽功耗/电流额度并配套调整风扇参数。Lightning 800 W 与 Matrix 800 W 的整套 V/F 和完整 `FactoryOC Table` 甚至逐字节相同；两者将 Astral OC 的 factory clock delta 从 `45 MHz` 提到 `195 MHz`，并将对应 factory vPstate/Boost 记录从 `2580 MHz` 提到 `2730 MHz`。Matrix 800 W 保留 NVVDD/MSVDD 的 `480/180 A` 轨级额度，Lightning 800/1000 W 则放宽为 `720/240 A`。完整差分见 `LIGHTNING_MATRIX_VF_POWER_DIFF_20260725.md`。

现代 Blackwell 的只读 `Clock Domains Info` 查询进一步消除了一个关键歧义。当前 GSP 的 `0x20809019` 接口在 Astral OC 上同时返回 GPC 用户偏移范围 `-1000..+1000 MHz` 和独立的 factory delta `+45000 kHz`；因此出厂超频并不会从用户 `+1000 MHz` 配额中扣除。配套的只读 `0x2080901a` 还返回 459 个 GPC 枚举点、范围 `15..3450 MHz`，说明 3.2 GHz 确实存在于允许枚举的时钟表中，但这不是稳定性保证。结合离线 ROM 差分，Matrix/Lightning 的 `+195 MHz` 应同样作为独立 factory adjustment 叠加在基础元组上，而不是把手动范围缩成 `+805 MHz`。这也意味着在这类 BIOS 上原样套用已经很激进的 Astral LACT 曲线，目标频率可能整体更高，反而更容易触发游戏/XID；它不会凭空改善芯片所需电压。只读探针、字段位置和原始输出见 `LIGHTNING_MATRIX_VF_POWER_DIFF_20260725.md`。

所以运行时分工可以更精确地表述为：VBIOS 提供并签名策略参数、门槛和启用状态，GSP/PMU 在运行时读取这些数据并执行快速闭环。XOC BIOS 因而确实可能改变 `OVERVOLTAGE/RELIABILITY/THERM/PWR` 候选上限，但不会替换 PMU 控制算法本身。

### FSP / SEC2

- 负责固件安全启动、认证、装载或受保护操作。
- 对 GSP 能否启动、加载何种签名固件很重要。
- 没有证据表明它们在正常游戏运行中逐点选择 V/F 工作点。

### 旧 RM 的功耗策略覆盖开关，以及它对 610 的意义

旧 MODS/RM 中已经恢复出完整的 `RmPmgrPwrPolicyOverride` 注册项和执行分支，而不只是一个孤立字符串。枚举位为：

```text
1  RmPwrPolicyOverrideDisabled
2  RmPwrPolicyOverrideLimitsUnlimited
4  RmPwrPolicyOverrideRatedLimitMaximum
6  同时启用 2 和 4
```

其中位 2 会在构造功耗策略对象前把 VBIOS 给出的 policy minimum/maximum 改成 `0 / 0xffffffff`，并打印 `overriding VBIOS policy limits ... to be 'unlimited'`；位 4 会把 rated limit 改为 maximum。普通 `SetPowerCap` 路径仍会拒绝低于 minimum 或高于 maximum 的值，所以这个注册项的关键之处在于它先改了 RM 用来建对象的边界，而不是绕过每一次设置请求的检查。

Linux 公共模块允许 `NVreg_RegistryDwords` 中未被内核层识别的键继续传给 RM，本机当前也在用同一通道传递 `RMUseSwI2c=0x01`。但当前 610 GSP 内没有找到精确字符串 `RmPmgrPwrPolicyOverride`；只发现了语义更泛的 `RmPmgrOverride` 和 `RmPmgrPmuOverride`，现有交叉引用仅能证明它们参与 PMGR/PMU 初始化，不能证明它们继承了旧功耗策略覆盖语义。因此现阶段结论是：**旧 RM 确有直接解除 policy 上限的实现；当前 610 是否仍接受该键，必须通过一次驱动初始化实验判定，不能由字符串存在性代替。**

该实验不需要刷 VBIOS：在桌面切到核显且 NVIDIA 无持有进程时，用一次临时模块参数加载 `RmPmgrPwrPolicyOverride=0x2`，只读回策略 maximum 后恢复原参数即可。当前桌面仍在 5090 上，因此没有执行。

## 已知可行的两条调整路线

### 路线 A：继续使用完整 V/F 曲线

- 不只抬目标电压点。
- 同时调整目标点以下约 50–80 mV 的一段曲线。
- 尽量保持原始曲线形状，再在目标电压之后封顶。
- 对低电压点存在每点约 `+1000 MHz` 的驱动 offset 上限，因此 0.89–0.90 V 一带可能已经没有继续上抬的空间。
- 若目标是实际 2900 MHz，更合理的工作区间可能是 0.95–0.975 V，而不是继续强推 0.90 V。

### 路线 B：默认曲线 + 正 offset + locked maximum clock

LACT 已支持通过 `GpcClkVfOffset` 与 locked clocks 间接降压：正 offset 让目标频率对应到默认曲线上的更低电压，再用最高频率锁避免轻载瞬间冲到不稳定频率。

本地已有旧配置证据：`/etc/lact/config.yaml.bak.pre-vf`

```yaml
min_core_clock: 2660
max_core_clock: 2900
gpu_clock_offsets:
  8: 1000
```

其中 `min_core_clock: 2660` 会造成不必要的高空闲频率。下一次更合理的测试形态是：

```yaml
min_core_clock: 180
max_core_clock: 2850   # 先做稳定基线，再测试 2900
gpu_clock_offsets:
  8: 1000
```

同时移除整张自定义 `gpu_vf_curve`。这条路线最接近“固定最高频率，让驱动选择能达到该频率的最低电压”。

## 2026-07-25：GPC 到 XBAR 的传播关系已由本机运行时闭环

当前 R610 的 Clock Propagation Topology 只读接口已恢复并实际调用成功。驱动处于自动 topology
选择（control ID `0xff`），当前活动 top ID 为 `7`；它启用关系 mask `0x000003ff`。其中活动关系 0
明确为 `GPC2CLK(api 0x1) -> XBARCLK(api 0x2)` 的双向 type-3 关系，控制值为 U16.16：

```text
ratio_raw = 0x0000e660
ratio     = 58976 / 65536
          = 0.89990234375
```

PMU 内部求值器 `0x202a817e` 会把 `PSTATE/GPC2CLK/XBARCLK` 三元组初始化为 `UINT32_MAX`，随后
只直接写入 PSTATE 与 GPC2CLK，XBARCLK 保持不受该求值器约束。当前活动传播关系再把 GPC 候选映射
到约 0.9 倍的 XBAR 基线，随后与共享电压关系、时钟网格及热/功耗/客户端限制合并。这修正了此前
“2X 功耗公式同时独立搜索 DG0 和 DG1”这一过强解释：对外状态中的 DG1 确实是 XBAR 候选，但它
主要由下游 clock-propagation topology 从 GPC 派生。

数值上，CP2077 6K PT 现有 565 个样本中有 427 个满足
`|DG1 - 0.89990234375*DG0| <= 10 MHz`，494 个在 30 MHz 内；FurMark Vulkan 的 335 个模型频率对
中有 299 个在 10 MHz 内。正残差最高约 49.5 MHz，符合“比例传播是基线，最终点还受共享 rail 与
离散档位影响”，但 type-5 voltage-relationship evaluator 的精确合并公式仍待还原。

完整 ABI、拓扑表和 14 条关系见 `BLACKWELL_CONTROL_LOGIC_EXTRACTION_20260725.md` 第十七节。

## 2026-07-25：直接读回当前 Client V/F 表

当前 R610 的只读 `CLIENT_CLK_VF_POINTS` INFO/STATUS/CONTROL 方法已经恢复并在本机调用成功。它们
能同时给出每个可编辑电压点的运行时频率、base tuple 和实际控制 offset；这比只看 LACT YAML 更接近
固件真正采用的曲线。

当前配置与运行时回读的代表性差异为：

```text
0.910 V: config 2858 -> runtime 2857 MHz
0.950 V: config 2900 -> runtime 2902 MHz
1.000 V: config 3000 -> runtime 3007 MHz
1.015 V: config 3030 -> runtime 3037 MHz
1.045 V: config 3030 -> runtime 3045 MHz
1.235 V: config 3030 -> runtime 3052 MHz
```

LACT 精确版本源码会先读取当时的 `vf_tuple_base`，再写入
`configured_frequency - base_frequency` 作为每点 offset；提交整条曲线后固件会按时钟网格与曲线约束
生成新的运行时点。当前 127 个 GPC 点中，`runtime - current_base - control_offset` 只有 23 个非零，
范围 `-13..+8 MHz`，说明控制 offset 与最终点基本闭环；但由于 base tuple 也会在整曲线重建后改变，
YAML 目标值与最终点仍可相差 15--22 MHz。按 LACT 写入公式反推，点 95 的提交前 base 是
2925 MHz、当前为 2940 MHz；点 125 的提交前 base 是 3240 MHz、当前为 3262 MHz。连续 12 秒
只读采样未见继续漂移。`apply_settings_timer: 5` 只是变更确认/回滚窗口，并不周期重写设置。

这也修正了此前“0.91 V 对应 2858/2835 到底哪个才是真的”的口径：配置目标、当前 V/F 表点和负载
下持续实频必须分开。此刻当前表中 0.91 V 的点是 2857 MHz；游戏中仍可能被 2X 功耗策略、传播拓扑、
热限制和 AVFS 选到更低频率。

另外，本机当前曲线不是从干净默认表直接生成。按 LACT 的精确写入公式由 control offset 反推写入前
base 后，点 79--126 中有 27 点与上一版自定义曲线逐 MHz 相同，点 96 以上几乎整段一致。LACT 的
controller 重载路径会忽略旧 controller 的 `reset_clocks()` 错误，而新 controller 又以
`vf_curve_written=false` 开始；如果旧曲线未被成功清零，新 controller 会在残留曲线上重新计算 offset。
06:50 的日志正好记录了 DRM event 后 controller 重建和配置重应用。所以下一次严谨稳定性测试前，应
在 5090 不承载桌面时先清零并读回全部 per-point offset，再且仅再应用一次曲线。

## 当前置信度

| 结论 | 置信度 |
|---|---|
| LACT 只写固定电压点的频率偏移，不直接写 VRM 电压 | 高；已核对精确版本源码 |
| `0x2080d02d` 曲线设置命令由 GSP-RM 的特权 Clock/VF 方法接收 | 高；已在用户态调用桩、Kernel-RM 路由和 GSP 方法表三处交叉确认 |
| MODS 的电压轨偏移最终通过 `0x2080d01c` 进入特权 GSP-RM 方法 | 高；原生包装层、PERF 实现和 610 GSP 方法表已交叉确认 |
| Clock Domain 数据会初始化到 PMU，并且存在显式的 FREQ_TO_VOLT / VOLT_TO_FREQ PMU RPC | 高；MODS 内置 RM 实现中的发送路径与错误文本一致 |
| RM 支持加密的 PMU-RISCV 量产/调试镜像，并有单独的未加密路径 | 高；MODS ELF 中三条日志的交叉引用落在同一装载函数的互斥分支 |
| 当前零售 5090 一定加载了加密量产 PMU 镜像 | 中高；符合量产安全状态和 RM 分支设计，但本机日志未直接打印所选类型 |
| CPU Kernel-RM 对该命令主要负责序列化和 RPC 转发 | 高 |
| GPU PMU 参与 Blackwell 的快速功耗策略闭环 | 高；本机固件/源码结构和 NVIDIA Blackwell 官方文档一致 |
| `0x43` 是 `PERF_LIMIT_PMU_DOM_GRP_1`，其查询返回当前动态功耗限频目标 | 高；MODS 调用语义、NVIDIA 二进制 ID 映射、610 GSP 方法表及本机运行时读数四处一致 |
| 策略 0 是 `WORKLOAD_COMBINED_2X`（`0x14`），它的 `DG0` 产生 `0x43` 动态目标 | 高；显式类型表、当前 GSP 的 `DIE_2X=0x13` 断言、12 次顺序成对读取及完整 CP2077 遥测相互一致 |
| `DG0` 是 `GPC2CLK`，`DG1` 是 `XBAR`；后者取 `0xe9 THERM_POLICY_XBAR` 与 `0xea PWR_POLICY_XBAR` 中较低者 | 高；MODS 的逐字打印、610 自身稀疏 ID 表以及交错成对读取一致 |
| 2X 求值器只直接产生 PSTATE/GPC；活动 topology 再以 `0xE660/65536` 把 GPC 传播到 XBAR 基线 | 高；PMU 逐字段写入数据流、本机 topology/status/control 和现有负载日志数值闭环 |
| XOC VBIOS 只改整卡瓦数，不会改变 PMU 策略输入 | 低；普通/XOC 同板族 ROM 还改变轨级数值和 THERMAL POLICY 记录启用状态 |
| CP2077 的降频来自普通静态 PERF limit | 低；237 个 limit 在整轮 1857 次查询中均无 active 项 |
| `0x43` 的每个瞬时读数就是最终实际频率硬上限 | 低；异步逐点相关性很弱，平滑后才呈现趋势相关 |
| LACT YAML 中每点 MHz 就是固件最终曲线点 | 低；当前 INFO/STATUS/CONTROL 回读证明可相差至 22 MHz |
| 当前 V/F 表的 runtime/base/control offset 可直接只读并逐点闭环 | 高；R610 方法表、探针、LACT 源码和 snapshot 一致 |
| 本机当前曲线从干净默认 base 单次生成 | 低；反推 pre-write base 与上一自定义曲线高段 27 点精确一致 |
| 最终实时 V/F 决策属于 GPU 内 PERF/PMU/VOLT/AVFS 栈 | 高 |
| VBIOS 主要提供表和限制而非实时调速 | 高 |
| SEC2/FSP 不是正常运行时 V/F 调速器 | 高 |
| Blackwell 会参考目标点下方约 50 mV 曲线窗口 | 中高：多卡实测和本机数据吻合，但无 NVIDIA 公开算法说明 |
| `SW_POWER_CAP` 在本机等价于真实撞 600 W | 低；现有证据反对这种解释 |
| 约 50 mV 计算精确发生在 GSP-RM 还是 PMU 固件中的某个具体函数 | 未确定 |

## 参考资料

- NVIDIA Linux Driver 610.43.03 README — GSP Firmware：<https://download.nvidia.com/XFree86/Linux-x86_64/610.43.03/README/gsp.html>
- NVIDIA DGX B200 User Guide — GPU PMU 选择功耗限制策略：<https://docs.nvidia.com/dgx/dgxb200-user-guide/power-capping.html>
- NVIDIA open-gpu-kernel-modules 610.43.03：<https://github.com/NVIDIA/open-gpu-kernel-modules/tree/610.43.03>
- NVIDIA open-gpu-kernel-modules discussion — RM/GSP-RM 定义：<https://github.com/NVIDIA/open-gpu-kernel-modules/discussions/157>
- LACT 精确版本的 NVIDIA 控制实现：<https://github.com/ilya-zlobintsev/LACT/blob/ab83c4c28189d5fbf55e995029162a453d02f733/lact-daemon/src/server/gpu_controller/nvidia.rs>
- LACT 精确版本的私有 NVAPI 定义：<https://github.com/ilya-zlobintsev/LACT/blob/ab83c4c28189d5fbf55e995029162a453d02f733/lact-daemon/src/server/gpu_controller/nvidia/nvapi.rs>
- NVIDIA NVML — Clocks Event Reasons：<https://docs.nvidia.com/deploy/nvml-api/group__nvmlClocksEventReasons.html>
- NVIDIA Developer Forum — Blackwell performance limiter reporting：<https://forums.developer.nvidia.com/t/performance-limiters-are-broken-on-blackwell/355113>
- NVIDIA 610 driver feedback：<https://forums.developer.nvidia.com/t/610-release-feedback-discussion/371356/12>
- LACT issue #486 — LockedClocks + GpcClkVfOffset：<https://github.com/ilya-zlobintsev/LACT/issues/486>
- RTX 5090 曲线窗口实测：<https://www.reddit.com/r/nvidia/comments/1k56gmn/undervolting_5090_increasing_power_limit/>
- RTX 5090 FE 整段曲线调整方法：<https://www.reddit.com/r/nvidia/comments/1jaz2yq/5090fe_undervolt_guide_better_than_stock_at_450w/>
- ASUS Astral 5090 V/F 调整案例：<https://rog-forum.asus.com/t5/push-the-limits/power-meets-precision-undervolting-your-rog-astral-oc-rtx-5090/ba-p/1093066>
