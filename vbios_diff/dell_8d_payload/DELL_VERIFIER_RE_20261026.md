# Dell RTX PRO 6000 更新器：Falcon secure-load / AES 错误路径静态复核

> **2026-10-27 更正：**本文早期把 `0xad4933` 一带误判为 DMOVERAES128/AES-CMAC。后续函数边界和 OpenSSL 实现对照确认它属于 `bsaes_xts_decrypt`。下文相关段落已改写；该地址不能作为 FSP CMAC/verifier 证据。参见 `CORRECTIONS.md` C-22。

日期：2026-10-26  
结论标签：**FACT / INFERENCE / UNKNOWN**；仅静态读取，不执行更新器、不访问 GPU/驱动、不写固件。

## 0. 范围与地址约定

目标 ELF：`RTXPRO6000_98.02.8D.00.01_FW_upgrade.bin`，stripped x86-64 `ET_EXEC`；`strings -a` 可见 `NVIDIA Firmware Update Utility` 与版本 `5.877.0`。SHA-256：

```text
6e1ccf97addee26c3c836cc4c87b4fdd0151cf78edb4df921b35338479e6ab61
```

`readelf -l -S` 显示：首个 LOAD 的 `VA=file_offset+0x400000`；RW LOAD 的 `VA=file_offset+0x600000`。下文反汇编地址为 ELF VA，文件偏移另行标明。目标 companion NVFW 的 SHA-256 为 `8658724061087279f59ca3a0d8ce443cb4ca52db2543c64723a3cea632a29b59`。

**核心限制：**本 ELF 中有 Falcon 错误消息、描述符分类/打印代码和 ioctl 状态解码；这些不能自动等同于实际执行 AES 校验的代码。以下把设备返回的错误、证书元数据打印、外层 SHA-384 记录及内部 secure-load 校验分开。

## 1. Falcon 错误消息表：完整恢复

### 表结构与引用

- 计数：VA `0x11ce9c0`（file `0xbce9c0`），值 `16`。
- 记录首地址：VA `0x11ce9e0`（file `0xbce9e0`），步长 `0x10`。
- `FUN_0044263a`（VA `0x44263a`）从 `DAT_011ce9e0` 起遍历，字段读取顺序为 `u32 code; u32 class; u64 string_VA`；循环上限为 `DAT_011ce9c0`。因此字符串指针槽在每条记录 `+8`，不能把它误当整张记录的起点。

| code | class | message |
|---:|---:|---|
| 0 | 0 | 空字符串 |
| 1 | 2 | A timeout occurred waiting for the PMU. Please restart and try again. |
| 2 | 2 | Falcon In HALT or STOP state, abort uCode command issuing process. |
| 3 | 2 | Falcon exception occurred during secure code execution. |
| **4** | **2** | **Falcon secure load failed, invalid AES signature.** |
| **5** | **2** | **Falcon secure load failed, invalid RSA3K signature.** |
| 6 | 2 | Invalid push-poll configuration. |
| 7 | 2 | Main firmware range does not match a protectable range. |
| 8 | 2 | You must close NVIDIA Control Panel before proceeding. |
| 9 | 2 | The program is already running. |
| 10 | 2 | This tool is for use with add-in graphics cards only. |
| 11 | 2 | The AC adapter must be plugged in before installing firmware. |
| 12 | 2 | The embedded firmwares are blank or empty. |
| 13 | 2 | Unable to acquire mutex for embedded driver loading. |
| 14 | 2 | Unable to open NVFLASH driver. |
| 15 | 0 | System is in legacy/CSM BIOS mode. Please switch to UEFI mode before updating your GPU firmware. |

AES 文本的 string VA 为 `0xc8dd78`（file `0x88dd78`），RSA3K 为 `0xc8ddb0`（file `0x88ddb0`）。**校正：**由于行首 8 字节是 code/class，AES 与 RSA3K 的 code 分别是 **4、5**，不是 5、6；后者是 push-poll 与 protectable-range 项。

### 可见的 ioctl 状态解码

