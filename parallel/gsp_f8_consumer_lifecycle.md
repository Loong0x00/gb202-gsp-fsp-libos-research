# 610 GSP `0x108c494`：OBJBSP/NVDEC 绑定与生命周期复核

日期：2026-07-21

## 结论先行

这条线已经闭合到足以排除一个此前很有诱惑力、但对 5090 不成立的解释：

1. **FACT：** `0x0108c494` 是 OBJBSP（NVDEC）的
   “force NVDEC ucode encryption” HAL 实现。它检查 `0x8200f8.bit4` 和
   `low16(0x82013c)`；必要时写 `0x820040.bit0=1` 与 `0x82013c=1`，从不写
   `0x8200f8`。
2. **FACT：** 注册表键 `RMForceNvdecUcodeEncryption` 在 OBJBSP 初始化时缓存到
   对象 `+0x3b1`；OBJBSP state-load 在正常 NVDEC load 之前检查该 flag，再经对象
   `+0x338` 间接调用相应 HAL。
3. **最关键 FACT：GB202 不绑定 `0x0108c494`。** GB202 的 ChipHal index 是 65；
   610 GSP 的 OBJBSP constructor 在该路径把 `+0x338` 装成
   `0x019b4ea0`，后者只是 `return 0` 的空实现。固定构造路径上没有更晚的
   `+0x338` 覆盖。
4. **FACT：** 在公开 610 ChipHal index 集以及额外 `0..127` 枚举校验中，真正把
   `0x0108c494` 装入 `+0x338` 的已知有效芯片是 TU102（37）和 TU116（40），
   不是 GB202（65）。
5. **因此对 RTX 5090/GB202：** 即使人为令该 registry flag 为 1，state-load
   也只会调用 success stub；这条路径不会读 `f8`，也不会写 `+0x40/+0x13c`。
   它不是 GB202 L2 direct-shadow latch 的权限准备或解锁路径。

这同时回答“它是在授予权限，还是消费既有权限”：对真正绑定该实现的旧芯片，
它只**消费/检查已有的 `f8.bit4` 权限**，不降低或恢复 PLM；对 GB202，它连这一步
也不执行。

## 1. 范围、artifact 与安全边界

固定 GSP 输入：

```text
/tmp/gsp_inner_19f040_a.elf
size   82,577,496
sha256 bda917c95547644398eaf77fefe6c7f1b701c962db91f88bffaed6448a218a47
RX     VA 0x01000000..0x01e97000
```

语义交叉校准使用：

```text
mods_audit/static/extracted_inner/mods
sha256 c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf
```

本轮没有打开 `/dev/nvidia*`，没有访问 GPU、BAR/MMIO、PCI config、debugfs 或
实时驱动状态；没有执行 MODS、固件、未知二进制、reset、模块操作或提权。GSP
构造路径只对约 9 KiB constructor 窗口做 RISC-V 解码和确定输入的整数分支回放。

### 1.1 资源边界偏差

主体 GSP 路径回放只读 82.6 MB ELF，进程已正常退出。但在提取三条已知 MODS
rodata 字符串时，一次辅助 Python 命令误用了 `Path.read_bytes()`，短暂整体读入
392,339,552-byte MODS 文件。没有反汇编或执行它，进程随即退出，之后检查未见
Capstone/radare2/objdump 残留进程；后续均恢复为 bounded window。该操作不改变
字节证据，但不符合预期的低内存读取方式，故明确记录。

## 2. 对象身份与方法槽

### 2.1 OBJBSP / NVDEC 身份

GSP 静态 metadata descriptor `0x01c75ce8` 包含：

```text
object size = 0x508
class ID    = 0x8f99e1
create fn   = 0x019bcbf4
```

公开 610 生成头将 `0x8f99e1` 定义为 `OBJBSP`，并明确给出
`ENG_CLASS_NVDEC = classId(OBJBSP)`：

```text
/usr/src/nvidia-610.43.03/src/nvidia/generated/g_eng_desc_nvoc.h:534-539
/usr/src/nvidia-610.43.03/src/nvidia/generated/g_eng_desc_nvoc.h:1054-1056
```

同一 metadata/table 区 `0x01c72e28` 保存 `0x01096a4c`。constructor
`0x019bcbf4` 则为 OBJBSP 对象的 `+0x338` 安装芯片 HAL 函数指针。

### 2.2 registry flag 在对象初始化时缓存

`0x01096252..0x01096274`：

```text
0x01096252  a2 = &stack_u32
0x01096256  a1 = 0x01e25ea8  # "RMForceNvdecUcodeEncryption"
0x0109625e  a0 = pGpu
0x01096260  call registry getter
0x01096268  test status
0x0109626c  load stack_u32
0x01096270  snez
0x01096274  sb a5,0x3b1(pBsp)
```

**FACT：** getter 成功且值非零时，`pBsp+0x3b1=1`。对象创建前面已按
`0x508` 清零，所以键缺失/读取失败时 flag 保持 0；这不是一条默认自动执行路径。

相邻键也提供了阶段语义校准：

