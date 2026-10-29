# GSP `0x144d4e8` reset-coupling getter：内部字段与读取地址

> **后续独立交叉校准：** `parallel/reset_getter_guard_provenance.md` 以另一条
> virtual/physical 特征路径把 `+0xb68` 闭合为 `isVirtual`，并以同一固定 GSP 的
> 三个 selector setter 及 MODS RegHal 三元组把 `+0x40/+0x44/+0x48` 校准为
> fuse/boot/base。故本文中原先仅由结构顺序给出的“强 INFERENCE”现可按该组合
> 证据升级为 `V-STATIC`；逐指令地址公式和 base 级联未知项不变。

## 结论先行

固定 GSP ELF 中，chip index 65 的 OBJGPU `+0x668` 最终绑定函数 `0x144d4e8`。该函数的正常路径可精确还原为：

```c
bool getter(GpuLikeObject *pGpu)
{
    if (*(uint8_t *)(pGpu + 0xb68) != 0)
        return false;

    const BinaryDeviceInfoEntry *pEntry = NULL;
    status = helper_0x1b562f0(pGpu, 0x2a, 3, -1, 0, &pEntry);
    if (status != 0 || pEntry == NULL)
    {
        // checked-build assertion/reporting path
        return false;          // if the reporter returns
    }

    uint32_t priBase = *(uint32_t *)((uint8_t *)pEntry + 0x10);
    uint8_t *aperture = *(uint8_t **)((uint8_t *)pGpu + 0xb98);

    uint32_t off0 = ((uint32_t)(priBase + 0x40) >> 2) << 2;
    if ((*(uint32_t *)(aperture + off0) & 1) != 0)
        return true;

    uint32_t off1 = ((uint32_t)(priBase + 0x44) >> 2) << 2;
    return (*(uint32_t *)(aperture + off1) & 1) != 0;
}
```

因此二进制级确定的两个读地址是：

```text
word0 = *(u32 *)( *(u64 *)(pGpu+0xb98)
                  + align_down_4_u32(entry.devicePriBase + 0x40) )
return true if word0.bit0 == 1

word1 = *(u32 *)( *(u64 *)(pGpu+0xb98)
                  + align_down_4_u32(entry.devicePriBase + 0x44) )
return word1.bit0
```

对合法、自然对齐的 `devicePriBase`，内部 PRI offset 简化为：

```text
devicePriBase + 0x40, bit 0
devicePriBase + 0x44, bit 0
```

**FACT：** 函数没有第三次 `devicePriBase+0x48` 读取。第一个 bit 为 1 时还会短路，第二个 word 不读。

**V-STATIC（组合证据）：** 结合相邻 GSP setter 和现有 MODS RegHal 表的
`fuse +0x40 / boot +0x44 / base +0x48` 排列，这两个 bit 分别是 fuse coupling
和 boot coupling；此 getter 没有直接读取 base coupling 的 `+0x48` 项。

**UNKNOWN：** base coupling 是否会由硬件/firmware 联动反映到前两个 bit 之一。故当前不能进一步声称“base-only 状态下 ioctl 一定返回 false”。

## 范围与安全边界

- GSP 文件：`/tmp/gsp_inner_19f040_a.elf`
- SHA-256：`bda917c95547644398eaf77fefe6c7f1b701c962db91f88bffaed6448a218a47`
- 格式：ELF64 RISC-V / RVC，stripped
- 目标函数：`0x144d4e8`
- bounded helper：`0x1b562f0`、iterator helper `0x1423958`
- 对照源码：本地公开 OpenRM 610.43.03

只做了有限 Capstone 解码、算术重放和公开源码文本搜索。没有打开 `/dev/nvidia*`，没有运行 MODS，没有访问 GPU/MMIO，没有驱动、模块或 reset 操作。

本文把证据分成：

- **FACT：** 固定 ELF 直接证明，或公开源码直接定义；
- **INFERENCE：** 二进制行为和公开结构高度吻合，但 stripped/private GSP layout 没有类型符号；
- **UNKNOWN：** 静态材料无法闭合。