`FUN_0052e93c`（VA `0x52e93c`）及相邻包装函数 `FUN_0052ea84` 对 `ioctl(fd, 0x2285, …)` 的返回缓冲区做分类，并可返回数值 `2/4/5`。在 `0x52e93c`：一个回复字节为 `0x44` 时，另一个回复字节低 4 位为 `4` 会返回 `4`；回复字节为 `0x24`（ASCII `'$'`）且另一个字节低 4 位为 `5` 会返回 `5`。这里仅描述字节比较，不给私有回复字段命名。这些数值与上表 AES/RSA3K 错误 code 一致。

**INFERENCE：**这与“主机把驱动/设备侧 secure-load 结果映射成错误消息”相符。**未闭合的证据：**目前没有直接调用边把这两个 ioctl 包装函数的返回值连到 `FUN_0044263a` 建立的消息 map；所以不能把“code 数值一致”提升为完整调用链证明。该 ioctl 包装函数本身没有显示 AES 运算或密钥处理。

## 2. V6 / `FSP_RUN` 对象与 `app=0x24,target=0x0f`

### 样本中的记录与对象

在 companion `.nvfw` 中，35-entry Falcon 表的 index 34（file `0xa0855`）原始 6 字节为：

```text
24 0f 04 51 0d 00
```

按表记录的字节布局，前两字节是 `app=0x24`、`target=0x0f`，后四字节是 `DescPtr=0x000d5104`。该样本的解析视图将其定位到 file `0x128104`（观察到的偏移增量为 `0x53000`）。该处描述符与 ELF 内置数据 file `0x10b5967` 起始的 **`0x36c50` 字节逐字节相同**；两者该范围 SHA-256 均为：

```text
c1c88db07805cb294e00a38829f47a14de07bf306c5b16047e6dfaf9df97f8dc
```

所以 ELF 确实含有与 Dell NVFW 样本相同的对象字节；但静态分析未发现对 VA `0x16b5967` 的直接代码引用，故“这份内置副本实际在何时、由谁消费”仍未证明。

描述符开头原始值：

```text
+0x00  0x0050060d     +0x04  0x00036c00
+0x08  0x00016800     +0x0c  0x00030c00
+0x10  0x00004000     +0x14  0x00006000
+0x18  0x00000301     +0x1c  0x01030000
+0x20  0x00000000     +0x24  0x00000000
+0x28  0x01012801
+0x2c  00 46 53 50 5f 52 55 4e   ( +0x2d..+0x33 = "FSP_RUN" )
+0x34..+0x73  64 bytes opaque material
```

- **FACT：**仅从字节可直接读出 `word0=0x0050060d`、`word1=0x36c00` 与 `FSP_RUN` 七个可打印字节；右侧未以 NUL 结束，`+0x34` 已是非文本数据。
- **交叉参考（不是本 ELF 的 v6 body 定义）：**项目本地 OpenRM 610.57.04 `gspkm/src/nvidia/src/kernel/gpu/gsp/kernel_gsp_fwsec.c:125-180` 将 bits 15:8 作为 version、bits 31:16 作为 size，bit 0 命名为 available、bit 2 命名为 encrypted；据此 raw word0 可拆成 version `6`、size `0x50`，bit 2 为 1。它同时把 bit 3 列为 reserved，而本样本低字节 `0x0d` 的 bit 3 也为 1；因此不把整个 flags byte 或 v6 body 解释成已公开格式。该源码仅定义旧 v2/v3 body，并只命名 app `0x05/0x45/0x85`，不定义这里的 v6 body，也没有给 app `0x24` / target `0x0f` 命名。
- **UNKNOWN：**`word1` 在 v6 schema 中的正式字段名和全部语义、`FSP_RUN` 的字段角色、+0x34 起 opaque bytes 的类型（签名/密钥/IV/tag 均未证实）、app/target 数值的正式含义。

### Dell ELF 的 classifier：v6 会走旧版 fallback

分类器在 VA `0x7dde66`（file `0x3dde66`），构造函数分别在 `0x7de9f6`、`0x7dec37` 调用它并把返回 enum 存入对象 `+0x40`。关键指令：

