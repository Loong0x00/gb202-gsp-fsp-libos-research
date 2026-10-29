# GB202 `0x144d4e8`：reset-coupling getter 的 guard 与字段 provenance

日期：2026-07-21

## 结论先行

对固定 inner GSP ELF、相邻 GSP setter、MODS 570.151 RegHal 元数据和公开
OpenRM 610.43.03 做交叉核对后，可以把 `0x144d4e8` 收敛为：

```c
NvBool reset_coupled_like(GpuPrivate *pGpu)
{
    if (pGpu_private_byte_0xb68 != 0)       // V-STATIC: isVirtual
        return NV_FALSE;

    entry = get_one_device_entry_like(pGpu, 0x2a, 3, -1, 0);
    if (lookup_failed || entry == NULL)
        return NV_FALSE;                    // checked-build report/assert path 后

    pri = entry->devicePriBase;             // entry + 0x10
    aperture = *(u8 **)(pGpu + 0xb98);

    return bit0(aperture + align4_u32(pri + 0x40)) ||
           bit0(aperture + align4_u32(pri + 0x44));
}
```

三个 reset-coupling 字段的静态对应现在是：

| device-relative target | PLM metadata | 名称 | getter 是否读取 |
|---:|---:|---|---|
| `+0x40.bit0` | `+0x308` | **fuse coupling** | 是，第一个，置位即短路返回 true |
| `+0x44.bit0` | `+0x30c` | **boot coupling** | 是，第二个 |
| `+0x48.bit0` | `+0x310` | **base coupling** | **否** |

这里的名称不再只靠 MODS 中三个相邻 offset 猜：固定 GSP 内的相邻 setter 也用
完全相同的 device-info 请求 `0x2a,3,-1,0` 和同一个 aperture base，逐项形成
`(+0x40,+0x308)`、`(+0x44,+0x30c)`、`(+0x48,+0x310)`；再与 MODS 已命名的
RegHal 三元组交叉对齐。因而 `0x144d4e8` 的两个直接输入是 **fuse OR boot**，
不是 boot/fuse/base 三项全 OR。

`OBJGPU-private+0xb68` 也不再只是“像某个 guard”：另一固定 GSP 函数
`0x1b2392c` 用同一字节在“读取 VGPU static-info cache”和“发送物理 RM control
`0x20801823`”之间分支；这与公开 `kbusSendBusInfo_IMPL` 的 `IS_VIRTUAL(pGpu)`
分支和同一 command ID 逐项吻合。因此把它校准为 `isVirtual` 属于
**V-STATIC**。guard 非零时返回 false 的直接原因是：此 getter 没有虚拟化
cache/RPC 分支，虚拟对象不进入那两次物理 PRI aperture load。

## 样本、方法与安全边界

固定 GSP 样本：

```text
file   /tmp/gsp_inner_19f040_a.elf
size   82577496
sha256 bda917c95547644398eaf77fefe6c7f1b701c962db91f88bffaed6448a218a47
RX VA  0x01000000..0x01e97000
```

MODS 对照样本：

```text
file   mods_audit/static/extracted_inner/mods
size   392339552
sha256 c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf
```

本轮只做固定文件的小窗口 RISC-V/RVC 反汇编、算术复算和本地公开源码文本核对。
没有打开 `/dev/nvidia*`，没有运行 MODS 或固件，没有访问 GPU、BAR/MMIO、PCI
config/debugfs，也没有 reset、驱动、模块、电源或显示操作。

证据等级：

- **FACT**：固定 artifact 直接给出的控制流、数值或公开源码直接定义；
- **V-STATIC**：两个独立静态来源以特殊控制流/常量闭合到同一语义；
- **INFERENCE**：证据很强，但 stripped/private ABI 缺正式符号；
- **UNKNOWN**：现有静态材料不能回答。

## 1. getter 的完整正常路径

前序两套独立 constructor replay 已证明 GB202/index 65 把 `0x144d4e8` 安装到
private GPU-like object 的 `+0x668`；绑定证据见
`parallel/reset_coupled_binding_replay.md`。本节只追该目标函数内部。