## 1. `+0xb68` guard 与完整返回路径

函数入口先把 `pGpu+0x1000` 保存到 `s1`：

```text
0x144d4f6: c.lui  a5, 1
0x144d4f8: add     s1, a0, a5        # s1 = pGpu + 0x1000
0x144d4fc: lbu     a5, -0x498(s1)    # *(u8 *)(pGpu + 0xb68)
0x144d512: c.beqz  a5, +6
0x144d514: c.li    a0, 0
0x144d516: c.j     return_epilogue
```

**FACT：** `pGpu+0xb68` 是一个一字节 guard；非零时 helper 和两个 aperture read 都不发生，函数直接返回 false。

固定 ELF 的同一 bounded OBJGPU 构造簇还出现：

```text
0x1b9f394: c.lui a4, 1
0x1b9f3a2: c.add a4, s11             # a4 = object + 0x1000
0x1b9f3b8: sh     zero, -0x498(a4)   # clear object+0xb68..+0xb69
0x1b9f3bc: sb     zero, -0x496(a4)   # clear object+0xb6a
```

公开 610 `OBJGPU` 在相应数据成员序列中正好有三个连续 `NvBool`：

```text
isVirtual, isGspClient, isDceClient
```

随后按 RV64 对齐依次是 `fbLength`、`instLength`、`instSetViaAttachArg`、`activeFBIOs`、`gpuVbiosPostTime`、`uefiScanoutSurfaceSizeInMB`、`gpuDeviceMapCount` 和 `deviceMappings[]`；若第一个 bool 位于 `+0xb68`，`deviceMappings[0]` 正好从 `+0xb98` 开始。

**V-STATIC（后续独立路径校准）：** guard `+0xb68` 是 private GSP layout 中的
`isVirtual`。除本节结构顺序外，`parallel/reset_getter_guard_provenance.md` 还
证明另一固定 GSP 函数用同一 byte 在 VGPU static-info cache 与物理 command
`0x20801823` 之间分支，逐项吻合公开 `kbusSendBusInfo_IMPL`。

**不是 ABI FACT：** 固定 ELF stripped，且其 private GSP layout 与公开 host NVOC layout 不能按偏移机械等同；正式字段名仍由结构顺序和行为校准，而不是 ELF symbol 给出。

其他返回路径：

| 条件 | 固定 ELF 行为 | 结果 |
|---|---|---|
| `+0xb68 != 0` | 不调用 helper | false |
| helper status 非零 | 进入 assertion/reporting cold path | reporter 若返回，则 false |
| helper 返回成功但 entry pointer 为空 | assertion/reporting cold path | reporter 若返回，则 false |
| 第一个 word bit0=1 | `0x144d54e -> 0x144d57c` | true，短路第二读 |
| 第一个 bit0=0 | 读取第二个 word | 返回第二个 bit0 |
| stack canary 不匹配 | `0x144d56c -> 0x144d5f2` | stack-fail path |

## 2. helper 请求项 `0x2a`

调用前的寄存器赋值为：

```text
0x144d510: a4 = 0
0x144d518: a5 = s0 - 0x40       # caller stack 上的 pointer output slot
0x144d51c: a3 = -1
0x144d51e: a2 = 3
0x144d520: a1 = 0x2a
0x144d526..52a -> call 0x1b562f0
```

所以精确 ABI 参数是：

```text
(pGpu, 0x2a, 3, -1, 0, &pEntry)
```

这里的 `3` 是 device-info helper 的筛选参数，不能与 OBJGPU constructor 的 chip dispatch `group=2` 混为一谈。

### `0x1b562f0` 的行为闭合

**FACT：** helper 首先把输出清零：

```text
0x1b5630a: s1 = a5
0x1b5631e: sd zero, 0(s1)       # *ppEntry = NULL
```

然后：

