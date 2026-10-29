# 610.74 Windows GSP 对 `0x8200f8` 结论的离线交叉检查

日期：2026-07-21

> **版本/绑定边界补充：** 本报告证明 610.74 ELF 仍含相同 direct block，但未
> 重放该版本的 OBJBSP chip-HAL binding。后续对项目主样本 610.43.03 的确定
> constructor 重放证明 GB202/index 65 绑定 success stub，只有 TU102/TU116
> 绑定该 NVDEC helper。因此“函数跨版本存在”不能写成“GB202 会调用”。见
> `parallel/gsp_f8_consumer_lifecycle.md`。

## 结论

本地 610.74 Windows 驱动包提供了一份比当前 610.43.03 Linux 样本稍新的
`gsp_ga10x.bin`。对其内层 RISC-V GSP-RM ELF 做同范围静态复核后：

- **FACT：** 直接 `LUI 0x820` 锚点仍为 8 个；已知 `f8` block 原样保留，只是
  从 `0x0108c4ae` 平移到 `0x0108c586`。它仍是
  `lw a2,0xf8(a5)`，同块 store 只写 `+0x40` 与 `+0x13c`。
- **FACT：** 新样本仍没有完整 little-endian `u32 0x8200f8`，也没有旧 MODS
  RegHal setter ID `0x405c4000`。
- **FACT：** 两份包含裸 `0xf8` 的 77 项 offset table 逐项保留；它们不是这个
  版本新加入的 f8 writer 线索。
- **FACT（direct-base 限定）：** 其余 7 个 `LUI 0x820` 小窗口没有第二个
  `base+0xf8` load/store。
- **UNKNOWN：** 动态 PRI helper、packed descriptor、FSP/ROM 与 HULK payload
  仍不在这项交叉检查内。

因此，610.74 没有推翻此前 610.43.03 的有限负结论：**可见 GSP-RM 的直接
硬编码形式仍只有已知 f8 read，没有 f8 setter/lowering/restore。**

## 1. Artifact 来源与边界

本地 package：

```text
/home/user/Downloads/610.74-desktop-win10-win11-64bit-international-dch-whql.exe
size    979166856
sha256  1d8e5d34cb3aaf2376cf1e15242399f3c288e4ac2e2de38429f6d254185f5600
```

7-Zip 只读目录记录显示其中有：

```text
Display.Driver/gsp_ga10x.bin  size 84293784
```

提取到 `/tmp` 后的 outer hash：

```text
ba5667d90467581ce43f1e7320e7f59a000a5278779f8fc35952309adad514a2
```

与 610.43.03 一样，outer file offset `0x19f040` 是内层 ELF 起点；从该 offset
到 EOF 恰为完整 inner ELF：

```text
/tmp/gsp_inner_61074.elf
size    82593880
sha256  bff2477fea7c8c8fde194006009f060f8eb1761fe2a1951235530dd57950b2a8
```

`readelf` 识别其为 stripped RV64/RVC executable。其 RX PT_LOAD 为 file
`0x0..0xe99000`、VA `0x01000000..0x01e99000`；RW PT_LOAD 为 file
`0xe99000..0x106e000`、VA `0x04000000..0x041d5000`。相较 610.43.03，RX 与
RW 各增长 `0x2000`，所以不能用旧绝对 VA 假定新函数位置。

这里的“驱动包”仅表示本地文件名和 archive metadata；本轮记录 hash 与 PE
certificate-table 存在，但没有独立完成 Authenticode 链验证。未执行 package、
GSP 或任何未知程序。

## 2. direct `LUI 0x820` 完整锚点枚举

对新 ELF 的 RX PT_LOAD 每 2-byte RVC instruction boundary 做编码级
`LUI imm20=0x820` 枚举，得到恰好 8 项：

```text
0x0108c57e  rd=a1
0x013d1f54  rd=a0
0x013d8a90  rd=a5
0x01415520  rd=a0
0x0144139c  rd=a0
0x01449176  rd=a7
0x015312de  rd=a2
0x01849f7c  rd=a5
```

旧 610.43.03 的同类枚举同样为 8 项，但地址因版本布局不同而变化。每项只做
明确地址的小窗口反汇编；没有建立分析数据库或反汇编完整 PT_LOAD。

### 2.1 已知 f8 read 在新版本中原样存在

新 block `0x0108c56c..0x0108c5c0` 的相关指令是：

```text
0x0108c57e  lui  a1,0x820
0x0108c584  add  a5,a1
0x0108c586  lw   a2,0xf8(a5)
0x0108c58a  lw   a3,0x13c(a5)
...
0x0108c5a8  sw   a4,0x40(a5)
0x0108c5b2  sw   a4,0x13c(a5)
```

核心 byte sequence 与旧样本一致。方向没有变化：`f8` 是 load，不是 store。

### 2.2 其余锚点

其余小窗口仍分别表现为 constant arithmetic、primary fuse-base constant
getter、向输出结构保存 `0x820000`、或读取其他固定 offset；没有第二个
`+0xf8` load/store。这一结论只覆盖“由这 8 个直接 LUI 锚点在小窗口内形成”的
地址，不外推到跨函数动态 base。

## 3. literal、setter ID 与 table 交叉检查

- RX/RW 中完整 4-byte `0x8200f8` literal：0 命中。
- 旧 MODS 风格 `0x405c4000` f8 setter ID：0 命中。
- 610.43.03 报告中的 77 项表在新 ELF 中仍有两份，起点为：

```text
file 0x00d88088 -> VA 0x01d88088
file 0x00d881c0 -> VA 0x01d881c0
```

两表仍按相同顺序包含 `0x000,0x004,...,0x0ec,0x0f8,...,0x15c,0x100` 共
77 项。旧报告已经闭合其 consumer 为“三只动态 base + PCIe-style dword
offset”的 table flow；新版本逐项保留该形状，不能把其中裸 `0xf8` 单独解释成
`0x8200f8`。

## 4. 安全与资源

本轮只用 `7z` 解包到 `/tmp`、`readelf`、hash/byte search、一个读取 RX
PT_LOAD 的约 15 MiB bounded scanner，以及每次不足 0x210 bytes 的既有
`gsp_rv_window.py` 小窗口。解包/扫描前设置 256 MiB virtual-memory limit；没有
全段 Capstone、Ghidra、radare analysis database 或常驻分析进程。

没有访问 GPU、设备节点、BAR/MMIO、PCI config、驱动 runtime 或网络；没有
reset、写寄存器、加载模块或执行任何固件/安装包。
