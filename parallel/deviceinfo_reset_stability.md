# GB202 PTOP DeviceInfo2 / FUSE base：floorsweep 与 reset 稳定性审计

日期：2026-07-21
状态：完成；纯离线、只读、固定小窗口

## 结论先行

这轮需要把三个很容易混在一起的问题分开：

1. **PTOP DeviceInfo2 硬件寄存器在 reset 边沿是否会被内部逻辑重新装载；**
2. **重新装载后，整张设备枚举表的逻辑内容是否可能因 floorsweep 改变；**
3. **即使别的设备项变化，FUSE/class `0x10` instance 0 的
   `devicePriBase` 是否也会变化。**

当前静态证据支持的最窄答案是：

- **FACT：** MODS 的 cache 是整张 PTOP DeviceInfo2 设备清单的 cache，不是
  FUSE 专用 cache。`0xdd2520` 一次性清空全部 56 个 class vector；其唯一已见
  direct caller 位于成功 floorsweep Apply 主线 `0x1095ffa`，并处于可选
  post-FS reset **之前**。
- **INFERENCE（强）：** 这个 invalidation 是通用拓扑维护。floorsweep 可以改变
  某些 engine/class 的存在、实例数或相关拓扑字段，MODS 因而保守地丢弃整张
  cache；它不表示表中的每一种设备都会变化，更不表示 FUSE aperture 会搬家。
- **FACT：** normal `SetSwFuses` 成功后的 hot/boot/fuse/base
  coupling-selected reset 不调用 `0xdd2520`，保留同一个 host
  `GpuSubdevice` 对象及其 built cache。四种 reset 在可见 host 代码里都不是
  DeviceInfo2 refresh 原语。
- **FACT（NVIDIA 610 公开源码）：** GB202 的
  `gpuGetPrimaryFuseBaseAddr_HAL` 明确绑定到
  `gpuGetPrimaryFuseBaseAddr_GH100`；后者不读取表或状态，只返回编译期常量
  `NV_FUSE0_PRI_BASE = 0x820000`。MODS 的 class-`0x10` instance-0 fixed
  fallback 也恰为 `0x820000`。
- **INFERENCE（很强）：** 对正常、非畸形 GB202，L2/FBP/SM floorsweep 以及
  hot/boot/fuse/base reset 都不应改变 FUSE instance-0 的逻辑 PRI base；即使
  DeviceInfo2 行在 reset 内部被重新生成，正常结果仍应是 `0x820000`。
- **UNKNOWN：** Blackwell 公开头没有给出 DeviceInfo2 行相对四种 MODS reset
  的 retention/reload 合同；本轮也没有本卡的 reset 前后表 capture。因此不能把
  “硬件寄存器位从不重载”或“class-`0x10` 行在所有瞬间绝对不可改变”升级成
  FACT。

换成人话：**floorsweep 后扔掉整张电话簿，是因为电话簿里有会被裁掉的各种
engine；不等于 NVIDIA 会把“FUSE 总机”的门牌号也换掉。** 目前所有独立地址
来源都指向 `0x820000`，没有一条证据显示 L2 解锁会让它迁移。

## 范围与安全边界

本轮材料限于：

- `mods_audit/static/extracted_inner/mods`，SHA-256
  `c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf`；
- 已知函数的固定小窗口：`0xdec350`、`0xdd2230`、`0xdd2520`、
  `0xdeda50`、`0x1095e50`、`0x1252200`；
- 一次流式、低内存、只识别 x86-64 `CALL rel32` 与 exact pointer 的目标扫描；
- `/usr/src/nvidia-610.43.03` 的 NVIDIA 公开源码与 published headers；
- 项目已有的 cache、reset 与 class identity 报告。

没有运行 MODS，没有打开 GPU 或设备节点，没有访问 BAR/MMIO、PCI config、
debugfs 或 ioctl，没有 reset/rebind/reboot，没有固件交互，也没有 whole-binary
反汇编、Ghidra 导入或大内存分析。

下文使用：

- **FACT**：当前 ELF 固定指令窗口或 NVIDIA 610 公开源码直接支持；
- **INFERENCE**：多项事实共同支持，但没有本卡 runtime capture；
- **UNKNOWN**：现有静态材料无法决定。

## 1. DeviceInfo2 是整机设备枚举，不是 FUSE 特殊映射

### 1.1 FACT：builder 每次解析 PTOP 硬件行的完整字段

GB202 vtable 的 DeviceInfo2 builder `0xdec350` 读取：

```text
PTOP DeviceInfo config：relative +0x4fc
PTOP DeviceInfo2 rows： relative +0x800 + 4*i
```