```text
0x01e25e80  "RmDisableBsp"
0x01e25e90  "RmDisableBspLoad"       -> pBsp+0x3b0
0x01e25ea8  "RMForceNvdecUcodeEncryption" -> pBsp+0x3b1
```

### 2.3 调用发生在 OBJBSP/NVDEC state-load 开头

`0x01096a4c` 的关键顺序：

```text
0x01096a62  load pBsp+0x198, then engine/state child
0x01096a74  lbu pBsp+0x3b1
0x01096a78  if zero: skip
0x01096a7a  ld  fn,pBsp+0x338
0x01096a7e  a1=pBsp
0x01096a80  a0=pGpu
0x01096a82  jalr fn
0x01096a84  lbu pBsp+0x3b0       # RmDisableBspLoad
...                              # normal NVDEC load continues
```

**FACT：** 这是 OBJBSP/NVDEC state-load 实现，而不是 constructor、task-2
sender 或 reset-only helper。它在 `RmDisableBspLoad` 判断和普通 NVDEC load
之前调用 `+0x338`。

**FACT：** `0x01096a82` 的返回值没有被检查；下一条指令直接读取 `+0x3b0`。
因此在真正绑定的旧芯片上，即便 helper 返回 `0xffff`，state-load 也不会仅因该
返回值失败；可见影响是日志和“未设置 latch”。x86 MODS twin
`0x06d83c9e..0x06d83cb3` 完全复现了相同行为。

公开 610 的通用框架确认 `gpuStateLoad` 会遍历 engine 并调用
`engstateStateLoad`：

```text
/usr/src/nvidia-610.43.03/src/nvidia/src/kernel/gpu/gpu.c:2765-2787
```

它在正常初始 load 使用，也在 power-management resume 路径重新使用：

```text
/usr/src/nvidia-610.43.03/src/nvidia/src/kernel/gpu/gpu_suspend.c:276-284
```

**UNKNOWN：** 当前没有找到一条把任意 Xid recovery、FLR 或用户触发 reset
直接连到该私有 OBJBSP 方法的固定 call edge。若某种恢复过程重新走完整 engine
state-load，它会按 state-load 规则再次到达；不能把这一条件关系扩写成
“每次 reset 必然调用”。

## 3. `0x0108c494` 的精确行为

### 3.1 指令级条件

函数从 `pGpu+0xb98` 取 PRI aperture base，再加 `0x820000`：

```text
0x0108c4ae  lw    a2,0xf8(base)
0x0108c4b2  lw    a3,0x13c(base)
0x0108c4b8  srliw a2,a2,4
0x0108c4bc  a3 &= 0xffff
0x0108c4be  a4 = (a3 != 0)
0x0108c4c2  a4 |= a2
0x0108c4c4  a4 &= 1
0x0108c4c6  if a4 == 0: fail
0x0108c4c8  if a3 != 0: success-without-write
0x0108c4ca  read +0x40
0x0108c4cc  set bit 0
0x0108c4d0  write +0x40
0x0108c4da  write 1 to +0x13c
```

令：

```text
P = bit4(read32(+0xf8))
E = (low16(read32(+0x13c)) != 0)
```

则真值表为：

| P | E | 结果 | 写入 | 返回 |
|---:|---:|---|---|---:|
| 0 | 0 | PLM 不允许且未设置 encryption | 无 | `0xffff` |
| 0 | 1 | 已设置 | 无 | `0` |
| 1 | 0 | 强制设置 | `+0x40.bit0=1`，`+0x13c=1` | `0` |
| 1 | 1 | 已设置 | 无 | `0` |

**FACT：** 成功判定精确为 `P || E`。只有 `P=1 && E=0` 才写寄存器。
函数不写 `+0xf8`，不保存旧 `+0x40/+0x13c`，不 restore，也不做写后 readback。

### 3.2 语义不是猜测：x86 twin 与日志

固定 MODS x86 函数 `0x06d84eb0..0x06d84fd4` 与上述 GSP 函数逐条件同构：

- 读 `0x8200f8`、`0x82013c`；
- 同一 `bit4 || low16-nonzero` 条件；
- 同一 `0x820040.bit0` RMW 和 `0x82013c=1`；
- 同一 `0/0xffff` 返回。

它引用的日志为：

```text
NVRM: Forcing UCODE encryption on NVDEC
NVRM: *** Cannot force Ucode encryption because of PLMs
NVRM: Encrption is already Set
```

GSP 与 MODS 还共享精确 registry 名 `RMForceNvdecUcodeEncryption`。因此
`0x0108c494` 的对象语义是 force NVDEC ucode encryption；`+0x13c` 在该函数中的
可证语义是“encryption 已设置/已锁存”的低 16-bit 状态。公开 GB202 RegHal 表对
`0x82013c` 没有 ordinary lookup row，所以本报告不发明更具体的官方字段名。

## 4. 最关键的 chip-HAL 绑定

### 4.1 GB202 index 与 constructor 输入

公开生成代码明确给出：

```text
GB202: arch 0x1b, impl 0x2 -> ChipHal index 65
```

来源：

```text
/usr/src/nvidia-610.43.03/src/nvidia/generated/g_chips2halspec_nvoc.c:129-133
```

