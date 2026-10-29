# GSP reset-coupling setter：`4/5/8` 三路静态交叉审计

## 结论先行

对固定 GSP ELF 的两个小窗口独立解码后，数值 selector 与地址对完全闭合：

| selector（函数第 3 参数 `a2`） | 写入前 gate | gate 条件 | 目标字段 | 写入动作 |
|---:|---:|---:|---:|---|
| `4` | `devicePriBase + 0x308` | word `bit4 == 1` | `devicePriBase + 0x40` | 对 word 做 `OR 1`，即置 `bit0` |
| `5` | `devicePriBase + 0x30c` | word `bit4 == 1` | `devicePriBase + 0x44` | 对 word 做 `OR 1`，即置 `bit0` |
| `8` | `devicePriBase + 0x310` | word `bit4 == 1` | `devicePriBase + 0x48` | 对 word 做 `OR 1`，即置 `bit0` |

这里的地址都相对于同一个 device-info entry 的 `devicePriBase`，再经 `pGpu` 内的寄存器 aperture 映射访问。实现实际上执行 `((base + offset) >> 2) << 2`，所以上表是地址自然按 4 byte 对齐时的简写。

**FACT（固定 ELF）：** `0x109300c` 专门处理 selector `8`；其他 selector 在恢复原始参数后 tail-call `0x1084508`。`0x1084508` 只接受 `4` 或 `5`。因此这两个函数合起来正好形成 `4/5/8` 三路。

**FACT（公开 OpenRM 610.43.03）：** 公共 BIF reset ABI 定义 `4 = BOOT_DEVICE_FUSE`、`5 = BOOT_DEVICE`、`8 = BASE`。

**强 INFERENCE（跨版本/私有实现命名）：** 固定 stripped GSP 中第 3 参数的 `4/5/8` 与公开 ABI 的三个同值 reset type 是同一套语义；因固定 ELF 没有类型符号，名称的套用仍保留版本边界。

## 范围与安全边界

- 固定文件：`/tmp/gsp_inner_19f040_a.elf`
- 文件大小：`82,577,496` bytes
- SHA-256：`bda917c95547644398eaf77fefe6c7f1b701c962db91f88bffaed6448a218a47`
- 格式：ELF64 little-endian RISC-V / RVC，stripped
- bounded code windows：`0x1084508..0x108473c`、`0x109300c..0x10931f8`
- 公共源码：`/usr/src/nvidia-610.43.03/src`

只做了本地文件读取、两个有限窗口的 Capstone 5.0.7 解码，以及用 radare2 的 RISC-V raw mapping 对关键分支做第二次解码核对。没有打开任何 `/dev/nvidia*`，没有运行 MODS，没有访问 GPU/MMIO，也没有做驱动、reset、固件或硬件写入。

证据等级：

- **FACT：** 固定 ELF 的指令/控制流直接证明，或公开 610 源码直接定义；
- **INFERENCE：** 多项事实吻合，但 stripped/private GSP 没有给出正式符号；
- **UNKNOWN：** 当前静态材料无法闭合。

## 1. 两个函数先取得同一 device-info entry

两个入口都先调用 `0x1b562f0`，参数相同：

```text
(pGpu, 0x2a, 3, -1, 0, &entry)
```

调用成功后，两处均以：

```text
lw priBase, 0x10(entry)
ld aperture, 0xb98(pGpu)
```

的等价序列取得随后使用的两个值。固定 ELF 的真实指令用 `pGpu+0x1000-0x468` 表示第二项，即 `pGpu+0xb98`。

公开 610 `DEVICE_INFO_ENTRY` 位于：

```text
/usr/src/nvidia-610.43.03/src/nvidia/generated/g_gpu_nvoc.h:778-792
```

其中 `+0x10` 正是 `devicePriBase`。公开 `gpuGetOneDeviceEntry_IMPL` 的六参数签名位于：

```text
/usr/src/nvidia-610.43.03/src/nvidia/src/kernel/gpu/gpu.c:7813-7855
```

**FACT（binary offset）：** 固定 ELF 后续地址运算的基值来自 `entry+0x10`。

**FACT（公开 610 layout）：** 公共结构把同一 offset 命名为 `devicePriBase`。

