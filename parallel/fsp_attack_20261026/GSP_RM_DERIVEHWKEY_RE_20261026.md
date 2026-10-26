# `gsp_inner_19f040_a.elf` 中 deriveHwKey / AES-ECB 路径静态审计

日期：2026-10-26
范围：只读、静态分析。没有访问 GPU、BAR/MMIO、`/dev/nvidia*`，没有联网，也没有运行固件。目标 ELF SHA-256：`bda917c95547644398eaf77fefe6c7f1b701c962db91f88bffaed6448a218a47`（82,577,496 bytes）。

## 0. 结论摘要

- **没有恢复出可确认命名为 `deriveHwKey` 或 `DeriveSecDataKeyHelper` 的函数。** 目标 ELF 的 section headers 全为 `SHT_NULL`，无可用符号表；字符串搜索只找到若干错误名，没有这两个函数标识符。
- 找到的 `DERIVEHWKEY` / `DeriveSecDataKeyHelper` 字样是错误名。对这些名字的 PC-relative 引用落在错误上报块中：块里设置错误码/字符串指针，再尾调用公共报告函数；不能把这些引用当作 derivation 实现或调用点。
- **AES 硬件后端的 keyslot 写入/清零路径部分可还原。** 一个 helper 将 16 字节（4×u32）缓冲区写到逻辑 aperture 偏移 `0x101c, 0x1020, 0x1024, 0x1028`；空缓冲区路径把这四个位置写零。调用点的跟踪串明确包含 `before kslot clear` / `after kslot clear`。地址经运行期窗口映射后才执行 `sw`，因此这些是逻辑 aperture 偏移，**不是已确认的物理 BAR 地址或寄存器号**。
- **推导输入仍 UNKNOWN：**没有将该缓冲区追溯到 fuse、seed、密钥源或输入字段；未确定 fuse register offset/value、slot ID、AES-ECB 的完整数据/控制序列，也未证明此 AES 后端调用就是上述 UDE/UCODE 错误名对应的具体 helper。
- ELF 中有软件 SHA/AES 常量及五份 P-384 参数副本，但没有将 P-384 参数消费者归属到 HULK、FWSECLIC 或 deriveHwKey 的证据。

## 1. 地址映射与限制

`readelf -l` 验证第一 ELF 的两个 PT_LOAD：

| 段 | 文件范围 | VA 范围 | 权限 |
|---|---|---|---|
| LOAD1 | `0x000000–0xe97000` | `0x01000000–0x01e97000` | R-E |
| LOAD2 | `0xe97000–0x106c000` | `0x04000000–0x041d5000` | RW |

LOAD1 内：`VA = 0x01000000 + file_offset`。下文 VA 与文件偏移分开标注。目标文件总长约 82.6 MB；本文的代码交叉引用扫描限制在上述已声明 LOAD1/LOAD2，**不对 `0x106c000` 之后的附加文件内容作“没有实现”的结论**。

反汇编使用 Capstone RV64 + RVC；PC-relative 地址由 `auipc` 与后续同寄存器 `addi` 组合计算，并按 2-byte 指令边界前进。仅把有效指令序列作为 xref；裸字节命中不计为代码引用。

## 2. 错误名 xref：指向上报块，不是函数体

### 2.1 字符串与代码引用

| 错误字符串（文件偏移） | VA | PC-relative 引用点 VA | 块内错误码 |
|---|---:|---:|---:|
| `NV_UDE_ERR_DEVINIT_TABLE_AUTHENTICATE_DATA_DERIVEHWKEY_DOAESECB_NOT_IN_HSMODE` (`0xe27e48`) | `0x1e27e48` | `0x11be31c` | `0x40d` |
| `NV_UDE_ERR_DEVINIT_SCRIPT_AUTHENTICATE_DATA_DERIVEHWKEY_DOAESECB_NOT_IN_HSMODE` (`0xe28018`) | `0x1e28018` | `0x11be250` | `0x413` |
| `NV_UDE_ERR_DEVINIT_AUTHENTICATE_DATA_PATCHER_DERIVEHWKEY_DOAESECB_NOT_IN_HSMODE` (`0xe28300`) | `0x1e28300` | `0x11bcf94` | `0x420` |
| `NV_UDE_ERR_DEVINIT_RESIGN_DATA_PATCHER_DERIVEHWKEY_DOAESECB_NOT_IN_HSMODE` (`0xe28548`) | `0x1e28548` | `0x11bce84` | `0x428` |
| `NV_UCODE_ERR_VERIFY_SECURE_DATA_DERIVE_SEC_DATA_KEY_HELPER_AESECB_NOT_IN_HSMODE` (`0xe29d00`) | `0x1e29d00` | `0x11c0190` | `0x20e` |