`GpuHalspecOwner` 的 `ChipHal`、`TegraChipHal` 紧邻 metadata/base 指针：

```text
/usr/src/nvidia-610.43.03/src/nvidia/generated/g_gpu_halspec_nvoc.h:136-150
```

这与 constructor 中 `lhu 0x10(s2)` / `lhu 0x12(s2)` 的两个 HAL index 完全吻合；
这里第二项是 TegraChipHal，不是 RM variant。

### 4.2 GB202 最终安装 success stub

对 constructor `0x019bcbf4` 的 HAL dispatch，以：

```text
ChipHal index  = 65 (GB202)
TegraChipHal   = 0  (dGPU/default PCIe)
```

做确定分支回放，303 条 bounded 指令后唯一到达的 `+0x338` store 是：

```text
0x019be874  auipc a5,0xffff6
0x019be878  addi  a5,a5,0x62c     # a5 = 0x019b4ea0
0x019be87c  sd    a5,0x338(s1)
```

`0x019b4ea0`：

```text
0x019b4ea0  addi sp,-0x10
0x019b4ea2  save s0
0x019b4ea8  li   a0,0
0x019b4eac  ret
```

**FACT：** 这是无副作用的 success stub。

对整个约 9 KiB constructor 窗口枚举 `sd *,0x338(s1)`，只有：

```text
0x019bcfa2  0x019bd6fc  0x019bdd8c
0x019be11c  0x019be706  0x019be87c
```

GB202 路径只经过 `0x019be87c`；后续对象初始化路径没有第二次 `+0x338` store。

### 4.3 谁真正绑定 `0x0108c494`

在相同 bounded replay 中：

| ChipHal | 公开芯片 | `pBsp+0x338` 最终值 |
|---:|---|---:|
| 37 | TU102 | `0x0108c494` |
| 38 | TU104 | `0x019b4ea0` stub |
| 39 | TU106 | `0x019b4ea0` stub |
| 40 | TU116 | `0x0108c494` |
| 41 | TU117 | `0x019b4ea0` stub |
| 65 | GB202 | `0x019b4ea0` stub |

额外枚举 index `0..127`、TegraHal `0/1`，最终命中 `0x0108c494` 的只有
37 和 40。这个额外枚举只是 constructor dispatch 的一致性检查；有效芯片名称仍
以公开生成表为准。

## 5. 对 L2 direct-shadow / `f8` 权限时序的含义

### FACT

- `0x0108c494` 读取 `f8.bit4`，不写它；因此它没有 lowering、grant、restore
  或扩大 `f8` 权限的动作。
- 在 `E=0` 时，`f8.bit4` 必须在调用前已经允许该级别访问；该 helper 只是消费
  这一既有条件。
- 它确实会在旧芯片的 `P=1,E=0` 情况下置同一个 `0x820040.bit0` latch，但目的由
  代码和日志闭合为 NVDEC ucode encryption。
- GB202 的方法槽是 stub，所以 5090 state-load 经这条 registry 路径不会接触
  `0x8200f8/0x820040/0x82013c`。
- 它与 floorsweep task 2、PRC `0x1d`、L2 direct-shadow writer 或 reset-coupled
  selection 没有已发现的 call/data-flow edge。

### INFERENCE

在 TU102/TU116 上，若其他功能也共享 `0x820040.bit0`，NVDEC state-load 的设置可能
让后续共享 latch 的消费者观察到它已为 1；这是共享寄存器状态的自然副作用。
但这不等于它获得了 `f8` 写权限，更不证明它为 L2 floorsweep 准备了 permission。

### UNKNOWN

- `0x820040.bit0` 在各代芯片上除 NVDEC encryption 外的全部硬件扇出；
- 不可见 FSP/ROM 是否另外修改 GB202 的 `f8` 或同一 latch；
- 任意特定 reset/recovery 是否重新进入完整 OBJBSP state-load；
- GB202 上替代这条旧 Turing helper 的 NVDEC encryption 实现位于何处。

这些未知项不能推翻已闭合的 GB202 constructor binding：固定 610 GSP 的
`pBsp+0x338` 在 GB202 上就是 success stub。

## 6. 直接回答

**能不能把 `0x0108c494` 当成 5090 运行时开 L2 latch 的入口？不能。** 它是
旧 Turing OBJBSP/NVDEC 的加密 helper；GB202 根本不绑定它。

**`f8.bit4/+13c` 的成功失败到底是什么？** `f8.bit4=1` 或 `+13c` 低 16 位非零
即成功；两者都为零才返回 `0xffff`。只有前者为 1、后者为 0 时才置
`+0x40.bit0` 并写 `+0x13c=1`。

**它什么时候跑？** registry flag 在对象初始化时读取；真正的调用点位于每次
OBJBSP/NVDEC engine state-load 开头。普通初始 load 和 PM resume 会走 state-load；
任意 reset 是否重走该阶段需看具体恢复流程，当前没有 reset-only 绑定证据。

**它授予权限吗？** 不授予。旧芯片实现只检查并消费调用前已有的 `f8.bit4`；
GB202 则调用空 stub，完全没有寄存器效果。