**版本边界：** 固定 GSP 的 private device-info table 并非由公开 host 结构的 ABI 保证；这里只把相同字段 offset、helper 形状和实际用途作为交叉校准，不声称两个版本的完整 entry layout 完全一致。

## 2. `0x1084508`：selector 4 与 5

函数入口把第 3 参数保存到 `s3`，helper 成功后依次判断：

```text
0x108454e  li   a5, 4
0x1084550  beq  s3, a5, 0x10845e6
0x1084554  li   a5, 5
0x1084556  bne  s3, a5, 0x10845e0
```

selector 不是 `4/5` 时，`0x10845e0` 置返回状态 `0x56`，不进入下面任何写入分支。

### selector 4

关键指令链：

```text
0x10845ee  lw      a5, 0x10(entry)       # priBase
0x10845f0  ld      a3, 0xb98(pGpu)       # aperture
0x10845f4  addiw   a4, a5, 0x308
0x10845f8  srliw   a4, a4, 2
0x10845fc  slli    a4, a4, 2
0x10845fe  add     a4, a4, a3
0x1084600  lw      a4, 0(a4)
0x1084602  addiw   a5, a5, 0x40
0x1084606  andi    a4, a4, 0x10
0x1084608  beqz    a4, 0x10846b0
0x108460a  srliw   a4, a5, 2
0x108460e  slli    a5, a4, 2
0x1084612  add     a3, a3, a5
0x1084614  lw      a5, 0(a3)
0x1084616  ori     a5, a5, 1
0x108461a  sw      a5, 0(a3)
```

`0x10846b0` 是 gate 未开放时的报告/assert/拒绝路径；若该路径继续返回，它把状态置为 `0x40`。它不会执行目标字段的 `OR 1`。

### selector 5

关键指令链：

```text
0x108455a  ld      entry, stack_slot
0x1084562  lw      a5, 0x10(entry)       # priBase
0x1084564  ld      a3, 0xb98(pGpu)       # aperture
0x1084568  addiw   a4, a5, 0x30c
0x108456c  srliw   a4, a4, 2
0x1084570  slli    a4, a4, 2
0x1084572  add     a4, a4, a3
0x1084574  lw      a4, 0(a4)
0x1084576  addiw   a5, a5, 0x44
0x108457a  andi    a4, a4, 0x10
0x108457c  beqz    a4, 0x108466e
0x108457e  srliw   a4, a5, 2
0x1084582  slli    a5, a4, 2
0x1084586  add     a3, a3, a5
0x1084588  lw      a5, 0(a3)
0x108458a  ori     a5, a5, 1
0x108458e  sw      a5, 0(a3)
```

`0x108466e` 同样是 gate 未开放时的报告/assert/拒绝路径；若该路径继续返回，状态为 `0x40`。

### 共享 readback

两路在写入后等待一个固定 `rdtime` 区间，然后共享 readback 尾声：

```text
readback = read32(aperture + aligned_target_offset)
status   = ((~readback) & 1) << 6
```

**FACT：** 目标 `bit0` 读回为 1 时返回 0；读回没有置位时返回 `0x40`。这不是盲写，函数会检查写入是否生效。

## 3. `0x109300c`：selector 8，并把其余值转交前一函数

该函数把第 3 参数保存到 `s2`，helper 成功后先判断：

```text
0x1093058  li   a5, 8
0x109305a  bne  s2, a5, 0x10930e6
```

selector `8` 的关键链为：

```text
0x1093066  lw      a5, 0x10(entry)       # priBase
0x1093068  ld      a3, 0xb98(pGpu)       # aperture
0x109306c  addiw   a4, a5, 0x310
0x1093070  srliw   a4, a4, 2
0x1093074  slli    a4, a4, 2
0x1093076  add     a4, a4, a3
0x1093078  lw      a4, 0(a4)
0x109307a  addiw   a5, a5, 0x48
0x109307e  andi    a4, a4, 0x10
0x1093080  beqz    a4, 0x1093116
0x1093082  srliw   a4, a5, 2
0x1093086  slli    a5, a4, 2
0x109308a  add     a3, a3, a5
0x109308c  lw      a5, 0(a3)
0x109308e  ori     a5, a5, 1
0x1093092  sw      a5, 0(a3)
```

gate 未开放时，`0x1093116` 进入报告/assert/拒绝路径；若该路径继续返回，状态为 `0x40`。写入后的 readback 也计算 `((~word) & 1) << 6`。

