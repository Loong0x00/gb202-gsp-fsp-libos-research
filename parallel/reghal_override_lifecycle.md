# MODS 570.151 `GpuSubdevice+0x6c0` RegHal override 生命周期

## 结论先行

`GB202GpuSubdevice` 的 RegHal getter `0x0db40a0` 并不是在普通物理卡上总会
返回某个隐藏 firmware backend。它做的是：

```text
if (GpuSubdevice+0x6c0 != NULL)
    return GpuSubdevice+0x6c0;
else
    return &GpuSubdevice+0x90;     // 内嵌普通 RegHal
```

本轮闭合出的 `+0x6c0` 生命周期是：

1. **FACT：** `GpuSubdevice` 构造时将它清零；
2. **FACT：** 只有 MIG/SMC partition 枚举成功、选定 partition 和 SMC/GR
   engine 后，`0x0dee3e0` 才构造一个 RTTI 名为 `SmcRegHal` 的对象并写入；
3. **FACT：** 重复成功初始化会先换入新对象，再虚析构旧对象；
4. **FACT：** `GpuSubdevice` 析构时若非空就虚析构它；
5. **FACT：** “RM 不支持 MIG”或“没有有效 partition”的跳过路径不写也不清
   `+0x6c0`。首次初始化时它因此保持构造值 `NULL`；若对象不重建却在此前已有
   SMC backend，跳过路径是否可能被再次调用是 **UNKNOWN**；
6. **强 INFERENCE：** 普通、未 partition 的物理 GB202/RTX 5090 正常保持
   `NULL`，getter 返回内嵌普通 RegHal。项目保存的 RTX 5090 状态也显示 MIG
   Current/Pending 均为 N/A，但本轮没有实时读取显卡；
7. **FACT：** `SmcRegHal` 只对 Blackwell 判为 SMC-local 的
   `0x400000..0x5fffff` resolved offset 改走带 GR route 的
   `NV2080_CTRL_CMD_GPU_EXEC_REG_OPS`；其余地址回退普通 RegHal；
8. **强 INFERENCE：** boot/fuse/base coupling 属于 PMC-relative
   `+0x44/+0x40/+0x48`，不在上述 GR/SMC-local 窗口，因此即使 `+0x6c0`
   非空，这三项仍走普通 backend。严格的 domain-`0x31` runtime address
   translation 数值没有在本轮执行 MODS 重放，故将“这三项绝不被改路”保留为
   强 INFERENCE，而不是运行时 FACT。

换成人话：这个字段不是“零售卡解锁后端”，而是“MODS 当前绑在哪个 MIG 分区、
哪个 GR engine 上”的可选寄存器访问适配器。

## 范围与安全边界

- 固定样本：`mods_audit/static/extracted_inner/mods`
- SHA-256：
  `c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf`
- 公开对照：本地 NVIDIA 610.43.03 headers
- 只做 bounded `objdump`、RTTI/vtable 数据读取、低内存 opcode/xref 候选检查、
  既有 GB202 RegHal table 的离线解析。

没有运行 MODS，没有打开 `/dev/nvidia*`，没有访问 PCI/BAR/MMIO，没有发 control，
没有 reset、驱动或固件操作。

本文等级：

- **FACT：** 固定二进制、固定表或公开 header 直接证明；
- **INFERENCE：** 多条静态证据一致，但仍缺一次目标 runtime 绑定/翻译；
- **UNKNOWN：** 当前材料不能闭合。

## 1. getter 与 GB202 vtable 绑定

`0x0db40a0` 的完整主体只有：

```text
0x0db40a0  mov  0x6c0(%rdi), %rax
0x0db40a7  add  $0x90, %rdi
0x0db40ae  test %rax, %rax
0x0db40b1  cmove %rdi, %rax
0x0db40b5  ret
```

RTTI `17GB202GpuSubdevice` 对应 vtable `0x92c8500`；其 `+0x208` 项是
`0x0db40a0`。GB20x 基类 vtable `0x92c1550+0x208` 也是同一函数。故这不是从
TU102 或旧架构类比出的绑定，而是固定 GB202 vtable 的直接 **FACT**。

`0x126b360` 的 coupling mapper 每次通过该 vtable slot 取当前 RegHal，再用
`0x1988fc0` 测试 boot/fuse/base 三项。因此非空 override 确实位于 mapper 的
动态调用链上；是否实际改变某一项读源，还要看 `SmcRegHal` 自己的地址分流。

## 2. 构造时明确为 `NULL`

基础 `GpuSubdevice` 构造函数 `0x0df2af0` 在 `0x0df2baa` 清零 `xmm0`，随后：

```text
0x0df2c9b  movups %xmm0, 0x6c0(%rbx)
0x0df2ca2  movups %xmm0, 0x6d0(%rbx)
0x0df2ca9  movups %xmm0, 0x6e0(%rbx)
```

第一条同时把 `+0x6c0` 和 `+0x6c8` 清零。GB20x/GB202 派生构造链先执行这个
基础构造，再安装派生 vtable。因此 `+0x6c0` 的初始值为 `NULL` 是 **FACT**。