1. 经 `pGpu+0xa0` 的方法确保 device-info table 已构造；
2. 调 iterator helper `0x1423958` 建立筛选状态；
3. 从 `pGpu+0x40d0` 取得 table pointer，从 `pGpu+0x40d8` 取得 entry count；
4. 按固定 ELF 的 `0x34` byte stride 遍历；
5. 比较 entry `+0x08 == 0x2a`；
6. 用 entry `+0x20` 生成的 group bit 与 iterator mask 相交；
7. 本次还要求 entry `+0x04 == 0`；
8. 无匹配返回 `0x57`，多匹配返回 `0x4c`，唯一匹配把 entry pointer 写入输出。

公开 610 的状态码定义确认：

- `0x4c = NV_ERR_MORE_DATA_AVAILABLE`
- `0x57 = NV_ERR_OBJECT_NOT_FOUND`

这与公开 `gpuGetOneDeviceEntry_IMPL` 的“零匹配 / 多匹配 / 唯一匹配”控制流逐项一致。公开声明的六参数形式也是：

```c
gpuGetOneDeviceEntry(pGpu,
                     deviceTypeEnum,
                     dieletInstance,
                     globalInstanceId,
                     dieLocalInstanceId,
                     ppDeviceEntry)
```

**FACT（公开 610）：** 按该公开签名解释，调用值分别是 `deviceTypeEnum=0x2a`、`dieletInstance=3`、`globalInstanceId=-1/ANY`、`dieLocalInstanceId=0`。

**版本边界：** 固定 ELF 的 entry stride 是 `0x34`，而公开 610 `DEVICE_INFO_ENTRY` 是 `0x30`；固定 ELF 的 iterator helper 也有一个公开 610 结构未展示的额外筛选 word。因此源码用于结构语义校准，不能声称两个版本的完整 private ABI 完全相同。

### `0x2a` 的设备身份

公开 610 的 GPU `dev_top.h` 没有发布完整 type-enum 名单；公开 LS10 topology 头明确给出：

```text
NV_SWPTOP_ENUM_DEVICE_PMC = 0x2a
```

目标函数又使用返回 entry 的 PRI base 加 `0x40/0x44` 读取 reset-coupling 候选位。

**强 INFERENCE：** 固定 GB202 GSP 中的 type enum `0x2a` 同样是 PMC device entry。

**UNKNOWN：** 当前公开 GB202 GPU header 没有直接给出 `TYPE_ENUM_PMC=0x2a` 宏，因此“PMC”不是来自该 GPU header 的独立 FACT。

## 3. 输出描述结构

caller 在自己的当前 stack `sp+0` 放的是一个 pointer output slot，不是把完整 descriptor 内联复制到 stack：

```text
caller s0 = caller sp + 0x40
output slot = s0 - 0x40 = sp
stack canary = s0 - 0x38 = sp + 8
```

helper 把唯一匹配的 table-entry 地址写进该 8-byte slot；caller 在 `0x144d532` 重新加载 pointer，再在 `0x144d538` 读取 `entry+0x10`。

固定 ELF 直接观测到的 entry 核心布局：

| binary offset | 使用方式 | 能确定的意义 |
|---:|---|---|
| `+0x04` | 与请求 filter `0` 比较 | 某个 instance ID；精确 570 字段名保留 |
| `+0x08` | 与 `0x2a` 比较 | device type enum |
| `+0x10` | caller 加 `0x40/0x44` 后作为 aperture offset | device PRI base |
| `+0x20` | `1 << field` 后与 iterator mask 相交 | group/dielet ID |
| stride `0x34` | table 遍历步长 | 固定 ELF entry 总跨度 |

公开 610 的 `DEVICE_INFO_ENTRY` 为：

```c
offset 0x00  faultId
offset 0x04  instanceId
offset 0x08  typeEnum
offset 0x0c  resetId
offset 0x10  devicePriBase
offset 0x14  isEngine
offset 0x18  rlEngId
offset 0x1c  runlistPriBase
offset 0x20  groupId
offset 0x24  ginTargetId
offset 0x28  deviceBroadcastPriBase
offset 0x2c  groupLocalInstanceId
sizeof       0x30
```