它把 chained rows 解成 `0x3c` 字节 record，至少包含：

```text
type/class
instanceId
faultId
resetId
devicePriBase
isEngine
runlist-engine ID
runlistPriBase
group / local-instance fields
```

公开 610 的 `blackwell/gb100/dev_top.h:27-51` 发布相同的 PTOP 地址与字段；
`ctrl2080internal.h:745-773` 也明确把 control 描述为在 physical side 解析
`DEVICE_INFO2_TABLE` 后返回给 kernel。

因此这张表的语义是“芯片有哪些可寻址设备/engine 及其拓扑属性”，不是一张只为
NewFuse writer 准备的跳转表。

### 1.2 FACT：cache 覆盖 56 个 class，失效也是全表失效

`GpuSubdevice` 拥有从 `+0x158` 到 `+0x697` 的 56 个、每个 24 字节的
`std::vector` 风格容器，`+0x698` 是 lazy-built flag。

`0xdd2520` 的循环边界为：

```text
start = this + 0x160       # first vector.end
stop  = this + 0x6a0
step  = 0x18
(0x6a0 - 0x160) / 0x18 = 56
```

每轮把 `vector.end` 恢复为 `vector.begin`，最后清 `this+0x698`。它没有
class 参数，也没有只清 class `0x10` 的分支。

### 1.3 FACT：同一 cache 还服务普通 engine class

对 `0xdeda50` 的 direct calls 可见 class/type `0x13`、`1`、`4`、`3` 和
fuse resolver 使用的 `0x10`。邻近输出字符串包括：

```text
LCE%d=0x%08x
NVDEC%d=0x%08x
NVENC%d=0x%08x
OFA%d=0x%08x
NVJPG%d=0x%08x
```

所以 floorsweep 后清掉这份 cache，首先应理解为对 engine/device inventory 的
通用维护，不能倒推出 FUSE base 本身发生过变化。

## 2. floorsweep invalidation 的精确位置和含义

### 2.1 FACT：唯一已见 direct caller 是 FS Apply

流式目标扫描得到：

```text
CALL source=0x1095ffa target=0xdd2520
```

没有第二个 `CALL rel32` 命中，也没有 exact 32/64-bit static pointer 命中
`0xdd2520`。这不排除理论上的运行时计算间接调用，但当前 ELF 没有相应证据。

`0x1095ffa` 位于 generic successful FS Apply 流程：

```text
FSP task 2 / subobject 1 完成
  -> pending host floorsweep apply（如有）
  -> post hook / bookkeeping
  -> 标记 FS initialized
  -> 0x1095ffa -> 0xdd2520
  -> later work
  -> optional post-FS reset
```

因此 invalidation 在控制流上属于 **floorsweep Apply 的成功提交尾部**，不是
reset dispatcher 的共同尾部。

### 2.2 INFERENCE：为什么要全表清，而不是只清某几个 class

DeviceInfo2 同时编码 device presence、instance、fault/reset ID、PRI base 与
runlist 信息。MODS 的 floorsweep 框架也不是只处理 L2；其公开 JS 参数包括
GPC、TPC、SM、FB，以及通用 `-floorsweep` 描述。

最小且自洽的解释是：成功 FS 可能使一部分枚举项或实例拓扑失效，MODS 没有维护
“哪一项依赖哪个 FS unit”的精细依赖图，而是廉价地丢掉 56 类全表 cache，让下次
查询重新解析硬件。

这属于 **cache coherence policy**，不是“每个 cached dword 都已改变”的证明。
例如禁用一个 video engine 可以影响 NVDEC/NVENC 类实例，却没有理由改变 FUSE
aperture。

### 2.3 UNKNOWN：哪些 GB202 FS unit 真会改变 PTOP 行

当前静态材料没有给出一张“FS unit -> DeviceInfo2 row mutation”规范，也没有本卡
应用以下不同 FS 配置前后的表差分。因此仍未知：

- 仅 L2/LTS mask 改变时，DeviceInfo2 是否连一行都不变；
- engine-level floorsweep 是删除 row、置 invalid row，还是只让下游软件过滤；
- FSP task 2、reset sequencer 或 PTOP 自身中的哪一层负责重新形成表；
- invalidation 是因为某代确实改变表，还是跨多代共用框架的保守动作。

可以说“MODS 认为 FS 后值得重新发现拓扑”，不能说“已证明 L2 FS 会改写
class-`0x10` row”。

## 3. class `0x10` / FUSE instance 0 的地址为什么应当稳定

### 3.1 FACT：三个独立软件来源都给出 `0x820000`

第一，MODS GB202 domain-5 resolver 对普通 accessor 固定请求：