### 1.1 guard

```text
0x144d4f6: lui/add  s1,a0,0x1000
0x144d4fc: lbu      a5,-0x498(s1)     # *(u8 *)(pGpu+0xb68)
0x144d512: beqz     a5,0x144d518
0x144d514: li       a0,0
0x144d516: j        common return
```

**FACT：** `+0xb68 != 0` 时 helper 和 aperture read 都不会执行，直接 false。

### 1.2 device-info lookup

guard 为零时调用前的寄存器为：

```text
a0 = incoming pGpu
a1 = 0x2a
a2 = 3
a3 = -1
a4 = 0
a5 = &entry_pointer_slot
call 0x1b562f0
```

返回 status 非零，或 status 为零但 output pointer 仍为空，都会进入日志/assert
cold path；若 reporter 返回，最终值是 false。只有唯一 entry 成功返回后才继续。

### 1.3 两次 load 和短路 OR

成功路径的关键指令为：

```text
0x144d538: lw      a4,0x10(entry)     # devicePriBase
0x144d53a: ld      a3,-0x468(s1)     # *(u64 *)(pGpu+0xb98)
0x144d53e: addiw   a5,a4,0x40
0x144d542: srliw   a5,a5,2
0x144d546: slli    a5,a5,2
0x144d548: add     a5,a3
0x144d54a: lw      a5,0(a5)
0x144d54c: andi    a5,a5,1
0x144d54e: bnez    a5,true

0x144d550: addiw   a4,a4,0x44
0x144d554: srliw   a4,a4,2
0x144d558: slli    a4,a4,2
0x144d55a: add     a3,a4
0x144d55c: lw      a0,0(a3)
0x144d55e: andi    a0,a0,1
```

精确公式是：

```text
r0 = *(u32 *)(aperture + (((u32)(devicePriBase + 0x40) >> 2) << 2))
r1 = *(u32 *)(aperture + (((u32)(devicePriBase + 0x44) >> 2) << 2))
return (r0.bit0 != 0) || (r1.bit0 != 0)
```

合法 DEVICE_INFO2 PRI base 本来就是 word-aligned，故通常可简写成
`devicePriBase+0x40` 和 `devicePriBase+0x44`。**FACT：** 此函数没有形成或读取
`devicePriBase+0x48`。

## 2. `0x1b562f0` 是 get-one-device-entry 家族 helper

固定 ELF 中的 helper：

1. 先执行 `*ppEntry = NULL`；
2. 经 private object `+0xa0` 方法确保 device-info table 已构造；
3. 调 `0x1423958` 建立 iterator/filter state；
4. 从 private object `+0x40d0/+0x40d8` 取得 table pointer/count；
5. 以 private stride `0x34` 遍历；
6. 比较 entry `+0x08` 的 type enum、entry `+0x20` 的 group 字段和另一个
   instance filter；
7. 零匹配返回 `0x57`，多匹配返回 `0x4c`，唯一匹配写出 entry pointer。

公开 610.43.03 的对应材料为：

- `src/nvidia/src/kernel/gpu/gpu.c:7769-7855`：
  `gpuIterDeviceInfo_IMPL`、`gpuDeviceInfoIterNext_IMPL`、
  `gpuGetOneDeviceEntry_IMPL`；公开 get-one helper 同样要求唯一匹配，零匹配返回
  `NV_ERR_OBJECT_NOT_FOUND`，多匹配返回 `NV_ERR_MORE_DATA_AVAILABLE`；
- `src/common/sdk/nvidia/inc/nvstatuscodes.h:105,116`：这两个状态正是
  `0x4c` 和 `0x57`；
- `src/nvidia/generated/g_gpu_nvoc.h:774-806`：公开
  `DEVICE_INFO_ENTRY` 的 `typeEnum/devicePriBase/groupId` 分别在
  `+0x08/+0x10/+0x20`。

所以：

- **FACT（binary role）：** `0x1b562f0` 是唯一 device-info entry 查询 helper，
  `0x2a` 是请求的 `deviceTypeEnum`；
