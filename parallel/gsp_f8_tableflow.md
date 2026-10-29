# GB202 GSP `0x8200f8` table/data-flow 静态复核

日期：2026-07-21

> **后续绑定纠错：** 下文“direct access 只有 `0x0108c4ae`”是 ELF 编码
> inventory，不等于 GB202 会调用。后续 OBJBSP constructor 重放证明
> `0x0108c494` 只绑定 TU102/TU116；GB202/index 65 的 `+0x338` 是无副作用
> success stub。故该 block 的读写方向事实保留，但它不是 5090 runtime reader。
> 见 `parallel/gsp_f8_consumer_lifecycle.md`。

## 结论先行

本轮没有在固定 GSP ELF 中找到新的 `0x8200f8` writer、permission lowering 或
restore 点。更准确的表述不是“固件全局只读 `f8`”，而是：

- **FACT：** 已确认的直接访问仍只有 `0x0108c4ae: lw a2,0xf8(a5)`；同一块
  写 `+0x40` 和 `+0x13c`，不写 `+0xf8`。
- **FACT（限定编码域）：** RX/RW PT_LOAD 中没有完整地址
  `0x8200f8`，没有已知 MODS 风格 `f8` RegHal setter ID，也没有普通
  `AUIPC + signed-12-bit low part` 对该完整地址的形成点。
- **FACT：** 对齐的 `u32 0xf8` 候选中，唯一值得继续追的数据结构是两份完全
  相同的 77 项偏移表；两条消费者都把表项加到三个动态返回的 32-bit 基址上，
  没有在该表流中使用 `0x820000`。
- **强 INFERENCE：** 这两份表是 PCIe config-space DWORD offset list，而不是
  fuse/PLM descriptor。其开头、步长、上界、消费者形状以及公开 KernelBif 的
  config save/restore 代码相互吻合；stripped 私有对象到公开方法名的最后一跳
  没有完全闭合，因此这里保留 inference 标签。
- **UNKNOWN：** packed/变长 descriptor、通用 PRI helper 的动态基址、签名
  HULK payload、FSP/ROM 内部 consumer 或其他未取得固件仍可能访问或修改
  `f8`。本轮负结果不能排除这些路径。

所以，这次 table-flow 复核**加强了“当前可见 GSP host-side 代码未出现 `f8`
setter”这一有限负证据**，但没有把它升级成 whole-firmware absence proof。

## 1. 范围、artifact 与安全边界

固定输入：

```text
/tmp/gsp_inner_19f040_a.elf
size   82577496
sha256 bda917c95547644398eaf77fefe6c7f1b701c962db91f88bffaed6448a218a47
```

本轮只读取该文件和本地 610.43.03 开源 RM：

```text
RX PT_LOAD  file 0x000000..0xe97000  VA 0x01000000..0x01e97000
RW PT_LOAD  file 0xe97000..0x106c000 VA 0x04000000..0x041d5000
```

没有访问 GPU、`/dev/nvidia*`、BAR/MMIO、PCI config、debugfs 或实时驱动
状态；没有执行 MODS、固件、未知二进制、reset、模块或电源操作。小窗口反汇编
使用 `parallel/gsp_rv_window.py`；保留下来的表和 literal 结论来自 raw/mmap
字节检查和明确地址的小窗口。

### 1.1 资源约束事故（必须明确记录）

本轮**没有满足原定“所有分析过程小于 384 MiB”约束**：

1. 一次探索性的整段 Capstone 顺序解码意外峰值约 `1,054,192 KiB`；进程正常
   结束后即停用该做法。
2. 后来一次 mmap/raw AUIPC 校准循环意外报告峰值 `562,076 KiB`；该进程也已
   正常结束。

两次都没有访问 GPU，也没有留下 Python/Capstone 常驻进程；发现后已停止所有
新的整段扫描，只用既有结果和小窗口完成本报告。这是工具资源事故，不能写成
符合 `<384 MiB`。它不改变下面字节命中和指令方向本身，但应在复核本轮操作风险
时计入。

## 2. 正校准：扫描器能识别已知 read/store/setter

### 2.1 当前 GSP 的已知 `0x8200f8` 块

对 RX PT_LOAD 的 `LUI 0x820` 直接基址候选共有 8 个；逐点小窗口中，只有
`0x0108c494..0x0108c4e8` 使用 `+0xf8`：

```text
0x0108c4a6  lui  a1,0x820
0x0108c4ac  add  a5,a1
0x0108c4ae  lw   a2,0xf8(a5)      # read 0x8200f8-relative target
0x0108c4b2  lw   a3,0x13c(a5)
...
0x0108c4ca  lw   a4,0x40(a5)
0x0108c4cc  ori  a4,a4,1
0x0108c4d0  sw   a4,0x40(a5)      # write +0x40
...
0x0108c4da  sw   a4,0x13c(a5)     # write +0x13c
```