```text
internal class = 0x10
instance       = 0
selector       = 0x10ef4000
```

若 class `0x10` vector 为空，selector 的 instance-0 row 给出：

```text
0x00820000
```

第二，`parallel/deviceinfo_class10_identity.md` 已机械恢复 GB202 映射：

```text
PTOP raw type 0x22 -> MODS internal class 0x10
```

结合调用者、domain 5 与 selector，这个 class 的语义是 FUSE。

第三，NVIDIA 610 generated HAL 对 GB202 的绑定是公开 FACT：

（完整的公开 caller 枚举与 HAL 交叉核对另见
`parallel/public_fusebase_callers.md`；此处只取与 reset/base 稳定性直接有关的
绑定和返回值。）

```text
g_gpu_nvoc.c:2723-2727
ChipHal ... GB202 ...
    pThis->__gpuGetPrimaryFuseBaseAddr__ =
        &gpuGetPrimaryFuseBaseAddr_GH100;
```

该实现位于 `kern_gpu_gh100.c:647-653`，函数体只有：

```c
return NV_FUSE0_PRI_BASE;
```

而 GH100 与 GB100 published `hwproject.h` 都把该常量定义为 `0x820000`；
GB202 的 generated binding 明确复用这个实现。函数没有读取 fuse、DeviceInfo2、
reset 状态、SKU、floorsweep mask 或 VBIOS。

因此 **NVIDIA 610 的正常 GB202 host API 把 primary FUSE base 当成架构常量**，
而不是 runtime-remappable topology 值。

### 3.2 INFERENCE（很强）：正常 DeviceInfo2 FUSE row 必须与固定 API 相容

MODS 若看见正常 class-`0x10` instance-0 row，会用其中的 `devicePriBase`；若
vector 为空，会回退 `0x820000`。公开 RM 的关键 Blackwell 代码则通过固定 getter
访问 FUSE。

若同一正常 GB202 配置把 DeviceInfo2 FUSE row 合法地改到另一个地址，而官方
primary getter 仍永久返回 `0x820000`，两套 NVIDIA 软件会对同一个 FUSE block
产生冲突。当前没有任何 relocation/alias 协议能解释这种分歧。

所以最合理的产品不变量是：

```text
normal class-0x10 instance-0 row, if present:
    devicePriBase == 0x820000

class-0x10 row absent:
    MODS fixed fallback == 0x820000
```

这仍标为强 INFERENCE 而不是本卡 runtime FACT，因为我们没有读取本卡 live row，
而公开源码也没有发布 raw type `0x22` 的完整 producer 实现。

### 3.3 INFERENCE：L2 floorsweep 不构成 FUSE aperture relocation

L2/LTS/FBP floorsweep 改的是存储层资源有效性。FUSE block 是全局控制基础设施，
它的地址由 PTOP/PRI 地址图决定；普通 GB202 accessor 也只有 instance 0。

当前没有：

- “L2 mask 选择另一个 FUSE instance”的 selector；
- “disabled FBP 数量 -> FUSE base”的计算；
- reset 后重写 accessor instance 的代码；
- `0x820000 -> 0xbf0000` 的运行时切换路径；
- FUSE base relocation/alias 的公开合同。

因此仅为了开启更多 LTS，预期 FUSE base 仍是 `0x820000`。真正需要重新判断的
是 raw shadow 是否被 reset/firmware 接纳，不是 FUSE aperture 是否搬家。

## 4. normal reset 与 cache/table 的关系

### 4.1 FACT：四类 reset 在可见 host 链中都不刷新 MODS cache

`NewFuse.SetSwFuses` 的成功尾根据现有 coupling 选择：

```text
base > fuse > boot > hot
```

但无论选择哪一类，均经同一 `0xdff7b0 -> 0xdfe3d0` state
unload/reset/state-load dispatcher。`parallel/postreset_deviceinfo_cache_lifetime.md`
已证明：

- reset 前后使用同一个 `GpuSubdevice*`；
- dispatcher 不调用 constructor/destructor；
- 不调用 `0xdd2520`；
- 不写 `+0x158..+0x698`；
- reset 返回后继续解引用同一对象。

所以 normal reset 后，MODS resolver 默认仍使用 pre-reset DeviceInfo2 snapshot。
这不是说硬件表一定没被内部重载，而是说 **MODS 没有把 reset 本身当成需要重新
发现地址图的事件**。

### 4.2 FACT / INFERENCE：NVIDIA 610 的公开 cache lifetime 也假定表稳定