- **V-STATIC：** entry `+0x10` 是 `devicePriBase`，不仅公开结构 offset 对齐，
  caller 还立即把它当 PRI address base 使用；
- **边界：** 固定 GSP entry stride 是 `0x34`，公开结构大小是 `0x30`，private
  iterator 也多出筛选状态。调用的数值 tuple `(0x2a,3,-1,0)` 是 FACT；按公开
  六参数原型给四个 selector 强行套完整私有字段名不作为后续结论的前提。

公开 Blackwell `gb100/dev_top.h:37-51` 还直接定义 DEVICE_INFO2 row 中的
`DEV_TYPE_ENUM` 和 `DEV_DEVICE_PRI_BASE` 字段，支持上述数据来源。

### `0x2a` 的设备名

公开 GPU `gb100/dev_top.h` 只发布了少量 type-enum 名称，没有
`TYPE_ENUM_PMC` 宏。公开 NVS topology 头
`published/nvswitch/ls10/dev_nvs_top.h:40-103` 中有
`NV_SWPTOP_ENUM_DEVICE_PMC = 0x2a`，但 NVS 与 GPU enum 名单并非逐项相同，
不能把它单独当 GB202 GPU 的证明。

结合下面相邻函数确实在该 entry 的 PRI base 下操纵三组 reset-coupling/PLM
字段，**强 INFERENCE：** GB202 GSP 的 type `0x2a` 是 PMC/reset-controller
device entry。正式 GPU enum 名仍未在公开头中发布。

## 3. `+0xb68` 为 `isVirtual` 的独立校准

### 3.1 固定 GSP 的特殊控制流匹配

固定函数 `0x1b2392c(pGpu,pBusInfo)` 也读取完全相同的 byte：

```text
0x1b2392c: add      a5,a0,0x1000
0x1b23932: lbu      a2,-0x498(a5)      # pGpu+0xb68
0x1b23936: bnez     a2,virtual_path
0x1b23938..3c: tail 0x10ada14          # physical path
```

其 nonzero 分支按 GPU instance 取得一张 static-info table，再按
`pBusInfo->index` 取缓存 data 写到 `pBusInfo->data`。zero 分支的目标
`0x10ada14` 组装并发送 control command；指令：

```text
lui   a3,0x20802
addi  a3,a3,-0x7dd
```

精确得到 `a3=0x20801823`。

### 3.2 公开 610 的精确同构实现

公开 `kern_bus.c:1083-1120` 的 `kbusSendBusInfo_IMPL` 恰好是：

```c
if (IS_VIRTUAL(pGpu)) {
    VGPU_STATIC_INFO *pVSI = GPU_GET_STATIC_INFO(pGpu);
    pBusInfo->data = pVSI->busGetInfoV2.busInfoList[pBusInfo->index].data;
} else {
    GPU_GET_PHYSICAL_RMAPI(pGpu)->Control(...,
        NV2080_CTRL_CMD_BUS_GET_INFO_V2, ...);
}
```

公开 `ctrl2080bus.h:588` 定义同一 command：

```text
NV2080_CTRL_CMD_BUS_GET_INFO_V2 = 0x20801823
```

“同一 private byte + VGPU static cache + physical control + 同一 32-bit command
ID”的组合足以排除普通 property/permission bit 的碰巧相似。因此：

- **V-STATIC：** private `pGpu+0xb68` 的语义是 `isVirtual`；
- 公开 generated constructor `g_gpu_nvoc.c:568-575` 也明确在 VF 变体设 true，
  在 PF_KERNEL_ONLY 变体设 false；
- `0x144d4e8` 的 early false 是虚拟化 implementation guard，不是 PLM、网络
  security level、fuse lock 或“当前已解耦”的缓存值。

“为什么 false”的可证明实现层答案是：此 getter 只实现 direct physical PRI
读取；对于 virtual object，它没有像 bus-info helper 那样的 static-info/RPC 替代，
所以直接给 false。更高层为什么 NVIDIA 选择不给 VGPU 暴露该状态，源码未说明。

对普通物理 PF，`isVirtual` 语义上应为 false，getter 才进入 lookup/read 路径；
这不是对本机此刻对象字节的运行时实测。