**FACT / cross-version match：** 固定 ELF 实际使用的 `+0x08`、`+0x10`、`+0x20` 与公开结构的 `typeEnum`、`devicePriBase`、`groupId` 完全对齐。`+0x10` 的 `devicePriBase` 身份尤其由 caller 后续地址运算确认。

**UNKNOWN：** 固定 ELF 比公开 610 多出的 4 byte 位于何处、叫什么；本报告不虚构该 tail/private 字段。

## 4. `+0xb98` base pointer

正常路径：

```text
0x144d53a: ld a3, -0x468(s1)
```

因为 `s1=pGpu+0x1000`，所以实际是：

```text
a3 = *(u64 *)(pGpu + 0xb98)
```

随后两个最终地址都直接由 `a3 + aligned_offset` 形成；函数没有再调用 register-read wrapper。

**FACT（二进制角色）：** `+0xb98` 保存一个可直接作为 32-bit register aperture 起点使用的 64-bit virtual base pointer。

公开 610 的 `OBJGPU` 数据成员顺序与前述 `+0xb68` 三个 bool 对齐后，`+0xb98` 正好是：

```c
pGpu->deviceMappings[0].gpuNvAddr
```

公开 `DEVICE_MAPPING` 的第一个成员定义为：

```c
GPUHWREG *gpuNvAddr;        // CPU Virtual Address
```

公开 `gpu_device_mapping.c` 还说明 discrete GPU 的 `DEVICE_INDEX_GPU` 映射就是 `deviceMappings[0]`，即 GPU/BAR0 PRI aperture mapping。

**强 INFERENCE（字段名）：** private GSP `+0xb98` 是 `deviceMappings[0].gpuNvAddr` 的对应字段。行为、RV64 对齐、与 `+0xb68` 起始字段的相对布局三者一致。

**表述边界：** 这是 GSP 地址空间里可解引用的 virtual aperture pointer；不要把 `pGpu+0xb98` 本身误写成 GPU PRI 数值，也不要把 host CPU virtual address 数值与 GSP virtual address 数值混用。

## 5. 两个 bit 的精确内部地址

### 第一个 bit

```text
0x144d538: lw      a4, 0x10(entry)       # priBase
0x144d53e: addiw   a5, a4, 0x40
0x144d542: srliw   a5, a5, 2
0x144d546: c.slli  a5, 2
0x144d548: c.add   a5, aperture
0x144d54a: c.lw    a5, 0(a5)
0x144d54c: c.andi  a5, 1
0x144d54e: c.bnez  a5, true_return
```

精确公式：

```text
VA0  = aperture + (((u32)(devicePriBase + 0x40) >> 2) << 2)
bit0 = (*(u32 *)VA0) & 1
```

### 第二个 bit

只在第一个 bit 为 0 时执行：

```text
0x144d550: addiw   a4, a4, 0x44
0x144d554: srliw   a4, a4, 2
0x144d558: c.slli  a4, 2
0x144d55a: c.add   a3, a4
0x144d55c: c.lw    a0, 0(a3)
0x144d55e: c.andi  a0, 1
```

精确公式：

```text
VA1  = aperture + (((u32)(devicePriBase + 0x44) >> 2) << 2)
bit1 = (*(u32 *)VA1) & 1
```

**FACT：** `srliw` 使结果成为 30-bit 非负值，再左移 2；因此这是严格的 32-bit wrap 后四字节向下对齐，不是依赖 sign extension 的 64-bit 指针算法。

**UNKNOWN：** `devicePriBase` 的本机运行时数值。它来自 runtime device-info table；固定 ELF 不包含本卡当次构造后的 table 内容。因此静态分析能给出精确 PRI offset 公式和 device-relative `+0x40/+0x44`，不能诚实地捏造一个绝对 numeric BAR0 address。