这同时正校准了三件事：`lw`/`sw` 方向、`0xf8` low offset，以及相同 base 上的
真实 store。**FACT：** 该块读取 `f8`，没有 lowering/restoring `f8`。

### 2.2 历史 PLM setter 校准

此前已经审计的 MODS x86 artifact 中，旧 GV100 函数 `0x1455240` 确实使用
RegHal setter ID `0x405c4000`，把旧路径的 `0x8200f8.[7:4]` 写成 `0xf`；其
类/vtable 边界和 secure-PMU caller 见 `parallel/task2_lifecycle_audit.md:345-371`。

本轮没有重新扫描 392 MiB 的 MODS ELF，只把该已闭合结果作为**跨 artifact
正校准**：传统明文 RegHal setter ID 是可以被 exact-ID 方法识别的。它不能证明
GB202 GSP 必须沿用相同 ID/编码，也不能把旧 GV100 setter 移植成 GB202 方案。

## 3. 完整地址、RegHal ID 与普通 PC-relative 形成

对两个 PT_LOAD 的 little-endian aligned/raw 字节检查均未命中下列完整 `u32`
地址；既然 4-byte 子串不存在，普通 zero-extended `u64` literal 也不存在：

```text
0x820040  0x8200d0  0x8200dc  0x8200e0
0x8200f4  0x8200f8  0x82013c
```

同样未命中这组本项目已知的 MODS 风格 RegHal ID：

```text
0x104f0000  0x404f0000  0x404f0001
0x405c4000  0x205c4000  0x105c4000
```

对 RX 中 2-byte instruction boundary 的 `AUIPC` 做编码级检查：若其结果距上述
任一完整地址在 signed 12-bit low part 范围内，则计为候选。七个地址的候选数
全部为 0。因此没有普通的：

```text
AUIPC rd, hi20
ADDI / LW / SW ..., lo12(rd)
```

直接 PC-relative absolute-address 形式。

这是**编码形式限定的 FACT**，不是任意算术或跨函数数据流证明。多步加减、动态
返回基址、packed ID 和 payload 都不在该负枚举内。

## 4. split `{0x820,0xf8}` descriptor 检查

对齐 `u32 0xf8` 的数量为：

```text
RX  33
RW  26
```

在每个候选前后 64 bytes 内检查 aligned `u16/u32/u64 0x820`，邻近命中为 0。
因此没有发现明文相邻的：

```text
{ base_hi = 0x820, offset = 0xf8 }
```

descriptor。

RX 只有一个 aligned `u32 0x820`（VA `0x01c1a224`）；其上下文是 RM control
method descriptor 记录，`0x820` 作为 method 参数大小出现，远离任何 `f8`
候选。RW 没有 aligned `u32 0x820`。

这项检查不覆盖 bit-packed、ULEB/varint、非对齐窄字段或 base/offset 分属不同表
的格式。

## 5. 对齐 `u32 0xf8` inventory

59 个候选的大部分能从局部结构排除为地址 offset：

- control-method parameter size，例如 RX `0x01c2abcc`；
- object/vtable metadata 的 size/field，例如 `0x01c6fd60`、`0x01c74160`；
- 元素都不超过 `0xff` 的 byte/enumerant table；
- crypto/high-entropy 常量块；
- RW 中 `f5,f6,f7,f8,f9,fa` 连续枚举数组；
- RTTI、hash 或普通记录字段。

唯一需要追消费者的结构是两份逐字节相同的 `u32` 数组：

```text
[0x01d8f5b8, 0x01d8f6ec)  77 entries
[0x01d8f758, 0x01d8f88c)  77 entries
```

内容为：

```text
000 004 008 00c 010 014 020 024 028 02c 030 034
040 044 048 04c 050 054 058 05c 060 064 068 06c
070 074 078 07c 080 084 088 08c 090 098 09c 0a0
0a4 0a8 0ac 0b0 0b4 0b8 0bc 0c0 0c4 0c8 0cc 0d0
0d4 0d8 0dc 0e0 0e4 0e8 0ec 0f8 0fc 108 110 120
128 12c 138 114 118 11c 124 130 140 144 148 14c
150 154 158 15c 100
```

`0xf8` 是 zero-based index 55，位于 `0x01d8f694` 和 `0x01d8f834`。

### 5.1 第一份表的消费者

普通 `AUIPC+ADDI` xref 为：

```text
0x0153f5a8 -> table start 0x01d8f5b8
0x0153f5b0 -> table end   0x01d8f6ec
```

`0x0153f55c` 开始的函数先调用 `a1+0x528` 的间接方法，让它返回三个 32-bit
base 到栈上。循环每次：