## 4. `+0xb98` 是 aperture pointer，不是 device PRI base

getter 先从 entry `+0x10` 取得 32-bit `devicePriBase`，又独立从
`pGpu+0xb98` 取得 64-bit pointer，最后执行：

```text
*(u32 *)(private_b98_pointer + devicePriBase + field_offset)
```

因此：

- **FACT：** `+0xb98` 是在 GSP 地址空间里可直接解引用的 GPU PRI/register
  aperture virtual base；它不是 `devicePriBase`，也不是 primary fuse base；
- **强 INFERENCE（正式字段名）：** 它对应公开
  `deviceMappings[0].gpuNvAddr`。公开 `DEVICE_MAPPING` 的首成员
  `gpuNvAddr` 被注释为 `CPU Virtual Address`
  (`g_gpu_access_nvoc.h:130-139`)；离散 GPU 的 `DEVICE_INDEX_GPU` 返回
  `&pGpu->deviceMappings[0]` (`gpu_device_mapping.c:63-69`)；
- 公开 object 成员顺序 `isVirtual/isGspClient/isDceClient/.../deviceMappings[]`
  (`g_gpu_nvoc.h:1288-1298`) 与 private `+0xb68`、`+0xb98` 的相对位置和 RV64
  对齐也吻合，但 private GSP 没有类型符号，所以不把字段名升级成 ABI FACT。

已有 `parallel/gsp318_private_provenance.md` 还从四个独立 primary-fuse-relative
caller 校准了同一 private `+0xb98` companion pointer；这与本函数的 direct
aperture 用法一致。

## 5. 相邻 GSP setter 闭合三元组

这是给两个 bit 命名的新增关键证据。

### 5.1 `0x1084508`：`+0x40/+0x44`

该函数同样调用 `0x1b562f0(pGpu,0x2a,3,-1,0,&entry)`，取 entry `+0x10`
和 private `pGpu+0xb98`。按其 selector：

```text
selector 5:
  read  aperture + align4(devicePriBase + 0x30c)
  require metadata.bit4
  RMW   aperture + align4(devicePriBase + 0x44), set bit0
  delay, read back target bit0

selector 4:
  read  aperture + align4(devicePriBase + 0x308)
  require metadata.bit4
  RMW   aperture + align4(devicePriBase + 0x40), set bit0
  delay, read back target bit0
```

对应关键 VA 分别是：

```text
0x1084568..0x108458e  +0x30c PLM / +0x44 target
0x10845f4..0x108461a  +0x308 PLM / +0x40 target
```

### 5.2 `0x109300c`：`+0x48`

另一函数仍用完全相同的 device lookup 和 aperture：

```text
selector 8:
  read  aperture + align4(devicePriBase + 0x310)
  require metadata.bit4
  RMW   aperture + align4(devicePriBase + 0x48), set bit0
  delay, read back target bit0
```

关键 VA 是 `0x109306c..0x1093092`。

这三个 GSP arm 自身直接证明存在一个同设备、同 aperture、同 PLM 间隔的
coupling-like 三元组；本轮没有执行这些函数。

### 5.3 与 MODS RegHal 元数据对齐

固定 MODS 570.151 的既有静态审计给出：

| 名称 | value/test ID | field offset | PLM offset |
|---|---|---:|---:|
| fuse | `0x42d6c000 / 0x42d6c001` | `0x40` | `0x308` |
| boot | `0x42d68000 / 0x42d68001` | `0x44` | `0x30c` |
| base | `0x42d64000 / 0x42d64001` | `0x48` | `0x310` |

详见 `parallel/reset_selection_inputs.md:120-132`。MODS mapper/setter 的业务
控制流又把这三项用于 base/fuse/boot reset 选择，故名称不是只从 ID 文本猜出。

现在形成的静态三角校准是：

```text
fixed GSP same device lookup + target/PLM arithmetic
  <-> fixed MODS RegHal target/PLM offsets
  <-> MODS reset mapper/setter 的 fuse/boot/base 业务角色
```