## 6. 与 MODS RegHal coupling 字段的对应

现有 MODS 570.151 静态 RegHal 结果是：

| 名称 | RegHal value/test IDs | RegHal domain 内 field offset |
|---|---|---:|
| fuse | `0x42d6c000 / 0x42d6c001` | `0x40` |
| boot | `0x42d68000 / 0x42d68001` | `0x44` |
| base | `0x42d64000 / 0x42d64001` | `0x48` |

GSP getter 的 device-relative 序列正好是：

```text
+0x40 bit0, then +0x44 bit0; no +0x48 load
```

证据分级：

- **FACT：** 数字 offset 和读取顺序精确相同；GSP getter 只读前两项。
- **V-STATIC（组合证据）：** `+0x40 bit0 = fuse coupling`，
  `+0x44 bit0 = boot coupling`；相邻 setter 还把 `+0x48` 闭合为 base coupling。
- **INFERENCE：** type enum `0x2a` 是 PMC，使这组对应关系比单纯“数字碰巧相同”更可信。
- **UNKNOWN：** MODS RegHal 的“field offset”是否可在所有 backend 中直接等同于该 PMC device-relative PRI offset；此前 RegHal 审计有意没有把它擅自写成绝对 BAR0 地址。
- **FACT：** 即使采用上述名称对应，函数也没有直接读取 `+0x48`。
- **UNKNOWN：** base coupling 是否具备级联/镜像语义，从而仍能让 `+0x40` 或 `+0x44` 的 bit0 置位。

所以最稳妥的用户态结论不是“公开 aggregate query 等于三个 coupling 位 OR”，而是：

```text
固定 GB202 GSP 实现的 +0x668 getter
= virtual guard 后，对某个 type-0x2a device PRI base 的
  +0x40.bit0 与 +0x44.bit0 做短路 OR。
```

在没有证明 base coupling 的硬件级联关系前，这个 aggregate bool 不能单独作为“boot/fuse/base 三项都为零”的完整证明。

## 7. 最终 FACT / INFERENCE / UNKNOWN 矩阵

| 问题 | 结论 | 等级 |
|---|---|---|
| chip index 65 的 `+0x668` 目标 | `0x144d4e8` | **FACT（前序独立重放）** |
| `+0xb68` 行为 | 非零立即 false | **FACT** |
| `+0xb68` 正式字段名 | `isVirtual` | **V-STATIC** |
| helper 地址 | `0x1b562f0` | **FACT** |
| helper 参数 | `(pGpu,0x2a,3,-1,0,&entry)` | **FACT** |
| helper 身份 | 与公开 `gpuGetOneDeviceEntry_IMPL` 控制流/状态码/结构吻合 | **FACT（行为）/ INFERENCE（stripped symbol 名）** |
| `0x2a` 身份 | PMC device type | **强 INFERENCE** |
| output 形态 | 8-byte pointer slot，指向 table entry | **FACT** |
| binary entry stride | `0x34` | **FACT** |
| entry `+0x10` | device PRI base | **FACT（行为 + 公开结构校准）** |
| `+0xb98` 行为 | aperture virtual base pointer | **FACT** |
| `+0xb98` 源字段名 | `deviceMappings[0].gpuNvAddr` | **强 INFERENCE** |
| 第一个读 | `aperture + align4_u32(priBase+0x40)`, word bit0 | **FACT** |
| 第二个读 | `aperture + align4_u32(priBase+0x44)`, word bit0 | **FACT** |
| 返回关系 | `first_bit || second_bit`，短路 | **FACT** |
| 直接 `+0x48` 读取 | 不存在 | **FACT** |
| `+0x40/+0x44` 名称 | fuse / boot coupling | **V-STATIC（组合证据）** |
| base coupling 是否能间接反映到两 bit | 未闭合 | **UNKNOWN** |
| 本机 numeric `devicePriBase` / 绝对读地址 | 静态 ELF 不包含运行时 table 值 | **UNKNOWN** |