```asm
7dde66  mov rdx,[rdi+0x10]
7dde6a  mov eax,[rdx]
7dde6c  cmp eax,1
7dde75  cmp eax,2
7dde7e  movzx ecx,byte ptr [rdx+1]
7dde82  cmp cl,4          ; -> enum 6
7dde8b  cmp cl,3          ; -> enum 5
7dde94  test byte ptr [rdx],1
7dde99  cmp cl,2          ; -> enum 2
7ddea2  cmp eax,0x5746564e ; "NVFW" sentinel
7ddead  mov dword ptr [rdi+0x40],3 ; catch-all
```

把样本头 `0d 06 50 00` 代入：dword 不等于 1/2；version byte 为 6，不等于 4/3/2；首字节 bit 0 为 1；dword 也不等于 `NVFW`。因此落入 `0x7ddead`，返回 enum 3。代码没有在此处检查 v6 或 size `0x50`。

打印函数 `FUN_007df574`（VA `0x7df574`）把 enum 3 打印为 `FALCON_UCODE_DESCRIPTOR_GFW_STYLE_V1`；enum 6 才打印 `UCODE_DESCRIPTOR_GFW_STYLE_V4`，大于 6 才打印 unsupported。没有 V5/V6 样式分支。进一步，fallback 将 descriptor dword `+0x2c` 复制到标准化对象 `+0x78`（`0x7ddfcb`）；printer 把对象 `+0x78` 标成 `DMEM Size`。对当前字节，这会得到 `0x50534600`（`00 46 53 50`，即 NUL 加 `FSP` 的小端值），显示这是旧 GFW-V1 投影，不是对 v6 body 的合理字段解码。

**FACT（代码行为）：**该 classifier 不显式识别 v6；若传入本样本头，会回退并被打印成 GFW V1。  
**UNKNOWN（运行路径）：**ELF 中的对象副本没有直接代码 xref；因此不能仅凭静态字节断言该 classifier 实际收到并处理了这份 `FSP_RUN`。也不能排除另有不解析 body、只搬运 opaque object 的路径。

### `app/target` 的边界

`app=0x24,target=0x0f` 是 NVFW Falcon 表 entry 的数据；已识别的上述 descriptor classifier 只读描述符字节，不检查这两个表项字段，也没有为它们分支。未找到能把该 pair 语义化的 Dell ELF 代码。

两个容易误判的代码点：

1. `FUN_0052e93c` 中 `cmp ...,0x24` 比较的是 ioctl 回复字节 `'$'`，同时对另一回复 nibble 做 `& 0xf`，不是 `app=0x24,target=0x0f` 比较。
2. `FUN_00991ec0` 同时出现状态值 `0x24` 与输入 `0x0f`；该函数引用 `ssl/statem/statem_srvr.c`（VA `0xd60768`）并调用 OpenSSL 错误路径，是 TLS server 状态机，不是 Falcon table 处理。

**结论：**本样本证明 entry 34 的 pair 指向含 `FSP_RUN` 字节的 v6 对象；没有证明 `0x24` 或 `0x0f` 的私有命名、匹配规则或策略含义。

## 3. AES 校验：能说什么、不能说什么

### 可见到的 AES / 证书算法信息

`FUN_007e5084`（VA `0x7e5084`）输出 certificate/license 信息。它读取 `param_1+0x250` 指向的证书对象并打印算法枚举：

- 证书偏移 `+0x14` 的值 `1` 时显示 `Hash: DMOVERAES128`；
- `+0x16` 的值 `1/2` 时显示 alternate hash `DMOVERAES128` / `SHA256`；
- `+0x15` 的值 `1/2/3` 时显示 crypto `RSA1024` / `RSA3072` / `ECDSA256`；
- `+0x17` 的值 `1/2` 时显示 alternate crypto `AES128` / `3AES128`。

这是**证书元数据打印/枚举**，不是 AES 运算证据。该函数还打印证书类型、size、serial、issuer 等；`NVIDIA Corp.` 是该诊断分支输出的 issuer 文本，不能据此判定实际信任根或 AES key 来源。ELF 中也有通用 OpenSSL AES/CBC/GCM 实现，但未找到其与这条 Falcon 错误映射、这个 v6 对象或 ioctl 响应之间的代码引用链。