例如 `0x11c0188–0x11c01a4`（文件偏移 `0x1c0188–0x1c01a4`）的结构为：

```asm
auipc a3, ...; addi a3, ...
auipc a2, ...; addi a2, ...   ; a2 -> NV_UCODE_ERR...AESECB_NOT_IN_HSMODE
addi  a1, zero, 0x20e         ; 错误码
c.li  a0, 3
addi  sp, sp, 0x10
auipc t1, ...; jalr zero, t1, ... ; 尾调用公共报告路径
```

四个 UDE 引用也位于同样的连续错误上报序列，分别装入错误码 `0x40d/0x413/0x420/0x428`。这说明字符串被错误处理路径使用；**不能由错误名推出函数边界、调用参数或 AES 输入**。另有一处位于 `VA 0x1734f58` 的引用落在 `RESIGN_DATA_PATCHER` 字符串内部偏移 `+0x20`，该处把字符串指针写入栈字段后跳转；其具体用途 UNKNOWN，亦未显示 fuse/key 数据流。

## 3. 可确认的 AES 硬件 keyslot 写入/清零片段

### 3.1 四字写入 helper

`VA 0x1bfd808`（文件偏移 `0xbfd808`）函数的关键指令：

```asm
c.lui  a5, 1
addi   s1, a5, 0x1c       ; 0x101c
addi   s0, a5, 0x2c       ; 0x102c，循环终点
...
if (buffer != NULL) lw a2, 0(buffer)
else                li a2, 0
mv     a1, s1           ; 当前逻辑 aperture offset
mv     a0, s4           ; 设备/引擎上下文
call   0x1bfd564
addi   s1, s1, 4
addi   buffer, buffer, 4
bne    s1, s0, loop
```

因此 helper 对 `0x101c, 0x1020, 0x1024, 0x1028` 连续执行 4 次 32-bit 写。若 `a1==NULL`，每次传入值为零。此处的 `c.lui a5,1` 是 `0x1000`，所以实际偏移是 `0x1000 + 0x1c…0x2c`，不是 `0x11c…`。

`VA 0x1bfd564` 按上下文中的范围/偏移字段校验并转换传入 offset，取运行期 aperture 基址后尾调用 `VA 0x1a94eec`。后者按全局映射窗口再转换地址，并最终执行 `sw a1, 0(a5)`。因此可确认的是**经过运行期映射的四个逻辑 aperture 写入**；静态文件不足以把它们还原成物理 BAR 地址/绝对 GPU 寄存器地址。

### 3.2 调用点与 keyslot 语义

- `VA 0x1bfa5e4` 函数的路径在检查上下文状态后，于 `VA 0x1bfa638` 调用 `0x1bfd808`。调用前设置 `a0 = *(s0+0)`、`a1 = s0+0x70`；helper 随后从该地址读取四个 u32 并写入上述四个偏移。这证明存在 **16-byte 缓冲区 → 四个 aperture word** 的加载路径。缓冲区内容的来源、用途和是否为最终 key 均 UNKNOWN。
- `VA 0x1bfa9b8` 包含 `before kslot clear`（引用点 `0x1bfa9d2`）和 `after kslot clear`（`0x1bfaa3c`）。在两串之间，代码以 `a1=0` 调用 `0x1bfd808`（调用点 `0x1bfaa20`），使其将四个 word 清零。这是将该四字窗口称作 keyslot 的最强证据；但**具体 slot 编号/硬件寄存器命名仍未知**。
- 同一 AES 后端中的跟踪串位于 `VA 0x1e24260` 等处；四组代码分别引用：