当 selector 不是 `8` 时，`0x10930e6..0x1093112` 恢复原始 `a0/a1/a2`，最后：

```text
0x109310e  auipc t1, 0xffff1
0x1093112  jr    0x3fa(t1)              # target = 0x1084508
```

**FACT：** 这是 tail-call，不是第三条独立 fallback 写入；所以 `4/5` 最终仍由上一节的函数处理。

## 4. gate 的精确含义边界

固定 ELF 可直接证明的是：

1. 每个目标字段都有一个固定配对 word；
2. 配对 word 的 `bit4` 必须为 1；
3. `bit4 == 0` 时进入报告/assert 路径；若该路径继续返回，状态为 `0x40`；
4. 只有通过 gate 后才对目标字段执行 `read -> OR 1 -> write -> delayed readback`。

因此把 `+0x308/+0x30c/+0x310 bit4` 描述成“写入 eligibility gate / permission-or-feature check”是行为层面的 **FACT**。

**INFERENCE：** 这三项很可能就是对应 coupling 字段的 PLM/可写能力元数据；它们以相同间距与 `+0x40/+0x44/+0x48` 一一配对，且失败表现为拒绝写入。

**UNKNOWN：** stripped GSP 没有发布该 bit 的正式寄存器字段名。本报告不把 `bit4` 进一步武断命名为某个确定的 PLM level、网络安全等级或凭据位，也不能从静态文件推断零售卡运行时该 bit 的值。

## 5. 公开 610 reset type 名称

公共定义位于：

```text
/usr/src/nvidia-610.43.03/src/common/sdk/nvidia/inc/ctrl/ctrl0080/ctrl0080bif.h:68-76
```

原定义的数值关系是：

```c
NV0080_CTRL_BIF_RESET_FLAGS_TYPE_BOOT_DEVICE_FUSE 0x4
NV0080_CTRL_BIF_RESET_FLAGS_TYPE_BOOT_DEVICE      0x5
NV0080_CTRL_BIF_RESET_FLAGS_TYPE_BASE             0x8
```

同一头文件 `:51-52` 还明确说明 Blackwell 及以后不支持 `_FUNDAMENTAL`，应使用 `BOOT_DEVICE_FUSE` 或 `BOOT_DEVICE`。

证据边界必须分开：

- **FACT（公开 610 ABI）：** 三个公共 reset type 的名称和值如上；
- **FACT（固定 GSP）：** selector `4/5/8` 分别选择三组 gate/target offset；
- **强 INFERENCE：** 两边的同值 selector、Blackwell reset 语境和逐级 coupling 行为表明，它们对应 fuse / boot / base 三类 coupling；
- **不是 FACT：** 公开头文件本身没有给出固定 stripped GSP 的函数地址，也没有公开这六个 internal offset 的硬件字段宏。

## 6. 最终 FACT / INFERENCE / UNKNOWN

### FACT

- `4 -> (+0x308.bit4 gate, +0x40.bit0 target)`；
- `5 -> (+0x30c.bit4 gate, +0x44.bit0 target)`；
- `8 -> (+0x310.bit4 gate, +0x48.bit0 target)`；
- 每路都是 gate、`OR bit0` 写入、延时、bit0 readback；
- `0x109300c` 的非 8 路 tail-call `0x1084508`；
- 公共 610 把 `4/5/8` 定义为 `BOOT_DEVICE_FUSE/BOOT_DEVICE/BASE`。

### INFERENCE

- 固定 GSP 三路就是公共 reset type 的 coupling setter 实现；
- `+0x308/+0x30c/+0x310 bit4` 是各自目标字段的 PLM/写资格元数据；
- `+0x40/+0x44/+0x48 bit0` 分别是 fuse/boot/base coupling 状态位。

### UNKNOWN

- 三个 gate 与 coupling bit 在目标 RTX 5090 当前的实际值；
- gate 的正式私有字段名、由哪个 boot stage/firmware 建立，以及零售安全策略是否允许改变；
- coupling 位跨 hot/boot/fuse/base reset 的保存、级联或清除规则；
- `BASE` coupling 是否会镜像或级联进其他 coupling 位；
- 仅凭这两个 setter，不能证明存在可安全调用的公开入口，更不能证明能在不 reset 的情况下改变状态。
