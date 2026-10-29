# GB202 5090 / RTX PRO 6000 标准 EFI 离线研究

## 结论

1. **两份 EFI 均严格 EfiDecompress 成功，TianoDecompress 均失败。** 解压输出从 offset 0 就是真实 MZ，e_lfanew=0xb0 指向 PE；AMD64 / PE32+ / EFI boot-service driver (subsystem 11)，entry RVA=0x308 位于可执行 `.text`。节区全部在文件边界内，pefile 无警告。不是从随机签名猜代码。
2. **定位到读取 `0x1fa3e0` 并解码容量的完整 62-byte 函数**；5090/PRO 对应字节完全相同。没有 32GB / 96GB SKU 专属容量常数；结果依赖已经存在的寄存器值。
3. 提取并用 Unicorn 纯软件仿真三类函数：容量解码、容量结果消费者（存在寄存器写入）、六分区容量求和。三段代码在两份 EFI 中均分别完全相同。总计 **312 个正常测试通过，6 个负控被拒绝**（父进程审查后补入48GiB消费者案例与边界负控）。
4. `0x1183a4`、`0x9a0200`、`0x9a0204` 在两份解压文件中均无完整 little-endian u32 常量，也未见对应指令立即数/位移。**不能据此排除运行时合成地址、间接调用、压缩/其他载荷。** 未找到这些目标的初始化写入路径。
5. 已找到的是 EFI 图形驱动内部的**现有容量读取及下游使用**，并非证明物理显存几何/训练初始化位置。容量消费者不是单纯向 GOP Mode 结构报告数字：它调用写寄存器抽象；但不能把这种下游寄存器设置误认作颗粒密度/行列/通道训练。

## 严格解压及 PE 验证

| 项目 | 5090 | PRO |
|---|---:|---:|
| EFI image ROM absolute | 0x47a00 | 0x45200 |
| EFI compressed header ROM absolute | 0x47f50 | 0x45750 |
| CompressedSize / OriginalSize | 96623 / 186568 | 96571 / 186536 |
| EFI image extent | 98304 | 98304 |
| `.text` RVA / raw | 0x280 | 0x280 |
| `.text` VirtualSize | 158643 | 158575 |
| PE entry RVA / raw | 0x308 | 0x308 |
| PE SizeOfImage | 184448 | 184416 |

`extraction.json` 包含原 ROM/解压 SHA256、所有 section 和 directory 及两个算法结果。标准压缩头 8 字节加 CompressedSize 严格切片，OriginalSize、EFI image offset、PCIR chain、机器类型和 executable entry 均断言验证。

注意：PE 尾部 2120 字节 security directory 是证书区域；**本次只验证结构，不验证 Authenticode 信任、签名有效性或刷写适用性**。无异常目录；空名称节实际无可验证的 runtime-function 表，未用 `.xdata` 名称臆造边界。

## 真实调用路径及函数提取

以下均为解压 PE RVA，恰好也等于 raw offset；不是 ROM absolute。结束地址 exclusive。

| 函数 | 5090 | PRO | 长度 | vtable slot |
|---|---|---|---:|---:|
| capacity | 0x20288–0x202c6 | 0x20244–0x20282 | 62 | +0xd8 |
| consumer | 0x1fe30–0x1ff06 | 0x1fdec–0x1fec2 | 214 | +0x38 |
| partition_sum | 0x201ac–0x20286 | 0x20168–0x20242 | 218 | +0xd0 |

### 不依赖偶然反汇编的证据

- 5090 vtable RVA `0x280b0`，PRO `0x28070`。
- 容量函数指针在 `0x28188` / `0x28148`，具有 IMAGE_REL_BASED_DIR64 relocation。
- 同一表的 `+0x38` 指向消费者，`+0xd0` 指向分区求和；消费者指针也验证了 DIR64 relocation。
- 构造器 `0x204cc` / `0x20488` 的 RIP-relative LEA 指向该表；`0x204f3` / `0x204af` 执行 `mov [rcx],rax` 安装 vtable。
- 消费者内 `0x1fe4a` / `0x1fe06` 调用自身对象 `[vtable+0xd8]`，因此有确定的内部容量调用关系。
- 三段函数均从这些入口做递归 CFG 解码，所有字节恰好覆盖，无重叠，无游离未知字节，正常 RET；`paths.json` 保存边和间接调用位置。
- 尚未建立从 PE entry 到这些对象的完整动态可达链；不宣称每个函数在本机启动时必然执行。

### capacity：输入及精确语义

Microsoft x64 ABI；RCX=`ctx`，`[ctx+8]`=`io`，`[io]`=`io_vtable`。唯一外部调用：

```c
uint32_t r = io->vtable[0x18 / 8](io, 0x1fa3e0);
uint32_t mb = (((r >> 4) & 0x00ffffff) << (r & 15)); // 32-bit 截断
if (r & 0x40000000) mb -= mb >> 4;
return (uint64_t)mb << 20;
```

读取调用在 5090 RVA `0x20298` / PRO `0x20254`。无目标寄存器写入，无其他表依赖，无 5090/PRO 分支。