## 3. 唯一闭合的非零 writer：创建 `SmcRegHal`

在本轮限定的 `GpuSubdevice`/GB20x 相关代码范围内，闭合到的 qword 非零 writer
是 `0x0dee6c6`：

```text
0x0dee69d  operator new(0x58)
0x0dee6b9  call 0x1990c40
0x0dee6be  old = [GpuSubdevice+0x6c0]
0x0dee6c6  [GpuSubdevice+0x6c0] = new_object
0x0dee6ce  if (old != NULL)
0x0dee6d3      old->vtable[1](old)       // deleting destructor
0x0dee6e4  call 0x1988880(new_object)   // RegHal setup
```

这里不能把有限范围 opcode 扫描写成“全 ELF 不可能有任何间接 writer”；但这个
writer 的构造、调用者、RTTI、getter 与析构均已互相闭合。

### 3.1 类型是二进制直接证明的 `SmcRegHal`

构造函数 `0x1990c40`：

```text
call 0x1988570                  // RegHal base constructor
vptr             = 0x93faeb0
object+0x40       = GpuSubdevice*
object+0x48       = selected partition/control object
object+0x50       = selected partition/swizz-related value
object+0x54       = selected SMC engine index
```

`0x93fae88` 的 RTTI name pointer 指向 `9SmcRegHal`，base RTTI name 是
`6RegHal`。所以类型和继承关系都是 **FACT**，不是从字符串附近猜出的名称。

## 4. 何时会赋值：MIG partition 初始化阶段

writer `0x0dee3e0` 的直接 caller 是 `0x0deede2`，位于初始化函数
`0x0dee7e0`；后者又由设备初始化循环 `0x0dffa80` 在 `0x0dffb1c` 调用。

`0x0dee7e0` 首先发 control：

```text
command = 0x20800175
size    = 0x748
```

公开 610 header `ctrl2080gpu.h:2803-2811` 将它定义为
`NV2080_CTRL_CMD_GPU_GET_PARTITIONS`；`:2676-2685` 明确写着 GPU 未 partition
时返回 `NV_ERR_NOT_SUPPORTED`。

固定 MODS 的结果分支为：

- `0x0dee858`：wrapper 返回 `0x255` 时跳到 `0x0deeaf0`，打印
  `MIG is not supported by RM. Skipping possible SMC resource initialization`，
  然后返回成功；
- `0x0dee86e..877`：`validPartitionCount==0` 时跳到 `0x0deebea`，打印
  `No valid MIG partitions found. Skipping SMC resource initialization`，然后
  返回成功；
- 有有效 partition 时，代码建立 partition/engine 候选，读取
  `SmcPartIdx` 与 `SmcEngineIdx`，验证选择；
- 选择成功后 `0x0deede2 -> 0x0dee3e0`，才创建并安装 `SmcRegHal`。

解码 JS `gpuargs.js:1649-1650` 对两个参数的说明也分别是选择 MODS 使用的 SMC
partition，以及该 partition 内的 local engine。故赋值时机和用途都是 **FACT**。

项目归档 `l2_slice_re/raw/20260713T092611+0800.LGScei/nvidia-smi.before.txt:20-22`
显示当时 RTX 5090 的 MIG Current/Pending 均为 N/A。这是历史 runtime 佐证，不是
本轮实时状态，也不能单独证明某个从未运行的 MODS 对象内存值。

## 5. 替换、跳过与析构语义

### 5.1 重复成功路径

`0x0dee6be..0x0dee6d6` 的顺序是：先保存旧指针、写入新指针，再删除旧对象。
因此一次成功重选不会先把 getter 暴露为 `NULL`；constructor 抛错时则尚未执行
store。这里的行为是 **FACT**。

### 5.2 skip 路径不负责 clear

MIG unsupported 和 zero-partition 两个早退分支均不触及 `+0x6c0`。所以：

- 新构造对象第一次走 skip：保持 `NULL`；
- 已经有 `SmcRegHal` 的同一对象若后来再次走 skip：现有窗口没有 clear。

后一种状态转换是否在产品控制流中允许发生、是否总会先重建 `GpuSubdevice`，是
**UNKNOWN**，不能把“skip”泛化成 teardown。

### 5.3 对象析构

`GpuSubdevice` 析构窗口：

```text
0x0dde27e  rdi = [object+0x6c0]
0x0dde285  test rdi,rdi
0x0dde28a  rax = [rdi]
0x0dde28d  call *0x8(rax)       // deleting destructor
```

所以 ownership 由 `GpuSubdevice` 持有并在整体销毁时释放，是 **FACT**。析构没有
再写零，因为 enclosing object 随即失效；这不构成 use-after-free 证据。

## 6. `SmcRegHal` 到底改变哪类读写

普通 `RegHal` vtable 的 read/write slots `+0x18/+0x20` 是
`0x198b240/0x198b310`；`SmcRegHal` 对应 slots 是
`0x1990e60/0x1990ee0`。