公开 610 的 FWCLIENT path 在
`gpu_gspclient.c:225-284` 首次请求 physical side DeviceInfo table 并复制到
`OBJGPU::pDeviceInfoTable`。若指针非空，函数在 `:235-236` 直接返回，不会重查。

对公开源码中 `pDeviceInfoTable` 的写入/释放做定向搜索得到：

- allocation/copy 只在 FWCLIENT/VF constructors；
- free、置 null 与 count 清零只在完整 `gpuDestruct_IMPL`
  (`gpu.c:1582-1584`)；
- `gpuStateUnload_IMPL`、`gpuStateLoad_IMPL`、甚至独立
  `gpuStateDestroy_IMPL` 都不清该指针。

这是另一个代码库，不能替代 MODS ELF 的机器码证明；但它形成一致的公开结构：
**DeviceInfo table 被当成 GPU object lifetime 级静态数据，而不是每次 state reset
都要刷新的瞬态状态。**

### 4.3 reset 分类表

| 事件 | MODS cache 行为 | 硬件表逻辑内容 | FUSE instance-0 base |
|---|---|---|---|
| floorsweep Apply，无 reset | 成功主线显式 invalidate；下次 query 重建 | 某些 device/engine 项可能改变；具体 unit 未闭合 | 强预期仍为 `0x820000` |
| hot reset | 不 invalidate；同一 host snapshot | register 是否 reload UNKNOWN；无独立拓扑变化证据 | 公开 getter/回退均固定 `0x820000` |
| boot reset | 不因 reset 本身 invalidate | 可能重新初始化硬件表，但同配置应得到同一逻辑地址图 | 强预期 `0x820000` |
| fuse reset，无新 physical fuse | 不 invalidate | 是否重装 UNKNOWN；没有理由改逻辑表 | 强预期 `0x820000` |
| fuse reset，physical fuses 真被改变 | 不因 reset 本身 invalidate；若另有 FS Apply 才清 | engine/topology membership 理论上可随新 fuse 改变 | FUSE block 自身仍强预期 `0x820000` |
| base reset | 不 invalidate；同一 host object | 最强 reset 的 retention/rebuild 细节 UNKNOWN | 无 relocation 证据；强预期 `0x820000` |

表中的“可能重新初始化/重装”只表示 bit-level implementation 未公开，不表示
post-reset logical value 会不同。

## 5. 为什么不能把稳定性写成绝对 FACT

### 5.1 Blackwell 公开寄存器头没有给四种 reset 的合同

`blackwell/gb100/dev_top.h` 把：

```text
NV_PTOP_DEVICE_INFO_CFG  0x224fc
NV_PTOP_DEVICE_INFO2(i)  0x22800 + 4*i
```

发布为 `RW` register/array，并发布 config/version/row 字段；它没有说明这些位
分别在 MODS 的 hot/boot/fuse/base reset 下是 retained、cleared 还是由硬件重新
生成。相比之下，仅看到 `RW` 也不能证明普通 host 有权限随意写表；PLM/firmware
控制仍未公开。

因此静态证据能证明的是软件如何消费和 cache，不能证明硅级触发器在每个 reset
边沿的波形。

### 5.2 hidden producer 仍缺失

610 公开控制说明说 physical side 解析表，但相应 physical producer body 没有
公开。我们因此不知道：

- PTOP 是组合地反映 fuse/strap，还是由 boot firmware 写入 SRAM-like rows；
- task 2 是否能直接影响表；
- reset 后何时表重新有效；
- 是否存在制造/仿真专用的 row override。

这些 UNKNOWN 使“绝不可能改变任何一位”过强，但并不削弱正常 FUSE base 的
`0x820000` 多源一致性。

### 5.3 malformed table 不是合法 relocation

既有 `parallel/deviceinfo_instance_nomatch.md` 已证明：class `0x10` 非空但缺少
instance 0 时，MODS 不 fail closed，而会越界取 `vector.end()+0x18` 当 base。

因此理论上可以看到一个非 `0x820000` 结果，但那是 malformed cache/table 导致的
不安全行为，不是“合法 reset 后 FUSE 搬家”。任何未来离线验证器仍应要求：

```text
class 0x10 empty
    -> fixed fallback 0x820000

class 0x10 nonempty
    -> instance 0 must exist
    -> devicePriBase must equal expected primary FUSE base 0x820000
```

这是一条安全不变量，不是建议进行 live probing。

## 6. 对 L2 解锁研究的直接含义

1. **地址不再是当前最大未知。** domain-relative key 仍是
   `0x34e0 + 4*FBP`；对正常 GB202，runtime class-`0x10` route 与 fixed
   fallback 都应落到 `0x820000`。