本地 NVIDIA 公开 Blackwell GB100 `dev_fb.h` 证实 `NV_PFB_PRI_MMU_LOCAL_MEMORY_RANGE=0x001FA3E0`，LOWER_SCALE=3:0，LOWER_MAG=27:4。该头没有公开 bit30；旧 GP102 header/实现将 bit30 命名 ECC_MODE。本段 EFI **确实测试 bit30 并扣减 1/16**，但这里不独立断言 GB202 上该位的硬件命名。代码的 32-bit 中间溢出和舍入与公开 64-bit C 实现不完全等同，仿真保留了真实机器语义。

**仅为合成输入的示例，绝非硬件实测：** `r=0x80000` → 32GiB；`r=0x180000` → 96GiB；相应加 bit30 后分别 30GiB / 90GiB。

### consumer：读容量后确有下游写路径

依赖：自身 vtable +0xd8（上面的 capacity），`io` vtable +0x18 读、+0x20 写。寄存器抽象命名来自实参/返回值和读改写惯例；尚未追到真实底层 PCI/MMIO 映射实现。以下语义经过机器码仿真核对：

```c
uint64_t fb = max(capacity(ctx) - 0x100000, 0); // 饱和减去 1MiB
uint32_t old = read32(0x10fd40);
uint64_t low = (uint64_t)(old & 0x7fffff) << 16;
uint64_t high = ((uint64_t)(old & 0x7fffff) + 16) << 16;
if (!(low < fb && fb < high)) {
    old = read32(0x10fd40); // 实际代码再次读取
    write32(0x10fd40, (old & ~0x7fffff) | ((fb >> 16) & 0x7fffff));
}
write32(0x830000, (uint32_t)fb << 12);
write32(0x830004, (uint32_t)(fb >> 32));
return true; // AL=1
```

5090 写调用位置分别为 `0x1fec7`、`0x1feda`、`0x1feec`（PRO 各减 0x44）。**本次没有足够 GB202 公开定义给这三个地址命名**；不能挪用其他架构同数值寄存器名称。本函数不写 0x1fa3e0，不是已证实的容量来源。

### partition_sum：几何相关的读取候选，不能直接认定 GB202 物理分区布局

读取 `0x2243c` 的低 8 位作数量上限、`0x820c14` 作禁用位图，逐项读取 `0x90020c + i*0x4000`，最多六项，累加每项低 17 位，最后左移 20。原代码 do/while 在数量=0 时也处理 i=0，仿真覆盖此边界。

这是另一个容量样式 helper，不是 DIMM/颗粒几何配置写入。它与 Blackwell 容量 helper 同处 vtable，不意味着此六项循环就是 GB202 真实 24 通道组织，也未证明 GB202 启动会调用它。

## 未找到及防止混淆

- 目标 `0x1fa3e0` 全文件仅一次完整 u32 命中，恰在已证实 capacity 的 `mov edx,imm32` 内。
- `0x1183a4` 无命中；本地公开 GA102 header 将此地址定义为 secure scratch group 42，但不能跨架构自动套用。
- `0x9a0200/0x9a0204` 无命中。邻近区域确有独立 getter 读取 **0x9a0838**（5090 0x202d8 / PRO 0x20294），不应误写为目标地址。
- `*.disasm.txt` 是完整 executable-section 线性扫描，仅用于索引；数据/填充也可能可解码。**强结论仅使用经 vtable、relocation、构造器和递归 CFG 验证的片段**。
- 不排除 EFI 其他间接合成地址路径，不排除 legacy / devinit / Falcon / FSP 才是真正几何初始化来源。公开 GP102 源注释说 Devinit 计算 MEMORY_RANGE，GB100 源还提到 FSP boot 周围恢复该寄存器；这些是相关背景，非本 ROM 的已证实启动链。

## 复现

仅使用项目主目录已存在的 venv；不修改 venv。所有生成物限定本目录。

```sh
P=/home/user/rt_5090_project/vbios_diff/gb202_boot_upstream_20260911/.venv/bin/python
R=/home/user/rt_5090_project/vbios_diff/gb202_boot_upstream_20260911/efi_research
"$P" -B "$R/extract.py"
"$P" -B "$R/analyze.py"
"$P" -B "$R/emulate.py"
"$P" -B "$R/paths.py"
```

`emulate.py` 不加载/执行完整 PE，不运行 PE entry，不做原生目标执行。仅将已提取的小函数映入 Unicorn RX 内存；IO 调用全部指向合成 callback，寄存器由 Python 字典返回、写入只记录日志。对象和栈 RW，未映射地址及片段外执行地址拒绝；写 callback 只允许消费者的三个已验证地址，顶层退出要求经过函数末 RET 且栈平衡。这不是完整GOP控制流或逐字节未知内存模型。指令限额 2000。每份 EFI：134 个容量测试（含固定种子随机值与溢出边界）、18 个消费者测试（含48GiB、条件写入与跳过分支）、4 个求和测试。另有每份3个负控：缺失读响应、仅仿真内修改写地址为deadbeef、直接跳到sentinel而不RET；均拒绝，见 `negative_controls.json`。实际 ROM/PE 从未以原生程序执行，无硬件访问、无刷写。

`upstream_excerpts.txt` 保存只读本地公开源码的精确路径、文件 SHA256 及行号引用；未使用网络，版本/架构限制如上。