```text
0x0153f5b8  lw    a5,0(s7)       # table offset
0x0153f5bc  lw    a3,...         # base 0
0x0153f5c0  lw    s3,...         # base 1
0x0153f5c4  lw    a6,...         # base 2
0x0153f5ca  addw  a3,a3,a5
0x0153f5d2  addw  s3,s3,a5
0x0153f5d6  addw  s4,a6,a5
0x0153f5da  call  helper 0
0x0153f5f2  call  helper 1
0x0153f60a  call  helper 2
0x0153f618  s7 += 4; loop until 0x01d8f6ec
```

在这个闭合的 table loop 内，没有 `0x820000` getter、literal 或 addition。

### 5.2 第二份表的消费者

第二份表只由 sibling loop 直接形成地址：

```text
0x01542af0 -> table start 0x01d8f758
0x01542af8 -> table end   0x01d8f88c
```

函数 `0x01542aa4` 同样调用 `a1+0x528` 得到三个 base，在
`0x01542b00..0x01542b7c` 对每个 offset 形成三只 `base+offset` 并调用三只
helper。区别主要是 helper 参数形状；也没有在该 loop 中引入 `0x820000`。

### 5.3 为什么判断为 PCIe config offset list

以下是直接事实：

1. 所有项均 DWORD aligned，范围 `0x0..0x15c`。
2. 开头严格呈现标准 PCI config header 的 dword offsets：
   `0,4,8,c,10,14,...,28,2c,30,34`；随后覆盖 capability-space 风格 offsets。
3. 两个消费者都把同一 offset 加到三只动态 base，而不是加到已闭合的 primary
   fuse base `0x820000`。
4. 固定 ELF 有 class descriptor `(size=0x23b8,classId=0xdbe523,
   createfn=0x0199d810)`；公开 610 generated header 将 `0xdbe523` 定义为
   `KernelBif`。公开 KernelBif 明确包含 PCIe config save/restore、Fn1 和 XVE
   regmap 方法，见：
   - `generated/g_kernel_bif_nvoc.h:270-304`；
   - `kernel_bif_gh100.c:745-818,1362-1470`；
   - `kernel_bif_gb202.c:42-112`。

此外，`0x0153f55c` 的地址在 `0x01987a4a..0x01987a52` 被安装到私有对象
`+0x180`，其相邻区域连续安装一组同类方法。该行为与 NVOC per-chip HAL table
初始化一致。

综合起来，将数组解释为 PCIe config-space offset list 是**强 INFERENCE**。
不过本轮没有把 `0x01987...` initializer 的 stripped 私有 receiver 一路闭合到
上述 `KernelBif` class descriptor，公开 host 和私有 GSP 的字段 offset 也不能
直接等同，所以不把正式方法名写成 binary FACT。

即使完全不采用该语义标签，binary-only 能确定的仍是：`f8` 表项跟随另外 76 个
`0..0x15c` DWORD offsets，被加到三只动态 base；它不是相邻
`{0x820,0xf8}` descriptor，且该 loop 没有 `0x820000` 数据依赖。

## 6. setter / lowering / restore 判定

在本轮实际覆盖的形式中：

| 形式 | `f8` 结果 |
|---|---|
| direct `LUI 0x820 + low offset` | 只有已知 `lw` read |
| full `u32/u64 0x8200f8` literal | 0 |
| ordinary `AUIPC + signed lo12` | 0 |
| known MODS-style RegHal setter ID | 0 |
| adjacent split `{0x820,0xf8}` | 0 |
| aligned `u32 0xf8` table inventory | 两份 PCIe-style offset list；没有 fuse-base 结合 |
| visible inverse/restore pair | 未发现 |

因此可以写：

> 对固定 GSP ELF 的 direct-base、plain literal、普通 PC-relative、已知 RegHal ID、
> 邻接 split descriptor 和 aligned-u32 table 这几类 host-visible 形式，唯一确认的
> `0x8200f8` 访问是 read；没有发现 setter、lowering 或 restore。

不可以写：

> `0x8200f8` 在所有 GSP/FSP/硬件路径中绝对只读，或不存在任何解锁方式。

仍然未覆盖的主要空间：

- 通用 PRI helper 接收运行时地址；
- base 由另一方法或 firmware response 动态返回；
- packed/索引化 RegHal descriptor；
- HULK certificate 中携带 register override/RMW；
- 当前 ELF 不包含的 FSP/ROM consumer；
- reset/boot-time hardware state machine。

## 7. 对主线问题的实际意义

这条支线没有提供可写 `f8` 的代码，也没有给出安全的 permission sequence。
相反，它排除了一个容易误判的候选：数据段里的裸 `0xf8` 并不是自动指向
`0x8200f8`；至少最可疑的两份表有独立的 PCIe-style table flow。

当前最稳妥的总判断仍是：

- GSP 侧可见 `f8` read，说明该状态会被消费；
- host-visible GSP 中没有找到传统明文 setter；
- 若现代 GB202 存在 lowering，它更可能位于动态授权 payload、FSP/ROM 或不可见
  policy/consumer，而不是这两个 PT_LOAD 中一张简单的 `0x8200f8` 表。