| 跟踪串 | 代码引用点 VA |
|---|---|
| `AES START` | `0x1bf1486`, `0x1bf5c1a`, `0x1bfa948`, `0x1bff688` |
| `before kslot clear` | `0x1bf1510`, `0x1bf5ca4`, `0x1bfa9d2`, `0x1bff712` |
| `after kslot clear` | `0x1bf157a`, `0x1bf5d0e`, `0x1bfaa3c`, `0x1bff77c` |
| `AES DONE` | `0x1bf162e`, `0x1bf5dc2`, `0x1bfaaf0`, `0x1bff830` |

另外有 `AES-GCM AAD START`、`AES GCM FINAL START`、`after AES GCM FINAL` 跟踪串。故该库至少包含 AES 通用硬件操作及 GCM 路径；**这些字符串不能证明 deriveHwKey 使用 GCM，也不能单独确定 ECB 模式寄存器/输入格式**。`AESECB_NOT_IN_HSMODE` 是错误名中的条件说明，不是成功执行 AES-ECB 的证据。

## 4. Crypto 常量表

### 4.1 SHA-256 / SHA-512

| 数据 | 文件偏移 | VA | 大小/识别依据 | 代码引用例 |
|---|---:|---:|---|---|
| SHA-256 K 副本 1 | `0xc402a8` | `0x1c402a8` | 64×u32，256 B；首字节与标准 K 表一致 | `0x10448d6`, `0x104c706`, `0x104cc58`, `0x104d400`, `0x1050338`, `0x10511f8` |
| SHA-256 K 副本 2 | `0xe07900` | `0x1e07900` | 与副本 1 字节相同 | `0x1a27384`, `0x1a28158` |
| SHA-512 K | `0xe07a00` | `0x1e07a00` | 80×u64，`0x280` B | `0x1a28448`, `0x1a329e2`（后者落在表内偏移） |

### 4.2 AES 软件表与消费者代码

- 32-bit 展开的 AES S-box：文件 `0xc40428` / VA `0x1c40428`，256 项；首项为 `63 00 00 00, 7c 00 00 00, 77 00 00 00, 7b 00 00 00`。
- 四张 AES T-table：文件 `0xc40828`, `0xc40c28`, `0xc41028`, `0xc41428`（各 256×u32）；按小端 u32 解释，其前缀与 AES 逆变换 Td 表家族匹配（四张表为旋转排列，表名/索引约定 UNKNOWN）。
- S-box 的代码引用在 `VA 0x1050330`、`0x10503ea`；附近函数入口候选为 `0x104ff78`、`0x1050600`（入口由栈帧序列界定，符号名未知）。T-table 引用集中在 `0x1050412–0x1050706` 以及 `0x1432acc–0x1433692`。这些是软件 AES 轮变换/查表代码的证据，但未单独证明某个函数就是 DeriveSecDataKeyHelper。

### 4.3 P-384 参数副本

在 LOAD1 数据中发现五份逐字节相同的 P-384 曲线参数组，P 值起点（文件偏移）为：

`0xe8aa40`, `0xe8af00`, `0xe8b3e8`, `0xe8b8d0`, `0xe8bdb8`。

每组连续 48-byte 大端字段为 `p, a, b, Gx, Gy, n`；例如第一组依次位于 `0xe8aa40/70/a0/d0/b00/b30`。`p`、`a=p−3`、`b`、生成点及阶数与 secp384r1/NIST P-384 参数一致。字符串 `NIST_P-384` 在文件 `0xe24198`（VA `0x1e24198`），五个记录里各有一个指向该字符串的 64-bit 指针。

代码扫描在周边 ECC/PKA 数据区找到约 115 个 PC-relative 目标，但精确扫描**没有**目标指向五个 P-384 `p` 起点或 `NIST_P-384` 名称；可见的直接引用落到相邻元数据及 P-256 参数区域（如 `0x1e8ac54`, `0x1e8ac84`）。因此“这些副本由某个 HULK/FWSECLIC 函数消费”未证实；具体记录消费者与用途 UNKNOWN。

## 5. UNKNOWN / 尚未闭合