### 可独立复算的外层 SHA-384 覆盖（不要与 AES signature 混同）

Dell NVFW 在 file `0x1280a6` 有一条记录；相关字段为：

```text
raw_first = 0x9f
raw0      = 0x22       (字段地址 0x1280aa)
length    = 0x36c50
SHA-384   = 537a5bb53bdbb2b891f73e629284716b82d217cb2377ac2f00e1e8b704a52fcae8dd11f22649fc582aa2c1e4f71ac12f
```

由该记录布局得到 `start = 0x1280aa + 0x38 + 0x22 = 0x128104`，`end = 0x15ed54`；存储 digest 与 `SHA-384(nvfw[0x128104:0x15ed54])` 逐字节相等。长度 `0x36c50 = 0x50 + word1`，因此这条**外层 hash 记录**覆盖 descriptor 与紧随其后的 `word1` 长度区域。

这只证明 hash-table 条目的字节关系和覆盖范围。它**不证明**谁认证/信任该 hash table，也不证明此 SHA-384 就是错误消息所称的 Falcon “AES signature”。

### 用户所问三项的结论

| 问题 | 结论 |
|---|---|
| Falcon secure-load 的 AES 算法/模式 | **UNKNOWN**。错误表只写 invalid AES signature；证书诊断标签包括 `DMOVERAES128`、`AES128`/`3AES128`，但未建立它们与本次 v6 对象的 verifier 调用链。不能据此猜 ECB/CBC/GCM、Davies–Meyer、padding 或 IV。 |
| AES signature 的准确覆盖字节 | **UNKNOWN**。已知的 `[0x128104,0x15ed54)` 是 companion NVFW 中独立 SHA-384 条目的覆盖范围，不是已证明的 AES signature transcript。 |
| AES key 来源 | **UNKNOWN**。在检查到的 ioctl/status 与诊断代码中没有 key derivation/source；描述符 +0x34 起 bytes 也未被识别成 key。不能推断 fuse、硬编码 key 或证书公钥。 |

历史 V100 `FWSEC_LIC` 的 RSA/DMOVERAES128 结论属于另一代硬件及另一 verifier 路径；不能移植为 GB202 Dell `FSP_RUN` v6 的事实。

## 4. 常量命中与误判控制

- 原始字节 `0d 06 50 00` 在此 ELF 的文件偏移 `0xb55171` 与 `0x10b5967` 各出现一次。前者位于 `.gcc_except_table`，不是指令/代码引用；后者是 `.data` 中与 NVFW 完整对象相同的副本。故不能把 `0xb55171` 当成 classifier 的代码魔数引用。
- 可执行 classifier 比较的 NVFW 魔数是 `0x5746564e`（little-endian `NVFW`），不是 `0x0050060d`。
- 只因二进制中存在 AES 指令/库、AES 字符串、`0x24` 或 `0x0f`，不构成这条 secure-load verifier 的算法或 app/target 证据。

## 5. 证据与验证记录

本次本地检查包括：

- `readelf -h -l -S RTXPRO6000_98.02.8D.00.01_FW_upgrade.bin`：确认 ELF 类型及 PT_LOAD / section 映射。
- `sha256sum`：计算目标 ELF、companion NVFW；逐字节比较 ELF `.data` 内对象与 NVFW 对象的 `0x36c50` 字节。
- `objdump -d -M intel`：检查 VA `0x7dde66` classifier、`0x7df574` printer、`0x52e93c` ioctl wrapper、`0x991ec0` TLS false positive。
- Ghidra headless：检查 `FUN_0044263a`、`FUN_007df574`、`FUN_007e5084`、`FUN_0052e93c` 与相邻 wrapper 的伪代码/引用；对 VA `0x16b5967` 未见直接静态 xref。
- Python 离线解析：还原 16 条错误记录、NVFW table entry 34、SHA-384 record 与 object byte range；SHA-384 复算通过。
- 未运行 ELF/updater/nvflash；未访问 GPU、设备节点、PCI/BAR/MMIO 或已有 VM。