read override `0x1990e60` 的行为可化简为：

```c
resolved = RegHalResolveOffset(...);             // 0x19879c0
if (!gpu->IsSmcLocalReg(resolved))
    return RegHalBaseRead(...);                  // 0x198b240
return SmcExecRegRead(resolved);                 // 0x1990c80
```

GB202 vtable 的 predicate chain 是：

```text
+0xe30 = 0x1249540
+0xe28 = 0x1247240 / cached SMC-enabled byte at GpuSubdevice+0x1ac4
+0xe38 = 0x0db4070
```

`0x0db4070` 精确执行：

```text
return (resolved - 0x400000) <= 0x1fffff;
```

即只接受闭区间 `0x400000..0x5fffff`。SMC 未启用、predicate 为 false，或某代
GpuSubdevice 没实现该 predicate 时，都回退普通 RegHal。

`0x1990c80` 构造一个单项 `NV2080_CTRL_GPU_REG_OP`：`regOp=READ_32`、
`regType=GLOBAL`、`regOffset=resolved`，填入所选 SMC/GR route，然后发
`0x20800122`。公开 `ctrl2080gpu.h:649-680,691-750` 证明该 ID 是
`NV2080_CTRL_CMD_GPU_EXEC_REG_OPS`，并明确说 SMC 启用时 `grRouteInfo` 是必填项。
write override `0x1990ee0` 对命中地址同样改走 `0x1990d50` 的 WRITE_32 control。

因此“override 的 runtime backend 是带 partition/GR route 的 RM reg-op control”
是 **FACT**；它不是把所有 RegHal 访问统一交给 GSP/FSP。

## 7. 对 boot/fuse/base coupling 读源的影响

固定 GB202 RegHal table 给出：

| 项 | effective read ID | normal offset | access/PLM offset |
|---|---:|---:|---:|
| fuse | `0x12d6c000` | `+0x40` | `+0x308` |
| boot | `0x12d68000` | `+0x44` | `+0x30c` |
| base | `0x12d64000` | `+0x48` | `+0x310` |

三项均处于 RegHal domain word `0x31`。固定 GSP 的独立 device-info 路径又把同一
三元组闭合为 type-`0x2a` PMC-like device 的
`devicePriBase+0x40/+0x44/+0x48`；公开 `nv_ref.h:107-108` 的稳定 PMC published
layout也以 `NV_PMC_BOOT_0=0` 为基点。

据此：

- **FACT：** `SmcRegHal` 只改路 resolved `0x400000..0x5fffff`；
- **FACT：** coupling table 的直接 field offsets 是 `0x40/0x44/0x48`；
- **V-STATIC / 强 INFERENCE：** 它们是 PMC-relative 小 offset，不属于
  SMC-local GR PRI 窗口，所以 override 最终调用 base read；
- **UNKNOWN：** 固定 MODS 在具体 runtime 为 domain `0x31` 建出的 capability/domain
  translation record 的最终数值。本轮没有执行 MODS，也没有读本卡来重放
  `0x19879c0`，所以不把 resolved 数值冒充直接 FACT。

这个边界很重要：mapper 取得 `SmcRegHal*` 是 FACT，但不能仅凭“取得了 override”
就断言三只 coupling bit 改由 MIG RM control 读取。现有证据更支持相反结论：
override 对 GR/SMC-local 地址有意义，对 PMC coupling 三元组回退普通路径。

## 8. 最终证据矩阵

| 问题 | 结论 | 等级 |
|---|---|---|
| getter | `+0x6c0` 非空取 override，否则 `this+0x90` | **FACT** |
| GB202 是否绑定该 getter | `GB202GpuSubdevice` vtable `+0x208=0xdb40a0` | **FACT** |
| 初始值 | constructor 清零 `+0x6c0` | **FACT** |
| 非零对象类型 | `SmcRegHal : RegHal` | **FACT（RTTI）** |
| writer | `0xdee6c6` | **FACT（限定相关范围）** |
| writer 时机 | 有效 MIG partition + 有效 SMC engine 选择之后 | **FACT** |
| MIG unsupported / no partition | 成功 skip，不写、不 clear override | **FACT** |
| 重选 | 新对象先换入，旧对象随后 deleting-destructor | **FACT** |
| 最终释放 | `GpuSubdevice` destructor 删除非空 override | **FACT** |
| 普通未 partition GB202 | 首次 init 后通常仍为 `NULL` | **强 INFERENCE / 条件 FACT** |
| override read backend | 命中 SMC-local 时发 routed `EXEC_REG_OPS READ_32` | **FACT** |
| 接管地址窗口 | `0x400000..0x5fffff`，且需 SMC enabled | **FACT** |
| coupling 三项是否被接管 | 静态证据支持否，回退 base RegHal | **强 INFERENCE** |
| domain-`0x31` 本卡当次 resolved 数值 | 未执行/未读取 | **UNKNOWN** |
| 本卡此刻 `+0x6c0` 内存值 | 本轮纯静态；MODS 未运行 | **UNKNOWN** |