2. **FS invalidator 不能用来证明 FUSE base 可改。** 它是全表 cache coherence，
   主要保护可能变化的 engine/device inventory。
3. **normal SetSwFuses reset 不会自动换一张 base map。** 同一 host cache 跨 reset
   保留；而公开固定 getter进一步说明 primary FUSE base 本来就不应依赖 reset。
4. **真正未闭合的仍是采纳链。** raw shadow 写入后，GFW/FSP/hardware 如何在
   reset 上形成 effective LTS mask、权限何时关闭、坏 slice 如何安全验证，均不由
   DeviceInfo2 base 稳定性回答。
5. **即使未来构造安全离线计划，也要验证表形状而不信任 MODS no-match 行为。**
   class 非空但 instance 0 缺失必须拒绝，不能照搬其越界读取。

## FACT / INFERENCE / UNKNOWN 汇总

| 问题 | 结论 | 等级 |
|---|---|---|
| DeviceInfo2 是否是全设备清单 | 是；56 class，含 engine/PRI/reset/runlist 字段 | **FACT** |
| `0xdd2520` 是否只清 FUSE | 否；无 class 参数，清全部 vectors | **FACT** |
| 已见 invalidator caller | 仅成功 FS Apply 的 `0x1095ffa` direct call | **FACT / bounded negative** |
| invalidation 是否发生在可选 post-FS reset 前 | 是 | **FACT** |
| invalidation 是否说明所有 class 都变化 | 否 | **FACT（逻辑）** |
| invalidation 的最合理目的 | 通用 topology/cache coherence | **INFERENCE（强）** |
| normal hot/boot/fuse/base reset 是否清 MODS cache | 已见路径均不清；同一 object 存活 | **FACT（visible host path）** |
| GB202 primary FUSE getter | 绑定 literal-return GH100 implementation | **FACT** |
| 公开 primary FUSE base | `0x820000` | **FACT** |
| MODS instance-0 fallback | `0x820000` | **FACT** |
| 合法 class-`0x10` row 是否应同为 `0x820000` | 是 | **INFERENCE（很强）** |
| L2 floorsweep 是否会迁移 FUSE aperture | 无证据；强预期不会 | **INFERENCE（很强）** |
| DeviceInfo2 bits 是否在各 reset 物理 retain/reload | 无公开 reset-domain 合同 | **UNKNOWN** |
| 本卡 live class-`0x10` row | 未读 | **UNKNOWN** |

## 最小可引用结论

> MODS 570.151 的 `0xdd2520` 清空 `GpuSubdevice` 内全部 56 个 PTOP
> DeviceInfo2 class vectors；唯一已见 direct caller 是成功 floorsweep Apply 的
> `0x1095ffa`，位置在可选 post-FS reset 之前。这个动作最合理地解释为对通用
> device/engine topology 的保守 cache coherence，并不证明 FUSE row 变化。
> normal hot/boot/fuse/base reset 保留同一 `GpuSubdevice` 与 built cache，不把
> reset 当作 DeviceInfo2 refresh。NVIDIA 610 对 GB202 的
> `gpuGetPrimaryFuseBaseAddr_HAL` 又明确绑定到只返回常量 `0x820000` 的实现，MODS
> class-`0x10` instance-0 fallback 也同为 `0x820000`。因此正常 GB202 即使在
> floorsweep/reset 中重新形成整张 DeviceInfo2 表，FUSE instance-0 的逻辑
> `devicePriBase` 仍应保持 `0x820000`；未公开的只是硬件表位如何 reload，以及本卡
> live row 的实际 capture，而不是已经发现了一个合法 FUSE relocation 机制。

## 复现记录

主要离线检查：

```text
objdump -d --start-address=0xdd2520  --stop-address=0xdd2570  mods
objdump -d --start-address=0xdeda50  --stop-address=0xdedbe0  mods
objdump -d --start-address=0x1095d80 --stop-address=0x10961f0  mods
objdump -d --start-address=0xdec350  --stop-address=0xdec940  mods

ulimit -v 196608
python3 parallel/mods_x86_direct_xrefs.py \
    0xdd2520 0xdeda50 0xdd2230

rg -n 'pDeviceInfoTable|gpuConstructDeviceInfoTable' \
    /usr/src/nvidia-610.43.03/src/nvidia

rg -n 'gpuGetPrimaryFuseBaseAddr|NV_FUSE0_PRI_BASE' \
    /usr/src/nvidia-610.43.03/src/nvidia \
    /usr/src/nvidia-610.43.03/src/common/inc/swref/published
```

其中 `mods` 缩写为本报告开头给出的固定 ELF 路径。所有命令只读取本地文件。