1. `deriveHwKey` / `DeriveSecDataKeyHelper` 的真实函数边界、调用者、参数结构及其是否位于本 ELF 的声明 PT_LOAD 内，UNKNOWN。错误名引用是上报块，不是该函数的符号或实现。
2. 融合位/fuse offset、读取 fuse 的函数、派生 seed、key/IV/input bytes、数据方向/长度及输出落点均 UNKNOWN。当前可恢复的只是一个 16-byte buffer 写入 AES 后端四字窗口的局部路径；没有数据流证据把 buffer 接到 fuse。
3. AES-ECB 成功路径及其与 HS/HSMODE 的真实调用关系 UNKNOWN。错误名只说明有 `NOT_IN_HSMODE` 错误类别；通用后端另有 GCM trace，不能据此给 ECB 编造模式值。
4. 逻辑偏移 `0x101c–0x1028` 经运行期映射后的物理/BAR 地址、slot 编号及寄存器字段名称 UNKNOWN。
5. P-384 参数记录的直接消费者及其与 HULK/FWSECLIC 或 deriveHwKey 的关系 UNKNOWN。
6. 本文不覆盖首 ELF 声明 PT_LOAD 之外的附加文件数据；不能据此排除函数位于其它内嵌固件/镜像中。

## 6. 可复核命令与方法

```bash
sha256sum ghidra_static/gsp_inner_19f040_a.elf
readelf -h -l -S -s ghidra_static/gsp_inner_19f040_a.elf
strings -a ghidra_static/gsp_inner_19f040_a.elf | grep -Ei 'deriveHwKey|DeriveSecDataKeyHelper|DERIVEHWKEY|AESECB'
```

另用离线 Python 字节扫描与 Capstone RV64/RVC 解码完成字符串定位、`auipc+addi` xref、AES helper 调用目标和曲线参数重复性检查。原始 ELF 未修改。

---

## 追加(2026-10-26 深夜,父会话手工追踪):kslot 上游链与引擎掩码

### 调用链(全部 jalr 目标已符号修正后复核)

```
0x1bfa6aa  编排器(kslot load 的一级调用者,含 A/B 槽与 digest 校验)
  └─ 0x1bfa5e4  kslot 装载入口
       ├─ 0x1bf9814  引擎位掩码测试:mask=0x8815, bits 0,2,4,11 set
       │    ⇒ engine_id ∈ {1,3,5,12}(0x1/0x3/0x5/0xC)有 kslot 通道
       │    以及 type==0x1006(AES0)/0x1011(AES1)直通
       ├─ [s0+0x14]&0x100 且 [s0+0x1a]!=0 时:
       │    0x1bfd808(dev, key=s0+0x70)  ← 16B 密钥写入窗口
       │    └─ 0x1bfd568  窗口写原语(基址来自 [a0+0x18]+[a0+0x10] 归一化)
       │         └─ 0x1a94eec  终端写:aperture 表在 RW vaddr 0x41904d0
       │            (+0x180/+0x188/+0x198/+0x1a0),ELF 静态镜像中为 0(运行期填充)
       └─ 0x1bf97b0  密钥**读取**: 从 (a1 + (count-0x10) + base) 取 16B
            ⇒ +0x70 缓冲区是**双向窗口**:写入=kslot 编程,读取=回读
```

### 新事实

1. **kslot 通道只对引擎 1/3/5/12 和 AES0(0x1006)/AES1(0x1011)开放**——
   掩码 0x8815 的位形与 SEC2/GSP/PMU 等引擎编号的对应待定,但通道面
   是封闭枚举(不是任意引擎)。
2. **+0x70 不是 CPU 写入的静态缓冲**——AES 后端簇 0x8000 范围内零个
   对 +0x70 的 store;0x1bfad92 处有对 +0x70 的 **load** 并立即写
   `[a5+0xc]`(引擎命令口)。结论(INFERENCE,强):密钥经硬件窗口
   (0x1bfd568 原语)进入,+0x70 是 DMA/窗口映射地址,不是内存中的
   明文密钥。**密钥不流经 GSP-RM 可读内存。**
3. 0x1bf97b0 的读取路径 offset=(count-0x10)+base 提供密钥**回读**通道,
   但它同样走引擎窗口(不是直接内存),受 0x18 标志门控。

### 对主任务的含义

GSP-RM 侧确认:**kslot 密钥由硬件引擎窗口编程,明文密钥不经过固件内存**。
deriveHwKey 的实际派生发生在窗口另一侧(引擎硬件/FSP),与"NOT_IN_HSMODE"
错误语义吻合。GSP-RM 可观测面到此为止——需要引擎侧(HS/物理)才能继续。