## 最终结论

**FACT：**Dell 更新器有 Falcon secure-load 的 AES/RSA3K 错误文本；其表码为 AES `4`、RSA3K `5`。Dell NVFW 的 Falcon index 34 entry 为 app `0x24` / target `0x0f`，对应 descriptor raw header `0x0050060d`，可见 `FSP_RUN`；该完整对象也嵌在 ELF `.data` 中。已识别 classifier 对 version `6` 不设专用分支，会将输入回退为 GFW V1；证书信息函数只打印 `DMOVERAES128`、AES/RSA enum。

**UNKNOWN：**是否有代码实际把这份 v6 对象送入该 classifier；secure-load AES verifier 的实际执行位置、算法/模式、被签名 transcript、key 来源；app `0x24` 与 target `0x0f` 的私有语义；外层 SHA-384 表的信任根。上述未知项不以历史 GPU 结果或通用 AES 库实现补猜。

---

## 追加(2026-10-26 深夜,父会话手工):AES 校验实现初步定位

### AES 原语位置(FACT)

- **S-box ×4**(T-table 实现)@ vaddr `0xac4c00-0xac4f00`
- **AES-128 块加密**(SSE,4 路)@ `~0xac3300`(入口 `0xac337d` 处 lea S-box)
- **AES-128 块解密 wrapper** @ `0xac38b0`(对齐栈、调用 `0xac35c0` 解密核心)
- 4 个解密调用点:`0xad3dab / 0xad507a / 0xad50e5 / 0xad5130`

### `0xad4933` 一带 = OpenSSL `bsaes_xts_decrypt`（更正）

早期分析看到 AES decrypt、逐块 XOR 和 GF(2^128) doubling，误把它解释为 CMAC K1/K2。完整函数边界和 OpenSSL BSAES/XTS 实现对照后，正确解释是：

- AES decrypt 处理数据块；
- XOR 的运行值是 XTS tweak；
- 每块后的 GF(2^128) doubling 是 XTS tweak 更新；
- 这些操作与 CMAC 子钥生成在局部指令形态上相似，但循环结构和调用约定属于 XTS sector decrypt。

因此：

- `0xad4933` **不是**已证明的 DMOVERAES128/FSP verifier；
- 它不能把用户态通用加密库与 `FSP_RUN` 校验、AES-CMAC 或 nvflash 错误码 4 建立数据流连接；
- `"Falcon secure load failed, invalid AES signature"` 仍只是用户态错误码字符串映射，最终验证逻辑位于设备侧或内核驱动侧；
- V100 时代 DMOVERAES128 结论不能迁移到本 GB202 路径。

### 架构判定（保留部分）

Dell 更新器 ELF 是完整 NVFLASH 用户态工具，包含 `/dev/nviH` 驱动接口、`NVFLASH_IO` 协议、uCode IMEM/DMEM 加载命令、Falcon descriptor 诊断文本和通用 OpenSSL 加密代码。

可保留的事实：

1. `"Falcon secure load failed, invalid AES signature"` 用户态路径只做错误码→字符串映射（错误表 RW `0x11ce9f0`）；
2. 诊断串完整列出 Falcon ucode descriptor 字段名，包括 prod/debug signatures、DMEM offset、IMEM/DMEM load ranges、dmapper version 和 feature masks；
3. `FALCON_UCODE_DESCRIPTOR_GFW_STYLE_V4` 存在于诊断字符串，但它与 v6 raw header `0x0050060d` 的精确关系仍未知；
4. 尚未定位 Dell 内核驱动或 GPU 侧把错误码 4 赋给该对象的 verifier。

### 下一步

- V4 descriptor 语义(对比 v6 word0)——classifier 里的 GFW_STYLE_V4
  解析逻辑可能就是 v6 的近似(实际 NVIDIA 内部把 v6 混入了 GFW 命名空间)
- ioctl 命令号→内核驱动的 Falcon 命令(需要驱动源码或 IDA 内核模块)