据此把 `+0x40/+0x44/+0x48` 命名为 fuse/boot/base 属于 **V-STATIC**。
这仍不把这些 offset 写成可直接戳的绝对 BAR0 地址：绝对地址必须先由运行时
DEVICE_INFO2 找到 type-`0x2a` entry 的 `devicePriBase`，而本轮没有读取本卡。

## 6. control 语义与 false 的边界

公开 ABI `ctrl2080gpu.h:4907-4923` 定义：

```text
NV2080_CTRL_CMD_GPU_IS_RESET_COUPLED = 0x208081f3
output: one NvBool isResetCoupled
```

固定 GSP handler 和 GB202 `+0x668` 绑定见前序报告。结合本轮结果，该固定实现
更精确地说是：

```text
isResetCoupled =
    !isVirtual
    && lookup(type=0x2a, selectors=3,-1,0) succeeded uniquely
    && (fuse_coupling.bit0 || boot_coupling.bit0)
```

所以一次 false 至少有三类来源：

1. virtual guard；
2. device-info lookup/reporting failure；
3. getter 读到 fuse=0 且 boot=0。

此外，固定函数没有直接检查 base `+0x48`。如果某个可实现状态在读取瞬间确实是
“仅 base=1、fuse=boot=0”，这段代码会返回 false；但硬件/firmware 是否允许该
组合、base 是否会级联或镜像到较低 coupling 位，现有静态资料仍是 **UNKNOWN**。
相邻 setter 只证明它直接写 `+0x48.bit0`，不能证明写入后的全部硬件副作用。

公开 host 侧 `_gpuRefreshRecoveryActionInLock` (`gpu.c:7416-7433`) 在 self-hosted
GPU 上用这个 bool 决定是否把 recovery action 从 bus reset 升为 system reboot。
这说明 aggregate query 的用途，但没有解释为何 fixed GSP getter 有意忽略 base
位；设计理由保持 **UNKNOWN**，不应补写成推测。

## 7. 最终证据矩阵

| 问题 | 结论 | 等级 |
|---|---|---|
| GB202 `+0x668` 目标 | `0x144d4e8` | **FACT（前序双重 replay）** |
| guard 数值位置/行为 | `pGpu+0xb68`；非零立即 false | **FACT** |
| guard 语义 | `isVirtual` | **V-STATIC** |
| guard 是否权限/PLM/熔丝锁 | 否；它选择 virtual/physical implementation | **V-STATIC** |
| helper 参数 tuple | `(pGpu,0x2a,3,-1,0,&entry)` | **FACT** |
| helper 家族 | unique `gpuGetOneDeviceEntry`-like lookup | **V-STATIC** |
| item `0x2a` | device type enum；很可能 PMC/reset controller | **FACT / 强 INFERENCE（名称）** |
| returned entry `+0x10` | `devicePriBase` | **V-STATIC** |
| `pGpu+0xb98` binary role | direct PRI aperture virtual base | **FACT** |
| `+0xb98` 正式字段名 | 很可能 `deviceMappings[0].gpuNvAddr` | **强 INFERENCE** |
| getter 第一位 | `devicePriBase+0x40.bit0` = fuse coupling | **FACT / V-STATIC（名称）** |
| getter 第二位 | `devicePriBase+0x44.bit0` = boot coupling | **FACT / V-STATIC（名称）** |
| getter 返回组合 | fuse OR boot，第一位短路 | **FACT / V-STATIC（名称）** |
| base coupling | `devicePriBase+0x48.bit0`，PLM `+0x310` | **V-STATIC** |
| getter 是否直接读 base | 否 | **FACT** |
| 为何设计上忽略 base | 公开源码未说明 | **UNKNOWN** |
| 本卡当前 guard/三个 coupling 值 | 本轮纯静态，未读取 | **UNKNOWN** |

最终最重要的修正是：历史 `is_reset_coupled=0` 不能再解释成“GB202 绑定恒假
stub”，也不能自动解释成 boot/fuse/base 全部为零。固定 GB202 getter 是状态感知
实现，但它受 `isVirtual` guard、lookup 成功与否以及 **fuse/boot 两位**共同决定，
并没有直接覆盖 base 位。
